defmodule Prizmo.TcgEngine.MechanicsTest do
  use Prizmo.DataCase, async: true

  alias Prizmo.Tcg.Decks.Alakazam27147
  alias Prizmo.Tcg.Decks.Dragapult27431
  alias Prizmo.Tcg.Decks.DragapultBlaziken28253
  alias Prizmo.Tcg.Decks.DragapultDusknoir28236
  alias Prizmo.Tcg.Decks.DragapultPlain28256
  alias Prizmo.Tcg.Decks.RocketMewtwo27459
  alias Prizmo.Tcg.Goal1.Decks.Dragapult28255
  alias Prizmo.Tcg.Goal1.Decks.DragapultBlaziken28258
  alias Prizmo.TcgEngine.AttackDamage
  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameSnapshot
  alias Prizmo.TcgEngine.GameView
  alias Prizmo.TcgEngine.Mechanics
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  describe "flow machine pregame" do
    test "coin toss winner chooses starting player and opening hands are dealt automatically" do
      {:ok, game} = create_game()

      assert game.flow_state == :pregame_awaiting_coin_toss
      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} = Mechanics.call_coin_toss(game, "player_1", :heads)
      assert game.flow_state == :pregame_awaiting_starting_player_choice
      assert game.coin_toss_calling_player_id == "player_1"
      assert game.coin_toss_call == :heads
      assert game.coin_toss_result in [:heads, :tails]
      assert game.coin_toss_winner_player_id in ["player_1", "player_2"]
      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} =
               Mechanics.choose_starting_player(
                 game,
                 game.coin_toss_winner_player_id,
                 "player_2"
               )

      assert game.status == :setup
      assert game.flow_state == :setup_choosing_opening_active
      assert game.first_player_id == "player_2"
      assert game.active_player_id == "player_2"
      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}

      assert event_types(game.id) == [
               "coin_toss_resolved",
               "starting_player_chosen",
               "opening_hands_drawn"
             ]

      assert snapshot_indexes(game.id) == [0, 1, 2, 3]
    end

    test "seeded games resolve coin toss from persisted RNG without publishing the seed" do
      {:ok, game_a} = create_seeded_game("coin-toss-seed")
      {:ok, game_b} = create_seeded_game("coin-toss-seed")

      assert {:ok, game_a} = Mechanics.call_coin_toss(game_a, "player_1", :heads)
      assert {:ok, game_b} = Mechanics.call_coin_toss(game_b, "player_1", :heads)

      assert game_a.coin_toss_result == game_b.coin_toss_result
      assert game_a.coin_toss_winner_player_id == game_b.coin_toss_winner_player_id

      event = event_by_type(game_a.id, "coin_toss_resolved")
      assert event.payload["call"] == "heads"
      assert event.payload["result"] == Atom.to_string(game_a.coin_toss_result)
      assert event.payload["rng_algorithm"] == "exsss"
      assert event.payload["rng_context"] == "coin_toss:player_1:heads"
      assert event.payload["rng_seed_source"] == "explicit"
      refute Map.has_key?(event.payload, "rng_seed")

      assert {:ok, view} = GameView.for_player(game_a.id, "player_1")
      refute Map.has_key?(view, :rng_seed)

      coin_toss_event_view = Enum.find(view.events, &(&1.type == "coin_toss_resolved"))
      refute Map.has_key?(coin_toss_event_view, :payload)
    end

    test "only the coin toss winner can choose who starts" do
      {:ok, game} = create_game()
      {:ok, game} = Mechanics.call_coin_toss(game, "player_1", :heads)

      loser_player_id =
        ["player_1", "player_2"]
        |> Enum.reject(&(&1 == game.coin_toss_winner_player_id))
        |> List.first()

      winner_player_id = game.coin_toss_winner_player_id

      assert {:error, {:not_coin_toss_winner, ^winner_player_id}} =
               Mechanics.choose_starting_player(game, loser_player_id, "player_1")

      assert counts_by_zone(game.id) == %{deck: 120}
      assert event_types(game.id) == ["coin_toss_resolved"]
    end

    test "setup ready choices automatically place prizes and open the first action window" do
      {:ok, game} = create_flow_action_window_game()

      assert game.status == :in_progress
      assert game.flow_state == :turn_action_window
      assert setup_status(game.id) == :completed
      assert counts_by_zone(game.id) == %{active: 2, deck: 93, hand: 13, prize: 12}

      assert %Turn{turn_number: 1, active_player_id: "player_1", status: :action_window} =
               current_turn(game.id)

      assert event_types(game.id) == [
               "coin_toss_resolved",
               "starting_player_chosen",
               "opening_hands_drawn",
               "setup_active_chosen",
               "setup_active_chosen",
               "setup_bench_choices_opened",
               "setup_player_ready",
               "setup_player_ready",
               "prizes_placed",
               "setup_completed",
               "turn_started",
               "turn_card_drawn",
               "action_window_opened"
             ]

      assert_setup_move_payload(event_by_type(game.id, "opening_hands_drawn").payload, "hand", 7)
      assert_setup_move_payload(event_by_type(game.id, "prizes_placed").payload, "prize", 6)

      assert %{"card" => drawn_card, "turn_id" => turn_id} =
               event_by_type(game.id, "turn_card_drawn").payload

      assert turn_id == current_turn(game.id).id
      assert drawn_card["owner_player_id"] == "player_1"
      assert drawn_card["from_zone"] == "deck"
      assert drawn_card["to_zone"] == "hand"
      assert drawn_card["to_position"] == 7
    end

    test "pass ends the current turn and automatically opens the opponent action window" do
      {:ok, game} = create_flow_action_window_game()

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      assert game.status == :in_progress
      assert game.flow_state == :turn_action_window
      assert game.active_player_id == "player_2"
      assert counts_by_zone(game.id) == %{active: 2, deck: 92, hand: 14, prize: 12}

      assert [turn_1, turn_2] = turns(game.id)
      assert %Turn{turn_number: 1, active_player_id: "player_1", status: :ended} = turn_1
      assert %Turn{turn_number: 2, active_player_id: "player_2", status: :action_window} = turn_2

      assert game.id |> event_types() |> Enum.slice(-5, 5) == [
               "turn_passed",
               "turn_ended",
               "turn_started",
               "turn_card_drawn",
               "action_window_opened"
             ]
    end

    test "declaring an attack automatically resolves, finishes, and opens the opponent action window" do
      {:ok, game} = create_flow_action_window_game(player_1_active_card_id: "JTG-120")

      attacker = active_card(game.id, "player_1")
      energy = deck_card(game.id, "player_1", "MEE-005")

      {:ok, energy} = ash_update(energy, :draw_to_hand, %{position: 99})
      {:ok, game} = Mechanics.attach_energy(game, "player_1", energy.id, attacker.id)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :trading_places)

      assert game.status == :in_progress
      assert game.flow_state == :turn_action_window
      assert game.active_player_id == "player_2"
      assert counts_by_zone(game.id) == %{active: 2, attached: 1, deck: 90, hand: 15, prize: 12}

      assert [turn_1, turn_2] = turns(game.id)
      assert %Turn{turn_number: 1, active_player_id: "player_1", status: :ended} = turn_1
      assert %Turn{turn_number: 2, active_player_id: "player_2", status: :action_window} = turn_2

      assert game.id |> event_types() |> Enum.slice(-7, 7) == [
               "declare_attack",
               "resolve_declared_attack",
               "finish_attack",
               "turn_ended",
               "turn_started",
               "turn_card_drawn",
               "action_window_opened"
             ]
    end
  end

  describe "setup flow" do
    test "opening hands can only be drawn once and rejected attempts are not saved" do
      {:ok, game} = create_started_setup_game()

      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} = Mechanics.draw_opening_hand(game)
      assert game.cursor_index == 2
      assert game.latest_event_index == 2
      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
      assert event_types(game.id) == ["start_setup", "draw_opening_hand"]
      assert snapshot_indexes(game.id) == [0, 1, 2]

      assert {:error, _reason} = Mechanics.draw_opening_hand(game)

      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
      assert event_types(game.id) == ["start_setup", "draw_opening_hand"]
      assert snapshot_indexes(game.id) == [0, 1, 2]
    end

    test "undo and redo restore granular snapshots" do
      {:ok, game} = create_started_setup_game()
      {:ok, game} = Mechanics.draw_opening_hand(game)

      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}

      assert {:ok, game} = Mechanics.undo(game)
      assert game.cursor_index == 1
      assert setup_status(game.id) == :waiting_to_draw
      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} = Mechanics.redo(game)
      assert game.cursor_index == 2
      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
    end
  end

  describe "generic play_card/4" do
    test "Ultra Ball-style card resolves with upfront choices and domain fact events" do
      {:ok, game} = create_action_window_game()

      %{ultra_ball: ultra_ball, cost_cards: cost_cards, target: target} =
        stage_ultra_ball_cards(game.id)

      assert {:ok, game} =
               Mechanics.play_card(game, "player_1", ultra_ball.id, %{
                 choices: %{
                   discard_two_from_hand: Enum.map(cost_cards, & &1.id),
                   search_deck_for_pokemon: [target.id]
                 }
               })

      assert game.cursor_index == 11
      assert zone(ultra_ball.id) == :discard
      assert Enum.map(cost_cards, &zone(&1.id)) == [:discard, :discard]
      assert zone(target.id) == :hand

      assert event_types(game.id) == [
               "start_setup",
               "card_play_started",
               "cost_payment_started",
               "cards_moved",
               "cost_paid",
               "cards_moved",
               "effect_started",
               "cards_moved",
               "deck_shuffled",
               "effect_completed",
               "card_play_completed"
             ]
    end

    test "Ultra Ball-style card can suspend for cost and effect prompts" do
      {:ok, game} = create_action_window_game()

      %{ultra_ball: ultra_ball, cost_cards: cost_cards, target: target} =
        stage_ultra_ball_cards(game.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", ultra_ball.id, %{})
      assert zone(ultra_ball.id) == :hand

      assert [%PendingEffect{status: :awaiting_prompt} = pending_effect] =
               pending_effects(game.id)

      assert [%Prompt{} = cost_prompt] = prompts(game.id)
      assert cost_prompt.payload["choice_key"] == "discard_two_from_hand"

      assert {:error, {:pending_effect_awaiting_prompt, _id}} =
               Mechanics.play_card(game, "player_1", ultra_ball.id, %{})

      assert {:ok, game} =
               Mechanics.choose_prompt(
                 game,
                 "player_1",
                 cost_prompt.id,
                 Enum.map(cost_cards, & &1.id)
               )

      assert zone(ultra_ball.id) == :discard
      assert Enum.map(cost_cards, &zone(&1.id)) == [:discard, :discard]

      assert [%PendingEffect{status: :awaiting_prompt, id: pending_effect_id}] =
               pending_effects(game.id)

      assert pending_effect_id == pending_effect.id
      assert [_resolved_cost_prompt, %Prompt{} = search_prompt] = prompts(game.id)
      assert search_prompt.payload["choice_key"] == "search_deck_for_pokemon"

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", search_prompt.id, [target.id])

      assert zone(target.id) == :hand
      assert [%PendingEffect{status: :completed}] = pending_effects(game.id)

      assert event_types(game.id) == [
               "start_setup",
               "card_play_started",
               "cost_payment_started",
               "pending_effect_created",
               "prompt_created",
               "prompt_resolved",
               "cards_moved",
               "cost_paid",
               "cards_moved",
               "effect_started",
               "pending_effect_created",
               "prompt_created",
               "prompt_resolved",
               "cards_moved",
               "deck_shuffled",
               "effect_completed",
               "card_play_completed"
             ]
    end

    test "first player cannot play ordinary Supporters on turn 1, but Team Rocket's Proton remains legal" do
      {:ok, game} = create_action_window_game_with_decks(RocketMewtwo27459, Alakazam27147)

      lillie = draw_deck_card_to_hand(game.id, "player_1", "MEG-119", 1)
      proton = draw_deck_card_to_hand(game.id, "player_1", "DRI-177", 2)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      refute lillie.id in play_card.source_card_instance_ids
      assert proton.id in play_card.source_card_instance_ids

      assert {:error, :first_player_cannot_play_supporter_on_first_turn} =
               Mechanics.play_card(game, "player_1", lillie.id, %{})
    end

    test "Team Rocket's Proton searches up to 3 Basic Team Rocket Pokémon on the Ash path" do
      {:ok, game} = create_action_window_game_with_decks(RocketMewtwo27459, Alakazam27147)

      proton = draw_deck_card_to_hand(game.id, "player_1", "DRI-177", 1)
      [target_1, target_2] = game.id |> deck_cards("player_1", "DRI-019") |> Enum.take(2)
      target_3 = deck_card(game.id, "player_1", "DRI-051")

      assert {:ok, game} =
               Mechanics.play_card(game, "player_1", proton.id, %{
                 choices: %{
                   search_deck_for_basic_team_rocket_pokemon: [
                     target_1.id,
                     target_2.id,
                     target_3.id
                   ]
                 }
               })

      assert zone(proton.id) == :discard
      assert Enum.map([target_1, target_2, target_3], &zone(&1.id)) == [:hand, :hand, :hand]

      assert event_types(game.id) == [
               "start_setup",
               "card_play_started",
               "cards_moved",
               "effect_started",
               "cards_moved",
               "deck_shuffled",
               "effect_completed",
               "card_play_completed"
             ]

      cards_moved_events =
        GameEvent
        |> Ash.Query.filter(game_id == ^game.id and type == "cards_moved")
        |> Ash.Query.sort(index: :asc)
        |> Ash.read!()

      proton_effect_event = Enum.at(cards_moved_events, 1)

      assert proton_effect_event.payload["effect_key"] ==
               "search_deck_for_basic_team_rocket_pokemon"

      assert proton_effect_event.payload["public_reveal"] == true
      assert length(proton_effect_event.payload["cards"]) == 3
    end

    test "SFA-064 Xerosic's Machinations resolves opponent_discards_to_hand_size effect" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, DragapultPlain28256)

      sfa = move_owned_card_to_hand(game.id, "player_2", "SFA-064", 1)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      opponent_hand_before = card_count_in_zone(game.id, "player_1", :hand)
      assert opponent_hand_before > 3

      assert {:ok, game} = Mechanics.play_card(game, "player_2", sfa.id, %{})

      [prompt] = prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "opponent_discards_to_hand_size"
      assert prompt.payload["min"] == opponent_hand_before - 3
      assert prompt.payload["max"] == opponent_hand_before - 3

      assert {:ok, game} =
               Mechanics.choose_prompt(
                 game,
                 "player_1",
                 prompt.id,
                 Enum.take(prompt.payload["legal_choices"], opponent_hand_before - 3)
               )

      assert card_count_in_zone(game.id, "player_1", :hand) == 3

      effect_cards_moved =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "opponent_discards_to_hand_size"))

      assert effect_cards_moved.payload["affected_player_id"] == "player_1"
      assert length(effect_cards_moved.payload["cards"]) == opponent_hand_before - 3
      assert Enum.all?(effect_cards_moved.payload["cards"], &(&1["from_zone"] == "hand"))
      assert Enum.all?(effect_cards_moved.payload["cards"], &(&1["to_zone"] == "discard"))
    end

    test "POR-084 Rosa's Encouragement resolves attach_basic_energy_from_discard_to_stage2_if_more_prizes effect" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, DragapultPlain28256)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      reduce_opponent_prize_count_to(game.id, "player_1", 3)

      stage2 = owned_card(game.id, "player_2", "TWM-130")
      assert stage2, "Expected player_2 to have a TWM-130 card for POR-084 setup"

      stage2 = move_owned_card_to_hand(game.id, "player_2", "TWM-130", 1)

      stage2 =
        case stage2.zone do
          :hand ->
            {:ok, stage2} = ash_update(stage2, :play_to_bench, %{position: 1})
            stage2

          _ ->
            stage2
        end

      energy = move_owned_card_to_hand(game.id, "player_2", "MEE-005", 2)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_2", energy.id)

      rosa = move_owned_card_to_hand(game.id, "player_2", "POR-084", 3)
      assert {:ok, game} = Mechanics.play_card(game, "player_2", rosa.id, %{})

      [prompt] = prompts(game.id)
      assert prompt.player_id == "player_2"

      assert prompt.payload["choice_key"] ==
               "attach_basic_energy_from_discard_to_stage2_if_more_prizes"

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [energy.id, stage2.id])

      attached_energy =
        CardInstance
        |> Ash.Query.filter(game_id == ^game.id and id == ^energy.id)
        |> Ash.read_one!()

      assert attached_energy.zone == :attached
      assert attached_energy.attached_to_card_instance_id == stage2.id

      effect_cards_moved =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "attach_basic_energy_from_discard_to_stage2_if_more_prizes")
        )

      assert effect_cards_moved.payload["affected_player_id"] == "player_2"
      assert Enum.any?(effect_cards_moved.payload["cards"], &(&1["from_zone"] == "discard"))
      assert Enum.any?(effect_cards_moved.payload["cards"], &(&1["to_zone"] == "attached"))
    end

    test "CRI-082 Special Red Card resolves opponent_hand_to_bottom_then_draw effect" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, DragapultPlain28256)

      cri = move_owned_card_to_hand(game.id, "player_2", "CRI-082", 1)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      reduce_opponent_prize_count_to(game.id, "player_1", 3)

      opponent_hand_before = card_count_in_zone(game.id, "player_1", :hand)
      assert opponent_hand_before > 0

      assert {:ok, game} = Mechanics.play_card(game, "player_2", cri.id, %{})

      assert card_count_in_zone(game.id, "player_1", :hand) == 3

      special_events =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.filter(&(&1.payload["effect_key"] == "opponent_hand_to_bottom_then_draw_if_any"))

      assert length(special_events) == 2

      [to_deck_event, to_hand_event] =
        Enum.sort_by(special_events, fn event ->
          if event.payload["destination"] in ["deck_bottom", :deck_bottom], do: 0, else: 1
        end)

      assert to_deck_event.payload["affected_player_id"] == "player_1"
      assert length(to_deck_event.payload["cards"]) == opponent_hand_before
      assert to_hand_event.payload["affected_player_id"] == "player_1"
      assert length(to_hand_event.payload["cards"]) == 3
    end
  end

  describe "Goal 1 Dragapult variant validation" do
    test "Fairy Zone makes opposing Darkness Pokémon weak to Psychic" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Dragapult28255, DragapultBlaziken28258,
          player_1_active_card_id: "MEG-088",
          player_2_active_card_id: "JTG-056"
        )

      attacker = active_card(game.id, "player_2")
      defender = active_card(game.id, "player_1")
      assert {:ok, attack} = CardCatalog.fetch_attack(attacker.card_id, :full_moon_rondo)

      assert {:ok, 40} = AttackDamage.damage_for(attacker, defender, attack)
    end

    test "Ground Melter gains bonus damage and discards the active Stadium" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(DragapultBlaziken28253, Alakazam27147,
          player_1_active_card_id: "TWM-039",
          player_2_active_card_id: "MEG-054"
        )

      stadium = move_owned_card_to_hand(game.id, "player_1", "SCR-131", 1)
      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", stadium.id)

      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")
      assert {:ok, attack} = CardCatalog.fetch_attack(attacker.card_id, :ground_melter)

      assert {:ok, 120} = AttackDamage.damage_for(attacker, defender, attack)

      assert {:ok, effect_payload} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 attack,
                 %{}
               )

      assert effect_payload.effect_type == "bonus_damage_if_stadium_in_play_then_discard_stadium"
      assert effect_payload.stadium_discarded?
      assert effect_payload.discarded_stadium_card_instance_ids == [stadium.id]
      assert zone(stadium.id) == :discard
    end

    test "Come and Get You prompts over discarded Duskull and benches the chosen card" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(DragapultDusknoir28236, Alakazam27147,
          player_1_active_card_id: "PRE-035",
          player_2_active_card_id: "ASC-142"
        )

      discarded_duskull =
        game.id
        |> other_owned_card("player_1", "PRE-035", [active_card(game.id, "player_1").id])
        |> move_card_to_hand(1)

      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", discarded_duskull.id)

      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")
      assert {:ok, attack} = CardCatalog.fetch_attack(attacker.card_id, :come_and_get_you)

      assert {:ok, effect_payload} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 attack,
                 %{}
               )

      assert effect_payload.effect_type == "put_up_to_3_duskull_from_discard_to_bench"
      assert effect_payload.duskull_prompt_created?

      [prompt] = awaiting_prompts(game.id)
      assert prompt.payload["choice_key"] == "put_duskull_from_discard_to_bench"
      assert prompt.payload["legal_choices"] == [discarded_duskull.id]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, [discarded_duskull.id])

      benched_duskull = card(discarded_duskull.id)
      assert benched_duskull.zone == :bench

      completed_event =
        game.id
        |> game_events_by_type("attack_effect_completed")
        |> List.last()

      assert completed_event.payload["effect_key"] == "put_up_to_3_duskull_from_discard_to_bench"
      assert completed_event.payload["selected_card_instance_ids"] == [discarded_duskull.id]
    end

    test "Cursed Blast drives knockout prize and replacement flow, and Damp blocks it" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(DragapultDusknoir28236, Alakazam27147,
          player_1_active_card_id: "PRE-035",
          player_2_active_card_id: "MEG-054"
        )

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      assert {:ok, game} = Mechanics.pass_turn(game, "player_2")

      player_1_bench = play_owned_basic_to_bench(game.id, "player_1", "TWM-128", 1)
      _player_1_other_bench = play_owned_basic_to_bench(game.id, "player_1", "ASC-016", 2)
      player_2_bench = play_owned_basic_to_bench(game.id, "player_2", "JTG-120", 1)
      _player_2_other_bench = play_owned_basic_to_bench(game.id, "player_2", "SSP-087", 2)

      duskull = active_card(game.id, "player_1")
      dusclops = move_owned_card_to_hand(game.id, "player_1", "PRE-036", 1)
      assert {:ok, game} = Mechanics.evolve_from_hand(game, "player_1", dusclops.id, duskull.id)

      source = active_card(game.id, "player_1")
      target = active_card(game.id, "player_2")

      assert {:ok, game} = Mechanics.use_cursed_blast(game, "player_1", source.id, target.id)
      assert zone(source.id) == :discard
      assert zone(target.id) == :discard

      [player_1_prize_prompt] = awaiting_prompts(game.id)
      assert player_1_prize_prompt.player_id == "player_1"
      assert player_1_prize_prompt.payload["choice_key"] == "knockout_prize_cards"
      assert player_1_prize_prompt.payload["queued_knockout_prize_selection_count"] == 1
      assert player_1_prize_prompt.payload["knocked_out_card_instance_ids"] == [target.id]

      player_1_prize = List.first(player_1_prize_prompt.payload["legal_choices"])

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", player_1_prize_prompt.id, [
                 player_1_prize
               ])

      [player_2_prize_prompt] = awaiting_prompts(game.id)
      assert player_2_prize_prompt.player_id == "player_2"
      assert player_2_prize_prompt.payload["choice_key"] == "knockout_prize_cards"
      assert player_2_prize_prompt.payload["knocked_out_card_instance_ids"] == [source.id]

      player_2_prize = List.first(player_2_prize_prompt.payload["legal_choices"])

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", player_2_prize_prompt.id, [
                 player_2_prize
               ])

      refute active_card_or_nil(game.id, "player_1")
      refute active_card_or_nil(game.id, "player_2")

      assert {:ok, game} =
               Mechanics.choose_replacement_active(game, "player_2", player_2_bench.id)

      assert {:ok, game} =
               Mechanics.choose_replacement_active(game, "player_1", player_1_bench.id)

      assert active_card(game.id, "player_1").id == player_1_bench.id
      assert active_card(game.id, "player_2").id == player_2_bench.id

      prize_events = game_events_by_type(game.id, "take_knockout_prizes")
      assert Enum.map(prize_events, & &1.player_id) == ["player_1", "player_2"]
      assert Enum.all?(prize_events, &(&1.payload["prize_count"] == 1))

      assert Enum.all?(prize_events, fn event ->
               length(event.payload["taken_prize_card_instance_ids"] || []) == 1
             end)

      {:ok, damp_game} =
        create_flow_action_window_game_with_decks(DragapultDusknoir28236, Alakazam27147,
          player_1_active_card_id: "PRE-035",
          player_2_active_card_id: "MEG-054"
        )

      assert {:ok, damp_game} = Mechanics.pass_turn(damp_game, "player_1")
      assert {:ok, damp_game} = Mechanics.pass_turn(damp_game, "player_2")

      _damp = play_owned_basic_to_bench(damp_game.id, "player_2", "ASC-039", 1)

      damp_duskull = active_card(damp_game.id, "player_1")
      damp_dusclops = move_owned_card_to_hand(damp_game.id, "player_1", "PRE-036", 1)

      assert {:ok, damp_game} =
               Mechanics.evolve_from_hand(
                 damp_game,
                 "player_1",
                 damp_dusclops.id,
                 damp_duskull.id
               )

      damp_source = active_card(damp_game.id, "player_1")
      damp_target = active_card(damp_game.id, "player_2")

      assert {:error, :self_knock_out_abilities_blocked_by_damp} =
               Mechanics.use_cursed_blast(damp_game, "player_1", damp_source.id, damp_target.id)

      assert zone(damp_source.id) == :active
      assert zone(damp_target.id) == :active
      assert game_events_by_type(damp_game.id, "ability_used") == []
    end

    test "Jamming Tower suppresses Lillie's Pearl prize reduction" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(DragapultBlaziken28258, Dragapult28255,
          player_1_active_card_id: "JTG-056",
          player_2_active_card_id: "MEG-088"
        )

      pearl = move_owned_card_to_hand(game.id, "player_1", "JTG-151", 1)
      clefairy = active_card(game.id, "player_1")
      assert {:ok, game} = Mechanics.attach_tool(game, "player_1", pearl.id, clefairy.id)
      assert ToolEffects.knockout_prize_reduction(game.id, clefairy) == 1

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      jamming_tower = move_owned_card_to_hand(game.id, "player_2", "TWM-153", 1)
      assert {:ok, game} = Mechanics.play_stadium(game, "player_2", jamming_tower.id)

      assert zone(jamming_tower.id) == :stadium
      assert ToolEffects.knockout_prize_reduction(game.id, clefairy) == 0
    end
  end

  defp create_game do
    Mechanics.create_game([
      {"player_1", Alakazam27147},
      {"player_2", Dragapult27431}
    ])
  end

  defp create_game_with_decks(player_1_deck, player_2_deck) do
    Mechanics.create_game([
      {"player_1", player_1_deck},
      {"player_2", player_2_deck}
    ])
  end

  defp create_seeded_game(seed) do
    Mechanics.create_game(
      [
        {"player_1", Alakazam27147},
        {"player_2", Dragapult27431}
      ],
      rng_seed: seed,
      rng_seed_source: "explicit"
    )
  end

  defp create_flow_action_window_game(opts \\ []) do
    with {:ok, game} <- create_game(),
         {:ok, game} <- Mechanics.call_coin_toss(game, "player_1", :heads),
         {:ok, game} <-
           Mechanics.choose_starting_player(game, game.coin_toss_winner_player_id, "player_1"),
         player_1_active = setup_active_card(game.id, "player_1", opts[:player_1_active_card_id]),
         player_2_active = hand_basic_card(game.id, "player_2"),
         {:ok, game} <- Mechanics.choose_active_from_hand(game, "player_1", player_1_active.id),
         {:ok, game} <- Mechanics.choose_active_from_hand(game, "player_2", player_2_active.id),
         {:ok, game} <- Mechanics.finish_setup_choices(game, "player_1") do
      Mechanics.finish_setup_choices(game, "player_2")
    end
  end

  defp create_flow_action_window_game_with_decks(player_1_deck, player_2_deck, opts \\ []) do
    with {:ok, game} <- create_game_with_decks(player_1_deck, player_2_deck),
         {:ok, game} <- Mechanics.call_coin_toss(game, "player_1", :heads),
         {:ok, game} <-
           Mechanics.choose_starting_player(game, game.coin_toss_winner_player_id, "player_1"),
         player_1_active = setup_active_card(game.id, "player_1", opts[:player_1_active_card_id]),
         player_2_active = setup_active_card(game.id, "player_2", opts[:player_2_active_card_id]),
         {:ok, game} <- Mechanics.choose_active_from_hand(game, "player_1", player_1_active.id),
         {:ok, game} <- Mechanics.choose_active_from_hand(game, "player_2", player_2_active.id),
         {:ok, game} <- Mechanics.finish_setup_choices(game, "player_1") do
      Mechanics.finish_setup_choices(game, "player_2")
    end
  end

  defp play_owned_basic_to_bench(game_id, player_id, card_id, position) do
    card = move_owned_card_to_hand(game_id, player_id, card_id, position + 20)
    turn_number = current_turn(game_id).turn_number

    {:ok, card} =
      ash_update(card, :play_to_bench, %{position: position, turn_entered_play: turn_number})

    card
  end

  defp create_started_setup_game do
    with {:ok, game} <-
           Mechanics.create_game([
             {"player_1", Alakazam27147},
             {"player_2", Dragapult27431}
           ]) do
      Mechanics.start_setup(game)
    end
  end

  defp create_action_window_game do
    create_action_window_game_with_decks(Dragapult27431, Alakazam27147)
  end

  defp create_action_window_game_with_decks(player_1_deck, player_2_deck) do
    with {:ok, game} <-
           Mechanics.create_game([
             {"player_1", player_1_deck},
             {"player_2", player_2_deck}
           ]),
         {:ok, game} <- Mechanics.start_setup(game),
         {:ok, game} <- ash_update(game, :complete_setup, %{}),
         {:ok, turn} <-
           ash_create(Turn, :create, %{
             game_id: game.id,
             turn_number: 1,
             active_player_id: "player_1"
           }),
         {:ok, turn} <- ash_update(turn, :draw_for_turn, %{}),
         {:ok, _turn} <- ash_update(turn, :open_action_window, %{}) do
      {:ok, game}
    end
  end

  defp stage_ultra_ball_cards(game_id) do
    ultra_ball = deck_card(game_id, "player_1", "MEG-131")
    target = deck_card(game_id, "player_1", "TWM-128")

    [cost_card_1, cost_card_2 | _rest] =
      deck_cards_except(game_id, "player_1", [ultra_ball.id, target.id])

    {:ok, ultra_ball} = ash_update(ultra_ball, :draw_to_hand, %{position: 1})
    {:ok, cost_card_1} = ash_update(cost_card_1, :draw_to_hand, %{position: 2})
    {:ok, cost_card_2} = ash_update(cost_card_2, :draw_to_hand, %{position: 3})

    %{ultra_ball: ultra_ball, cost_cards: [cost_card_1, cost_card_2], target: target}
  end

  defp draw_deck_card_to_hand(game_id, player_id, card_id, position) do
    card = deck_card(game_id, player_id, card_id)
    move_card_to_hand(card, position)
  end

  defp move_card_to_hand(%CardInstance{zone: :deck} = card, position) do
    {:ok, card} = ash_update(card, :draw_to_hand, %{position: position})
    card
  end

  defp move_card_to_hand(%CardInstance{zone: :prize} = card, position) do
    {:ok, card} = ash_update(card, :take_prize, %{position: position})
    card
  end

  defp move_card_to_hand(%CardInstance{zone: :discard} = card, position) do
    {:ok, card} = ash_update(card, :recover_to_hand, %{position: position})
    card
  end

  defp move_card_to_hand(%CardInstance{} = card, _position), do: card

  defp move_owned_card_to_hand(game_id, player_id, card_id, position) do
    game_id
    |> owned_card(player_id, card_id)
    |> case do
      %CardInstance{zone: :deck} = card ->
        {:ok, card} = ash_update(card, :draw_to_hand, %{position: position})
        card

      %CardInstance{zone: :prize} = card ->
        {:ok, card} = ash_update(card, :take_prize, %{position: position})
        card

      %CardInstance{zone: :discard} = card ->
        {:ok, card} = ash_update(card, :recover_to_hand, %{position: position})
        card

      %CardInstance{} = card ->
        card

      nil ->
        flunk("Expected to find #{card_id} for #{player_id}")
    end
  end

  defp owned_card(game_id, player_id, card_id) do
    CardInstance
    |> Ash.Query.filter(
      game_id == ^game_id and owner_player_id == ^player_id and card_id == ^card_id
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> List.first()
  end

  defp other_owned_card(game_id, player_id, card_id, excluded_ids) do
    CardInstance
    |> Ash.Query.filter(
      game_id == ^game_id and owner_player_id == ^player_id and card_id == ^card_id
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> Enum.reject(&(&1.id in excluded_ids))
    |> List.first()
  end

  defp deck_card(game_id, player_id, card_id) do
    game_id
    |> deck_cards(player_id, card_id)
    |> List.first()
  end

  defp deck_cards(game_id, player_id, card_id) do
    CardInstance
    |> Ash.Query.filter(
      game_id == ^game_id and owner_player_id == ^player_id and card_id == ^card_id and
        zone == :deck
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
  end

  defp deck_cards_except(game_id, player_id, excluded_ids) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :deck)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> Enum.reject(&(&1.id in excluded_ids))
  end

  defp cards_in_zone(game_id, player_id, zone) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == ^zone)
    |> Ash.Query.sort(position: :asc, instance_id: :asc)
    |> Ash.read!()
  end

  defp card_count_in_zone(game_id, player_id, zone) do
    game_id
    |> cards_in_zone(player_id, zone)
    |> length()
  end

  defp reduce_opponent_prize_count_to(game_id, player_id, target_count) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :prize)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> Enum.sort_by(& &1.position)
    |> then(fn cards_in_prize ->
      over = length(cards_in_prize) - target_count

      cards_in_prize
      |> Enum.take(max(over, 0))
      |> Enum.with_index(card_count_in_zone(game_id, player_id, :hand) + 1)
      |> Enum.each(fn {prize_card, position} ->
        ash_update(prize_card, :take_prize, %{position: position})
      end)
    end)
  end

  defp game_events_by_type(game_id, type) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game_id and type == ^type)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
  end

  defp hand_basic_card(game_id, player_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :hand)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> Enum.find(&CardCatalog.basic_pokemon?(&1.card_id))
  end

  defp setup_active_card(game_id, player_id, nil), do: hand_basic_card(game_id, player_id)

  defp setup_active_card(game_id, player_id, card_id) do
    move_owned_card_to_hand(game_id, player_id, card_id, 99)
  end

  defp active_card(game_id, player_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :active)
    |> Ash.read_one!()
  end

  defp active_card_or_nil(game_id, player_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :active)
    |> Ash.read_one!()
  end

  defp card(card_id) do
    CardInstance
    |> Ash.Query.filter(id == ^card_id)
    |> Ash.read_one!()
  end

  defp current_turn(game_id) do
    Turn
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(turn_number: :desc)
    |> Ash.read!()
    |> List.first()
  end

  defp turns(game_id) do
    Turn
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(turn_number: :asc)
    |> Ash.read!()
  end

  defp zone(card_id) do
    CardInstance
    |> Ash.Query.filter(id == ^card_id)
    |> Ash.read_one!()
    |> Map.fetch!(:zone)
  end

  defp pending_effects(game_id) do
    PendingEffect
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read!()
  end

  defp prompts(game_id) do
    Prompt
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read!()
  end

  defp awaiting_prompts(game_id) do
    Prompt
    |> Ash.Query.filter(game_id == ^game_id and status == :awaiting_choice)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read!()
  end

  defp ash_create(resource, action, attrs) do
    resource
    |> Ash.Changeset.for_create(action, attrs)
    |> Ash.create()
  end

  defp ash_update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update()
  end

  defp counts_by_zone(game_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read!()
    |> Enum.frequencies_by(& &1.zone)
  end

  defp setup_status(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one!()
    |> Map.fetch!(:status)
  end

  defp event_types(game_id) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
    |> Enum.map(& &1.type)
  end

  defp event_by_type(game_id, type) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game_id and type == ^type)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
    |> List.first()
  end

  defp assert_setup_move_payload(payload, to_zone, card_count) do
    assert is_binary(payload["setup_id"])

    players = Enum.sort_by(payload["players"], & &1["player_id"])
    assert Enum.map(players, & &1["player_id"]) == ["player_1", "player_2"]

    for player <- players do
      assert player["card_count"] == card_count
      assert length(player["cards"]) == card_count

      assert Enum.map(player["cards"], & &1["to_position"]) == Enum.to_list(1..card_count)

      assert Enum.all?(player["cards"], &(&1["owner_player_id"] == player["player_id"]))
      assert Enum.all?(player["cards"], &(&1["from_zone"] == "deck"))
      assert Enum.all?(player["cards"], &(&1["to_zone"] == to_zone))
    end
  end

  defp snapshot_indexes(game_id) do
    GameSnapshot
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
    |> Enum.map(& &1.index)
  end
end

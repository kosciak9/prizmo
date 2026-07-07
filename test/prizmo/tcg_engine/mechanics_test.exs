defmodule Prizmo.TcgEngine.MechanicsTest do
  use Prizmo.DataCase, async: true

  alias Prizmo.Tcg.CardCoverage
  alias Prizmo.Tcg.Decks.Alakazam27147
  alias Prizmo.Tcg.Decks.Dragapult27431
  alias Prizmo.Tcg.Decks.DragapultBlaziken28253
  alias Prizmo.Tcg.Decks.DragapultDusknoir28236
  alias Prizmo.Tcg.Decks.DragapultPlain28256
  alias Prizmo.Tcg.Decks.RocketMewtwo27459
  alias Prizmo.Tcg.Goal1.Decks.Alakazam28291
  alias Prizmo.Tcg.Goal1.Decks.Alakazam28340
  alias Prizmo.Tcg.Goal1.Decks.Dragapult28255
  alias Prizmo.Tcg.Goal1.Decks.Dragapult28268
  alias Prizmo.Tcg.Goal1.Decks.DragapultBlaziken28258
  alias Prizmo.TcgEngine.AttackDamage
  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.BattleActions
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.EventLog
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GamePlayer
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

    test "AZ's Tranquility switches and heals a moved Active Pokemon ex" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, azs_tranquility} = create_custom_owned_card(game.id, "player_2", "CRI-076", 220)
      {:ok, azs_tranquility} = ash_update(azs_tranquility, :draw_to_hand, %{position: 20})

      {:ok, pokemon_ex} = create_custom_owned_card(game.id, "player_2", "TWM-112", 221)
      {:ok, pokemon_ex} = ash_update(pokemon_ex, :draw_to_hand, %{position: 21})

      {:ok, pokemon_ex} =
        ash_update(pokemon_ex, :play_to_bench, %{
          position: 2,
          turn_entered_play: current_turn(game.id).turn_number
        })

      original_active = active_card(game.id, "player_2")

      {:ok, _original_active} =
        ash_update(original_active, :move_active_to_bench, %{position: 5, status: nil})

      {:ok, pokemon_ex} = ash_update(pokemon_ex, :promote_to_active, %{position: 1, status: nil})
      {:ok, pokemon_ex} = ash_update(pokemon_ex, :set_damage, %{damage: 120})

      {:ok, bench_target} = create_custom_owned_card(game.id, "player_2", "PRE-035", 222)
      {:ok, bench_target} = ash_update(bench_target, :draw_to_hand, %{position: 22})

      {:ok, bench_target} =
        ash_update(bench_target, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn(game.id).turn_number
        })

      assert CardCoverage.summarize("CRI-076").coverage_status == :supported

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert azs_tranquility.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_2", azs_tranquility.id, %{})

      [prompt] = awaiting_prompts(game.id)

      assert prompt.payload["choice_key"] ==
               "switch_own_active_with_bench_then_heal_moved_pokemon_ex"

      assert bench_target.id in prompt.payload["legal_choices"]

      assert {:ok, _game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [bench_target.id])

      assert zone(azs_tranquility.id) == :discard
      assert active_card(game.id, "player_2").id == bench_target.id
      assert zone(pokemon_ex.id) == :bench
      assert card(pokemon_ex.id).damage == 40

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "switch_own_active_with_bench_then_heal_moved_pokemon_ex")
        )

      assert cards_moved_event.payload["healed_card_instance_id"] == pokemon_ex.id
      assert cards_moved_event.payload["healed_damage"] == 80

      assert Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"]) == [
               pokemon_ex.id,
               bench_target.id
             ]
    end

    test "AZ's Tranquility does not heal a moved Active non-ex Pokemon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, azs_tranquility} = create_custom_owned_card(game.id, "player_2", "CRI-076", 230)
      {:ok, azs_tranquility} = ash_update(azs_tranquility, :draw_to_hand, %{position: 20})

      {:ok, non_ex_active} = create_custom_owned_card(game.id, "player_2", "PRE-035", 231)
      {:ok, non_ex_active} = ash_update(non_ex_active, :draw_to_hand, %{position: 21})

      {:ok, non_ex_active} =
        ash_update(non_ex_active, :play_to_bench, %{
          position: 2,
          turn_entered_play: current_turn(game.id).turn_number
        })

      original_active = active_card(game.id, "player_2")

      {:ok, _original_active} =
        ash_update(original_active, :move_active_to_bench, %{position: 5, status: nil})

      {:ok, non_ex_active} =
        ash_update(non_ex_active, :promote_to_active, %{position: 1, status: nil})

      {:ok, non_ex_active} = ash_update(non_ex_active, :set_damage, %{damage: 50})

      {:ok, bench_target} = create_custom_owned_card(game.id, "player_2", "SCR-114", 232)
      {:ok, bench_target} = ash_update(bench_target, :draw_to_hand, %{position: 22})

      {:ok, bench_target} =
        ash_update(bench_target, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn(game.id).turn_number
        })

      assert {:ok, game} = Mechanics.play_card(game, "player_2", azs_tranquility.id, %{})

      [prompt] = awaiting_prompts(game.id)

      assert {:ok, _game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [bench_target.id])

      assert active_card(game.id, "player_2").id == bench_target.id
      assert zone(non_ex_active.id) == :bench
      assert card(non_ex_active.id).damage == 50

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "switch_own_active_with_bench_then_heal_moved_pokemon_ex")
        )

      refute Map.has_key?(cards_moved_event.payload, "healed_damage")
      refute Map.has_key?(cards_moved_event.payload, "healed_card_instance_id")
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

    test "Morty's Conviction is unavailable without an opponent Benched Pokémon" do
      {:ok, game} = create_flow_action_window_game()
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, morty} = create_custom_owned_card(game.id, "player_2", "TEF-155", 200)
      {:ok, morty} = ash_update(morty, :draw_to_hand, %{position: 20})

      {:ok, discard_card} = create_custom_owned_card(game.id, "player_2", "MEE-005", 201)
      {:ok, discard_card} = ash_update(discard_card, :draw_to_hand, %{position: 21})

      assert cards_in_zone(game.id, "player_1", :bench) == []

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      refute morty.id in play_card.source_card_instance_ids

      assert {:error, :draw_card_effect_has_no_effect} =
               Mechanics.play_card(game, "player_2", morty.id, %{
                 choices: %{discard_one_from_hand: [discard_card.id]}
               })

      assert zone(morty.id) == :hand
      assert zone(discard_card.id) == :hand
    end

    test "Morty's Conviction discards 1 card and draws per opponent Benched Pokémon" do
      {:ok, game} = create_flow_action_window_game()
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, morty} = create_custom_owned_card(game.id, "player_2", "TEF-155", 210)
      {:ok, morty} = ash_update(morty, :draw_to_hand, %{position: 20})

      {:ok, discard_card} = create_custom_owned_card(game.id, "player_2", "MEE-005", 211)
      {:ok, discard_card} = ash_update(discard_card, :draw_to_hand, %{position: 21})

      current_turn_number = current_turn(game.id).turn_number

      for {card_id, instance_position, hand_position, bench_position} <- [
            {"PRE-035", 212, 22, 4},
            {"SCR-114", 213, 23, 5},
            {"JTG-120", 214, 24, 6}
          ] do
        {:ok, bench_card} =
          create_custom_owned_card(game.id, "player_1", card_id, instance_position)

        {:ok, bench_card} = ash_update(bench_card, :draw_to_hand, %{position: hand_position})

        assert {:ok, _bench_card} =
                 ash_update(bench_card, :play_to_bench, %{
                   position: bench_position,
                   turn_entered_play: current_turn_number
                 })
      end

      draw_targets = game.id |> deck_cards_except("player_2", []) |> Enum.take(3)

      assert {:ok, game} =
               Mechanics.play_card(game, "player_2", morty.id, %{
                 choices: %{discard_one_from_hand: [discard_card.id]}
               })

      assert zone(morty.id) == :discard
      assert zone(discard_card.id) == :discard
      assert Enum.map(draw_targets, &zone(&1.id)) == [:hand, :hand, :hand]

      effect_event = game.id |> game_events_by_type("cards_moved") |> List.last()
      assert effect_event.payload["effect_key"] == "draw_cards_per_opponent_benched_pokemon"
      assert length(effect_event.payload["cards"]) == 3

      assert Enum.all?(effect_event.payload["cards"], fn card_payload ->
               card_payload["from_zone"] == "deck" and card_payload["to_zone"] == "hand"
             end)
    end

    test "Iris's Fighting Spirit discards another card then draws until 6" do
      {:ok, game} = create_flow_action_window_game()
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      discard_all_hand_cards_except(game.id, "player_2", [])

      {:ok, iris} = create_custom_owned_card(game.id, "player_2", "JTG-149", 220)
      {:ok, iris} = ash_update(iris, :draw_to_hand, %{position: 1})

      hand_cards =
        for position <- 2..7 do
          {:ok, hand_card} =
            create_custom_owned_card(game.id, "player_2", "MEE-005", 220 + position)

          {:ok, hand_card} = ash_update(hand_card, :draw_to_hand, %{position: position})
          hand_card
        end

      [discard_card | kept_hand_cards] = hand_cards
      draw_target = game.id |> deck_cards_except("player_2", [iris.id]) |> List.first()

      assert CardCoverage.summarize("JTG-149").coverage_status == :supported

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert iris.id in play_card.source_card_instance_ids

      assert {:ok, game} =
               Mechanics.play_card(game, "player_2", iris.id, %{
                 choices: %{discard_one_from_hand: [discard_card.id]}
               })

      assert zone(iris.id) == :discard
      assert zone(discard_card.id) == :discard
      assert Enum.all?(kept_hand_cards, &(zone(&1.id) == :hand))
      assert zone(draw_target.id) == :hand
      assert card_count_in_zone(game.id, "player_2", :hand) == 6

      cost_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["cost_key"] == "discard_one_from_hand"))

      assert [%{"instance_id" => discarded_card_id}] = cost_event.payload["cards"]
      assert discarded_card_id == discard_card.id

      effect_event = game.id |> game_events_by_type("cards_moved") |> List.last()
      assert effect_event.payload["effect_key"] == "discard_one_then_draw_until_6"

      assert [%{"instance_id" => drawn_card_id, "from_zone" => "deck", "to_zone" => "hand"}] =
               effect_event.payload["cards"]

      assert drawn_card_id == draw_target.id
    end

    test "Carmine can be played on the first turn and discards hand before drawing 5" do
      {:ok, game} = create_flow_action_window_game()

      {:ok, carmine} = create_custom_owned_card(game.id, "player_1", "TWM-145", 220)
      {:ok, carmine} = ash_update(carmine, :draw_to_hand, %{position: 20})

      {:ok, discard_card_1} = create_custom_owned_card(game.id, "player_1", "MEE-005", 221)
      {:ok, discard_card_1} = ash_update(discard_card_1, :draw_to_hand, %{position: 21})

      {:ok, discard_card_2} = create_custom_owned_card(game.id, "player_1", "PRE-035", 222)
      {:ok, discard_card_2} = ash_update(discard_card_2, :draw_to_hand, %{position: 22})

      draw_targets = game.id |> deck_cards_except("player_1", []) |> Enum.take(5)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert carmine.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_1", carmine.id, %{})

      assert zone(carmine.id) == :discard
      assert zone(discard_card_1.id) == :discard
      assert zone(discard_card_2.id) == :discard
      assert card_count_in_zone(game.id, "player_1", :hand) == 5
      assert Enum.map(draw_targets, &zone(&1.id)) == [:hand, :hand, :hand, :hand, :hand]

      effect_event = game.id |> game_events_by_type("cards_moved") |> List.last()
      assert effect_event.payload["effect_key"] == "discard_hand_then_draw"

      assert Enum.count(effect_event.payload["cards"], fn card_payload ->
               card_payload["from_zone"] == "deck" and card_payload["to_zone"] == "hand"
             end) == 5
    end

    test "Energy Search opens a Basic Energy-only prompt and resolves to hand" do
      {:ok, game} = create_flow_action_window_game()

      {:ok, energy_search} = create_custom_owned_card(game.id, "player_1", "POR-072", 220)
      {:ok, energy_search} = ash_update(energy_search, :draw_to_hand, %{position: 20})

      {:ok, basic_energy} = create_custom_owned_card(game.id, "player_1", "MEE-005", 221)
      {:ok, special_energy} = create_custom_owned_card(game.id, "player_1", "ASC-216", 222)
      {:ok, pokemon} = create_custom_owned_card(game.id, "player_1", "PRE-035", 223)

      assert CardCoverage.summarize("POR-072").coverage_status == :supported

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert energy_search.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_1", energy_search.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "search_deck_for_basic_energy"
      assert prompt.payload["min"] == 1
      assert prompt.payload["max"] == 1
      assert basic_energy.id in prompt.payload["legal_choices"]
      refute special_energy.id in prompt.payload["legal_choices"]
      refute pokemon.id in prompt.payload["legal_choices"]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, [basic_energy.id])

      assert zone(energy_search.id) == :discard
      assert zone(basic_energy.id) == :hand
      assert zone(special_energy.id) == :deck
      assert zone(pokemon.id) == :deck

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "search_deck_for_basic_energy"))

      assert cards_moved_event.payload["public_reveal"] == true
      assert Enum.map(cards_moved_event.payload["cards"], & &1["card_id"]) == ["MEE-005"]
      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "Larry's Skill discards hand before searching a Pokemon Supporter and Basic Energy" do
      {:ok, game} = create_flow_action_window_game()
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, larry} = create_custom_owned_card(game.id, "player_2", "PRE-115", 230)
      {:ok, larry} = ash_update(larry, :draw_to_hand, %{position: 20})

      {:ok, discard_card_1} = create_custom_owned_card(game.id, "player_2", "PRE-035", 231)
      {:ok, discard_card_1} = ash_update(discard_card_1, :draw_to_hand, %{position: 21})

      {:ok, discard_card_2} = create_custom_owned_card(game.id, "player_2", "MEE-005", 232)
      {:ok, discard_card_2} = ash_update(discard_card_2, :draw_to_hand, %{position: 22})

      {:ok, pokemon} = create_custom_owned_card(game.id, "player_2", "SCR-114", 233)
      {:ok, second_pokemon} = create_custom_owned_card(game.id, "player_2", "JTG-120", 234)
      {:ok, supporter} = create_custom_owned_card(game.id, "player_2", "POR-076", 235)
      {:ok, basic_energy} = create_custom_owned_card(game.id, "player_2", "MEE-005", 236)
      {:ok, special_energy} = create_custom_owned_card(game.id, "player_2", "ASC-216", 237)
      {:ok, item} = create_custom_owned_card(game.id, "player_2", "POR-072", 238)

      assert CardCoverage.summarize("PRE-115").coverage_status == :supported

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert larry.id in play_card.source_card_instance_ids

      assert {:error, {:wrong_search_group_count, %{kind: :pokemon}, 2, 1}} =
               Mechanics.play_card(game, "player_2", larry.id, %{
                 choices: %{
                   discard_hand_then_search_for_pokemon_supporter_basic_energy: [
                     pokemon.id,
                     second_pokemon.id,
                     supporter.id
                   ]
                 }
               })

      assert zone(larry.id) == :hand
      assert zone(discard_card_1.id) == :hand
      assert zone(discard_card_2.id) == :hand

      assert {:ok, game} = Mechanics.play_card(game, "player_2", larry.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"

      assert prompt.payload["choice_key"] ==
               "discard_hand_then_search_for_pokemon_supporter_basic_energy"

      assert prompt.payload["min"] == 3
      assert prompt.payload["max"] == 3
      assert pokemon.id in prompt.payload["legal_choices"]
      assert supporter.id in prompt.payload["legal_choices"]
      assert basic_energy.id in prompt.payload["legal_choices"]
      refute special_energy.id in prompt.payload["legal_choices"]
      refute item.id in prompt.payload["legal_choices"]

      expected_discarded_card_ids =
        game.id
        |> cards_in_zone("player_2", :hand)
        |> Enum.map(& &1.card_id)
        |> Enum.sort()

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [
                 pokemon.id,
                 supporter.id,
                 basic_energy.id
               ])

      assert zone(larry.id) == :discard
      assert zone(discard_card_1.id) == :discard
      assert zone(discard_card_2.id) == :discard
      assert zone(pokemon.id) == :hand
      assert zone(supporter.id) == :hand
      assert zone(basic_energy.id) == :hand
      assert zone(second_pokemon.id) == :deck
      assert zone(special_energy.id) == :deck
      assert zone(item.id) == :deck

      cards_moved_events = game_events_by_type(game.id, "cards_moved")

      discard_event =
        Enum.find(cards_moved_events, fn event ->
          event.payload["effect_key"] ==
            "discard_hand_then_search_for_pokemon_supporter_basic_energy" and
            Enum.all?(event.payload["cards"], &(&1["to_zone"] == "discard"))
        end)

      assert discard_event.payload["affected_player_id"] == "player_2"

      assert Enum.sort(Enum.map(discard_event.payload["cards"], & &1["card_id"])) ==
               expected_discarded_card_ids

      search_event =
        Enum.find(cards_moved_events, fn event ->
          event.payload["effect_key"] ==
            "discard_hand_then_search_for_pokemon_supporter_basic_energy" and
            event.payload["public_reveal"] == true
        end)

      assert Enum.sort(Enum.map(search_event.payload["cards"], & &1["card_id"])) == [
               "MEE-005",
               "POR-076",
               "SCR-114"
             ]

      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "Lucian bottoms both players' hands then each player flips to draw 6 or 3" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Alakazam27147, DragapultPlain28256,
          rng_seed: "lucian-seed"
        )

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, lucian} = create_custom_owned_card(game.id, "player_2", "TWM-157", 240)
      {:ok, lucian} = ash_update(lucian, :draw_to_hand, %{position: 20})

      player_1_hand_before = cards_in_zone(game.id, "player_1", :hand)

      player_2_hand_before =
        game.id
        |> cards_in_zone("player_2", :hand)
        |> Enum.reject(&(&1.id == lucian.id))

      assert player_1_hand_before != []
      assert player_2_hand_before != []
      assert CardCoverage.summarize("TWM-157").coverage_status == :supported

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert lucian.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_2", lucian.id, %{})

      assert zone(lucian.id) == :discard
      assert Enum.all?(player_1_hand_before, &(zone(&1.id) == :deck))
      assert Enum.all?(player_2_hand_before, &(zone(&1.id) == :deck))

      lucian_card_events =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.filter(
          &(&1.payload["effect_key"] ==
              "each_player_hand_to_bottom_then_coin_draw_if_any")
        )

      bottom_events =
        Enum.filter(
          lucian_card_events,
          &(&1.payload["destination"] in ["deck_bottom", :deck_bottom])
        )

      assert length(bottom_events) == 2
      bottom_event_by_player = Map.new(bottom_events, &{&1.payload["affected_player_id"], &1})

      assert length(bottom_event_by_player["player_1"].payload["cards"]) ==
               length(player_1_hand_before)

      assert length(bottom_event_by_player["player_2"].payload["cards"]) ==
               length(player_2_hand_before)

      coin_events =
        game.id
        |> game_events_by_type("coin_flipped")
        |> Enum.filter(
          &(&1.payload["effect_key"] ==
              "each_player_hand_to_bottom_then_coin_draw_if_any")
        )

      assert length(coin_events) == 2

      draw_events = lucian_card_events -- bottom_events
      assert length(draw_events) == 2

      draw_event_by_player = Map.new(draw_events, &{&1.payload["affected_player_id"], &1})

      for coin_event <- coin_events do
        player_id = coin_event.player_id
        result = coin_event.payload["result"]
        expected_draw_count = if result in ["heads", :heads], do: 6, else: 3

        assert coin_event.payload["rng_context"] ==
                 "trainer_effect_coin_flip:#{player_id}:turn_2:TWM-157:each_player_hand_to_bottom_then_coin_draw_if_any"

        assert length(draw_event_by_player[player_id].payload["cards"]) == expected_draw_count
      end
    end

    test "Lucian is unavailable when neither player would put hand cards on the bottom" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, DragapultPlain28256)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, lucian} = create_custom_owned_card(game.id, "player_2", "TWM-157", 260)
      {:ok, lucian} = ash_update(lucian, :draw_to_hand, %{position: 20})

      discard_all_hand_cards_except(game.id, "player_1", [])
      discard_all_hand_cards_except(game.id, "player_2", [lucian.id])

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))

      if is_map(play_card) do
        refute lucian.id in play_card.source_card_instance_ids
      end

      assert {:error, :lucian_has_no_effect} =
               Mechanics.play_card(game, "player_2", lucian.id, %{})

      assert zone(lucian.id) == :hand
    end

    test "Brock's Scouting opens a prompt and resolves for up to 2 Basic Pokémon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, brock} = create_custom_owned_card(game.id, "player_2", "JTG-146", 200)
      {:ok, brock} = ash_update(brock, :draw_to_hand, %{position: 20})

      {:ok, basic_1} = create_custom_owned_card(game.id, "player_2", "PRE-035", 201)
      {:ok, basic_2} = create_custom_owned_card(game.id, "player_2", "SCR-114", 202)
      {:ok, evolution} = create_custom_owned_card(game.id, "player_2", "PRE-036", 203)

      assert {:ok, game} = Mechanics.play_card(game, "player_2", brock.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.payload["choice_key"] == "search_deck_for_basic_pokemon_or_evolution_pokemon"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 2
      assert basic_1.id in prompt.payload["legal_choices"]
      assert basic_2.id in prompt.payload["legal_choices"]
      assert evolution.id in prompt.payload["legal_choices"]

      label_by_id = Map.new(prompt.payload["legal_choice_labels"], &{&1["id"], &1})

      assert label_by_id[basic_1.id]["detail"] =~ "Basic Pokémon"
      assert label_by_id[basic_2.id]["detail"] =~ "Basic Pokémon"
      assert label_by_id[evolution.id]["detail"] =~ "Evolution Pokémon"

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [basic_1.id, basic_2.id])

      assert zone(brock.id) == :discard
      assert zone(basic_1.id) == :hand
      assert zone(basic_2.id) == :hand
      assert zone(evolution.id) == :deck

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] == "search_deck_for_basic_pokemon_or_evolution_pokemon")
        )

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.map(cards_moved_event.payload["cards"], & &1["card_id"]) == [
               basic_1.card_id,
               basic_2.card_id
             ]

      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "Brock's Scouting accepts 1 Evolution Pokémon but rejects mixed Basic and Evolution selections" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, brock} = create_custom_owned_card(game.id, "player_2", "JTG-146", 200)
      {:ok, brock} = ash_update(brock, :draw_to_hand, %{position: 20})

      {:ok, basic} = create_custom_owned_card(game.id, "player_2", "PRE-035", 201)
      {:ok, evolution} = create_custom_owned_card(game.id, "player_2", "PRE-036", 202)

      assert {:error, :invalid_exclusive_search_group_selection} =
               Mechanics.play_card(game, "player_2", brock.id, %{
                 choices: %{
                   search_deck_for_basic_pokemon_or_evolution_pokemon: [basic.id, evolution.id]
                 }
               })

      assert zone(brock.id) == :hand
      assert zone(basic.id) == :deck
      assert zone(evolution.id) == :deck

      assert {:ok, _game} =
               Mechanics.play_card(game, "player_2", brock.id, %{
                 choices: %{
                   search_deck_for_basic_pokemon_or_evolution_pokemon: [evolution.id]
                 }
               })

      assert zone(brock.id) == :discard
      assert zone(evolution.id) == :hand
    end

    test "Prime Catcher appears in affordances, opens a bench-choice prompt, and switches both players" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, prime_catcher} = create_custom_owned_card(game.id, "player_1", "TEF-157", 200)
      {:ok, prime_catcher} = ash_update(prime_catcher, :draw_to_hand, %{position: 20})

      {:ok, own_bench} = create_custom_owned_card(game.id, "player_1", "SCR-114", 201)
      {:ok, own_bench} = ash_update(own_bench, :draw_to_hand, %{position: 21})

      {:ok, own_bench} =
        ash_update(own_bench, :play_to_bench, %{position: 1, turn_entered_play: 1})

      {:ok, opponent_bench} = create_custom_owned_card(game.id, "player_2", "PRE-035", 202)
      {:ok, opponent_bench} = ash_update(opponent_bench, :draw_to_hand, %{position: 21})

      {:ok, opponent_bench} =
        ash_update(opponent_bench, :play_to_bench, %{position: 1, turn_entered_play: 1})

      original_own_active = active_card(game.id, "player_1")
      original_opponent_active = active_card(game.id, "player_2")

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert prime_catcher.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_1", prime_catcher.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"

      assert prompt.payload["choice_key"] ==
               "switch_opponent_bench_to_active_then_switch_own_active_with_bench"

      assert Enum.sort(prompt.payload["legal_choices"]) ==
               Enum.sort([own_bench.id, opponent_bench.id])

      label_by_id = Map.new(prompt.payload["legal_choice_labels"], &{&1["id"], &1})

      assert label_by_id[own_bench.id]["detail"] =~ "Your Benched Pokémon"
      assert label_by_id[opponent_bench.id]["detail"] =~ "Opponent Benched Pokémon"

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      [view_prompt] = view.prompts

      assert Enum.sort(Enum.map(view_prompt.payload["legal_choice_cards"], & &1.id)) ==
               Enum.sort([own_bench.id, opponent_bench.id])

      assert Enum.map(view_prompt.payload["legal_choice_cards"], & &1.zone) == ["bench", "bench"]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, [
                 own_bench.id,
                 opponent_bench.id
               ])

      assert zone(prime_catcher.id) == :discard
      assert active_card(game.id, "player_1").id == own_bench.id
      assert active_card(game.id, "player_2").id == opponent_bench.id
      assert zone(original_own_active.id) == :bench
      assert zone(original_opponent_active.id) == :bench

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "switch_opponent_bench_to_active_then_switch_own_active_with_bench")
        )

      assert length(cards_moved_event.payload["cards"]) == 4
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

    test "TEF-146 Eri appears in play_card affordances and resolves discard_opponent_item_cards_from_hand prompt" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult28268, Alakazam28340)

      eri = move_owned_card_to_hand(game.id, "player_2", "TEF-146", 1)
      item_1 = move_owned_card_to_hand(game.id, "player_1", "TEF-144", 1)
      item_2 = move_owned_card_to_hand(game.id, "player_1", "POR-081", 2)
      item_3 = move_owned_card_to_hand(game.id, "player_1", "TWM-165", 3)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert eri.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_2", eri.id, %{})

      [prompt] = prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.payload["choice_key"] == "discard_opponent_item_cards_from_hand"

      assert Enum.sort(prompt.payload["legal_choices"]) ==
               Enum.sort([item_1.id, item_2.id, item_3.id])

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [item_1.id, item_2.id])

      assert zone(item_1.id) == :discard
      assert zone(item_2.id) == :discard
      assert zone(item_3.id) == :hand

      effect_cards_moved =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "discard_opponent_item_cards_from_hand"))

      assert effect_cards_moved.payload["affected_player_id"] == "player_1"

      assert Enum.map(effect_cards_moved.payload["cards"], & &1["card_id"]) == [
               item_1.card_id,
               item_2.card_id
             ]
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

    test "TEF-145 Ciphermaniac's Codebreaking appears in play_card affordances and stacks chosen cards on top of deck" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult28255, Alakazam28291)

      ciphermaniac = move_owned_card_to_hand(game.id, "player_2", "TEF-145", 1)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert is_map(play_card)
      assert ciphermaniac.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_2", ciphermaniac.id, %{})

      [prompt] = prompts(game.id)
      [chosen_1, chosen_2 | _rest] = prompt.payload["legal_choices"]

      assert prompt.player_id == "player_2"
      assert prompt.payload["choice_key"] == "search_deck_for_cards_to_top"

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [chosen_1, chosen_2])

      assert zone(ciphermaniac.id) == :discard

      assert game.id
             |> cards_in_zone("player_2", :deck)
             |> Enum.take(2)
             |> Enum.map(& &1.id) == [chosen_1, chosen_2]

      refute "deck_shuffled" in Enum.take(event_types(game.id), -6)
    end
  end

  describe "Goal 2 metadata-backed support slice" do
    test "MEE-008 Metal Energy metadata makes the card generic-supported" do
      assert {:ok, metal_energy} = CardCatalog.fetch("MEE-008")
      assert metal_energy.supertype == :energy
      assert metal_energy.energy_type == :basic
      assert metal_energy.provides == [:metal]

      assert %{coverage_status: :generic_supported} = CardCoverage.summarize("MEE-008")
    end

    test "ASC-046 Snorunt metadata makes Chilly executable" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "ASC-046", 200)
      defender = active_card(game.id, "player_2")

      assert {:ok, attack} = CardCatalog.fetch_attack(attacker.card_id, :chilly)
      assert attack.damage == 10
      assert {:ok, 10} = AttackDamage.damage_for(attacker, defender, attack)
    end

    test "CRI-080 Prism Tower discards 2 cards from hand to draw 1 once per turn" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, prism_tower} = create_custom_owned_card(game.id, "player_1", "CRI-080", 200)
      {:ok, prism_tower} = ash_update(prism_tower, :draw_to_hand, %{position: 20})

      {:ok, discard_1} = create_custom_owned_card(game.id, "player_1", "MEE-005", 201)
      {:ok, discard_1} = ash_update(discard_1, :draw_to_hand, %{position: 21})

      {:ok, discard_2} = create_custom_owned_card(game.id, "player_1", "PRE-035", 202)
      {:ok, discard_2} = ash_update(discard_2, :draw_to_hand, %{position: 22})

      draw_target = game.id |> cards_in_zone("player_1", :deck) |> List.first()

      assert CardCoverage.summarize("CRI-080").coverage_status == :supported

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", prism_tower.id)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")

      prism_action = Enum.find(view.action_affordances, &(&1.key == "prism_tower"))
      assert is_map(prism_action)
      assert prism_action.source_card_instance_ids == [prism_tower.id]
      assert prism_action.required_source_count == 2
      assert prism_action.choice_keys == ["discard_cards"]
      assert discard_1.id in prism_action.target_card_instance_ids
      assert discard_2.id in prism_action.target_card_instance_ids

      assert {:ok, game} =
               Mechanics.use_prism_tower(game, "player_1", [discard_1.id, discard_2.id])

      assert zone(discard_1.id) == :discard
      assert zone(discard_2.id) == :discard
      assert zone(draw_target.id) == :hand

      prism_event =
        game.id
        |> game_events_by_type("stadium_effect_used")
        |> Enum.find(&(&1.payload["effect_key"] == "discard_two_cards_to_draw_one"))

      assert prism_event.payload["source_card_id"] == "CRI-080"
      assert prism_event.payload["discarded_card_count"] == 2
      assert prism_event.payload["drawn_card_count"] == 1
      assert prism_event.payload["public_note"] =~ "Prism Tower"

      assert {:error, :prism_tower_already_used_this_turn} =
               Mechanics.use_prism_tower(game, "player_1", [draw_target.id, prism_tower.id])

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      refute Enum.any?(view.action_affordances, &(&1.key == "prism_tower"))
    end

    test "CRI-080 Prism Tower rejects invalid discard selections before moving cards" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, prism_tower} = create_custom_owned_card(game.id, "player_1", "CRI-080", 210)
      {:ok, prism_tower} = ash_update(prism_tower, :draw_to_hand, %{position: 20})
      {:ok, discard_1} = create_custom_owned_card(game.id, "player_1", "MEE-005", 211)
      {:ok, discard_1} = ash_update(discard_1, :draw_to_hand, %{position: 21})

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", prism_tower.id)

      assert {:error, {:wrong_prism_tower_discard_count, 1}} =
               Mechanics.use_prism_tower(game, "player_1", [discard_1.id])

      assert zone(discard_1.id) == :hand
      assert game_events_by_type(game.id, "stadium_effect_used") == []
    end

    test "POR-077 Lumiose City searches a Basic Pokémon to Bench and ends the turn" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, lumiose_city} = create_custom_owned_card(game.id, "player_1", "POR-077", 220)
      {:ok, lumiose_city} = ash_update(lumiose_city, :draw_to_hand, %{position: 20})

      {:ok, target} = create_custom_owned_card(game.id, "player_1", "PRE-035", 221)
      {:ok, non_target} = create_custom_owned_card(game.id, "player_1", "MEE-005", 222)

      assert CardCoverage.summarize("POR-077").coverage_status == :supported

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", lumiose_city.id)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")

      lumiose_action = Enum.find(view.action_affordances, &(&1.key == "lumiose_city"))

      assert is_map(lumiose_action)
      assert lumiose_action.source_card_instance_ids == [lumiose_city.id]
      assert lumiose_action.required_source_count == 1
      assert lumiose_action.choice_keys == ["target_card_instance_id"]
      assert target.id in lumiose_action.target_card_instance_ids
      refute non_target.id in lumiose_action.target_card_instance_ids

      assert {:ok, game} = Mechanics.use_lumiose_city(game, "player_1", target.id)

      assert zone(target.id) == :bench
      assert card(target.id).turn_entered_play == 1
      assert current_turn(game.id).status == :ended

      lumiose_event =
        game.id
        |> game_events_by_type("stadium_effect_used")
        |> Enum.find(&(&1.payload["effect_key"] == "search_basic_pokemon_to_bench_then_end_turn"))

      assert lumiose_event.payload["source_card_id"] == "POR-077"
      assert lumiose_event.payload["public_reveal"] == true
      assert lumiose_event.payload["public_note"] =~ "Lumiose City"
      assert [moved_card] = lumiose_event.payload["cards"]
      assert moved_card["instance_id"] == target.id
      assert moved_card["from_zone"] == "deck"
      assert moved_card["to_zone"] == "bench"

      assert [deck_shuffle_event] = game_events_by_type(game.id, "deck_shuffled")
      assert deck_shuffle_event.payload["source_card_id"] == "POR-077"
      assert deck_shuffle_event.payload["shuffle"] == "lumiose_city"

      assert game.id
             |> game_events_by_type("end_turn")
             |> List.last()
             |> then(& &1.payload["reason"]) == "lumiose_city"
    end

    test "POR-077 Lumiose City rejects non-Basic deck selections before moving cards" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, lumiose_city} = create_custom_owned_card(game.id, "player_1", "POR-077", 230)
      {:ok, lumiose_city} = ash_update(lumiose_city, :draw_to_hand, %{position: 20})

      {:ok, non_target} = create_custom_owned_card(game.id, "player_1", "MEE-005", 231)

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", lumiose_city.id)

      assert {:error, _reason} = Mechanics.use_lumiose_city(game, "player_1", non_target.id)

      assert zone(non_target.id) == :deck
      assert current_turn(game.id).status == :action_window
      assert game_events_by_type(game.id, "stadium_effect_used") == []
    end

    test "SFA-057 Colress's Tenacity searches for a Stadium and an Energy" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, colress} = create_custom_owned_card(game.id, "player_2", "SFA-057", 200)
      {:ok, colress} = ash_update(colress, :draw_to_hand, %{position: 20})

      {:ok, stadium} = create_custom_owned_card(game.id, "player_2", "SCR-131", 201)
      {:ok, energy} = create_custom_owned_card(game.id, "player_2", "MEE-005", 202)
      {:ok, non_matching} = create_custom_owned_card(game.id, "player_2", "PRE-035", 203)

      assert {:ok, game} = Mechanics.play_card(game, "player_2", colress.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.payload["choice_key"] == "search_deck_for_stadium_and_energy"
      assert prompt.payload["min"] == 2
      assert prompt.payload["max"] == 2
      assert stadium.id in prompt.payload["legal_choices"]
      assert energy.id in prompt.payload["legal_choices"]
      refute non_matching.id in prompt.payload["legal_choices"]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [stadium.id, energy.id])

      assert zone(colress.id) == :discard
      assert zone(stadium.id) == :hand
      assert zone(energy.id) == :hand
      assert zone(non_matching.id) == :deck

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "search_deck_for_stadium_and_energy"))

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.sort(Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"])) ==
               Enum.sort([stadium.id, energy.id])

      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "SVI-171 Energy Retrieval returns up to 2 Basic Energy cards from discard to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, energy_retrieval} = create_custom_owned_card(game.id, "player_1", "SVI-171", 200)
      {:ok, energy_retrieval} = ash_update(energy_retrieval, :draw_to_hand, %{position: 20})

      {:ok, basic_energy_1} = create_custom_owned_card(game.id, "player_1", "MEE-005", 201)
      {:ok, basic_energy_1} = ash_update(basic_energy_1, :draw_to_hand, %{position: 21})

      {:ok, basic_energy_2} = create_custom_owned_card(game.id, "player_1", "MEE-006", 202)
      {:ok, basic_energy_2} = ash_update(basic_energy_2, :draw_to_hand, %{position: 22})

      {:ok, special_energy} = create_custom_owned_card(game.id, "player_1", "POR-088", 203)
      {:ok, special_energy} = ash_update(special_energy, :draw_to_hand, %{position: 23})

      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", basic_energy_1.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", basic_energy_2.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", special_energy.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", energy_retrieval.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "recover_basic_energy_from_discard"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 2
      assert basic_energy_1.id in prompt.payload["legal_choices"]
      assert basic_energy_2.id in prompt.payload["legal_choices"]
      refute special_energy.id in prompt.payload["legal_choices"]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, [
                 basic_energy_1.id,
                 basic_energy_2.id
               ])

      assert zone(energy_retrieval.id) == :discard
      assert zone(basic_energy_1.id) == :hand
      assert zone(basic_energy_2.id) == :hand
      assert zone(special_energy.id) == :discard

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "recover_basic_energy_from_discard"))

      assert Enum.sort(Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"])) ==
               Enum.sort([basic_energy_1.id, basic_energy_2.id])
    end

    test "PRE-116 Max Rod returns up to 5 Pokemon and Basic Energy cards from discard to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, max_rod} = create_custom_owned_card(game.id, "player_1", "PRE-116", 200)
      {:ok, max_rod} = ash_update(max_rod, :draw_to_hand, %{position: 20})

      {:ok, pokemon_1} = create_custom_owned_card(game.id, "player_1", "PRE-035", 201)
      {:ok, pokemon_1} = ash_update(pokemon_1, :draw_to_hand, %{position: 21})

      {:ok, pokemon_2} = create_custom_owned_card(game.id, "player_1", "DRI-016", 202)
      {:ok, pokemon_2} = ash_update(pokemon_2, :draw_to_hand, %{position: 22})

      {:ok, pokemon_3} = create_custom_owned_card(game.id, "player_1", "TWM-130", 203)
      {:ok, pokemon_3} = ash_update(pokemon_3, :draw_to_hand, %{position: 23})

      {:ok, basic_energy_1} = create_custom_owned_card(game.id, "player_1", "MEE-005", 204)
      {:ok, basic_energy_1} = ash_update(basic_energy_1, :draw_to_hand, %{position: 24})

      {:ok, basic_energy_2} = create_custom_owned_card(game.id, "player_1", "MEE-006", 205)
      {:ok, basic_energy_2} = ash_update(basic_energy_2, :draw_to_hand, %{position: 25})

      {:ok, special_energy} = create_custom_owned_card(game.id, "player_1", "POR-088", 206)
      {:ok, special_energy} = ash_update(special_energy, :draw_to_hand, %{position: 26})

      {:ok, trainer} = create_custom_owned_card(game.id, "player_1", "PRE-115", 207)
      {:ok, trainer} = ash_update(trainer, :draw_to_hand, %{position: 27})

      selected_targets = [pokemon_1, pokemon_2, pokemon_3, basic_energy_1, basic_energy_2]

      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", pokemon_1.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", pokemon_2.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", pokemon_3.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", basic_energy_1.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", basic_energy_2.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", special_energy.id)
      assert {:ok, game} = Mechanics.discard_from_hand(game, "player_1", trainer.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", max_rod.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "recover_pokemon_or_basic_energy_from_discard"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 5

      for card <- selected_targets do
        assert card.id in prompt.payload["legal_choices"]
      end

      refute special_energy.id in prompt.payload["legal_choices"]
      refute trainer.id in prompt.payload["legal_choices"]

      assert {:ok, game} =
               Mechanics.choose_prompt(
                 game,
                 "player_1",
                 prompt.id,
                 Enum.map(selected_targets, & &1.id)
               )

      assert zone(max_rod.id) == :discard

      for card <- selected_targets do
        assert zone(card.id) == :hand
      end

      assert zone(special_energy.id) == :discard
      assert zone(trainer.id) == :discard

      game_id = game.id

      player =
        GamePlayer
        |> Ash.Query.filter(game_id == ^game_id and player_id == "player_1")
        |> Ash.read_one!()

      assert player.ace_spec_played_this_game?

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] == "recover_pokemon_or_basic_energy_from_discard")
        )

      assert Enum.sort(Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"])) ==
               selected_targets
               |> Enum.map(& &1.id)
               |> Enum.sort()

      assert CardCoverage.summarize("PRE-116").coverage_status == :supported
    end

    test "MEG-116 Fighting Gong searches for a Basic Fighting Energy or a Basic Fighting Pokémon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, fighting_gong} = create_custom_owned_card(game.id, "player_1", "MEG-116", 210)
      {:ok, fighting_gong} = ash_update(fighting_gong, :draw_to_hand, %{position: 20})

      {:ok, fighting_energy} = create_custom_owned_card(game.id, "player_1", "MEE-006", 211)
      {:ok, basic_fighting} = create_custom_owned_card(game.id, "player_1", "SSP-111", 212)
      {:ok, stage_1_fighting} = create_custom_owned_card(game.id, "player_1", "TWM-100", 213)
      {:ok, basic_non_fighting} = create_custom_owned_card(game.id, "player_1", "PRE-035", 214)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", fighting_gong.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"

      assert prompt.payload["choice_key"] ==
               "search_deck_for_basic_fighting_energy_or_basic_fighting_pokemon"

      assert prompt.payload["min"] == 1
      assert prompt.payload["max"] == 1
      assert fighting_energy.id in prompt.payload["legal_choices"]
      assert basic_fighting.id in prompt.payload["legal_choices"]
      refute stage_1_fighting.id in prompt.payload["legal_choices"]
      refute basic_non_fighting.id in prompt.payload["legal_choices"]

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, [basic_fighting.id])

      assert zone(fighting_gong.id) == :discard
      assert zone(basic_fighting.id) == :hand
      assert zone(fighting_energy.id) == :deck

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "search_deck_for_basic_fighting_energy_or_basic_fighting_pokemon")
        )

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"]) == [
               basic_fighting.id
             ]
    end

    test "MEG-074 Lunatone Lunar Cycle discards Basic Fighting Energy to draw 3 once per turn" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      current_turn_number = current_turn(game.id).turn_number

      {:ok, lunatone} = create_custom_owned_card(game.id, "player_1", "MEG-074", 230)
      {:ok, lunatone} = ash_update(lunatone, :draw_to_hand, %{position: 20})

      {:ok, lunatone} =
        ash_update(lunatone, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn_number
        })

      {:ok, fighting_energy} = create_custom_owned_card(game.id, "player_1", "MEE-006", 231)
      {:ok, fighting_energy} = ash_update(fighting_energy, :draw_to_hand, %{position: 21})

      assert {:error, {:lunar_cycle_requires_card_in_play, "MEG-075"}} =
               Mechanics.use_lunatone_lunar_cycle(
                 game,
                 "player_1",
                 lunatone.id,
                 fighting_energy.id
               )

      {:ok, solrock} = create_custom_owned_card(game.id, "player_1", "MEG-075", 232)
      {:ok, solrock} = ash_update(solrock, :draw_to_hand, %{position: 22})

      {:ok, _solrock} =
        ash_update(solrock, :play_to_bench, %{
          position: 2,
          turn_entered_play: current_turn_number
        })

      draw_targets = game.id |> cards_in_zone("player_1", :deck) |> Enum.take(3)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      lunar_action = Enum.find(view.action_affordances, &(&1.key == "lunar_cycle"))
      assert is_map(lunar_action)
      assert lunar_action.source_card_instance_ids == [lunatone.id, fighting_energy.id]
      assert lunar_action.target_card_instance_ids == [fighting_energy.id]
      assert lunar_action.choice_keys == ["energy_card_instance_id"]

      assert {:ok, game} =
               Mechanics.use_lunatone_lunar_cycle(
                 game,
                 "player_1",
                 lunatone.id,
                 fighting_energy.id
               )

      assert zone(fighting_energy.id) == :discard

      for drawn_card <- draw_targets do
        assert zone(drawn_card.id) == :hand
      end

      lunar_event =
        game.id
        |> game_events_by_type("ability_used")
        |> Enum.find(&(&1.payload["ability_id"] == "lunar_cycle"))

      assert lunar_event.payload["source_card_id"] == "MEG-074"
      assert lunar_event.payload["energy_card_instance_id"] == fighting_energy.id
      assert lunar_event.payload["discarded_card_count"] == 1
      assert lunar_event.payload["drawn_card_count"] == 3

      assert lunar_event.payload["public_note"] ==
               "Lunar Cycle discarded Basic Fighting Energy and drew 3 cards."

      {:ok, second_lunatone} = create_custom_owned_card(game.id, "player_1", "MEG-074", 233)
      {:ok, second_lunatone} = ash_update(second_lunatone, :draw_to_hand, %{position: 23})

      {:ok, second_lunatone} =
        ash_update(second_lunatone, :play_to_bench, %{
          position: 3,
          turn_entered_play: current_turn_number
        })

      {:ok, second_energy} = create_custom_owned_card(game.id, "player_1", "MEE-006", 234)
      {:ok, second_energy} = ash_update(second_energy, :draw_to_hand, %{position: 24})

      assert {:error, {:ability_already_used_this_turn, "player_1", :lunar_cycle}} =
               Mechanics.use_lunatone_lunar_cycle(
                 game,
                 "player_1",
                 second_lunatone.id,
                 second_energy.id
               )

      assert zone(second_energy.id) == :hand
      assert {:ok, view_after} = GameView.for_player(game.id, "player_1")
      refute Enum.any?(view_after.action_affordances, &(&1.key == "lunar_cycle"))
    end

    test "MEG-075 Solrock Cosmic Beam requires a Benched Lunatone and ignores Weakness" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "MEG-075", 240)
      {:ok, defender} = create_custom_owned_card(game.id, "player_2", "CRI-070", 241)

      assert {:ok, cosmic_beam} = CardCatalog.fetch_attack(attacker.card_id, :cosmic_beam)
      assert cosmic_beam.damage == 70
      assert {:ok, 0} = AttackDamage.damage_for(attacker, defender, cosmic_beam)

      {:ok, lunatone} = create_custom_owned_card(game.id, "player_1", "MEG-074", 242)
      {:ok, lunatone} = ash_update(lunatone, :draw_to_hand, %{position: 20})

      {:ok, _lunatone} =
        ash_update(lunatone, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn(game.id).turn_number
        })

      assert {:ok, 70} = AttackDamage.damage_for(attacker, defender, cosmic_beam)
    end

    test "ASC-047 Mega Froslass ex scales with opponent hand size and puts the Active Pokémon Asleep" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "ASC-047", 220)
      defender = active_card(game.id, "player_2")
      opponent_hand_count = card_count_in_zone(game.id, "player_2", :hand)
      expected_damage = opponent_hand_count * 50

      assert {:ok, resentful_refrain} =
               CardCatalog.fetch_attack(attacker.card_id, :resentful_refrain)

      assert resentful_refrain.damage == 0

      assert {:ok, ^expected_damage} =
               AttackDamage.damage_for(attacker, defender, resentful_refrain)

      assert {:ok, absolute_snow} = CardCatalog.fetch_attack(attacker.card_id, :absolute_snow)
      assert absolute_snow.damage == 150

      assert {:ok, effect_payload} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 absolute_snow,
                 %{}
               )

      assert effect_payload.effect_type == "sleep_defender_active"
      assert effect_payload.defender_status == "asleep"
      assert effect_payload.defender_status_applied?
      assert card(defender.id).status == :asleep
    end

    test "TWM-162 Scoop Up Cyclone returns a Benched Pokémon and its attached cards to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, scoop_up} = create_custom_owned_card(game.id, "player_1", "TWM-162", 200)
      {:ok, scoop_up} = ash_update(scoop_up, :draw_to_hand, %{position: 20})

      {:ok, target} = create_custom_owned_card(game.id, "player_1", "PRE-035", 201)
      {:ok, target} = ash_update(target, :draw_to_hand, %{position: 21})
      {:ok, target} = ash_update(target, :play_to_bench, %{position: 1, turn_entered_play: 1})

      {:ok, basic_energy} = create_custom_owned_card(game.id, "player_1", "MEE-005", 202)
      {:ok, basic_energy} = ash_update(basic_energy, :draw_to_hand, %{position: 22})

      {:ok, special_energy} = create_custom_owned_card(game.id, "player_1", "POR-088", 203)
      {:ok, special_energy} = ash_update(special_energy, :draw_to_hand, %{position: 23})

      {:ok, basic_energy} =
        ash_update(basic_energy, :attach, %{attached_to_card_instance_id: target.id, position: 1})

      {:ok, special_energy} =
        ash_update(special_energy, :attach, %{
          attached_to_card_instance_id: target.id,
          position: 2
        })

      assert {:ok, _game} =
               Mechanics.play_card(game, "player_1", scoop_up.id, %{
                 choices: %{return_own_pokemon_with_attached_cards_to_hand: [target.id]}
               })

      assert zone(scoop_up.id) == :discard
      assert zone(target.id) == :hand
      assert zone(basic_energy.id) == :hand
      assert zone(special_energy.id) == :hand

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] == "return_own_pokemon_with_attached_cards_to_hand")
        )

      assert Enum.sort(Enum.map(cards_moved_event.payload["cards"], & &1["instance_id"])) ==
               Enum.sort([target.id, basic_energy.id, special_energy.id])
    end

    test "TWM-162 Scoop Up Cyclone on the Active Pokémon leaves a replacement-active affordance during the action window" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, scoop_up} = create_custom_owned_card(game.id, "player_1", "TWM-162", 210)
      {:ok, scoop_up} = ash_update(scoop_up, :draw_to_hand, %{position: 20})

      {:ok, bench_1} = create_custom_owned_card(game.id, "player_1", "PRE-035", 211)
      {:ok, bench_1} = ash_update(bench_1, :draw_to_hand, %{position: 21})
      {:ok, bench_1} = ash_update(bench_1, :play_to_bench, %{position: 1, turn_entered_play: 1})

      {:ok, bench_2} = create_custom_owned_card(game.id, "player_1", "PRE-036", 212)
      {:ok, bench_2} = ash_update(bench_2, :draw_to_hand, %{position: 22})
      {:ok, bench_2} = ash_update(bench_2, :play_to_bench, %{position: 2, turn_entered_play: 1})

      original_active = active_card(game.id, "player_1")

      assert {:ok, _game} =
               Mechanics.play_card(game, "player_1", scoop_up.id, %{
                 choices: %{return_own_pokemon_with_attached_cards_to_hand: [original_active.id]}
               })

      assert zone(original_active.id) == :hand

      assert {:ok, view} = GameView.for_player(game.id, "player_1")

      [replacement] =
        Enum.filter(view.action_affordances, &(&1.key == "choose_replacement_active"))

      assert Enum.sort(replacement.target_card_instance_ids) ==
               Enum.sort([bench_1.id, bench_2.id])

      assert {:ok, _game} = Mechanics.choose_replacement_active(game, "player_1", bench_2.id)
      assert active_card(game.id, "player_1").id == bench_2.id
    end

    test "SCR-132 Briar adds an extra Prize when a Tera attack Knocks Out the opponent's Active Pokémon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      reduce_opponent_prize_count_to(game.id, "player_1", 2)

      current_turn = current_turn(game.id)

      {:ok, briar} = create_custom_owned_card(game.id, "player_2", "SCR-132", 220)
      {:ok, briar} = ash_update(briar, :draw_to_hand, %{position: 20})

      attacker = active_card(game.id, "player_2")

      {:ok, _moved_attacker} =
        ash_update(attacker, :move_active_to_bench, %{position: 2, status: nil})

      {:ok, tera_attacker} = create_custom_owned_card(game.id, "player_2", "TWM-025", 221)
      {:ok, tera_attacker} = ash_update(tera_attacker, :draw_to_hand, %{position: 21})

      {:ok, tera_attacker} =
        ash_update(tera_attacker, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn.turn_number
        })

      {:ok, tera_attacker} =
        ash_update(tera_attacker, :promote_to_active, %{position: 1, status: nil})

      defender = active_card(game.id, "player_1")

      {:ok, _moved_defender} =
        ash_update(defender, :move_active_to_bench, %{position: 2, status: nil})

      {:ok, target_active} = create_custom_owned_card(game.id, "player_1", "PRE-035", 222)
      {:ok, target_active} = ash_update(target_active, :draw_to_hand, %{position: 21})

      {:ok, target_active} =
        ash_update(target_active, :play_to_bench, %{position: 1, turn_entered_play: 1})

      {:ok, target_active} =
        ash_update(target_active, :promote_to_active, %{position: 1, status: nil})

      for {card_id, position} <- [{"MEE-001", 223}, {"MEE-001", 224}, {"MEE-001", 225}] do
        {:ok, energy} = create_custom_owned_card(game.id, "player_2", card_id, position)
        {:ok, energy} = ash_update(energy, :draw_to_hand, %{position: position})

        {:ok, _energy} =
          ash_update(energy, :attach, %{
            attached_to_card_instance_id: tera_attacker.id,
            position: position - 222
          })
      end

      assert {:ok, game} = Mechanics.play_card(game, "player_2", briar.id, %{})
      assert {:ok, game} = Mechanics.declare_attack(game, "player_2", :myriad_leaf_shower)

      [prompt] = awaiting_prompts(game.id)
      assert prompt.prompt_type == "choose_knockout_prizes"
      assert prompt.payload["min"] == 2
      assert prompt.payload["max"] == 2
      assert [%{"prize_count" => 2}] = prompt.payload["knockouts"]

      knockout_required = event_by_type(game.id, "knockout_prize_selection_required")
      assert knockout_required.payload["prize_count"] == 2
      assert knockout_required.payload["knocked_out_card_instance_id"] == target_active.id
    end

    test "SSP-187 Surfer switches and then draws up to 5 cards" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, surfer} = create_custom_owned_card(game.id, "player_2", "SSP-187", 230)
      {:ok, surfer} = ash_update(surfer, :draw_to_hand, %{position: 20})

      {:ok, bench_target} = create_custom_owned_card(game.id, "player_2", "PRE-035", 231)
      {:ok, bench_target} = ash_update(bench_target, :draw_to_hand, %{position: 21})

      {:ok, bench_target} =
        ash_update(bench_target, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn(game.id).turn_number
        })

      current_hand = cards_in_zone(game.id, "player_2", :hand)

      current_hand
      |> Enum.reject(&(&1.id == surfer.id))
      |> Enum.take(max(length(current_hand) - 3, 0))
      |> Enum.with_index(card_count_in_zone(game.id, "player_2", :discard) + 1)
      |> Enum.each(fn {hand_card, position} ->
        {:ok, _discarded} = ash_update(hand_card, :discard, %{position: position})
      end)

      original_active = active_card(game.id, "player_2")

      assert {:ok, game} = Mechanics.play_card(game, "player_2", surfer.id, %{})

      [prompt] = awaiting_prompts(game.id)

      assert prompt.payload["choice_key"] ==
               "switch_own_active_with_bench_then_draw_until_hand_size"

      assert prompt.payload["legal_choices"] == [bench_target.id]

      assert {:ok, _game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [bench_target.id])

      assert zone(surfer.id) == :discard
      assert active_card(game.id, "player_2").id == bench_target.id
      assert zone(original_active.id) == :bench
      assert card_count_in_zone(game.id, "player_2", :hand) == 5

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] == "switch_own_active_with_bench_then_draw_until_hand_size")
        )

      assert Enum.count(cards_moved_event.payload["cards"], &(&1["to_zone"] == "hand")) == 3
    end

    test "ASC-162 Team Rocket's Kangaskhan ex uses heads-count damage and gains Wicked Impact bonus after a Team Rocket Supporter" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, petrel} = create_custom_owned_card(game.id, "player_2", "DRI-176", 240)
      {:ok, petrel} = ash_update(petrel, :draw_to_hand, %{position: 20})

      {:ok, trainer_target} = create_custom_owned_card(game.id, "player_2", "MEG-130", 241)
      {:ok, attacker} = create_custom_owned_card(game.id, "player_2", "ASC-162", 242)
      {:ok, defender} = create_custom_owned_card(game.id, "player_1", "PRE-035", 243)

      assert {:ok, comet_punch} = CardCatalog.fetch_attack(attacker.card_id, :comet_punch)
      assert {:ok, wicked_impact} = CardCatalog.fetch_attack(attacker.card_id, :wicked_impact)

      assert {:ok, 90} =
               AttackDamage.damage_for(attacker, defender, comet_punch, %{heads_count: 3})

      assert {:ok, 120} = AttackDamage.damage_for(attacker, defender, wicked_impact)

      assert {:ok, _game} =
               Mechanics.play_card(game, "player_2", petrel.id, %{
                 choices: %{search_deck_for_trainer_card: [trainer_target.id]}
               })

      assert {:ok, 220} = AttackDamage.damage_for(attacker, defender, wicked_impact)
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

  describe "Goal 2 HP modifier support slice" do
    test "Gravity Mountain immediately knocks out a damaged Stage 2 Pokémon when played" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      bench_position = card_count_in_zone(game.id, "player_1", :bench) + 1

      {:ok, stage_2} = create_custom_owned_card(game.id, "player_1", "PRE-037", 200)
      {:ok, stage_2} = ash_update(stage_2, :draw_to_hand, %{position: 20})

      {:ok, stage_2} =
        ash_update(stage_2, :play_to_bench, %{
          position: bench_position,
          turn_entered_play: current_turn(game.id).turn_number
        })

      {:ok, _stage_2} = ash_update(stage_2, :set_damage, %{damage: 130})

      {:ok, gravity_mountain} = create_custom_owned_card(game.id, "player_1", "SSP-177", 201)
      {:ok, gravity_mountain} = ash_update(gravity_mountain, :draw_to_hand, %{position: 21})

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", gravity_mountain.id)

      assert zone(gravity_mountain.id) == :stadium
      assert zone(stage_2.id) == :discard

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.prompt_type == "choose_knockout_prizes"
      assert prompt.payload["knocked_out_card_instance_ids"] == [stage_2.id]
    end

    test "Gravity Mountain lowers the knockout threshold for later damage" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      bench_position = card_count_in_zone(game.id, "player_1", :bench) + 1

      {:ok, stage_2} = create_custom_owned_card(game.id, "player_1", "PRE-037", 210)
      {:ok, stage_2} = ash_update(stage_2, :draw_to_hand, %{position: 20})

      {:ok, stage_2} =
        ash_update(stage_2, :play_to_bench, %{
          position: bench_position,
          turn_entered_play: current_turn(game.id).turn_number
        })

      {:ok, _stage_2} = ash_update(stage_2, :set_damage, %{damage: 110})

      {:ok, gravity_mountain} = create_custom_owned_card(game.id, "player_1", "SSP-177", 211)
      {:ok, gravity_mountain} = ash_update(gravity_mountain, :draw_to_hand, %{position: 21})

      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", gravity_mountain.id)
      assert awaiting_prompts(game.id) == []

      assert {:ok, %{knocked_out?: true, resulting_damage: 130, knockout_prize_count: 1}} =
               BattleActions.apply_attack_damage(game.id, "player_2", card(stage_2.id), 20)

      assert zone(stage_2.id) == :discard
    end

    test "Jamming Tower suppression can knock out a Hero's Cape target" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      bench_position = card_count_in_zone(game.id, "player_1", :bench) + 1

      {:ok, target} = create_custom_owned_card(game.id, "player_1", "PRE-035", 220)
      {:ok, target} = ash_update(target, :draw_to_hand, %{position: 20})

      {:ok, target} =
        ash_update(target, :play_to_bench, %{
          position: bench_position,
          turn_entered_play: current_turn(game.id).turn_number
        })

      {:ok, heros_cape} = create_custom_owned_card(game.id, "player_1", "TEF-152", 221)
      {:ok, heros_cape} = ash_update(heros_cape, :draw_to_hand, %{position: 21})

      assert {:ok, game} = Mechanics.attach_tool(game, "player_1", heros_cape.id, target.id)
      {:ok, _target} = ash_update(card(target.id), :set_damage, %{damage: 120})

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      {:ok, jamming_tower} = create_custom_owned_card(game.id, "player_2", "TWM-153", 222)
      {:ok, jamming_tower} = ash_update(jamming_tower, :draw_to_hand, %{position: 20})

      assert {:ok, game} = Mechanics.play_stadium(game, "player_2", jamming_tower.id)

      assert zone(jamming_tower.id) == :stadium
      assert zone(target.id) == :discard
      assert zone(heros_cape.id) == :discard

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.prompt_type == "choose_knockout_prizes"
      assert prompt.payload["knocked_out_card_instance_ids"] == [target.id]
    end
  end

  describe "Goal 2 Punk Helmet support slice" do
    test "PFL-092 places 4 damage counters on the attacker after damaging an Active Darkness Pokémon" do
      {:ok, game} = create_punk_helmet_attack_game()
      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")

      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      punk_helmet = attach_direct_punk_helmet(game.id, defender)

      assert CardCoverage.summarize("PFL-092").coverage_status == :supported

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :ram)

      assert card(attacker.id).damage == 40
      assert card(defender.id).damage == 20
      assert zone(punk_helmet.id) == :attached

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      assert resolve_event.payload["punk_helmet_damage_counter_count"] == 4
      assert resolve_event.payload["punk_helmet_damage"] == 40
      assert resolve_event.payload["punk_helmet_source_card_instance_ids"] == [punk_helmet.id]
      refute resolve_event.payload["self_knocked_out?"]
    end

    test "PFL-092 still triggers when the attached Darkness Pokémon is Knocked Out by damage" do
      {:ok, game} = create_punk_helmet_attack_game()
      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")

      play_direct_basic_to_bench(game.id, "player_2", "PFL-083", 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      punk_helmet = attach_direct_punk_helmet(game.id, defender)
      {:ok, _defender} = ash_update(defender, :set_damage, %{damage: 190})

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :ram)

      assert zone(defender.id) == :discard
      assert zone(punk_helmet.id) == :discard
      assert card(attacker.id).damage == 40

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.prompt_type == "choose_knockout_prizes"
      assert prompt.payload["knocked_out_card_instance_ids"] == [defender.id]

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      assert resolve_event.payload["punk_helmet_damage_counter_count"] == 4
      assert resolve_event.payload["knocked_out?"]
    end

    test "Jamming Tower suppresses PFL-092 damage counters" do
      {:ok, game} = create_punk_helmet_attack_game()
      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")

      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      attach_direct_punk_helmet(game.id, defender)

      {:ok, jamming_tower} = create_custom_owned_card(game.id, "player_1", "TWM-153", 240)
      {:ok, jamming_tower} = ash_update(jamming_tower, :draw_to_hand, %{position: 20})
      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", jamming_tower.id)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :ram)

      assert card(attacker.id).damage == 0
      assert card(defender.id).damage == 20

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      refute Map.has_key?(resolve_event.payload, "punk_helmet_damage_counter_count")
    end

    test "PFL-092 damage counters can Knock Out the attacking Pokémon" do
      {:ok, game} = create_punk_helmet_attack_game()
      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")

      play_direct_basic_to_bench(game.id, "player_1", "PFL-083", 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      attach_direct_punk_helmet(game.id, defender)
      {:ok, _attacker} = ash_update(attacker, :set_damage, %{damage: 30})

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :ram)

      assert zone(attacker.id) == :discard
      assert active_card(game.id, "player_1").card_id == "PFL-083"

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.prompt_type == "choose_knockout_prizes"
      assert prompt.payload["knocked_out_card_instance_ids"] == [attacker.id]

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      assert resolve_event.payload["punk_helmet_resulting_damage"] == 70
      assert resolve_event.payload["self_knocked_out?"]
    end
  end

  describe "Goal 2 Powerglass support slice" do
    test "SFA-063 prompts at turn end and attaches the chosen Basic Energy from discard" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, Dragapult27431)
      active = active_card(game.id, "player_1")
      {game, powerglass} = attach_powerglass_from_hand(game, "player_1", active)
      energy = discard_custom_basic_energy(game.id, "player_1")

      assert CardCoverage.summarize("SFA-063").coverage_status == :supported

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      assert game.flow_state == :turn_ending_turn
      assert current_turn(game.id).status == :action_window

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.prompt_type == "select_cards"

      assert prompt.payload["choice_key"] ==
               "attach_basic_energy_from_discard_to_attached_active_at_end_of_turn"

      assert prompt.payload["legal_choices"] == [energy.id]
      assert prompt.payload["source_card_instance_id"] == powerglass.id
      assert prompt.payload["target_card_instance_id"] == active.id

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, [energy.id])

      assert game.flow_state == :turn_action_window
      assert current_turn(game.id).active_player_id == "player_2"
      assert current_turn(game.id).status == :action_window
      assert awaiting_prompts(game.id) == []

      assert zone(energy.id) == :attached
      assert card(energy.id).attached_to_card_instance_id == active.id

      cards_moved_event = game.id |> game_events_by_type("cards_moved") |> List.last()
      assert cards_moved_event.payload["reason"] == "tool_effect_resolution"

      assert cards_moved_event.payload["effect_key"] ==
               "attach_basic_energy_from_discard_to_attached_active_at_end_of_turn"
    end

    test "SFA-063 prompts after attack before finishing the turn" do
      {:ok, game} = create_punk_helmet_attack_game()
      attacker = active_card(game.id, "player_1")
      defender = active_card(game.id, "player_2")

      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      {game, _powerglass} = attach_powerglass_from_hand(game, "player_1", attacker)
      energy = discard_custom_basic_energy(game.id, "player_1")

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :ram)

      assert game.flow_state == :turn_attack_resolving
      assert current_turn(game.id).status == :attack_resolving
      assert card(defender.id).damage == 20

      [prompt] = awaiting_prompts(game.id)
      assert prompt.payload["legal_choices"] == [energy.id]
      assert prompt.payload["target_card_instance_id"] == attacker.id

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, [energy.id])

      assert game.flow_state == :turn_action_window
      assert current_turn(game.id).active_player_id == "player_2"
      assert zone(energy.id) == :attached
      assert card(energy.id).attached_to_card_instance_id == attacker.id
    end

    test "Jamming Tower suppresses SFA-063 end-of-turn prompts" do
      {:ok, game} = create_flow_action_window_game_with_decks(Alakazam27147, Dragapult27431)
      active = active_card(game.id, "player_1")
      {game, _powerglass} = attach_powerglass_from_hand(game, "player_1", active)
      energy = discard_custom_basic_energy(game.id, "player_1")

      {:ok, jamming_tower} = create_custom_owned_card(game.id, "player_1", "TWM-153", 230)
      {:ok, jamming_tower} = ash_update(jamming_tower, :draw_to_hand, %{position: 30})
      assert {:ok, game} = Mechanics.play_stadium(game, "player_1", jamming_tower.id)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      assert game.flow_state == :turn_action_window
      assert current_turn(game.id).active_player_id == "player_2"
      assert awaiting_prompts(game.id) == []
      assert zone(energy.id) == :discard
    end
  end

  describe "SCR-118 Fan Call Ability" do
    alias Prizmo.Tcg.Goal1.Decks.Alakazam28438

    test "Fan Call creates a select_cards prompt with Colorless Pokémon ≤100 HP from deck on first turn" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Alakazam28438, Dragapult27431,
          player_1_active_card_id: "SCR-118"
        )

      fan_rotom = active_card(game.id, "player_1")
      assert fan_rotom.card_id == "SCR-118"

      dudunsparce_in_hand =
        CardInstance
        |> Ash.Query.filter(
          game_id == ^game.id and owner_player_id == "player_1" and card_id == "JTG-120" and
            zone == :hand
        )
        |> Ash.read!()

      for card <- dudunsparce_in_hand do
        {:ok, _} = ash_update(card, :shuffle_into_deck, %{})
      end

      assert {:ok, game} =
               Mechanics.use_fan_rotom_fan_call(game, "player_1", fan_rotom.id)

      prompt =
        Prompt
        |> Ash.Query.filter(game_id == ^game.id and player_id == "player_1")
        |> Ash.read!()
        |> List.first()

      assert prompt
      assert prompt.prompt_type == "select_cards"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 3
      assert prompt.payload["choice_key"] == "fan_call"

      legal_choices = prompt.payload["legal_choices"]
      assert length(legal_choices) > 0

      for choice_id <- legal_choices do
        choice_card =
          CardInstance
          |> Ash.Query.filter(id == ^choice_id)
          |> Ash.read_one!()

        assert choice_card.owner_player_id == "player_1"
        assert choice_card.zone == :deck
        assert choice_card.card_id == "JTG-120"
      end

      deck_before = cards_in_zone(game.id, "player_1", :deck)
      hand_before = cards_in_zone(game.id, "player_1", :hand)

      selected = Enum.take(legal_choices, 1)

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, selected)

      for card_id <- selected do
        assert zone(card_id) == :hand
      end

      deck_after = cards_in_zone(game.id, "player_1", :deck)
      hand_after = cards_in_zone(game.id, "player_1", :hand)

      assert length(hand_after) == length(hand_before) + length(selected)
      assert length(deck_after) == length(deck_before) - length(selected)

      assert game_events_by_type(game.id, "ability_used") != []
      assert game_events_by_type(game.id, "cards_moved") != []
      assert game_events_by_type(game.id, "deck_shuffled") != []

      pending_effects =
        PendingEffect
        |> Ash.Query.filter(game_id == ^game.id)
        |> Ash.read!()

      assert Enum.all?(pending_effects, &(&1.status == :completed))
    end

    test "Fan Call is unavailable after being used once" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Alakazam28438, Dragapult27431,
          player_1_active_card_id: "SCR-118"
        )

      fan_rotom = active_card(game.id, "player_1")

      dudunsparce_in_hand =
        CardInstance
        |> Ash.Query.filter(
          game_id == ^game.id and owner_player_id == "player_1" and card_id == "JTG-120" and
            zone == :hand
        )
        |> Ash.read!()

      for card <- dudunsparce_in_hand do
        {:ok, _} = ash_update(card, :shuffle_into_deck, %{})
      end

      assert {:ok, game} =
               Mechanics.use_fan_rotom_fan_call(game, "player_1", fan_rotom.id)

      prompt =
        Prompt
        |> Ash.Query.filter(game_id == ^game.id and player_id == "player_1")
        |> Ash.read!()
        |> List.first()

      legal_choices = prompt.payload["legal_choices"]
      selected = Enum.take(legal_choices, 1)

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", prompt.id, selected)

      assert {:error, {:ability_already_used_this_turn, _, :fan_call}} =
               Mechanics.use_fan_rotom_fan_call(game, "player_1", fan_rotom.id)
    end
  end

  describe "TWM-131 Tatsugiri Attract Customers Ability" do
    test "creates a top-six Supporter prompt and resolves the selected Supporter to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      tatsugiri = promote_custom_tatsugiri_to_active(game.id, "player_1")

      top_cards =
        stage_top_deck_cards(game.id, "player_1", [
          "TWM-143",
          "SCR-133",
          "TWM-129",
          "MEG-114",
          "TWM-143",
          "TWM-129"
        ])

      support_ids =
        top_cards
        |> Enum.filter(&(&1.card_id in ["SCR-133", "MEG-114"]))
        |> Enum.map(& &1.id)

      inspected_ids = Enum.map(top_cards, & &1.id)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      affordance = Enum.find(view.action_affordances, &(&1.key == "attract_customers"))
      assert is_map(affordance)
      assert affordance.source_card_instance_ids == [tatsugiri.id]

      assert {:ok, game} =
               Mechanics.use_tatsugiri_attract_customers(game, "player_1", tatsugiri.id)

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.prompt_type == "select_cards"
      assert prompt.payload["choice_key"] == "attract_customers"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 1
      assert prompt.payload["look_count"] == 6
      assert prompt.payload["inspected_card_count"] == 6
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      assert Enum.sort(prompt.payload["legal_choices"]) == Enum.sort(support_ids)

      assert {:ok, view_with_prompt} = GameView.for_player(game.id, "player_1")
      [view_prompt] = view_with_prompt.prompts

      assert Enum.sort(Enum.map(view_prompt.payload["legal_choice_cards"], & &1.id)) ==
               Enum.sort(support_ids)

      assert Enum.map(view_prompt.payload["inspected_cards"], & &1.id) == inspected_ids

      hand_before = cards_in_zone(game.id, "player_1", :hand)
      deck_before = cards_in_zone(game.id, "player_1", :deck)
      selected = [List.first(support_ids)]

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, selected)

      assert zone(List.first(selected)) == :hand
      assert length(cards_in_zone(game.id, "player_1", :hand)) == length(hand_before) + 1
      assert length(cards_in_zone(game.id, "player_1", :deck)) == length(deck_before) - 1

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "attract_customers"))

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.map(cards_moved_event.payload["revealed_cards"], & &1["instance_id"]) ==
               selected

      assert game_events_by_type(game.id, "deck_shuffled") != []

      assert {:error, {:ability_already_used_this_turn, _, :attract_customers}} =
               Mechanics.use_tatsugiri_attract_customers(game, "player_1", tatsugiri.id)
    end

    test "requires Tatsugiri to be in the Active Spot" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      tatsugiri = play_direct_basic_to_bench(game.id, "player_1", "TWM-131", 4)
      stage_top_deck_cards(game.id, "player_1", ["SCR-133", "TWM-143"])

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      refute Enum.any?(view.action_affordances, &(&1.key == "attract_customers"))

      assert {:error, {:ability_source_not_active, _, :bench}} =
               Mechanics.use_tatsugiri_attract_customers(game, "player_1", tatsugiri.id)
    end

    test "allows selecting no Supporter when the top six have no legal choice" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      tatsugiri = promote_custom_tatsugiri_to_active(game.id, "player_1")

      staged_cards =
        stage_top_deck_cards(game.id, "player_1", [
          "TWM-143",
          "TWM-129",
          "TWM-143",
          "TWM-129",
          "TWM-143",
          "TWM-129",
          "SCR-133"
        ])

      seventh_card = List.last(staged_cards)

      assert {:ok, game} =
               Mechanics.use_tatsugiri_attract_customers(game, "player_1", tatsugiri.id)

      [prompt] = awaiting_prompts(game.id)
      inspected_ids = staged_cards |> Enum.take(6) |> Enum.map(& &1.id)

      assert prompt.payload["choice_key"] == "attract_customers"
      assert prompt.payload["legal_choices"] == []
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      refute seventh_card.id in prompt.payload["legal_choices"]
      refute seventh_card.id in prompt.payload["inspected_card_ids"]

      hand_before = cards_in_zone(game.id, "player_1", :hand)
      deck_before = cards_in_zone(game.id, "player_1", :deck)

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, [])

      assert length(cards_in_zone(game.id, "player_1", :hand)) == length(hand_before)
      assert length(cards_in_zone(game.id, "player_1", :deck)) == length(deck_before)

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "attract_customers"))

      assert cards_moved_event.payload["cards"] == []
      assert cards_moved_event.payload["public_reveal"] == false
      assert game_events_by_type(game.id, "deck_shuffled") != []

      assert {:error, {:ability_already_used_this_turn, _, :attract_customers}} =
               Mechanics.use_tatsugiri_attract_customers(game, "player_1", tatsugiri.id)
    end
  end

  describe "TEF-081 Iron Crown ex" do
    test "Cobalt Command boosts Future Pokémon except Iron Crown ex" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      iron_leaves = promote_custom_basic_to_active(game.id, "player_1", "TEF-025")
      defender = active_card(game.id, "player_2")

      attack = %{
        damage: 100,
        effect: %{type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active}
      }

      assert {:ok, 100} = AttackDamage.damage_for(iron_leaves, defender, attack)

      iron_crown = play_direct_basic_to_bench(game.id, "player_1", "TEF-081", 2)

      assert {:ok, 120} = AttackDamage.damage_for(iron_leaves, defender, attack)
      assert {:ok, 100} = AttackDamage.damage_for(iron_crown, defender, attack)
    end

    test "Twin Shotels damages two chosen opponent Pokémon and ignores target effects" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147,
          player_2_active_card_id: "ASC-142"
        )

      attacker = promote_custom_basic_to_active(game.id, "player_1", "TEF-081")
      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      attach_direct_basic_energy(game.id, "player_1", attacker, 3)

      defender = active_card(game.id, "player_2")
      tera_bench = play_direct_basic_to_bench(game.id, "player_2", "TEF-025", 1)
      unselected_bench = play_direct_basic_to_bench(game.id, "player_2", "PRE-035", 2)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :twin_shotels)
      assert game.flow_state == :turn_attack_declared

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      assert view.current_turn.pending_attack_requires_opponent_pokemon_damage_targets

      assert Enum.sort(
               Enum.map(view.current_turn.pending_attack_opponent_pokemon_damage_choices, & &1.id)
             ) ==
               Enum.sort([defender.id, tera_bench.id, unselected_bench.id])

      assert {:error, {:opponent_pokemon_damage_requires_targets, 2}} =
               Mechanics.resolve_declared_attack(game, "player_1", %{})

      assert {:ok, _game} =
               Mechanics.resolve_declared_attack(game, "player_1", %{
                 opponent_pokemon_damage_target_card_instance_ids: [defender.id, tera_bench.id]
               })

      assert card(defender.id).damage == 50
      assert card(tera_bench.id).damage == 50
      assert card(unselected_bench.id).damage == 0

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()

      assert resolve_event.payload["effect_type"] ==
               "damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects"

      assert Enum.sort(resolve_event.payload["opponent_pokemon_damage_target_card_instance_ids"]) ==
               Enum.sort([defender.id, tera_bench.id])

      assert Enum.all?(resolve_event.payload["opponent_pokemon_damage_results"], fn result ->
               result["damage"] == 50 and result["damage_prevented?"] == false and
                 result["damage_ignored_effects_on_target?"] == true
             end)
    end

    test "Twin Shotels auto-targets when the opponent has at most two Pokémon in play" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147,
          player_2_active_card_id: "ASC-142"
        )

      attacker = promote_custom_basic_to_active(game.id, "player_1", "TEF-081")
      attach_direct_basic_energy(game.id, "player_1", attacker, 1)
      attach_direct_basic_energy(game.id, "player_1", attacker, 2)
      attach_direct_basic_energy(game.id, "player_1", attacker, 3)

      defender = active_card(game.id, "player_2")
      bench = play_direct_basic_to_bench(game.id, "player_2", "PRE-035", 1)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :twin_shotels)

      assert game.flow_state == :turn_action_window
      assert game.active_player_id == "player_2"
      assert card(defender.id).damage == 50
      assert card(bench.id).damage == 50
    end
  end

  describe "SSP-175 Dusk Ball" do
    test "creates a bottom-seven Pokémon prompt and resolves the selected Pokémon to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      dusk_ball = move_owned_or_custom_card_to_hand(game.id, "player_1", "SSP-175", 1)

      bottom_cards =
        stage_bottom_deck_cards(game.id, "player_1", [
          "SCR-133",
          "TWM-143",
          "TWM-129",
          "POR-071",
          "TWM-128",
          "MEG-131",
          "SCR-133"
        ])

      pokemon_ids =
        bottom_cards
        |> Enum.filter(&(&1.card_id in ["TWM-129", "TWM-128"]))
        |> Enum.map(& &1.id)

      inspected_ids = Enum.map(bottom_cards, & &1.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", dusk_ball.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.prompt_type == "select_cards"
      assert prompt.payload["choice_key"] == "search_bottom_7_for_pokemon_to_hand"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 1
      assert prompt.payload["look_count"] == 7
      assert prompt.payload["deck_slice_position"] == "bottom"
      assert prompt.payload["inspected_card_count"] == 7
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      assert Enum.sort(prompt.payload["legal_choices"]) == Enum.sort(pokemon_ids)

      assert {:ok, view_with_prompt} = GameView.for_player(game.id, "player_1")
      [view_prompt] = view_with_prompt.prompts

      assert Enum.sort(Enum.map(view_prompt.payload["legal_choice_cards"], & &1.id)) ==
               Enum.sort(pokemon_ids)

      assert Enum.map(view_prompt.payload["inspected_cards"], & &1.id) == inspected_ids

      hand_before = cards_in_zone(game.id, "player_1", :hand)
      deck_before = cards_in_zone(game.id, "player_1", :deck)
      selected = [List.first(pokemon_ids)]

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, selected)

      assert zone(List.first(selected)) == :hand
      assert zone(dusk_ball.id) == :discard
      assert length(cards_in_zone(game.id, "player_1", :hand)) == length(hand_before) + 1
      assert length(cards_in_zone(game.id, "player_1", :deck)) == length(deck_before) - 1

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "search_bottom_7_for_pokemon_to_hand"))

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.map(cards_moved_event.payload["revealed_cards"], & &1["instance_id"]) ==
               selected

      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "inspects only the bottom seven and allows selecting no Pokémon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      dusk_ball = move_owned_or_custom_card_to_hand(game.id, "player_1", "SSP-175", 1)
      [top_pokemon] = stage_top_deck_cards(game.id, "player_1", ["TWM-129"])

      bottom_cards =
        stage_bottom_deck_cards(game.id, "player_1", [
          "SCR-133",
          "TWM-143",
          "POR-071",
          "MEG-131",
          "SCR-133",
          "TWM-143",
          "POR-071"
        ])

      assert {:ok, game} = Mechanics.play_card(game, "player_1", dusk_ball.id, %{})

      [prompt] = awaiting_prompts(game.id)
      inspected_ids = Enum.map(bottom_cards, & &1.id)

      assert prompt.payload["legal_choices"] == []
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      refute top_pokemon.id in prompt.payload["legal_choices"]
      refute top_pokemon.id in prompt.payload["inspected_card_ids"]

      hand_before = cards_in_zone(game.id, "player_1", :hand)
      deck_before = cards_in_zone(game.id, "player_1", :deck)

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, [])

      assert length(cards_in_zone(game.id, "player_1", :hand)) == length(hand_before)
      assert length(cards_in_zone(game.id, "player_1", :deck)) == length(deck_before)

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "search_bottom_7_for_pokemon_to_hand"))

      assert cards_moved_event.payload["cards"] == []
      assert cards_moved_event.payload["public_reveal"] == false
      assert game_events_by_type(game.id, "deck_shuffled") != []
    end
  end

  describe "SCR-114 Hoothoot and SCR-115 Noctowl support" do
    test "Hoothoot Triple Stab scales damage by heads count" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "SCR-114", 200)
      defender = active_card(game.id, "player_2")

      assert {:ok, attack} = CardCatalog.fetch_attack(attacker.card_id, :triple_stab)
      assert attack.damage == 0
      assert {:ok, 20} = AttackDamage.damage_for(attacker, defender, attack, %{heads_count: 2})
    end

    test "Noctowl Jewel Seeker appears after evolving with Tera in play and resolves a Trainer search prompt" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      assert {:ok, game} = Mechanics.pass_turn(game, "player_2")

      current_turn_number = current_turn(game.id).turn_number

      {:ok, hoothoot} = create_custom_owned_card(game.id, "player_1", "SCR-114", 200)
      {:ok, hoothoot} = ash_update(hoothoot, :draw_to_hand, %{position: 20})

      {:ok, hoothoot} =
        ash_update(hoothoot, :play_to_bench, %{
          position: 4,
          turn_entered_play: current_turn_number - 1
        })

      {:ok, tera_pokemon} = create_custom_owned_card(game.id, "player_1", "TWM-025", 201)
      {:ok, tera_pokemon} = ash_update(tera_pokemon, :draw_to_hand, %{position: 21})

      {:ok, _tera_pokemon} =
        ash_update(tera_pokemon, :play_to_bench, %{
          position: 5,
          turn_entered_play: current_turn_number - 1
        })

      {:ok, noctowl} = create_custom_owned_card(game.id, "player_1", "SCR-115", 202)
      {:ok, noctowl} = ash_update(noctowl, :draw_to_hand, %{position: 9})

      assert {:ok, game} = Mechanics.evolve_from_hand(game, "player_1", noctowl.id, hoothoot.id)

      assert zone(noctowl.id) == :bench

      evolved_noctowl = card(noctowl.id)
      assert evolved_noctowl.evolves_from_card_instance_id == hoothoot.id

      assert {:ok, view} = GameView.for_player(game.id, "player_1")

      jewel_seeker = Enum.find(view.action_affordances, &(&1.key == "jewel_seeker"))
      assert is_map(jewel_seeker)
      assert jewel_seeker.source_card_instance_ids == [noctowl.id]

      assert {:ok, game} = Mechanics.use_noctowl_jewel_seeker(game, "player_1", noctowl.id)

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "jewel_seeker"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 2

      legal_choices = prompt.payload["legal_choices"]
      assert length(legal_choices) > 0

      for choice_id <- legal_choices do
        choice_card = card(choice_id)

        assert choice_card.owner_player_id == "player_1"
        assert choice_card.zone == :deck
        assert {:ok, %{supertype: :trainer}} = CardCatalog.fetch(choice_card.card_id)
      end

      hand_before = cards_in_zone(game.id, "player_1", :hand)
      deck_before = cards_in_zone(game.id, "player_1", :deck)
      selected = Enum.take(legal_choices, 2)

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_1", prompt.id, selected)

      for card_id <- selected do
        assert zone(card_id) == :hand
      end

      hand_after = cards_in_zone(game.id, "player_1", :hand)
      deck_after = cards_in_zone(game.id, "player_1", :deck)

      assert length(hand_after) == length(hand_before) + length(selected)
      assert length(deck_after) == length(deck_before) - length(selected)

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(&(&1.payload["effect_key"] == "jewel_seeker"))

      assert cards_moved_event.payload["public_reveal"] == true
      assert length(cards_moved_event.payload["revealed_cards"]) == length(selected)

      assert {:error, {:ability_already_used_this_turn, _, :jewel_seeker}} =
               Mechanics.use_noctowl_jewel_seeker(game, "player_1", noctowl.id)
    end
  end

  describe "TWM-112 Cornerstone Mask Ogerpon ex support" do
    test "Tera bench protection and Cornerstone Stance prevent attack damage only when appropriate" do
      {:ok, game} = create_flow_action_window_game()
      current_turn_number = current_turn(game.id).turn_number

      {:ok, target} = create_custom_owned_card(game.id, "player_2", "TWM-112", 200)
      {:ok, target} = ash_update(target, :draw_to_hand, %{position: 20})

      {:ok, target} =
        ash_update(target, :play_to_bench, %{position: 4, turn_entered_play: current_turn_number})

      assert {:ok, _game} = Mechanics.resolve_attack_damage(game, "player_1", target.id, 120)
      assert card(target.id).damage == 0

      player_2_active = active_card(game.id, "player_2")

      assert {:ok, _player_2_active} =
               ash_update(player_2_active, :move_active_to_bench, %{position: 2, status: nil})

      assert {:ok, _target} =
               ash_update(card(target.id), :promote_to_active, %{position: 1, status: nil})

      player_1_active = active_card(game.id, "player_1")

      assert {:ok, _player_1_active} =
               ash_update(player_1_active, :move_active_to_bench, %{position: 2, status: nil})

      {:ok, no_ability_attacker} = create_custom_owned_card(game.id, "player_1", "PRE-035", 201)
      {:ok, no_ability_attacker} = ash_update(no_ability_attacker, :draw_to_hand, %{position: 21})

      {:ok, no_ability_attacker} =
        ash_update(no_ability_attacker, :play_to_bench, %{
          position: 4,
          turn_entered_play: current_turn_number
        })

      assert {:ok, _no_ability_attacker} =
               ash_update(no_ability_attacker, :promote_to_active, %{position: 1, status: nil})

      assert {:ok, %{abilities: abilities}} = CardCatalog.fetch(no_ability_attacker.card_id)
      assert abilities == %{}

      assert {:ok, _game} = Mechanics.resolve_attack_damage(game, "player_1", target.id, 50)
      assert card(target.id).damage == 50

      assert {:ok, _target} = ash_update(card(target.id), :set_damage, %{damage: 0})

      assert {:ok, _no_ability_attacker} =
               ash_update(active_card(game.id, "player_1"), :move_active_to_bench, %{
                 position: 5,
                 status: nil
               })

      {:ok, ability_attacker} = create_custom_owned_card(game.id, "player_1", "TWM-025", 202)
      {:ok, ability_attacker} = ash_update(ability_attacker, :draw_to_hand, %{position: 22})

      {:ok, ability_attacker} =
        ash_update(ability_attacker, :play_to_bench, %{
          position: 6,
          turn_entered_play: current_turn_number
        })

      assert {:ok, _ability_attacker} =
               ash_update(ability_attacker, :promote_to_active, %{position: 1, status: nil})

      assert {:ok, %{abilities: abilities}} = CardCatalog.fetch(ability_attacker.card_id)
      assert map_size(abilities) > 0

      assert {:ok, _game} = Mechanics.resolve_attack_damage(game, "player_1", target.id, 140)
      assert card(target.id).damage == 0

      prevention_event = game.id |> game_events_by_type("resolve_attack_damage") |> List.last()
      assert prevention_event.payload["damage_prevented?"] == true

      assert prevention_event.payload["attack_prevention_source_effect_id"] ==
               "cornerstone_stance"
    end
  end

  describe "ASC-121 Koraidon ex support" do
    test "Orichalcum Fang checks the opponent's previous-turn knockout and Impact Blow sets its lock marker" do
      {:ok, game} = create_flow_action_window_game()

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "ASC-121", 210)
      defender = active_card(game.id, "player_2")

      assert {:ok, orichalcum_fang} = CardCatalog.fetch_attack(attacker.card_id, :orichalcum_fang)
      assert {:ok, impact_blow} = CardCatalog.fetch_attack(attacker.card_id, :impact_blow)

      assert orichalcum_fang.damage == 50
      assert {:ok, 50} = AttackDamage.damage_for(attacker, defender, orichalcum_fang)
      assert impact_blow.damage == 200
      assert {:ok, 200} = AttackDamage.damage_for(attacker, defender, impact_blow)

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")

      current_turn_number = current_turn(game.id).turn_number

      {:ok, knocked_out_target} = create_custom_owned_card(game.id, "player_1", "PRE-035", 211)
      {:ok, knocked_out_target} = ash_update(knocked_out_target, :draw_to_hand, %{position: 20})

      {:ok, knocked_out_target} =
        ash_update(knocked_out_target, :play_to_bench, %{
          position: 4,
          turn_entered_play: current_turn_number
        })

      assert {:ok, %{hp: hp}} = CardCatalog.fetch(knocked_out_target.card_id)
      assert is_integer(hp) and hp > 10

      assert {:ok, _knocked_out_target} =
               ash_update(knocked_out_target, :set_damage, %{damage: hp - 10})

      assert {:ok, game} =
               Mechanics.resolve_attack_damage(game, "player_2", knocked_out_target.id, 10)

      assert [prize_prompt] = awaiting_prompts(game.id)
      prize_choice = List.first(prize_prompt.payload["legal_choices"])

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_2", prize_prompt.id, [prize_choice])

      assert {:ok, game} = Mechanics.pass_turn(game, "player_2")

      assert {:ok, 170} = AttackDamage.damage_for(attacker, defender, orichalcum_fang)

      assert {:ok, %{effect_type: "attacker_cannot_attack_next_turn"}} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 impact_blow,
                 %{}
               )

      updated_attacker = card(attacker.id)

      assert is_map(
               Map.get(updated_attacker.markers, "cannot_attack_next_turn") ||
                 Map.get(updated_attacker.markers, :cannot_attack_next_turn)
             )
    end
  end

  describe "JTG-121 Dudunsparce ex support" do
    test "Tenacious Tail counts only opponent Pokémon ex in play, and Destructive Drill is executable" do
      {:ok, game} =
        create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147,
          player_2_active_card_id: "JTG-120"
        )

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "JTG-121", 200)
      assert cards_in_zone(game.id, "player_2", :bench) == []

      current_turn_number = current_turn(game.id).turn_number

      {:ok, opponent_bench_ex} = create_custom_owned_card(game.id, "player_2", "SFA-039", 201)
      {:ok, opponent_bench_ex} = ash_update(opponent_bench_ex, :draw_to_hand, %{position: 20})

      {:ok, _opponent_bench_ex} =
        ash_update(opponent_bench_ex, :play_to_bench, %{
          position: 4,
          turn_entered_play: current_turn_number
        })

      {:ok, second_opponent_bench_ex} =
        create_custom_owned_card(game.id, "player_2", "ASC-142", 202)

      {:ok, second_opponent_bench_ex} =
        ash_update(second_opponent_bench_ex, :draw_to_hand, %{position: 21})

      {:ok, _second_opponent_bench_ex} =
        ash_update(second_opponent_bench_ex, :play_to_bench, %{
          position: 5,
          turn_entered_play: current_turn_number
        })

      {:ok, opponent_bench_non_ex} = create_custom_owned_card(game.id, "player_2", "PRE-035", 203)

      {:ok, opponent_bench_non_ex} =
        ash_update(opponent_bench_non_ex, :draw_to_hand, %{position: 22})

      {:ok, _opponent_bench_non_ex} =
        ash_update(opponent_bench_non_ex, :play_to_bench, %{
          position: 6,
          turn_entered_play: current_turn_number
        })

      defender = active_card(game.id, "player_2")

      assert {:ok, tenacious_tail} = CardCatalog.fetch_attack(attacker.card_id, :tenacious_tail)
      assert tenacious_tail.damage == 0
      assert {:ok, 120} = AttackDamage.damage_for(attacker, defender, tenacious_tail)

      assert {:ok, destructive_drill} =
               CardCatalog.fetch_attack(attacker.card_id, :destructive_drill)

      assert destructive_drill.damage == 150
      assert {:ok, 150} = AttackDamage.damage_for(attacker, defender, destructive_drill)

      assert {:ok, %{}} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 destructive_drill,
                 %{}
               )
    end
  end

  describe "CRI-061 Metagross support" do
    test "Metallic Hammer optionally discards 3 attached Metal Energy for 300 damage" do
      assert CardCoverage.summarize("CRI-061").coverage_status == :supported

      assert {:ok, bounce_back} = CardCatalog.fetch_attack("CRI-061", :bounce_back)
      assert bounce_back.damage == 60
      assert bounce_back.cost == [:metal]

      assert bounce_back.effect == %{
               type: :switch_opponent_active_with_bench_chosen_by_opponent
             }

      assert {:ok, metallic_hammer} = CardCatalog.fetch_attack("CRI-061", :metallic_hammer)
      assert metallic_hammer.damage == 150
      assert metallic_hammer.cost == [:metal, :metal, :metal, :colorless]

      assert metallic_hammer.effect == %{
               type: :discard_attached_energy_for_bonus_damage,
               energy_type: :metal,
               discard_count: 3,
               bonus_damage: 150
             }

      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      attacker = promote_custom_card_to_active(game.id, "player_1", "CRI-061")
      defender = promote_custom_card_to_active(game.id, "player_2", "TWM-130")

      metal_energies =
        for position <- 1..4 do
          attach_direct_energy(game.id, "player_1", attacker, "MEE-008", position)
        end

      discarded_energy_ids = metal_energies |> Enum.take(3) |> Enum.map(& &1.id)

      assert {:ok, 150} = AttackDamage.damage_for(attacker, defender, metallic_hammer)

      assert {:ok, 300} =
               AttackDamage.damage_for(attacker, defender, metallic_hammer, %{
                 discarded_energy_card_instance_ids: discarded_energy_ids
               })

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :metallic_hammer)
      assert game.flow_state == :turn_attack_declared

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      assert view.current_turn.pending_attack_requires_discarded_energy

      assert {:ok, _game} =
               Mechanics.resolve_declared_attack(game, "player_1", %{
                 discarded_energy_card_instance_ids: discarded_energy_ids
               })

      assert card(defender.id).damage == 300
      assert Enum.all?(discarded_energy_ids, &(zone(&1) == :discard))
      assert zone(List.last(metal_energies).id) == :attached

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      assert resolve_event.payload["effect_type"] == "discard_attached_energy_for_bonus_damage"
      assert resolve_event.payload["damage"] == 300
      assert resolve_event.payload["bonus_damage_applied?"]
      assert resolve_event.payload["discarded_energy_count"] == 3

      assert Enum.sort(resolve_event.payload["discarded_energy_card_instance_ids"]) ==
               Enum.sort(discarded_energy_ids)
    end

    test "Bounce Back prompts the opponent to choose the new Active Pokémon" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      attacker = promote_custom_card_to_active(game.id, "player_1", "CRI-061")
      defender = promote_custom_card_to_active(game.id, "player_2", "TWM-130")

      attach_direct_energy(game.id, "player_1", attacker, "MEE-008", 1)

      chosen_bench = play_direct_basic_to_bench(game.id, "player_2", "PRE-035", 1)
      other_bench = play_direct_basic_to_bench(game.id, "player_2", "PFL-083", 2)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :bounce_back)
      assert game.flow_state == :turn_attack_resolving

      assert card(defender.id).damage == 60
      assert active_card(game.id, "player_2").id == defender.id

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.payload["choice_key"] == "bounce_back_choose_new_active"
      assert chosen_bench.id in prompt.payload["legal_choices"]
      assert other_bench.id in prompt.payload["legal_choices"]

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()

      assert resolve_event.payload["effect_type"] ==
               "switch_opponent_active_with_bench_chosen_by_opponent"

      assert resolve_event.payload["switch_prompt_created?"]
      assert resolve_event.payload["switch_legal_choice_count"] >= 2

      [pending_effect] = pending_effects(game.id)
      assert pending_effect.source_card_id == "CRI-061"
      assert pending_effect.current_player_id == "player_2"

      assert {:ok, _game} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [chosen_bench.id])

      assert active_card(game.id, "player_2").id == chosen_bench.id
      assert zone(defender.id) == :bench
      assert zone(other_bench.id) == :bench

      cards_moved_event = game.id |> game_events_by_type("cards_moved") |> List.last()
      assert cards_moved_event.player_id == "player_2"
      assert cards_moved_event.payload["effect_key"] == "bounce_back_choose_new_active"
    end
  end

  describe "DRI-016 Applin support" do
    test "DRI-016 Applin Mini Drain heals itself after dealing damage" do
      assert CardCoverage.summarize("DRI-016").coverage_status == :supported

      assert {:ok, mini_drain} = CardCatalog.fetch_attack("DRI-016", :mini_drain)
      assert mini_drain.damage == 10
      assert mini_drain.cost == [:grass]

      assert mini_drain.effect == %{
               type: :heal_self_after_damage,
               heal_damage: 10
             }

      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      attacker = promote_custom_basic_to_active(game.id, "player_1", "DRI-016")
      {:ok, attacker} = ash_update(attacker, :set_damage, %{damage: 30})

      {:ok, grass_energy} = create_custom_owned_card(game.id, "player_1", "MEE-001", 260)
      {:ok, grass_energy} = ash_update(grass_energy, :draw_to_hand, %{position: 60})

      {:ok, _grass_energy} =
        ash_update(grass_energy, :attach, %{
          attached_to_card_instance_id: attacker.id,
          position: 1
        })

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :mini_drain)

      assert card(attacker.id).damage == 20

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()
      assert resolve_event.payload["effect_type"] == "heal_self_after_damage"
      assert resolve_event.payload["self_healed_card_instance_id"] == attacker.id
      assert resolve_event.payload["requested_self_heal"] == 10
      assert resolve_event.payload["self_healed_damage"] == 10
      assert resolve_event.payload["self_resulting_damage"] == 20
      assert resolve_event.payload["self_heal_applied?"]
    end
  end

  describe "DRI-127 Team Rocket's Murkrow support" do
    test "Deceit searches a Supporter from deck to hand" do
      assert CardCoverage.summarize("DRI-127").coverage_status == :supported

      assert {:ok, deceit} = CardCatalog.fetch_attack("DRI-127", :deceit)
      assert deceit.cost == [:colorless]
      assert deceit.effect == %{type: :search_supporter_to_hand}

      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      attacker = promote_custom_basic_to_active(game.id, "player_1", "DRI-127")
      attach_direct_energy(game.id, "player_1", attacker, "MEE-007", 1)

      {:ok, supporter} = create_custom_owned_card(game.id, "player_1", "DRI-171", 260)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :deceit)

      assert [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_1"
      assert prompt.payload["choice_key"] == "search_supporter_to_hand"
      assert prompt.payload["min"] == 1
      assert prompt.payload["max"] == 1
      assert supporter.id in prompt.payload["legal_choices"]

      assert {:ok, _game} = Mechanics.choose_prompt(game, "player_1", prompt.id, [supporter.id])
      assert zone(supporter.id) == :hand

      completed_event = game.id |> game_events_by_type("attack_effect_completed") |> List.last()
      assert completed_event.payload["effect_key"] == "search_supporter_to_hand"
      assert completed_event.payload["selected_card_instance_id"] == supporter.id
    end

    test "Torment locks only the chosen defender attack on the opponent's next turn" do
      assert {:ok, torment} = CardCatalog.fetch_attack("DRI-127", :torment)
      assert torment.damage == 30
      assert torment.cost == [:darkness, :colorless]

      assert torment.effect == %{
               type: :defending_pokemon_cannot_use_selected_attack_next_turn
             }

      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      attacker = promote_custom_basic_to_active(game.id, "player_1", "DRI-127")
      defender = promote_custom_basic_to_active(game.id, "player_2", "DRI-127")

      attach_direct_energy(game.id, "player_1", attacker, "MEE-007", 1)
      attach_direct_energy(game.id, "player_1", attacker, "MEE-007", 2)
      attach_direct_energy(game.id, "player_2", defender, "MEE-007", 1)

      assert {:ok, game} = Mechanics.declare_attack(game, "player_1", :torment)

      assert {:ok, view} = GameView.for_player(game.id, "player_1")
      assert view.current_turn.pending_attack_requires_blocked_attack

      assert Enum.map(view.current_turn.pending_attack_blocked_attack_choices, & &1.attack_id) ==
               [
                 "deceit",
                 "torment"
               ]

      assert {:error, :blocked_attack_requires_choice} =
               Mechanics.resolve_declared_attack(game, "player_1", %{})

      assert {:ok, game} =
               Mechanics.resolve_declared_attack(game, "player_1", %{blocked_attack_id: "torment"})

      resolve_event = game.id |> game_events_by_type("resolve_declared_attack") |> List.last()

      assert resolve_event.payload["effect_type"] ==
               "defending_pokemon_cannot_use_selected_attack_next_turn"

      assert resolve_event.payload["blocked_card_instance_id"] == defender.id
      assert resolve_event.payload["blocked_attack_id"] == "torment"
      assert resolve_event.payload["attack_lock_applied?"]

      assert {:ok, game} = Prizmo.TcgEngine.Flow.Interpreter.stabilize(game)
      assert current_turn(game.id).active_player_id == "player_2"
      assert current_turn(game.id).status == :action_window

      assert {:error, {:attacker_cannot_use_attack_this_turn, :torment}} =
               Mechanics.declare_attack(game, "player_2", :torment)

      assert {:ok, _game} = Mechanics.declare_attack(game, "player_2", :deceit)
    end
  end

  describe "POR-020 Staryu and POR-021 Mega Starmie ex support" do
    test "Staryu Water Gun and Mega Starmie ex attacks are executable" do
      assert CardCoverage.summarize("POR-020").coverage_status == :supported
      assert CardCoverage.summarize("POR-021").coverage_status == :supported

      assert {:ok, water_gun} = CardCatalog.fetch_attack("POR-020", :water_gun)
      assert water_gun.damage == 20
      assert water_gun.cost == [:water]

      assert {:ok, jetting_blow} = CardCatalog.fetch_attack("POR-021", :jetting_blow)
      assert jetting_blow.damage == 120
      assert jetting_blow.cost == [:water]

      assert jetting_blow.effect == %{
               type: :damage_opponent_bench,
               bench_damage: 50
             }

      assert {:ok, nebula_beam} = CardCatalog.fetch_attack("POR-021", :nebula_beam)
      assert nebula_beam.damage == 210
      assert nebula_beam.cost == [:colorless, :colorless, :colorless]

      assert nebula_beam.effect == %{
               type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active
             }
    end

    test "Jetting Blow damages one opponent Benched Pokémon and respects Tera Bench protection" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "POR-021", 230)
      defender = active_card(game.id, "player_2")

      assert {:ok, jetting_blow} = CardCatalog.fetch_attack(attacker.card_id, :jetting_blow)
      assert {:ok, 120} = AttackDamage.damage_for(attacker, defender, jetting_blow)

      assert {:ok,
              %{
                effect_type: "damage_opponent_bench",
                requested_bench_damage: 50,
                bench_damage: 0,
                bench_damage_applied?: false
              }} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 jetting_blow,
                 %{}
               )

      current_turn_number = current_turn(game.id).turn_number

      {:ok, first_bench_target} = create_custom_owned_card(game.id, "player_2", "PRE-035", 231)
      {:ok, first_bench_target} = ash_update(first_bench_target, :draw_to_hand, %{position: 20})

      {:ok, first_bench_target} =
        ash_update(first_bench_target, :play_to_bench, %{
          position: 1,
          turn_entered_play: current_turn_number
        })

      {:ok, tera_bench_target} = create_custom_owned_card(game.id, "player_2", "TWM-112", 232)
      {:ok, tera_bench_target} = ash_update(tera_bench_target, :draw_to_hand, %{position: 21})

      {:ok, tera_bench_target} =
        ash_update(tera_bench_target, :play_to_bench, %{
          position: 2,
          turn_entered_play: current_turn_number
        })

      assert {:error, :bench_damage_requires_target} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 jetting_blow,
                 %{}
               )

      assert {:ok,
              %{
                effect_type: "damage_opponent_bench",
                bench_damage_target_card_instance_id: first_target_id,
                bench_damage: 50,
                bench_resulting_damage: 50,
                bench_knocked_out?: false,
                bench_damage_applied?: true,
                bench_damage_prevented?: false
              }} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 jetting_blow,
                 %{bench_damage_target_card_instance_id: first_bench_target.id}
               )

      assert first_target_id == first_bench_target.id
      assert card(first_bench_target.id).damage == 50

      assert {:ok,
              %{
                effect_type: "damage_opponent_bench",
                bench_damage_target_card_instance_id: tera_target_id,
                bench_damage: 0,
                bench_prevented_damage: 50,
                bench_resulting_damage: 0,
                bench_damage_applied?: false,
                bench_damage_prevented?: true,
                bench_damage_prevention: "tera_bench_protection"
              }} =
               AttackEffects.resolve_after_damage(
                 game.id,
                 "player_1",
                 attacker,
                 defender,
                 jetting_blow,
                 %{bench_damage_target_card_instance_id: tera_bench_target.id}
               )

      assert tera_target_id == tera_bench_target.id
      assert card(tera_bench_target.id).damage == 0
    end
  end

  describe "MEG-094 Mega Mawile ex support" do
    test "Gobble Down and Huge Bite damage follow prize and prior-damage text" do
      assert CardCoverage.summarize("MEG-094").coverage_status == :supported

      assert {:ok, gobble_down} = CardCatalog.fetch_attack("MEG-094", :gobble_down)
      assert gobble_down.damage == 0
      assert gobble_down.cost == [:metal, :metal]

      assert gobble_down.effect == %{
               type: :damage_per_own_prize_taken,
               damage_per_prize: 80
             }

      assert {:ok, huge_bite} = CardCatalog.fetch_attack("MEG-094", :huge_bite)
      assert huge_bite.damage == 260
      assert huge_bite.cost == [:metal, :metal, :colorless]

      assert huge_bite.effect == %{
               type: :base_damage_if_defender_has_damage_counters,
               base_damage: 30
             }

      {:ok, game} =
        create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147,
          player_2_active_card_id: "JTG-120"
        )

      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "MEG-094", 240)
      defender = active_card(game.id, "player_2")

      assert {:ok, 0} = AttackDamage.damage_for(attacker, defender, gobble_down)

      reduce_player_prize_count_to(game.id, "player_1", 4)
      assert {:ok, 160} = AttackDamage.damage_for(attacker, defender, gobble_down)

      reduce_player_prize_count_to(game.id, "player_1", 1)
      assert {:ok, 400} = AttackDamage.damage_for(attacker, defender, gobble_down)

      assert {:ok, 260} = AttackDamage.damage_for(attacker, defender, huge_bite)

      {:ok, damaged_defender} = ash_update(defender, :set_damage, %{damage: 10})
      assert {:ok, 30} = AttackDamage.damage_for(attacker, damaged_defender, huge_bite)
    end
  end

  describe "PRE-086 Regigigas support" do
    test "Jewel Breaker adds damage against the opponent's Active Tera Pokemon" do
      assert CardCoverage.summarize("PRE-086").coverage_status == :supported

      assert {:ok, jewel_breaker} = CardCatalog.fetch_attack("PRE-086", :jewel_breaker)
      assert jewel_breaker.damage == 100
      assert jewel_breaker.cost == [:colorless, :colorless, :colorless, :colorless]

      assert jewel_breaker.effect == %{
               type: :bonus_damage_if_defender_tera_pokemon,
               bonus_damage: 230
             }

      {:ok, tera_game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      {:ok, tera_attacker} = create_custom_owned_card(tera_game.id, "player_1", "PRE-086", 245)
      tera_defender = promote_custom_basic_to_active(tera_game.id, "player_2", "TWM-112")

      assert CardCatalog.tera_pokemon?(tera_defender.card_id)
      assert {:ok, 330} = AttackDamage.damage_for(tera_attacker, tera_defender, jewel_breaker)

      {:ok, non_tera_game} =
        create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      {:ok, non_tera_attacker} =
        create_custom_owned_card(non_tera_game.id, "player_1", "PRE-086", 246)

      non_tera_defender = promote_custom_basic_to_active(non_tera_game.id, "player_2", "JTG-120")

      refute CardCatalog.tera_pokemon?(non_tera_defender.card_id)

      assert {:ok, 100} =
               AttackDamage.damage_for(non_tera_attacker, non_tera_defender, jewel_breaker)
    end
  end

  describe "SFA-039 Pecharunt ex support" do
    test "Irritated Outburst scales with the number of Prize cards the opponent has taken" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      {:ok, attacker} = create_custom_owned_card(game.id, "player_1", "SFA-039", 210)
      defender = active_card(game.id, "player_2")

      assert {:ok, irritated_outburst} =
               CardCatalog.fetch_attack(attacker.card_id, :irritated_outburst)

      assert irritated_outburst.damage == 0
      assert {:ok, 0} = AttackDamage.damage_for(attacker, defender, irritated_outburst)

      reduce_opponent_prize_count_to(game.id, "player_1", 4)
      assert {:ok, 120} = AttackDamage.damage_for(attacker, defender, irritated_outburst)

      reduce_opponent_prize_count_to(game.id, "player_1", 1)
      assert {:ok, 300} = AttackDamage.damage_for(attacker, defender, irritated_outburst)
    end

    test "Subjugating Chains exposes a switch affordance, poisons the promoted target, and is once per turn across copies" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)

      current_turn_number = current_turn(game.id).turn_number
      active_before = active_card(game.id, "player_1")

      {:ok, first_pecharunt} = create_custom_owned_card(game.id, "player_1", "SFA-039", 220)
      {:ok, first_pecharunt} = ash_update(first_pecharunt, :draw_to_hand, %{position: 20})

      {:ok, first_pecharunt} =
        ash_update(first_pecharunt, :play_to_bench, %{
          position: 4,
          turn_entered_play: current_turn_number
        })

      {:ok, second_pecharunt} = create_custom_owned_card(game.id, "player_1", "SFA-039", 221)
      {:ok, second_pecharunt} = ash_update(second_pecharunt, :draw_to_hand, %{position: 21})

      {:ok, second_pecharunt} =
        ash_update(second_pecharunt, :play_to_bench, %{
          position: 5,
          turn_entered_play: current_turn_number
        })

      {:ok, darkness_target} = create_custom_owned_card(game.id, "player_1", "ASC-142", 222)
      {:ok, darkness_target} = ash_update(darkness_target, :draw_to_hand, %{position: 22})

      {:ok, darkness_target} =
        ash_update(darkness_target, :play_to_bench, %{
          position: 6,
          turn_entered_play: current_turn_number
        })

      assert {:ok, view} = GameView.for_player(game.id, "player_1")

      first_affordance =
        Enum.find(view.action_affordances, fn action ->
          action.key == "subjugating_chains" and
            action.source_card_instance_ids == [first_pecharunt.id]
        end)

      second_affordance =
        Enum.find(view.action_affordances, fn action ->
          action.key == "subjugating_chains" and
            action.source_card_instance_ids == [second_pecharunt.id]
        end)

      assert is_map(first_affordance)
      assert is_map(second_affordance)
      assert first_affordance.target_card_instance_ids == [darkness_target.id]
      assert second_affordance.target_card_instance_ids == [darkness_target.id]

      assert {:ok, game} =
               Mechanics.use_pecharunt_ex_subjugating_chains(
                 game,
                 "player_1",
                 first_pecharunt.id,
                 darkness_target.id
               )

      promoted_active = active_card(game.id, "player_1")
      moved_active = card(active_before.id)

      assert promoted_active.id == darkness_target.id
      assert promoted_active.status == :poisoned
      assert moved_active.zone == :bench
      assert moved_active.position == 6

      subjugating_event =
        game.id
        |> game_events_by_type("ability_used")
        |> Enum.find(&(&1.payload["ability_id"] == "subjugating_chains"))

      assert is_map(subjugating_event)
      assert subjugating_event.payload["bench_card_instance_id"] == darkness_target.id
      assert subjugating_event.payload["status_applied"] == true

      assert {:error, {:ability_already_used_this_turn, _, :subjugating_chains}} =
               Mechanics.use_pecharunt_ex_subjugating_chains(
                 game,
                 "player_1",
                 second_pecharunt.id,
                 darkness_target.id
               )

      assert {:ok, next_view} = GameView.for_player(game.id, "player_1")
      refute Enum.any?(next_view.action_affordances, &(&1.key == "subjugating_chains"))
    end
  end

  describe "SSP-174 Drayton" do
    test "creates a top-seven Pokémon/Trainer prompt and resolves one of each to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      drayton = move_owned_or_custom_card_to_hand(game.id, "player_2", "SSP-174", 1)

      top_cards =
        stage_top_deck_cards(game.id, "player_2", [
          "TWM-129",
          "SCR-133",
          "MEE-001",
          "TWM-128",
          "POR-071",
          "MEE-002",
          "MEE-003"
        ])

      legal_ids =
        top_cards
        |> Enum.filter(&(&1.card_id in ["TWM-129", "SCR-133", "TWM-128", "POR-071"]))
        |> Enum.map(& &1.id)

      inspected_ids = Enum.map(top_cards, & &1.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_2", drayton.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.prompt_type == "select_cards"
      assert prompt.payload["choice_key"] == "search_top_7_for_pokemon_and_trainer_to_hand"
      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 2
      assert prompt.payload["look_count"] == 7
      assert prompt.payload["deck_slice_position"] == "top"
      assert prompt.payload["inspected_card_count"] == 7
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      assert Enum.sort(prompt.payload["legal_choices"]) == Enum.sort(legal_ids)

      assert {:ok, view_with_prompt} = GameView.for_player(game.id, "player_2")
      [view_prompt] = view_with_prompt.prompts

      assert Enum.sort(Enum.map(view_prompt.payload["legal_choice_cards"], & &1.id)) ==
               Enum.sort(legal_ids)

      assert Enum.map(view_prompt.payload["inspected_cards"], & &1.id) == inspected_ids

      selected = [List.first(legal_ids), List.last(legal_ids)]
      hand_before = cards_in_zone(game.id, "player_2", :hand)
      deck_before = cards_in_zone(game.id, "player_2", :deck)

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_2", prompt.id, selected)

      assert Enum.all?(selected, &(zone(&1) == :hand))
      assert zone(drayton.id) == :discard
      assert length(cards_in_zone(game.id, "player_2", :hand)) == length(hand_before) + 2
      assert length(cards_in_zone(game.id, "player_2", :deck)) == length(deck_before) - 2

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] == "search_top_7_for_pokemon_and_trainer_to_hand")
        )

      assert cards_moved_event.payload["public_reveal"] == true

      assert Enum.sort(Enum.map(cards_moved_event.payload["revealed_cards"], & &1["instance_id"])) ==
               Enum.sort(selected)

      assert game_events_by_type(game.id, "deck_shuffled") != []
    end

    test "rejects selecting two Pokémon from the top-seven Drayton prompt" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      drayton = move_owned_or_custom_card_to_hand(game.id, "player_2", "SSP-174", 1)

      top_cards =
        stage_top_deck_cards(game.id, "player_2", [
          "TWM-129",
          "TWM-128",
          "SCR-133",
          "POR-071",
          "MEE-001",
          "MEE-002",
          "MEE-003"
        ])

      [pokemon_1, pokemon_2] = Enum.filter(top_cards, &(&1.card_id in ["TWM-129", "TWM-128"]))

      assert {:ok, game} = Mechanics.play_card(game, "player_2", drayton.id, %{})

      [prompt] = awaiting_prompts(game.id)

      assert {:error, {:too_many_search_group_targets, %{kind: :pokemon}, 2, 1}} =
               Mechanics.choose_prompt(game, "player_2", prompt.id, [pokemon_1.id, pokemon_2.id])

      assert zone(pokemon_1.id) == :deck
      assert zone(pokemon_2.id) == :deck
      assert zone(drayton.id) == :discard
      [still_awaiting] = awaiting_prompts(game.id)
      assert still_awaiting.id == prompt.id
    end
  end

  describe "TWM-151 Hassel" do
    test "requires an own Pokémon knockout during the opponent's last turn" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      hassel = move_owned_or_custom_card_to_hand(game.id, "player_2", "TWM-151", 1)

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      play_card_source_ids = if play_card, do: play_card.source_card_instance_ids, else: []
      refute hassel.id in play_card_source_ids

      assert {:error, :hassel_requires_own_pokemon_ko_during_opponents_last_turn} =
               Mechanics.play_card(game, "player_2", hassel.id, %{})

      assert zone(hassel.id) == :hand
    end

    test "creates a top-eight any-card prompt and resolves up to three cards to hand" do
      {:ok, game} = create_flow_action_window_game_with_decks(Dragapult27431, Alakazam27147)
      previous_turn = current_turn(game.id)
      active = active_card(game.id, "player_2")

      assert {:ok, game} = Mechanics.pass_turn(game, "player_1")
      hassel = move_owned_or_custom_card_to_hand(game.id, "player_2", "TWM-151", 1)

      top_cards =
        stage_top_deck_cards(game.id, "player_2", [
          "TWM-129",
          "SCR-133",
          "MEE-001",
          "TWM-128",
          "POR-071",
          "MEE-002",
          "MEE-003",
          "TWM-130"
        ])

      inspected_ids = Enum.map(top_cards, & &1.id)

      assert {:ok, _event} =
               EventLog.write_event_and_snapshot(game.id, :take_knockout_prizes, "player_1", %{
                 turn_id: previous_turn.id,
                 prize_count: 1,
                 taken_prize_card_instance_ids: [],
                 knockouts: [
                   %{
                     knocked_out_player_id: "player_2",
                     knocked_out_card_id: active.card_id,
                     knocked_out_card_instance_id: active.id,
                     prize_count: 1
                   }
                 ]
               })

      assert {:ok, view} = GameView.for_player(game.id, "player_2")
      play_card = Enum.find(view.action_affordances, &(&1.key == "play_card"))
      assert hassel.id in play_card.source_card_instance_ids

      assert {:ok, game} = Mechanics.play_card(game, "player_2", hassel.id, %{})

      [prompt] = awaiting_prompts(game.id)
      assert prompt.player_id == "player_2"
      assert prompt.prompt_type == "select_cards"

      assert prompt.payload["choice_key"] ==
               "search_top_8_for_up_to_3_cards_if_own_pokemon_knocked_out"

      assert prompt.payload["min"] == 0
      assert prompt.payload["max"] == 3
      assert prompt.payload["look_count"] == 8
      assert prompt.payload["deck_slice_position"] == "top"
      assert prompt.payload["inspected_card_count"] == 8
      assert prompt.payload["inspected_card_ids"] == inspected_ids
      assert Enum.sort(prompt.payload["legal_choices"]) == Enum.sort(inspected_ids)

      assert {:ok, view_with_prompt} = GameView.for_player(game.id, "player_2")
      [view_prompt] = view_with_prompt.prompts

      assert Enum.sort(Enum.map(view_prompt.payload["legal_choice_cards"], & &1.id)) ==
               Enum.sort(inspected_ids)

      assert Enum.map(view_prompt.payload["inspected_cards"], & &1.id) == inspected_ids

      selected = Enum.take(inspected_ids, 3)
      hand_before = cards_in_zone(game.id, "player_2", :hand)
      deck_before = cards_in_zone(game.id, "player_2", :deck)

      assert {:ok, game} = Mechanics.choose_prompt(game, "player_2", prompt.id, selected)

      assert Enum.all?(selected, &(zone(&1) == :hand))
      assert zone(hassel.id) == :discard
      assert length(cards_in_zone(game.id, "player_2", :hand)) == length(hand_before) + 3
      assert length(cards_in_zone(game.id, "player_2", :deck)) == length(deck_before) - 3

      cards_moved_event =
        game.id
        |> game_events_by_type("cards_moved")
        |> Enum.find(
          &(&1.payload["effect_key"] ==
              "search_top_8_for_up_to_3_cards_if_own_pokemon_knocked_out")
        )

      refute Map.has_key?(cards_moved_event.payload, "public_reveal")
      refute Map.has_key?(cards_moved_event.payload, "revealed_cards")
      assert game_events_by_type(game.id, "deck_shuffled") != []
    end
  end

  defp create_game do
    Mechanics.create_game([
      {"player_1", Alakazam27147},
      {"player_2", Dragapult27431}
    ])
  end

  defp create_game_with_decks(player_1_deck, player_2_deck, opts) do
    Mechanics.create_game(
      [
        {"player_1", player_1_deck},
        {"player_2", player_2_deck}
      ],
      opts
    )
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
    with {:ok, game} <-
           create_game_with_decks(player_1_deck, player_2_deck,
             rng_seed: Keyword.get(opts, :rng_seed, "test-seed")
           ),
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

  defp create_punk_helmet_attack_game do
    create_flow_action_window_game_with_decks(Alakazam27147, Dragapult27431,
      player_1_active_card_id: "JTG-120",
      player_2_active_card_id: "ASC-142"
    )
  end

  defp attach_direct_basic_energy(game_id, player_id, target_card, position) do
    attach_direct_energy(game_id, player_id, target_card, "MEE-005", position)
  end

  defp attach_direct_energy(game_id, player_id, target_card, energy_card_id, position) do
    {:ok, energy} = create_custom_owned_card(game_id, player_id, energy_card_id, 220 + position)
    {:ok, energy} = ash_update(energy, :draw_to_hand, %{position: 20 + position})

    {:ok, energy} =
      ash_update(energy, :attach, %{
        attached_to_card_instance_id: target_card.id,
        position: position
      })

    energy
  end

  defp attach_direct_punk_helmet(game_id, target_card) do
    {:ok, punk_helmet} =
      create_custom_owned_card(game_id, target_card.owner_player_id, "PFL-092", 230)

    {:ok, punk_helmet} = ash_update(punk_helmet, :draw_to_hand, %{position: 30})

    {:ok, punk_helmet} =
      ash_update(punk_helmet, :attach, %{
        attached_to_card_instance_id: target_card.id,
        position: 1
      })

    punk_helmet
  end

  defp attach_powerglass_from_hand(game, player_id, target_card) do
    {:ok, powerglass} = create_custom_owned_card(game.id, player_id, "SFA-063", 235)
    {:ok, powerglass} = ash_update(powerglass, :draw_to_hand, %{position: 35})
    {:ok, game} = Mechanics.attach_tool(game, player_id, powerglass.id, target_card.id)
    {game, card(powerglass.id)}
  end

  defp discard_custom_basic_energy(game_id, player_id) do
    {:ok, energy} = create_custom_owned_card(game_id, player_id, "MEE-005", 245)

    {:ok, energy} =
      ash_update(energy, :discard, %{
        position: card_count_in_zone(game_id, player_id, :discard) + 1
      })

    energy
  end

  defp play_direct_basic_to_bench(game_id, player_id, card_id, position) do
    {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, 240 + position)
    {:ok, card} = ash_update(card, :draw_to_hand, %{position: 40 + position})

    {:ok, card} =
      ash_update(card, :play_to_bench, %{
        position: position,
        turn_entered_play: current_turn(game_id).turn_number
      })

    card
  end

  defp promote_custom_tatsugiri_to_active(game_id, player_id) do
    existing_active = active_card(game_id, player_id)
    {:ok, _existing_active} = ash_update(existing_active, :move_active_to_bench, %{position: 5})

    {:ok, tatsugiri} = create_custom_owned_card(game_id, player_id, "TWM-131", 240)
    {:ok, tatsugiri} = ash_update(tatsugiri, :draw_to_hand, %{position: 40})

    {:ok, tatsugiri} =
      ash_update(tatsugiri, :play_to_bench, %{
        position: 4,
        turn_entered_play: current_turn(game_id).turn_number
      })

    {:ok, tatsugiri} = ash_update(tatsugiri, :promote_to_active, %{position: 1, status: nil})
    tatsugiri
  end

  defp promote_custom_basic_to_active(game_id, player_id, card_id) do
    existing_active = active_card(game_id, player_id)
    {:ok, _existing_active} = ash_update(existing_active, :move_active_to_bench, %{position: 5})

    {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, 250)
    {:ok, card} = ash_update(card, :draw_to_hand, %{position: 50})

    {:ok, card} =
      ash_update(card, :play_to_bench, %{
        position: 4,
        turn_entered_play: current_turn(game_id).turn_number
      })

    {:ok, card} = ash_update(card, :promote_to_active, %{position: 1, status: nil})
    card
  end

  defp promote_custom_card_to_active(game_id, player_id, card_id) do
    existing_active = active_card(game_id, player_id)
    {:ok, _existing_active} = ash_update(existing_active, :move_active_to_bench, %{position: 5})

    {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, 270)
    {:ok, card} = ash_update(card, :draw_to_hand, %{position: 70})

    {:ok, card} =
      ash_update(card, :choose_active, %{
        position: 1,
        turn_entered_play: current_turn(game_id).turn_number
      })

    card
  end

  defp stage_top_deck_cards(game_id, player_id, card_ids) when is_list(card_ids) do
    card_ids
    |> Enum.with_index(-length(card_ids))
    |> Enum.map(fn {card_id, position} ->
      {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, position)
      card
    end)
  end

  defp stage_bottom_deck_cards(game_id, player_id, card_ids) when is_list(card_ids) do
    max_position =
      game_id
      |> cards_in_zone(player_id, :deck)
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> 0 end)

    card_ids
    |> Enum.with_index(max_position + 1)
    |> Enum.map(fn {card_id, position} ->
      {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, position)
      card
    end)
  end

  defp move_owned_or_custom_card_to_hand(game_id, player_id, card_id, position) do
    case owned_card(game_id, player_id, card_id) do
      %CardInstance{} = card -> move_card_to_hand(card, position)
      nil -> create_custom_card_in_hand(game_id, player_id, card_id, position)
    end
  end

  defp create_custom_card_in_hand(game_id, player_id, card_id, position) do
    {:ok, card} = create_custom_owned_card(game_id, player_id, card_id, 260 + position)
    {:ok, card} = ash_update(card, :draw_to_hand, %{position: position})
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

  defp discard_all_hand_cards_except(game_id, player_id, kept_card_ids) do
    game_id
    |> cards_in_zone(player_id, :hand)
    |> Enum.reject(&(&1.id in kept_card_ids))
    |> Enum.with_index(card_count_in_zone(game_id, player_id, :discard) + 1)
    |> Enum.each(fn {hand_card, position} ->
      {:ok, _discarded} = ash_update(hand_card, :discard, %{position: position})
    end)
  end

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

  defp reduce_player_prize_count_to(game_id, player_id, target_count) do
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

  defp reduce_opponent_prize_count_to(game_id, player_id, target_count) do
    reduce_player_prize_count_to(game_id, player_id, target_count)
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

  defp create_custom_owned_card(game_id, player_id, card_id, position) do
    player =
      GamePlayer
      |> Ash.Query.filter(game_id == ^game_id and player_id == ^player_id)
      |> Ash.read_one!()

    ash_create(CardInstance, :create, %{
      game_id: game_id,
      game_player_id: player.id,
      owner_player_id: player_id,
      instance_id: Ecto.UUID.generate(),
      card_id: card_id,
      position: position,
      damage: 0,
      markers: %{}
    })
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

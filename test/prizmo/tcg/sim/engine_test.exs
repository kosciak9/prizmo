defmodule Prizmo.Tcg.Sim.EngineTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Sim.Action
  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.Tcg.Sim.Decks.Alakazam27147
  alias Prizmo.Tcg.Sim.Decks.Dragapult27431
  alias Prizmo.Tcg.Sim.Engine
  alias Prizmo.Tcg.Sim.Invariants

  @dragapult_setup_deck [
    "TWM-128",
    "ASC-016",
    "MEE-005",
    "TWM-129",
    "TWM-130",
    "MEG-119",
    "TEF-144",
    "POR-081"
  ]
  @alakazam_setup_deck [
    "MEG-054",
    "JTG-120",
    "MEE-005",
    "MEG-055",
    "MEG-056",
    "PFL-087",
    "TEF-144",
    "POR-081"
  ]

  test "builds the two fixed decklists as 60-card decks" do
    assert length(Dragapult27431.card_ids()) == 60
    assert length(Alakazam27147.card_ids()) == 60
  end

  test "starts deterministic game and advances through first lifecycle actions" do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert state.game_lifecycle == :not_started

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert state.game_lifecycle == :setup

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})
    assert :ok = Invariants.validate_card_accounting(state)

    dreepy = card_in_hand(state, :dragapult, "TWM-128")
    abra = card_in_hand(state, :alakazam, "MEG-054")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             })

    budew = card_in_hand(state, :dragapult, "ASC-016")
    dunsparce = card_in_hand(state, :alakazam, "JTG-120")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_setup_bench_from_hand,
               player_id: :dragapult,
               params: %{instance_id: budew.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_setup_bench_from_hand,
               player_id: :alakazam,
               params: %{instance_id: dunsparce.instance_id}
             })

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :place_prizes})
    assert :ok = Invariants.validate_card_accounting(state)

    assert length(state.players.dragapult.prizes) == 6
    assert length(state.players.alakazam.prizes) == 6
    assert length(state.players.dragapult.deck) == 47
    assert length(state.players.alakazam.deck) == 47

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :complete_setup})
    assert state.game_lifecycle == :in_progress
    assert state.turn_lifecycle == :start_turn

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert state.turn_lifecycle == :draw_for_turn
    assert length(state.players.dragapult.hand) == 6

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})
    assert state.turn_lifecycle == :action_window
  end

  test "setup actions can be undone and redone without losing card accounting" do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert :ok = Invariants.validate_card_accounting(state)
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})

    assert length(state.players.dragapult.hand) == 7
    assert length(state.players.alakazam.hand) == 7
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:ok, undone} = Engine.undo(state)
    assert state_without_history(undone).players.dragapult.hand == []
    assert length(undone.players.dragapult.deck) == 60
    assert :ok = Invariants.validate_card_accounting(undone)

    assert {:ok, redone} = Engine.redo(undone)
    assert length(redone.players.dragapult.hand) == 7
    assert length(redone.players.alakazam.hand) == 7
    assert :ok = Invariants.validate_card_accounting(redone)

    dreepy = card_in_hand(redone, :dragapult, "TWM-128")
    abra = card_in_hand(redone, :alakazam, "MEG-054")

    assert {:ok, state} =
             Engine.apply_action(redone, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             })

    budew = card_in_hand(state, :dragapult, "ASC-016")
    dunsparce = card_in_hand(state, :alakazam, "JTG-120")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_setup_bench_from_hand,
               player_id: :dragapult,
               params: %{instance_id: budew.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_setup_bench_from_hand,
               player_id: :alakazam,
               params: %{instance_id: dunsparce.instance_id}
             })

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :place_prizes})
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:ok, undone} = Engine.undo(state)
    assert undone.players.dragapult.prizes == []
    assert length(undone.players.dragapult.deck) == 53
    assert :ok = Invariants.validate_card_accounting(undone)

    assert {:ok, redone} = Engine.redo(undone)
    assert length(redone.players.dragapult.prizes) == 6
    assert length(redone.players.alakazam.prizes) == 6
    assert :ok = Invariants.validate_card_accounting(redone)
  end

  test "mulligan redraws seven when opening hand has no Basic Pokemon" do
    no_basic_opening = [
      "MEE-005",
      "MEE-002",
      "MEE-007",
      "MEG-119",
      "SCR-133",
      "POR-071",
      "TEF-144"
    ]

    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult:
            full_deck_with_opening(no_basic_opening ++ ["TWM-128"], Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})
    refute Enum.any?(state.players.dragapult.hand, &CardRegistry.basic_pokemon?(&1.card_id))

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :take_mulligan, player_id: :dragapult})

    assert state.players.dragapult.mulligans_taken == 1
    assert length(state.players.dragapult.hand) == 7
    assert Enum.any?(state.players.dragapult.hand, &(&1.card_id == "TWM-128"))
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:error, :cannot_mulligan_with_basic_pokemon_in_hand} =
             Engine.apply_action(state, %Action{type: :take_mulligan, player_id: :dragapult})
  end

  test "opponent may draw up to one bonus card per mulligan" do
    no_basic_opening = [
      "MEE-005",
      "MEE-002",
      "MEE-007",
      "MEG-119",
      "SCR-133",
      "POR-071",
      "TEF-144"
    ]

    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult:
            full_deck_with_opening(no_basic_opening ++ ["TWM-128"], Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :take_mulligan, player_id: :dragapult})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :draw_mulligan_bonus,
               player_id: :alakazam,
               params: %{count: 1}
             })

    assert state.players.alakazam.mulligan_bonus_draws_taken == 1
    assert length(state.players.alakazam.hand) == 8
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:error, {:too_many_mulligan_bonus_cards, 1, 0}} =
             Engine.apply_action(state, %Action{
               type: :draw_mulligan_bonus,
               player_id: :alakazam,
               params: %{count: 1}
             })
  end

  test "plays a Basic Pokémon to Bench and attaches Energy with undo/redo" do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})

    dreepy = card_in_hand(state, :dragapult, "TWM-128")
    abra = card_in_hand(state, :alakazam, "MEG-054")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             })

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :place_prizes})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :complete_setup})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})

    budew = card_in_hand(state, :dragapult, "ASC-016")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :play_basic_to_bench,
               player_id: :dragapult,
               params: %{instance_id: budew.instance_id}
             })

    assert [bench_budew] = state.players.dragapult.bench

    energy = card_in_hand(state, :dragapult, "MEE-005")
    active = state.players.dragapult.active

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :attach_energy,
               player_id: :dragapult,
               params: %{instance_id: energy.instance_id, target_id: active.instance_id}
             })

    assert [attached_energy] = state.players.dragapult.active.attachments
    assert attached_energy.card_id == "MEE-005"

    assert {:ok, undone} = Engine.undo(state)
    assert undone.players.dragapult.active.attachments == []
    assert card_in_hand(undone, :dragapult, "MEE-005")

    assert {:ok, redone} = Engine.redo(undone)

    assert redone.players.dragapult.active.attachments ==
             state.players.dragapult.active.attachments

    assert [^bench_budew] = redone.players.dragapult.bench
  end

  test "rejects drawing twice in the same turn action window" do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_setup})
    assert {:ok, state} = Engine.apply_action(state, %Action{type: :draw_opening_hand})

    dreepy = card_in_hand(state, :dragapult, "TWM-128")
    abra = card_in_hand(state, :alakazam, "MEG-054")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             })

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :place_prizes})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :complete_setup})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})

    assert {:error, error} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert error.state == :action_window
    assert error.event == :draw_for_turn
  end

  test "skip_draw_for_turn advances to action window without drawing" do
    assert {:ok, state} = setup_game_with_actives_only()

    hand_size_before = length(state.players.dragapult.hand)

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :skip_draw_for_turn, player_id: :dragapult})

    assert state.turn_lifecycle == :action_window
    assert length(state.players.dragapult.hand) == hand_size_before
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "discard_from_deck moves a card from deck to discard" do
    assert {:ok, state} = setup_game_with_actives_only()
    assert {:ok, state} = advance_to_next_turn_action_window(state, :dragapult)

    target = hd(state.players.dragapult.deck)

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :discard_from_deck,
               player_id: :dragapult,
               params: %{instance_id: target.instance_id}
             })

    assert Enum.any?(state.players.dragapult.discard, &(&1.instance_id == target.instance_id))
    refute Enum.any?(state.players.dragapult.deck, &(&1.instance_id == target.instance_id))
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "ends a turn and starts the opponent turn" do
    assert {:ok, state} = setup_game_with_actives_only()

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :end_turn, player_id: :dragapult})

    assert state.turn_lifecycle == :not_in_turn
    assert state.active_player == :dragapult

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_next_turn})
    assert state.active_player == :alakazam
    assert state.turn_lifecycle == :start_turn
    assert state.turn_number == 2
  end

  test "attack damage can knock out active Pokemon, award a prize, and end the game" do
    assert {:ok, state} = setup_game_with_actives_only()

    target = state.players.alakazam.active

    assert {:ok, state} = advance_to_next_turn_action_window(state, :dragapult)

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :declare_attack, player_id: :dragapult})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :resolve_attack_damage,
               player_id: :dragapult,
               params: %{target_player_id: :alakazam, target_id: target.instance_id, damage: 50}
             })

    assert state.game_lifecycle == :choosing_prizes

    assert {:ok, state} = choose_first_prize(state, :dragapult)

    assert state.winner == :dragapult
    assert state.game_lifecycle == :finished
    assert state.players.alakazam.active == nil
    assert Enum.any?(state.players.alakazam.discard, &(&1.instance_id == target.instance_id))
    assert length(state.players.dragapult.prizes) == 5
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:ok, undone} = Engine.undo(state)
    assert undone.winner == nil
    assert undone.game_lifecycle == :choosing_prizes
    assert undone.players.alakazam.active == nil

    assert {:ok, undone} = Engine.undo(undone)
    assert undone.players.alakazam.active.instance_id == target.instance_id
    assert length(undone.players.dragapult.prizes) == 6
    assert :ok = Invariants.validate_card_accounting(undone)
  end

  test "choose_prize takes a selected prize instead of the top prize" do
    assert {:ok, state} = setup_game_with_benches()

    target = state.players.alakazam.active
    [top_prize, chosen_prize | _] = state.players.dragapult.prizes

    assert {:ok, state} =
             attack_active_for_damage(state, :dragapult, :alakazam, target.instance_id, 50)

    assert state.game_lifecycle == :choosing_prizes

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_prize,
               player_id: :dragapult,
               params: %{instance_id: chosen_prize.instance_id}
             })

    assert state.game_lifecycle == :replacing_active
    assert Enum.any?(state.players.dragapult.hand, &(&1.instance_id == chosen_prize.instance_id))
    assert Enum.any?(state.players.dragapult.prizes, &(&1.instance_id == top_prize.instance_id))

    refute Enum.any?(
             state.players.dragapult.prizes,
             &(&1.instance_id == chosen_prize.instance_id)
           )

    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "declares and resolves a real attack from card metadata" do
    assert {:ok, state} = setup_game_with_actives_only()
    abra = state.players.alakazam.active

    assert {:ok, state} = advance_to_next_turn_action_window(state, :dragapult)

    energy = card_in_hand(state, :dragapult, "MEE-005")
    dreepy = state.players.dragapult.active

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :attach_energy,
               player_id: :dragapult,
               params: %{instance_id: energy.instance_id, target_id: dreepy.instance_id}
             })

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :declare_attack,
               player_id: :dragapult,
               params: %{attack_id: :petty_grudge}
             })

    assert state.pending_attack.attack.damage == 10

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :resolve_declared_attack,
               player_id: :dragapult
             })

    assert state.pending_attack == nil
    assert state.players.alakazam.active.instance_id == abra.instance_id
    assert state.players.alakazam.active.damage == 10

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :finish_attack, player_id: :dragapult})

    assert state.game_lifecycle == :in_progress
    assert state.turn_lifecycle == :end_turn
  end

  test "rejects real attacks when attached Energy cannot pay the cost" do
    assert {:ok, state} = setup_game_with_actives_only()

    assert {:ok, state} = advance_to_next_turn_action_window(state, :dragapult)

    energy = card_in_hand(state, :dragapult, "MEE-005")
    dreepy = state.players.dragapult.active

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :attach_energy,
               player_id: :dragapult,
               params: %{instance_id: energy.instance_id, target_id: dreepy.instance_id}
             })

    assert {:error, {:cannot_pay_attack_cost, :bite, [:fire, :psychic], [:psychic]}} =
             Engine.apply_action(state, %Action{
               type: :declare_attack,
               player_id: :dragapult,
               params: %{attack_id: :bite}
             })
  end

  test "evolves an in-play Pokemon from hand and preserves card accounting" do
    assert {:ok, state} = setup_game_with_actives_only()
    assert {:ok, state} = advance_to_next_turn_action_window(state, :dragapult)

    drakloak = card_in_hand(state, :dragapult, "TWM-129")
    dreepy = state.players.dragapult.active

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :evolve_from_hand,
               player_id: :dragapult,
               params: %{instance_id: drakloak.instance_id, target_id: dreepy.instance_id}
             })

    assert state.players.dragapult.active.card_id == "TWM-129"
    assert [evolved_from] = state.players.dragapult.active.evolved_from
    assert evolved_from.card_id == "TWM-128"
    refute Enum.any?(state.players.dragapult.hand, &(&1.instance_id == drakloak.instance_id))
    assert :ok = Invariants.validate_card_accounting(state)

    assert {:ok, undone} = Engine.undo(state)
    assert undone.players.dragapult.active.card_id == "TWM-128"
    assert Enum.any?(undone.players.dragapult.hand, &(&1.instance_id == drakloak.instance_id))
    assert :ok = Invariants.validate_card_accounting(undone)
  end

  test "rejects evolution on the first turn of the game" do
    assert {:ok, state} = setup_game_with_actives_only()

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})

    drakloak = card_in_hand(state, :dragapult, "TWM-129")
    dreepy = state.players.dragapult.active

    assert {:error, :cannot_evolve_on_first_turn_of_game} =
             Engine.apply_action(state, %Action{
               type: :evolve_from_hand,
               player_id: :dragapult,
               params: %{instance_id: drakloak.instance_id, target_id: dreepy.instance_id}
             })
  end

  test "rejects evolution onto the wrong Pokemon" do
    assert {:ok, state} = setup_game_with_benches()

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :open_action_window})

    budew = card_in_hand(state, :dragapult, "ASC-016")

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :play_basic_to_bench,
               player_id: :dragapult,
               params: %{instance_id: budew.instance_id}
             })

    drakloak = card_in_hand(state, :dragapult, "TWM-129")
    budew = hd(state.players.dragapult.bench)

    assert {:error, {:cannot_evolve, "TWM-129", :expected, "TWM-128", :got, "ASC-016"}} =
             Engine.apply_action(state, %Action{
               type: :evolve_from_hand,
               player_id: :dragapult,
               params: %{instance_id: drakloak.instance_id, target_id: budew.instance_id}
             })
  end

  test "scripted playthrough can KO, replace Active, continue, and end by no Pokemon remaining" do
    assert {:ok, state} = setup_game_with_benches()

    abra = state.players.alakazam.active
    [dunsparce] = state.players.alakazam.bench

    assert {:ok, state} =
             attack_active_for_damage(state, :dragapult, :alakazam, abra.instance_id, 50)

    assert {:ok, state} = choose_first_prize(state, :dragapult)

    assert state.game_lifecycle == :replacing_active
    assert state.turn_lifecycle == :attack_resolving
    assert length(state.players.dragapult.prizes) == 5

    assert {:ok, state} =
             Engine.apply_action(state, %Action{
               type: :choose_replacement_active,
               player_id: :alakazam,
               params: %{instance_id: dunsparce.instance_id}
             })

    assert state.players.alakazam.active.instance_id == dunsparce.instance_id
    assert state.game_lifecycle == :in_progress

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :finish_attack, player_id: :dragapult})

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :end_turn, player_id: :dragapult})

    assert {:ok, state} = Engine.apply_action(state, %Action{type: :start_next_turn})

    dreepy = state.players.dragapult.active

    assert {:ok, state} =
             attack_active_for_damage(state, :alakazam, :dragapult, dreepy.instance_id, 70)

    assert {:ok, state} = choose_first_prize(state, :alakazam)

    assert state.winner == :alakazam
    assert state.game_lifecycle == :finished
    assert state.players.dragapult.active == nil
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "scripted playthrough can end by taking the final prize" do
    assert {:ok, state} = setup_game_with_many_alakazam_pokemon()

    [final_prize | already_taken_prizes] = state.players.dragapult.prizes
    player = state.players.dragapult
    player = %{player | prizes: [final_prize], hand: already_taken_prizes ++ player.hand}
    state = put_in(state.players.dragapult, player)
    target = state.players.alakazam.active

    assert {:ok, state} =
             attack_active_for_damage(state, :dragapult, :alakazam, target.instance_id, 50)

    assert {:ok, state} = choose_first_prize(state, :dragapult)

    assert state.winner == :dragapult
    assert state.game_lifecycle == :finished
    assert state.players.dragapult.prizes == []
    assert state.players.dragapult.expected_card_count == 60
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "scripted playthrough can end by deck-out on draw for turn" do
    assert {:ok, state} = setup_game_with_actives_only()
    state = put_in(state.players.dragapult.deck, [])
    state = put_in(state.players.dragapult.expected_card_count, 13)

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :dragapult})

    assert state.winner == :alakazam
    assert state.game_lifecycle == :finished
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "scripted playthrough can end by concession" do
    assert {:ok, state} = setup_game_with_actives_only()

    assert {:ok, state} =
             Engine.apply_action(state, %Action{type: :concede, player_id: :alakazam})

    assert state.winner == :dragapult
    assert state.game_lifecycle == :finished
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "rejects illegal action with clear state-machine error" do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [dragapult: ["TWM-128"], alakazam: ["MEG-054"]]
      )

    assert {:error, error} = Engine.apply_action(state, %Action{type: :complete_setup})
    assert error.state == :not_started
    assert error.event == :complete_setup
  end

  defp card_in_hand(state, player_id, card_id) do
    Enum.find(state.players[player_id].hand, &(&1.card_id == card_id))
  end

  defp choose_first_prize(state, player_id) do
    [prize | _] = state.players[player_id].prizes

    Engine.apply_action(state, %Action{
      type: :choose_prize,
      player_id: player_id,
      params: %{instance_id: prize.instance_id}
    })
  end

  defp setup_game_with_actives_only do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    with {:ok, state} <- Engine.apply_action(state, %Action{type: :start_setup}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :draw_opening_hand}) do
      dreepy = card_in_hand(state, :dragapult, "TWM-128")
      abra = card_in_hand(state, :alakazam, "MEG-054")

      with {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             }),
           {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             }),
           {:ok, state} <- Engine.apply_action(state, %Action{type: :place_prizes}) do
        Engine.apply_action(state, %Action{type: :complete_setup})
      end
    end
  end

  defp setup_game_with_benches do
    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(@alakazam_setup_deck, Alakazam27147.card_ids())
        ]
      )

    with {:ok, state} <- Engine.apply_action(state, %Action{type: :start_setup}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :draw_opening_hand}) do
      dreepy = card_in_hand(state, :dragapult, "TWM-128")
      abra = card_in_hand(state, :alakazam, "MEG-054")

      with {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             }),
           {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             }) do
        dunsparce = card_in_hand(state, :alakazam, "JTG-120")

        with {:ok, state} <-
               Engine.apply_action(state, %Action{
                 type: :choose_setup_bench_from_hand,
                 player_id: :alakazam,
                 params: %{instance_id: dunsparce.instance_id}
               }),
             {:ok, state} <- Engine.apply_action(state, %Action{type: :place_prizes}) do
          Engine.apply_action(state, %Action{type: :complete_setup})
        end
      end
    end
  end

  defp setup_game_with_many_alakazam_pokemon do
    opening = ["MEG-054", "JTG-120", "TEF-023", "ASC-039", "SSP-087", "MEE-005", "PFL-087"]

    state =
      Engine.new_game(
        active_player: :dragapult,
        players: [
          dragapult: full_deck_with_opening(@dragapult_setup_deck, Dragapult27431.card_ids()),
          alakazam: full_deck_with_opening(opening, Alakazam27147.card_ids())
        ]
      )

    with {:ok, state} <- Engine.apply_action(state, %Action{type: :start_setup}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :draw_opening_hand}) do
      dreepy = card_in_hand(state, :dragapult, "TWM-128")
      abra = card_in_hand(state, :alakazam, "MEG-054")

      with {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :dragapult,
               params: %{instance_id: dreepy.instance_id}
             }),
           {:ok, state} <-
             Engine.apply_action(state, %Action{
               type: :choose_active_from_hand,
               player_id: :alakazam,
               params: %{instance_id: abra.instance_id}
             }),
           {:ok, state} <-
             bench_all_basics(state, :alakazam, ["JTG-120", "TEF-023", "ASC-039", "SSP-087"]),
           {:ok, state} <- Engine.apply_action(state, %Action{type: :place_prizes}) do
        Engine.apply_action(state, %Action{type: :complete_setup})
      end
    end
  end

  defp bench_all_basics(state, _player_id, []), do: {:ok, state}

  defp bench_all_basics(state, player_id, [card_id | rest]) do
    card = card_in_hand(state, player_id, card_id)

    with {:ok, state} <-
           Engine.apply_action(state, %Action{
             type: :choose_setup_bench_from_hand,
             player_id: player_id,
             params: %{instance_id: card.instance_id}
           }) do
      bench_all_basics(state, player_id, rest)
    end
  end

  defp attack_active_for_damage(
         state,
         attacking_player_id,
         defending_player_id,
         target_id,
         damage
       ) do
    with {:ok, state} <- open_attack_window(state, attacking_player_id),
         {:ok, state} <-
           Engine.apply_action(state, %Action{
             type: :declare_attack,
             player_id: attacking_player_id
           }) do
      Engine.apply_action(state, %Action{
        type: :resolve_attack_damage,
        player_id: attacking_player_id,
        params: %{target_player_id: defending_player_id, target_id: target_id, damage: damage}
      })
    end
  end

  defp open_attack_window(%{first_player: player_id, turn_number: 1} = state, player_id) do
    advance_to_next_turn_action_window(state, player_id)
  end

  defp open_attack_window(state, player_id) do
    with {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: player_id}) do
      Engine.apply_action(state, %Action{type: :open_action_window})
    end
  end

  defp advance_to_next_turn_action_window(state, player_id) do
    with {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: player_id}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :open_action_window}),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :end_turn, player_id: player_id}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :start_next_turn}),
         {:ok, opponent_id} <- other_player_id(state, player_id),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: opponent_id}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :open_action_window}),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :end_turn, player_id: opponent_id}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :start_next_turn}),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: player_id}) do
      Engine.apply_action(state, %Action{type: :open_action_window})
    end
  end

  defp other_player_id(state, player_id) do
    state.players
    |> Map.keys()
    |> Enum.reject(&(&1 == player_id))
    |> case do
      [other] -> {:ok, other}
      other -> {:error, {:expected_one_other_player, other}}
    end
  end

  defp full_deck_with_opening(opening_card_ids, full_deck_ids) do
    remainder = Enum.reduce(opening_card_ids, full_deck_ids, &remove_one/2)
    opening_card_ids ++ remainder
  end

  defp remove_one(card_id, card_ids) do
    {before_match, [_match | after_match]} = Enum.split_while(card_ids, &(&1 != card_id))
    before_match ++ after_match
  end

  defp state_without_history(state), do: %{state | history: Prizmo.Tcg.Sim.History.new()}
end

defmodule Prizmo.Tcg.Sim.NewCardActionsTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Sim.Action
  alias Prizmo.Tcg.Sim.CardInstance
  alias Prizmo.Tcg.Sim.Decks.Alakazam27147
  alias Prizmo.Tcg.Sim.Decks.RagingBoltOgerpon27599
  alias Prizmo.Tcg.Sim.Decks.RocketMewtwo27459
  alias Prizmo.Tcg.Sim.Engine
  alias Prizmo.Tcg.Sim.Invariants
  alias Prizmo.Tcg.Sim.TestHelpers

  test "Raging Bolt ex Bellowing Thunder damages per discarded own basic energy" do
    assert {:ok, state} =
             setup_attack_game(
               RagingBoltOgerpon27599,
               "TEF-123",
               defender_deck: RagingBoltOgerpon27599,
               active_b: "TEF-123"
             )

    {state, [lightning, fighting]} = attach_to_active(state, :player_a, ["MEE-004", "MEE-006"])
    defender = state.players.player_b.active

    assert {:ok, state} =
             attack(state, :bellowing_thunder, %{
               attachment_ids: [lightning.instance_id, fighting.instance_id]
             })

    assert state.players.player_b.active.damage == 140

    assert Enum.count(state.players.player_a.discard, &(&1.card_id in ["MEE-004", "MEE-006"])) ==
             2

    assert state.players.player_b.active.instance_id == defender.instance_id
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "Teal Mask Ogerpon ex Myriad Leaf Shower counts energy on both Active Pokémon" do
    assert {:ok, state} =
             setup_attack_game(
               RagingBoltOgerpon27599,
               "TWM-025",
               defender_deck: RagingBoltOgerpon27599,
               active_b: "TEF-123"
             )

    {state, _own_energy} = attach_to_active(state, :player_a, ["MEE-001", "MEE-001", "MEE-001"])
    {state, _opponent_energy} = attach_to_active(state, :player_b, ["MEE-005", "MEE-005"])

    assert {:ok, state} = attack(state, :myriad_leaf_shower)

    assert state.players.player_b.active.damage == 180
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "Team Rocket's Articuno Dark Frost gets its bonus from Team Rocket's Energy" do
    assert {:ok, state} =
             setup_attack_game(
               RocketMewtwo27459,
               "DRI-051",
               defender_deck: RocketMewtwo27459,
               active_b: "DRI-081"
             )

    state = add_cards_to_hand(state, :player_a, ["MEE-003"])
    {state, _energy} = attach_to_active(state, :player_a, ["MEE-003", "DRI-182", "DRI-182"])

    assert {:ok, state} = attack(state, :dark_frost)

    assert state.players.player_b.active.damage == 120
    assert :ok = Invariants.validate_card_accounting(state)
  end

  test "Chien-Pao Icicle Loop returns attached energy to hand after damage" do
    assert {:ok, state} =
             setup_attack_game(
               RagingBoltOgerpon27599,
               "SSP-056",
               defender_deck: RagingBoltOgerpon27599,
               active_b: "TEF-123"
             )

    state = add_cards_to_hand(state, :player_a, ["MEE-003"])

    {state, attached_energy} =
      attach_to_active(state, :player_a, ["MEE-003", "MEE-003", "MEE-001"])

    attached_ids = MapSet.new(attached_energy, & &1.instance_id)

    assert {:ok, state} = attack(state, :icicle_loop)

    assert state.players.player_b.active.damage == 120

    assert Enum.all?(attached_ids, fn id ->
             Enum.any?(state.players.player_a.hand, &(&1.instance_id == id))
           end)

    assert state.players.player_a.active.attachments == []
    assert :ok = Invariants.validate_card_accounting(state)
  end

  defp setup_attack_game(attacker_deck, attacker_card_id, opts) do
    defender_deck = Keyword.get(opts, :defender_deck, Alakazam27147)

    opts =
      Keyword.merge(
        [
          player_a: :player_a,
          player_b: :player_b,
          active_a: attacker_card_id,
          active_b: "MEG-054",
          active_player: :player_b
        ],
        opts
      )

    with {:ok, state} <- TestHelpers.setup_open_game(attacker_deck, defender_deck, opts),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :end_turn, player_id: :player_b}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :start_next_turn}),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: :player_a}) do
      Engine.apply_action(state, %Action{type: :open_action_window})
    end
  end

  defp attack(state, attack_id, params \\ %{}) do
    with {:ok, state} <-
           Engine.apply_action(state, %Action{
             type: :declare_attack,
             player_id: :player_a,
             params: Map.put(params, :attack_id, attack_id)
           }) do
      Engine.apply_action(state, %Action{type: :resolve_declared_attack, player_id: :player_a})
    end
  end

  defp attach_to_active(state, player_id, card_ids) do
    card_ids
    |> Enum.map_reduce(state, fn card_id, state ->
      player = state.players[player_id]
      card = Enum.find(player.hand ++ player.deck, &(&1.card_id == card_id))
      attached = %{card | zone: :attached, lifecycle: :attached}
      active = %{player.active | attachments: [attached | player.active.attachments]}

      player = %{
        player
        | active: active,
          hand: Enum.reject(player.hand, &(&1.instance_id == card.instance_id)),
          deck: Enum.reject(player.deck, &(&1.instance_id == card.instance_id))
      }

      {attached, put_in(state.players[player_id], player)}
    end)
    |> then(fn {attached, state} -> {state, attached} end)
  end

  defp add_cards_to_hand(state, player_id, card_ids) do
    player = state.players[player_id]

    cards =
      Enum.with_index(card_ids, fn card_id, index ->
        %CardInstance{
          instance_id: "#{player_id}-fixture-#{card_id}-#{index}",
          card_id: card_id,
          owner: player_id,
          lifecycle: :in_hand,
          zone: :hand
        }
      end)

    player = %{
      player
      | hand: cards ++ player.hand,
        expected_card_count: player.expected_card_count + length(cards)
    }

    put_in(state.players[player_id], player)
  end
end

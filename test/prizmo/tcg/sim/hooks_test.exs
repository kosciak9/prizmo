defmodule Prizmo.Tcg.Sim.HooksTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Sim.CardInstance
  alias Prizmo.Tcg.Sim.Decks.RagingBoltOgerpon27599
  alias Prizmo.Tcg.Sim.Hooks
  alias Prizmo.Tcg.Sim.Invariants
  alias Prizmo.Tcg.Sim.TestHelpers

  test "before_play_trainer halts items while item lock is active" do
    assert {:ok, state} =
             TestHelpers.setup_open_game(RagingBoltOgerpon27599, RagingBoltOgerpon27599)

    state = put_in(state.players.player_a.item_cards_locked?, true)

    assert Hooks.run(state, :before_play_trainer, %{
             player_id: :player_a,
             metadata: %{trainer_type: :item}
           }) == {:halt, :item_cards_locked_this_turn}
  end

  test "before_ability halts Colorless abilities under Team Rocket's Watchtower" do
    assert {:ok, state} =
             TestHelpers.setup_open_game(RagingBoltOgerpon27599, RagingBoltOgerpon27599)

    state = %{
      state
      | stadium: %CardInstance{instance_id: "stadium", card_id: "DRI-180", owner: :player_a}
    }

    assert Hooks.run(state, :before_ability, %{
             metadata: %{supertype: :pokemon, type: :colorless, id: "SCR-118"}
           }) == {:halt, {:ability_blocked_by_stadium, "DRI-180", "SCR-118"}}
  end

  test "modify_damage applies Kieran marker against Pokémon ex" do
    assert {:ok, state} =
             TestHelpers.setup_open_game(
               RagingBoltOgerpon27599,
               RagingBoltOgerpon27599,
               active_a: "SSP-111",
               active_b: "TEF-123"
             )

    state =
      update_in(
        state.players.player_a.markers,
        &MapSet.put(&1, {:damage_bonus_to_opponent_active_pokemon_ex_or_v, :kieran})
      )

    assert Hooks.run(state, :modify_damage, %{
             source: :attack,
             damage: 40,
             attacking_player_id: :player_a,
             attacker_id: state.players.player_a.active.instance_id,
             target_player_id: :player_b,
             target_id: state.players.player_b.active.instance_id,
             target_zone: :active
           }) == {:ok, 70}
  end

  test "before_attack_effect halts attack effects against Mist Energy attached Pokémon" do
    assert {:ok, state} =
             TestHelpers.setup_open_game(
               RagingBoltOgerpon27599,
               RagingBoltOgerpon27599,
               active_a: "TEF-123",
               active_b: "TEF-123"
             )

    state = attach_fixture(state, :player_b, "TEF-161")
    target = state.players.player_b.active

    assert Hooks.run(state, :before_attack_effect, %{
             source: :attack_effect,
             attacking_player_id: :player_a,
             target_player_id: :player_b,
             target_id: target.instance_id
           }) == {:halt, {:attack_effect_prevented_by_energy, "TEF-161", :mist_energy}}

    assert :ok = Invariants.validate_card_accounting(state)
  end

  defp attach_fixture(state, player_id, card_id) do
    player = state.players[player_id]

    attachment = %CardInstance{
      instance_id: "#{player_id}-fixture-#{card_id}",
      card_id: card_id,
      owner: player_id,
      lifecycle: :attached,
      zone: :attached
    }

    active = %{player.active | attachments: [attachment | player.active.attachments]}
    player = %{player | active: active, expected_card_count: player.expected_card_count + 1}

    put_in(state.players[player_id], player)
  end
end

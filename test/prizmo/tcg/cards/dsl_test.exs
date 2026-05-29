defmodule Prizmo.Tcg.Cards.DSLTest do
  use ExUnit.Case, async: true

  test "builds a behavior manifest from attack, ability, and card-effect entries" do
    [{module, _bytecode}] =
      Code.compile_string("""
      defmodule Prizmo.Tcg.Cards.DSLTest.ValidBehavior do
        use Prizmo.Tcg.Cards.DSL

        card "TEF-123" do
          attack(:burst_roar, damage: 0, effect: %{type: :discard_hand_then_draw, count: 6})
        end

        card "TWM-025" do
          ability(:teal_dance, effect: %{type: :attach_basic_grass_energy_from_hand_to_self_then_draw, count: 1})
        end

        card "POR-086" do
          card_effect(effect: %{type: :grass_pokemon_hp_plus_20_energy})
        end
      end
      """)

    assert module.behavior_card_ids() == ["POR-086", "TEF-123", "TWM-025"]
    assert {:ok, raging_bolt} = module.behavior_for("TEF-123")
    assert raging_bolt.attacks.burst_roar.overlay.effect.type == :discard_hand_then_draw

    assert [card_effect] = module.behavior_manifest()["POR-086"].card_effects

    assert card_effect.overlay.effect.type ==
             :grass_pokemon_hp_plus_20_energy
  end

  test "requires executable effect overlays when cached text has printed effects" do
    assert_raise ArgumentError,
                 ~r/must declare an executable :effect overlay/,
                 fn ->
                   Code.compile_string("""
                   defmodule Prizmo.Tcg.Cards.DSLTest.MissingEffect do
                     use Prizmo.Tcg.Cards.DSL

                     card "TEF-123" do
                       attack(:burst_roar, damage: 0)
                     end
                   end
                   """)
                 end
  end

  test "rejects behavior for uncached card metadata" do
    assert_raise ArgumentError,
                 ~r/cannot declare behavior without cached metadata/,
                 fn ->
                   Code.compile_string("""
                   defmodule Prizmo.Tcg.Cards.DSLTest.UnknownCard do
                     use Prizmo.Tcg.Cards.DSL

                     card "NOPE-999" do
                       attack(:missing, effect: nil)
                     end
                   end
                   """)
                 end
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.POR do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "POR-020" do
    attack(:water_gun, effect: nil)
  end

  card "POR-021" do
    attack(:jetting_blow,
      effect: %{type: :damage_opponent_bench, bench_damage: 50}
    )

    attack(:nebula_beam,
      effect: %{type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active}
    )
  end

  card "POR-052" do
    attack(:wrack_down, effect: nil)

    attack(:hazardous_tail,
      effect: %{type: :self_damage_then_paralyze_and_poison_defender_active, self_damage: 70}
    )
  end

  card "POR-077" do
    card_effect(effect: %{type: :search_basic_pokemon_to_bench_then_end_turn})
  end

  card "POR-086" do
    card_effect(effect: %{type: :grass_pokemon_hp_plus_20_energy})
  end

  card "POR-087" do
    card_effect(
      effect: %{
        type: :prevent_opponent_attack_effects_to_attached_pokemon,
        required_attached_pokemon_type: :fighting
      }
    )
  end

  card "POR-088" do
    card_effect(
      effect: %{
        type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
        max_targets: 2
      }
    )
  end

  card "POR-062" do
    ability(:last_ditch_catch,
      effect: %{type: :search_supporter_when_benched_from_hand, last_ditch?: true}
    )

    attack(:tuck_tail,
      cost: [:colorless, :colorless, :colorless],
      damage: 60,
      effect: %{type: :return_attacker_and_attached_to_hand}
    )
  end

  card "POR-084" do
    card_effect(
      effect: %{
        type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes,
        max_targets: 2
      }
    )
  end
end

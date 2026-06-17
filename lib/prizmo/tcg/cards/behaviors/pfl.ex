defmodule Prizmo.Tcg.Cards.Behaviors.PFL do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "PFL-014" do
    attack(:fighting_wings,
      damage: 20,
      effect: %{type: :bonus_damage_if_defender_pokemon_ex, bonus_damage: 90}
    )
  end

  card "PFL-083" do
    attack(:run_around, effect: %{type: :switch_self_with_bench})
    attack(:kick, effect: nil)
  end

  card "PFL-084" do
    attack(:gale_thrust,
      damage: 60,
      effect: %{type: :bonus_damage_if_moved_from_bench_to_active_this_turn, bonus_damage: 170}
    )

    attack(:spiky_hopper, effect: %{type: :damage_unaffected_by_effects_on_opponent_active})
  end

  card "PFL-085" do
    card_effect(effect: %{type: :prevent_damage_counters_to_bench_from_opponent_pokemon_effects})
  end

  card "PFL-094" do
    card_effect(
      effect: %{type: :attach_basic_psychic_energy_from_discard_to_benched_psychic_pokemon}
    )
  end
end

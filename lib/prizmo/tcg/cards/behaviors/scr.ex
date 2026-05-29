defmodule Prizmo.Tcg.Cards.Behaviors.SCR do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SCR-012" do
    attack(:spray_fluid, effect: nil)
  end

  card "SCR-118" do
    ability(:fan_call,
      effect: %{
        type: :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn,
        max_targets: 3
      }
    )

    attack(:assault_landing, effect: %{type: :damage_only_if_stadium_in_play})
  end

  card "SCR-131" do
    card_effect(effect: %{type: :bench_limit_8_with_tera_in_play_else_discard_to_5})
  end

  card "SCR-135" do
    card_effect(
      effect: %{
        type: :attach_basic_energy_from_discard_to_benched_colorless_if_tera_in_play,
        max_targets: 2
      }
    )
  end
end

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
end

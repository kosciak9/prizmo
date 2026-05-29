defmodule Prizmo.Tcg.Cards.Behaviors.JTG do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "JTG-120" do
    attack(:trading_places,
      effect: %{type: :switch_self_with_bench}
    )

    attack(:ram, effect: nil)
  end

  card "JTG-143" do
    card_effect(
      effect: %{
        type: :turn_bonus_attack_damage_to_opponent_active_pokemon_ex,
        bonus_damage: 40
      }
    )
  end
end

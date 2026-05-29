defmodule Prizmo.Tcg.Cards.Behaviors.JTG do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "JTG-056" do
    ability(:fairy_zone,
      effect: %{type: :opponent_darkness_pokemon_weakness_becomes_psychic}
    )

    attack(:full_moon_rondo,
      damage: 20,
      effect: %{type: :bonus_damage_per_benched_pokemon, bonus_damage: 20}
    )
  end

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

defmodule Prizmo.Tcg.Cards.Behaviors.WHT do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "WHT-080" do
    card_effect(
      effect: %{
        type: :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
        bonus_damage: 30
      }
    )
  end
end

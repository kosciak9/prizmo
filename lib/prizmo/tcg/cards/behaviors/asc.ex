defmodule Prizmo.Tcg.Cards.Behaviors.ASC do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "ASC-016" do
    attack(:itchy_pollen, effect: %{type: :lock_opponent_items_next_turn})
  end

  card "ASC-039" do
    ability(:damp, effect: %{type: :pokemon_lose_self_knock_out_abilities})
    attack(:ram, effect: nil)
  end

  card "ASC-142" do
    ability(:flip_the_script,
      effect: %{type: :draw_if_own_pokemon_knocked_out_last_turn, count: 3}
    )

    attack(:cruel_arrow, effect: %{type: :damage_any_opponent_pokemon, amount: 20})
  end

  card "ASC-181" do
    card_effect(
      effect: %{
        type: :retreat_cost_reduction,
        energy_type: :colorless,
        amount: 2
      }
    )
  end
end

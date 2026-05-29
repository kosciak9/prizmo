defmodule Prizmo.Tcg.Cards.Behaviors.ASC do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "ASC-039" do
    ability(:damp, effect: %{type: :pokemon_lose_self_knock_out_abilities})
    attack(:ram, effect: nil)
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

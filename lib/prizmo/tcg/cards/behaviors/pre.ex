defmodule Prizmo.Tcg.Cards.Behaviors.PRE do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "PRE-021" do
    ability(:festival_lead,
      effect: %{type: :may_attack_twice_if_festival_grounds_in_play}
    )

    attack(:rapid_draw,
      effect: %{type: :draw_after_attack, count: 2}
    )
  end
end

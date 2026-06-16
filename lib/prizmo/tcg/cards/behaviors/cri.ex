defmodule Prizmo.Tcg.Cards.Behaviors.CRI do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "CRI-082" do
    card_effect(
      effect: %{
        type: :opponent_hand_to_bottom_then_draw_if_any,
        draw_count: 3,
        requires_opponent_prize_count_at_most: 3
      }
    )
  end
end

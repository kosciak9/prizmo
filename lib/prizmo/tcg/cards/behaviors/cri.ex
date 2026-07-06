defmodule Prizmo.Tcg.Cards.Behaviors.CRI do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "CRI-080" do
    card_effect(
      effect: %{
        type: :discard_two_cards_to_draw_one,
        discard_count: 2,
        draw_count: 1
      }
    )
  end

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

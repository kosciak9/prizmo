defmodule Prizmo.Tcg.Cards.Behaviors.SVI do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SVI-186" do
    card_effect(effect: %{type: :top_n_choose_supporter_to_hand, count: 7})
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.SFA do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SFA-040" do
    ability(:ace_nullifier,
      effect: %{type: :opponent_cannot_play_ace_spec_if_tool_attached}
    )

    attack(:magnetic_blast, effect: nil)
  end

  card "SFA-064" do
    card_effect(effect: %{type: :opponent_discards_to_hand_size, target_hand_size: 3})
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.SFA do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SFA-040" do
    ability(:ace_nullifier,
      effect: %{type: :opponent_cannot_play_ace_spec_if_tool_attached}
    )

    attack(:magnetic_blast, effect: nil)
  end
end

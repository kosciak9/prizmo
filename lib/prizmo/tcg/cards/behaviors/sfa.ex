defmodule Prizmo.Tcg.Cards.Behaviors.SFA do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SFA-040" do
    attack(:magnetic_blast, effect: nil)
  end
end

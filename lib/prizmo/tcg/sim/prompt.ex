defmodule Prizmo.Tcg.Sim.Prompt do
  @moduledoc """
  Prompt that suspends simulator execution until a choice is supplied.
  """

  @enforce_keys [:id, :type, :player_id]
  defstruct [:id, :type, :player_id, choices: [], min: 1, max: 1, metadata: %{}]
end

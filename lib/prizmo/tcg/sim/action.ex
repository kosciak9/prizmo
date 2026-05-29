defmodule Prizmo.Tcg.Sim.Action do
  @moduledoc """
  Explicit player/system action submitted to the simulator reducer.
  """

  @enforce_keys [:type]
  defstruct [:type, :player_id, params: %{}]
end

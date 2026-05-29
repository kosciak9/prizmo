defmodule Prizmo.Tcg.Sim.IllegalTransition do
  @moduledoc """
  Error returned when a simulator state machine receives an unsupported transition.
  """

  @enforce_keys [:machine, :state, :event]
  defstruct [:machine, :state, :event, :allowed]

  @type t :: %__MODULE__{
          machine: module(),
          state: atom(),
          event: atom(),
          allowed: [atom()] | nil
        }

  def new(machine, state, event, allowed \\ nil) do
    %__MODULE__{machine: machine, state: state, event: event, allowed: allowed}
  end
end

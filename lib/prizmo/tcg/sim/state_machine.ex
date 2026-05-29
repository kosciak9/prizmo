defmodule Prizmo.Tcg.Sim.StateMachine do
  @moduledoc """
  Small helper used by the simulator lifecycle modules.

  The first simulator slice intentionally starts with explicit state machines so
  the engine can reject unsupported game states instead of approximating them.
  """

  alias Prizmo.Tcg.Sim.IllegalTransition

  @type transition_map :: %{required(atom()) => %{required(atom()) => atom()}}

  @spec transition(module(), transition_map(), atom(), atom()) ::
          {:ok, atom()} | {:error, IllegalTransition.t()}
  def transition(machine, transitions, state, event) do
    case get_in(transitions, [state, event]) do
      nil ->
        allowed = transitions |> Map.get(state, %{}) |> Map.keys() |> Enum.sort()
        {:error, IllegalTransition.new(machine, state, event, allowed)}

      next_state ->
        {:ok, next_state}
    end
  end
end

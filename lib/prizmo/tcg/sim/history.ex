defmodule Prizmo.Tcg.Sim.History do
  @moduledoc """
  Undo/redo history for pure simulator states.

  Each applied action stores the state before and after the action with nested
  history stripped. Undo and redo restore snapshots while preserving the updated
  history stacks.
  """

  defstruct past: [], future: []

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:action, :before_state, :after_state]
    defstruct [:action, :before_state, :after_state]
  end

  def new, do: %__MODULE__{}

  def record(%{history: %__MODULE__{} = history} = before_state, action, after_state) do
    entry = %Entry{
      action: action,
      before_state: snapshot(before_state),
      after_state: snapshot(after_state)
    }

    %{after_state | history: %__MODULE__{past: [entry | history.past], future: []}}
  end

  def undo(%{history: %__MODULE__{past: [entry | rest], future: future}}) do
    history = %__MODULE__{past: rest, future: [entry | future]}
    {:ok, %{entry.before_state | history: history}}
  end

  def undo(%{history: %__MODULE__{past: []}}), do: {:error, :nothing_to_undo}

  def redo(%{history: %__MODULE__{past: past, future: [entry | rest]}}) do
    history = %__MODULE__{past: [entry | past], future: rest}
    {:ok, %{entry.after_state | history: history}}
  end

  def redo(%{history: %__MODULE__{future: []}}), do: {:error, :nothing_to_redo}

  defp snapshot(%{history: %__MODULE__{}} = state), do: %{state | history: new()}
end

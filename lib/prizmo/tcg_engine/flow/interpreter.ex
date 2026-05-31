defmodule Prizmo.TcgEngine.Flow.Interpreter do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [transaction: 1]

  alias Prizmo.TcgEngine.Flow.Actions
  alias Prizmo.TcgEngine.Flow.Context
  alias Prizmo.TcgEngine.Flow.Machine
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameStore

  @max_microsteps 20

  def dispatch(game_or_id, event, attrs) when is_atom(event) and is_map(attrs) do
    transaction(fn ->
      with {:ok, context} <- Context.load(game_or_id),
           {:ok, transition} <- Machine.public_transition(event),
           :ok <- require_source_state(context.game, transition.from),
           {:ok, game} <- run_action(transition.action, context, attrs),
           :ok <- require_target_state(game, transition.target) do
        stabilize_steps(game.id, @max_microsteps)
      end
    end)
  end

  def stabilize(game_or_id) do
    with {:ok, game} <- GameStore.get_game(game_or_id) do
      stabilize_steps(game.id, @max_microsteps)
    end
  end

  defp stabilize_steps(_game_id, 0), do: {:error, :flow_microstep_limit_exceeded}

  defp stabilize_steps(game_id, remaining_steps) do
    with {:ok, context} <- Context.load(game_id) do
      case next_always_transition(context) do
        nil ->
          {:ok, context.game}

        transition ->
          with {:ok, game} <- run_action(transition.action, context, %{}),
               :ok <- require_target_state(game, transition.target) do
            stabilize_steps(game.id, remaining_steps - 1)
          end
      end
    end
  end

  defp next_always_transition(%Context{game: %Game{flow_state: flow_state}} = context) do
    flow_state
    |> Machine.always_transitions()
    |> Enum.find(&guard_passes?(&1, context))
  end

  defp guard_passes?(%{guard: guard}, %Context{} = context) do
    apply(Actions, guard, [context, %{}])
  end

  defp run_action(action, %Context{} = context, attrs) do
    apply(Actions, action, [context, attrs])
  end

  defp require_source_state(%Game{flow_state: state}, state), do: :ok

  defp require_source_state(%Game{flow_state: actual}, expected),
    do: {:error, {:invalid_flow_state, actual, expected}}

  defp require_target_state(%Game{flow_state: state}, state), do: :ok

  defp require_target_state(%Game{id: game_id}, expected) do
    with {:ok, %Game{flow_state: actual}} <- GameStore.get_game(game_id) do
      if actual == expected do
        :ok
      else
        {:error, {:invalid_flow_target, actual, expected}}
      end
    end
  end
end

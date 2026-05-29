defmodule Prizmo.Tcg.Sim.StateMachines.GameLifecycle do
  @moduledoc """
  Whole-game lifecycle for a supported Pokémon TCG simulation.
  """

  alias Prizmo.Tcg.Sim.StateMachine

  @transitions %{
    not_started: %{start_setup: :setup},
    setup: %{complete_setup: :in_progress, finish: :finished},
    in_progress: %{
      declare_attack: :resolving_attack,
      choose_prizes: :choosing_prizes,
      replace_active: :replacing_active,
      between_turns: :between_turns,
      finish: :finished
    },
    resolving_attack: %{
      choose_prizes: :choosing_prizes,
      replace_active: :replacing_active,
      finish_attack: :in_progress,
      finish: :finished
    },
    choosing_prizes: %{
      replace_active: :replacing_active,
      finish_prizes: :in_progress,
      finish: :finished
    },
    replacing_active: %{replacement_chosen: :in_progress, finish: :finished},
    between_turns: %{start_next_turn: :in_progress, finish: :finished},
    finished: %{}
  }

  @spec transition(atom(), atom()) ::
          {:ok, atom()} | {:error, Prizmo.Tcg.Sim.IllegalTransition.t()}
  def transition(state, event),
    do: StateMachine.transition(__MODULE__, @transitions, state, event)

  def transitions, do: @transitions
end

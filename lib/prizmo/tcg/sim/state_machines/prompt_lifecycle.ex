defmodule Prizmo.Tcg.Sim.StateMachines.PromptLifecycle do
  @moduledoc """
  Lifecycle for prompts that suspend engine execution until a player chooses.
  """

  alias Prizmo.Tcg.Sim.StateMachine

  @transitions %{
    no_prompt: %{open_prompt: :awaiting_choice},
    awaiting_choice: %{submit_choice: :validating_choice, cancel_prompt: :no_prompt},
    validating_choice: %{choice_valid: :applying_choice, choice_invalid: :awaiting_choice},
    applying_choice: %{finish_prompt: :prompt_complete},
    prompt_complete: %{clear_prompt: :no_prompt}
  }

  @spec transition(atom(), atom()) ::
          {:ok, atom()} | {:error, Prizmo.Tcg.Sim.IllegalTransition.t()}
  def transition(state, event),
    do: StateMachine.transition(__MODULE__, @transitions, state, event)

  def transitions, do: @transitions
end

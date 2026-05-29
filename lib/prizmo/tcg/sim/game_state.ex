defmodule Prizmo.Tcg.Sim.GameState do
  @moduledoc """
  Root immutable state for the simulator.
  """

  alias Prizmo.Tcg.Sim.History

  defstruct players: %{},
            active_player: nil,
            first_player: nil,
            game_lifecycle: :not_started,
            turn_lifecycle: :not_in_turn,
            prompt_lifecycle: :no_prompt,
            turn_number: 0,
            stadium: nil,
            pending_prompts: [],
            pending_attack: nil,
            pending_prizes: nil,
            log: [],
            winner: nil,
            rng: nil,
            history: History.new()
end

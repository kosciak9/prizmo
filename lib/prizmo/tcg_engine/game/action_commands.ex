defmodule Prizmo.TcgEngine.Game.ActionCommands do
  @moduledoc false

  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.Mechanics

  actions do
    action :play_card_command, :struct do
      description "Play an engine-defined card from hand through the generic mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      argument :choices, :map do
        allow_nil? false
        default %{}
      end

      run fn input, _context ->
        Mechanics.play_card(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id,
          %{choices: input.arguments.choices}
        )
      end
    end
  end
end

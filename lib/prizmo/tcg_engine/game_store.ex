defmodule Prizmo.TcgEngine.GameStore do
  @moduledoc false

  alias Prizmo.TcgEngine
  alias Prizmo.TcgEngine.Game

  def get_game(%Game{} = game), do: get_game(game.id)

  def get_game(game_id) when is_binary(game_id) do
    case TcgEngine.get_game_by_id(game_id) do
      {:ok, %Game{} = game} -> {:ok, game}
      {:ok, nil} -> {:error, :game_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end

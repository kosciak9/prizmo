defmodule Prizmo.TcgEngine.PlayerStore do
  @moduledoc false

  alias Prizmo.TcgEngine.GamePlayer

  require Ash.Query

  def get_player(game_id, player_id) do
    case GamePlayer
         |> Ash.Query.filter(game_id == ^game_id and player_id == ^player_id)
         |> Ash.read_one() do
      {:ok, %GamePlayer{} = player} -> {:ok, player}
      {:ok, nil} -> {:error, :player_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_players(game_id) do
    GamePlayer
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(player_id: :asc)
    |> Ash.read()
  end
end

defmodule Prizmo.TcgEngine.Flow.Context do
  @moduledoc false

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.PlayerStore

  defstruct [:game, :players]

  @type t :: %__MODULE__{game: Game.t(), players: list()}

  def load(game_or_id) do
    with {:ok, game} <- GameStore.get_game(game_or_id),
         {:ok, players} <- PlayerStore.list_players(game.id) do
      {:ok, %__MODULE__{game: game, players: players}}
    end
  end

  def player?(%__MODULE__{players: players}, player_id) do
    Enum.any?(players, &(&1.player_id == player_id))
  end
end

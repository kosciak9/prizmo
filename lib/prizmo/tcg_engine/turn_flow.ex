defmodule Prizmo.TcgEngine.TurnFlow do
  @moduledoc false

  import Prizmo.TcgEngine.Requirements,
    only: [require_active_player: 2, require_game_status: 2]

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  def require_current_turn_status(game_id, status) do
    with {:ok, turn} <- TurnStore.current_turn(game_id) do
      if turn.status == status do
        {:ok, turn}
      else
        {:error, {:invalid_turn_status, turn.status, status}}
      end
    end
  end

  def require_action_window_for_player(%Game{} = game, player_id) do
    with :ok <- require_game_status(game, :in_progress),
         :ok <- require_active_player(game, player_id) do
      require_current_turn_status(game.id, :action_window)
    end
  end

  def next_turn_player_id(%Game{} = game) do
    case TurnStore.latest_turn(game.id) do
      {:ok, nil} ->
        {:ok, game.active_player_id}

      {:ok, %Turn{status: :ended}} ->
        opponent_player_id(game.id, game.active_player_id)

      {:ok, %Turn{}} ->
        {:error, :turn_already_in_progress}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def next_turn_number(game_id) do
    case TurnStore.latest_turn(game_id) do
      {:ok, nil} -> {:ok, 1}
      {:ok, %Turn{} = turn} -> {:ok, turn.turn_number + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  def opponent_player_id(game_id, player_id) do
    with {:ok, players} <- PlayerStore.list_players(game_id) do
      case Enum.reject(players, &(&1.player_id == player_id)) do
        [%GamePlayer{player_id: opponent_player_id}] -> {:ok, opponent_player_id}
        [] -> {:error, :opponent_not_found}
        _players -> {:error, :expected_two_players}
      end
    end
  end
end

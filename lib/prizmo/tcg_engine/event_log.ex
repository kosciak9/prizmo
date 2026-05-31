defmodule Prizmo.TcgEngine.EventLog do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [bulk_destroy: 3, create: 3, update: 3]

  alias Prizmo.TcgEngine
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameSnapshot
  alias Prizmo.TcgEngine.Snapshot

  require Ash.Query

  def write_event(%Game{} = game, type, player_id, payload) do
    with {:ok, current_game} <- get_game(game.id),
         :ok <- truncate_future_branch(current_game),
         index = current_game.cursor_index + 1,
         {:ok, event} <-
           create(GameEvent, :create, %{
             game_id: current_game.id,
             index: index,
             type: Atom.to_string(type),
             player_id: player_id,
             payload: stringify_map(payload)
           }),
         {:ok, _game} <-
           update(current_game, :record_event_cursor, %{
             cursor_index: index,
             latest_event_index: index
           }) do
      {:ok, event}
    end
  end

  def write_event_and_snapshot(game_id, type, player_id, payload) do
    with {:ok, game} <- get_game(game_id),
         {:ok, event} <- write_event(game, type, player_id, payload),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, event}
    end
  end

  def write_snapshot(game_id, event_id, index) do
    with {:ok, snapshot} <- Snapshot.dump(game_id) do
      create(GameSnapshot, :create, %{
        game_id: game_id,
        game_event_id: event_id,
        index: index,
        snapshot: snapshot
      })
    end
  end

  defp truncate_future_branch(%Game{
         id: game_id,
         cursor_index: cursor_index,
         latest_event_index: latest_event_index
       })
       when cursor_index < latest_event_index do
    with {:ok, :destroyed} <- destroy_future_snapshots(game_id, cursor_index),
         {:ok, :destroyed} <- destroy_future_events(game_id, cursor_index) do
      :ok
    end
  end

  defp truncate_future_branch(%Game{}), do: :ok

  defp destroy_future_snapshots(game_id, cursor_index) do
    GameSnapshot
    |> Ash.Query.filter(game_id == ^game_id and index > ^cursor_index)
    |> bulk_destroy(:destroy, %{})
  end

  defp destroy_future_events(game_id, cursor_index) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game_id and index > ^cursor_index)
    |> bulk_destroy(:destroy, %{})
  end

  defp get_game(game_id) do
    case TcgEngine.get_game_by_id(game_id) do
      {:ok, %Game{} = game} -> {:ok, game}
      {:ok, nil} -> {:error, :game_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end

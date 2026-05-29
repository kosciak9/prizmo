defmodule Prizmo.TcgEngine.SnapshotRestorer do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameSnapshot
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  def restore(game_id, index) do
    with {:ok, snapshot} <- get_snapshot(game_id, index),
         snapshot_data = snapshot.snapshot,
         {:ok, game} <- get_game(game_id),
         {:ok, _game} <- restore_game(game, Map.fetch!(snapshot_data, "game")),
         :ok <- restore_players(game_id, Map.fetch!(snapshot_data, "players")),
         :ok <- restore_setup(game_id, Map.get(snapshot_data, "setup")),
         :ok <- restore_turns(game_id, Map.get(snapshot_data, "turns", [])),
         :ok <- restore_cards(game_id, Map.fetch!(snapshot_data, "cards")) do
      get_game(game_id)
    end
  end

  defp get_game(game_id) do
    case TcgEngine.get_game_by_id(game_id) do
      {:ok, %Game{} = game} -> {:ok, game}
      {:ok, nil} -> {:error, :game_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_snapshot(game_id, index) do
    case GameSnapshot
         |> Ash.Query.filter(game_id == ^game_id and index == ^index)
         |> Ash.read_one() do
      {:ok, %GameSnapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, nil} -> {:error, {:snapshot_not_found, index}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_game(%Game{} = game, data) do
    update(game, :restore, %{
      status: string_to_existing_atom(Map.fetch!(data, "status")),
      active_player_id: Map.fetch!(data, "active_player_id"),
      first_player_id: Map.fetch!(data, "first_player_id"),
      winner_player_id: Map.get(data, "winner_player_id"),
      cursor_index: Map.fetch!(data, "cursor_index"),
      latest_event_index: max(game.latest_event_index, Map.fetch!(data, "latest_event_index"))
    })
  end

  defp restore_setup(_game_id, nil), do: :ok

  defp restore_setup(game_id, data) do
    with {:ok, setup} <- get_setup(game_id),
         {:ok, _setup} <-
           update(setup, :restore, %{status: string_to_existing_atom(Map.fetch!(data, "status"))}) do
      :ok
    end
  end

  defp restore_players(game_id, player_snapshots) do
    with {:ok, players} <- PlayerStore.list_players(game_id) do
      players_by_id = Map.new(players, &{&1.id, &1})

      player_snapshots
      |> Enum.map(fn data ->
        player = Map.fetch!(players_by_id, Map.fetch!(data, "id"))

        update(player, :restore, %{
          energy_attached_this_turn?: Map.fetch!(data, "energy_attached_this_turn?"),
          supporter_played_this_turn?: Map.fetch!(data, "supporter_played_this_turn?"),
          retreated_this_turn?: Map.fetch!(data, "retreated_this_turn?"),
          ace_spec_played_this_game?: Map.fetch!(data, "ace_spec_played_this_game?")
        })
      end)
      |> collect_results()
      |> case do
        {:ok, _players} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp restore_turns(game_id, turn_snapshots) do
    with {:ok, turns} <- TurnStore.list_all_turns(game_id) do
      turns_by_id = Map.new(turns, &{&1.id, &1})
      snapshot_turn_ids = MapSet.new(turn_snapshots, &Map.fetch!(&1, "id"))

      restore_visible_turns =
        Enum.map(turn_snapshots, fn data ->
          case Map.fetch(turns_by_id, Map.fetch!(data, "id")) do
            {:ok, turn} ->
              update(turn, :restore, %{
                status: string_to_existing_atom(Map.fetch!(data, "status")),
                visible?: true,
                pending_attack_id:
                  maybe_string_to_existing_atom(Map.get(data, "pending_attack_id")),
                pending_attacker_card_instance_id:
                  Map.get(data, "pending_attacker_card_instance_id"),
                pending_defender_card_instance_id:
                  Map.get(data, "pending_defender_card_instance_id")
              })

            :error ->
              {:ok, :snapshot_references_deleted_turn}
          end
        end)

      hide_future_turns =
        turns
        |> Enum.reject(&MapSet.member?(snapshot_turn_ids, &1.id))
        |> Enum.map(&update(&1, :restore, %{status: &1.status, visible?: false}))

      (restore_visible_turns ++ hide_future_turns)
      |> collect_results()
      |> case do
        {:ok, _turns} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp restore_cards(game_id, card_snapshots) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      cards_by_id = Map.new(cards, &{&1.id, &1})

      card_snapshots
      |> Enum.map(fn data ->
        card = Map.fetch!(cards_by_id, Map.fetch!(data, "id"))

        update(card, :restore, %{
          zone: string_to_existing_atom(Map.fetch!(data, "zone")),
          position: Map.fetch!(data, "position"),
          damage: Map.fetch!(data, "damage"),
          status: maybe_string_to_existing_atom(Map.get(data, "status")),
          markers: Map.fetch!(data, "markers"),
          attached_to_card_instance_id: Map.get(data, "attached_to_card_instance_id"),
          evolves_from_card_instance_id: Map.get(data, "evolves_from_card_instance_id"),
          turn_entered_play: Map.get(data, "turn_entered_play")
        })
      end)
      |> collect_results()
      |> case do
        {:ok, _cards} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp get_setup(game_id) do
    case maybe_get_setup(game_id) do
      {:ok, %Setup{} = setup} -> {:ok, setup}
      {:ok, nil} -> {:error, :setup_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_get_setup(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one()
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp string_to_existing_atom(value) when is_atom(value), do: value
  defp string_to_existing_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp maybe_string_to_existing_atom(nil), do: nil
  defp maybe_string_to_existing_atom(value), do: string_to_existing_atom(value)
end

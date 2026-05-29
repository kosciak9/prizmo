defmodule Prizmo.TcgEngine.BoardState do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.PlayerStore

  def require_no_tool_attached(game_id, target_card_instance_id) do
    with {:ok, attachments} <- CardStore.attached_cards(game_id, target_card_instance_id),
         {:ok, tool_attached?} <- tool_attached?(attachments) do
      if tool_attached? do
        {:error, :tool_already_attached}
      else
        :ok
      end
    end
  end

  def require_no_active(game_id, player_id) do
    with {:ok, active} <- CardStore.cards_in_zone(game_id, player_id, :active) do
      case active do
        [] -> :ok
        _cards -> {:error, :active_already_chosen}
      end
    end
  end

  def require_all_players_have_active(game_id) do
    with {:ok, players} <- PlayerStore.list_players(game_id) do
      players
      |> Enum.map(fn player ->
        with {:ok, active} <- CardStore.cards_in_zone(game_id, player.player_id, :active) do
          case active do
            [_card] -> :ok
            [] -> {:error, {:missing_active, player.player_id}}
            _cards -> {:error, {:too_many_active, player.player_id}}
          end
        end
      end)
      |> collect_ok_results()
    end
  end

  def active_card(game_id, player_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active) do
      case active_cards do
        [card] -> {:ok, card}
        [] -> {:error, {:missing_active, player_id}}
        _cards -> {:error, {:too_many_active, player_id}}
      end
    end
  end

  def require_no_prizes_placed(game_id) do
    case CardStore.cards_in_zone(game_id, :prize) do
      {:ok, []} -> :ok
      {:ok, _cards} -> {:error, :prizes_already_placed}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_all_players_have_prizes(game_id, count) do
    with {:ok, players} <- PlayerStore.list_players(game_id) do
      players
      |> Enum.map(fn player ->
        with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player.player_id, :prize) do
          if length(prizes) == count do
            :ok
          else
            {:error, {:invalid_prize_count, player.player_id, length(prizes), count}}
          end
        end
      end)
      |> collect_ok_results()
    end
  end

  def maybe_finish_for_last_prize(%Game{} = game, player_id) do
    with {:ok, remaining_prizes} <- CardStore.cards_in_zone(game.id, player_id, :prize) do
      case remaining_prizes do
        [] -> update(game, :finish, %{winner_player_id: player_id})
        _prizes -> {:ok, game}
      end
    end
  end

  def maybe_finish_for_empty_board(%Game{} = game, winner_player_id, knocked_out_player_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game.id, knocked_out_player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game.id, knocked_out_player_id, :bench) do
      case {active_cards, bench_cards} do
        {[], []} -> update(game, :finish, %{winner_player_id: winner_player_id})
        _has_pokemon -> {:ok, game}
      end
    end
  end

  defp tool_attached?(attachments) do
    Enum.reduce_while(attachments, {:ok, false}, fn attachment, {:ok, false} ->
      case CardRegistry.fetch(attachment.card_id) do
        {:ok, %{supertype: :trainer, trainer_type: :tool}} -> {:halt, {:ok, true}}
        {:ok, _card} -> {:cont, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end
end

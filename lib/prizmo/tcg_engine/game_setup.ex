defmodule Prizmo.TcgEngine.GameSetup do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PlayerStore

  def first_player_id([{player_id, _deck} | _rest]), do: player_id
  def first_player_id([]), do: nil

  def require_two_players(player_decks) do
    case player_decks do
      [{player_a, _deck_a}, {player_b, _deck_b}]
      when is_binary(player_a) and is_binary(player_b) and player_a != player_b ->
        :ok

      _other ->
        {:error, :expected_two_distinct_players}
    end
  end

  def create_game_record(active_player_id) do
    create(Game, :create, %{active_player_id: active_player_id, first_player_id: active_player_id})
  end

  def create_players_and_cards(%Game{} = game, player_decks) do
    player_decks
    |> Enum.map(fn {player_id, deck} ->
      with {:ok, player} <-
             create(GamePlayer, :create, %{
               game_id: game.id,
               player_id: player_id,
               deck_key: deck_id(deck)
             }) do
        create_deck_cards(game, player, deck)
      end
    end)
    |> collect_results()
  end

  def draw_opening_cards(game_id) do
    game_id
    |> PlayerStore.list_players()
    |> then(fn
      {:ok, players} ->
        players
        |> Enum.map(&draw_opening_cards_for_player/1)
        |> collect_results()

      {:error, reason} ->
        {:error, reason}
    end)
  end

  def require_no_setup_cards_moved(game_id) do
    case CardStore.non_deck_cards(game_id) do
      {:ok, []} -> :ok
      {:ok, _cards} -> {:error, :opening_hands_already_drawn}
      {:error, reason} -> {:error, reason}
    end
  end

  def place_prize_cards(game_id) do
    game_id
    |> PlayerStore.list_players()
    |> then(fn
      {:ok, players} ->
        players
        |> Enum.map(&place_prize_cards_for_player/1)
        |> collect_results()

      {:error, reason} ->
        {:error, reason}
    end)
  end

  defp create_deck_cards(%Game{} = game, %GamePlayer{} = player, deck) do
    deck
    |> deck_card_ids()
    |> Enum.with_index(1)
    |> Enum.map(fn {card_id, position} ->
      create(CardInstance, :create, %{
        game_id: game.id,
        game_player_id: player.id,
        owner_player_id: player.player_id,
        instance_id: "#{player.player_id}-#{position}",
        card_id: card_id,
        position: position
      })
    end)
    |> collect_results()
  end

  defp deck_id(deck_module) when is_atom(deck_module), do: deck_module.id()
  defp deck_id(%{id: deck_id}) when is_binary(deck_id), do: deck_id

  defp deck_card_ids(deck_module) when is_atom(deck_module), do: deck_module.card_ids()
  defp deck_card_ids(%{card_ids: card_ids}) when is_list(card_ids), do: card_ids

  defp draw_opening_cards_for_player(%GamePlayer{} = player) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, 7) do
      cards
      |> Enum.with_index(1)
      |> Enum.map(fn {card, hand_position} ->
        update(card, :draw_to_hand, %{position: hand_position})
      end)
      |> collect_results()
    end
  end

  defp place_prize_cards_for_player(%GamePlayer{} = player) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, 6) do
      cards
      |> Enum.with_index(1)
      |> Enum.map(fn {card, prize_position} ->
        update(card, :place_prize, %{position: prize_position})
      end)
      |> collect_results()
    end
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
end

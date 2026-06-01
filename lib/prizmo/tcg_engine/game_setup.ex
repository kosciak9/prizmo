defmodule Prizmo.TcgEngine.GameSetup do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Rng

  require Ash.Query

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

  def create_game_record(active_player_id, opts \\ []) do
    attrs = %{
      active_player_id: active_player_id,
      first_player_id: active_player_id
    }

    create(Game, :create, Map.merge(attrs, Keyword.get(opts, :rng_metadata, %{})))
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

  def shuffle_decks(%Game{} = game, player_decks, seed) when is_binary(seed) do
    player_decks
    |> Enum.map(fn {player_id, deck} -> shuffle_deck(game, player_id, deck, seed) end)
    |> collect_results()
  end

  def shuffle_deck(%Game{} = game, player_id, deck, seed)
      when is_binary(player_id) and is_binary(seed) do
    with {:ok, cards} <- CardStore.cards_in_zone(game.id, player_id, :deck) do
      shuffled_cards = Rng.shuffle(cards, seed, {:opening_deck_shuffle, player_id, deck_id(deck)})

      shuffled_cards
      |> Enum.with_index(1)
      |> Enum.map(fn {card, position} ->
        update(card, :reorder_deck, %{position: position})
      end)
      |> collect_results()
      |> case do
        {:ok, cards} ->
          {:ok,
           %{
             player_id: player_id,
             deck_key: deck_id(deck),
             card_count: length(cards),
             shuffle: "opening_deck",
             rng_algorithm: Rng.algorithm()
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
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

  def opening_hand_has_basic?(game_id, player_id) do
    with {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, player_id, :hand) do
      {:ok, hand_has_basic?(hand_cards)}
    end
  end

  def mulligan_opening_hand(%Game{} = game, %GamePlayer{} = player) do
    with {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, player.player_id, :hand),
         :ok <- require_opening_hand_without_basic(hand_cards),
         {:ok, mulligan_number} <- next_mulligan_number(game.id, player.player_id),
         returned_card_ids = MapSet.new(hand_cards, & &1.id),
         {:ok, _returned_cards} <- return_hand_to_deck(game.id, player.player_id, hand_cards),
         {:ok, shuffled_cards} <- reshuffle_player_deck(game, player, mulligan_number),
         returned_cards = Enum.filter(shuffled_cards, &MapSet.member?(returned_card_ids, &1.id)),
         {:ok, hand_fact} <- draw_opening_cards_for_player(player) do
      {:ok,
       game
       |> mulligan_rng_payload(player.player_id, mulligan_number)
       |> Map.merge(%{
         player_id: player.player_id,
         deck_key: player.deck_key,
         mulligan_number: mulligan_number,
         returned_card_count: length(returned_cards),
         drawn_card_count: hand_fact.card_count,
         returned_cards: EventPayloads.moved_cards(returned_cards, :hand, :deck),
         drawn_cards: hand_fact.cards
       })}
    end
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
      |> move_fact(player.player_id, :deck, :hand)
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
      |> move_fact(player.player_id, :deck, :prize)
    end
  end

  defp require_opening_hand_without_basic([]), do: {:error, :opening_hand_not_drawn}

  defp require_opening_hand_without_basic(hand_cards) do
    if hand_has_basic?(hand_cards) do
      {:error, :opening_hand_has_basic}
    else
      :ok
    end
  end

  defp hand_has_basic?(hand_cards) do
    Enum.any?(hand_cards, &CardCatalog.basic_pokemon?(&1.card_id))
  end

  defp next_mulligan_number(game_id, player_id) do
    case GameEvent
         |> Ash.Query.filter(
           game_id == ^game_id and player_id == ^player_id and type == "opening_hand_mulligan"
         )
         |> Ash.read() do
      {:ok, events} -> {:ok, length(events) + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp return_hand_to_deck(game_id, player_id, hand_cards) do
    with {:ok, deck_count} <- CardStore.deck_count(game_id, player_id) do
      hand_cards
      |> Enum.with_index(deck_count + 1)
      |> Enum.map(fn {card, position} ->
        update(card, :shuffle_into_deck, %{attached_to_card_instance_id: nil, position: position})
      end)
      |> collect_results()
    end
  end

  defp reshuffle_player_deck(%Game{} = game, %GamePlayer{} = player, mulligan_number) do
    context = {:opening_hand_mulligan, player.player_id, mulligan_number}

    with {:ok, cards} <- CardStore.cards_in_zone(game.id, player.player_id, :deck) do
      cards
      |> shuffle_cards(game.rng_seed, context)
      |> Enum.with_index(1)
      |> Enum.map(fn {card, position} -> update(card, :reorder_deck, %{position: position}) end)
      |> collect_results()
    end
  end

  defp shuffle_cards(cards, seed, context) when is_binary(seed),
    do: Rng.shuffle(cards, seed, context)

  defp shuffle_cards(cards, _seed, _context), do: Enum.shuffle(cards)

  defp mulligan_rng_payload(%Game{rng_seed: seed} = game, player_id, mulligan_number)
       when is_binary(seed) do
    %{
      rng_algorithm: game.rng_algorithm || Rng.algorithm(),
      rng_context: mulligan_rng_context_label(player_id, mulligan_number),
      rng_seed_source: game.rng_seed_source
    }
  end

  defp mulligan_rng_payload(%Game{}, _player_id, _mulligan_number), do: %{}

  defp mulligan_rng_context_label(player_id, mulligan_number) do
    "opening_hand_mulligan:#{player_id}:#{mulligan_number}"
  end

  defp move_fact({:ok, cards}, player_id, from_zone, to_zone) do
    {:ok,
     %{
       player_id: player_id,
       card_count: length(cards),
       cards: EventPayloads.moved_cards(cards, from_zone, to_zone)
     }}
  end

  defp move_fact({:error, reason}, _player_id, _from_zone, _to_zone), do: {:error, reason}

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

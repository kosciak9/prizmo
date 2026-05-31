defmodule Prizmo.TcgEngine.Decklists do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.Mechanics

  @expected_deck_size 60

  @type card_count :: {String.t(), pos_integer()} | map()
  @type player_deck_selection :: map()

  @doc "Resolves arbitrary catalog-backed deck payloads into mechanics-ready decks."
  @spec resolve_player_decks([player_deck_selection()]) ::
          {:ok, [Mechanics.player_deck()]} | {:error, term()}
  def resolve_player_decks(player_decks) when is_list(player_decks) do
    player_decks
    |> Enum.map(&resolve_player_deck/1)
    |> collect_results()
  end

  def resolve_player_decks(_player_decks), do: {:error, :expected_player_deck_list}

  @doc "Creates a persisted game from arbitrary catalog-backed deck payloads."
  @spec create_game([player_deck_selection()], keyword()) :: {:ok, Game.t()} | {:error, term()}
  def create_game(player_decks, opts \\ [])

  def create_game(player_decks, opts) when is_list(player_decks) do
    with {:ok, resolved_player_decks} <- resolve_player_decks(player_decks) do
      Mechanics.create_game(resolved_player_decks, opts)
    end
  end

  def create_game(_player_decks, _opts), do: {:error, :expected_player_deck_list}

  defp resolve_player_deck(selection) do
    with {:ok, {player_id, deck_key, cards}} <- normalize_selection(selection),
         {:ok, counts} <- normalize_counts(deck_key, cards),
         :ok <- require_deck_size(deck_key, counts),
         {:ok, catalog_cards} <- resolve_catalog_cards(deck_key, counts),
         :ok <- require_basic_pokemon(deck_key, catalog_cards) do
      {:ok, {player_id, %{id: deck_key, card_ids: expand_counts(counts)}}}
    end
  end

  defp normalize_selection(selection) when is_map(selection) do
    with {:ok, player_id} <- required_string(selection, [:player_id, "player_id", "playerId"]),
         {:ok, deck_key} <- required_string(selection, [:deck_key, "deck_key", "deckKey"]),
         {:ok, cards} <- required_value(selection, [:cards, "cards"]) do
      {:ok, {player_id, deck_key, cards}}
    else
      {:error, reason} -> {:error, {:invalid_player_deck_selection, reason}}
    end
  end

  defp normalize_selection(selection), do: {:error, {:invalid_player_deck_selection, selection}}

  defp required_string(map, keys) do
    case required_value(map, keys) do
      {:ok, value} when is_binary(value) -> validate_non_empty_string(value)
      {:ok, value} -> {:error, {:expected_string, keys, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp required_value(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:ok, value}
        :error -> nil
      end
    end) || {:error, {:missing_required_key, keys}}
  end

  defp validate_non_empty_string(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, :blank_string}
    else
      {:ok, value}
    end
  end

  defp validate_non_empty_string(value), do: {:error, {:expected_string, value}}

  defp normalize_counts(deck_key, cards) when is_list(cards) do
    with {:ok, counts} <- cards |> Enum.map(&normalize_count/1) |> collect_results(),
         :ok <- require_unique_card_ids(deck_key, counts) do
      {:ok, counts}
    end
  end

  defp normalize_counts(_deck_key, cards), do: {:error, {:expected_card_count_list, cards}}

  defp normalize_count({card_id, count}) do
    normalize_card_count_values(card_id, count)
  end

  defp normalize_count(card) when is_map(card) do
    with {:ok, card_id} <- required_string(card, [:card_id, "card_id", "cardId"]),
         {:ok, count} <- required_value(card, [:count, "count"]) do
      normalize_card_count_values(card_id, count)
    else
      {:error, reason} -> {:error, {:invalid_deck_card_count, reason}}
    end
  end

  defp normalize_count(card), do: {:error, {:invalid_deck_card_count, card}}

  defp normalize_card_count_values(card_id, count) do
    with {:ok, card_id} <- validate_non_empty_string(card_id),
         :ok <- require_positive_integer_count(card_id, count) do
      {:ok, {card_id, count}}
    end
  end

  defp require_positive_integer_count(_card_id, count) when is_integer(count) and count > 0,
    do: :ok

  defp require_positive_integer_count(card_id, count) do
    {:error, {:invalid_card_count, card_id, count}}
  end

  defp require_unique_card_ids(deck_key, counts) do
    duplicated_card_ids =
      counts
      |> Enum.map(&elem(&1, 0))
      |> Enum.frequencies()
      |> Enum.filter(fn {_card_id, frequency} -> frequency > 1 end)
      |> Enum.map(&elem(&1, 0))

    case duplicated_card_ids do
      [] -> :ok
      card_ids -> {:error, {:duplicate_deck_card_ids, deck_key, card_ids}}
    end
  end

  defp require_deck_size(deck_key, counts) do
    total = Enum.reduce(counts, 0, fn {_card_id, count}, acc -> acc + count end)

    if total == @expected_deck_size do
      :ok
    else
      {:error, {:invalid_deck_size, deck_key, total, @expected_deck_size}}
    end
  end

  defp resolve_catalog_cards(deck_key, counts) do
    counts
    |> Enum.map(fn {card_id, _count} ->
      case CardCatalog.fetch(card_id) do
        {:ok, card} -> {:ok, {card_id, card}}
        {:error, _reason} -> {:error, card_id}
      end
    end)
    |> Enum.reduce({[], []}, fn
      {:ok, card}, {cards, unresolved} -> {[card | cards], unresolved}
      {:error, card_id}, {cards, unresolved} -> {cards, [card_id | unresolved]}
    end)
    |> case do
      {cards, []} ->
        {:ok, cards |> Enum.reverse() |> Map.new()}

      {_cards, unresolved} ->
        {:error, {:unresolved_deck_cards, deck_key, Enum.reverse(unresolved)}}
    end
  end

  defp require_basic_pokemon(deck_key, catalog_cards) do
    has_basic_pokemon? =
      Enum.any?(catalog_cards, fn {_card_id, card} ->
        match?(%{supertype: :pokemon, stage: :basic}, card)
      end)

    if has_basic_pokemon? do
      :ok
    else
      {:error, {:deck_missing_basic_pokemon, deck_key}}
    end
  end

  defp expand_counts(counts) do
    Enum.flat_map(counts, fn {card_id, count} -> List.duplicate(card_id, count) end)
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

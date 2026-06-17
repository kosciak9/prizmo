defmodule Prizmo.TcgEngine.SupportedDecks do
  @moduledoc """
  Engine/UI boundary for supported TCG deck fixtures.

  UI callers work with stable `deck_key` strings. This module resolves those
  keys into deck modules only at the engine boundary before delegating to the
  persisted mechanics layer.
  """

  alias Prizmo.Tcg.Decks
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.Mechanics
  alias Prizmo.TcgEngine.Rng

  @type deck_key :: Decks.deck_key()
  @type player_deck_selection ::
          {String.t(), deck_key()}
          | %{required(:player_id) => String.t(), required(:deck_key) => deck_key()}
          | %{required(String.t()) => String.t()}

  @doc "Returns UI-safe summaries for all supported engine deck fixtures."
  @spec list() :: [Decks.summary()]
  def list, do: Decks.playtest_list()

  @doc "Fetches a supported engine deck summary by deck key."
  @spec fetch(deck_key()) :: {:ok, Decks.summary()} | {:error, {:unsupported_deck, term()}}
  def fetch(deck_key) do
    case Decks.fetch_playtest(deck_key) do
      {:ok, deck_module} -> {:ok, Decks.summary(deck_module)}
      :error -> {:error, {:unsupported_deck, deck_key}}
    end
  end

  @type blueprint :: %{
          deck_key: deck_key(),
          name: String.t(),
          source_url: String.t(),
          card_count: non_neg_integer(),
          unique_card_count: non_neg_integer(),
          counts: [%{card_id: String.t(), count: pos_integer()}]
        }

  @doc "Returns the full blueprint (including raw card counts) for a supported deck key."
  @spec fetch_blueprint(deck_key()) :: {:ok, blueprint()} | {:error, {:unsupported_deck, term()}}
  def fetch_blueprint(deck_key) do
    case Decks.fetch_playtest(deck_key) do
      {:ok, deck_module} ->
        summary = Decks.summary(deck_module)

        {:ok,
         %{
           deck_key: summary.deck_key,
           name: summary.name,
           source_url: summary.source_url,
           card_count: summary.card_count,
           unique_card_count: summary.unique_card_count,
           counts:
             Enum.map(deck_module.counts(), fn {card_id, count} ->
               %{card_id: card_id, count: count}
             end)
         }}

      :error ->
        {:error, {:unsupported_deck, deck_key}}
    end
  end

  @doc "Resolves UI deck selections into the module tuples expected by mechanics."
  @spec resolve_player_decks([player_deck_selection()]) ::
          {:ok, [Mechanics.player_deck()]} | {:error, term()}
  def resolve_player_decks(player_decks) when is_list(player_decks) do
    player_decks
    |> Enum.map(&resolve_player_deck/1)
    |> collect_results()
  end

  def resolve_player_decks(_player_decks), do: {:error, :expected_player_deck_list}

  @doc "Creates a persisted game from supported deck keys."
  @spec create_game([player_deck_selection()], keyword()) :: {:ok, Game.t()} | {:error, term()}
  def create_game(player_decks, opts \\ [])

  def create_game(player_decks, opts) when is_list(player_decks) do
    with {:ok, resolved_player_decks} <- resolve_player_decks(player_decks),
         {:ok, rng_opts} <- supported_deck_rng_opts(opts) do
      Mechanics.create_game(resolved_player_decks, Keyword.merge(opts, rng_opts))
    end
  end

  def create_game(_player_decks, _opts), do: {:error, :expected_player_deck_list}

  defp supported_deck_rng_opts(opts) do
    case Keyword.get(opts, :rng_seed) do
      nil ->
        {:ok,
         [
           rng_seed: Rng.generate_seed(),
           rng_seed_source: "fresh",
           rng_algorithm: Rng.algorithm(),
           shuffle_decks?: true
         ]}

      seed ->
        with {:ok, seed} <- Rng.normalize_seed(seed) do
          {:ok,
           [
             rng_seed: seed,
             rng_seed_source: "explicit",
             rng_algorithm: Rng.algorithm(),
             shuffle_decks?: true
           ]}
        end
    end
  end

  defp resolve_player_deck(selection) do
    with {:ok, {player_id, deck_key}} <- normalize_selection(selection),
         {:ok, deck_module} <- fetch_deck_module(deck_key) do
      {:ok, {player_id, deck_module}}
    end
  end

  defp normalize_selection({player_id, deck_key})
       when is_binary(player_id) and is_binary(deck_key) do
    {:ok, {player_id, deck_key}}
  end

  defp normalize_selection(%{player_id: player_id, deck_key: deck_key})
       when is_binary(player_id) and is_binary(deck_key) do
    {:ok, {player_id, deck_key}}
  end

  defp normalize_selection(%{"player_id" => player_id, "deck_key" => deck_key})
       when is_binary(player_id) and is_binary(deck_key) do
    {:ok, {player_id, deck_key}}
  end

  defp normalize_selection(%{"playerId" => player_id, "deckKey" => deck_key})
       when is_binary(player_id) and is_binary(deck_key) do
    {:ok, {player_id, deck_key}}
  end

  defp normalize_selection(selection), do: {:error, {:invalid_player_deck_selection, selection}}

  defp fetch_deck_module(deck_key) do
    case Decks.fetch_playtest(deck_key) do
      {:ok, deck_module} -> {:ok, deck_module}
      :error -> {:error, {:unsupported_deck, deck_key}}
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

defmodule Prizmo.Tcg.Goal1.SeedFinder do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.SupportedDecks

  @opening_hand_size 7

  @type player_requirement :: %{
          required(:player_id) => String.t(),
          required(:deck_key) => String.t(),
          optional(:all_of) => [String.t()],
          optional(:any_of) => [String.t()],
          optional(:require_basic?) => boolean()
        }

  @type search_opts :: [
          prefix: String.t(),
          start: pos_integer(),
          attempts: pos_integer(),
          limit: pos_integer()
        ]

  @doc "Finds supported-deck seeds whose opening hands satisfy target-card constraints."
  @spec find_supported_opening_seeds([player_requirement()], search_opts()) ::
          {:ok, [map()]} | {:error, term()}
  def find_supported_opening_seeds(player_requirements, opts \\ [])

  def find_supported_opening_seeds(player_requirements, opts) when is_list(player_requirements) do
    with {:ok, normalized_requirements} <- normalize_player_requirements(player_requirements),
         {:ok, prefix} <- normalize_prefix(Keyword.get(opts, :prefix, "goal1-seed")),
         {:ok, start} <- normalize_positive_integer(Keyword.get(opts, :start, 1), :start),
         {:ok, attempts} <-
           normalize_positive_integer(Keyword.get(opts, :attempts, 1000), :attempts),
         {:ok, limit} <- normalize_positive_integer(Keyword.get(opts, :limit, 5), :limit),
         {:ok, player_decks} <-
           SupportedDecks.resolve_player_decks(
             Enum.map(normalized_requirements, &Map.take(&1, [:player_id, :deck_key]))
           ),
         {:ok, player_specs} <- build_player_specs(normalized_requirements, player_decks) do
      {:ok, collect_seed_matches(player_specs, prefix, start, attempts, limit)}
    end
  end

  def find_supported_opening_seeds(_player_requirements, _opts) do
    {:error, :expected_player_requirement_list}
  end

  defp collect_seed_matches(player_specs, prefix, start, attempts, limit) do
    start
    |> Range.new(start + attempts - 1)
    |> Enum.reduce_while([], fn seed_index, acc ->
      result = simulate_seed(player_specs, "#{prefix}-#{seed_index}", seed_index)

      if Enum.all?(result.players, & &1.matched?) do
        next = [result | acc]

        if length(next) >= limit do
          {:halt, Enum.reverse(next)}
        else
          {:cont, next}
        end
      else
        {:cont, acc}
      end
    end)
  end

  defp simulate_seed(player_specs, seed, seed_index) do
    %{
      seed: seed,
      seed_index: seed_index,
      players: Enum.map(player_specs, &simulate_player_seed(&1, seed))
    }
  end

  defp simulate_player_seed(player_spec, seed) do
    opening_hand_ids =
      player_spec.deck_module.card_ids()
      |> Rng.shuffle(seed, {:opening_deck_shuffle, player_spec.player_id, player_spec.deck_key})
      |> Enum.take(@opening_hand_size)

    opening_hand = Enum.map(opening_hand_ids, &hand_card_summary/1)
    basic_count = Enum.count(opening_hand, & &1.basic?)
    all_of_matches = Enum.filter(player_spec.all_of, &(&1 in opening_hand_ids))
    any_of_matches = Enum.filter(player_spec.any_of, &(&1 in opening_hand_ids))

    %{
      player_id: player_spec.player_id,
      deck_key: player_spec.deck_key,
      deck_name: player_spec.deck_name,
      opening_hand: opening_hand,
      opening_hand_card_ids: opening_hand_ids,
      basic_count: basic_count,
      require_basic?: player_spec.require_basic?,
      all_of: player_spec.all_of,
      all_of_matches: all_of_matches,
      any_of: player_spec.any_of,
      any_of_matches: any_of_matches,
      matched?:
        basic_requirement_met?(player_spec.require_basic?, basic_count) and
          length(all_of_matches) == length(player_spec.all_of) and
          any_requirement_met?(player_spec, any_of_matches)
    }
  end

  defp basic_requirement_met?(false, _basic_count), do: true
  defp basic_requirement_met?(true, basic_count), do: basic_count > 0

  defp any_requirement_met?(%{any_of: []}, _matches), do: true
  defp any_requirement_met?(%{any_of: _any_of}, matches), do: matches != []

  defp hand_card_summary(card_id) do
    card = CardCatalog.fetch!(card_id)

    %{
      card_id: card_id,
      name: card.name,
      basic?: match?(%{supertype: :pokemon, stage: :basic}, card)
    }
  end

  defp normalize_player_requirements(player_requirements) do
    player_requirements
    |> Enum.map(&normalize_player_requirement/1)
    |> collect_results()
  end

  defp normalize_player_requirement(requirement) when is_map(requirement) do
    with {:ok, player_id} <- fetch_required_string(requirement, :player_id),
         {:ok, deck_key} <- fetch_required_string(requirement, :deck_key),
         {:ok, all_of} <- normalize_card_id_list(Map.get(requirement, :all_of, []), :all_of),
         {:ok, any_of} <- normalize_card_id_list(Map.get(requirement, :any_of, []), :any_of),
         {:ok, require_basic?} <- normalize_boolean(Map.get(requirement, :require_basic?, true)) do
      {:ok,
       %{
         player_id: player_id,
         deck_key: deck_key,
         all_of: all_of,
         any_of: any_of,
         require_basic?: require_basic?
       }}
    end
  end

  defp normalize_player_requirement(requirement) do
    {:error, {:invalid_player_requirement, requirement}}
  end

  defp fetch_required_string(requirement, key) do
    case Map.fetch(requirement, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_requirement_field, key, value}}
      :error -> {:error, {:missing_requirement_field, key}}
    end
  end

  defp normalize_card_id_list(values, key) when is_list(values) do
    values
    |> Enum.map(fn
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, {:invalid_requirement_field, key, value}}
    end)
    |> collect_results()
  end

  defp normalize_card_id_list(values, key),
    do: {:error, {:invalid_requirement_field, key, values}}

  defp normalize_boolean(value) when is_boolean(value), do: {:ok, value}

  defp normalize_boolean(value),
    do: {:error, {:invalid_requirement_field, :require_basic?, value}}

  defp build_player_specs(requirements, player_decks) do
    resolved_by_player = Map.new(player_decks)

    requirements
    |> Enum.map(fn requirement ->
      case Map.fetch(resolved_by_player, requirement.player_id) do
        {:ok, deck_module} -> build_player_spec(requirement, deck_module)
        :error -> {:error, {:unresolved_player_deck, requirement.player_id}}
      end
    end)
    |> collect_results()
  end

  defp build_player_spec(requirement, deck_module) do
    deck_card_ids = MapSet.new(deck_module.card_ids())
    target_card_ids = Enum.uniq(requirement.all_of ++ requirement.any_of)

    case Enum.reject(target_card_ids, &MapSet.member?(deck_card_ids, &1)) do
      [] ->
        {:ok,
         %{
           player_id: requirement.player_id,
           deck_key: requirement.deck_key,
           deck_name: deck_module.name(),
           deck_module: deck_module,
           all_of: requirement.all_of,
           any_of: requirement.any_of,
           require_basic?: requirement.require_basic?
         }}

      missing_card_ids ->
        {:error,
         {:target_cards_not_in_deck, requirement.player_id, requirement.deck_key,
          missing_card_ids}}
    end
  end

  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix = String.trim(prefix)

    if prefix == "" do
      {:error, :blank_prefix}
    else
      {:ok, prefix}
    end
  end

  defp normalize_prefix(prefix), do: {:error, {:invalid_prefix, prefix}}

  defp normalize_positive_integer(value, _key) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp normalize_positive_integer(value, key),
    do: {:error, {:invalid_positive_integer, key, value}}

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

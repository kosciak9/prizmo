defmodule Prizmo.Tcg.Decklist do
  @moduledoc """
  Compile-time helper for shared TCG deck modules.

  Deck modules intentionally contain only source identity and card quantities.
  Static card facts belong to the card metadata cache/registry, not decklists.
  """

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__), only: [deck: 1]
    end
  end

  defmacro deck(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    source_url = Keyword.fetch!(opts, :source_url)
    counts = Keyword.fetch!(opts, :counts)
    validate? = Keyword.get(opts, :validate, true)

    validate!(id, name, source_url, counts, validate?)

    quote do
      @id unquote(id)
      @name unquote(name)
      @source_url unquote(source_url)
      @cards unquote(Macro.escape(counts))

      def id, do: @id
      def name, do: @name
      def source_url, do: @source_url
      def counts, do: @cards

      def card_ids do
        Enum.flat_map(@cards, fn {card_id, count} -> List.duplicate(card_id, count) end)
      end
    end
  end

  defp validate!(id, name, source_url, counts, validate?) do
    validate_non_empty_string!(:id, id)
    validate_non_empty_string!(:name, name)
    validate_non_empty_string!(:source_url, source_url)
    validate_counts!(counts)

    if validate? do
      validate_total!(id, counts)
    end
  end

  defp validate_non_empty_string!(field, value) when is_binary(value) do
    if String.trim(value) == "" do
      raise ArgumentError, "deck #{field} must not be blank"
    end
  end

  defp validate_non_empty_string!(field, _value) do
    raise ArgumentError, "deck #{field} must be a string"
  end

  defp validate_counts!(counts) when is_list(counts) do
    Enum.each(counts, fn
      {card_id, count} when is_binary(card_id) and is_integer(count) and count > 0 ->
        if String.trim(card_id) == "" do
          raise ArgumentError, "deck card IDs must not be blank"
        end

      other ->
        raise ArgumentError,
              "deck counts must be {card_id, positive_count} tuples, got: #{inspect(other)}"
    end)

    duplicated_card_ids =
      counts
      |> Enum.map(&elem(&1, 0))
      |> Enum.frequencies()
      |> Enum.filter(fn {_card_id, frequency} -> frequency > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicated_card_ids != [] do
      raise ArgumentError,
            "deck counts duplicate card IDs: #{Enum.join(duplicated_card_ids, ", ")}"
    end
  end

  defp validate_counts!(_counts) do
    raise ArgumentError, "deck counts must be a list"
  end

  defp validate_total!(id, counts) do
    total = Enum.sum(Enum.map(counts, &elem(&1, 1)))

    if total != 60 do
      raise ArgumentError, "deck #{id} must contain exactly 60 cards, got: #{total}"
    end
  end
end

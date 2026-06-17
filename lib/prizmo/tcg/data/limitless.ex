defmodule Prizmo.Tcg.Data.Limitless do
  @moduledoc """
  Minimal Limitless fetch helpers for roadmap-driven corpus audits.

  This module intentionally stays small: it only fetches live deck overview pages
  and extracts the latest deck-list ids visible on those pages. That is enough to
  detect when the committed Goal 1 fixture corpus has drifted from the current
  latest-Limitless result universe without forcing those live decks into the
  legacy known-deck pool.
  """

  @base_url "https://limitlesstcg.com"
  @decklist_card_block_regex ~r/<div class="decklist-card"[^>]*data-set="([A-Z0-9]+)"[^>]*data-number="([0-9A-Z]+)"[^>]*>(.*?)<\/div>/s
  @decklist_card_count_regex ~r/<span class="card-count">(\d+)<\/span>/
  @decklist_card_name_regex ~r/<span class="card-name">([^<]+)<\/span>/
  @decklist_title_regex ~r/<div class="decklist-title">\s*([^<\n]+)\s*/

  @type deck_id :: String.t() | pos_integer()
  @type deck_list_id :: String.t()
  @type decklist_entry :: %{card_id: String.t(), count: pos_integer(), name: String.t()}
  @type decklist :: %{
          id: deck_list_id(),
          name: String.t(),
          source_url: String.t(),
          entries: [decklist_entry()],
          counts: [{String.t(), pos_integer()}]
        }

  @doc "Returns the live Limitless overview URL for a deck archetype id."
  @spec deck_url(deck_id()) :: String.t()
  def deck_url(deck_id), do: @base_url <> "/decks/" <> normalize_id(deck_id)

  @doc "Returns the live Limitless URL for a concrete deck list id."
  @spec deck_list_url(deck_list_id()) :: String.t()
  def deck_list_url(deck_list_id), do: @base_url <> "/decks/list/" <> normalize_id(deck_list_id)

  @doc "Fetches and parses a concrete Limitless deck list page into card counts."
  @spec fetch_decklist!(deck_list_id()) :: decklist()
  def fetch_decklist!(deck_list_id) do
    deck_list_id = normalize_id(deck_list_id)
    html = fetch_html!(deck_list_url(deck_list_id))
    entries = extract_decklist_entries(html)

    %{
      id: deck_list_id,
      name: extract_decklist_name(html),
      source_url: deck_list_url(deck_list_id),
      entries: entries,
      counts: Enum.map(entries, &{&1.card_id, &1.count})
    }
  end

  @doc """
  Fetches the latest result deck-list ids shown on a Limitless deck overview page.

  The result is ordered as shown by the page and de-duplicated so downstream
  roadmap audits can compare live latest-result ids against committed fixtures.
  """
  @spec fetch_latest_result_list_ids!(deck_id()) :: [deck_list_id()]
  def fetch_latest_result_list_ids!(deck_id) do
    deck_id
    |> deck_url()
    |> fetch_html!()
    |> extract_deck_list_ids()
  end

  defp fetch_html!(url) do
    ensure_req_started!()

    case Req.get(url: url, retry: false, receive_timeout: 30_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise RuntimeError, "Limitless request failed with HTTP #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise RuntimeError, "Limitless request failed: #{Exception.message(reason)}"
    end
  end

  defp extract_deck_list_ids(html) do
    ~r{/decks/list/(\d+)}
    |> Regex.scan(html)
    |> Enum.map(&Enum.at(&1, 1))
    |> Enum.uniq()
  end

  defp extract_decklist_name(html) do
    case Regex.run(@decklist_title_regex, html) do
      [_, name] -> String.trim(name)
      _other -> "Limitless Deck"
    end
  end

  defp extract_decklist_entries(html) do
    entries =
      @decklist_card_block_regex
      |> Regex.scan(html)
      |> Enum.map(fn [_, set, number, block] ->
        %{
          card_id: prizmo_card_id(set, number),
          count:
            block
            |> extract_required_capture!(@decklist_card_count_regex, "card count")
            |> String.to_integer(),
          name:
            block
            |> extract_required_capture!(@decklist_card_name_regex, "card name")
            |> String.trim()
            |> decode_html_entities()
        }
      end)

    validate_decklist_entries!(entries)
  end

  defp validate_decklist_entries!([]) do
    raise RuntimeError, "Limitless decklist parser found no cards"
  end

  defp validate_decklist_entries!(entries) do
    total_count = Enum.reduce(entries, 0, fn entry, total -> total + entry.count end)

    if total_count != 60 do
      raise RuntimeError, "Limitless decklist must contain exactly 60 cards, got: #{total_count}"
    end

    duplicated_card_ids =
      entries
      |> Enum.map(& &1.card_id)
      |> Enum.frequencies()
      |> Enum.filter(fn {_card_id, frequency} -> frequency > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicated_card_ids != [] do
      raise RuntimeError,
            "Limitless decklist duplicated card ids: #{Enum.join(duplicated_card_ids, ", ")}"
    end

    entries
  end

  defp prizmo_card_id(set, number) do
    normalized_number =
      case Integer.parse(number) do
        {integer, ""} -> integer |> Integer.to_string() |> String.pad_leading(3, "0")
        _other -> String.upcase(number)
      end

    String.upcase(set) <> "-" <> normalized_number
  end

  defp decode_html_entities(value) do
    value
    |> String.replace("&#039;", "'")
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
  end

  defp extract_required_capture!(value, regex, label) do
    case Regex.run(regex, value) do
      [_, capture] -> capture
      _other -> raise RuntimeError, "Limitless decklist parser missing #{label}"
    end
  end

  defp normalize_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_id(value) when is_binary(value), do: value

  defp ensure_req_started! do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} -> :ok
      {:error, reason} -> raise RuntimeError, "failed to start Req: #{inspect(reason)}"
    end
  end
end

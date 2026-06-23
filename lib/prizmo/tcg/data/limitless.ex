defmodule Prizmo.Tcg.Data.Limitless do
  @moduledoc """
  Minimal Limitless fetch helpers for roadmap-driven corpus audits.

  This module intentionally stays parser-light, but it now supports three live
  surfaces needed by the current roadmap:

  - metagame archetype rows from `/decks`
  - latest-result deck-list ids from `/decks/:id`
  - per-archetype card breakdowns from `/decks/:id/cards`
  """

  @base_url "https://limitlesstcg.com"
  @decklist_card_block_regex ~r/<div class="decklist-card"[^>]*data-set="([A-Z0-9]+)"[^>]*data-number="([0-9A-Z]+)"[^>]*>(.*?)<\/div>/s
  @decklist_card_count_regex ~r/<span class="card-count">(\d+)<\/span>/
  @breakdown_card_count_regex ~r/<span class="card-count">([0-9]+(?:\.[0-9]+)?)<\/span>/
  @decklist_card_name_regex ~r/<span class="card-name">([^<]+)<\/span>/
  @decklist_title_regex ~r/<div class="decklist-title">\s*([^<\n]+)\s*/
  @metagame_row_regex ~r/<tr>\s*<td>(\d+)<\/td>\s*<td>.*?<\/td>\s*<td><a href="\/decks\/(\d+)">(.*?)<\/a><\/td>\s*<td>([^<]*)<\/td>\s*<td>([0-9.]+)%<\/td>\s*<\/tr>/s
  @metagame_format_regex ~r/<span class="label">Format:<\/span>\s*([^<\n]+)\s*<\/li>/
  @deck_name_regex ~r/<h1 class="name">([^<]+)<\/h1>/
  @breakdown_format_regex ~r/<div class="dropdown-select" data-reload data-key="format">\s*([^<]+?)\s*<span class="sub">([0-9,]+) decklists<\/span>/s

  @type deck_id :: String.t() | pos_integer()
  @type deck_list_id :: String.t()
  @type decklist_entry :: %{card_id: String.t(), count: pos_integer(), name: String.t()}
  @type metagame_row :: %{
          rank: non_neg_integer(),
          overview_deck_id: String.t(),
          name: String.t(),
          points: non_neg_integer() | nil,
          share_percent: float(),
          source_url: String.t()
        }
  @type metagame_snapshot :: %{
          source_url: String.t(),
          format: String.t() | nil,
          rows: [metagame_row()]
        }
  @type card_breakdown_entry :: %{card_id: String.t(), average_count: float(), name: String.t()}
  @type card_breakdown :: %{
          overview_deck_id: String.t(),
          name: String.t(),
          format: String.t() | nil,
          decklist_count: non_neg_integer() | nil,
          source_url: String.t(),
          entries: [card_breakdown_entry()]
        }
  @type decklist :: %{
          id: deck_list_id(),
          name: String.t(),
          source_url: String.t(),
          entries: [decklist_entry()],
          counts: [{String.t(), pos_integer()}]
        }

  @doc "Returns the live Limitless metagame URL."
  @spec metagame_url(keyword()) :: String.t()
  def metagame_url(opts \\ []) do
    @base_url <> "/decks" <> encode_query_string(Keyword.put_new(opts, :show, 100))
  end

  @doc "Returns the live Limitless overview URL for a deck archetype id."
  @spec deck_url(deck_id()) :: String.t()
  def deck_url(deck_id), do: @base_url <> "/decks/" <> normalize_id(deck_id)

  @doc "Returns the live Limitless detailed card breakdown URL for an archetype id."
  @spec deck_cards_url(deck_id(), keyword()) :: String.t()
  def deck_cards_url(deck_id, opts \\ []) do
    @base_url <> "/decks/" <> normalize_id(deck_id) <> "/cards" <> encode_query_string(opts)
  end

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

  @doc "Fetches the current live metagame archetype rows from Limitless."
  @spec fetch_metagame_snapshot!(keyword()) :: metagame_snapshot()
  def fetch_metagame_snapshot!(opts \\ []) do
    url = metagame_url(opts)
    html = fetch_html!(url)

    %{
      source_url: url,
      format: extract_active_metagame_format(html),
      rows: extract_metagame_rows(html)
    }
  end

  @doc "Fetches and parses a Limitless archetype card-breakdown page."
  @spec fetch_deck_card_breakdown!(deck_id(), keyword()) :: card_breakdown()
  def fetch_deck_card_breakdown!(deck_id, opts \\ []) do
    deck_id = normalize_id(deck_id)
    url = deck_cards_url(deck_id, opts)
    html = fetch_html!(url)
    {format, decklist_count} = extract_breakdown_format_and_count(html)

    %{
      overview_deck_id: deck_id,
      name: extract_deck_name(html),
      format: format,
      decklist_count: decklist_count,
      source_url: url,
      entries: extract_card_breakdown_entries(html)
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

  defp extract_deck_name(html) do
    case Regex.run(@deck_name_regex, html) do
      [_, name] -> name |> decode_html_entities() |> String.trim()
      _other -> "Limitless Archetype"
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

  defp extract_card_breakdown_entries(html) do
    entries =
      @decklist_card_block_regex
      |> Regex.scan(html)
      |> Enum.map(fn [_, set, number, block] ->
        %{
          card_id: prizmo_card_id(set, number),
          average_count:
            block
            |> extract_required_capture!(@breakdown_card_count_regex, "card count")
            |> Float.parse()
            |> case do
              {value, ""} ->
                value

              _other ->
                raise RuntimeError, "Limitless card breakdown parser found invalid card count"
            end,
          name:
            block
            |> extract_required_capture!(@decklist_card_name_regex, "card name")
            |> String.trim()
            |> decode_html_entities()
        }
      end)

    validate_breakdown_entries!(entries)
  end

  defp extract_metagame_rows(html) do
    @metagame_row_regex
    |> Regex.scan(html)
    |> Enum.map(fn [_, rank, deck_id, name_html, points, share_percent] ->
      %{
        rank: String.to_integer(rank),
        overview_deck_id: deck_id,
        name: name_html |> strip_html_tags() |> decode_html_entities() |> normalize_whitespace(),
        points: parse_optional_integer(points),
        share_percent: parse_percent!(share_percent),
        source_url: deck_url(deck_id)
      }
    end)
  end

  defp extract_active_metagame_format(html) do
    case Regex.run(@metagame_format_regex, html) do
      [_, format] -> String.trim(format)
      _other -> nil
    end
  end

  defp extract_breakdown_format_and_count(html) do
    case Regex.run(@breakdown_format_regex, html) do
      [_, format, decklist_count] ->
        {String.trim(format), decklist_count |> String.replace(",", "") |> String.to_integer()}

      _other ->
        {nil, nil}
    end
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

  defp validate_breakdown_entries!([]) do
    raise RuntimeError, "Limitless card breakdown parser found no cards"
  end

  defp validate_breakdown_entries!(entries) do
    duplicated_card_ids =
      entries
      |> Enum.map(& &1.card_id)
      |> Enum.frequencies()
      |> Enum.filter(fn {_card_id, frequency} -> frequency > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicated_card_ids != [] do
      raise RuntimeError,
            "Limitless card breakdown duplicated card ids: #{Enum.join(duplicated_card_ids, ", ")}"
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

  defp strip_html_tags(value) do
    String.replace(value, ~r/<[^>]+>/, " ")
  end

  defp normalize_whitespace(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_required_capture!(value, regex, label) do
    case Regex.run(regex, value) do
      [_, capture] -> capture
      _other -> raise RuntimeError, "Limitless decklist parser missing #{label}"
    end
  end

  defp parse_optional_integer(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      String.to_integer(value)
    end
  end

  defp parse_percent!(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _other -> raise RuntimeError, "Limitless metagame parser found invalid share percent"
    end
  end

  defp encode_query_string([]), do: ""

  defp encode_query_string(opts) do
    query = URI.encode_query(opts)
    if query == "", do: "", else: "?" <> query
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

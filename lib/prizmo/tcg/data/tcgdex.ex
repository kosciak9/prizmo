defmodule Prizmo.Tcg.Data.TCGdex do
  @moduledoc """
  TCGdex adapter and on-disk cache helpers for simulator card metadata.

  Prizmo card IDs remain the public simulator IDs in `SET-localId` form. This
  module maps those IDs to TCGdex card IDs and writes API responses into the
  committed metadata cache under `priv/tcg/cards/tcgdex`.

  The cache stores TCGdex static card facts and raw printed text. Dynamic market
  pricing fields are intentionally removed so normal tests can rely on stable,
  offline metadata files.
  """

  @api_base_url "https://api.tcgdex.net/v2/en"
  @cache_root Path.join(["priv", "tcg", "cards", "tcgdex"])

  @known_deck_modules [
    Prizmo.Tcg.Decks.Dragapult27431,
    Prizmo.Tcg.Decks.Alakazam27147,
    Prizmo.Tcg.Decks.RagingBoltOgerpon27599,
    Prizmo.Tcg.Decks.FestivalLead27445,
    Prizmo.Tcg.Decks.LopunnyDudunsparce27514,
    Prizmo.Tcg.Decks.RocketMewtwo27459
  ]

  @tcgdex_set_id_by_prizmo_abbreviation %{
    "ASC" => "me02.5",
    "DRI" => "sv10",
    "JTG" => "sv09",
    "MEE" => "mee",
    "MEG" => "me01",
    "PFL" => "me02",
    "POR" => "me03",
    "PRE" => "sv08.5",
    "SCR" => "sv07",
    "SFA" => "sv06.5",
    "SSP" => "sv08",
    "SVI" => "sv01",
    "TEF" => "sv05",
    "TWM" => "sv06",
    "WHT" => "sv10.5w"
  }

  @doc "Returns the repository-relative TCGdex cache root."
  def cache_root(opts \\ []) do
    opts
    |> Keyword.get(:root, @cache_root)
    |> Path.expand(File.cwd!())
  end

  @doc "Returns known deck modules whose metadata should be cached."
  def known_deck_modules, do: @known_deck_modules

  @doc "Returns unique Prizmo card IDs across all known deck modules."
  def known_card_ids do
    @known_deck_modules
    |> Enum.flat_map(& &1.counts())
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Returns the TCGdex card ID for a Prizmo card ID."
  def tcgdex_card_id!(
        prizmo_card_id,
        set_id_by_abbreviation \\ @tcgdex_set_id_by_prizmo_abbreviation
      ) do
    case String.split(prizmo_card_id, "-", parts: 2) do
      [set_abbreviation, local_id] ->
        case Map.fetch(set_id_by_abbreviation, set_abbreviation) do
          {:ok, tcgdex_set_id} ->
            "#{tcgdex_set_id}-#{local_id}"

          :error ->
            raise ArgumentError,
                  "unknown TCGdex set mapping for Prizmo set #{inspect(set_abbreviation)}"
        end

      _other ->
        raise ArgumentError, "invalid Prizmo card ID #{inspect(prizmo_card_id)}"
    end
  end

  @doc "Returns the cache path for a Prizmo card ID."
  def card_cache_path(prizmo_card_id, opts \\ []) do
    Path.join([cache_root(opts), "cards", "#{prizmo_card_id}.json"])
  end

  @doc "Returns the cache path for selected TCGdex set metadata."
  def sets_cache_path(opts \\ []) do
    Path.join(cache_root(opts), "sets.json")
  end

  @doc "Reads a cached card payload by Prizmo card ID."
  def read_cached_card!(prizmo_card_id, opts \\ []) do
    prizmo_card_id
    |> card_cache_path(opts)
    |> read_json!()
  end

  @doc "Synchronizes TCGdex metadata for all cards in the known deck pool."
  def sync_known_decks!(opts \\ []) do
    ensure_req_started!()

    root = cache_root(opts)
    refresh? = Keyword.get(opts, :refresh?, false)
    sets = load_or_fetch_sets!(root, refresh?)
    set_index = set_id_by_official_abbreviation!(sets)

    card_results = Enum.map(known_card_ids(), &sync_card!(&1, set_index, root, refresh?))

    %{
      cache_root: root,
      sets: length(sets),
      cards: length(card_results),
      written_cards: count_results(card_results, :written),
      cached_cards: count_results(card_results, :cached)
    }
  end

  defp load_or_fetch_sets!(root, refresh?) do
    path = sets_cache_path(root: root)

    if File.exists?(path) and not refresh? do
      path
      |> read_json!()
      |> Map.fetch!("sets")
    else
      sets =
        @tcgdex_set_id_by_prizmo_abbreviation
        |> Enum.sort_by(fn {abbreviation, _set_id} -> abbreviation end)
        |> Enum.map(fn {abbreviation, tcgdex_set_id} ->
          fetch_set!(tcgdex_set_id, abbreviation)
        end)

      write_json!(path, sets_payload(sets))

      sets
    end
  end

  defp fetch_set!(tcgdex_set_id, expected_abbreviation) do
    set =
      "sets/#{tcgdex_set_id}"
      |> fetch_json!()
      |> strip_dynamic_fields()
      |> Map.delete("cards")

    actual_abbreviation = get_in(set, ["abbreviation", "official"])

    if actual_abbreviation != expected_abbreviation do
      raise ArgumentError,
            "TCGdex set #{tcgdex_set_id} reported abbreviation " <>
              "#{inspect(actual_abbreviation)}, expected #{inspect(expected_abbreviation)}"
    end

    set
  end

  defp sync_card!(prizmo_card_id, set_index, root, refresh?) do
    path = card_cache_path(prizmo_card_id, root: root)

    if File.exists?(path) and not refresh? do
      {:cached, prizmo_card_id}
    else
      tcgdex_card_id = tcgdex_card_id!(prizmo_card_id, set_index)

      card =
        "cards/#{tcgdex_card_id}"
        |> fetch_json!()
        |> strip_dynamic_fields()

      if Map.fetch!(card, "id") != tcgdex_card_id do
        raise ArgumentError,
              "TCGdex card #{tcgdex_card_id} returned payload for #{inspect(card["id"])}"
      end

      write_json!(path, card_payload(prizmo_card_id, tcgdex_card_id, card))

      {:written, prizmo_card_id}
    end
  end

  defp set_id_by_official_abbreviation!(sets) do
    set_index =
      Map.new(sets, fn set ->
        abbreviation = get_in(set, ["abbreviation", "official"])
        id = Map.fetch!(set, "id")

        if is_nil(abbreviation) do
          raise ArgumentError, "TCGdex set #{inspect(id)} has no official abbreviation"
        end

        {abbreviation, id}
      end)

    missing_abbreviations =
      known_card_ids()
      |> Enum.map(fn card_id -> card_id |> String.split("-", parts: 2) |> hd() end)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(set_index, &1))

    if missing_abbreviations != [] do
      raise ArgumentError,
            "TCGdex set cache is missing Prizmo set abbreviations: " <>
              Enum.join(Enum.sort(missing_abbreviations), ", ")
    end

    set_index
  end

  defp sets_payload(sets) do
    %{
      "source" => source_payload(),
      "sets" => sets
    }
  end

  defp card_payload(prizmo_card_id, tcgdex_card_id, card) do
    %{
      "prizmo_id" => prizmo_card_id,
      "source" => source_payload(),
      "tcgdex" => card,
      "tcgdex_id" => tcgdex_card_id
    }
  end

  defp source_payload do
    %{
      "base_url" => @api_base_url,
      "dynamic_fields_removed" => ["pricing"],
      "language" => "en",
      "provider" => "TCGdex"
    }
  end

  defp fetch_json!(path) do
    url = @api_base_url <> "/" <> path

    case Req.get(url: url, retry: false, receive_timeout: 30_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        decode_body!(body)

      {:ok, %{status: status, body: body}} ->
        raise RuntimeError, "TCGdex request failed with HTTP #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise RuntimeError, "TCGdex request failed: #{Exception.message(reason)}"
    end
  end

  defp decode_body!(body) when is_binary(body), do: Jason.decode!(body)
  defp decode_body!(body), do: body

  defp strip_dynamic_fields(%{} = map) do
    map
    |> Map.delete("pricing")
    |> Map.new(fn {key, value} -> {key, strip_dynamic_fields(value)} end)
  end

  defp strip_dynamic_fields(list) when is_list(list), do: Enum.map(list, &strip_dynamic_fields/1)
  defp strip_dynamic_fields(value), do: value

  # sobelow_skip ["Traversal.FileModule"] paths are generated under the repository card cache.
  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  # sobelow_skip ["Traversal.FileModule"] paths are generated under the repository card cache.
  defp write_json!(path, data) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, [Jason.encode_to_iodata!(data, pretty: true), "\n"])
  end

  defp ensure_req_started! do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} -> :ok
      {:error, reason} -> raise RuntimeError, "failed to start Req: #{inspect(reason)}"
    end
  end

  defp count_results(results, status) do
    Enum.count(results, fn {result_status, _prizmo_card_id} -> result_status == status end)
  end
end

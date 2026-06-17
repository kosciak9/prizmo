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

  @type deck_id :: String.t() | pos_integer()
  @type deck_list_id :: String.t()

  @doc "Returns the live Limitless overview URL for a deck archetype id."
  @spec deck_url(deck_id()) :: String.t()
  def deck_url(deck_id), do: @base_url <> "/decks/" <> normalize_id(deck_id)

  @doc "Returns the live Limitless URL for a concrete deck list id."
  @spec deck_list_url(deck_list_id()) :: String.t()
  def deck_list_url(deck_list_id), do: @base_url <> "/decks/list/" <> normalize_id(deck_list_id)

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

  defp normalize_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_id(value) when is_binary(value), do: value

  defp ensure_req_started! do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} -> :ok
      {:error, reason} -> raise RuntimeError, "failed to start Req: #{inspect(reason)}"
    end
  end
end

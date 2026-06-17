defmodule Prizmo.Tcg.Decks do
  @moduledoc """
  Shared catalog of supported static TCG deck fixtures.

  Deck modules remain the source of truth for card counts. This catalog is the
  stable boundary for callers that need to list or resolve committed fixtures
  without depending on individual deck modules. The broader Goal 1 latest-
  Limitless playtest pool is exposed separately so browser validation can use
  the live fixture universe without widening the legacy known-deck smoke pool.
  """

  alias Prizmo.Tcg.Decks.Alakazam27147
  alias Prizmo.Tcg.Decks.Dragapult27431
  alias Prizmo.Tcg.Decks.FestivalLead27445
  alias Prizmo.Tcg.Decks.LopunnyDudunsparce27514
  alias Prizmo.Tcg.Decks.RagingBoltOgerpon27599
  alias Prizmo.Tcg.Decks.RocketMewtwo27459
  alias Prizmo.Tcg.Goal1.LatestLimitless

  @modules [
    Dragapult27431,
    Prizmo.Tcg.Decks.DragapultBlaziken28253,
    Prizmo.Tcg.Decks.DragapultDusknoir28236,
    Prizmo.Tcg.Decks.DragapultPlain28256,
    Alakazam27147,
    RagingBoltOgerpon27599,
    FestivalLead27445,
    LopunnyDudunsparce27514,
    RocketMewtwo27459
  ]

  @playtest_supplemental_modules [
    Dragapult27431,
    Alakazam27147,
    RagingBoltOgerpon27599,
    FestivalLead27445,
    LopunnyDudunsparce27514,
    RocketMewtwo27459
  ]

  @type deck_key :: String.t()
  @type deck_module :: module()
  @type summary :: %{
          deck_key: deck_key(),
          name: String.t(),
          source_url: String.t(),
          card_count: non_neg_integer(),
          unique_card_count: non_neg_integer()
        }

  @doc "Returns supported deck fixture modules."
  @spec modules() :: [deck_module()]
  def modules, do: @modules

  @doc "Returns the expanded fixture pool used by Goal 1 browser/play-surface validation."
  @spec playtest_modules() :: [deck_module()]
  def playtest_modules do
    LatestLimitless.fixture_modules()
    |> Kernel.++(@playtest_supplemental_modules)
    |> uniq_by_deck_key()
  end

  @doc "Returns UI-safe summaries for all supported deck fixtures."
  @spec list() :: [summary()]
  def list do
    Enum.map(modules(), &summary/1)
  end

  @doc "Returns UI-safe summaries for the Goal 1 playtest fixture pool."
  @spec playtest_list() :: [summary()]
  def playtest_list do
    Enum.map(playtest_modules(), &summary/1)
  end

  @doc "Fetches a supported deck module by its fixture key."
  @spec fetch(deck_key()) :: {:ok, deck_module()} | :error
  def fetch(deck_key) when is_binary(deck_key) do
    fetch_from(deck_key, modules())
  end

  def fetch(_deck_key), do: :error

  @doc "Fetches a Goal 1 playtest deck module by its fixture key."
  @spec fetch_playtest(deck_key()) :: {:ok, deck_module()} | :error
  def fetch_playtest(deck_key) when is_binary(deck_key) do
    fetch_from(deck_key, playtest_modules())
  end

  def fetch_playtest(_deck_key), do: :error

  @doc "Builds a UI-safe summary for a supported deck module."
  @spec summary(deck_module()) :: summary()
  def summary(deck_module) when is_atom(deck_module) do
    counts = deck_module.counts()

    %{
      deck_key: deck_module.id(),
      name: deck_module.name(),
      source_url: deck_module.source_url(),
      card_count: card_count(counts),
      unique_card_count: length(counts)
    }
  end

  defp card_count(counts) do
    Enum.reduce(counts, 0, fn {_card_id, count}, total -> total + count end)
  end

  defp fetch_from(deck_key, deck_modules) do
    case Enum.find(deck_modules, &(&1.id() == deck_key)) do
      nil -> :error
      deck_module -> {:ok, deck_module}
    end
  end

  defp uniq_by_deck_key(deck_modules) do
    deck_modules
    |> Enum.reduce({MapSet.new(), []}, fn deck_module, {seen_keys, acc} ->
      deck_key = deck_module.id()

      if MapSet.member?(seen_keys, deck_key) do
        {seen_keys, acc}
      else
        {MapSet.put(seen_keys, deck_key), [deck_module | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end

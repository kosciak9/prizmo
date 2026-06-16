defmodule Prizmo.Tcg.Decks do
  @moduledoc """
  Shared catalog of supported static TCG deck fixtures.

  Deck modules remain the source of truth for card counts. This catalog is the
  stable boundary for callers that need to list or resolve committed fixtures
  without depending on individual deck modules.
  """

  @modules [
    Prizmo.Tcg.Decks.Dragapult27431,
    Prizmo.Tcg.Decks.DragapultBlaziken28253,
    Prizmo.Tcg.Decks.DragapultDusknoir28236,
    Prizmo.Tcg.Decks.DragapultPlain28256,
    Prizmo.Tcg.Decks.Alakazam27147,
    Prizmo.Tcg.Decks.RagingBoltOgerpon27599,
    Prizmo.Tcg.Decks.FestivalLead27445,
    Prizmo.Tcg.Decks.LopunnyDudunsparce27514,
    Prizmo.Tcg.Decks.RocketMewtwo27459
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

  @doc "Returns UI-safe summaries for all supported deck fixtures."
  @spec list() :: [summary()]
  def list do
    Enum.map(@modules, &summary/1)
  end

  @doc "Fetches a supported deck module by its fixture key."
  @spec fetch(deck_key()) :: {:ok, deck_module()} | :error
  def fetch(deck_key) when is_binary(deck_key) do
    case Enum.find(@modules, &(&1.id() == deck_key)) do
      nil -> :error
      deck_module -> {:ok, deck_module}
    end
  end

  def fetch(_deck_key), do: :error

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
end

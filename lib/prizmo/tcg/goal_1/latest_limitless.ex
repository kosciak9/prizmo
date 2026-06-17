defmodule Prizmo.Tcg.Goal1.LatestLimitless do
  @moduledoc """
  Audits the live Goal 1 latest-Limitless deck-result universe.

  Goal 1 is defined in the knowledge base as "Dragapult + Alakazam latest-
  Limitless completeness". The historical fixture deck catalog predates that
  scope and should not be assumed current without a live comparison.
  """

  alias Prizmo.Tcg.Data.Limitless
  alias Prizmo.Tcg.Decks.Alakazam27147
  alias Prizmo.Tcg.Decks.Dragapult27431
  alias Prizmo.Tcg.Decks.DragapultBlaziken28253
  alias Prizmo.Tcg.Decks.DragapultDusknoir28236
  alias Prizmo.Tcg.Decks.DragapultPlain28256

  @type audit_row :: %{
          key: atom(),
          label: String.t(),
          overview_deck_id: String.t(),
          overview_url: String.t(),
          committed_fixture_ids: [String.t()],
          committed_fixture_urls: [String.t()],
          latest_result_list_ids: [String.t()],
          latest_result_list_urls: [String.t()],
          missing_fixture_ids: [String.t()],
          stale_fixture_ids: [String.t()]
        }

  @goal_1_archetypes [
    %{
      key: :dragapult,
      label: "Dragapult",
      overview_deck_id: "284",
      fixture_modules: [
        Dragapult27431,
        DragapultDusknoir28236,
        DragapultBlaziken28253,
        DragapultPlain28256
      ]
    },
    %{
      key: :alakazam,
      label: "Alakazam",
      overview_deck_id: "350",
      fixture_modules: [Alakazam27147]
    }
  ]

  @doc "Returns the archetypes currently tracked by the Goal 1 audit."
  @spec tracked_archetypes() :: [map()]
  def tracked_archetypes, do: @goal_1_archetypes

  @doc "Builds the live-versus-committed Goal 1 audit rows for all archetypes."
  @spec audit!() :: [audit_row()]
  def audit! do
    Enum.map(@goal_1_archetypes, &audit_archetype!/1)
  end

  defp audit_archetype!(archetype) do
    committed_fixture_ids = Enum.map(archetype.fixture_modules, & &1.id())
    latest_result_list_ids = Limitless.fetch_latest_result_list_ids!(archetype.overview_deck_id)

    %{
      key: archetype.key,
      label: archetype.label,
      overview_deck_id: archetype.overview_deck_id,
      overview_url: Limitless.deck_url(archetype.overview_deck_id),
      committed_fixture_ids: committed_fixture_ids,
      committed_fixture_urls: Enum.map(archetype.fixture_modules, & &1.source_url()),
      latest_result_list_ids: latest_result_list_ids,
      latest_result_list_urls: Enum.map(latest_result_list_ids, &Limitless.deck_list_url/1),
      missing_fixture_ids: latest_result_list_ids -- committed_fixture_ids,
      stale_fixture_ids: committed_fixture_ids -- latest_result_list_ids
    }
  end
end

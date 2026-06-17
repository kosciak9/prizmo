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
  alias Prizmo.Tcg.Goal1.CardCoverage

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

  @type corpus_card_row :: %{
          card_id: String.t(),
          name: String.t(),
          live_deck_ids: [String.t()],
          in_committed_fixture_corpus: boolean(),
          metadata_status: :cached | :missing,
          coverage_status: CardCoverage.coverage_status(),
          rules_status: atom(),
          rules_label: String.t()
        }

  @type corpus_row :: %{
          key: atom(),
          label: String.t(),
          overview_deck_id: String.t(),
          overview_url: String.t(),
          committed_fixture_ids: [String.t()],
          latest_result_list_ids: [String.t()],
          live_unique_card_count: non_neg_integer(),
          committed_fixture_unique_card_count: non_neg_integer(),
          newly_in_scope_card_ids: [String.t()],
          coverage_status_counts: %{optional(CardCoverage.coverage_status()) => non_neg_integer()},
          metadata_status_counts: %{optional(:cached | :missing) => non_neg_integer()},
          newly_in_scope_cards: [corpus_card_row()],
          incomplete_live_cards: [corpus_card_row()],
          cards: [corpus_card_row()]
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

  @doc "Builds the live Goal 1 card-corpus reconciliation report for all archetypes."
  @spec corpus_report!() :: [corpus_row()]
  def corpus_report! do
    Enum.map(@goal_1_archetypes, &corpus_archetype!/1)
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

  defp corpus_archetype!(archetype) do
    committed_fixture_ids = Enum.map(archetype.fixture_modules, & &1.id())
    latest_result_list_ids = Limitless.fetch_latest_result_list_ids!(archetype.overview_deck_id)
    live_decklists = Enum.map(latest_result_list_ids, &Limitless.fetch_decklist!/1)
    committed_fixture_card_ids = committed_fixture_card_ids(archetype.fixture_modules)

    live_cards =
      live_decklists
      |> live_card_index()
      |> Enum.map(&corpus_card_row(&1, committed_fixture_card_ids))
      |> sort_card_rows()

    newly_in_scope_cards = Enum.reject(live_cards, & &1.in_committed_fixture_corpus)

    %{
      key: archetype.key,
      label: archetype.label,
      overview_deck_id: archetype.overview_deck_id,
      overview_url: Limitless.deck_url(archetype.overview_deck_id),
      committed_fixture_ids: committed_fixture_ids,
      latest_result_list_ids: latest_result_list_ids,
      live_unique_card_count: length(live_cards),
      committed_fixture_unique_card_count: length(committed_fixture_card_ids),
      newly_in_scope_card_ids: Enum.map(newly_in_scope_cards, & &1.card_id),
      coverage_status_counts: Enum.frequencies_by(live_cards, & &1.coverage_status),
      metadata_status_counts: Enum.frequencies_by(live_cards, & &1.metadata_status),
      newly_in_scope_cards: newly_in_scope_cards,
      incomplete_live_cards:
        Enum.filter(live_cards, &(&1.coverage_status in [:partial, :unimplemented])),
      cards: live_cards
    }
  end

  defp committed_fixture_card_ids(fixture_modules) do
    fixture_modules
    |> Enum.flat_map(& &1.counts())
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp live_card_index(decklists) do
    Enum.reduce(decklists, %{}, fn decklist, acc ->
      Enum.reduce(decklist.entries, acc, fn entry, acc ->
        Map.update(
          acc,
          entry.card_id,
          %{name: entry.name, live_deck_ids: [decklist.id]},
          fn row ->
            %{row | live_deck_ids: Enum.uniq([decklist.id | row.live_deck_ids])}
          end
        )
      end)
    end)
  end

  defp corpus_card_row(
         {card_id, %{name: name, live_deck_ids: live_deck_ids}},
         committed_fixture_card_ids
       ) do
    summary = CardCoverage.summarize(card_id)
    metadata_status = if(summary.rules_status == :unknown, do: :missing, else: :cached)

    %{
      card_id: card_id,
      name: name,
      live_deck_ids: Enum.sort(live_deck_ids),
      in_committed_fixture_corpus: card_id in committed_fixture_card_ids,
      metadata_status: metadata_status,
      coverage_status: summary.coverage_status,
      rules_status: summary.rules_status,
      rules_label: summary.rules_label
    }
  end

  defp sort_card_rows(card_rows) do
    Enum.sort_by(card_rows, fn row ->
      {coverage_priority(row.coverage_status), -length(row.live_deck_ids), row.card_id}
    end)
  end

  defp coverage_priority(:unimplemented), do: 0
  defp coverage_priority(:partial), do: 1
  defp coverage_priority(:generic_supported), do: 2
  defp coverage_priority(:supported), do: 3
end

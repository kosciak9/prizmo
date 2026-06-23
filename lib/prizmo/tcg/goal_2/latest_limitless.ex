defmodule Prizmo.Tcg.Goal2.LatestLimitless do
  @moduledoc """
  Goal 2 latest-Limitless metagame and card-corpus reporting.

  Goal 2 is defined in the knowledge base as top-30 latest-Limitless archetype
  coverage by usage. This module fetches the live metagame table, selects the
  current top archetypes by share, and builds a card corpus from each
  archetype's detailed card breakdown page.
  """

  alias Prizmo.Tcg.CardCoverage
  alias Prizmo.Tcg.Data.Limitless

  @default_limit 30

  @type archetype_row :: %{
          rank: non_neg_integer(),
          overview_deck_id: String.t(),
          name: String.t(),
          points: non_neg_integer() | nil,
          share_percent: float(),
          source_url: String.t()
        }

  @type archetype_report_row :: %{
          rank: non_neg_integer(),
          overview_deck_id: String.t(),
          name: String.t(),
          share_percent: float(),
          points: non_neg_integer() | nil,
          source_url: String.t(),
          card_count: non_neg_integer(),
          coverage_status_counts: %{optional(CardCoverage.coverage_status()) => non_neg_integer()},
          metadata_status_counts: %{optional(:cached | :missing) => non_neg_integer()},
          incomplete_cards: [corpus_card_row()]
        }

  @type corpus_card_row :: %{
          card_id: String.t(),
          name: String.t(),
          archetype_names: [String.t()],
          archetype_ids: [String.t()],
          archetype_count: non_neg_integer(),
          total_share_percent: float(),
          metadata_status: :cached | :missing,
          coverage_status: CardCoverage.coverage_status(),
          rules_status: atom(),
          rules_label: String.t()
        }

  @type corpus_report :: %{
          source_url: String.t(),
          metagame_format: String.t() | nil,
          top_archetype_count: non_neg_integer(),
          top_archetypes: [archetype_report_row()],
          tracked_card_count: non_neg_integer(),
          coverage_status_counts: %{optional(CardCoverage.coverage_status()) => non_neg_integer()},
          metadata_status_counts: %{optional(:cached | :missing) => non_neg_integer()},
          incomplete_cards: [corpus_card_row()],
          cards: [corpus_card_row()]
        }

  @doc "Returns the current top Goal 2 archetypes by live metagame share."
  @spec top_archetypes!(pos_integer()) :: [archetype_row()]
  def top_archetypes!(limit \\ @default_limit) when is_integer(limit) and limit > 0 do
    Limitless.fetch_metagame_snapshot!()
    |> Map.fetch!(:rows)
    |> select_top_archetypes(limit)
  end

  @doc "Builds the live Goal 2 top-archetype card corpus report."
  @spec corpus_report!(pos_integer()) :: corpus_report()
  def corpus_report!(limit \\ @default_limit) when is_integer(limit) and limit > 0 do
    snapshot = Limitless.fetch_metagame_snapshot!()
    top_archetypes = select_top_archetypes(snapshot.rows, limit)

    breakdowns_by_id =
      Map.new(top_archetypes, fn archetype ->
        {archetype.overview_deck_id,
         Limitless.fetch_deck_card_breakdown!(archetype.overview_deck_id)}
      end)

    cards =
      top_archetypes
      |> build_corpus_index(breakdowns_by_id)
      |> Enum.map(&corpus_card_row/1)
      |> sort_card_rows()

    %{
      source_url: snapshot.source_url,
      metagame_format: snapshot.format,
      top_archetype_count: length(top_archetypes),
      top_archetypes: Enum.map(top_archetypes, &archetype_report_row(&1, breakdowns_by_id)),
      tracked_card_count: length(cards),
      coverage_status_counts: Enum.frequencies_by(cards, & &1.coverage_status),
      metadata_status_counts: Enum.frequencies_by(cards, & &1.metadata_status),
      incomplete_cards: Enum.filter(cards, &(&1.coverage_status in [:partial, :unimplemented])),
      cards: cards
    }
  end

  defp select_top_archetypes(rows, limit) do
    rows
    |> Enum.filter(&(&1.share_percent > 0.0))
    |> Enum.sort_by(fn row -> {-row.share_percent, -(row.points || 0), row.name} end)
    |> Enum.take(limit)
  end

  defp archetype_report_row(archetype, breakdowns_by_id) do
    entries = scoped_breakdown_entries(breakdowns_by_id[archetype.overview_deck_id])

    rows =
      entries
      |> Enum.map(fn entry ->
        summary = CardCoverage.summarize(entry.card_id)
        metadata_status = if(summary.rules_status == :unknown, do: :missing, else: :cached)

        %{
          card_id: entry.card_id,
          name: entry.name,
          archetype_names: [archetype.name],
          archetype_ids: [archetype.overview_deck_id],
          archetype_count: 1,
          total_share_percent: archetype.share_percent,
          metadata_status: metadata_status,
          coverage_status: summary.coverage_status,
          rules_status: summary.rules_status,
          rules_label: summary.rules_label
        }
      end)
      |> sort_card_rows()

    %{
      rank: archetype.rank,
      overview_deck_id: archetype.overview_deck_id,
      name: archetype.name,
      share_percent: archetype.share_percent,
      points: archetype.points,
      source_url: archetype.source_url,
      card_count: length(rows),
      coverage_status_counts: Enum.frequencies_by(rows, & &1.coverage_status),
      metadata_status_counts: Enum.frequencies_by(rows, & &1.metadata_status),
      incomplete_cards: Enum.filter(rows, &(&1.coverage_status in [:partial, :unimplemented]))
    }
  end

  defp build_corpus_index(top_archetypes, breakdowns_by_id) do
    Enum.reduce(top_archetypes, %{}, fn archetype, acc ->
      entries = scoped_breakdown_entries(breakdowns_by_id[archetype.overview_deck_id])

      Enum.reduce(entries, acc, fn entry, acc ->
        Map.update(
          acc,
          entry.card_id,
          %{
            card_id: entry.card_id,
            name: entry.name,
            archetype_names: [archetype.name],
            archetype_ids: [archetype.overview_deck_id],
            total_share_percent: archetype.share_percent
          },
          fn row ->
            %{
              row
              | archetype_names: Enum.sort(Enum.uniq([archetype.name | row.archetype_names])),
                archetype_ids:
                  Enum.sort(Enum.uniq([archetype.overview_deck_id | row.archetype_ids])),
                total_share_percent: row.total_share_percent + archetype.share_percent
            }
          end
        )
      end)
    end)
  end

  defp corpus_card_row({_card_id, row}) do
    summary = CardCoverage.summarize(row.card_id)
    metadata_status = if(summary.rules_status == :unknown, do: :missing, else: :cached)

    %{
      card_id: row.card_id,
      name: row.name,
      archetype_names: row.archetype_names,
      archetype_ids: row.archetype_ids,
      archetype_count: length(row.archetype_ids),
      total_share_percent: Float.round(row.total_share_percent, 2),
      metadata_status: metadata_status,
      coverage_status: summary.coverage_status,
      rules_status: summary.rules_status,
      rules_label: summary.rules_label
    }
  end

  defp scoped_breakdown_entries(%{entries: entries}) do
    Enum.filter(entries, &(&1.average_count > 0.0))
  end

  defp sort_card_rows(card_rows) do
    Enum.sort_by(card_rows, fn row ->
      {coverage_priority(row.coverage_status), -row.archetype_count, -row.total_share_percent,
       row.card_id}
    end)
  end

  defp coverage_priority(:unimplemented), do: 0
  defp coverage_priority(:partial), do: 1
  defp coverage_priority(:generic_supported), do: 2
  defp coverage_priority(:supported), do: 3
end

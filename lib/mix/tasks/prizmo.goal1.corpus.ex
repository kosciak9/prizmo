defmodule Mix.Tasks.Prizmo.Goal1.Corpus do
  @shortdoc "Reports Goal 1 live latest-Limitless card corpus"

  @moduledoc """
  Fetches the live latest-result decklists for the Goal 1 archetypes and
  compares their current card corpus against the committed fixture corpus.

      mix prizmo.goal1.corpus
  """

  use Mix.Task

  alias Prizmo.Tcg.Goal1.LatestLimitless

  @impl Mix.Task
  def run(_args) do
    LatestLimitless.corpus_report!()
    |> format_report()
    |> Mix.shell().info()
  end

  defp format_report(rows) do
    [
      "Goal 1 latest-Limitless corpus report",
      "",
      Enum.map(rows, &format_row/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_row(row) do
    [
      "#{row.label} (overview #{row.overview_deck_id})",
      "  committed fixtures: #{join_or_none(row.committed_fixture_ids)}",
      "  latest result deck ids: #{join_or_none(row.latest_result_list_ids)}",
      "  live unique cards: #{row.live_unique_card_count}",
      "  committed fixture unique cards: #{row.committed_fixture_unique_card_count}",
      "  newly in scope cards: #{join_or_none(row.newly_in_scope_card_ids)}",
      "  coverage: #{format_counts(row.coverage_status_counts)}",
      "  metadata: #{format_counts(row.metadata_status_counts)}",
      "  newly in scope details:",
      format_card_rows(row.newly_in_scope_cards),
      "  live cards still not fully supported:",
      format_card_rows(row.incomplete_live_cards),
      ""
    ]
  end

  defp format_card_rows([]), do: ["    none"]

  defp format_card_rows(rows) do
    Enum.map(rows, fn row ->
      coverage = row.coverage_status |> Atom.to_string() |> String.replace("_", "-")
      metadata = Atom.to_string(row.metadata_status)
      decks = Enum.join(row.live_deck_ids, ", ")

      "    - #{row.card_id} #{row.name} [#{coverage}; metadata=#{metadata}; decks=#{decks}]"
    end)
  end

  defp join_or_none([]), do: "none"
  defp join_or_none(values), do: Enum.join(values, ", ")

  defp format_counts(counts) when map_size(counts) == 0, do: "none"

  defp format_counts(counts) do
    counts
    |> Enum.sort_by(fn {status, _count} -> Atom.to_string(status) end)
    |> Enum.map_join(", ", fn {status, count} ->
      status = status |> Atom.to_string() |> String.replace("_", "-")
      "#{status}=#{count}"
    end)
  end
end

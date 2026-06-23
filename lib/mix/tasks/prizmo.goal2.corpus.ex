defmodule Mix.Tasks.Prizmo.Goal2.Corpus do
  @shortdoc "Reports Goal 2 top-30 latest-Limitless card corpus"

  @moduledoc """
  Fetches the live Limitless metagame page, selects the current top 30
  archetypes by share, and reports the combined card corpus from their detailed
  card breakdown pages.

      mix prizmo.goal2.corpus
  """

  use Mix.Task

  alias Prizmo.Tcg.Goal2.LatestLimitless

  @impl Mix.Task
  def run(_args) do
    LatestLimitless.corpus_report!()
    |> format_report()
    |> Mix.shell().info()
  end

  defp format_report(report) do
    [
      "Goal 2 latest-Limitless top-30 corpus report",
      "",
      "metagame format: #{report.metagame_format || "unknown"}",
      "source: #{report.source_url}",
      "top archetypes: #{report.top_archetype_count}",
      "tracked cards: #{report.tracked_card_count}",
      "coverage: #{format_counts(report.coverage_status_counts)}",
      "metadata: #{format_counts(report.metadata_status_counts)}",
      "",
      "top archetypes:",
      Enum.map(report.top_archetypes, &format_archetype_row/1),
      "",
      "cards still not fully supported:",
      format_card_rows(report.incomplete_cards)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_archetype_row(row) do
    [
      "  - #{row.rank}. #{row.name} [overview #{row.overview_deck_id}; share=#{format_percent(row.share_percent)}; cards=#{row.card_count}]",
      "    coverage: #{format_counts(row.coverage_status_counts)}",
      "    metadata: #{format_counts(row.metadata_status_counts)}",
      "    incomplete: #{join_or_none(Enum.map(row.incomplete_cards, & &1.card_id))}"
    ]
  end

  defp format_card_rows([]), do: ["  none"]

  defp format_card_rows(rows) do
    Enum.map(rows, fn row ->
      coverage = row.coverage_status |> Atom.to_string() |> String.replace("_", "-")
      metadata = Atom.to_string(row.metadata_status)
      archetypes = Enum.join(row.archetype_names, ", ")

      "  - #{row.card_id} #{row.name} [#{coverage}; metadata=#{metadata}; archetypes=#{row.archetype_count}; total-share=#{format_percent(row.total_share_percent)}; decks=#{archetypes}]"
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

  defp format_percent(value) do
    :erlang.float_to_binary(value, decimals: 2) <> "%"
  end
end

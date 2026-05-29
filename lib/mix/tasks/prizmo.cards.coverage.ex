defmodule Mix.Tasks.Prizmo.Cards.Coverage do
  @shortdoc "Reports coverage for the known TCG deck pool"

  @moduledoc """
  Reports current metadata-cache and registry-overlay behavior coverage.

      mix prizmo.cards.coverage

  The report is offline and covers the known meta-deck pool while behavior
  overlays are migrated toward the meta-deck north-star plan.
  """

  use Mix.Task

  alias Prizmo.Tcg.Sim.RegistryCoverage

  @impl Mix.Task
  def run(_args) do
    RegistryCoverage.report()
    |> format_report()
    |> Mix.shell().info()
  end

  defp format_report(report) do
    [
      "Known TCG deck coverage",
      "Source: #{report.source}",
      "",
      "Decks:",
      format_decks(report.decks),
      "",
      "Summary:",
      "  cards: #{report.summary.card_count}",
      "  cards in known decks: #{report.summary.deck_card_count}",
      "  metadata: #{format_counts(report.summary.metadata_statuses)}",
      "  behavior: #{format_counts(report.summary.behavior_statuses)}",
      "  behavior families: #{format_counts(report.summary.behavior_family_statuses)}",
      "",
      "Cards:",
      format_cards(report.cards)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_decks(decks) do
    Enum.map(decks, fn deck ->
      unsupported =
        case deck.unsupported_card_ids do
          [] -> "none"
          card_ids -> Enum.join(card_ids, ", ")
        end

      "  #{deck.id} #{deck.name}: #{deck.card_count} cards, " <>
        "#{deck.unique_card_count} unique, unsupported: #{unsupported}"
    end)
  end

  defp format_cards(cards) do
    rows =
      Enum.map(cards, fn card ->
        [
          card.card_id,
          card.name,
          deck_list(card.decks),
          Atom.to_string(card.metadata_status),
          Atom.to_string(card.behavior_status)
        ]
      end)

    widths = column_widths([["Card", "Name", "Decks", "Metadata", "Behavior"] | rows])

    [format_row(["Card", "Name", "Decks", "Metadata", "Behavior"], widths), separator(widths)] ++
      Enum.map(rows, &format_row(&1, widths))
  end

  defp format_counts(counts) when map_size(counts) == 0, do: "none"

  defp format_counts(counts) do
    Enum.map_join(counts, ", ", fn {status, count} -> "#{status}=#{count}" end)
  end

  defp deck_list([]), do: "-"
  defp deck_list(decks), do: Enum.join(decks, ",")

  defp column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn column ->
      column
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp format_row(row, widths) do
    row
    |> Enum.zip(widths)
    |> Enum.map_join("  ", fn {value, width} -> String.pad_trailing(value, width) end)
  end

  defp separator(widths) do
    Enum.map_join(widths, "  ", &String.duplicate("-", &1))
  end
end

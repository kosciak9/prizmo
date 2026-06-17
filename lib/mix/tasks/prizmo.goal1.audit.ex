defmodule Mix.Tasks.Prizmo.Goal1.Audit do
  @shortdoc "Audits Goal 1 live latest-Limitless deck ids"

  @moduledoc """
  Fetches the live Limitless overview pages for Goal 1 archetypes and compares
  the current latest-result deck-list ids against the committed Goal 1 fixture
  corpus in the repository.

      mix prizmo.goal1.audit
  """

  use Mix.Task

  alias Prizmo.Tcg.Goal1.LatestLimitless

  @impl Mix.Task
  def run(_args) do
    LatestLimitless.audit!()
    |> format_report()
    |> Mix.shell().info()
  end

  defp format_report(rows) do
    [
      "Goal 1 latest-Limitless audit",
      "",
      Enum.map(rows, &format_row/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_row(row) do
    [
      "#{row.label} (overview #{row.overview_deck_id})",
      "  live overview: #{row.overview_url}",
      "  committed fixtures: #{join_or_none(row.committed_fixture_ids)}",
      "  latest result deck ids: #{join_or_none(row.latest_result_list_ids)}",
      "  missing fixtures: #{join_or_none(row.missing_fixture_ids)}",
      "  stale fixtures: #{join_or_none(row.stale_fixture_ids)}",
      ""
    ]
  end

  defp join_or_none([]), do: "none"
  defp join_or_none(values), do: Enum.join(values, ", ")
end

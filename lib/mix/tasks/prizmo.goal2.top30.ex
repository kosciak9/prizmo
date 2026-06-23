defmodule Mix.Tasks.Prizmo.Goal2.Top30 do
  @shortdoc "Reports Goal 2 latest-Limitless top 30 archetypes"

  @moduledoc """
  Fetches the live Limitless metagame page and reports the current top 30
  archetypes by share for Goal 2 roadmap work.

      mix prizmo.goal2.top30
  """

  use Mix.Task

  alias Prizmo.Tcg.Goal2.LatestLimitless

  @impl Mix.Task
  def run(_args) do
    LatestLimitless.top_archetypes!()
    |> format_report()
    |> Mix.shell().info()
  end

  defp format_report(rows) do
    [
      "Goal 2 latest-Limitless top 30 archetypes",
      "",
      Enum.map(rows, &format_row/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_row(row) do
    points = if(is_integer(row.points), do: Integer.to_string(row.points), else: "n/a")

    "#{row.rank}. #{row.name} [overview #{row.overview_deck_id}; share=#{format_percent(row.share_percent)}; points=#{points}]"
  end

  defp format_percent(value) do
    :erlang.float_to_binary(value, decimals: 2) <> "%"
  end
end

defmodule Mix.Tasks.Prizmo.Cards.Sync do
  @shortdoc "Synchronizes TCGdex metadata cache for known TCG decks"

  @moduledoc """
  Synchronizes the committed TCGdex metadata cache for the known deck pool.

      mix prizmo.cards.sync
      mix prizmo.cards.sync --refresh

  This task is networked by design and should be run explicitly. Normal tests use
  the committed cache and do not call TCGdex.
  """

  use Mix.Task

  alias Prizmo.Tcg.Data.TCGdex

  @impl Mix.Task
  def run(args) do
    refresh? = parse_refresh!(args)

    report = TCGdex.sync_known_decks!(refresh?: refresh?)

    Mix.shell().info("TCGdex metadata cache synchronized")
    Mix.shell().info("  cache root: #{Path.relative_to_cwd(report.cache_root)}")
    Mix.shell().info("  sets: #{report.sets}")
    Mix.shell().info("  cards: #{report.cards}")
    Mix.shell().info("  written cards: #{report.written_cards}")
    Mix.shell().info("  cached cards: #{report.cached_cards}")
  end

  defp parse_refresh!(args) do
    case OptionParser.parse(args, strict: [refresh: :boolean]) do
      {opts, [], []} ->
        Keyword.get(opts, :refresh, false)

      {_opts, unexpected_args, invalid_opts} ->
        details =
          [
            format_unexpected_args(unexpected_args),
            format_invalid_opts(invalid_opts)
          ]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join(", ")

        Mix.raise("invalid arguments for prizmo.cards.sync: #{details}")
    end
  end

  defp format_unexpected_args([]), do: ""
  defp format_unexpected_args(args), do: "unexpected args #{Enum.join(args, ", ")}"

  defp format_invalid_opts([]), do: ""

  defp format_invalid_opts(opts) do
    formatted = Enum.map_join(opts, ", ", fn {opt, value} -> "#{opt}=#{value}" end)
    "invalid options #{formatted}"
  end
end

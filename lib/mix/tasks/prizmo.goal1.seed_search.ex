defmodule Mix.Tasks.Prizmo.Goal1.SeedSearch do
  @shortdoc "Finds Goal 1 fixture seeds for target opening hands"

  @moduledoc """
  Searches deterministic supported-fixture seeds whose opening hands satisfy
  target-card constraints for one or both Goal 1 players.

      mix prizmo.goal1.seed_search \
        --deck1 28258 \
        --deck2 28337 \
        --all1 TWM-163,ASC-181 \
        --any2 PFL-094,TWM-141 \
        --prefix goal1-28258-vs-28337-seed
  """

  use Mix.Task

  alias Prizmo.Tcg.Goal1.SeedFinder

  @switches [
    deck1: :string,
    deck2: :string,
    all1: :string,
    all2: :string,
    any1: :string,
    any2: :string,
    prefix: :string,
    start: :integer,
    attempts: :integer,
    limit: :integer,
    player1: :string,
    player2: :string,
    allow_mulligan1: :boolean,
    allow_mulligan2: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    with {:ok, options} <- parse_options(args),
         {:ok, results} <-
           SeedFinder.find_supported_opening_seeds(
             options.player_requirements,
             options.search_opts
           ) do
      options
      |> format_report(results)
      |> Mix.shell().info()
    else
      {:error, reason} -> Mix.raise(format_error(reason))
    end
  end

  defp parse_options(args) do
    case OptionParser.parse(args, strict: @switches) do
      {parsed, [], []} ->
        with {:ok, deck1} <- fetch_required_option(parsed, :deck1),
             {:ok, deck2} <- fetch_required_option(parsed, :deck2) do
          {:ok,
           %{
             player_requirements: [
               %{
                 player_id: Keyword.get(parsed, :player1, "player_1"),
                 deck_key: deck1,
                 all_of: parse_card_ids(Keyword.get(parsed, :all1)),
                 any_of: parse_card_ids(Keyword.get(parsed, :any1)),
                 require_basic?: !Keyword.get(parsed, :allow_mulligan1, false)
               },
               %{
                 player_id: Keyword.get(parsed, :player2, "player_2"),
                 deck_key: deck2,
                 all_of: parse_card_ids(Keyword.get(parsed, :all2)),
                 any_of: parse_card_ids(Keyword.get(parsed, :any2)),
                 require_basic?: !Keyword.get(parsed, :allow_mulligan2, false)
               }
             ],
             search_opts: [
               prefix: Keyword.get(parsed, :prefix, "goal1-#{deck1}-vs-#{deck2}-seed"),
               start: Keyword.get(parsed, :start, 1),
               attempts: Keyword.get(parsed, :attempts, 1000),
               limit: Keyword.get(parsed, :limit, 5)
             ]
           }}
        end

      {_parsed, args, []} ->
        {:error, {:unexpected_arguments, args}}

      {_parsed, _args, invalid} ->
        {:error, {:invalid_options, invalid}}
    end
  end

  defp fetch_required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, {:missing_or_invalid_option, key, value}}
    end
  end

  defp parse_card_ids(nil), do: []

  defp parse_card_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_report(options, results) do
    [
      "Goal 1 opening seed search",
      "",
      format_player_requirement(Enum.at(options.player_requirements, 0)),
      format_player_requirement(Enum.at(options.player_requirements, 1)),
      "  prefix: #{Keyword.fetch!(options.search_opts, :prefix)}",
      "  start: #{Keyword.fetch!(options.search_opts, :start)}",
      "  attempts: #{Keyword.fetch!(options.search_opts, :attempts)}",
      "  limit: #{Keyword.fetch!(options.search_opts, :limit)}",
      "",
      format_results(results)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format_player_requirement(requirement) do
    [
      "#{requirement.player_id}: #{requirement.deck_key}",
      "  require basic opening hand: #{yes_no(requirement.require_basic?)}",
      "  all-of targets: #{join_or_none(requirement.all_of)}",
      "  any-of targets: #{join_or_none(requirement.any_of)}"
    ]
  end

  defp format_results([]), do: ["No matching seeds found."]

  defp format_results(results) do
    [
      "Found #{length(results)} matching seed(s):",
      "",
      Enum.flat_map(results, &format_result/1)
    ]
  end

  defp format_result(result) do
    List.flatten([
      "seed #{result.seed} (index #{result.seed_index})",
      Enum.map(result.players, &format_player_result/1),
      ""
    ])
  end

  defp format_player_result(player) do
    [
      "  #{player.player_id}: #{player.deck_key} #{player.deck_name}",
      "    basics in opening hand: #{player.basic_count}",
      "    matched all-of: #{join_or_none(player.all_of_matches)} / needed #{join_or_none(player.all_of)}",
      "    matched any-of: #{join_or_none(player.any_of_matches)} / options #{join_or_none(player.any_of)}",
      "    opening hand: #{format_hand(player.opening_hand)}"
    ]
  end

  defp format_hand(cards) do
    Enum.map_join(cards, ", ", fn card ->
      marker = if card.basic?, do: " [Basic]", else: ""
      "#{card.card_id} #{card.name}#{marker}"
    end)
  end

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp join_or_none([]), do: "none"
  defp join_or_none(values), do: Enum.join(values, ", ")

  defp format_error({:missing_or_invalid_option, key, _value}) do
    "missing required option --#{key}"
  end

  defp format_error({:unexpected_arguments, args}) do
    "unexpected positional arguments: #{Enum.join(args, ", ")}"
  end

  defp format_error({:invalid_options, invalid}) do
    options = Enum.map_join(invalid, ", ", fn {key, value} -> "--#{key}=#{value}" end)
    "invalid options: #{options}"
  end

  defp format_error(reason), do: inspect(reason)
end

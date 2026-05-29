defmodule Mix.Tasks.Check.Filenames do
  @shortdoc "Checks project source filenames are snake_case"
  @moduledoc """
  Checks repository-authored Elixir, HEEx, and TypeScript source filenames.
  """

  use Mix.Task

  @source_patterns [
    "*.{ex,exs}",
    "config/**/*.{ex,exs}",
    "lib/**/*.{ex,exs,heex}",
    "priv/**/*.{ex,exs}",
    "lib/prizmo_web/spa/**/*.{ts,tsx}"
  ]

  @allowed ~r/^[a-z0-9]+(?:_[a-z0-9]+)*$/

  @impl Mix.Task
  def run(_args) do
    invalid_files =
      @source_patterns
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.reject(&File.dir?/1)
      |> Enum.reject(&snake_case_filename?/1)
      |> Enum.sort()

    case invalid_files do
      [] ->
        :ok

      files ->
        Mix.raise(
          Enum.join(
            ["Non-snake_case source filenames found:" | Enum.map(files, &"  - #{&1}")],
            "\n"
          )
        )
    end
  end

  defp snake_case_filename?(path) do
    if String.starts_with?(path, "lib/mix/tasks/") do
      path
      |> Path.basename()
      |> String.replace(".", "_")
      |> basename_without_known_extension()
      |> Kernel.=~(@allowed)
    else
      path
      |> Path.basename()
      |> basename_without_known_extension()
      |> Kernel.=~(@allowed)
    end
  end

  defp basename_without_known_extension(filename) do
    cond do
      String.ends_with?(filename, ".html.heex") ->
        String.replace_suffix(filename, ".html.heex", "")

      String.ends_with?(filename, ".d.ts") ->
        String.replace_suffix(filename, ".d.ts", "")

      true ->
        Path.rootname(filename)
    end
  end
end

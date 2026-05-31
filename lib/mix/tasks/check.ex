defmodule Mix.Tasks.Check do
  @shortdoc "Runs all code quality checks with minimal output"
  @moduledoc """
  Runs all code quality checks for the project with minimal, clean output.

  ## Usage

      mix check
      mix check --no-test
      mix check --verbose
  """

  use Mix.Task

  @cmd_checks [
    {"Format", ["format"]},
    {"Sobelow", ["sobelow", "--config", "--compact", "--private"]}
  ]

  @static_checks [
    {"Compiling", ["compile", "--warnings-as-errors"]},
    {"Unused Deps", ["deps.unlock", "--check-unused"]},
    {"Xref", ["xref", "graph", "--label", "compile-connected", "--fail-above", "50"]},
    {"Filenames", ["check.filenames"]},
    {"Service Images", ["check.service_images"]},
    {"Ash TS Gen", ["ash_typescript.codegen"]},
    {"Ash TS Check", ["ash_typescript.codegen", "--check"]},
    {"Credo", ["credo", "--strict"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  @impl Mix.Task
  def run(args) do
    verbose = "--verbose" in args
    skip_tests = "--no-test" in args

    results =
      Enum.map(@cmd_checks, fn {name, task_args} -> run_cmd_check(name, task_args, verbose) end) ++
        Enum.map(@static_checks, fn {name, task_args} -> run_check(name, task_args, verbose) end) ++
        if(skip_tests, do: [], else: [run_cmd_check("Tests", ["test"], verbose)])

    failed = Enum.filter(results, fn {_, status, _} -> status == :error end)

    IO.puts("")

    if failed == [] do
      IO.puts(IO.ANSI.green() <> "All checks passed." <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "#{length(failed)} check(s) failed." <> IO.ANSI.reset())
      System.halt(1)
    end
  end

  defp run_cmd_check(name, [task | args], verbose) do
    padded_name = String.pad_trailing(name, 14)
    IO.write("#{padded_name} ")

    mix = System.find_executable("mix") || "mix"
    {output, exit_code} = System.cmd(mix, [task | args], stderr_to_stdout: true)

    handle_result(name, exit_code == 0, output, verbose)
  end

  defp run_check(name, [task | args], verbose) do
    padded_name = String.pad_trailing(name, 14)
    IO.write("#{padded_name} ")

    {result, output} = capture_task(task, args, verbose)
    handle_result(name, result == :ok, output, verbose)
  end

  defp handle_result(name, true, output, verbose) do
    IO.puts(IO.ANSI.green() <> "OK" <> IO.ANSI.reset())
    if verbose and output != "", do: IO.puts(output)
    {name, :ok, output}
  end

  defp handle_result(name, false, output, verbose) do
    IO.puts(IO.ANSI.red() <> "FAIL" <> IO.ANSI.reset())

    if !verbose do
      IO.puts("")
      IO.puts(output)
      IO.puts("")
    end

    {name, :error, output}
  end

  defp capture_task(task, args, true) do
    IO.puts("")
    run_task_directly(task, args)
  end

  defp capture_task(task, args, false) do
    original_gl = Process.group_leader()
    {:ok, capture_pid} = StringIO.open("")
    Process.group_leader(self(), capture_pid)

    result = run_task_directly(task, args)

    Process.group_leader(self(), original_gl)
    {_input, output} = StringIO.contents(capture_pid)
    StringIO.close(capture_pid)

    case result do
      {:ok, _} -> {:ok, output}
      {:error, message} -> {:error, output <> "\n" <> message}
    end
  end

  defp run_task_directly(task, args) do
    Mix.Task.rerun(task, args)
    {:ok, ""}
  rescue
    e in Mix.Error -> {:error, Exception.message(e)}
  catch
    :exit, _ -> {:error, "Task failed"}
  end
end

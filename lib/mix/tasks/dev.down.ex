defmodule Mix.Tasks.Dev.Down do
  @shortdoc "Stops worktree dev services and unregisters Caddy route"

  @moduledoc """
  Stops worktree development services.

  1. Loads configuration from .env.local (or uses defaults)
  2. Stops Phoenix server
  3. Unregisters Caddy route
  4. Stops and removes Podman Compose services (including volumes)
  """

  use Mix.Task

  alias Mix.Tasks.Dev.Shared

  @defaults %{
    "PORT" => "4003",
    "DB_PORT" => "5435",
    "S3_PORT" => "4570",
    "BRANCH" => "main"
  }

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    env = load_env()

    branch = Map.fetch!(env, "BRANCH")
    port = Map.fetch!(env, "PORT")
    db_port = Map.fetch!(env, "DB_PORT")
    s3_port = Map.fetch!(env, "S3_PORT")

    Mix.shell().info("Stopping services for branch '#{branch}'...")

    stop_phoenix_server()
    unregister_caddy_route(branch)
    stop_services(branch, port, db_port, s3_port)

    Mix.shell().info("Services stopped for branch '#{branch}'")
  end

  defp stop_phoenix_server do
    pid_file = "tmp/phoenix.pid"

    case File.read(pid_file) do
      {:ok, pid_str} ->
        pid = String.trim(pid_str)

        if String.starts_with?(pid, "tmux:") do
          session = String.replace_prefix(pid, "tmux:", "")
          Mix.shell().info("Stopping Phoenix tmux session: #{session}...")

          if System.find_executable("tmux") do
            System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true)
            File.rm(pid_file)
            Mix.shell().info("Phoenix tmux session stopped")
          else
            Mix.shell().info(
              "tmux not found on PATH. Please stop the session manually: tmux kill-session -t #{session}"
            )
          end
        else
          Mix.shell().info("Stopping Phoenix server (PID: #{pid})...")

          case Integer.parse(pid) do
            {int_pid, ""} ->
              System.cmd("pkill", ["-P", Integer.to_string(int_pid)], stderr_to_stdout: true)
              System.cmd("kill", [Integer.to_string(int_pid)], stderr_to_stdout: true)
              File.rm(pid_file)
              Mix.shell().info("Phoenix server stopped")

            _ ->
              Mix.shell().info(
                "Unrecognized PID format in #{pid_file}: #{pid}. Please stop the server manually and remove the PID file."
              )
          end
        end

      {:error, :enoent} ->
        Mix.shell().info("No Phoenix PID file found (server may not be running)")
    end
  end

  defp unregister_caddy_route(branch) do
    branch = sanitize_branch(branch)
    Mix.shell().info("Unregistering Caddy route...")

    if System.user_home!() =~ "kosciak" do
      case Req.delete("http://localhost:11190/api/routes/#{local_caddy_route_id(branch)}") do
        {:ok, %{status: status}} when status in 200..299 ->
          Mix.shell().info("Caddy route unregistered")

        {:ok, _} ->
          Mix.shell().info("Warning: Caddy route not found")

        {:error, _} ->
          Mix.shell().info("Warning: development-caddy not running")
      end
    else
      admin_base_url = System.get_env("CADDY_ADMIN_URL") || "http://localhost:2019"

      case Req.delete("#{admin_base_url}/id/wt:prizmo:#{branch}") do
        {:ok, %{status: status}} when status in 200..299 ->
          Mix.shell().info("Caddy route unregistered")

        {:ok, _} ->
          Mix.shell().info("Warning: Caddy route not found")

        {:error, _} ->
          Mix.shell().info("Warning: Caddy not running")
      end
    end
  end

  defp stop_services(branch, port, db_port, s3_port) do
    compose_env = [
      {"COMPOSE_PROJECT_NAME", "prizmo-#{branch}"},
      {"PORT", port},
      {"DB_PORT", db_port},
      {"S3_PORT", s3_port}
    ]

    case Shared.podman(["compose", "-f", "local/compose.yml", "down", "-v"], compose_env) do
      {output, 0} ->
        Mix.shell().info(output)
        Mix.shell().info("Podman Compose services stopped and volumes removed")

      {output, code} ->
        Mix.shell().error("Podman Compose failed (exit #{code}):")
        Mix.shell().error(output)
    end
  end

  defp load_env do
    case File.read(".env.local") do
      {:ok, content} ->
        Mix.shell().info("Loading configuration from .env.local")
        Shared.parse_env(content)

      {:error, :enoent} ->
        Mix.shell().info("No .env.local found, using defaults (main branch setup)")
        @defaults
    end
  end

  defp sanitize_branch(branch), do: Shared.sanitize_branch(branch)

  defp local_caddy_route_id(branch), do: "prizmo-#{branch}"
end

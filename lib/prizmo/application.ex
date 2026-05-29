defmodule Prizmo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PrizmoWeb.Telemetry,
      Prizmo.Repo,
      {DNSCluster, query: Application.get_env(:prizmo, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:prizmo, :ash_domains),
         Application.fetch_env!(:prizmo, Oban)
       )},
      {Phoenix.PubSub, name: Prizmo.PubSub},
      # Start a worker by calling: Prizmo.Worker.start_link(arg)
      # {Prizmo.Worker, arg},
      # Start to serve requests, typically the last entry
      PrizmoWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :prizmo]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Prizmo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PrizmoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

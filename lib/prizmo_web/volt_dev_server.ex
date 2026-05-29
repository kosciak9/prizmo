defmodule PrizmoWeb.VoltDevServer do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    Volt.DevServer.call(conn, config(opts))
  end

  defp config(opts) do
    key = {__MODULE__, :config, :erlang.phash2(opts)}

    case :persistent_term.get(key, :missing) do
      :missing -> init_once(key, opts)
      config -> config
    end
  end

  defp init_once(key, opts) do
    :global.trans({__MODULE__, key}, fn ->
      case :persistent_term.get(key, :missing) do
        :missing ->
          config = Volt.DevServer.init(opts)
          :persistent_term.put(key, config)
          config

        config ->
          config
      end
    end)
  end
end

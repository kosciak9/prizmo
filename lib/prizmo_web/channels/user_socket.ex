defmodule PrizmoWeb.UserSocket do
  use Phoenix.Socket

  channel "tcg:*", PrizmoWeb.TcgChannel
  channel "tcg_game:*", PrizmoWeb.TcgChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

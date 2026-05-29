defmodule PrizmoWeb.TcgChannel do
  @moduledoc false
  use PrizmoWeb, :channel

  alias Prizmo.Tcg.Sim.GameStore
  alias Prizmo.Tcg.Sim.StateView

  @impl true
  def join("tcg:lobby", _payload, socket), do: {:ok, %{"decks" => GameStore.list_decks()}, socket}

  def join("tcg_game:" <> game_id, _payload, socket) do
    case GameStore.fetch_game(game_id) do
      {:ok, game} ->
        {:ok, %{"gameId" => game_id, "state" => StateView.render(game)},
         assign(socket, :game_id, game_id)}

      :error ->
        {:error, %{"reason" => "game_not_found"}}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{"reason" => "unsupported_topic"}}

  @impl true
  def handle_in("list_decks", _payload, socket) do
    {:reply, {:ok, %{"decks" => GameStore.list_decks()}}, socket}
  end

  def handle_in("create_game", payload, socket) do
    player1_deck_id = Map.get(payload, "player1DeckId") || Map.get(payload, "player1_deck_id")
    player2_deck_id = Map.get(payload, "player2DeckId") || Map.get(payload, "player2_deck_id")

    case GameStore.create_game(player1_deck_id, player2_deck_id) do
      {:ok, game_id, game} ->
        {:reply, {:ok, %{"gameId" => game_id, "state" => StateView.render(game)}}, socket}

      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in("get_state", _payload, %{assigns: %{game_id: game_id}} = socket) do
    case GameStore.fetch_game(game_id) do
      {:ok, game} ->
        {:reply, {:ok, %{"gameId" => game_id, "state" => StateView.render(game)}}, socket}

      :error ->
        {:reply, {:error, %{"reason" => "game_not_found"}}, socket}
    end
  end

  def handle_in("submit_action", payload, %{assigns: %{game_id: game_id}} = socket) do
    case GameStore.apply_action(game_id, payload) do
      {:ok, game} ->
        response = %{"gameId" => game_id, "state" => StateView.render(game)}
        broadcast!(socket, "state_updated", response)
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{"reason" => "unsupported_event"}}, socket}
  end

  defp error_payload(reason) do
    %{"reason" => inspect(reason)}
  end
end

defmodule Prizmo.Tcg.Sim.GameStore do
  @moduledoc """
  Process-local game store for the rough playable TCG UI.

  This is intentionally volatile. Games are kept in memory for fast iteration
  and disappear when the application restarts.
  """

  use GenServer

  alias Prizmo.Tcg.Data.TCGdex
  alias Prizmo.Tcg.Sim.Action
  alias Prizmo.Tcg.Sim.Engine

  @type game_id :: String.t()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(state), do: {:ok, state}

  def list_decks do
    Enum.map(TCGdex.known_deck_modules(), fn module ->
      %{
        "id" => module.id(),
        "name" => module.name(),
        "sourceUrl" => module.source_url(),
        "cardCount" => length(module.card_ids()),
        "counts" =>
          Enum.map(module.counts(), fn {card_id, count} ->
            %{"cardId" => card_id, "count" => count}
          end)
      }
    end)
  end

  def create_game(player1_deck_id, player2_deck_id) do
    GenServer.call(__MODULE__, {:create_game, player1_deck_id, player2_deck_id})
  end

  def fetch_game(game_id) do
    GenServer.call(__MODULE__, {:fetch_game, game_id})
  end

  def apply_action(game_id, action_params) do
    GenServer.call(__MODULE__, {:apply_action, game_id, action_params})
  end

  @impl true
  def handle_call({:create_game, player1_deck_id, player2_deck_id}, _from, games) do
    with {:ok, player1_deck} <- fetch_deck(player1_deck_id),
         {:ok, player2_deck} <- fetch_deck(player2_deck_id) do
      game_id = generate_game_id()

      game =
        Engine.new_game(
          players: [{"player1", player1_deck.card_ids()}, {"player2", player2_deck.card_ids()}],
          active_player: "player1"
        )

      {:reply, {:ok, game_id, game}, Map.put(games, game_id, game)}
    else
      {:error, reason} -> {:reply, {:error, reason}, games}
    end
  end

  def handle_call({:fetch_game, game_id}, _from, games) do
    {:reply, Map.fetch(games, game_id), games}
  end

  def handle_call({:apply_action, game_id, action_params}, _from, games) do
    with {:ok, game} <- Map.fetch(games, game_id),
         {:ok, action} <- build_action(action_params),
         {:ok, next_game} <- Engine.apply_action(game, action) do
      {:reply, {:ok, next_game}, Map.put(games, game_id, next_game)}
    else
      :error -> {:reply, {:error, :game_not_found}, games}
      {:error, reason} -> {:reply, {:error, reason}, games}
    end
  end

  defp fetch_deck(deck_id) do
    TCGdex.known_deck_modules()
    |> Enum.find(&(&1.id() == deck_id))
    |> case do
      nil -> {:error, {:unknown_deck, deck_id}}
      module -> {:ok, module}
    end
  end

  defp build_action(%{"type" => type} = params) when is_binary(type) do
    with {:ok, type} <- existing_atom(type),
         {:ok, action_params} <- atomize_params(Map.get(params, "params", %{})) do
      {:ok,
       %Action{
         type: type,
         player_id: Map.get(params, "playerId") || Map.get(params, "player_id"),
         params: action_params
       }}
    end
  end

  defp build_action(_params), do: {:error, :missing_action_type}

  defp atomize_params(params) when is_map(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- param_key(key),
           {:ok, value} <- atomize_value(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp atomize_params(_params), do: {:error, :action_params_must_be_object}

  defp atomize_value(value) when is_map(value), do: atomize_params(value)

  defp atomize_value(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case atomize_value(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp atomize_value(value) when is_binary(value) do
    case existing_atom(value) do
      {:ok, atom} -> {:ok, atom}
      {:error, _reason} -> {:ok, value}
    end
  end

  defp atomize_value(value), do: {:ok, value}

  defp param_key(key) when is_atom(key), do: {:ok, key}

  defp param_key(key) when is_binary(key) do
    existing_atom(Macro.underscore(key))
  end

  defp existing_atom(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, {:unknown_atom, value}}
  end

  defp generate_game_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end

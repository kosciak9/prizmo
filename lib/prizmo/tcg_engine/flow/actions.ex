defmodule Prizmo.TcgEngine.Flow.Actions do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [require_no_prizes_placed: 1]
  import Prizmo.TcgEngine.EventLog, only: [write_event: 4, write_snapshot: 3]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.Flow.Context
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameSetup
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.SetupStore

  @coin_faces [:heads, :tails]

  def opening_hands_not_dealt?(%Context{game: %Game{} = game}, _attrs) do
    GameSetup.require_no_setup_cards_moved(game.id) == :ok
  end

  def record_coin_toss(%Context{} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    call = normalize_coin_face(Map.fetch!(attrs, :call))

    with {:ok, call} <- call,
         :ok <- require_player(context, player_id),
         :ok <- require_no_coin_toss(context.game),
         result = random_coin_face(),
         winner_player_id = coin_toss_winner(context, player_id, call, result),
         {:ok, game} <-
           update(context.game, :record_coin_toss, %{
             flow_state: :pregame_awaiting_starting_player_choice,
             coin_toss_calling_player_id: player_id,
             coin_toss_call: call,
             coin_toss_result: result,
             coin_toss_winner_player_id: winner_player_id
           }),
         {:ok, event} <-
           write_event(game, :coin_toss_resolved, player_id, %{
             call: Atom.to_string(call),
             result: Atom.to_string(result),
             winner_player_id: winner_player_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def choose_starting_player(%Context{} = context, attrs) do
    chooser_player_id = Map.fetch!(attrs, :chooser_player_id)
    starting_player_id = Map.fetch!(attrs, :starting_player_id)

    with :ok <- require_player(context, chooser_player_id),
         :ok <- require_player(context, starting_player_id),
         :ok <- require_coin_toss_winner(context.game, chooser_player_id),
         {:ok, game} <-
           update(context.game, :choose_starting_player, %{
             flow_state: :setup_dealing_opening_hands,
             active_player_id: starting_player_id,
             first_player_id: starting_player_id,
             starting_player_chosen_by_player_id: chooser_player_id
           }),
         {:ok, _setup} <- create(Setup, :create, %{game_id: game.id}),
         {:ok, event} <-
           write_event(game, :starting_player_chosen, chooser_player_id, %{
             starting_player_id: starting_player_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def deal_opening_hands(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, setup} <- SetupStore.get_setup(game.id),
         {:ok, setup} <- update(setup, :draw_opening_hand, %{}),
         :ok <- GameSetup.require_no_setup_cards_moved(game.id),
         {:ok, _cards} <- GameSetup.draw_opening_cards(game.id),
         :ok <- require_no_prizes_placed(game.id),
         {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_active}),
         {:ok, event} <- write_event(game, :opening_hands_drawn, nil, %{setup_id: setup.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  defp normalize_coin_face(face) when face in @coin_faces, do: {:ok, face}
  defp normalize_coin_face("heads"), do: {:ok, :heads}
  defp normalize_coin_face("tails"), do: {:ok, :tails}
  defp normalize_coin_face(face), do: {:error, {:invalid_coin_call, face}}

  defp random_coin_face do
    Enum.random(@coin_faces)
  end

  defp coin_toss_winner(%Context{} = context, calling_player_id, call, result) do
    if call == result do
      calling_player_id
    else
      context.players
      |> Enum.reject(&(&1.player_id == calling_player_id))
      |> List.first()
      |> Map.fetch!(:player_id)
    end
  end

  defp require_player(%Context{} = context, player_id) do
    if Context.player?(context, player_id), do: :ok, else: {:error, :player_not_found}
  end

  defp require_no_coin_toss(%Game{coin_toss_result: nil}), do: :ok
  defp require_no_coin_toss(%Game{}), do: {:error, :coin_toss_already_resolved}

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: player_id}, player_id), do: :ok

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: nil}, _player_id),
    do: {:error, :coin_toss_not_resolved}

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: winner_player_id}, _player_id),
    do: {:error, {:not_coin_toss_winner, winner_player_id}}
end

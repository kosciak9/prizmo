defmodule Prizmo.TcgEngine.ZoneActions do
  @moduledoc false

  import Prizmo.TcgEngine.Requirements,
    only: [require_card_owned_by_player: 2, require_card_zone: 2]

  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventLog
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.Operation
  alias Prizmo.TcgEngine.TurnFlow

  def move_owned_card_to_hand_from_zone(game_or_id, player_id, card_instance_id, zone, event_type) do
    Operation.transaction(fn ->
      with {:ok, game} <- GameStore.get_game(game_or_id),
           {:ok, turn} <- TurnFlow.require_action_window_for_player(game, player_id),
           {:ok, card} <- CardStore.get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, zone),
           {:ok, position} <- CardStore.next_hand_position_result(game.id, player_id),
           {:ok, _card} <- CardStore.move_card_to_hand(card, zone, position),
           {:ok, event} <-
             EventLog.write_event(game, event_type, player_id, %{
               turn_id: turn.id,
               card_instance_id: card.id,
               from_zone: Atom.to_string(zone),
               position: position
             }),
           {:ok, _snapshot} <- EventLog.write_snapshot(game.id, event.id, event.index) do
        GameStore.get_game(game.id)
      end
    end)
  end

  def discard_owned_card_from_zone(game_or_id, player_id, card_instance_id, zone, event_type) do
    Operation.transaction(fn ->
      with {:ok, game} <- GameStore.get_game(game_or_id),
           {:ok, turn} <- TurnFlow.require_action_window_for_player(game, player_id),
           {:ok, card} <- CardStore.get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, zone),
           {:ok, position} <- CardStore.next_discard_position(game.id, player_id),
           {:ok, _card} <- Operation.update(card, :discard, %{position: position}),
           {:ok, event} <-
             EventLog.write_event(game, event_type, player_id, %{
               turn_id: turn.id,
               card_instance_id: card.id,
               from_zone: Atom.to_string(zone),
               position: position
             }),
           {:ok, _snapshot} <- EventLog.write_snapshot(game.id, event.id, event.index) do
        GameStore.get_game(game.id)
      end
    end)
  end
end

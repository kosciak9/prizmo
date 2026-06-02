defmodule Prizmo.TcgEngine.ItemLocks do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  @effect_type "lock_opponent_items_next_turn"
  @source_card_id "ASC-016"
  @source_attack_id "itchy_pollen"

  @spec lock_opponent_items_next_turn_payload(CardInstance.t(), String.t(), Turn.t()) :: map()
  def lock_opponent_items_next_turn_payload(
        %CardInstance{} = attacker_card,
        blocked_player_id,
        %Turn{
          turn_number: turn_number,
          active_player_id: source_player_id
        }
      )
      when is_binary(blocked_player_id) and is_integer(turn_number) do
    %{
      effect_type: @effect_type,
      item_lock_source_card_id: attacker_card.card_id,
      item_lock_source_card_instance_id: attacker_card.id,
      item_lock_source_attack_id: @source_attack_id,
      item_lock_source_player_id: source_player_id,
      item_lock_source_turn_number: turn_number,
      item_lock_blocked_player_id: blocked_player_id,
      item_lock_blocked_turn_number: turn_number + 1
    }
  end

  @spec require_item_unlocked_if_item(map(), String.t(), String.t(), Turn.t()) ::
          :ok | {:error, term()}
  def require_item_unlocked_if_item(%{trainer_type: :item}, game_id, player_id, %Turn{} = turn) do
    require_item_unlocked(game_id, player_id, turn)
  end

  def require_item_unlocked_if_item(_metadata, _game_id, _player_id, %Turn{}), do: :ok

  @spec require_item_unlocked(String.t(), String.t(), Turn.t()) :: :ok | {:error, term()}
  def require_item_unlocked(game_id, player_id, %Turn{} = turn)
      when is_binary(game_id) and is_binary(player_id) do
    case item_locked_this_turn?(game_id, player_id, turn) do
      {:ok, false} -> :ok
      {:ok, true} -> {:error, :items_locked_by_itchy_pollen}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec item_locked_this_turn?(String.t(), String.t(), Turn.t()) ::
          {:ok, boolean()} | {:error, term()}
  def item_locked_this_turn?(game_id, player_id, %Turn{turn_number: turn_number})
      when is_binary(game_id) and is_binary(player_id) and is_integer(turn_number) do
    events =
      GameEvent
      |> Ash.Query.filter(game_id == ^game_id and type == "resolve_declared_attack")
      |> Ash.Query.sort(index: :asc)
      |> Ash.read()

    case events do
      {:ok, events} ->
        {:ok, Enum.any?(events, &matching_lock?(&1, player_id, turn_number))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp matching_lock?(%GameEvent{payload: payload}, player_id, turn_number)
       when is_map(payload) do
    payload_value(payload, "effect_type", :effect_type) == @effect_type and
      payload_value(payload, "item_lock_source_card_id", :item_lock_source_card_id) ==
        @source_card_id and
      payload_value(payload, "item_lock_source_attack_id", :item_lock_source_attack_id) ==
        @source_attack_id and
      payload_value(payload, "item_lock_blocked_player_id", :item_lock_blocked_player_id) ==
        player_id and
      payload_value(payload, "item_lock_blocked_turn_number", :item_lock_blocked_turn_number) ==
        turn_number
  end

  defp matching_lock?(%GameEvent{}, _player_id, _turn_number), do: false

  defp payload_value(payload, string_key, atom_key) do
    Map.get(payload, string_key) || Map.get(payload, atom_key)
  end
end

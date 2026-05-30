defmodule Prizmo.TcgEngine.AttackPrevention do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Turn

  @damage_and_effects_next_turn_key "prevent_damage_and_effects_from_attacks_next_turn"
  @source_card_id "TEF-128"
  @source_attack_id "dig"

  @spec put_damage_and_effects_next_turn_marker(CardInstance.t(), Turn.t()) :: map()
  def put_damage_and_effects_next_turn_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@damage_and_effects_next_turn_key, damage_and_effects_next_turn_marker(turn))
  end

  @spec damage_and_effects_next_turn_marker(Turn.t()) :: map()
  def damage_and_effects_next_turn_marker(%Turn{
        active_player_id: active_player_id,
        turn_number: turn_number
      })
      when is_integer(turn_number) do
    %{
      "source_card_id" => @source_card_id,
      "source_attack_id" => @source_attack_id,
      "source_player_id" => active_player_id,
      "source_turn_number" => turn_number,
      "blocked_turn_number" => turn_number + 1
    }
  end

  @spec damage_and_effects_prevented_this_turn?(CardInstance.t(), Turn.t(), String.t()) ::
          boolean()
  def damage_and_effects_prevented_this_turn?(
        %CardInstance{} = card,
        %Turn{turn_number: turn_number},
        attacking_player_id
      )
      when is_integer(turn_number) and is_binary(attacking_player_id) do
    opponent_attack?(card, attacking_player_id) and in_play?(card) and
      card.markers
      |> persisted_damage_and_effects_next_turn_marker()
      |> blocked_on_turn?(turn_number)
  end

  def damage_and_effects_prevented_this_turn?(%CardInstance{}, %Turn{}, _attacking_player_id),
    do: false

  @spec prevention_payload(CardInstance.t(), Turn.t()) :: map()
  def prevention_payload(%CardInstance{} = card, %Turn{turn_number: turn_number}) do
    marker = persisted_damage_and_effects_next_turn_marker(card.markers) || %{}

    %{
      attack_prevention_source_card_id:
        marker_value(marker, "source_card_id", :source_card_id) || @source_card_id,
      attack_prevention_source_attack_id:
        marker_value(marker, "source_attack_id", :source_attack_id) || @source_attack_id,
      attack_prevention_source_player_id:
        marker_value(marker, "source_player_id", :source_player_id),
      attack_prevention_source_turn_number:
        marker_value(marker, "source_turn_number", :source_turn_number),
      attack_prevention_blocked_turn_number:
        marker_value(marker, "blocked_turn_number", :blocked_turn_number) || turn_number,
      protected_card_instance_id: card.id
    }
  end

  defp opponent_attack?(%CardInstance{owner_player_id: owner_player_id}, attacking_player_id),
    do: owner_player_id != attacking_player_id

  defp in_play?(%CardInstance{zone: zone}), do: zone in [:active, :bench]

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}

  defp persisted_damage_and_effects_next_turn_marker(markers) when is_map(markers) do
    Map.get(markers, @damage_and_effects_next_turn_key) ||
      Map.get(markers, :prevent_damage_and_effects_from_attacks_next_turn)
  end

  defp persisted_damage_and_effects_next_turn_marker(_markers), do: nil

  defp blocked_on_turn?(marker, turn_number) when is_map(marker) do
    marker_value(marker, "blocked_turn_number", :blocked_turn_number) == turn_number
  end

  defp blocked_on_turn?(_marker, _turn_number), do: false

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end
end

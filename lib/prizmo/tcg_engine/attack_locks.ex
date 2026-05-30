defmodule Prizmo.TcgEngine.AttackLocks do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Turn

  @cannot_attack_next_turn_key "cannot_attack_next_turn"

  @spec put_cannot_attack_next_turn_marker(CardInstance.t(), Turn.t()) :: map()
  def put_cannot_attack_next_turn_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@cannot_attack_next_turn_key, cannot_attack_next_turn_marker(turn))
  end

  @spec cannot_attack_next_turn_marker(Turn.t()) :: map()
  def cannot_attack_next_turn_marker(%Turn{
        active_player_id: active_player_id,
        turn_number: turn_number
      })
      when is_integer(turn_number) do
    %{
      "source_player_id" => active_player_id,
      "source_turn_number" => turn_number,
      "blocked_turn_number" => turn_number + 2
    }
  end

  @spec blocked_this_turn?(CardInstance.t(), Turn.t()) :: boolean()
  def blocked_this_turn?(%CardInstance{markers: markers}, %Turn{turn_number: turn_number})
      when is_integer(turn_number) do
    markers
    |> persisted_cannot_attack_next_turn_marker()
    |> blocked_on_turn?(turn_number)
  end

  def blocked_this_turn?(%CardInstance{}, %Turn{}), do: false

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}

  defp persisted_cannot_attack_next_turn_marker(markers) when is_map(markers) do
    Map.get(markers, @cannot_attack_next_turn_key) || Map.get(markers, :cannot_attack_next_turn)
  end

  defp persisted_cannot_attack_next_turn_marker(_markers), do: nil

  defp blocked_on_turn?(marker, turn_number) when is_map(marker) do
    marker_value(marker, "blocked_turn_number", :blocked_turn_number) == turn_number
  end

  defp blocked_on_turn?(_marker, _turn_number), do: false

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end
end

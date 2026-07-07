defmodule Prizmo.TcgEngine.AttackLocks do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Turn

  @cannot_attack_next_turn_key "cannot_attack_next_turn"
  @cannot_use_attack_next_turn_key "cannot_use_attack_next_turn"

  @spec put_cannot_attack_next_turn_marker(CardInstance.t(), Turn.t()) :: map()
  def put_cannot_attack_next_turn_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@cannot_attack_next_turn_key, cannot_attack_next_turn_marker(turn))
  end

  @spec put_cannot_use_attack_next_turn_marker(CardInstance.t(), Turn.t(), atom() | String.t()) ::
          map()
  def put_cannot_use_attack_next_turn_marker(
        %CardInstance{markers: markers},
        %Turn{} = turn,
        attack_id
      )
      when is_atom(attack_id) or is_binary(attack_id) do
    markers
    |> normalize_markers()
    |> Map.put(
      @cannot_use_attack_next_turn_key,
      cannot_use_attack_next_turn_marker(turn, attack_id)
    )
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

  @spec cannot_use_attack_next_turn_marker(Turn.t(), atom() | String.t()) :: map()
  def cannot_use_attack_next_turn_marker(
        %Turn{active_player_id: active_player_id, turn_number: turn_number},
        attack_id
      )
      when is_integer(turn_number) and (is_atom(attack_id) or is_binary(attack_id)) do
    %{
      "source_player_id" => active_player_id,
      "source_turn_number" => turn_number,
      "blocked_turn_number" => turn_number + 1,
      "attack_id" => stringify_attack_id(attack_id)
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

  @spec blocked_this_turn?(CardInstance.t(), Turn.t(), atom() | String.t()) :: boolean()
  def blocked_this_turn?(%CardInstance{} = card, %Turn{} = turn, attack_id)
      when is_atom(attack_id) or is_binary(attack_id) do
    blocked_this_turn?(card, turn) or selected_attack_blocked_this_turn?(card, turn, attack_id)
  end

  def blocked_this_turn?(%CardInstance{} = card, %Turn{} = turn, _attack_id) do
    blocked_this_turn?(card, turn)
  end

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}

  defp persisted_cannot_attack_next_turn_marker(markers) when is_map(markers) do
    Map.get(markers, @cannot_attack_next_turn_key) || Map.get(markers, :cannot_attack_next_turn)
  end

  defp persisted_cannot_attack_next_turn_marker(_markers), do: nil

  defp persisted_cannot_use_attack_next_turn_marker(markers) when is_map(markers) do
    Map.get(markers, @cannot_use_attack_next_turn_key) ||
      Map.get(markers, :cannot_use_attack_next_turn)
  end

  defp persisted_cannot_use_attack_next_turn_marker(_markers), do: nil

  defp blocked_on_turn?(marker, turn_number) when is_map(marker) do
    marker_value(marker, "blocked_turn_number", :blocked_turn_number) == turn_number
  end

  defp blocked_on_turn?(_marker, _turn_number), do: false

  defp selected_attack_blocked_this_turn?(
         %CardInstance{markers: markers},
         %Turn{turn_number: turn_number},
         attack_id
       )
       when is_integer(turn_number) do
    markers
    |> persisted_cannot_use_attack_next_turn_marker()
    |> blocked_attack_on_turn?(turn_number, stringify_attack_id(attack_id))
  end

  defp blocked_attack_on_turn?(marker, turn_number, attack_id) when is_map(marker) do
    blocked_on_turn?(marker, turn_number) and
      marker_value(marker, "attack_id", :attack_id) == attack_id
  end

  defp blocked_attack_on_turn?(_marker, _turn_number, _attack_id), do: false

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end

  defp stringify_attack_id(attack_id) when is_atom(attack_id), do: Atom.to_string(attack_id)
  defp stringify_attack_id(attack_id) when is_binary(attack_id), do: attack_id
end

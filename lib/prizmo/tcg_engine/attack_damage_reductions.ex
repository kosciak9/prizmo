defmodule Prizmo.TcgEngine.AttackDamageReductions do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Turn

  @outgoing_damage_reduction_key "outgoing_attack_damage_reduction_next_turn"
  @outgoing_damage_reduction_atom_key :outgoing_attack_damage_reduction_next_turn
  @incoming_damage_reduction_key "incoming_attack_damage_reduction_next_turn"
  @incoming_damage_reduction_atom_key :incoming_attack_damage_reduction_next_turn

  @spec put_outgoing_reduction_next_turn_marker(
          CardInstance.t(),
          Turn.t(),
          non_neg_integer(),
          CardInstance.t(),
          atom()
        ) :: map()
  def put_outgoing_reduction_next_turn_marker(
        %CardInstance{markers: markers},
        %Turn{} = turn,
        amount,
        %CardInstance{} = source_card,
        attack_id
      )
      when is_integer(amount) and amount >= 0 and is_atom(attack_id) do
    markers
    |> normalize_markers()
    |> Map.put(@outgoing_damage_reduction_key, %{
      "source_card_id" => source_card.card_id,
      "source_card_instance_id" => source_card.id,
      "source_player_id" => turn.active_player_id,
      "source_attack_id" => Atom.to_string(attack_id),
      "source_turn_number" => turn.turn_number,
      "reduced_turn_number" => turn.turn_number + 1,
      "amount" => amount
    })
  end

  @spec put_incoming_reduction_next_turn_marker(
          CardInstance.t(),
          Turn.t(),
          non_neg_integer(),
          atom()
        ) :: map()
  def put_incoming_reduction_next_turn_marker(
        %CardInstance{
          markers: markers,
          card_id: card_id,
          owner_player_id: player_id,
          id: card_instance_id
        },
        %Turn{} = turn,
        amount,
        attack_id
      )
      when is_integer(amount) and amount >= 0 and is_atom(attack_id) do
    markers
    |> normalize_markers()
    |> Map.put(@incoming_damage_reduction_key, %{
      "source_card_id" => card_id,
      "source_card_instance_id" => card_instance_id,
      "source_player_id" => player_id,
      "source_attack_id" => Atom.to_string(attack_id),
      "source_turn_number" => turn.turn_number,
      "reduced_turn_number" => turn.turn_number + 1,
      "amount" => amount
    })
  end

  @spec outgoing_reduction_this_turn(CardInstance.t(), Turn.t()) :: non_neg_integer()
  def outgoing_reduction_this_turn(%CardInstance{markers: markers}, %Turn{
        turn_number: turn_number
      })
      when is_integer(turn_number) do
    markers
    |> persisted_outgoing_reduction_marker()
    |> reduction_on_turn(turn_number)
  end

  def outgoing_reduction_this_turn(%CardInstance{}, %Turn{}), do: 0

  @spec incoming_reduction_this_turn(CardInstance.t(), Turn.t()) :: non_neg_integer()
  def incoming_reduction_this_turn(%CardInstance{markers: markers}, %Turn{
        turn_number: turn_number
      })
      when is_integer(turn_number) do
    markers
    |> persisted_incoming_reduction_marker()
    |> reduction_on_turn(turn_number)
  end

  def incoming_reduction_this_turn(%CardInstance{}, %Turn{}), do: 0

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}

  defp persisted_outgoing_reduction_marker(markers) when is_map(markers) do
    Map.get(markers, @outgoing_damage_reduction_key) ||
      Map.get(markers, @outgoing_damage_reduction_atom_key)
  end

  defp persisted_outgoing_reduction_marker(_markers), do: nil

  defp persisted_incoming_reduction_marker(markers) when is_map(markers) do
    Map.get(markers, @incoming_damage_reduction_key) ||
      Map.get(markers, @incoming_damage_reduction_atom_key)
  end

  defp persisted_incoming_reduction_marker(_markers), do: nil

  defp reduction_on_turn(marker, turn_number) when is_map(marker) do
    if marker_value(marker, "reduced_turn_number", :reduced_turn_number) == turn_number do
      marker
      |> marker_value("amount", :amount)
      |> valid_amount()
    else
      0
    end
  end

  defp reduction_on_turn(_marker, _turn_number), do: 0

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end

  defp valid_amount(amount) when is_integer(amount) and amount > 0, do: amount
  defp valid_amount(_amount), do: 0
end

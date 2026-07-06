defmodule Prizmo.TcgEngine.AttackPrevention do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Turn

  @damage_and_effects_next_turn_key "prevent_damage_and_effects_from_attacks_next_turn"
  @source_card_id "TEF-128"
  @source_attack_id "dig"
  @mist_energy_card_id "TEF-161"
  @mist_energy_effect_id "mist_energy"
  @rocky_fighting_energy_card_id "POR-087"
  @rocky_fighting_energy_effect_id "rocky_fighting_energy"

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

  @spec attack_effect_prevention_payload(CardInstance.t(), Turn.t(), String.t()) ::
          {:prevented, map()} | :not_prevented | {:error, term()}
  def attack_effect_prevention_payload(
        %CardInstance{} = card,
        %Turn{} = turn,
        attacking_player_id
      )
      when is_binary(attacking_player_id) do
    if damage_and_effects_prevented_this_turn?(card, turn, attacking_player_id) do
      {:prevented, prevention_payload(card, turn)}
    else
      with {:ok, prevention_energy_card} <-
             attached_attack_effect_prevention_energy_card(card, attacking_player_id) do
        case prevention_energy_card do
          %CardInstance{} = prevention_energy_card ->
            {:prevented, energy_prevention_payload(card, turn, prevention_energy_card)}

          nil ->
            :not_prevented
        end
      end
    end
  end

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

  defp attached_attack_effect_prevention_energy_card(%CardInstance{} = card, attacking_player_id) do
    if opponent_attack?(card, attacking_player_id) and in_play?(card) do
      with {:ok, attached_cards} <- CardStore.attached_cards(card.game_id, card.id) do
        {:ok, Enum.find(attached_cards, &attack_effect_prevention_energy_card?(&1, card))}
      end
    else
      {:ok, nil}
    end
  end

  defp attack_effect_prevention_energy_card?(
         %CardInstance{card_id: card_id},
         %CardInstance{} = target_card
       )
       when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :energy,
         effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon} = effect
       }} ->
        prevention_energy_target_matches?(target_card, effect)

      _other ->
        false
    end
  end

  defp attack_effect_prevention_energy_card?(%CardInstance{}, %CardInstance{}), do: false

  defp prevention_energy_target_matches?(%CardInstance{}, %{required_attached_pokemon_type: nil}),
    do: true

  defp prevention_energy_target_matches?(%CardInstance{} = target_card, %{
         required_attached_pokemon_type: type
       })
       when is_atom(type) do
    pokemon_type?(target_card, type)
  end

  defp prevention_energy_target_matches?(%CardInstance{}, _effect), do: true

  defp pokemon_type?(%CardInstance{card_id: card_id}, type) when is_atom(type) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, types: types}} when is_list(types) -> type in types
      {:ok, %{supertype: :pokemon, type: ^type}} -> true
      _other -> false
    end
  end

  defp energy_prevention_payload(
         %CardInstance{} = card,
         %Turn{turn_number: turn_number},
         %CardInstance{} = energy_card
       ) do
    %{
      attack_prevention_source_card_id: energy_card.card_id,
      attack_prevention_source_card_instance_id: energy_card.id,
      attack_prevention_source_effect_id: energy_prevention_effect_id(energy_card),
      attack_prevention_source_player_id: card.owner_player_id,
      attack_prevention_blocked_turn_number: turn_number,
      protected_card_instance_id: card.id
    }
  end

  defp energy_prevention_effect_id(%CardInstance{card_id: @mist_energy_card_id}),
    do: @mist_energy_effect_id

  defp energy_prevention_effect_id(%CardInstance{card_id: @rocky_fighting_energy_card_id}),
    do: @rocky_fighting_energy_effect_id

  defp energy_prevention_effect_id(%CardInstance{card_id: card_id}), do: card_id

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

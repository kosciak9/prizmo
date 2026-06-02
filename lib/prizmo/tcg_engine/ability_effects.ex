defmodule Prizmo.TcgEngine.AbilityEffects do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Turn

  @adrena_brain_card_id "TWM-095"
  @adrena_brain_ability_id :adrena_brain
  @adrena_brain_effect_type :move_damage_counters
  @adrena_brain_marker_key "ability_used:adrena_brain"
  @adrena_brain_marker_atom_key :"ability_used:adrena_brain"
  @adrena_brain_max_counters 3
  @adrena_brain_required_type :darkness

  def adrena_brain_card_id, do: @adrena_brain_card_id
  def adrena_brain_ability_id, do: @adrena_brain_ability_id
  def adrena_brain_max_counters, do: @adrena_brain_max_counters

  def adrena_brain_source?(%CardInstance{card_id: @adrena_brain_card_id}), do: true
  def adrena_brain_source?(%CardInstance{}), do: false

  def adrena_brain_available?(%CardInstance{} = source, attached_cards, %Turn{} = turn)
      when is_list(attached_cards) do
    adrena_brain_source?(source) and in_play?(source) and
      not adrena_brain_used_this_turn?(source, turn) and
      Enum.any?(attached_cards, &darkness_energy?/1)
  end

  def require_adrena_brain_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with :ok <- require_adrena_brain_source(source),
         :ok <- require_in_play(source),
         :ok <- require_adrena_brain_unused(source, turn),
         {:ok, attached_cards} <- CardStore.attached_cards(game_id, source.id) do
      require_attached_darkness_energy(source, attached_cards)
    end
  end

  def require_adrena_brain_source(%CardInstance{card_id: @adrena_brain_card_id} = source) do
    with {:ok, %{max_counters: @adrena_brain_max_counters}} <- adrena_brain_effect(source) do
      :ok
    end
  end

  def require_adrena_brain_source(%CardInstance{} = source) do
    {:error, {:wrong_card_for_ability, @adrena_brain_card_id, source.card_id}}
  end

  def require_adrena_brain_unused(%CardInstance{} = source, %Turn{} = turn) do
    if adrena_brain_used_this_turn?(source, turn) do
      {:error, {:ability_already_used_this_turn, source.id, @adrena_brain_ability_id}}
    else
      :ok
    end
  end

  def put_adrena_brain_used_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@adrena_brain_marker_key, %{
      "ability_id" => Atom.to_string(@adrena_brain_ability_id),
      "source_card_id" => @adrena_brain_card_id,
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number
    })
  end

  def adrena_brain_used_this_turn?(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> adrena_brain_marker()
    |> marker_matches_turn?(turn)
  end

  def movable_damage_counter_count(%CardInstance{damage: damage}) when is_integer(damage) do
    damage
    |> max(0)
    |> div(10)
    |> min(@adrena_brain_max_counters)
  end

  def movable_damage_counter_count(%CardInstance{}), do: 0

  def require_damage_counter_count(counters, %CardInstance{} = from_card)
      when is_integer(counters) do
    max_counters = movable_damage_counter_count(from_card)

    cond do
      counters < 1 ->
        {:error, {:invalid_damage_counter_count, counters, 1, max_counters}}

      counters > max_counters ->
        {:error, {:not_enough_damage_counters, from_card.id, counters, max_counters}}

      true ->
        :ok
    end
  end

  def require_damage_counter_count(counters, %CardInstance{} = from_card) do
    {:error,
     {:invalid_damage_counter_count, counters, 1, movable_damage_counter_count(from_card)}}
  end

  def damage_for_counters(counters) when is_integer(counters), do: counters * 10

  def darkness_energy?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, name: "Team Rocket's Energy"}} ->
        true

      {:ok, %{supertype: :energy, provides: provides}} when is_list(provides) ->
        @adrena_brain_required_type in provides

      {:ok, _metadata} ->
        false

      {:error, _reason} ->
        false
    end
  end

  defp require_in_play(%CardInstance{} = source) do
    if in_play?(source) do
      :ok
    else
      {:error, {:ability_source_not_in_play, source.id, source.zone}}
    end
  end

  defp in_play?(%CardInstance{zone: zone}), do: zone in [:active, :bench]

  defp require_attached_darkness_energy(%CardInstance{} = source, attached_cards) do
    if Enum.any?(attached_cards, &darkness_energy?/1) do
      :ok
    else
      {:error, {:missing_attached_energy_type, source.id, @adrena_brain_required_type}}
    end
  end

  defp adrena_brain_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @adrena_brain_ability_id),
         %{
           type: @adrena_brain_effect_type,
           max_counters: max_counters,
           requires_attached_type: @adrena_brain_required_type
         } <- effect do
      {:ok, %{max_counters: max_counters}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @adrena_brain_ability_id,
          @adrena_brain_effect_type}}
    end
  end

  defp adrena_brain_marker(markers) when is_map(markers) do
    Map.get(markers, @adrena_brain_marker_key) || Map.get(markers, @adrena_brain_marker_atom_key)
  end

  defp adrena_brain_marker(_markers), do: nil

  defp marker_matches_turn?(marker, %Turn{id: turn_id, turn_number: turn_number})
       when is_map(marker) do
    marker_value(marker, "turn_id", :turn_id) == turn_id or
      marker_value(marker, "turn_number", :turn_number) == turn_number
  end

  defp marker_matches_turn?(_marker, %Turn{}), do: false

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}
end

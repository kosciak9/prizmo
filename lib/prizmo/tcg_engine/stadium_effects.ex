defmodule Prizmo.TcgEngine.StadiumEffects do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  @special_condition_immunity_effect :special_condition_immunity_for_pokemon_with_energy
  @special_conditions [:asleep, :burned, :confused, :paralyzed, :poisoned]
  @festival_grounds_effect_id "festival_grounds"
  @team_rockets_factory_effect :draw_after_playing_team_rocket_supporter
  @team_rockets_factory_card_id "DRI-173"
  @risky_ruins_effect :damage_on_bench_for_basic_non_darkness
  @risky_ruins_card_id "MEG-127"
  @risky_ruins_damage 20
  @forest_of_vitality_effect :same_turn_grass_evolution_exception
  @forest_of_vitality_card_id "MEG-117"
  @team_rockets_watchtower_effect :colorless_pokemon_have_no_abilities
  @area_zero_underdepths_effect :bench_limit_8_with_tera_in_play_else_discard_to_5

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @special_condition_immunity_effect}
      }),
      do: true

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @team_rockets_factory_effect}
      }),
      do: true

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @risky_ruins_effect}
      }), do: true

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @forest_of_vitality_effect}
      }),
      do: true

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @team_rockets_watchtower_effect}
      }),
      do: true

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @area_zero_underdepths_effect}
      }),
      do: true

  def supported_stadium?(_card), do: false

  def supported_stadium_card?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> supported_stadium?(card)
      {:error, _reason} -> false
    end
  end

  def team_rockets_factory_card?(%CardInstance{card_id: card_id}),
    do: team_rockets_factory_card?(card_id)

  def team_rockets_factory_card?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{effect: %{type: @team_rockets_factory_effect}}} -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  def active_team_rockets_factory(game_id) when is_binary(game_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      case stadiums do
        [%CardInstance{} = stadium] ->
          if team_rockets_factory_card?(stadium) do
            {:ok, stadium}
          else
            {:error, {:wrong_stadium_in_play, @team_rockets_factory_card_id, stadium.card_id}}
          end

        [] ->
          {:error, {:stadium_not_in_play, @team_rockets_factory_card_id}}

        _multiple ->
          {:error, {:stadium_not_in_play, @team_rockets_factory_card_id}}
      end
    end
  end

  @doc """
  Checks if Risky Ruins is the active Stadium and the benched card is a Basic non-Darkness Pokémon.
  If so, applies 20 damage to the benched card.
  Returns `{:ok, damage_payload}` when damage was applied,
  `{:ok, nil}` when no effect applies.
  The caller should include the payload in the bench event.
  """
  def apply_risky_ruins_if_needed(game_id, %CardInstance{} = pokemon_card, _turn_id, _player_id)
      when is_binary(game_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium),
         true <- Enum.any?(stadiums, &match?(%CardInstance{card_id: @risky_ruins_card_id}, &1)),
         {:ok, catalog_card} <- CardCatalog.fetch(pokemon_card.card_id),
         true <- risky_ruins_target?(catalog_card) do
      new_damage = pokemon_card.damage + @risky_ruins_damage

      with {:ok, _updated} <- update(pokemon_card, :set_damage, %{damage: new_damage}) do
        {:ok,
         %{
           damage: @risky_ruins_damage,
           target_card_instance_id: pokemon_card.id,
           target_card_id: pokemon_card.card_id,
           stadium_card_id: @risky_ruins_card_id
         }}
      end
    else
      _other -> {:ok, nil}
    end
  end

  defp risky_ruins_target?(%{supertype: :pokemon, stage: :basic, type: type})
       when type != :darkness, do: true

  defp risky_ruins_target?(_catalog_card), do: false

  @doc """
  Waives the same-turn evolution restriction when Forest of Vitality is active
  and the evolution card is a Grass-type Pokémon. Applies only when the target
  card entered play this turn (turn_entered_play == turn_number) and it's not
  the first turn of the game.

  Returns `:ok` when:
  - The target did NOT enter play this turn (normal case — no stadium needed), OR
  - Forest of Vitality is the active Stadium AND the evolution card is Grass AND
    it's not turn 1.

  Returns `{:error, :target_entered_play_this_turn}` when the target entered play
  this turn but Forest of Vitality does not apply.
  """
  def require_or_waive_same_turn_evolution(_game_id, _target_card, _evolution_card_id, %Turn{
        turn_number: turn_number
      })
      when turn_number <= 1, do: {:error, :cannot_evolve_on_first_turn}

  def require_or_waive_same_turn_evolution(
        game_id,
        %CardInstance{turn_entered_play: turn_entered_play} = _target_card,
        evolution_card_id,
        %Turn{turn_number: turn_number}
      )
      when is_binary(game_id) and is_binary(evolution_card_id) do
    cond do
      is_nil(turn_entered_play) ->
        {:error, :target_play_turn_unknown}

      turn_entered_play < turn_number ->
        # Target entered play on a previous turn — normal evolution, no stadium needed
        :ok

      turn_entered_play == turn_number ->
        # Target entered play this turn — check Forest of Vitality exception
        with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium),
             true <-
               Enum.any?(
                 stadiums,
                 &match?(%CardInstance{card_id: @forest_of_vitality_card_id}, &1)
               ),
             {:ok, catalog_card} <- CardCatalog.fetch(evolution_card_id),
             true <- grass_type?(catalog_card) do
          :ok
        else
          _other -> {:error, :target_entered_play_this_turn}
        end

      true ->
        {:error, :target_play_turn_unknown}
    end
  end

  def require_or_waive_same_turn_evolution(_game_id, _target_card, _evolution_card_id, _turn) do
    {:error, :target_play_turn_unknown}
  end

  def forest_of_vitality_active?(game_id) when is_binary(game_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      {:ok, Enum.any?(stadiums, &match?(%CardInstance{card_id: @forest_of_vitality_card_id}, &1))}
    end
  end

  defp grass_type?(%{supertype: :pokemon, type: :grass}), do: true
  defp grass_type?(_catalog_card), do: false

  def require_team_rockets_factory_available(game_id, turn_id, player_id)
      when is_binary(game_id) and is_binary(turn_id) and is_binary(player_id) do
    with :ok <- require_team_rocket_supporter_played_this_turn(game_id, turn_id, player_id),
         :ok <- require_team_rockets_factory_unused_this_turn(game_id, turn_id, player_id),
         {:ok, deck_count} <- CardStore.deck_count(game_id, player_id),
         true <- deck_count > 0 || {:error, :team_rockets_factory_has_no_effect} do
      :ok
    end
  end

  def recover_special_conditions(game_id) when is_binary(game_id) do
    with {:ok, stadium} <- active_special_condition_immunity_stadium(game_id) do
      case stadium do
        %CardInstance{} = stadium -> recover_in_play_special_conditions(game_id, stadium)
        nil -> {:ok, []}
      end
    end
  end

  def recover_special_condition(game_id, %CardInstance{} = card) when is_binary(game_id) do
    with {:ok, stadium} <- active_special_condition_immunity_stadium(game_id) do
      case stadium do
        %CardInstance{} = stadium -> recover_card_special_condition(game_id, stadium, card)
        nil -> {:ok, nil}
      end
    end
  end

  def status_condition_prevention_payload(game_id, %CardInstance{} = card, status)
      when is_binary(game_id) do
    with true <- special_condition?(status),
         true <- in_play?(card),
         {:ok, %CardInstance{} = stadium} <- active_special_condition_immunity_stadium(game_id),
         true <- energy_attached?(game_id, card) do
      {:prevented, prevention_payload(stadium, card, status)}
    else
      _other -> :not_prevented
    end
  end

  defp active_special_condition_immunity_stadium(game_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      stadium = Enum.find(stadiums, &special_condition_immunity_stadium?/1)
      {:ok, stadium}
    end
  end

  defp require_team_rocket_supporter_played_this_turn(game_id, turn_id, player_id) do
    with {:ok, events} <- card_play_completed_events_for_turn(game_id, turn_id, player_id) do
      if Enum.any?(events, &team_rocket_supporter_card_play?/1) do
        :ok
      else
        {:error, :team_rockets_factory_requires_team_rocket_supporter_played_this_turn}
      end
    end
  end

  defp require_team_rockets_factory_unused_this_turn(game_id, turn_id, player_id) do
    with {:ok, events} <- stadium_effect_used_events_for_turn(game_id, turn_id, player_id) do
      if Enum.any?(events, &team_rockets_factory_effect_used?/1) do
        {:error, :team_rockets_factory_already_used_this_turn}
      else
        :ok
      end
    end
  end

  defp card_play_completed_events_for_turn(game_id, turn_id, player_id) do
    GameEvent
    |> Ash.Query.filter(
      game_id == ^game_id and turn_id == ^turn_id and player_id == ^player_id and
        type == "card_play_completed"
    )
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp stadium_effect_used_events_for_turn(game_id, turn_id, player_id) do
    GameEvent
    |> Ash.Query.filter(
      game_id == ^game_id and turn_id == ^turn_id and player_id == ^player_id and
        type == "stadium_effect_used"
    )
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp team_rocket_supporter_card_play?(%GameEvent{payload: payload}) do
    case payload_value(payload, "card_id") do
      card_id when is_binary(card_id) -> team_rocket_supporter_card_id?(card_id)
      _other -> false
    end
  end

  defp team_rockets_factory_effect_used?(%GameEvent{payload: payload}) do
    payload_value(payload, "effect_key") == Atom.to_string(@team_rockets_factory_effect) or
      payload_value(payload, "source_card_id") == @team_rockets_factory_card_id
  end

  defp team_rocket_supporter_card_id?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{trainer_type: :supporter, name: "Team Rocket" <> _rest}} -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  defp payload_value(payload, key) when is_map(payload) and is_binary(key) do
    case payload_atom_key(key) do
      nil -> Map.get(payload, key)
      atom_key -> Map.get(payload, key) || Map.get(payload, atom_key)
    end
  end

  defp payload_atom_key("card_id"), do: :card_id
  defp payload_atom_key("effect_key"), do: :effect_key
  defp payload_atom_key("source_card_id"), do: :source_card_id
  defp payload_atom_key(_key), do: nil

  defp special_condition_immunity_stadium?(%CardInstance{card_id: card_id}) do
    card_id
    |> CardCatalog.fetch()
    |> case do
      {:ok, card} -> supported_stadium?(card)
      {:error, _reason} -> false
    end
  end

  defp recover_in_play_special_conditions(game_id, %CardInstance{} = stadium) do
    with {:ok, cards} <- in_play_cards(game_id) do
      cards
      |> Enum.map(&recover_card_special_condition(game_id, stadium, &1))
      |> collect_recoveries()
    end
  end

  defp in_play_cards(game_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, :bench) do
      {:ok, active_cards ++ bench_cards}
    end
  end

  defp recover_card_special_condition(game_id, %CardInstance{} = stadium, %CardInstance{} = card) do
    if recoverable_special_condition?(game_id, card) do
      with {:ok, _card} <- update(card, :set_status, %{status: nil}) do
        {:ok, recovery_payload(stadium, card)}
      end
    else
      {:ok, nil}
    end
  end

  defp recoverable_special_condition?(game_id, %CardInstance{status: status} = card) do
    special_condition?(status) and in_play?(card) and energy_attached?(game_id, card)
  end

  defp energy_attached?(game_id, %CardInstance{} = card) do
    case CardStore.attached_cards(game_id, card.id) do
      {:ok, attached_cards} -> Enum.any?(attached_cards, &energy_card?/1)
      {:error, _reason} -> false
    end
  end

  defp energy_card?(%CardInstance{card_id: card_id}) do
    card_id
    |> CardCatalog.fetch()
    |> case do
      {:ok, %{supertype: :energy}} -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  defp recovery_payload(%CardInstance{} = stadium, %CardInstance{} = card) do
    %{
      card_instance_id: card.id,
      card_id: card.card_id,
      owner_player_id: card.owner_player_id,
      recovered_status: Atom.to_string(card.status),
      stadium_card_id: stadium.card_id,
      stadium_card_instance_id: stadium.id,
      stadium_effect_id: @festival_grounds_effect_id
    }
  end

  defp prevention_payload(%CardInstance{} = stadium, %CardInstance{} = card, status) do
    %{
      protected_card_instance_id: card.id,
      prevented_status: Atom.to_string(status),
      status_prevention_source_card_id: stadium.card_id,
      status_prevention_source_card_instance_id: stadium.id,
      status_prevention_source_effect_id: @festival_grounds_effect_id,
      status_prevention_source_player_id: stadium.owner_player_id
    }
  end

  defp special_condition?(status), do: status in @special_conditions
  defp in_play?(%CardInstance{zone: zone}), do: zone in [:active, :bench]

  defp collect_recoveries(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, nil}, {:ok, acc} -> {:cont, {:ok, acc}}
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end
end

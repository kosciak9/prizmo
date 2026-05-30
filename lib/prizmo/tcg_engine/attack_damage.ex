defmodule Prizmo.TcgEngine.AttackDamage do
  @moduledoc false

  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @spec damage_for(CardInstance.t(), CardInstance.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def damage_for(%CardInstance{} = attacker_card, %CardInstance{} = defender_card, attack)
      when is_map(attack) do
    with {:ok, damage} <- base_damage(attack) do
      apply_effect(damage, attacker_card, defender_card, Map.get(attack, :effect))
    end
  end

  defp base_damage(%{damage: damage}) when is_integer(damage) and damage >= 0, do: {:ok, damage}
  defp base_damage(%{damage: nil}), do: {:ok, 0}
  defp base_damage(attack) when not is_map_key(attack, :damage), do: {:ok, 0}
  defp base_damage(%{damage: damage}), do: {:error, {:unsupported_attack_damage, damage}}

  defp apply_effect(damage, _attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_if_defender_pokemon_ex,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id) do
      if pokemon_ex?(defender_metadata) do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :bonus_damage_if_attacker_has_team_rocket_energy,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, has_team_rocket_energy?} <- attached_team_rocket_energy?(attacker_card) do
      if has_team_rocket_energy? do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :bonus_damage_if_moved_from_bench_to_active_this_turn,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, moved?} <- moved_from_bench_to_active_this_turn?(attacker_card) do
      if moved? do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_per_benched_pokemon,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, benched_pokemon_count} <- benched_pokemon_count(attacker_card, defender_card) do
      {:ok, damage + bonus_damage * benched_pokemon_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :damage_per_own_benched_pokemon,
         damage_per_pokemon: damage_per_pokemon
       })
       when is_integer(damage_per_pokemon) and damage_per_pokemon >= 0 do
    with {:ok, benched_pokemon_count} <- own_benched_pokemon_count(attacker_card) do
      {:ok, damage + damage_per_pokemon * benched_pokemon_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :damage_per_own_basic_pokemon_in_play,
         damage_per_pokemon: damage_per_pokemon
       })
       when is_integer(damage_per_pokemon) and damage_per_pokemon >= 0 do
    with {:ok, basic_pokemon_count} <- own_basic_pokemon_in_play_count(attacker_card) do
      {:ok, damage + damage_per_pokemon * basic_pokemon_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :damage_per_own_team_rocket_pokemon_in_play,
         damage_per_pokemon: damage_per_pokemon
       })
       when is_integer(damage_per_pokemon) and damage_per_pokemon >= 0 do
    with {:ok, team_rocket_pokemon_count} <- own_team_rocket_pokemon_in_play_count(attacker_card) do
      {:ok, damage + damage_per_pokemon * team_rocket_pokemon_count}
    end
  end

  defp apply_effect(damage, %CardInstance{game_id: game_id}, _defender_card, %{
         type: :damage_only_if_stadium_in_play
       }) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      if Enum.empty?(stadiums), do: {:ok, 0}, else: {:ok, damage}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_per_energy_attached_to_both_active,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, energy_count} <-
           attached_energy_count_for_both_active(attacker_card, defender_card) do
      {:ok, damage + bonus_damage * energy_count}
    end
  end

  defp apply_effect(damage, _attacker_card, _defender_card, nil), do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_per_energy_attached_to_defender,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, energy_count} <- attached_energy_count(defender_card) do
      {:ok, damage + bonus_damage * energy_count}
    end
  end

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :switch_self_with_bench}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :damage_unaffected_by_effects_on_opponent_active
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :draw_after_attack}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :self_damage}),
    do: {:ok, damage}

  defp apply_effect(_damage, _attacker_card, _defender_card, effect) do
    {:error, {:unsupported_attack_effect, AttackEffects.type(effect)}}
  end

  defp pokemon_ex?(%{supertype: :pokemon, suffix: "ex"}), do: true

  defp pokemon_ex?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex")
  end

  defp pokemon_ex?(_metadata), do: false

  defp attached_energy_count(%CardInstance{game_id: game_id, id: card_instance_id}) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, card_instance_id) do
      attached_cards
      |> Enum.map(&energy_card?/1)
      |> collect_energy_count()
    end
  end

  defp energy_card?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :energy}} -> {:ok, true}
      {:ok, _card} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attached_team_rocket_energy?(%CardInstance{game_id: game_id, id: card_instance_id}) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, card_instance_id) do
      Enum.reduce_while(attached_cards, {:ok, false}, fn card, {:ok, false} ->
        case team_rocket_energy_card?(card) do
          {:ok, true} -> {:halt, {:ok, true}}
          {:ok, false} -> {:cont, {:ok, false}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp team_rocket_energy_card?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :energy, name: "Team Rocket's Energy"}} -> {:ok, true}
      {:ok, _card} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_energy_count(results) do
    Enum.reduce_while(results, {:ok, 0}, fn
      {:ok, true}, {:ok, count} -> {:cont, {:ok, count + 1}}
      {:ok, false}, {:ok, count} -> {:cont, {:ok, count}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp attached_energy_count_for_both_active(attacker_card, defender_card) do
    with {:ok, attacker_energy_count} <- attached_energy_count(attacker_card),
         {:ok, defender_energy_count} <- attached_energy_count(defender_card) do
      {:ok, attacker_energy_count + defender_energy_count}
    end
  end

  defp benched_pokemon_count(%CardInstance{game_id: game_id} = attacker_card, defender_card) do
    [attacker_card.owner_player_id, defender_card.owner_player_id]
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, 0}, fn player_id, {:ok, count} ->
      case CardStore.cards_in_zone(game_id, player_id, :bench) do
        {:ok, cards} -> {:cont, {:ok, count + length(cards)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp own_benched_pokemon_count(%CardInstance{game_id: game_id, owner_player_id: player_id}) do
    with {:ok, cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      {:ok, length(cards)}
    end
  end

  defp own_basic_pokemon_in_play_count(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      [active_cards, bench_cards]
      |> List.flatten()
      |> Enum.map(&basic_pokemon_card?/1)
      |> collect_basic_pokemon_count()
    end
  end

  defp basic_pokemon_card?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, stage: :basic}} -> {:ok, true}
      {:ok, _card} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_basic_pokemon_count(results) do
    Enum.reduce_while(results, {:ok, 0}, fn
      {:ok, true}, {:ok, count} -> {:cont, {:ok, count + 1}}
      {:ok, false}, {:ok, count} -> {:cont, {:ok, count}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp own_team_rocket_pokemon_in_play_count(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      [active_cards, bench_cards]
      |> List.flatten()
      |> Enum.map(&team_rocket_pokemon_card?/1)
      |> collect_team_rocket_pokemon_count()
    end
  end

  defp team_rocket_pokemon_card?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, name: "Team Rocket's " <> _name}} -> {:ok, true}
      {:ok, _card} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_team_rocket_pokemon_count(results) do
    Enum.reduce_while(results, {:ok, 0}, fn
      {:ok, true}, {:ok, count} -> {:cont, {:ok, count + 1}}
      {:ok, false}, {:ok, count} -> {:cont, {:ok, count}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp moved_from_bench_to_active_this_turn?(%CardInstance{
         game_id: game_id,
         id: card_instance_id,
         owner_player_id: player_id
       }) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, events} <- turn_player_events(game_id, turn.id, player_id) do
      {:ok, Enum.any?(events, &bench_to_active_event?(&1, card_instance_id))}
    end
  end

  defp turn_player_events(game_id, turn_id, player_id) do
    case GameEvent
         |> Ash.Query.filter(game_id == ^game_id and player_id == ^player_id)
         |> Ash.Query.sort(index: :asc)
         |> Ash.read() do
      {:ok, events} ->
        {:ok, Enum.filter(events, &(Map.get(&1.payload, "turn_id") == turn_id))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bench_to_active_event?(%GameEvent{type: type, payload: payload}, card_instance_id)
       when type in ["retreat", "switch_active_with_bench"] do
    Map.get(payload, "bench_card_instance_id") == card_instance_id
  end

  defp bench_to_active_event?(
         %GameEvent{type: "resolve_declared_attack", payload: payload},
         card_instance_id
       ) do
    Map.get(payload, "effect_type") == "switch_self_with_bench" and
      Map.get(payload, "switched_bench_card_instance_id") == card_instance_id
  end

  defp bench_to_active_event?(%GameEvent{}, _card_instance_id), do: false
end

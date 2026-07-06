defmodule Prizmo.TcgEngine.AttackDamage do
  @moduledoc false

  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @starting_prize_count 6

  @spec damage_for(CardInstance.t(), CardInstance.t(), map(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  @spec damage_for(CardInstance.t(), CardInstance.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def damage_for(
        %CardInstance{} = attacker_card,
        %CardInstance{} = defender_card,
        attack,
        opts \\ %{}
      )
      when is_map(attack) and is_map(opts) do
    with {:ok, damage} <- base_damage(attack),
         {:ok, damage} <-
           apply_effect(damage, attacker_card, defender_card, Map.get(attack, :effect), opts),
         {:ok, damage} <-
           apply_tool_attack_damage_bonus(damage, attacker_card, defender_card),
         {:ok, damage} <-
           apply_black_belts_training_bonus(damage, attacker_card, defender_card),
         {:ok, damage} <- apply_kieran_damage_bonus(damage, attacker_card, defender_card) do
      if weakness_and_resistance_ignored?(attack) do
        {:ok, max(damage, 0)}
      else
        apply_weakness_and_resistance(damage, attacker_card, defender_card)
      end
    end
  end

  defp base_damage(%{damage: damage}) when is_integer(damage) and damage >= 0, do: {:ok, damage}
  defp base_damage(%{damage: nil}), do: {:ok, 0}
  defp base_damage(attack) when not is_map_key(attack, :damage), do: {:ok, 0}
  defp base_damage(%{damage: damage}), do: {:error, {:unsupported_attack_damage, damage}}

  defp apply_effect(
         _damage,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card,
         %{type: :copy_opponent_active_tera_pokemon_attack},
         opts
       ) do
    with {:ok, {copied_attack, _copy_payload}} <-
           AttackEffects.effective_attack_for_resolution(
             defender_card,
             %{
               effect: %{type: :copy_opponent_active_tera_pokemon_attack}
             },
             opts
           ) do
      damage_for(attacker_card, defender_card, copied_attack, opts)
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{type: :bonus_damage_on_coin_heads, bonus_damage: bonus_damage},
         opts
       )
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, coin_result} <- AttackEffects.coin_result(opts) do
      if coin_result == :heads do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{type: :bonus_damage_per_coin_heads_count, bonus_damage: bonus_damage},
         opts
       )
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, heads_count} <- AttackEffects.heads_count(opts) do
      {:ok, damage + heads_count * bonus_damage}
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads},
         opts
       ) do
    with {:ok, _coin_result} <- AttackEffects.coin_result(opts) do
      {:ok, damage}
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{type: :discard_defending_energy_on_coin_heads},
         opts
       ) do
    with {:ok, _coin_result} <- AttackEffects.coin_result(opts) do
      {:ok, damage}
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{type: :damage_per_discarded_own_basic_energy, damage_per_energy: damage_per_energy},
         opts
       )
       when is_integer(damage_per_energy) and damage_per_energy >= 0 do
    with {:ok, energy_card_instance_ids} <- discarded_energy_card_instance_ids(opts) do
      {:ok, damage + length(energy_card_instance_ids) * damage_per_energy}
    end
  end

  defp apply_effect(
         damage,
         _attacker_card,
         _defender_card,
         %{
           type: :discard_energy_from_own_bench_for_bonus_damage,
           bonus_damage: bonus_damage,
           max_discards: max_discards
         },
         opts
       )
       when is_integer(bonus_damage) and bonus_damage >= 0 and is_integer(max_discards) and
              max_discards >= 0 do
    with {:ok, energy_card_instance_ids} <- discarded_energy_card_instance_ids(opts),
         :ok <- require_max_discarded_energy_count(energy_card_instance_ids, max_discards) do
      {:ok, damage + length(energy_card_instance_ids) * bonus_damage}
    end
  end

  defp apply_effect(damage, attacker_card, defender_card, effect, _opts) do
    apply_effect(damage, attacker_card, defender_card, effect)
  end

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

  defp apply_effect(damage, %CardInstance{game_id: game_id}, _defender_card, %{
         type: :bonus_damage_if_stadium_in_play_then_discard_stadium,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      if Enum.empty?(stadiums), do: {:ok, damage}, else: {:ok, damage + bonus_damage}
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

  defp apply_effect(damage, %CardInstance{} = attacker_card, %CardInstance{} = defender_card, %{
         type: :damage_per_opponent_pokemon_ex_in_play,
         damage_per_pokemon: damage_per_pokemon
       })
       when is_integer(damage_per_pokemon) and damage_per_pokemon >= 0 do
    with {:ok, opponent_pokemon_ex_count} <-
           opponent_pokemon_ex_in_play_count(attacker_card, defender_card) do
      {:ok, damage + damage_per_pokemon * opponent_pokemon_ex_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :damage_per_opponent_prize_taken,
         damage_per_prize: damage_per_prize
       })
       when is_integer(damage_per_prize) and damage_per_prize >= 0 do
    with {:ok, opponent_prize_taken_count} <- opponent_prize_taken_count(attacker_card) do
      {:ok, damage + damage_per_prize * opponent_prize_taken_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :bonus_damage_if_own_pokemon_knocked_out_last_turn,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, own_pokemon_knocked_out_last_turn?} <-
           own_pokemon_knocked_out_last_turn?(attacker_card) do
      if own_pokemon_knocked_out_last_turn? do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
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

  defp apply_effect(damage, %CardInstance{game_id: game_id}, %CardInstance{} = defender_card, %{
         type: :damage_per_opponent_hand_card,
         damage_per_card: damage_per_card
       })
       when is_integer(damage_per_card) and damage_per_card >= 0 do
    with {:ok, hand_cards} <-
           CardStore.cards_in_zone(game_id, defender_card.owner_player_id, :hand) do
      {:ok, damage + length(hand_cards) * damage_per_card}
    end
  end

  defp apply_effect(damage, _attacker_card, _defender_card, nil), do: {:ok, damage}

  defp apply_effect(
         _damage,
         %CardInstance{game_id: game_id, owner_player_id: player_id},
         _defender_card,
         %{
           type: :active_damage_counters_per_hand_card,
           counters_per_card: counters
         }
       )
       when is_integer(counters) and counters >= 0 do
    with {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, player_id, :hand) do
      {:ok, length(hand_cards) * counters * 10}
    end
  end

  defp apply_effect(damage, _attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_per_energy_attached_to_defender,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, energy_count} <- attached_energy_count(defender_card) do
      {:ok, damage + bonus_damage * energy_count}
    end
  end

  defp apply_effect(damage, %CardInstance{} = attacker_card, _defender_card, %{
         type: :bonus_damage_if_team_rocket_supporter_played_this_turn,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, team_rocket_supporter_played?} <-
           team_rocket_supporter_played_this_turn?(attacker_card) do
      if team_rocket_supporter_played? do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :switch_self_with_bench}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :damage_unaffected_by_effects_on_opponent_active
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :draw_after_attack}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :discard_hand_then_draw}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :search_pokemon_to_hand}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :recover_trainer_from_discard_to_hand
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :return_attached_energy_to_hand
       }), do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :opponent_bench_damage_counters
       }), do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :put_up_to_3_duskull_from_discard_to_bench
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :shuffle_attached_energy_into_deck_then_damage_opponent_bench
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :attacker_cannot_attack_next_turn
       }), do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :confuse_defender_active}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :sleep_defender_active}),
    do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :confuse_defender_active_then_move_opponent_damage_counters
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :defending_pokemon_cannot_retreat_next_turn
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :lock_opponent_items_next_turn
       }), do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :move_opponent_attached_energy_between_pokemon
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :discard_defending_energy_on_coin_heads
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{
         type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads
       }),
       do: {:ok, damage}

  defp apply_effect(damage, _attacker_card, _defender_card, %{type: :self_damage}),
    do: {:ok, damage}

  defp apply_effect(_damage, _attacker_card, _defender_card, effect) do
    {:error, {:unsupported_attack_effect, AttackEffects.type(effect)}}
  end

  defp apply_weakness_and_resistance(0, %CardInstance{}, %CardInstance{}), do: {:ok, 0}

  defp apply_weakness_and_resistance(
         damage,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card
       ) do
    with {:ok, attacker_metadata} <- CardCatalog.fetch(attacker_card.card_id),
         {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id),
         {:ok, weakness} <- effective_weakness(attacker_card, defender_card, defender_metadata) do
      damage =
        damage
        |> apply_weakness(attacker_metadata, weakness)
        |> apply_resistance(attacker_metadata, defender_metadata)
        |> max(0)

      {:ok, damage}
    end
  end

  defp effective_weakness(
         %CardInstance{game_id: game_id, owner_player_id: attacker_player_id},
         %CardInstance{},
         defender_metadata
       ) do
    with true <- darkness_pokemon?(defender_metadata),
         {:ok, cards} <- CardStore.list_cards(game_id),
         true <- Enum.any?(cards, &opponent_fairy_zone_active?(&1, attacker_player_id)) do
      {:ok, %{type: :psychic, multiplier: 2}}
    else
      false -> {:ok, Map.get(defender_metadata, :weakness)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_weakness(damage, %{type: attack_type}, %{type: attack_type, multiplier: multiplier})
       when is_integer(multiplier) and multiplier > 0 do
    damage * multiplier
  end

  defp apply_weakness(damage, _attacker_metadata, _weakness), do: damage

  defp apply_resistance(damage, %{type: attack_type}, %{
         resistance: %{type: attack_type, value: value}
       })
       when is_integer(value) do
    damage + value
  end

  defp apply_resistance(damage, _attacker_metadata, _defender_metadata), do: damage

  defp weakness_and_resistance_ignored?(%{
         effect: %{type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active}
       }),
       do: true

  defp weakness_and_resistance_ignored?(_attack), do: false

  defp opponent_fairy_zone_active?(
         %CardInstance{owner_player_id: owner_player_id, zone: zone, card_id: card_id},
         attacker_player_id
       )
       when owner_player_id == attacker_player_id and zone in [:active, :bench] do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         abilities: %{
           fairy_zone: %{effect: %{type: :opponent_darkness_pokemon_weakness_becomes_psychic}}
         }
       }} ->
        true

      {:ok, _metadata} ->
        false

      {:error, _reason} ->
        false
    end
  end

  defp opponent_fairy_zone_active?(%CardInstance{}, _attacker_player_id), do: false

  defp darkness_pokemon?(%{supertype: :pokemon, types: types}) when is_list(types) do
    :darkness in types
  end

  defp darkness_pokemon?(%{supertype: :pokemon, type: :darkness}), do: true
  defp darkness_pokemon?(_metadata), do: false

  defp apply_black_belts_training_bonus(
         damage,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card
       ) do
    with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id) do
      if pokemon_ex?(defender_metadata) and
           black_belts_training_played_this_turn?(attacker_card) do
        {:ok, damage + 40}
      else
        {:ok, damage}
      end
    end
  end

  defp black_belts_training_played_this_turn?(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, turn} <- TurnStore.current_turn(game_id) do
      events =
        GameEvent
        |> Ash.Query.filter(
          game_id == ^game_id and player_id == ^player_id and type == "card_play_completed" and
            turn_id == ^turn.id
        )
        |> Ash.Query.sort(index: :asc)
        |> Ash.read()

      case events do
        {:ok, events} ->
          {:ok, Enum.any?(events, &(&1.payload["card_id"] == "JTG-143"))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp apply_kieran_damage_bonus(
         damage,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card
       ) do
    with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id) do
      if pokemon_ex_or_v?(defender_metadata) and
           kieran_damage_played_this_turn?(attacker_card) do
        {:ok, damage + 30}
      else
        {:ok, damage}
      end
    end
  end

  defp kieran_damage_played_this_turn?(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, events} <- current_turn_card_play_completed_events(game_id, player_id) do
      {:ok,
       Enum.any?(events, fn event ->
         event.payload["card_id"] == "TWM-154" and
           event.payload["kieran_effect"] == "damage"
       end)}
    end
  end

  defp team_rocket_supporter_played_this_turn?(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, events} <- current_turn_card_play_completed_events(game_id, player_id) do
      {:ok, Enum.any?(events, &team_rocket_supporter_card_play?/1)}
    end
  end

  defp current_turn_card_play_completed_events(game_id, player_id)
       when is_binary(game_id) and is_binary(player_id) do
    with {:ok, turn} <- TurnStore.current_turn(game_id) do
      GameEvent
      |> Ash.Query.filter(
        game_id == ^game_id and player_id == ^player_id and type == "card_play_completed" and
          turn_id == ^turn.id
      )
      |> Ash.Query.sort(index: :asc)
      |> Ash.read()
    end
  end

  defp team_rocket_supporter_card_play?(%GameEvent{payload: payload}) do
    case payload["card_id"] do
      card_id when is_binary(card_id) -> team_rocket_supporter_card_id?(card_id)
      _other -> false
    end
  end

  defp team_rocket_supporter_card_id?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{trainer_type: :supporter, name: "Team Rocket" <> _rest}} -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  defp pokemon_ex_or_v?(%{supertype: :pokemon, suffix: suffix})
       when suffix in ["ex", "V", "VMAX", "VSTAR"], do: true

  defp pokemon_ex_or_v?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex") or String.ends_with?(name, " V") or
      String.ends_with?(name, " VMAX") or String.ends_with?(name, " VSTAR")
  end

  defp pokemon_ex_or_v?(_metadata), do: false

  defp apply_tool_attack_damage_bonus(
         damage,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card
       ) do
    with {:ok, bonus_damage} <-
           ToolEffects.attack_damage_bonus(attacker_card.game_id, attacker_card, defender_card) do
      {:ok, damage + bonus_damage}
    end
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

  defp opponent_pokemon_ex_in_play_count(%CardInstance{game_id: game_id}, %CardInstance{
         owner_player_id: player_id
       }) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      [active_cards, bench_cards]
      |> List.flatten()
      |> Enum.map(&pokemon_ex_card?/1)
      |> collect_pokemon_ex_count()
    end
  end

  defp pokemon_ex_card?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, metadata} -> {:ok, pokemon_ex?(metadata)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_pokemon_ex_count(results) do
    Enum.reduce_while(results, {:ok, 0}, fn
      {:ok, true}, {:ok, count} -> {:cont, {:ok, count + 1}}
      {:ok, false}, {:ok, count} -> {:cont, {:ok, count}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp discarded_energy_card_instance_ids(opts) do
    case Map.get(opts, :discarded_energy_card_instance_ids) ||
           Map.get(opts, "discarded_energy_card_instance_ids") do
      nil -> {:ok, []}
      ids when is_list(ids) -> {:ok, ids}
      _invalid -> {:error, :invalid_discarded_energy_card_instance_ids}
    end
  end

  defp require_max_discarded_energy_count(energy_card_instance_ids, max_discards) do
    if length(energy_card_instance_ids) <= max_discards do
      :ok
    else
      {:error, {:too_many_discarded_energy_cards, max_discards}}
    end
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
         %GameEvent{type: "ability_used", payload: payload},
         card_instance_id
       ) do
    Map.get(payload, "ability_id") == "subjugating_chains" and
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

  defp opponent_prize_taken_count(%CardInstance{game_id: game_id, owner_player_id: player_id}) do
    with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player_id, :prize) do
      {:ok, max(@starting_prize_count - length(prizes), 0)}
    end
  end

  defp own_pokemon_knocked_out_last_turn?(%CardInstance{
         game_id: game_id,
         owner_player_id: player_id
       }) do
    with {:ok, current_turn} <- TurnStore.current_turn(game_id),
         {:ok, turns} <- TurnStore.list_all_turns(game_id),
         previous_turn when not is_nil(previous_turn) <-
           Enum.find(turns, &(&1.turn_number == current_turn.turn_number - 1)),
         true <- previous_turn.active_player_id != player_id,
         {:ok, events} <-
           turn_player_events(game_id, previous_turn.id, previous_turn.active_player_id) do
      {:ok, Enum.any?(events, &knocked_out_own_pokemon_by_attack_damage?(&1, player_id, game_id))}
    else
      nil -> {:ok, false}
      false -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp knocked_out_own_pokemon_by_attack_damage?(
         %GameEvent{type: type, payload: payload},
         player_id,
         game_id
       )
       when type in ["resolve_attack_damage", "resolve_declared_attack"] do
    if payload["knocked_out?"] do
      card_instance_id =
        payload["target_card_instance_id"] || payload["defender_card_instance_id"]

      case card_instance_id do
        id when is_binary(id) ->
          case CardStore.get_card(game_id, id) do
            {:ok, %CardInstance{owner_player_id: ^player_id}} -> true
            _other -> false
          end

        _other ->
          false
      end
    else
      false
    end
  end

  defp knocked_out_own_pokemon_by_attack_damage?(
         %GameEvent{type: "take_knockout_prizes", payload: payload},
         player_id,
         _game_id
       ) do
    payload
    |> Map.get("knockouts", [])
    |> Enum.any?(fn
      %{"knocked_out_player_id" => ^player_id} -> true
      _other -> false
    end)
  end

  defp knocked_out_own_pokemon_by_attack_damage?(%GameEvent{}, _player_id, _game_id), do: false
end

defmodule Prizmo.Tcg.Sim.Hooks do
  @moduledoc """
  Hook phase runner for card effects that modify or block generic engine actions.

  Hooks return `{:ok, state}` when a stateful phase should continue, `{:ok, value}`
  for value-modifying phases such as `:modify_damage`, or `{:halt, reason}` when
  a card effect prevents the action. Reducers decide whether a halted hook is an
  error or a legal prevention/no-op for the active phase.
  """

  alias Prizmo.Tcg.Cards.Metadata
  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.Tcg.Sim.StateMachines.CardLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.ZoneMovement

  def run(state, :before_play_trainer, context) do
    with {:ok, state} <- prevent_item_if_locked(state, context) do
      prevent_ace_spec_if_nullified(state, context)
    end
  end

  def run(state, :before_ability, context) do
    prevent_colorless_ability_if_watchtower(state, context)
  end

  def run(state, :modify_damage, context) do
    with {:ok, damage} <- modify_attack_damage_if_brave_bangle_active(state, context),
         {:ok, damage} <-
           modify_attack_damage_if_black_belts_training_active(
             state,
             %{context | damage: damage}
           ) do
      modify_attack_damage_if_kieran_active(
        state,
        %{context | damage: damage}
      )
    end
  end

  def run(state, :before_damage, context) do
    with {:ok, state} <- prevent_damage_if_dig_protected(state, context),
         {:ok, state} <- prevent_bench_attack_damage_if_spherical_shield(state, context),
         {:ok, state} <- prevent_bench_attack_damage_if_flower_curtain(state, context),
         {:ok, state} <- prevent_bench_damage_counters_if_battle_cage(state, context) do
      prevent_attack_damage_counters_if_mist_energy_attached(state, context)
    end
  end

  def run(state, :before_attack_effect, context) do
    with {:ok, state} <- prevent_attack_effect_if_dig_protected(state, context) do
      prevent_attack_effect_if_mist_energy_attached(state, context)
    end
  end

  def run(state, :after_damage, context) do
    with {:ok, state} <- draw_cards_if_lucky_helmet_active(state, context) do
      move_attack_energy_if_handheld_fan_active(state, context)
    end
  end

  def run(state, _phase, _context), do: {:ok, state}

  defp modify_attack_damage_if_brave_bangle_active(state, %{
         source: :attack,
         damage: damage,
         attacking_player_id: attacking_player_id,
         attacker_id: attacker_id,
         target_player_id: target_player_id,
         target_id: target_id,
         target_zone: :active
       })
       when is_integer(damage) and damage > 0 do
    with true <- attacking_player_id != target_player_id,
         {:ok, attacker} <- find_in_play(state, attacking_player_id, attacker_id),
         true <- equipped_tool?(attacker, "WHT-080"),
         {:ok, attacker_metadata} <- CardRegistry.fetch(attacker.card_id),
         false <- rule_box?(attacker_metadata),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         true <- active_target?(state, target_player_id, target),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         true <- pokemon_ex?(target_metadata) do
      {:ok, damage + 30}
    else
      false -> {:ok, damage}
      true -> {:ok, damage}
      {:error, reason} -> {:halt, reason}
    end
  end

  defp modify_attack_damage_if_brave_bangle_active(_state, %{damage: damage}), do: {:ok, damage}

  defp modify_attack_damage_if_black_belts_training_active(state, %{
         source: :attack,
         damage: damage,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id,
         target_zone: :active
       })
       when is_integer(damage) and damage > 0 do
    with true <- attacking_player_id != target_player_id,
         {:ok, attacking_player} <- fetch_player(state, attacking_player_id),
         true <-
           MapSet.member?(
             attacking_player.markers,
             {:damage_bonus_to_opponent_active_pokemon_ex, :black_belts_training}
           ),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         true <- active_target?(state, target_player_id, target),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         true <- pokemon_ex?(target_metadata) do
      {:ok, damage + 40}
    else
      false -> {:ok, damage}
      true -> {:ok, damage}
      {:error, reason} -> {:halt, reason}
    end
  end

  defp modify_attack_damage_if_black_belts_training_active(_state, %{damage: damage}),
    do: {:ok, damage}

  defp modify_attack_damage_if_kieran_active(state, %{
         source: :attack,
         damage: damage,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id,
         target_zone: :active
       })
       when is_integer(damage) and damage > 0 do
    with true <- attacking_player_id != target_player_id,
         {:ok, attacking_player} <- fetch_player(state, attacking_player_id),
         true <-
           MapSet.member?(
             attacking_player.markers,
             {:damage_bonus_to_opponent_active_pokemon_ex_or_v, :kieran}
           ),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         true <- active_target?(state, target_player_id, target),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         true <- pokemon_ex_or_v?(target_metadata) do
      {:ok, damage + 30}
    else
      false -> {:ok, damage}
      true -> {:ok, damage}
      {:error, reason} -> {:halt, reason}
    end
  end

  defp modify_attack_damage_if_kieran_active(_state, %{damage: damage}), do: {:ok, damage}

  defp draw_cards_if_lucky_helmet_active(state, %{
         source: :attack,
         attacking_player_id: attacking_player_id,
         target_player_id: defending_player_id,
         target_id: target_id,
         target_zone: :active,
         damage: damage
       })
       when is_integer(damage) and damage > 0 and attacking_player_id != defending_player_id do
    with {:ok, defender} <- find_in_play(state, defending_player_id, target_id),
         true <- active_target?(state, defending_player_id, defender),
         %{card_id: "TWM-158"} <- defender.tool do
      case draw_cards(state, defending_player_id, 2) do
        {:ok, state} -> {:ok, state}
        {:error, reason} -> {:halt, reason}
      end
    else
      false -> {:ok, state}
      nil -> {:ok, state}
      {:error, reason} -> {:halt, reason}
      _other_tool -> {:ok, state}
    end
  end

  defp draw_cards_if_lucky_helmet_active(state, _context), do: {:ok, state}

  defp move_attack_energy_if_handheld_fan_active(state, %{
         source: :attack,
         attack: _attack,
         attacking_player_id: attacking_player_id,
         attacker_id: attacker_id,
         target_player_id: defending_player_id,
         target_id: target_id,
         target_zone: :active,
         damage: damage,
         params: params
       }) do
    with true <- damage > 0,
         {:ok, defender} <- find_in_play(state, defending_player_id, target_id),
         %{card_id: "TWM-150"} <- defender.tool do
      with {:ok, attacker} <- find_in_play(state, attacking_player_id, attacker_id),
           attachment_id when not is_nil(attachment_id) <-
             Map.get(params, :handheld_fan_attachment_id),
           target_bench_id when not is_nil(target_bench_id) <-
             Map.get(params, :handheld_fan_target_id),
           {:ok, attachment} <- find_attachment(attacker, attachment_id),
           {:ok, attachment_metadata} <- CardRegistry.fetch(attachment.card_id),
           :ok <- require_energy(attachment_metadata),
           {:ok, bench_target} <-
             find_in_player_zone(state, defending_player_id, :bench, target_bench_id) do
        move_attached_card(
          state,
          attacking_player_id,
          attacker,
          attachment,
          defending_player_id,
          bench_target
        )
      else
        nil -> {:halt, :handheld_fan_requires_energy_and_bench_target}
        {:error, reason} -> {:halt, reason}
      end
    else
      false -> {:ok, state}
      {:ok, _defender_without_fan} -> {:ok, state}
      nil -> {:ok, state}
      {:error, reason} -> {:halt, reason}
      _other_tool -> {:ok, state}
    end
  end

  defp move_attack_energy_if_handheld_fan_active(state, _context), do: {:ok, state}

  defp draw_cards(state, _player_id, 0), do: {:ok, state}

  defp draw_cards(state, player_id, count) when count > 0 do
    with {:ok, state} <- draw_card(state, player_id) do
      draw_cards(state, player_id, count - 1)
    end
  end

  defp draw_card(state, player_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      case player.deck do
        [] ->
          {:error, :cannot_draw_from_empty_deck}

        [card | deck] ->
          with {:ok, :hand} <- ZoneMovement.transition(:deck, :hand),
               {:ok, :in_hand} <- CardLifecycle.transition(card.lifecycle, :draw) do
            card = %{card | zone: :hand, lifecycle: :in_hand}
            player = %{player | deck: deck, hand: [card | player.hand]}
            {:ok, put_player(state, player)}
          end
      end
    end
  end

  defp prevent_bench_attack_damage_if_spherical_shield(state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_zone: :bench
       })
       when attacking_player_id != target_player_id do
    if card_in_play?(state, target_player_id, "TEF-024"),
      do: {:halt, {:damage_prevented_by_ability, "TEF-024", :spherical_shield}},
      else: {:ok, state}
  end

  defp prevent_bench_attack_damage_if_spherical_shield(state, _context), do: {:ok, state}

  defp prevent_bench_attack_damage_if_flower_curtain(state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id,
         target_zone: :bench,
         damage_kind: :damage
       })
       when attacking_player_id != target_player_id do
    with true <- card_in_play?(state, target_player_id, "DRI-010"),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         {:ok, target_metadata} <- Metadata.fetch(target.card_id),
         false <- rule_box?(target_metadata) do
      {:halt, {:damage_prevented_by_ability, "DRI-010", :flower_curtain}}
    else
      false -> {:ok, state}
      true -> {:ok, state}
      {:error, reason} -> {:halt, reason}
    end
  end

  defp prevent_bench_attack_damage_if_flower_curtain(state, _context), do: {:ok, state}

  defp prevent_bench_damage_counters_if_battle_cage(%{stadium: %{card_id: "PFL-085"}} = _state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_zone: :bench,
         damage_kind: :damage_counters
       })
       when attacking_player_id != target_player_id do
    {:halt, {:damage_prevented_by_stadium, "PFL-085", :battle_cage}}
  end

  defp prevent_bench_damage_counters_if_battle_cage(%{stadium: %{card_id: "PFL-085"}} = _state, %{
         source: :ability_effect,
         source_player_id: source_player_id,
         target_player_id: target_player_id,
         target_zone: :bench,
         damage_kind: :damage_counters
       })
       when source_player_id != target_player_id do
    {:halt, {:damage_prevented_by_stadium, "PFL-085", :battle_cage}}
  end

  defp prevent_bench_damage_counters_if_battle_cage(state, _context), do: {:ok, state}

  defp prevent_damage_if_dig_protected(state, %{
         source: source,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id
       })
       when source in [:attack, :attack_effect] and attacking_player_id != target_player_id do
    if dig_protected?(state, target_player_id, target_id),
      do: {:halt, {:damage_prevented_by_attack_effect, "TEF-128", :dig}},
      else: {:ok, state}
  end

  defp prevent_damage_if_dig_protected(state, _context), do: {:ok, state}

  defp prevent_attack_damage_counters_if_mist_energy_attached(state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id,
         damage_kind: :damage_counters
       })
       when attacking_player_id != target_player_id do
    if mist_energy_attached?(state, target_player_id, target_id),
      do: {:halt, {:damage_prevented_by_energy, "TEF-161", :mist_energy}},
      else: {:ok, state}
  end

  defp prevent_attack_damage_counters_if_mist_energy_attached(state, _context), do: {:ok, state}

  defp prevent_attack_effect_if_dig_protected(state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id
       })
       when attacking_player_id != target_player_id do
    if dig_protected?(state, target_player_id, target_id),
      do: {:halt, {:attack_effect_prevented_by_attack_effect, "TEF-128", :dig}},
      else: {:ok, state}
  end

  defp prevent_attack_effect_if_dig_protected(state, _context), do: {:ok, state}

  defp prevent_attack_effect_if_mist_energy_attached(state, %{
         source: :attack_effect,
         attacking_player_id: attacking_player_id,
         target_player_id: target_player_id,
         target_id: target_id
       })
       when attacking_player_id != target_player_id do
    if mist_energy_attached?(state, target_player_id, target_id),
      do: {:halt, {:attack_effect_prevented_by_energy, "TEF-161", :mist_energy}},
      else: {:ok, state}
  end

  defp prevent_attack_effect_if_mist_energy_attached(state, _context), do: {:ok, state}

  defp prevent_colorless_ability_if_watchtower(%{stadium: %{card_id: "DRI-180"}} = _state, %{
         metadata: %{supertype: :pokemon, type: :colorless, id: card_id}
       }),
       do: {:halt, {:ability_blocked_by_stadium, "DRI-180", card_id}}

  defp prevent_colorless_ability_if_watchtower(state, _context), do: {:ok, state}

  defp prevent_item_if_locked(state, %{player_id: player_id, metadata: %{trainer_type: :item}}) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        if player.item_cards_locked?,
          do: {:halt, :item_cards_locked_this_turn},
          else: {:ok, state}

      {:error, reason} ->
        {:halt, reason}
    end
  end

  defp prevent_item_if_locked(state, _context), do: {:ok, state}

  defp prevent_ace_spec_if_nullified(state, %{player_id: player_id, metadata: %{ace_spec?: true}}) do
    case opponent_id(state, player_id) do
      {:ok, opponent_id} ->
        if ace_nullifier_active?(state, opponent_id),
          do: {:halt, :ace_spec_cards_blocked_by_ace_nullifier},
          else: {:ok, state}

      {:error, reason} ->
        {:halt, reason}
    end
  end

  defp prevent_ace_spec_if_nullified(state, _context), do: {:ok, state}

  defp ace_nullifier_active?(state, player_id) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        player
        |> in_play_cards()
        |> Enum.any?(fn pokemon -> pokemon.card_id == "SFA-040" && not is_nil(pokemon.tool) end)

      {:error, _reason} ->
        false
    end
  end

  defp opponent_id(state, player_id) do
    state.players
    |> Map.keys()
    |> Enum.reject(&(&1 == player_id))
    |> case do
      [opponent_id] -> {:ok, opponent_id}
      opponents -> {:error, {:expected_one_opponent, opponents}}
    end
  end

  defp fetch_player(state, player_id) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} -> {:ok, player}
      :error -> {:error, {:unknown_player, player_id}}
    end
  end

  defp find_in_player_zone(state, player_id, zone, instance_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      player
      |> Map.fetch!(zone)
      |> Enum.find(&(&1.instance_id == instance_id))
      |> case do
        nil -> {:error, {:card_not_found, player_id, zone, instance_id}}
        card -> {:ok, card}
      end
    end
  end

  defp find_in_play(state, player_id, instance_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      player
      |> in_play_cards()
      |> Enum.find(&(&1.instance_id == instance_id))
      |> case do
        nil -> {:error, {:pokemon_not_in_play, player_id, instance_id}}
        card -> {:ok, card}
      end
    end
  end

  defp find_attachment(target, attachment_id) do
    target.attachments
    |> Enum.find(&(&1.instance_id == attachment_id))
    |> case do
      nil -> {:error, {:attachment_not_found, target.instance_id, attachment_id}}
      attachment -> {:ok, attachment}
    end
  end

  defp mist_energy_attached?(state, player_id, target_id) do
    case find_in_play(state, player_id, target_id) do
      {:ok, target} -> Enum.any?(target.attachments, &(&1.card_id == "TEF-161"))
      {:error, _reason} -> false
    end
  end

  defp move_attached_card(
         state,
         from_player_id,
         from_pokemon,
         attachment,
         to_player_id,
         to_pokemon
       ) do
    with {:ok, from_player} <- fetch_player(state, from_player_id),
         {:ok, to_player} <- fetch_player(state, to_player_id) do
      updated_from = %{
        from_pokemon
        | attachments: reject_instance(from_pokemon.attachments, attachment.instance_id)
      }

      updated_to =
        to_pokemon
        |> Map.put(:attachments, [attachment | to_pokemon.attachments])
        |> recover_special_condition_if_festival_grounds_active(state)

      state = put_player(state, replace_in_play(from_player, updated_from))
      {:ok, put_player(state, replace_in_play(to_player, updated_to))}
    end
  end

  defp replace_in_play(player, card) do
    cond do
      player.active && player.active.instance_id == card.instance_id ->
        %{player | active: card}

      Enum.any?(player.bench, &(&1.instance_id == card.instance_id)) ->
        %{
          player
          | bench:
              Enum.map(player.bench, fn bench_card ->
                if bench_card.instance_id == card.instance_id, do: card, else: bench_card
              end)
        }

      true ->
        player
    end
  end

  defp put_player(state, player),
    do: %{state | players: Map.put(state.players, player.id, player)}

  defp recover_special_condition_if_festival_grounds_active(pokemon, %{
         stadium: %{card_id: "TWM-149"}
       }),
       do: %{pokemon | status: nil}

  defp recover_special_condition_if_festival_grounds_active(pokemon, _state), do: pokemon

  defp require_energy(%{supertype: :energy}), do: :ok
  defp require_energy(metadata), do: {:error, {:not_energy, metadata}}

  defp reject_instance(cards, instance_id),
    do: Enum.reject(cards, &(&1.instance_id == instance_id))

  defp in_play_cards(player), do: Enum.reject([player.active | player.bench], &is_nil/1)

  defp equipped_tool?(%{tool: %{card_id: card_id}}, card_id), do: true
  defp equipped_tool?(_pokemon, _card_id), do: false

  defp active_target?(state, player_id, target) do
    case fetch_player(state, player_id) do
      {:ok, %{active: %{instance_id: instance_id}}} -> instance_id == target.instance_id
      _other -> false
    end
  end

  defp rule_box?(metadata), do: Map.get(metadata, :rule_box?, false)

  defp pokemon_ex?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex")
  end

  defp pokemon_ex?(_metadata), do: false

  defp pokemon_ex_or_v?(metadata), do: pokemon_ex?(metadata) || pokemon_v?(metadata)

  defp pokemon_v?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, [" V", " VMAX", " VSTAR", " V-UNION"])
  end

  defp pokemon_v?(_metadata), do: false

  defp card_in_play?(state, player_id, card_id) do
    case fetch_player(state, player_id) do
      {:ok, player} -> Enum.any?(in_play_cards(player), &(&1.card_id == card_id))
      {:error, _reason} -> false
    end
  end

  defp dig_protected?(state, player_id, target_id) do
    with {:ok, player} <- fetch_player(state, player_id),
         true <- in_play_instance?(player, target_id) do
      MapSet.member?(player.markers, {:prevent_damage_and_effects_from_attacks, target_id, :dig})
    else
      _not_protected -> false
    end
  end

  defp in_play_instance?(player, instance_id),
    do: Enum.any?(in_play_cards(player), &(&1.instance_id == instance_id))
end

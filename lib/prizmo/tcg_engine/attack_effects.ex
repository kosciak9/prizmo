defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [active_card: 2]

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      require_basic_energy: 1,
      require_energy: 1,
      require_pokemon_card: 1,
      require_tera_pokemon_card: 1,
      require_trainer_type: 2
    ]

  import Prizmo.TcgEngine.CardStore,
    only: [
      attached_cards: 2,
      cards_in_zone: 3,
      deck_cards_for_player: 2,
      discard_cards_from_hand: 3,
      get_card: 2,
      get_cards: 2,
      list_cards: 1,
      move_attached_card_to_hand: 3,
      move_deck_card_to_hand: 3,
      move_play_card_to_hand: 3,
      move_discard_card_to_hand: 3,
      next_bench_position: 2,
      next_hand_position_result: 2,
      shuffle_attached_cards_into_deck: 3
    ]

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [
      require_all_owned_in_zone: 3,
      require_card_owned_by_player: 2,
      require_card_zone: 2,
      require_exact_count: 3,
      require_in_play_pokemon_zone: 1,
      require_max_count: 3,
      require_unique_ids: 1
    ]

  alias Prizmo.TcgEngine.AbilityEffects
  alias Prizmo.TcgEngine.AttackLocks
  alias Prizmo.TcgEngine.AttackPrevention
  alias Prizmo.TcgEngine.BattleActions
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.HpEffects
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.RetreatLocks
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.TeraBenchProtection
  alias Prizmo.TcgEngine.TurnStore

  @copy_opponent_active_tera_pokemon_attack :copy_opponent_active_tera_pokemon_attack
  @spherical_shield_card_id "TEF-024"
  @spherical_shield_effect_id "spherical_shield"

  @supported_effect_types [
    :bonus_damage_per_benched_pokemon,
    :bonus_damage_if_stadium_in_play_then_discard_stadium,
    :bonus_damage_on_coin_heads,
    :bonus_damage_per_coin_heads_count,
    :bonus_damage_if_defender_pokemon_ex,
    :bonus_damage_if_attacker_has_team_rocket_energy,
    :bonus_damage_if_team_rocket_supporter_played_this_turn,
    :bonus_damage_if_own_pokemon_knocked_out_last_turn,
    :bonus_damage_if_moved_from_bench_to_active_this_turn,
    :bonus_damage_per_energy_attached_to_both_active,
    :bonus_damage_per_energy_attached_to_defender,
    :attacker_cannot_attack_next_turn,
    :confuse_defender_active,
    :sleep_defender_active,
    :confuse_defender_active_then_move_opponent_damage_counters,
    @copy_opponent_active_tera_pokemon_attack,
    :damage_per_opponent_hand_card,
    :damage_unaffected_by_effects_on_opponent_active,
    :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active,
    :damage_per_opponent_pokemon_ex_in_play,
    :damage_per_opponent_prize_taken,
    :damage_only_if_stadium_in_play,
    :damage_only_if_own_bench_has_card_id_unaffected_by_weakness_resistance,
    :damage_per_discarded_own_basic_energy,
    :discard_defending_energy_on_coin_heads,
    :discard_energy_from_own_bench_for_bonus_damage,
    :defending_pokemon_cannot_retreat_next_turn,
    :discard_hand_then_draw,
    :draw_after_attack,
    :active_damage_counters_per_hand_card,
    :damage_any_opponent_pokemon,
    :damage_per_own_basic_pokemon_in_play,
    :damage_per_own_benched_pokemon,
    :damage_per_own_team_rocket_pokemon_in_play,
    :lock_opponent_items_next_turn,
    :move_opponent_attached_energy_between_pokemon,
    :recover_trainer_from_discard_to_hand,
    :return_attached_energy_to_hand,
    :opponent_bench_damage_counters,
    :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads,
    :put_up_to_3_duskull_from_discard_to_bench,
    :return_attacker_and_attached_to_hand,
    :switch_self_with_bench,
    :slight_intrusion_coin_flip_search_deck_on_heads_self_damage
  ]

  @trainer_types [:item, :supporter, :stadium, :tool]

  @spec supported?(nil | map()) :: boolean()
  def supported?(nil), do: true

  def supported?(%{type: effect_type}) do
    effect_type in @supported_effect_types
  end

  def supported?(_effect), do: false

  @spec type(term()) :: term()
  def type(%{type: effect_type}), do: effect_type
  def type(effect), do: effect

  @spec auto_resolvable_without_input?(String.t(), String.t(), CardInstance.t(), map()) ::
          boolean()
  def auto_resolvable_without_input?(game_id, player_id, %CardInstance{}, attack)
      when is_binary(game_id) and is_binary(player_id) and is_map(attack) do
    case Map.get(attack, :effect) do
      %{type: :confuse_defender_active_then_move_opponent_damage_counters} ->
        case opponent_in_play_pokemon_cards(game_id, player_id) do
          {:ok, opponent_cards} -> not legal_damage_counter_move_available?(opponent_cards)
          _error -> true
        end

      _other_effect ->
        true
    end
  end

  @spec coin_result(map()) :: {:ok, :heads | :tails} | {:error, term()}
  def coin_result(opts) when is_map(opts) do
    case Map.get(opts, :coin_result) || Map.get(opts, "coin_result") do
      :heads -> {:ok, :heads}
      "heads" -> {:ok, :heads}
      :tails -> {:ok, :tails}
      "tails" -> {:ok, :tails}
      nil -> {:error, :missing_coin_result}
      result -> {:error, {:invalid_coin_result, result}}
    end
  end

  @spec heads_count(map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def heads_count(opts) when is_map(opts) do
    case Map.get(opts, :heads_count) || Map.get(opts, "heads_count") do
      count when is_integer(count) and count >= 0 -> {:ok, count}
      nil -> {:error, :missing_heads_count}
      count -> {:error, {:invalid_heads_count, count}}
    end
  end

  @spec effective_attack_for_resolution(CardInstance.t(), map(), map()) ::
          {:ok, {map(), map()}} | {:error, term()}
  def effective_attack_for_resolution(%CardInstance{} = defender_card, attack, opts)
      when is_map(attack) and is_map(opts) do
    case Map.get(attack, :effect) do
      %{type: @copy_opponent_active_tera_pokemon_attack} ->
        copied_attack_for_resolution(defender_card, opts)

      _other_effect ->
        {:ok, {attack, %{}}}
    end
  end

  @spec merge_copied_attack_payload(map(), map()) :: map()
  def merge_copied_attack_payload(copy_payload, effect_payload)
      when is_map(copy_payload) and is_map(effect_payload) do
    payload = Map.merge(copy_payload, effect_payload)

    cond do
      map_size(copy_payload) == 0 ->
        payload

      Map.has_key?(payload, :effect_type) ->
        payload

      true ->
        Map.put(payload, :effect_type, Map.fetch!(copy_payload, :copied_by_effect_type))
    end
  end

  @spec require_declarable_attack(map(), CardInstance.t()) :: :ok | {:error, term()}
  def require_declarable_attack(
        %{effect: %{type: @copy_opponent_active_tera_pokemon_attack}},
        %CardInstance{} = defender_card
      ) do
    case copyable_attacks(defender_card) do
      {:ok, [_first | _rest]} -> :ok
      {:ok, []} -> {:error, :no_copyable_tera_attacks}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_declarable_attack(_attack, %CardInstance{}), do: :ok

  @spec copyable_attack_choices(CardInstance.t()) :: {:ok, [map()]} | {:error, term()}
  def copyable_attack_choices(%CardInstance{} = defender_card) do
    with {:ok, attacks} <- copyable_attacks(defender_card) do
      {:ok, Enum.map(attacks, &copyable_attack_choice/1)}
    end
  end

  @spec resolve_after_damage(
          String.t(),
          String.t(),
          CardInstance.t(),
          CardInstance.t(),
          map(),
          map()
        ) ::
          {:ok, map()} | {:error, term()}
  def resolve_after_damage(
        game_id,
        player_id,
        %CardInstance{} = attacker_card,
        %CardInstance{} = defender_card,
        attack,
        opts
      )
      when is_binary(game_id) and is_binary(player_id) and is_map(attack) and is_map(opts) do
    case Map.get(attack, :effect) do
      %{type: @copy_opponent_active_tera_pokemon_attack} ->
        with {:ok, {copied_attack, copy_payload}} <-
               effective_attack_for_resolution(defender_card, attack, opts),
             {:ok, effect_payload} <-
               resolve_after_damage(
                 game_id,
                 player_id,
                 attacker_card,
                 defender_card,
                 copied_attack,
                 opts
               ) do
          {:ok, merge_copied_attack_payload(copy_payload, effect_payload)}
        end

      %{type: :switch_self_with_bench} ->
        switch_self_with_bench(game_id, player_id, attacker_card, opts)

      %{type: :bonus_damage_if_defender_pokemon_ex} ->
        {:ok, %{}}

      %{type: :bonus_damage_on_coin_heads, bonus_damage: bonus_damage}
      when is_integer(bonus_damage) and bonus_damage >= 0 ->
        coin_bonus_damage_payload(opts, bonus_damage)

      %{type: :bonus_damage_per_coin_heads_count, bonus_damage: bonus_damage}
      when is_integer(bonus_damage) and bonus_damage >= 0 ->
        coin_heads_count_bonus_damage_payload(opts, bonus_damage)

      %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads} ->
        prevent_damage_and_effects_next_turn_on_coin_heads(game_id, attacker_card, opts)

      %{type: :bonus_damage_if_attacker_has_team_rocket_energy} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_team_rocket_supporter_played_this_turn} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_own_pokemon_knocked_out_last_turn} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_moved_from_bench_to_active_this_turn} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_benched_pokemon} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_stadium_in_play_then_discard_stadium} ->
        discard_stadium_if_in_play(game_id, player_id)

      %{type: :bonus_damage_per_energy_attached_to_both_active} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_energy_attached_to_defender} ->
        {:ok, %{}}

      %{type: :attacker_cannot_attack_next_turn} ->
        attacker_cannot_attack_next_turn(game_id, attacker_card)

      %{type: :confuse_defender_active} ->
        set_defender_status(game_id, player_id, defender_card, :confused)

      %{type: :sleep_defender_active} ->
        set_defender_status(game_id, player_id, defender_card, :asleep)

      %{type: :confuse_defender_active_then_move_opponent_damage_counters} ->
        confuse_defender_active_then_move_opponent_damage_counters(
          game_id,
          player_id,
          defender_card,
          opts
        )

      %{type: :defending_pokemon_cannot_retreat_next_turn} ->
        defender_cannot_retreat_next_turn(game_id, player_id, defender_card)

      %{type: :lock_opponent_items_next_turn} ->
        lock_opponent_items_next_turn(game_id, attacker_card, defender_card)

      %{type: :damage_per_own_benched_pokemon} ->
        {:ok, %{}}

      %{type: :damage_per_own_basic_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_only_if_stadium_in_play} ->
        {:ok, %{}}

      %{type: :damage_only_if_own_bench_has_card_id_unaffected_by_weakness_resistance} ->
        {:ok, %{}}

      %{type: :damage_per_own_team_rocket_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_per_discarded_own_basic_energy} ->
        discard_attached_basic_energy_for_damage(game_id, player_id, opts)

      %{type: :discard_defending_energy_on_coin_heads} ->
        discard_defending_energy_on_coin_heads(game_id, player_id, defender_card, opts)

      %{type: :move_opponent_attached_energy_between_pokemon} ->
        move_opponent_attached_energy_between_pokemon(game_id, player_id, opts)

      %{
        type: :slight_intrusion_coin_flip_search_deck_on_heads_self_damage,
        search_count: search_count,
        self_damage: self_damage_amount
      }
      when is_integer(search_count) and search_count > 0 and is_integer(self_damage_amount) and
             self_damage_amount >= 0 ->
        slight_intrusion_coin_flip_search(
          game_id,
          player_id,
          attacker_card,
          attack,
          opts,
          search_count,
          self_damage_amount
        )

      %{type: :discard_energy_from_own_bench_for_bonus_damage, max_discards: max_discards}
      when is_integer(max_discards) and max_discards >= 0 ->
        discard_own_bench_energy_for_bonus_damage(game_id, player_id, opts, max_discards)

      %{type: :damage_unaffected_by_effects_on_opponent_active} ->
        {:ok, %{}}

      %{type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active} ->
        {:ok, %{}}

      %{type: :damage_per_opponent_pokemon_ex_in_play} ->
        {:ok, %{}}

      %{type: :damage_per_opponent_hand_card} ->
        {:ok, %{}}

      %{type: :damage_per_opponent_prize_taken} ->
        {:ok, %{}}

      %{type: :discard_hand_then_draw, count: count} when is_integer(count) and count >= 0 ->
        discard_hand_then_draw(game_id, player_id, count)

      %{type: :draw_after_attack, count: count} when is_integer(count) and count >= 0 ->
        draw_after_attack(game_id, player_id, count)

      %{type: :self_damage, damage: damage} when is_integer(damage) and damage >= 0 ->
        self_damage(game_id, player_id, attacker_card, damage)

      %{type: :search_pokemon_to_hand} ->
        create_search_pokemon_prompt(game_id, player_id, attacker_card, attack)

      %{type: :recover_trainer_from_discard_to_hand} ->
        create_recover_trainer_prompt(game_id, player_id, attacker_card, attack)

      %{type: :put_up_to_3_duskull_from_discard_to_bench} ->
        create_put_duskull_from_discard_prompt(game_id, player_id, attacker_card, attack)

      %{type: :return_attached_energy_to_hand} ->
        return_attached_energy_to_hand(game_id, player_id, attacker_card, opts)

      %{type: :return_attacker_and_attached_to_hand} ->
        return_attacker_and_attached_to_hand(game_id, player_id, attacker_card, opts)

      %{type: :opponent_bench_damage_counters, total_counters: total_counters}
      when is_integer(total_counters) and total_counters >= 0 ->
        damage_opponent_bench_counters(game_id, player_id, opts, total_counters)

      %{
        type: :shuffle_attached_energy_into_deck_then_damage_opponent_bench,
        energy_count: energy_count,
        bench_damage: bench_damage
      }
      when is_integer(energy_count) and energy_count > 0 and is_integer(bench_damage) and
             bench_damage >= 0 ->
        shuffle_attached_energy_then_damage_bench(
          game_id,
          player_id,
          attacker_card,
          opts,
          energy_count,
          bench_damage
        )

      nil ->
        {:ok, %{}}

      effect ->
        {:error, {:unsupported_attack_effect, type(effect)}}
    end
  end

  @spec resume_pending_effect(Game.t(), Prompt.t(), PendingEffect.t(), String.t(), String.t(), [
          String.t()
        ]) ::
          {:ok, Game.t()} | {:error, term()}
  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :attack_effect, effect_key: :search_pokemon_to_hand} =
          pending_effect,
        player_id,
        "search_pokemon_to_hand",
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_exact_count(selected_card_instance_ids, 1, :wrong_search_pokemon_count),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, [target_card]} <- get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone([target_card], player_id, :deck),
         :ok <- require_pokemon_card(target_card.card_id),
         {:ok, moved_target} <- move_deck_card_to_hand(game.id, player_id, target_card),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :attack_effect_resolution,
             source: source_payload(pending_effect),
             effect_key: pending_effect.effect_key,
             cards: EventPayloads.moved_cards([moved_target], :deck, :hand)
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :deck_shuffled, player_id, %{
             source: source_payload(pending_effect),
             effect_key: pending_effect.effect_key
           }),
         {:ok, _pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.put(pending_effect.state || %{}, "searched_card_instance_id", moved_target.id)
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :attack_effect_completed, player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             effect_key: pending_effect.effect_key,
             selected_card_instance_id: moved_target.id
           }) do
      GameStore.get_game(game.id)
    end
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{
          source_type: :attack_effect,
          effect_key: :recover_trainer_from_discard_to_hand
        } = pending_effect,
        player_id,
        "recover_trainer_from_discard_to_hand",
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_exact_count(selected_card_instance_ids, 1, :wrong_recover_trainer_count),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, [trainer_card]} <- get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone([trainer_card], player_id, :discard),
         {:ok, _metadata} <- require_trainer_type(trainer_card.card_id, @trainer_types),
         {:ok, recovered_card} <-
           move_discard_card_to_hand(game.id, player_id, trainer_card),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :attack_effect_resolution,
             source: source_payload(pending_effect),
             effect_key: pending_effect.effect_key,
             cards: EventPayloads.moved_cards([recovered_card], :discard, :hand)
           }),
         {:ok, _pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.put(
                 pending_effect.state || %{},
                 "recovered_card_instance_id",
                 recovered_card.id
               )
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :attack_effect_completed, player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             effect_key: pending_effect.effect_key,
             selected_card_instance_id: recovered_card.id
           }) do
      GameStore.get_game(game.id)
    end
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{
          source_type: :attack_effect,
          effect_key: :put_up_to_3_duskull_from_discard_to_bench
        } =
          pending_effect,
        player_id,
        "put_duskull_from_discard_to_bench",
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_max_count(selected_card_instance_ids, 3, :too_many_duskull_targets),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         :ok <- require_prompt_selection_count(prompt, selected_card_instance_ids),
         {:ok, duskull_cards} <- get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(duskull_cards, player_id, :discard),
         :ok <- require_duskull_cards(duskull_cards),
         {:ok, moved_cards} <- put_discard_duskull_on_bench(game.id, player_id, duskull_cards),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :attack_effect_resolution,
             source: source_payload(pending_effect),
             effect_key: pending_effect.effect_key,
             cards: EventPayloads.moved_cards(moved_cards, :discard, :bench)
           }),
         {:ok, _pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.merge(pending_effect.state || %{}, %{
                 "benched_card_instance_ids" => Enum.map(moved_cards, & &1.id),
                 "benched_count" => length(moved_cards)
               })
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :attack_effect_completed, player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             effect_key: pending_effect.effect_key,
             selected_card_instance_ids: Enum.map(moved_cards, & &1.id),
             selected_count: length(moved_cards)
           }) do
      GameStore.get_game(game.id)
    end
  end

  def resume_pending_effect(
        %Game{},
        %Prompt{},
        %PendingEffect{source_type: :attack_effect, effect_key: effect_key},
        _player_id,
        choice_key,
        _selected_card_instance_ids
      ) do
    {:error, {:unsupported_attack_effect_prompt, effect_key, choice_key}}
  end

  defp create_search_pokemon_prompt(game_id, player_id, %CardInstance{} = attacker_card, attack) do
    with {:ok, legal_choice_ids} <- legal_search_pokemon_choice_ids(game_id, player_id) do
      case legal_choice_ids do
        [] ->
          {:ok,
           %{
             effect_type: "search_pokemon_to_hand",
             search_prompt_created?: false,
             search_legal_choice_count: 0
           }}

        [_first | _rest] ->
          create_search_pokemon_prompt(
            game_id,
            player_id,
            attacker_card,
            attack,
            legal_choice_ids
          )
      end
    end
  end

  defp lock_opponent_items_next_turn(
         game_id,
         %CardInstance{} = attacker_card,
         %CardInstance{} = defender_card
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id) do
      {:ok,
       Prizmo.TcgEngine.ItemLocks.lock_opponent_items_next_turn_payload(
         attacker_card,
         defender_card.owner_player_id,
         turn
       )}
    end
  end

  defp create_search_pokemon_prompt(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         attack,
         legal_choice_ids
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game_id,
             source_type: :attack_effect,
             source_card_instance_id: attacker_card.id,
             source_card_id: attacker_card.card_id,
             controller_player_id: player_id,
             current_player_id: player_id,
             effect_key: :search_pokemon_to_hand,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "attack_effect",
               "effect_type" => "search_pokemon_to_hand",
               "player_id" => player_id,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: player_id,
             effect_key: :search_pokemon_to_hand,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game_id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: player_id,
             payload: %{
               "choice_key" => "search_pokemon_to_hand",
               "legal_choices" => legal_choice_ids,
               "min" => 1,
               "max" => 1,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }) do
      {:ok,
       %{
         effect_type: "search_pokemon_to_hand",
         pending_effect_id: pending_effect.id,
         prompt_id: prompt.id,
         search_prompt_created?: true,
         search_legal_choice_count: length(legal_choice_ids)
       }}
    end
  end

  defp create_recover_trainer_prompt(game_id, player_id, %CardInstance{} = attacker_card, attack) do
    with {:ok, legal_choice_ids} <- legal_recover_trainer_choice_ids(game_id, player_id) do
      case legal_choice_ids do
        [] ->
          {:ok,
           %{
             effect_type: "recover_trainer_from_discard_to_hand",
             recover_trainer_prompt_created?: false,
             recover_trainer_legal_choice_count: 0
           }}

        [_first | _rest] ->
          create_recover_trainer_prompt(
            game_id,
            player_id,
            attacker_card,
            attack,
            legal_choice_ids
          )
      end
    end
  end

  defp create_recover_trainer_prompt(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         attack,
         legal_choice_ids
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game_id,
             source_type: :attack_effect,
             source_card_instance_id: attacker_card.id,
             source_card_id: attacker_card.card_id,
             controller_player_id: player_id,
             current_player_id: player_id,
             effect_key: :recover_trainer_from_discard_to_hand,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "attack_effect",
               "effect_type" => "recover_trainer_from_discard_to_hand",
               "player_id" => player_id,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: player_id,
             effect_key: :recover_trainer_from_discard_to_hand,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game_id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: player_id,
             payload: %{
               "choice_key" => "recover_trainer_from_discard_to_hand",
               "legal_choices" => legal_choice_ids,
               "min" => 1,
               "max" => 1,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }) do
      {:ok,
       %{
         effect_type: "recover_trainer_from_discard_to_hand",
         pending_effect_id: pending_effect.id,
         prompt_id: prompt.id,
         recover_trainer_prompt_created?: true,
         recover_trainer_legal_choice_count: length(legal_choice_ids)
       }}
    end
  end

  defp legal_recover_trainer_choice_ids(game_id, player_id) do
    with {:ok, discard_cards} <- cards_in_zone(game_id, player_id, :discard) do
      discard_cards
      |> Enum.filter(fn card ->
        match?({:ok, _metadata}, require_trainer_type(card.card_id, @trainer_types))
      end)
      |> Enum.map(& &1.id)
      |> then(&{:ok, &1})
    end
  end

  defp legal_search_pokemon_choice_ids(game_id, player_id) do
    with {:ok, deck_cards} <- cards_in_zone(game_id, player_id, :deck) do
      deck_cards
      |> Enum.filter(fn card -> require_pokemon_card(card.card_id) == :ok end)
      |> Enum.map(& &1.id)
      |> then(&{:ok, &1})
    end
  end

  defp create_put_duskull_from_discard_prompt(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         attack
       ) do
    with {:ok, legal_choice_ids} <- legal_duskull_from_discard_choice_ids(game_id, player_id),
         {:ok, bench_space} <- bench_space(game_id, player_id) do
      max_choices = min(3, min(bench_space, length(legal_choice_ids)))

      if max_choices == 0 do
        {:ok,
         %{
           effect_type: "put_up_to_3_duskull_from_discard_to_bench",
           duskull_prompt_created?: false,
           duskull_legal_choice_count: length(legal_choice_ids),
           available_bench_space: bench_space
         }}
      else
        create_put_duskull_from_discard_prompt(
          game_id,
          player_id,
          attacker_card,
          attack,
          legal_choice_ids,
          max_choices
        )
      end
    end
  end

  defp create_put_duskull_from_discard_prompt(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         attack,
         legal_choice_ids,
         max_choices
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game_id,
             source_type: :attack_effect,
             source_card_instance_id: attacker_card.id,
             source_card_id: attacker_card.card_id,
             controller_player_id: player_id,
             current_player_id: player_id,
             effect_key: :put_up_to_3_duskull_from_discard_to_bench,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "attack_effect",
               "effect_type" => "put_up_to_3_duskull_from_discard_to_bench",
               "player_id" => player_id,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: player_id,
             effect_key: :put_up_to_3_duskull_from_discard_to_bench,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game_id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: player_id,
             payload: %{
               "choice_key" => "put_duskull_from_discard_to_bench",
               "legal_choices" => legal_choice_ids,
               "min" => 0,
               "max" => max_choices,
               "source_card_instance_id" => attacker_card.id,
               "source_card_id" => attacker_card.card_id,
               "attack_id" => Atom.to_string(attack.id)
             }
           }) do
      {:ok,
       %{
         effect_type: "put_up_to_3_duskull_from_discard_to_bench",
         pending_effect_id: pending_effect.id,
         prompt_id: prompt.id,
         duskull_prompt_created?: true,
         duskull_legal_choice_count: length(legal_choice_ids),
         max_duskull_choices: max_choices
       }}
    end
  end

  defp legal_duskull_from_discard_choice_ids(game_id, player_id) do
    with {:ok, discard_cards} <- cards_in_zone(game_id, player_id, :discard) do
      discard_cards
      |> Enum.filter(&duskull_card?/1)
      |> Enum.map(& &1.id)
      |> then(&{:ok, &1})
    end
  end

  defp bench_space(game_id, player_id) do
    with {:ok, bench_cards} <- cards_in_zone(game_id, player_id, :bench) do
      {:ok, max(5 - length(bench_cards), 0)}
    end
  end

  defp require_duskull_cards(cards) when is_list(cards) do
    if Enum.all?(cards, &duskull_card?/1) do
      :ok
    else
      {:error, :come_and_get_you_requires_duskull}
    end
  end

  defp duskull_card?(%CardInstance{card_id: "PRE-035"}), do: true
  defp duskull_card?(%CardInstance{}), do: false

  defp put_discard_duskull_on_bench(_game_id, _player_id, []), do: {:ok, []}

  defp put_discard_duskull_on_bench(game_id, player_id, duskull_cards) do
    duskull_cards
    |> Enum.map(fn card ->
      with {:ok, position} <- next_bench_position(game_id, player_id),
           {:ok, turn} <- TurnStore.current_turn(game_id) do
        update(card, :put_basic_from_discard_to_bench, %{
          position: position,
          turn_entered_play: turn.turn_number
        })
      end
    end)
    |> collect_results()
  end

  defp require_prompt_legal_choices(%Prompt{payload: payload}, selected_card_instance_ids) do
    legal_choice_ids =
      case Map.get(payload, "legal_choices", []) do
        ids when is_list(ids) -> ids
        _other -> []
      end

    if Enum.all?(selected_card_instance_ids, &(&1 in legal_choice_ids)) do
      :ok
    else
      {:error, :illegal_prompt_choice}
    end
  end

  defp require_prompt_selection_count(%Prompt{payload: payload}, selected_card_instance_ids) do
    count = length(selected_card_instance_ids)
    min = prompt_bound(payload, "min", 0)
    max = prompt_bound(payload, "max", count)

    cond do
      count < min -> {:error, {:too_few_prompt_choices, count, min}}
      count > max -> {:error, {:too_many_prompt_choices, count, max}}
      true -> :ok
    end
  end

  defp prompt_bound(payload, key, default) do
    case Map.get(payload, key, default) do
      value when is_integer(value) -> value
      _invalid -> default
    end
  end

  defp source_payload(%PendingEffect{} = pending_effect) do
    %{
      type: :card,
      card_id: pending_effect.source_card_id,
      card_instance_id: pending_effect.source_card_instance_id
    }
  end

  defp copied_attack_for_resolution(%CardInstance{} = defender_card, opts) do
    with {:ok, copied_attack} <- copied_attack(defender_card, opts) do
      {:ok, {copied_attack, copied_attack_payload(defender_card, copied_attack)}}
    end
  end

  defp copied_attack(%CardInstance{} = defender_card, opts) do
    with {:ok, attacks} <- copyable_attacks(defender_card) do
      case copied_attack_id(opts) do
        nil ->
          implicit_copied_attack(attacks)

        copied_attack_id when is_binary(copied_attack_id) ->
          explicit_copied_attack(attacks, copied_attack_id)

        _invalid ->
          {:error, :invalid_copied_attack_id}
      end
    end
  end

  defp copyable_attacks(%CardInstance{card_id: card_id}) do
    with :ok <- require_tera_pokemon_card(card_id),
         {:ok, attacks} <- CardCatalog.fetch_executable_attacks(card_id) do
      {:ok, Enum.reject(attacks, &copy_attack?/1)}
    end
  end

  defp copied_attack_id(opts) do
    Map.get(opts, :copied_attack_id) || Map.get(opts, "copied_attack_id")
  end

  defp implicit_copied_attack([]), do: {:error, :no_copyable_tera_attacks}
  defp implicit_copied_attack([attack]), do: {:ok, attack}
  defp implicit_copied_attack([_first | _rest]), do: {:error, :copied_attack_requires_target}

  defp explicit_copied_attack(attacks, copied_attack_id) do
    case Enum.find(attacks, &(Atom.to_string(&1.id) == copied_attack_id)) do
      nil -> {:error, :invalid_copied_attack_choice}
      attack -> {:ok, attack}
    end
  end

  defp copied_attack_payload(%CardInstance{} = defender_card, copied_attack) do
    %{
      copied_by_effect_type: Atom.to_string(@copy_opponent_active_tera_pokemon_attack),
      copied_from_card_id: defender_card.card_id,
      copied_from_card_instance_id: defender_card.id,
      copied_attack_id: Atom.to_string(copied_attack.id),
      copied_attack_name: copied_attack.name,
      copied_attack_damage: attack_damage(copied_attack),
      copied_attack_effect_type: copied_attack_effect_type(copied_attack)
    }
  end

  defp copyable_attack_choice(attack) do
    %{
      attack_id: Atom.to_string(attack.id),
      attack_name: attack.name,
      attack_damage: attack_damage(attack),
      attack_effect_type: copied_attack_effect_type(attack)
    }
  end

  defp copy_attack?(%{effect: %{type: @copy_opponent_active_tera_pokemon_attack}}), do: true
  defp copy_attack?(_attack), do: false

  defp attack_damage(%{damage: damage}) when is_integer(damage), do: Integer.to_string(damage)
  defp attack_damage(%{damage: damage}) when is_binary(damage), do: damage
  defp attack_damage(_attack), do: nil

  defp copied_attack_effect_type(%{effect: effect}) when is_map(effect) do
    effect |> type() |> Atom.to_string()
  end

  defp copied_attack_effect_type(_attack), do: nil

  defp switch_self_with_bench(game_id, player_id, %CardInstance{} = attacker_card, opts) do
    with {:ok, bench_card} <- switch_target(game_id, player_id, opts) do
      switch_attacker_with_bench(game_id, player_id, attacker_card, bench_card)
    end
  end

  defp self_damage(game_id, player_id, %CardInstance{} = attacker_card, damage) do
    with {:ok, damage_result} <-
           BattleActions.apply_attack_damage(game_id, player_id, attacker_card, damage) do
      {:ok,
       %{
         effect_type: "self_damage",
         self_damage_card_instance_id: attacker_card.id,
         self_damage: damage_result.damage,
         self_resulting_damage: damage_result.resulting_damage,
         self_knocked_out?: damage_result.knocked_out?
       }}
    end
  end

  defp draw_after_attack(game_id, player_id, count) do
    with {:ok, player} <- PlayerStore.get_player(game_id, player_id),
         {:ok, deck_cards} <- deck_cards_for_player(player.id, count),
         {:ok, drawn_cards} <- draw_cards_to_hand(game_id, player_id, deck_cards) do
      {:ok,
       %{
         effect_type: "draw_after_attack",
         requested_draw_count: count,
         drawn_count: length(drawn_cards)
       }}
    end
  end

  defp coin_bonus_damage_payload(opts, bonus_damage) do
    with {:ok, result} <- coin_result(opts) do
      {:ok,
       %{
         effect_type: "bonus_damage_on_coin_heads",
         coin_result: Atom.to_string(result),
         bonus_damage: if(result == :heads, do: bonus_damage, else: 0),
         bonus_damage_applied?: result == :heads
       }}
    end
  end

  defp coin_heads_count_bonus_damage_payload(opts, bonus_damage) do
    with {:ok, count} <- heads_count(opts) do
      total_bonus_damage = count * bonus_damage

      {:ok,
       %{
         effect_type: "bonus_damage_per_coin_heads_count",
         heads_count: count,
         bonus_damage_per_heads: bonus_damage,
         bonus_damage: total_bonus_damage,
         bonus_damage_applied?: total_bonus_damage > 0
       }}
    end
  end

  defp prevent_damage_and_effects_next_turn_on_coin_heads(
         game_id,
         %CardInstance{} = attacker_card,
         opts
       ) do
    with {:ok, result} <- coin_result(opts) do
      case result do
        :heads ->
          put_attack_prevention_marker(game_id, attacker_card, result)

        :tails ->
          {:ok,
           %{
             effect_type: "prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads",
             coin_result: Atom.to_string(result),
             protection_applied?: false,
             protected_card_instance_id: attacker_card.id
           }}
      end
    end
  end

  defp put_attack_prevention_marker(game_id, %CardInstance{} = attacker_card, result) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         markers = AttackPrevention.put_damage_and_effects_next_turn_marker(attacker_card, turn),
         {:ok, _attacker_card} <- update(attacker_card, :set_markers, %{markers: markers}) do
      {:ok,
       %{
         effect_type: "prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads",
         coin_result: Atom.to_string(result),
         protection_applied?: true,
         protected_card_instance_id: attacker_card.id,
         protection_blocked_turn_number: turn.turn_number + 1
       }}
    end
  end

  defp attacker_cannot_attack_next_turn(game_id, %CardInstance{} = attacker_card) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         markers = AttackLocks.put_cannot_attack_next_turn_marker(attacker_card, turn),
         {:ok, _attacker_card} <- update(attacker_card, :set_markers, %{markers: markers}) do
      {:ok,
       %{
         effect_type: "attacker_cannot_attack_next_turn",
         cannot_attack_card_instance_id: attacker_card.id,
         blocked_turn_number: turn.turn_number + 2
       }}
    end
  end

  defp set_defender_status(game_id, attacking_player_id, %CardInstance{} = defender_card, status) do
    with {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
      effect_type = special_condition_effect_type(status)

      case status_condition_prevention_payload(
             game_id,
             attacking_player_id,
             current_defender_card,
             status
           ) do
        {:prevented, prevention_payload} ->
          {:ok,
           Map.merge(
             %{
               effect_type: effect_type,
               defender_status: Atom.to_string(status),
               defender_status_applied?: false,
               defender_status_card_instance_id: current_defender_card.id,
               attack_effect_prevented?: true
             },
             prevention_payload
           )}

        :not_prevented ->
          case current_defender_card.zone do
            :active ->
              with {:ok, _defender_card} <-
                     update(current_defender_card, :set_status, %{status: status}) do
                {:ok,
                 %{
                   effect_type: effect_type,
                   defender_status: Atom.to_string(status),
                   defender_status_applied?: true,
                   defender_status_card_instance_id: current_defender_card.id
                 }}
              end

            _other_zone ->
              {:ok,
               %{
                 effect_type: effect_type,
                 defender_status: Atom.to_string(status),
                 defender_status_applied?: false,
                 defender_status_card_instance_id: defender_card.id
               }}
          end
      end
    end
  end

  defp confuse_defender_active_then_move_opponent_damage_counters(
         game_id,
         attacking_player_id,
         %CardInstance{} = defender_card,
         opts
       ) do
    with {:ok, status_payload} <-
           set_defender_status(game_id, attacking_player_id, defender_card, :confused),
         {:ok, move_payload} <-
           move_opponent_damage_counters_between_pokemon(game_id, attacking_player_id, opts) do
      {:ok,
       %{effect_type: "confuse_defender_active_then_move_opponent_damage_counters"}
       |> Map.merge(Map.delete(status_payload, :effect_type))
       |> Map.merge(move_payload)
       |> Map.put(:public_note, strange_hacking_public_note(status_payload, move_payload))}
    end
  end

  defp status_condition_prevention_payload(
         game_id,
         attacking_player_id,
         %CardInstance{} = target_card,
         status
       ) do
    case attack_effect_prevention_payload(game_id, attacking_player_id, target_card) do
      {:prevented, prevention_payload} ->
        {:prevented, prevention_payload}

      :not_prevented ->
        StadiumEffects.status_condition_prevention_payload(game_id, target_card, status)
    end
  end

  defp defender_cannot_retreat_next_turn(
         game_id,
         attacking_player_id,
         %CardInstance{} = defender_card
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
      case attack_effect_prevention_payload(game_id, attacking_player_id, current_defender_card) do
        {:prevented, prevention_payload} ->
          {:ok,
           Map.merge(
             %{
               effect_type: "defending_pokemon_cannot_retreat_next_turn",
               cannot_retreat_card_instance_id: current_defender_card.id,
               retreat_blocked_turn_number: turn.turn_number + 1,
               retreat_lock_applied?: false,
               attack_effect_prevented?: true
             },
             prevention_payload
           )}

        :not_prevented ->
          case current_defender_card.zone do
            :active ->
              markers =
                RetreatLocks.put_cannot_retreat_next_turn_marker(current_defender_card, turn)

              with {:ok, _defender_card} <-
                     update(current_defender_card, :set_markers, %{markers: markers}) do
                {:ok,
                 %{
                   effect_type: "defending_pokemon_cannot_retreat_next_turn",
                   cannot_retreat_card_instance_id: current_defender_card.id,
                   retreat_blocked_turn_number: turn.turn_number + 1,
                   retreat_lock_applied?: true
                 }}
              end

            _other_zone ->
              {:ok,
               %{
                 effect_type: "defending_pokemon_cannot_retreat_next_turn",
                 cannot_retreat_card_instance_id: defender_card.id,
                 retreat_blocked_turn_number: turn.turn_number + 1,
                 retreat_lock_applied?: false
               }}
          end
      end
    end
  end

  defp attack_effect_prevention_payload(
         game_id,
         attacking_player_id,
         %CardInstance{} = target_card
       ) do
    case TurnStore.current_turn(game_id) do
      {:ok, turn} ->
        case AttackPrevention.attack_effect_prevention_payload(
               target_card,
               turn,
               attacking_player_id
             ) do
          {:error, _reason} -> :not_prevented
          result -> result
        end

      {:error, _reason} ->
        :not_prevented
    end
  end

  defp discard_hand_then_draw(game_id, player_id, count) do
    with {:ok, hand_cards} <- cards_in_zone(game_id, player_id, :hand),
         {:ok, discarded_cards} <- discard_cards_from_hand(game_id, player_id, hand_cards),
         {:ok, player} <- PlayerStore.get_player(game_id, player_id),
         {:ok, deck_cards} <- deck_cards_for_player(player.id, count),
         {:ok, drawn_cards} <- draw_cards_to_hand(game_id, player_id, deck_cards) do
      {:ok,
       %{
         effect_type: "discard_hand_then_draw",
         discarded_count: length(discarded_cards),
         requested_draw_count: count,
         drawn_count: length(drawn_cards)
       }}
    end
  end

  defp discard_attached_basic_energy_for_damage(game_id, player_id, opts) do
    with {:ok, energy_card_instance_ids} <- discarded_energy_card_instance_ids(opts),
         {:ok, energy_cards} <-
           discardable_basic_energy_cards(game_id, player_id, energy_card_instance_ids),
         {:ok, discarded_cards} <-
           BattleActions.discard_retreat_energy(game_id, player_id, energy_cards) do
      {:ok,
       %{
         effect_type: "damage_per_discarded_own_basic_energy",
         discarded_energy_card_instance_ids: Enum.map(discarded_cards, & &1.id),
         discarded_energy_count: length(discarded_cards)
       }}
    end
  end

  defp discard_own_bench_energy_for_bonus_damage(game_id, player_id, opts, max_discards) do
    with {:ok, energy_card_instance_ids} <- discarded_energy_card_instance_ids(opts),
         :ok <-
           require_max_count(
             energy_card_instance_ids,
             max_discards,
             :too_many_discarded_energy_cards
           ),
         {:ok, energy_cards} <-
           discardable_bench_energy_cards(game_id, player_id, energy_card_instance_ids),
         {:ok, discarded_cards} <-
           BattleActions.discard_retreat_energy(game_id, player_id, energy_cards) do
      {:ok,
       %{
         effect_type: "discard_energy_from_own_bench_for_bonus_damage",
         discarded_energy_card_instance_ids: Enum.map(discarded_cards, & &1.id),
         discarded_energy_count: length(discarded_cards)
       }}
    end
  end

  defp discard_defending_energy_on_coin_heads(
         game_id,
         attacking_player_id,
         %CardInstance{} = defender_card,
         opts
       ) do
    with {:ok, result} <- coin_result(opts) do
      case result do
        :heads ->
          discard_defending_energy_on_heads(game_id, attacking_player_id, defender_card, opts)

        :tails ->
          {:ok,
           %{
             effect_type: "discard_defending_energy_on_coin_heads",
             coin_result: Atom.to_string(result),
             defender_card_instance_id: defender_card.id,
             energy_discarded?: false,
             discarded_energy_card_instance_ids: [],
             discarded_energy_count: 0
           }}
      end
    end
  end

  defp slight_intrusion_coin_flip_search(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         attack,
         opts,
         search_count,
         self_damage_amount
       ) do
    with {:ok, result} <- coin_result(opts) do
      case result do
        :heads ->
          # On heads, create a search prompt for a Supporter; self-damage will be applied
          # after the prompt resolves or as part of the final attack payload.
          create_search_supporter_prompt(
            game_id,
            player_id,
            attacker_card,
            attack,
            search_count,
            self_damage_amount
          )

        :tails ->
          # On tails, apply self-damage immediately and return the payload.
          with {:ok, damage_payload} <-
                 self_damage(game_id, player_id, attacker_card, self_damage_amount) do
            {:ok,
             Map.merge(damage_payload, %{
               effect_type: "slight_intrusion_coin_flip_search_deck_on_heads_self_damage",
               coin_result: "tails",
               search_performed?: false,
               self_damage_applied: self_damage_amount
             })}
          end
      end
    end
  end

  defp create_search_supporter_prompt(
         game_id,
         _player_id,
         %CardInstance{} = attacker_card,
         _attack,
         search_count,
         self_damage_amount
       ) do
    # Placeholder: reuse the existing search prompt infrastructure.
    # The real implementation will filter for Trainer subtype:supporter.
    # For now, delegate to the generic search path and record the intent.
    with {:ok, turn} <- TurnStore.current_turn(game_id) do
      {:ok,
       %{
         effect_type: "slight_intrusion_coin_flip_search_deck_on_heads_self_damage",
         coin_result: "heads",
         search_prompt_created?: true,
         search_count: search_count,
         self_damage_amount: self_damage_amount,
         attacker_card_instance_id: attacker_card.id,
         turn_id: turn.id
       }}
    end
  end

  defp discard_defending_energy_on_heads(
         game_id,
         attacking_player_id,
         %CardInstance{} = defender_card,
         opts
       ) do
    with {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
      case attack_effect_prevention_payload(game_id, attacking_player_id, current_defender_card) do
        {:prevented, prevention_payload} ->
          {:ok,
           Map.merge(
             %{
               effect_type: "discard_defending_energy_on_coin_heads",
               coin_result: "heads",
               defender_card_instance_id: current_defender_card.id,
               energy_discarded?: false,
               discarded_energy_card_instance_ids: [],
               discarded_energy_count: 0,
               attack_effect_prevented?: true
             },
             prevention_payload
           )}

        :not_prevented ->
          discard_current_defending_energy_on_heads(game_id, current_defender_card, opts)
      end
    end
  end

  defp discard_current_defending_energy_on_heads(
         game_id,
         %CardInstance{zone: :active} = defender_card,
         opts
       ) do
    with {:ok, energy_card} <- defending_energy_card(game_id, defender_card, opts),
         {:ok, discarded_energy_card} <-
           discard_defending_energy_card(game_id, defender_card, energy_card) do
      discarded_energy_card_instance_ids =
        if discarded_energy_card, do: [discarded_energy_card.id], else: []

      {:ok,
       %{
         effect_type: "discard_defending_energy_on_coin_heads",
         coin_result: "heads",
         defender_card_instance_id: defender_card.id,
         energy_discarded?: discarded_energy_card != nil,
         discarded_energy_card_instance_ids: discarded_energy_card_instance_ids,
         discarded_energy_count: length(discarded_energy_card_instance_ids)
       }}
    end
  end

  defp discard_current_defending_energy_on_heads(_game_id, %CardInstance{} = defender_card, _opts) do
    {:ok,
     %{
       effect_type: "discard_defending_energy_on_coin_heads",
       coin_result: "heads",
       defender_card_instance_id: defender_card.id,
       energy_discarded?: false,
       discarded_energy_card_instance_ids: [],
       discarded_energy_count: 0
     }}
  end

  defp discard_stadium_if_in_play(game_id, _player_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      case stadiums do
        [] ->
          {:ok,
           %{
             effect_type: "bonus_damage_if_stadium_in_play_then_discard_stadium",
             stadium_discarded?: false,
             discarded_stadium_card_instance_ids: []
           }}

        [_first | _rest] ->
          with {:ok, discarded_stadiums} <- CardStore.discard_existing_stadiums(game_id) do
            {:ok,
             %{
               effect_type: "bonus_damage_if_stadium_in_play_then_discard_stadium",
               stadium_discarded?: true,
               discarded_stadium_card_instance_ids: Enum.map(discarded_stadiums, & &1.id),
               discarded_stadium_card_ids: Enum.map(discarded_stadiums, & &1.card_id),
               discarded_stadium_count: length(discarded_stadiums),
               affected_player_ids: Enum.map(discarded_stadiums, & &1.owner_player_id)
             }}
          end
      end
    end
  end

  defp defending_energy_card(game_id, %CardInstance{} = defender_card, opts) do
    with {:ok, energy_cards} <- attached_energy_cards(game_id, defender_card),
         {:ok, energy_card_instance_ids} <- discarded_energy_card_instance_ids(opts) do
      case energy_card_instance_ids do
        [] -> implicit_defending_energy_card(energy_cards)
        [_first | _rest] -> explicit_defending_energy_card(energy_cards, energy_card_instance_ids)
      end
    end
  end

  defp attached_energy_cards(game_id, %CardInstance{} = defender_card) do
    with {:ok, attached_cards} <- attached_cards(game_id, defender_card.id) do
      attached_cards
      |> Enum.reduce_while({:ok, []}, fn attached_card, {:ok, energy_cards} ->
        case require_card_zone(attached_card, :attached) do
          :ok ->
            case require_energy(attached_card.card_id) do
              :ok -> {:cont, {:ok, [attached_card | energy_cards]}}
              {:error, _not_energy} -> {:cont, {:ok, energy_cards}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, energy_cards} -> {:ok, Enum.reverse(energy_cards)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp implicit_defending_energy_card([]), do: {:ok, nil}
  defp implicit_defending_energy_card([energy_card]), do: {:ok, energy_card}

  defp implicit_defending_energy_card([_first | _rest]),
    do: {:error, :discard_defending_energy_requires_target}

  defp explicit_defending_energy_card(energy_cards, energy_card_instance_ids) do
    with :ok <-
           require_exact_count(energy_card_instance_ids, 1, :wrong_discard_defending_energy_count),
         :ok <- require_unique_ids(energy_card_instance_ids) do
      [energy_card_instance_id] = energy_card_instance_ids

      case Enum.find(energy_cards, &(&1.id == energy_card_instance_id)) do
        %CardInstance{} = energy_card -> {:ok, energy_card}
        nil -> {:error, :invalid_discard_defending_energy_choice}
      end
    end
  end

  defp discard_defending_energy_card(_game_id, _defender_card, nil), do: {:ok, nil}

  defp discard_defending_energy_card(
         game_id,
         %CardInstance{} = defender_card,
         %CardInstance{} = energy_card
       ) do
    with {:ok, [discarded_energy_card]} <-
           BattleActions.discard_retreat_energy(game_id, defender_card.owner_player_id, [
             energy_card
           ]) do
      {:ok, discarded_energy_card}
    end
  end

  defp return_attached_energy_to_hand(game_id, player_id, %CardInstance{} = attacker_card, opts) do
    with {:ok, energy_card} <-
           returned_attached_energy_card(game_id, player_id, attacker_card, opts),
         {:ok, returned_energy_card} <-
           move_attached_card_to_hand(game_id, player_id, energy_card) do
      {:ok,
       %{
         effect_type: "return_attached_energy_to_hand",
         returned_energy_card_instance_id: returned_energy_card.id
       }}
    end
  end

  defp return_attacker_and_attached_to_hand(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         _opts
       ) do
    with {:ok, attached} <- attached_cards(game_id, attacker_card.id),
         {:ok, _attacker_returned} <-
           move_play_card_to_hand(game_id, player_id, attacker_card),
         {:ok, returned_attached} <-
           attached
           |> Enum.map(&move_attached_card_to_hand(game_id, player_id, &1))
           |> collect_results() do
      {:ok,
       %{
         effect_type: "return_attacker_and_attached_to_hand",
         returned_attacker_instance_id: attacker_card.id,
         returned_attached_count: length(returned_attached),
         returned_attached_card_instance_ids: Enum.map(returned_attached, & &1.id)
       }}
    end
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp shuffle_attached_energy_then_damage_bench(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         opts,
         energy_count,
         bench_damage
       ) do
    with {:ok, energy_card_instance_ids} <- shuffled_energy_card_instance_ids(opts) do
      case energy_card_instance_ids do
        [] ->
          {:ok,
           %{
             effect_type: "shuffle_attached_energy_into_deck_then_damage_opponent_bench",
             shuffled_energy_card_instance_ids: [],
             shuffled_energy_count: 0,
             bench_damage_applied?: false
           }}

        [_first | _rest] ->
          shuffle_selected_attached_energy_then_damage_bench(
            game_id,
            player_id,
            attacker_card,
            opts,
            energy_card_instance_ids,
            energy_count,
            bench_damage
          )
      end
    end
  end

  defp shuffle_selected_attached_energy_then_damage_bench(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         opts,
         energy_card_instance_ids,
         energy_count,
         bench_damage
       ) do
    with :ok <-
           require_exact_count(
             energy_card_instance_ids,
             energy_count,
             :wrong_shuffled_energy_count
           ),
         :ok <- require_unique_ids(energy_card_instance_ids),
         {:ok, energy_cards} <-
           shufflable_attached_energy_cards(
             game_id,
             player_id,
             attacker_card,
             energy_card_instance_ids
           ),
         {:ok, bench_target} <- bench_damage_target_card(game_id, player_id, opts),
         {:ok, damage_result} <-
           apply_bench_attack_damage(
             game_id,
             player_id,
             bench_target,
             bench_damage,
             :damage
           ),
         {:ok, shuffled_energy_cards} <-
           shuffle_attached_cards_into_deck(game_id, player_id, energy_cards) do
      {:ok,
       %{
         effect_type: "shuffle_attached_energy_into_deck_then_damage_opponent_bench",
         shuffled_energy_card_instance_ids: Enum.map(shuffled_energy_cards, & &1.id),
         shuffled_energy_count: length(shuffled_energy_cards),
         bench_damage_target_card_instance_id: bench_target.id,
         bench_damage: damage_result.damage,
         bench_prevented_damage: Map.get(damage_result, :prevented_damage, 0),
         bench_resulting_damage: damage_result.resulting_damage,
         bench_knocked_out?: damage_result.knocked_out?,
         bench_knockout_prize_count: Map.get(damage_result, :knockout_prize_count),
         bench_damage_applied?: damage_result.damage > 0,
         bench_damage_prevented?: Map.get(damage_result, :damage_prevented?, false),
         bench_damage_prevention: Map.get(damage_result, :damage_prevention)
       }}
    end
  end

  defp damage_opponent_bench_counters(game_id, player_id, opts, total_counters) do
    with {:ok, opponent_player_id} <- opponent_player_id(game_id, player_id),
         {:ok, opponent_bench_cards} <- cards_in_zone(game_id, opponent_player_id, :bench),
         {:ok, allocations} <- bench_damage_counter_allocations(opts),
         {:ok, allocations} <- normalize_bench_damage_counter_allocations(allocations),
         :ok <- require_bench_counter_allocation_targets(allocations, opponent_bench_cards),
         :ok <- require_bench_counter_total(allocations, opponent_bench_cards, total_counters),
         {:ok, damage_results} <-
           apply_bench_damage_counter_allocations(
             game_id,
             player_id,
             allocations,
             opponent_bench_cards
           ) do
      {:ok,
       %{
         effect_type: "opponent_bench_damage_counters",
         bench_damage_counter_total: total_counters,
         bench_damage_counter_allocations: damage_results,
         bench_damage_applied?: damage_results != []
       }}
    end
  end

  defp move_opponent_damage_counters_between_pokemon(game_id, player_id, opts) do
    with {:ok, selections} <- damage_counter_move_selections(opts),
         {:ok, opponent_cards} <- opponent_in_play_pokemon_cards(game_id, player_id),
         cards_by_id = Map.new(opponent_cards, &{&1.id, &1}),
         :ok <- require_damage_counter_move_targets(selections, cards_by_id),
         :ok <- require_damage_counter_move_counts(selections, cards_by_id),
         {:ok, move_results} <-
           build_damage_counter_move_results(game_id, player_id, selections, cards_by_id),
         {:ok, card_results} <-
           apply_damage_counter_move_results(game_id, cards_by_id, move_results) do
      successful_results = Enum.filter(move_results, &Map.get(&1, :applied?, false))

      {:ok,
       %{
         opponent_damage_counter_move_applied?: successful_results != [],
         opponent_damage_counter_move_total:
           total_damage_counter_move_counters(successful_results),
         opponent_damage_counter_move_results: move_results,
         opponent_damage_counter_card_results: card_results,
         effect_knockout_card_instance_ids:
           card_results
           |> Enum.filter(&Map.get(&1, :knocked_out?, false))
           |> Enum.map(&Map.get(&1, :card_instance_id))
       }}
    end
  end

  defp build_damage_counter_move_results(game_id, player_id, selections, cards_by_id)
       when is_map(cards_by_id) do
    selections
    |> Enum.map(fn %{from_card_instance_id: from_id, to_card_instance_id: to_id} = selection ->
      from_card = Map.fetch!(cards_by_id, from_id)
      to_card = Map.fetch!(cards_by_id, to_id)

      damage_counter_move_result(
        game_id,
        player_id,
        from_card,
        to_card,
        selection.damage_counters
      )
    end)
    |> collect_results()
  end

  defp damage_counter_move_result(
         game_id,
         player_id,
         %CardInstance{} = from_card,
         %CardInstance{} = to_card,
         damage_counters
       ) do
    move_payload = %{
      from_card_instance_id: from_card.id,
      from_card_id: from_card.card_id,
      to_card_instance_id: to_card.id,
      to_card_id: to_card.card_id,
      damage_counters: damage_counters,
      moved_damage: damage_counters * 10
    }

    case AbilityEffects.damage_counter_move_prevention_payload(game_id) do
      {:prevented, prevention_payload} ->
        {:ok,
         move_payload
         |> Map.merge(prevention_payload)
         |> Map.put(:applied?, false)
         |> Map.put(:prevented?, true)}

      :not_prevented ->
        damage_counter_move_result_after_global_prevention(
          game_id,
          player_id,
          from_card,
          to_card,
          move_payload
        )
    end
  end

  defp damage_counter_move_result_after_global_prevention(
         game_id,
         player_id,
         %CardInstance{} = from_card,
         %CardInstance{} = to_card,
         move_payload
       ) do
    case source_damage_counter_move_prevention_payload(game_id, player_id, from_card) do
      {:prevented, prevention_payload} ->
        {:ok,
         move_payload
         |> Map.merge(prevention_payload)
         |> Map.put(:applied?, false)
         |> Map.put(:prevented?, true)}

      :not_prevented ->
        case target_damage_counter_move_prevention_payload(game_id, player_id, to_card) do
          {:prevented, prevention_payload} ->
            {:ok,
             move_payload
             |> Map.merge(prevention_payload)
             |> Map.put(:applied?, false)
             |> Map.put(:prevented?, true)}

          :not_prevented ->
            {:ok, Map.merge(move_payload, %{applied?: true, prevented?: false})}
        end
    end
  end

  defp source_damage_counter_move_prevention_payload(
         game_id,
         player_id,
         %CardInstance{} = from_card
       ) do
    attack_effect_prevention_payload(game_id, player_id, from_card)
  end

  defp target_damage_counter_move_prevention_payload(
         game_id,
         player_id,
         %CardInstance{} = to_card
       ) do
    case attack_effect_prevention_payload(game_id, player_id, to_card) do
      {:prevented, prevention_payload} ->
        {:prevented, prevention_payload}

      :not_prevented ->
        StadiumEffects.damage_counter_prevention_payload(
          game_id,
          to_card,
          player_id,
          :opponent_pokemon_effect
        )
    end
  end

  defp apply_damage_counter_move_results(_game_id, _cards_by_id, []), do: {:ok, []}

  defp apply_damage_counter_move_results(game_id, cards_by_id, move_results)
       when is_map(cards_by_id) do
    successful_results = Enum.filter(move_results, &Map.get(&1, :applied?, false))

    case successful_results do
      [] ->
        {:ok, []}

      _results ->
        with {:ok, card_results} <-
               damage_counter_move_card_results(game_id, successful_results, cards_by_id),
             {:ok, _updated_cards} <- update_damage_counter_move_cards(card_results, cards_by_id),
             {:ok, _discarded_cards} <-
               discard_knocked_out_damage_counter_move_cards(game_id, card_results, cards_by_id) do
          {:ok, card_results}
        end
    end
  end

  defp damage_counter_move_card_results(game_id, successful_results, cards_by_id)
       when is_map(cards_by_id) do
    outgoing_by_card = Enum.reduce(successful_results, %{}, &add_outgoing_damage_counter_move/2)
    incoming_by_card = Enum.reduce(successful_results, %{}, &add_incoming_damage_counter_move/2)

    affected_card_ids = Enum.uniq(Map.keys(outgoing_by_card) ++ Map.keys(incoming_by_card))

    affected_card_ids
    |> Enum.map(fn card_instance_id ->
      card = Map.fetch!(cards_by_id, card_instance_id)
      outgoing_counters = Map.get(outgoing_by_card, card_instance_id, 0)
      incoming_counters = Map.get(incoming_by_card, card_instance_id, 0)
      resulting_damage = card.damage - outgoing_counters * 10 + incoming_counters * 10

      with {:ok, knocked_out?} <- HpEffects.damage_knocks_out?(game_id, card, resulting_damage) do
        {:ok,
         %{
           card_instance_id: card.id,
           card_id: card.card_id,
           starting_damage: card.damage,
           resulting_damage: resulting_damage,
           knocked_out?: knocked_out?
         }}
      end
    end)
    |> collect_results()
  end

  defp add_outgoing_damage_counter_move(result, acc) do
    Map.update(
      acc,
      result.from_card_instance_id,
      result.damage_counters,
      &(&1 + result.damage_counters)
    )
  end

  defp add_incoming_damage_counter_move(result, acc) do
    Map.update(
      acc,
      result.to_card_instance_id,
      result.damage_counters,
      &(&1 + result.damage_counters)
    )
  end

  defp update_damage_counter_move_cards(card_results, cards_by_id) when is_map(cards_by_id) do
    card_results
    |> Enum.map(fn card_result ->
      card = Map.fetch!(cards_by_id, card_result.card_instance_id)
      update(card, :set_damage, %{damage: card_result.resulting_damage})
    end)
    |> collect_results()
  end

  defp discard_knocked_out_damage_counter_move_cards(game_id, card_results, cards_by_id)
       when is_map(cards_by_id) do
    card_results
    |> Enum.filter(&Map.get(&1, :knocked_out?, false))
    |> Enum.map(fn card_result ->
      card = Map.fetch!(cards_by_id, card_result.card_instance_id)
      BattleActions.discard_knocked_out_stack(game_id, card)
    end)
    |> collect_results()
  end

  defp total_damage_counter_move_counters(results) do
    Enum.reduce(results, 0, fn result, total -> Map.get(result, :damage_counters, 0) + total end)
  end

  defp movable_damage_counter_count(%CardInstance{damage: damage}) when is_integer(damage) do
    damage
    |> max(0)
    |> div(10)
  end

  defp movable_damage_counter_count(%CardInstance{}), do: 0

  defp legal_damage_counter_move_available?(opponent_cards) when is_list(opponent_cards) do
    Enum.any?(opponent_cards, fn source_card ->
      movable_damage_counter_count(source_card) > 0 and
        Enum.any?(opponent_cards, &(&1.id != source_card.id))
    end)
  end

  defp strange_hacking_public_note(status_payload, move_payload) do
    status_applied? = Map.get(status_payload, :defender_status_applied?, false)
    moved_counters = Map.get(move_payload, :opponent_damage_counter_move_total, 0)

    cond do
      status_applied? and moved_counters > 0 ->
        "Strange Hacking Confused the opponent's Active Pokémon and moved #{moved_counters} #{pluralize_damage_counter(moved_counters)}."

      status_applied? ->
        "Strange Hacking Confused the opponent's Active Pokémon."

      moved_counters > 0 ->
        "Strange Hacking moved #{moved_counters} #{pluralize_damage_counter(moved_counters)}."

      true ->
        "Strange Hacking resolved."
    end
  end

  defp pluralize_damage_counter(1), do: "damage counter"
  defp pluralize_damage_counter(_count), do: "damage counters"

  defp special_condition_effect_type(:asleep), do: "sleep_defender_active"
  defp special_condition_effect_type(:confused), do: "confuse_defender_active"

  defp move_opponent_attached_energy_between_pokemon(game_id, player_id, opts) do
    with {:ok, move_option} <- opponent_energy_move_option(game_id, player_id, opts) do
      case move_option do
        nil ->
          {:ok,
           %{
             effect_type: "move_opponent_attached_energy_between_pokemon",
             moved_energy?: false
           }}

        %{energy_card: %CardInstance{} = energy_card, attached_to: %CardInstance{} = from_card} ->
          with {:ok, target_card} <-
                 opponent_energy_move_target(game_id, player_id, from_card, opts) do
            case target_card do
              nil ->
                {:ok,
                 %{
                   effect_type: "move_opponent_attached_energy_between_pokemon",
                   moved_energy?: false
                 }}

              %CardInstance{} = target_card ->
                with {:ok, moved_energy_card} <-
                       reparent_opponent_attached_energy(game_id, energy_card, target_card) do
                  {:ok,
                   %{
                     effect_type: "move_opponent_attached_energy_between_pokemon",
                     moved_energy?: true,
                     moved_opponent_energy_card_instance_id: moved_energy_card.id,
                     moved_opponent_energy_card_id: moved_energy_card.card_id,
                     moved_opponent_energy_from_card_instance_id: from_card.id,
                     moved_opponent_energy_from_card_id: from_card.card_id,
                     moved_opponent_energy_to_card_instance_id: target_card.id,
                     moved_opponent_energy_to_card_id: target_card.card_id
                   }}
                end
            end
          end
      end
    end
  end

  defp discarded_energy_card_instance_ids(opts) do
    case Map.get(opts, :discarded_energy_card_instance_ids) ||
           Map.get(opts, "discarded_energy_card_instance_ids") do
      nil -> {:ok, []}
      ids when is_list(ids) -> {:ok, ids}
      _invalid -> {:error, :invalid_discarded_energy_card_instance_ids}
    end
  end

  defp shuffled_energy_card_instance_ids(opts) do
    case Map.get(opts, :shuffled_energy_card_instance_ids) ||
           Map.get(opts, "shuffled_energy_card_instance_ids") do
      nil -> {:ok, []}
      ids when is_list(ids) -> {:ok, ids}
      _invalid -> {:error, :invalid_shuffled_energy_card_instance_ids}
    end
  end

  defp bench_damage_counter_allocations(opts) do
    case Map.get(opts, :bench_damage_counter_allocations) ||
           Map.get(opts, "bench_damage_counter_allocations") do
      nil -> {:ok, %{}}
      allocations when is_map(allocations) -> {:ok, allocations}
      _invalid -> {:error, :invalid_bench_damage_counter_allocations}
    end
  end

  defp damage_counter_move_selections(opts) do
    case Map.get(opts, :damage_counter_move_selections) ||
           Map.get(opts, "damage_counter_move_selections") do
      nil ->
        {:ok, []}

      selections when is_list(selections) ->
        normalize_damage_counter_move_selections(selections)

      _invalid ->
        {:error, :invalid_damage_counter_move_selections}
    end
  end

  defp normalize_damage_counter_move_selections(selections) when is_list(selections) do
    selections
    |> Enum.reduce_while({:ok, %{}}, fn selection, {:ok, acc} ->
      with {:ok, from_card_instance_id} <-
             required_selection_string(
               selection,
               [
                 :from_card_instance_id,
                 "from_card_instance_id",
                 :fromCardInstanceId,
                 "fromCardInstanceId"
               ],
               :invalid_damage_counter_move_source_card_instance_id
             ),
           {:ok, to_card_instance_id} <-
             required_selection_string(
               selection,
               [
                 :to_card_instance_id,
                 "to_card_instance_id",
                 :toCardInstanceId,
                 "toCardInstanceId"
               ],
               :invalid_damage_counter_move_target_card_instance_id
             ),
           {:ok, damage_counters} <-
             required_selection_integer(
               selection,
               [:damage_counters, "damage_counters", :damageCounters, "damageCounters"],
               :invalid_damage_counter_move_count
             ),
           true <- damage_counters > 0 || {:error, :invalid_damage_counter_move_count} do
        key = {from_card_instance_id, to_card_instance_id}

        {:cont, {:ok, Map.update(acc, key, damage_counters, &(&1 + damage_counters))}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} ->
        {:ok,
         Enum.map(normalized, fn {{from_card_instance_id, to_card_instance_id}, damage_counters} ->
           %{
             from_card_instance_id: from_card_instance_id,
             to_card_instance_id: to_card_instance_id,
             damage_counters: damage_counters
           }
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp required_selection_string(selection, keys, error_reason) when is_map(selection) do
    case Enum.find_value(keys, fn key ->
           case Map.get(selection, key) do
             value when is_binary(value) and value != "" -> value
             _other -> nil
           end
         end) do
      value when is_binary(value) -> {:ok, value}
      _missing -> {:error, error_reason}
    end
  end

  defp required_selection_string(_selection, _keys, error_reason), do: {:error, error_reason}

  defp required_selection_integer(selection, keys, error_reason) when is_map(selection) do
    case Enum.find_value(keys, fn key ->
           case Map.get(selection, key) do
             value when is_integer(value) -> value
             _other -> nil
           end
         end) do
      value when is_integer(value) -> {:ok, value}
      _missing -> {:error, error_reason}
    end
  end

  defp required_selection_integer(_selection, _keys, error_reason), do: {:error, error_reason}

  defp require_damage_counter_move_targets([], _cards_by_id), do: :ok

  defp require_damage_counter_move_targets(selections, cards_by_id) when is_map(cards_by_id) do
    if Enum.all?(selections, fn %{from_card_instance_id: from_id, to_card_instance_id: to_id} ->
         is_map_key(cards_by_id, from_id) and is_map_key(cards_by_id, to_id) and from_id != to_id
       end) do
      :ok
    else
      {:error, :invalid_damage_counter_move_target}
    end
  end

  defp require_damage_counter_move_counts(selections, cards_by_id) when is_map(cards_by_id) do
    selections
    |> Enum.group_by(& &1.from_card_instance_id)
    |> Enum.reduce_while(:ok, fn {from_card_instance_id, source_selections}, :ok ->
      from_card = Map.fetch!(cards_by_id, from_card_instance_id)
      requested_counters = Enum.reduce(source_selections, 0, &(&1.damage_counters + &2))
      available_counters = movable_damage_counter_count(from_card)

      cond do
        requested_counters < 1 ->
          {:halt, {:error, :invalid_damage_counter_move_count}}

        requested_counters > available_counters ->
          {:halt,
           {:error,
            {:not_enough_damage_counters, from_card_instance_id, requested_counters,
             available_counters}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp normalize_bench_damage_counter_allocations(allocations) do
    allocations
    |> Enum.reduce_while({:ok, []}, fn {card_instance_id, counters}, {:ok, normalized} ->
      cond do
        not is_binary(card_instance_id) ->
          {:halt, {:error, :invalid_bench_damage_counter_target}}

        is_integer(counters) and counters > 0 ->
          {:cont, {:ok, [{card_instance_id, counters} | normalized]}}

        counters == 0 ->
          {:cont, {:ok, normalized}}

        true ->
          {:halt, {:error, :invalid_bench_damage_counter_count}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_bench_counter_allocation_targets(allocations, opponent_bench_cards) do
    bench_card_ids = MapSet.new(opponent_bench_cards, & &1.id)

    if Enum.all?(allocations, fn {card_instance_id, _counters} ->
         MapSet.member?(bench_card_ids, card_instance_id)
       end) do
      :ok
    else
      {:error, :invalid_bench_damage_counter_target}
    end
  end

  defp require_bench_counter_total(allocations, [], _total_counters) do
    allocated_counters = total_allocated_counters(allocations)

    if allocated_counters == 0 do
      :ok
    else
      {:error, :invalid_bench_damage_counter_target}
    end
  end

  defp require_bench_counter_total(allocations, [_first | _rest], total_counters) do
    if total_allocated_counters(allocations) == total_counters do
      :ok
    else
      {:error, :wrong_bench_damage_counter_total}
    end
  end

  defp total_allocated_counters(allocations) do
    Enum.reduce(allocations, 0, fn {_card_instance_id, counters}, total -> total + counters end)
  end

  defp apply_bench_damage_counter_allocations(_game_id, _player_id, [], _opponent_bench_cards),
    do: {:ok, []}

  defp apply_bench_damage_counter_allocations(
         game_id,
         player_id,
         allocations,
         opponent_bench_cards
       ) do
    opponent_bench_cards_by_id = Map.new(opponent_bench_cards, &{&1.id, &1})

    allocations
    |> Enum.map(fn {card_instance_id, counters} ->
      bench_card = Map.fetch!(opponent_bench_cards_by_id, card_instance_id)
      damage = counters * 10

      with {:ok, damage_result} <-
             apply_bench_attack_damage(
               game_id,
               player_id,
               bench_card,
               damage,
               :damage_counters
             ) do
        {:ok,
         %{
           card_instance_id: bench_card.id,
           counters: counters,
           damage: damage_result.damage,
           prevented_damage: Map.get(damage_result, :prevented_damage, 0),
           resulting_damage: damage_result.resulting_damage,
           knocked_out?: damage_result.knocked_out?,
           damage_prevented?: Map.get(damage_result, :damage_prevented?, false)
         }}
      end
    end)
    |> collect_results()
  end

  defp bench_damage_target_card_instance_id(opts) do
    Map.get(opts, :bench_damage_target_card_instance_id) ||
      Map.get(opts, "bench_damage_target_card_instance_id")
  end

  defp moved_opponent_energy_card_instance_id(opts) do
    Map.get(opts, :moved_opponent_energy_card_instance_id) ||
      Map.get(opts, "moved_opponent_energy_card_instance_id")
  end

  defp moved_opponent_energy_target_card_instance_id(opts) do
    Map.get(opts, :moved_opponent_energy_target_card_instance_id) ||
      Map.get(opts, "moved_opponent_energy_target_card_instance_id")
  end

  defp opponent_energy_move_option(game_id, player_id, opts) do
    with {:ok, move_options} <- opponent_energy_move_options(game_id, player_id) do
      case moved_opponent_energy_card_instance_id(opts) do
        nil ->
          implicit_opponent_energy_move_option(move_options)

        card_instance_id when is_binary(card_instance_id) ->
          explicit_opponent_energy_move_option(move_options, card_instance_id)

        _invalid ->
          {:error, :invalid_moved_opponent_energy_card_instance_id}
      end
    end
  end

  defp implicit_opponent_energy_move_option([]), do: {:ok, nil}
  defp implicit_opponent_energy_move_option([move_option]), do: {:ok, move_option}

  defp implicit_opponent_energy_move_option([_first | _rest]),
    do: {:error, :move_opponent_energy_requires_energy_choice}

  defp explicit_opponent_energy_move_option(move_options, card_instance_id) do
    case Enum.find(move_options, fn %{energy_card: energy_card} ->
           energy_card.id == card_instance_id
         end) do
      nil -> {:error, :invalid_moved_opponent_energy_choice}
      move_option -> {:ok, move_option}
    end
  end

  defp opponent_energy_move_target(game_id, player_id, %CardInstance{} = from_card, opts) do
    with {:ok, target_options} <-
           opponent_energy_move_target_options(game_id, player_id, from_card) do
      case moved_opponent_energy_target_card_instance_id(opts) do
        nil ->
          implicit_opponent_energy_move_target(target_options)

        card_instance_id when is_binary(card_instance_id) ->
          explicit_opponent_energy_move_target(target_options, card_instance_id)

        _invalid ->
          {:error, :invalid_moved_opponent_energy_target_card_instance_id}
      end
    end
  end

  defp implicit_opponent_energy_move_target([]), do: {:ok, nil}
  defp implicit_opponent_energy_move_target([target_card]), do: {:ok, target_card}

  defp implicit_opponent_energy_move_target([_first | _rest]),
    do: {:error, :move_opponent_energy_requires_target}

  defp explicit_opponent_energy_move_target(target_options, card_instance_id) do
    case Enum.find(target_options, &(&1.id == card_instance_id)) do
      nil -> {:error, :invalid_moved_opponent_energy_target_choice}
      target_card -> {:ok, target_card}
    end
  end

  defp opponent_energy_move_options(game_id, player_id) do
    with {:ok, opponent_in_play_cards} <- opponent_in_play_pokemon_cards(game_id, player_id) do
      case opponent_in_play_cards do
        [_only_card] ->
          {:ok, []}

        [] ->
          {:ok, []}

        _cards ->
          {:ok,
           Enum.flat_map(opponent_in_play_cards, fn target_card ->
             case attached_cards(game_id, target_card.id) do
               {:ok, attachments} ->
                 attachments
                 |> Enum.filter(&energy_card?/1)
                 |> Enum.map(fn energy_card ->
                   %{energy_card: energy_card, attached_to: target_card}
                 end)

               {:error, _reason} ->
                 []
             end
           end)}
      end
    end
  end

  defp opponent_energy_move_target_options(game_id, player_id, %CardInstance{} = from_card) do
    with {:ok, opponent_in_play_cards} <- opponent_in_play_pokemon_cards(game_id, player_id) do
      {:ok, Enum.reject(opponent_in_play_cards, &(&1.id == from_card.id))}
    end
  end

  defp opponent_in_play_pokemon_cards(game_id, player_id) do
    with {:ok, opponent_player_id} <- opponent_player_id(game_id, player_id),
         {:ok, active_cards} <- cards_in_zone(game_id, opponent_player_id, :active),
         {:ok, bench_cards} <- cards_in_zone(game_id, opponent_player_id, :bench) do
      {:ok, active_cards ++ bench_cards}
    end
  end

  defp energy_card?(%CardInstance{card_id: card_id}), do: match?(:ok, require_energy(card_id))

  defp reparent_opponent_attached_energy(
         game_id,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card
       ) do
    with {:ok, target_attachments} <- attached_cards(game_id, target_card.id) do
      update(energy_card, :reparent_attachment, %{
        attached_to_card_instance_id: target_card.id,
        position: length(target_attachments) + 1
      })
    end
  end

  defp returned_attached_energy_card(game_id, player_id, %CardInstance{} = attacker_card, opts) do
    with {:ok, energy_cards} <-
           returnable_attached_energy_cards(game_id, player_id, attacker_card) do
      case returned_energy_card_instance_id(opts) do
        nil ->
          implicit_returned_attached_energy_card(energy_cards)

        card_instance_id when is_binary(card_instance_id) ->
          explicit_returned_attached_energy_card(energy_cards, card_instance_id)

        _invalid ->
          {:error, :invalid_returned_energy_card_instance_id}
      end
    end
  end

  defp returned_energy_card_instance_id(opts) do
    Map.get(opts, :returned_energy_card_instance_id) ||
      Map.get(opts, "returned_energy_card_instance_id")
  end

  defp implicit_returned_attached_energy_card([]), do: {:error, :no_attached_energy_to_return}
  defp implicit_returned_attached_energy_card([energy_card]), do: {:ok, energy_card}

  defp implicit_returned_attached_energy_card([_first | _rest]),
    do: {:error, :return_attached_energy_requires_target}

  defp explicit_returned_attached_energy_card(energy_cards, card_instance_id) do
    case Enum.find(energy_cards, &(&1.id == card_instance_id)) do
      %CardInstance{} = energy_card -> {:ok, energy_card}
      nil -> {:error, :invalid_returned_energy_choice}
    end
  end

  defp returnable_attached_energy_cards(game_id, player_id, %CardInstance{} = attacker_card) do
    with {:ok, active_card} <- active_card(game_id, player_id),
         :ok <- require_same_card(active_card, attacker_card),
         {:ok, attached_cards} <- attached_cards(game_id, attacker_card.id) do
      attached_cards
      |> Enum.reduce_while({:ok, []}, fn attached_card, {:ok, energy_cards} ->
        with :ok <- require_card_owned_by_player(attached_card, player_id),
             :ok <- require_card_zone(attached_card, :attached) do
          case require_energy(attached_card.card_id) do
            :ok -> {:cont, {:ok, [attached_card | energy_cards]}}
            {:error, _not_energy} -> {:cont, {:ok, energy_cards}}
          end
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, energy_cards} -> {:ok, Enum.reverse(energy_cards)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp shufflable_attached_energy_cards(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         energy_card_instance_ids
       ) do
    with {:ok, energy_cards} <-
           returnable_attached_energy_cards(game_id, player_id, attacker_card) do
      energy_cards_by_id = Map.new(energy_cards, &{&1.id, &1})

      energy_card_instance_ids
      |> Enum.map(fn card_instance_id ->
        case Map.fetch(energy_cards_by_id, card_instance_id) do
          {:ok, energy_card} -> {:ok, energy_card}
          :error -> {:error, :invalid_shuffled_energy_choice}
        end
      end)
      |> collect_results()
    end
  end

  defp bench_damage_target_card(game_id, player_id, opts) do
    with {:ok, opponent_player_id} <- opponent_player_id(game_id, player_id) do
      case bench_damage_target_card_instance_id(opts) do
        nil ->
          implicit_bench_damage_target(game_id, opponent_player_id)

        card_instance_id when is_binary(card_instance_id) ->
          explicit_bench_damage_target(game_id, opponent_player_id, card_instance_id)

        _invalid ->
          {:error, :invalid_bench_damage_target_card_instance_id}
      end
    end
  end

  defp implicit_bench_damage_target(game_id, opponent_player_id) do
    with {:ok, bench_cards} <- cards_in_zone(game_id, opponent_player_id, :bench) do
      case bench_cards do
        [bench_card] -> {:ok, bench_card}
        [] -> {:error, :bench_damage_target_required}
        [_first | _rest] -> {:error, :bench_damage_requires_target}
      end
    end
  end

  defp explicit_bench_damage_target(game_id, opponent_player_id, card_instance_id) do
    with {:ok, bench_card} <- get_card(game_id, card_instance_id),
         :ok <- require_card_owned_by_player(bench_card, opponent_player_id),
         :ok <- require_card_zone(bench_card, :bench) do
      {:ok, bench_card}
    end
  end

  defp apply_bench_attack_damage(
         game_id,
         attacking_player_id,
         %CardInstance{} = bench_target,
         damage,
         kind
       ) do
    case prevented_bench_attack_damage_result(
           game_id,
           attacking_player_id,
           bench_target,
           damage,
           kind
         ) do
      {:ok, damage_result} ->
        {:ok, damage_result}

      :not_prevented ->
        new_damage = bench_target.damage + damage

        with {:ok, knocked_out?} <-
               HpEffects.damage_knocks_out?(game_id, bench_target, new_damage),
             {:ok, knockout_prize_count} <-
               maybe_bench_knockout_prize_count(game_id, bench_target, knocked_out?, kind),
             {:ok, _bench_target} <- update(bench_target, :set_damage, %{damage: new_damage}),
             {:ok, _discarded_cards} <-
               maybe_discard_knocked_out_bench_stack(game_id, bench_target, knocked_out?) do
          {:ok,
           maybe_put_knockout_prize_count(
             %{damage: damage, resulting_damage: new_damage, knocked_out?: knocked_out?},
             knockout_prize_count
           )}
        end
    end
  end

  defp maybe_bench_knockout_prize_count(_game_id, _bench_target, false, _kind), do: {:ok, nil}

  defp maybe_bench_knockout_prize_count(game_id, %CardInstance{} = bench_target, true, :damage),
    do: BattleActions.knockout_prize_count_for_opponent_attack(game_id, bench_target)

  defp maybe_bench_knockout_prize_count(_game_id, _bench_target, true, _kind), do: {:ok, nil}

  defp maybe_put_knockout_prize_count(payload, knockout_prize_count)
       when is_integer(knockout_prize_count) and knockout_prize_count >= 0 do
    Map.put(payload, :knockout_prize_count, knockout_prize_count)
  end

  defp maybe_put_knockout_prize_count(payload, _knockout_prize_count), do: payload

  defp maybe_discard_knocked_out_bench_stack(_game_id, _bench_target, false), do: {:ok, []}

  defp maybe_discard_knocked_out_bench_stack(game_id, %CardInstance{} = bench_target, true) do
    BattleActions.discard_knocked_out_stack(game_id, bench_target)
  end

  defp prevented_bench_attack_damage_result(
         game_id,
         attacking_player_id,
         bench_target,
         damage,
         :damage
       ) do
    if TeraBenchProtection.prevents_attack_damage?(bench_target) do
      {:ok, TeraBenchProtection.prevented_attack_damage_result(bench_target, damage)}
    else
      case spherical_shield_bench_prevention_result(
             game_id,
             attacking_player_id,
             bench_target,
             damage
           ) do
        {:ok, damage_result} ->
          {:ok, damage_result}

        :not_prevented ->
          prevented_bench_attack_damage_by_marker_result(
            game_id,
            attacking_player_id,
            bench_target,
            damage
          )
      end
    end
  end

  defp prevented_bench_attack_damage_result(
         game_id,
         attacking_player_id,
         bench_target,
         damage,
         _kind
       ) do
    prevented_bench_attack_effect_damage_result(
      game_id,
      attacking_player_id,
      bench_target,
      damage
    )
  end

  defp prevented_bench_attack_damage_by_marker_result(
         game_id,
         attacking_player_id,
         bench_target,
         damage
       ) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         true <-
           AttackPrevention.damage_and_effects_prevented_this_turn?(
             bench_target,
             turn,
             attacking_player_id
           ) do
      {:ok,
       Map.merge(
         %{
           damage: 0,
           prevented_damage: damage,
           resulting_damage: bench_target.damage,
           knocked_out?: false,
           damage_prevented?: true
         },
         AttackPrevention.prevention_payload(bench_target, turn)
       )}
    else
      _not_prevented -> :not_prevented
    end
  end

  defp prevented_bench_attack_effect_damage_result(
         game_id,
         attacking_player_id,
         bench_target,
         damage
       ) do
    case spherical_shield_bench_prevention_result(
           game_id,
           attacking_player_id,
           bench_target,
           damage
         ) do
      {:ok, damage_result} ->
        {:ok, damage_result}

      :not_prevented ->
        with {:ok, turn} <- TurnStore.current_turn(game_id),
             {:prevented, prevention_payload} <-
               AttackPrevention.attack_effect_prevention_payload(
                 bench_target,
                 turn,
                 attacking_player_id
               ) do
          {:ok,
           Map.merge(
             %{
               damage: 0,
               prevented_damage: damage,
               resulting_damage: bench_target.damage,
               knocked_out?: false,
               damage_prevented?: true
             },
             prevention_payload
           )}
        else
          _not_prevented -> :not_prevented
        end
    end
  end

  defp spherical_shield_bench_prevention_result(
         game_id,
         attacking_player_id,
         %CardInstance{zone: :bench, owner_player_id: owner_player_id} = bench_target,
         damage
       )
       when owner_player_id != attacking_player_id do
    with {:ok, cards} <- list_cards(game_id),
         %CardInstance{} = shield_card <- active_spherical_shield_card(cards, owner_player_id) do
      {:ok,
       %{
         damage: 0,
         prevented_damage: damage,
         resulting_damage: bench_target.damage,
         knocked_out?: false,
         damage_prevented?: true,
         damage_prevention: @spherical_shield_effect_id,
         attack_prevention_source_card_id: shield_card.card_id,
         attack_prevention_source_card_instance_id: shield_card.id,
         attack_prevention_source_effect_id: @spherical_shield_effect_id,
         attack_prevention_source_player_id: owner_player_id,
         protected_card_instance_id: bench_target.id
       }}
    else
      _not_prevented -> :not_prevented
    end
  end

  defp spherical_shield_bench_prevention_result(
         _game_id,
         _attacking_player_id,
         %CardInstance{},
         _damage
       ),
       do: :not_prevented

  defp active_spherical_shield_card(cards, owner_player_id) when is_list(cards) do
    Enum.find(cards, fn
      %CardInstance{
        card_id: @spherical_shield_card_id,
        owner_player_id: ^owner_player_id,
        zone: zone
      }
      when zone in [:active, :bench] ->
        true

      %CardInstance{} ->
        false
    end)
  end

  defp opponent_player_id(game_id, player_id) do
    with {:ok, players} <- PlayerStore.list_players(game_id) do
      players
      |> Enum.reject(&(&1.player_id == player_id))
      |> case do
        [opponent] -> {:ok, opponent.player_id}
        [] -> {:error, :opponent_player_not_found}
        _players -> {:error, :ambiguous_opponent_player}
      end
    end
  end

  defp discardable_basic_energy_cards(_game_id, _player_id, []), do: {:ok, []}

  defp discardable_basic_energy_cards(game_id, player_id, energy_card_instance_ids) do
    with :ok <- require_unique_ids(energy_card_instance_ids),
         {:ok, energy_cards} <- get_cards(game_id, energy_card_instance_ids) do
      energy_cards
      |> Enum.map(&discardable_basic_energy_card(game_id, player_id, &1))
      |> collect_results()
    end
  end

  defp discardable_basic_energy_card(game_id, player_id, %CardInstance{} = energy_card) do
    with :ok <- require_card_owned_by_player(energy_card, player_id),
         :ok <- require_card_zone(energy_card, :attached),
         :ok <- require_basic_energy(energy_card.card_id),
         {:ok, _target_card} <- attached_to_own_in_play_pokemon(game_id, player_id, energy_card) do
      {:ok, energy_card}
    end
  end

  defp discardable_bench_energy_cards(_game_id, _player_id, []), do: {:ok, []}

  defp discardable_bench_energy_cards(game_id, player_id, energy_card_instance_ids) do
    with :ok <- require_unique_ids(energy_card_instance_ids),
         {:ok, energy_cards} <- get_cards(game_id, energy_card_instance_ids) do
      energy_cards
      |> Enum.map(&discardable_bench_energy_card(game_id, player_id, &1))
      |> collect_results()
    end
  end

  defp discardable_bench_energy_card(game_id, player_id, %CardInstance{} = energy_card) do
    with :ok <- require_card_owned_by_player(energy_card, player_id),
         :ok <- require_card_zone(energy_card, :attached),
         :ok <- require_energy(energy_card.card_id),
         {:ok, _target_card} <- attached_to_own_bench_pokemon(game_id, player_id, energy_card) do
      {:ok, energy_card}
    end
  end

  defp attached_to_own_in_play_pokemon(_game_id, _player_id, %CardInstance{
         attached_to_card_instance_id: nil
       }) do
    {:error, :energy_not_attached_to_pokemon}
  end

  defp attached_to_own_in_play_pokemon(game_id, player_id, %CardInstance{} = energy_card) do
    with {:ok, target_card} <- get_card(game_id, energy_card.attached_to_card_instance_id),
         :ok <- require_card_owned_by_player(target_card, player_id),
         :ok <- require_in_play_pokemon_zone(target_card) do
      {:ok, target_card}
    end
  end

  defp attached_to_own_bench_pokemon(_game_id, _player_id, %CardInstance{
         attached_to_card_instance_id: nil
       }) do
    {:error, :energy_not_attached_to_pokemon}
  end

  defp attached_to_own_bench_pokemon(game_id, player_id, %CardInstance{} = energy_card) do
    with {:ok, target_card} <- get_card(game_id, energy_card.attached_to_card_instance_id),
         :ok <- require_card_owned_by_player(target_card, player_id),
         :ok <- require_card_zone(target_card, :bench) do
      {:ok, target_card}
    end
  end

  defp draw_cards_to_hand(_game_id, _player_id, []), do: {:ok, []}

  defp draw_cards_to_hand(game_id, player_id, deck_cards) do
    with {:ok, first_hand_position} <- next_hand_position_result(game_id, player_id) do
      deck_cards
      |> Enum.with_index(first_hand_position)
      |> Enum.map(fn {card, position} ->
        update(card, :draw_to_hand, %{position: position})
      end)
      |> collect_results()
    end
  end

  defp switch_target(game_id, player_id, opts) do
    case switch_bench_card_instance_id(opts) do
      nil ->
        implicit_switch_target(game_id, player_id)

      card_instance_id when is_binary(card_instance_id) ->
        explicit_switch_target(game_id, player_id, card_instance_id)

      _invalid ->
        {:error, :invalid_switch_bench_card_instance_id}
    end
  end

  defp switch_bench_card_instance_id(opts) do
    Map.get(opts, :switch_bench_card_instance_id) ||
      Map.get(opts, "switch_bench_card_instance_id")
  end

  defp implicit_switch_target(game_id, player_id) do
    with {:ok, bench_cards} <- cards_in_zone(game_id, player_id, :bench) do
      case bench_cards do
        [] -> {:ok, nil}
        [bench_card] -> {:ok, bench_card}
        [_first | _rest] -> {:error, :switch_self_with_bench_requires_target}
      end
    end
  end

  defp explicit_switch_target(game_id, player_id, card_instance_id) do
    with {:ok, bench_card} <- get_card(game_id, card_instance_id),
         :ok <- require_card_owned_by_player(bench_card, player_id),
         :ok <- require_card_zone(bench_card, :bench) do
      {:ok, bench_card}
    end
  end

  defp switch_attacker_with_bench(_game_id, _player_id, _attacker_card, nil) do
    {:ok, %{effect_type: "switch_self_with_bench", switched?: false}}
  end

  defp switch_attacker_with_bench(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         %CardInstance{} = bench_card
       ) do
    with {:ok, active_card} <- active_card(game_id, player_id),
         :ok <- require_same_card(active_card, attacker_card),
         bench_position = bench_card.position,
         {:ok, _active_card} <-
           update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
         {:ok, _bench_card} <-
           update(bench_card, :promote_to_active, %{position: 1, status: nil}) do
      {:ok,
       %{
         effect_type: "switch_self_with_bench",
         switched?: true,
         switched_active_card_instance_id: active_card.id,
         switched_bench_card_instance_id: bench_card.id
       }}
    end
  end

  defp require_same_card(%CardInstance{id: id}, %CardInstance{id: id}), do: :ok

  defp require_same_card(%CardInstance{}, %CardInstance{}),
    do: {:error, :attacker_is_no_longer_active}
end

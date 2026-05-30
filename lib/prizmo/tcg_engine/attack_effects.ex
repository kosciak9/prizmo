defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [active_card: 2]

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      pokemon_hp: 1,
      require_basic_energy: 1,
      require_energy: 1,
      require_pokemon_card: 1,
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
      move_attached_card_to_hand: 3,
      move_deck_card_to_hand: 3,
      move_discard_card_to_hand: 3,
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

  alias Prizmo.TcgEngine.AttackLocks
  alias Prizmo.TcgEngine.BattleActions
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.RetreatLocks
  alias Prizmo.TcgEngine.TurnStore

  @supported_effect_types [
    :bonus_damage_per_benched_pokemon,
    :bonus_damage_if_defender_pokemon_ex,
    :bonus_damage_if_attacker_has_team_rocket_energy,
    :bonus_damage_if_moved_from_bench_to_active_this_turn,
    :bonus_damage_per_energy_attached_to_both_active,
    :bonus_damage_per_energy_attached_to_defender,
    :attacker_cannot_attack_next_turn,
    :confuse_defender_active,
    :damage_unaffected_by_effects_on_opponent_active,
    :damage_only_if_stadium_in_play,
    :damage_per_discarded_own_basic_energy,
    :discard_energy_from_own_bench_for_bonus_damage,
    :defending_pokemon_cannot_retreat_next_turn,
    :discard_hand_then_draw,
    :draw_after_attack,
    :damage_per_own_basic_pokemon_in_play,
    :damage_per_own_benched_pokemon,
    :damage_per_own_team_rocket_pokemon_in_play,
    :recover_trainer_from_discard_to_hand,
    :return_attached_energy_to_hand,
    :opponent_bench_damage_counters,
    :search_pokemon_to_hand,
    :self_damage,
    :shuffle_attached_energy_into_deck_then_damage_opponent_bench,
    :switch_self_with_bench
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
      %{type: :switch_self_with_bench} ->
        switch_self_with_bench(game_id, player_id, attacker_card, opts)

      %{type: :bonus_damage_if_defender_pokemon_ex} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_attacker_has_team_rocket_energy} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_moved_from_bench_to_active_this_turn} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_benched_pokemon} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_energy_attached_to_both_active} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_energy_attached_to_defender} ->
        {:ok, %{}}

      %{type: :attacker_cannot_attack_next_turn} ->
        attacker_cannot_attack_next_turn(game_id, attacker_card)

      %{type: :confuse_defender_active} ->
        set_defender_status(game_id, defender_card, :confused)

      %{type: :defending_pokemon_cannot_retreat_next_turn} ->
        defender_cannot_retreat_next_turn(game_id, defender_card)

      %{type: :damage_per_own_benched_pokemon} ->
        {:ok, %{}}

      %{type: :damage_per_own_basic_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_only_if_stadium_in_play} ->
        {:ok, %{}}

      %{type: :damage_per_own_team_rocket_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_per_discarded_own_basic_energy} ->
        discard_attached_basic_energy_for_damage(game_id, player_id, opts)

      %{type: :discard_energy_from_own_bench_for_bonus_damage, max_discards: max_discards}
      when is_integer(max_discards) and max_discards >= 0 ->
        discard_own_bench_energy_for_bonus_damage(game_id, player_id, opts, max_discards)

      %{type: :damage_unaffected_by_effects_on_opponent_active} ->
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

      %{type: :return_attached_energy_to_hand} ->
        return_attached_energy_to_hand(game_id, player_id, attacker_card, opts)

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

  defp source_payload(%PendingEffect{} = pending_effect) do
    %{
      type: :card,
      card_id: pending_effect.source_card_id,
      card_instance_id: pending_effect.source_card_instance_id
    }
  end

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

  defp set_defender_status(game_id, %CardInstance{} = defender_card, status) do
    with {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
      case current_defender_card.zone do
        :active ->
          with {:ok, _defender_card} <-
                 update(current_defender_card, :set_status, %{status: status}) do
            {:ok,
             %{
               effect_type: "confuse_defender_active",
               defender_status: Atom.to_string(status),
               defender_status_applied?: true,
               defender_status_card_instance_id: current_defender_card.id
             }}
          end

        _other_zone ->
          {:ok,
           %{
             effect_type: "confuse_defender_active",
             defender_status: Atom.to_string(status),
             defender_status_applied?: false,
             defender_status_card_instance_id: defender_card.id
           }}
      end
    end
  end

  defp defender_cannot_retreat_next_turn(game_id, %CardInstance{} = defender_card) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
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
           apply_bench_attack_damage_without_knockout(bench_target, bench_damage),
         {:ok, shuffled_energy_cards} <-
           shuffle_attached_cards_into_deck(game_id, player_id, energy_cards) do
      {:ok,
       %{
         effect_type: "shuffle_attached_energy_into_deck_then_damage_opponent_bench",
         shuffled_energy_card_instance_ids: Enum.map(shuffled_energy_cards, & &1.id),
         shuffled_energy_count: length(shuffled_energy_cards),
         bench_damage_target_card_instance_id: bench_target.id,
         bench_damage: damage_result.damage,
         bench_resulting_damage: damage_result.resulting_damage,
         bench_knocked_out?: damage_result.knocked_out?,
         bench_damage_applied?: true
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
           apply_bench_damage_counter_allocations(allocations, opponent_bench_cards) do
      {:ok,
       %{
         effect_type: "opponent_bench_damage_counters",
         bench_damage_counter_total: total_counters,
         bench_damage_counter_allocations: damage_results,
         bench_damage_applied?: damage_results != []
       }}
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

  defp apply_bench_damage_counter_allocations([], _opponent_bench_cards), do: {:ok, []}

  defp apply_bench_damage_counter_allocations(allocations, opponent_bench_cards) do
    opponent_bench_cards_by_id = Map.new(opponent_bench_cards, &{&1.id, &1})

    allocations
    |> Enum.map(fn {card_instance_id, counters} ->
      bench_card = Map.fetch!(opponent_bench_cards_by_id, card_instance_id)
      damage = counters * 10

      with {:ok, damage_result} <- apply_bench_attack_damage_without_knockout(bench_card, damage) do
        {:ok,
         %{
           card_instance_id: bench_card.id,
           counters: counters,
           damage: damage_result.damage,
           resulting_damage: damage_result.resulting_damage,
           knocked_out?: damage_result.knocked_out?
         }}
      end
    end)
    |> collect_results()
  end

  defp bench_damage_target_card_instance_id(opts) do
    Map.get(opts, :bench_damage_target_card_instance_id) ||
      Map.get(opts, "bench_damage_target_card_instance_id")
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

  defp apply_bench_attack_damage_without_knockout(%CardInstance{} = bench_target, damage) do
    with {:ok, target_hp} <- pokemon_hp(bench_target.card_id),
         new_damage = bench_target.damage + damage,
         :ok <- require_bench_damage_does_not_knock_out(new_damage, target_hp),
         {:ok, _bench_target} <- update(bench_target, :set_damage, %{damage: new_damage}) do
      {:ok,
       %{
         damage: damage,
         resulting_damage: new_damage,
         knocked_out?: false
       }}
    end
  end

  defp require_bench_damage_does_not_knock_out(new_damage, target_hp) when new_damage < target_hp,
    do: :ok

  defp require_bench_damage_does_not_knock_out(_new_damage, _target_hp),
    do: {:error, :bench_damage_knockout_not_supported}

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
end

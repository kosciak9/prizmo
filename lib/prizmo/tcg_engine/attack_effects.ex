defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [active_card: 2]

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      require_basic_energy: 1,
      require_energy: 1,
      require_pokemon_card: 1,
      require_trainer_type: 2
    ]

  import Prizmo.TcgEngine.CardStore,
    only: [
      cards_in_zone: 3,
      deck_cards_for_player: 2,
      discard_cards_from_hand: 3,
      get_card: 2,
      get_cards: 2,
      move_deck_card_to_hand: 3,
      move_discard_card_to_hand: 3,
      next_hand_position_result: 2
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
    :search_pokemon_to_hand,
    :self_damage,
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

  defp discarded_energy_card_instance_ids(opts) do
    case Map.get(opts, :discarded_energy_card_instance_ids) ||
           Map.get(opts, "discarded_energy_card_instance_ids") do
      nil -> {:ok, []}
      ids when is_list(ids) -> {:ok, ids}
      _invalid -> {:error, :invalid_discarded_energy_card_instance_ids}
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

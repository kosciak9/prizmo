defmodule Prizmo.TcgEngine.CardPlay do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      require_basic_pokemon: 1,
      require_basic_energy: 1,
      require_night_stretcher_target: 1,
      require_non_rule_box_pokemon_card: 1,
      require_poffin_targets: 1,
      require_pokemon_card: 1,
      require_rare_candy_evolves_from: 2,
      require_special_energy: 1,
      require_stage_2_pokemon: 1,
      require_trainer_type: 2
    ]

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [
      require_ace_spec_available: 2,
      require_can_evolve_target: 2,
      require_card_owned_by_player: 2,
      require_card_zone: 2,
      evolve_action_for_zone: 1,
      require_evolution_allowed_this_turn: 1,
      require_in_play_pokemon_zone: 1,
      require_supporter_available: 2
    ]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.ChoiceValidator
  alias Prizmo.TcgEngine.CostRunner
  alias Prizmo.TcgEngine.EffectRunner
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.PendingEffects
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.TrainerPlay
  alias Prizmo.TcgEngine.TurnStore

  def require_playable_trainer_definition(
        %GamePlayer{} = player,
        %CardInstance{} = card,
        player_id,
        definition
      ) do
    with :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         {:ok, metadata} <- require_trainer_type(card.card_id, [definition.trainer_type]),
         :ok <- require_supporter_available(player, metadata),
         :ok <- require_ace_spec_available(player, metadata) do
      {:ok, metadata}
    end
  end

  def require_trainer_card(
        %GamePlayer{} = player,
        %CardInstance{} = card,
        player_id,
        expected_card_id,
        allowed_types
      ) do
    with :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         :ok <- Prizmo.TcgEngine.Requirements.require_card_id(card, expected_card_id),
         {:ok, metadata} <- require_trainer_type(card.card_id, allowed_types),
         :ok <- require_supporter_available(player, metadata) do
      require_ace_spec_available(player, metadata)
    end
  end

  def require_no_awaiting_pending_effect(game_id) do
    case PendingEffects.awaiting_for_game(game_id) do
      {:ok, nil} -> :ok
      {:ok, pending_effect} -> {:error, {:pending_effect_awaiting_prompt, pending_effect.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def required_choices_available?(
        cards,
        %CardInstance{} = action_card,
        definition,
        current_turn \\ nil
      )
      when is_list(cards) do
    Enum.all?(choice_steps(definition), fn choice_step ->
      case legal_choice_ids(
             cards,
             action_card.owner_player_id,
             action_card.id,
             choice_step,
             current_turn
           ) do
        {:ok, legal_choice_ids} ->
          required_choice_count_available?(legal_choice_ids, definition, choice_step.key)

        {:error, _reason} ->
          false
      end
    end)
  end

  def require_required_choices_available(game_id, player_id, action_card_id, definition)
      when is_binary(game_id) and is_binary(player_id) and is_binary(action_card_id) do
    with {:ok, current_turn} <- TurnStore.current_turn(game_id) do
      Enum.reduce_while(choice_steps(definition), :ok, fn choice_step, :ok ->
        with {:ok, legal_choice_ids} <-
               legal_choice_ids(
                 game_id,
                 player_id,
                 action_card_id,
                 definition,
                 choice_step.key,
                 current_turn
               ),
             :ok <- require_required_choice_count(legal_choice_ids, definition, choice_step.key) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  def resolve_play_card_costs(game, turn, player, card, metadata, definition, choices) do
    case CostRunner.first_cost(definition) do
      {:ok, cost} ->
        with {:ok, _event} <-
               write_event_and_snapshot(game.id, :cost_payment_started, player.player_id, %{
                 turn_id: turn.id,
                 card_instance_id: card.id,
                 card_id: card.card_id,
                 cost_key: cost.key
               }) do
          case CostRunner.selected_choice(choices, cost) do
            {:ok, discard_ids} ->
              complete_play_card_cost(
                game,
                turn,
                player,
                card,
                metadata,
                definition,
                choices,
                discard_ids
              )

            :missing ->
              suspend_play_card_for_choice(
                game,
                turn,
                player,
                card,
                definition,
                choices,
                :paying_cost,
                cost.key
              )
          end
        end

      {:error, :missing_cost_definition} ->
        with {:ok, _event} <- discard_played_trainer(game, player, card, metadata) do
          resolve_play_card_effects(game, turn, player, card, definition, choices)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def resume_pending_effect(%Game{} = game, pending_effect, choice_key, submitted_choice) do
    state = pending_effect.state || %{}

    with {:ok, player} <-
           PlayerStore.get_player(game.id, Map.fetch!(state, "player_id")),
         {:ok, card} <- CardStore.get_card(game.id, Map.fetch!(state, "card_instance_id")),
         {:ok, definition} <- EngineCardRegistry.fetch(card.card_id),
         {:ok, turn} <- TurnStore.current_turn(game.id),
         {:ok, metadata} <- require_trainer_type(card.card_id, [definition.trainer_type]) do
      choices =
        ChoiceValidator.put_choice(
          ChoiceValidator.from_pending_state(state),
          choice_key,
          submitted_choice
        )

      case Map.fetch!(state, "phase") do
        "paying_cost" ->
          {:ok, cost} = CostRunner.first_cost(definition)
          {:ok, discard_ids} = CostRunner.selected_choice(choices, cost)

          complete_play_card_cost(
            game,
            turn,
            player,
            card,
            metadata,
            definition,
            choices,
            discard_ids
          )

        "resolving_effect" ->
          {:ok, effect} = EffectRunner.first_effect(definition)
          {:ok, target_ids} = EffectRunner.selected_choice(choices, effect)
          complete_play_card_effect(game, turn, player, card, effect, target_ids)
      end
    end
  end

  defp complete_play_card_cost(
         game,
         turn,
         player,
         card,
         metadata,
         definition,
         choices,
         discard_ids
       ) do
    with {:ok, cost} <- CostRunner.first_cost(definition),
         {:ok, discard_cards} <-
           validate_discard_from_hand_cost(game.id, player.player_id, card.id, cost, discard_ids),
         {:ok, _discarded_cards} <-
           CardStore.discard_cards_from_hand(game.id, player.player_id, discard_cards),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :cost_payment,
             source: EventPayloads.card_source(card),
             cost_key: cost.key,
             cards: EventPayloads.moved_cards(discard_cards, :hand, :discard)
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cost_paid, player.player_id, %{
             turn_id: turn.id,
             card_instance_id: card.id,
             card_id: card.card_id,
             cost_key: cost.key
           }),
         {:ok, _event} <- discard_played_trainer(game, player, card, metadata) do
      resolve_play_card_effects(game, turn, player, card, definition, choices)
    end
  end

  defp discard_played_trainer(game, player, card, metadata) do
    with {:ok, discarded_trainer} <-
           TrainerPlay.discard_trainer_card(game, player, card, metadata) do
      write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
        reason: :played_trainer_discarded,
        source: EventPayloads.card_source(card),
        cards: EventPayloads.moved_cards([discarded_trainer], :hand, :discard)
      })
    end
  end

  defp resolve_play_card_effects(game, turn, player, card, definition, choices) do
    with {:ok, effect} <- EffectRunner.first_effect(definition),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :effect_started, player.player_id, %{
             turn_id: turn.id,
             source: EventPayloads.card_source(card),
             effect_key: effect.key
           }) do
      case EffectRunner.selected_choice(choices, effect) do
        {:ok, target_ids} ->
          complete_play_card_effect(game, turn, player, card, effect, target_ids)

        :missing ->
          suspend_play_card_for_choice(
            game,
            turn,
            player,
            card,
            definition,
            choices,
            :resolving_effect,
            effect.key
          )
      end
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :search_deck} = effect,
         target_ids
       ) do
    with {:ok, target_cards} <-
           validate_search_deck_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_targets} <- move_search_targets(game, turn, player, effect, target_cards),
         {:ok, _event} <-
           write_event_and_snapshot(
             game.id,
             :cards_moved,
             player.player_id,
             search_cards_moved_payload(card, effect, moved_targets)
           ),
         {:ok, _event} <- maybe_shuffle_and_write_deck_shuffled(game, turn, player, card, effect) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :search_top_deck} = effect,
         target_ids
       ) do
    with {:ok, target_cards} <-
           validate_search_top_deck_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_targets} <- move_search_targets(game, turn, player, effect, target_cards),
         {:ok, _event} <-
           write_event_and_snapshot(
             game.id,
             :cards_moved,
             player.player_id,
             search_cards_moved_payload(card, effect, moved_targets)
           ),
         {:ok, _event} <- maybe_shuffle_and_write_deck_shuffled(game, turn, player, card, effect) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :search_basic_energy_split_hand_attach} = effect,
         target_ids
       ) do
    with {:ok, {hand_energy_card, attach_energy_card, target_card}} <-
           validate_crispin_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_hand_energy_card} <-
           CardStore.move_deck_card_to_hand(game.id, player.player_id, hand_energy_card),
         {:ok, {moved_attached_energy_card, recovered_special_condition}} <-
           maybe_attach_crispin_energy(game, attach_energy_card, target_card),
         {:ok, _event} <-
           write_event_and_snapshot(
             game.id,
             :cards_moved,
             player.player_id,
             maybe_put(
               %{
                 reason: :effect_resolution,
                 source: EventPayloads.card_source(card),
                 effect_key: effect.key,
                 cards:
                   crispin_moved_card_payloads(
                     moved_hand_energy_card,
                     moved_attached_energy_card,
                     target_card
                   )
               },
               :recovered_special_condition,
               recovered_special_condition
             )
           ),
         {:ok, _event} <- maybe_shuffle_and_write_deck_shuffled(game, turn, player, card, effect) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :recover_discard_to_hand} = effect,
         target_ids
       ) do
    with {:ok, target_cards} <-
           validate_recover_discard_to_hand_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_targets} <-
           move_discard_cards_to_hand(game.id, player.player_id, target_cards),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards: EventPayloads.moved_cards(moved_targets, :discard, :hand)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :rare_candy_evolve} = effect,
         target_ids
       ) do
    with {:ok, {stage_2_card, target_basic_card}} <-
           validate_rare_candy_effect(game.id, player.player_id, turn, effect, target_ids),
         target_position = target_basic_card.position,
         target_zone = target_basic_card.zone,
         evolve_action = evolve_action_for_zone(target_zone),
         {:ok, evolved_card} <-
           update(stage_2_card, evolve_action, %{
             evolves_from_card_instance_id: target_basic_card.id,
             position: target_position,
             damage: target_basic_card.damage,
             status: nil,
             turn_entered_play: turn.turn_number
           }),
         {:ok, reparented_attachments} <-
           CardStore.reparent_attached_cards(game.id, target_basic_card.id, evolved_card.id),
         {:ok, evolved_under_card} <-
           update(target_basic_card, :evolve_under, %{
             attached_to_card_instance_id: evolved_card.id,
             damage: 0,
             status: nil,
             position: 1
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards:
               rare_candy_evolution_payloads(
                 evolved_card,
                 evolved_under_card,
                 reparented_attachments,
                 target_zone,
                 target_basic_card.id
               )
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :move_basic_energy_between_own_pokemon} = effect,
         target_ids
       ) do
    with {:ok, {energy_card, target_card}} <-
           validate_energy_switch_effect(game.id, player.player_id, effect, target_ids),
         source_target_card_instance_id = energy_card.attached_to_card_instance_id,
         {:ok, position} <- CardStore.next_attachment_position(game.id, target_card.id),
         {:ok, moved_energy_card} <-
           update(energy_card, :reparent_attachment, %{
             attached_to_card_instance_id: target_card.id,
             position: position
           }),
         {:ok, recovered_special_condition} <-
           StadiumEffects.recover_special_condition(game.id, target_card),
         {:ok, _event} <-
           write_event_and_snapshot(
             game.id,
             :cards_moved,
             player.player_id,
             maybe_put(
               %{
                 reason: :effect_resolution,
                 source: EventPayloads.card_source(card),
                 effect_key: effect.key,
                 cards: [
                   energy_switch_move_payload(
                     moved_energy_card,
                     source_target_card_instance_id,
                     target_card.id
                   )
                 ]
               },
               :recovered_special_condition,
               recovered_special_condition
             )
           ) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :switch_opponent_bench_to_active} = effect,
         target_ids
       ) do
    with {:ok, [target_bench_card]} <-
           validate_opponent_bench_switch_effect(game.id, player.player_id, effect, target_ids),
         {:ok, opponent_active_card} <- opponent_active_card(game.id, player.player_id),
         bench_position = target_bench_card.position,
         {:ok, moved_active_card} <-
           update(opponent_active_card, :move_active_to_bench, %{
             position: bench_position,
             status: nil
           }),
         {:ok, moved_target_card} <-
           update(target_bench_card, :promote_to_active, %{position: 1, status: nil}),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards: opponent_switch_payload(moved_active_card, moved_target_card)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :discard_opponent_special_energy} = effect,
         target_ids
       ) do
    with {:ok, [target_energy_card]} <-
           validate_opponent_special_energy_discard_effect(
             game.id,
             player.player_id,
             effect,
             target_ids
           ),
         {:ok, discarded_energy_card} <- discard_attached_energy_card(game, target_energy_card),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: discarded_energy_card.owner_player_id,
             cards: EventPayloads.moved_cards([discarded_energy_card], :attached, :discard)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :shuffle_hand_into_deck_then_draw} = effect,
         _target_ids
       ) do
    with :ok <- require_can_draw_after_hand_shuffle(game, player, effect),
         {:ok, _summary} <-
           shuffle_hand_into_deck_then_draw_for_player(game, turn, player, player, card, effect) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :shuffle_each_player_hand_into_deck_then_draw} = effect,
         _target_ids
       ) do
    with {:ok, affected_players} <- PlayerStore.list_players(game.id),
         :ok <- require_each_player_can_draw_after_hand_shuffle(game, affected_players, effect),
         {:ok, _summaries} <-
           shuffle_each_player_hand_into_deck_then_draw(
             game,
             turn,
             player,
             card,
             effect,
             affected_players
           ) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(_game, _turn, _player, _card, effect, _target_ids) do
    {:error, {:unsupported_card_effect, effect.type}}
  end

  defp complete_play_card_resolution(game, turn, player, card, effect) do
    with {:ok, _event} <-
           write_event_and_snapshot(game.id, :effect_completed, player.player_id, %{
             turn_id: turn.id,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             status: :completed
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :card_play_completed, player.player_id, %{
             turn_id: turn.id,
             card_instance_id: card.id,
             card_id: card.card_id,
             result: :completed
           }),
         :ok <- PendingEffects.complete_resolving_for_game(game.id) do
      GameStore.get_game(game.id)
    end
  end

  defp suspend_play_card_for_choice(
         game,
         turn,
         player,
         card,
         definition,
         choices,
         phase,
         choice_key
       ) do
    with {:ok, legal_choice_ids} <-
           legal_choice_ids(game.id, player.player_id, card.id, definition, choice_key, turn),
         :ok <- require_required_choice_count(legal_choice_ids, definition, choice_key),
         {min, max} <-
           prompt_choice_bounds(
             game.id,
             player.player_id,
             definition,
             choice_key,
             legal_choice_ids
           ),
         {:ok, pending_effect} <-
           PendingEffects.upsert_awaiting(
             game,
             player,
             card,
             choices,
             phase,
             choice_key
           ),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :pending_effect_created, player.player_id, %{
             pending_effect_id: pending_effect.id,
             source: EventPayloads.card_source(card),
             phase: phase,
             choice_key: choice_key
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game.id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: player.player_id,
             payload: prompt_payload(game.id, choice_key, legal_choice_ids, min, max)
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :prompt_created, player.player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             choice_key: choice_key,
             prompt_type: :select_cards
           }) do
      GameStore.get_game(game.id)
    end
  end

  defp validate_discard_from_hand_cost(game_id, player_id, action_card_id, cost, discard_ids) do
    with :ok <- CostRunner.validate_discard_from_hand_selection(cost, action_card_id, discard_ids),
         {:ok, discard_cards} <- CardStore.get_cards(game_id, discard_ids),
         :ok <- require_all_owned_in_zone(discard_cards, player_id, :hand) do
      {:ok, discard_cards}
    end
  end

  defp validate_search_deck_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_search_deck_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_search_filters(target_cards, effect.params.filter),
         :ok <-
           require_required_search_groups(target_cards, Map.get(effect.params, :required_groups)) do
      {:ok, target_cards}
    end
  end

  defp validate_search_top_deck_effect(game_id, player_id, effect, target_ids) do
    look_count = Map.fetch!(effect.params, :look_count)

    with {:ok, target_ids} <-
           EffectRunner.validate_choice_selection(
             effect,
             target_ids,
             :wrong_search_top_deck_target_count
           ),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_in_top_deck(game_id, player_id, target_cards, look_count, effect.key),
         :ok <- require_all_search_filters(target_cards, effect.params.filter) do
      {:ok, target_cards}
    end
  end

  defp validate_crispin_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids) do
      selected_crispin_cards(target_cards, player_id)
    end
  end

  defp validate_opponent_bench_switch_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_opponent_cards(target_cards, player_id),
         :ok <- require_all_in_zone(target_cards, :bench) do
      {:ok, target_cards}
    end
  end

  defp validate_opponent_special_energy_discard_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_opponent_cards(target_cards, player_id),
         :ok <- require_all_in_zone(target_cards, :attached),
         :ok <- require_all_special_energy(target_cards) do
      {:ok, target_cards}
    end
  end

  defp validate_energy_switch_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         {:ok, energy_card} <- selected_energy_switch_source(target_cards, player_id),
         {:ok, target_card} <- selected_energy_switch_target(target_cards, player_id),
         :ok <- require_energy_switch_target_changed(energy_card, target_card) do
      {:ok, {energy_card, target_card}}
    end
  end

  defp validate_recover_discard_to_hand_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :discard),
         :ok <- require_all_recover_discard_to_hand_filters(target_cards, effect.params.filter) do
      {:ok, target_cards}
    end
  end

  defp validate_rare_candy_effect(game_id, player_id, turn, effect, target_ids) do
    with :ok <- require_evolution_allowed_this_turn(turn),
         {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         {:ok, {stage_2_card, target_basic_card}} <-
           selected_rare_candy_cards(target_cards, player_id, turn.turn_number),
         :ok <- require_rare_candy_evolves_from(stage_2_card.card_id, target_basic_card.card_id) do
      {:ok, {stage_2_card, target_basic_card}}
    end
  end

  defp move_search_targets(game, _turn, player, %{params: %{destination: :hand}}, target_cards) do
    target_cards
    |> Enum.map(&CardStore.move_deck_card_to_hand(game.id, player.player_id, &1))
    |> collect_results()
  end

  defp move_search_targets(game, turn, player, %{params: %{destination: :bench}}, target_cards) do
    CardStore.move_deck_cards_to_bench(game.id, player.player_id, target_cards, turn.turn_number)
  end

  defp move_search_targets(_game, _turn, _player, effect, _target_cards) do
    {:error, {:unsupported_search_deck_destination, Map.get(effect.params, :destination)}}
  end

  defp move_discard_cards_to_hand(game_id, player_id, target_cards) do
    target_cards
    |> Enum.map(&CardStore.move_discard_card_to_hand(game_id, player_id, &1))
    |> collect_results()
  end

  defp search_effect_destination_zone(%{params: %{destination: :bench}}), do: :bench
  defp search_effect_destination_zone(%{params: %{destination: :hand}}), do: :hand

  defp effect_choice_ids(cards, player_id, choice_step, current_turn)

  defp effect_choice_ids(cards, player_id, %{type: :search_deck} = choice_step, _current_turn) do
    cards
    |> search_deck_choice_cards(player_id, choice_step)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(cards, player_id, %{type: :search_top_deck} = choice_step, _current_turn) do
    cards
    |> search_top_deck_choice_cards(player_id, choice_step)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :search_basic_energy_split_hand_attach},
         _current_turn
       ) do
    cards
    |> crispin_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :switch_opponent_bench_to_active},
         _current_turn
       ) do
    cards
    |> opponent_bench_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :discard_opponent_special_energy},
         _current_turn
       ) do
    cards
    |> opponent_special_energy_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :move_basic_energy_between_own_pokemon},
         _current_turn
       ) do
    cards
    |> energy_switch_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :recover_discard_to_hand} = choice_step,
         _current_turn
       ) do
    cards
    |> recover_discard_to_hand_choice_cards(player_id, choice_step)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(cards, player_id, %{type: :rare_candy_evolve}, current_turn) do
    cards
    |> rare_candy_choice_cards(player_id, current_turn)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(_cards, _player_id, choice_step, _current_turn) do
    {:error, {:unsupported_choice_step, choice_step.key, choice_step.type}}
  end

  defp legal_choice_ids(game_id, player_id, action_card_id, definition, choice_key, current_turn) do
    cond do
      Enum.any?(definition.costs, &(&1.key == choice_key)) ->
        with {:ok, hand} <- CardStore.cards_in_zone(game_id, player_id, :hand) do
          {:ok, hand |> Enum.reject(&(&1.id == action_card_id)) |> Enum.map(& &1.id)}
        end

      Enum.any?(definition.effects, &(&1.key == choice_key)) ->
        with {:ok, cards} <- CardStore.list_cards(game_id) do
          effect_choice_ids(cards, player_id, effect_step(definition, choice_key), current_turn)
        end

      true ->
        {:error, {:unknown_choice_key, choice_key}}
    end
  end

  defp legal_choice_ids(cards, player_id, action_card_id, choice_step, current_turn) do
    case choice_step.type do
      :discard_from_hand ->
        cards
        |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :hand))
        |> Enum.reject(&(&1.id == action_card_id))
        |> Enum.map(& &1.id)
        |> then(&{:ok, &1})

      type
      when type in [
             :search_deck,
             :search_top_deck,
             :search_basic_energy_split_hand_attach,
             :switch_opponent_bench_to_active,
             :discard_opponent_special_energy,
             :move_basic_energy_between_own_pokemon,
             :recover_discard_to_hand,
             :rare_candy_evolve
           ] ->
        effect_choice_ids(cards, player_id, choice_step, current_turn)

      _other ->
        {:error, {:unsupported_choice_step, choice_step.key, choice_step.type}}
    end
  end

  defp choice_steps(definition) do
    definition.costs ++ Enum.filter(definition.effects, &EffectRunner.requires_choice?/1)
  end

  defp require_required_choice_count(legal_choice_ids, definition, choice_key) do
    if required_choice_count_available?(legal_choice_ids, definition, choice_key) do
      :ok
    else
      {:error,
       {:not_enough_legal_choices, choice_key, ChoiceValidator.count_for(definition, choice_key),
        length(legal_choice_ids)}}
    end
  end

  defp required_choice_count_available?(legal_choice_ids, definition, choice_key) do
    length(legal_choice_ids) >= ChoiceValidator.count_for(definition, choice_key)
  end

  defp prompt_choice_bounds(game_id, player_id, definition, choice_key, legal_choice_ids) do
    min = ChoiceValidator.count_for(definition, choice_key)

    max =
      definition
      |> ChoiceValidator.max_count_for(choice_key)
      |> min(length(legal_choice_ids))
      |> maybe_cap_bench_choice_max(game_id, player_id, effect_step(definition, choice_key))
      |> maybe_cap_crispin_choice_max(
        game_id,
        effect_step(definition, choice_key),
        legal_choice_ids
      )

    {min, max}
  end

  defp maybe_cap_bench_choice_max(max, game_id, player_id, %{params: %{destination: :bench}}) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} -> min(max, bench_space(cards, player_id))
      {:error, _reason} -> max
    end
  end

  defp maybe_cap_bench_choice_max(max, _game_id, _player_id, _choice_step), do: max

  defp maybe_cap_crispin_choice_max(
         max,
         game_id,
         %{type: :search_basic_energy_split_hand_attach},
         legal_choice_ids
       ) do
    case CardStore.get_cards(game_id, legal_choice_ids) do
      {:ok, cards} ->
        if Enum.any?(cards, &(&1.zone in [:active, :bench])) do
          max
        else
          min(max, 1)
        end

      {:error, _reason} ->
        max
    end
  end

  defp maybe_cap_crispin_choice_max(max, _game_id, _choice_step, _legal_choice_ids), do: max

  defp search_deck_choice_cards(cards, player_id, choice_step) do
    choices =
      cards
      |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :deck))
      |> Enum.filter(&matches_search_filter?(&1, choice_step.params.filter))
      |> maybe_hide_when_bench_full(cards, player_id, choice_step)

    if required_search_groups_available?(choices, Map.get(choice_step.params, :required_groups)) do
      choices
    else
      []
    end
  end

  defp search_top_deck_choice_cards(cards, player_id, choice_step) do
    choices =
      cards
      |> top_deck_cards(player_id, Map.fetch!(choice_step.params, :look_count))
      |> Enum.filter(&matches_search_filter?(&1, choice_step.params.filter))

    if required_search_groups_available?(choices, Map.get(choice_step.params, :required_groups)) do
      choices
    else
      []
    end
  end

  defp top_deck_cards(cards, player_id, look_count) do
    cards
    |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :deck))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
    |> Enum.take(look_count)
  end

  defp opponent_bench_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :bench))
    |> Enum.sort_by(&{&1.owner_player_id, &1.position, &1.instance_id})
  end

  defp crispin_choice_cards(cards, player_id) do
    energy_cards = crispin_basic_energy_choice_cards(cards, player_id)
    target_cards = crispin_target_choice_cards(cards, player_id)

    legal_target_cards =
      if crispin_has_different_energy_types?(energy_cards) and target_cards != [] do
        target_cards
      else
        []
      end

    case energy_cards do
      [] -> []
      legal_energy_cards -> legal_energy_cards ++ legal_target_cards
    end
  end

  defp crispin_basic_energy_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&crispin_basic_energy_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp crispin_target_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&crispin_target_card?(&1, player_id))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp opponent_special_energy_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(
      &(&1.owner_player_id != player_id and &1.zone == :attached and special_energy_card?(&1))
    )
    |> Enum.sort_by(
      &{&1.owner_player_id, &1.attached_to_card_instance_id, &1.position, &1.instance_id}
    )
  end

  defp energy_switch_choice_cards(cards, player_id) do
    source_cards = energy_switch_source_cards(cards, player_id)
    target_cards = energy_switch_target_cards(cards, player_id)

    legal_source_cards =
      Enum.filter(source_cards, fn source_card ->
        Enum.any?(target_cards, &(&1.id != source_card.attached_to_card_instance_id))
      end)

    legal_target_cards =
      Enum.filter(target_cards, fn target_card ->
        Enum.any?(source_cards, &(&1.attached_to_card_instance_id != target_card.id))
      end)

    if Enum.empty?(legal_source_cards) or Enum.empty?(legal_target_cards) do
      []
    else
      legal_source_cards ++ legal_target_cards
    end
  end

  defp recover_discard_to_hand_choice_cards(cards, player_id, choice_step) do
    cards
    |> Enum.filter(
      &(&1.owner_player_id == player_id and &1.zone == :discard and
          matches_recover_discard_to_hand_filter?(&1, choice_step.params.filter))
    )
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp rare_candy_choice_cards(cards, player_id, %{turn_number: turn_number})
       when turn_number > 1 do
    stage_2_cards = rare_candy_stage_2_cards(cards, player_id)
    target_cards = rare_candy_target_cards(cards, player_id, turn_number)

    legal_stage_2_cards =
      Enum.filter(stage_2_cards, fn stage_2_card ->
        Enum.any?(target_cards, &rare_candy_evolves_from?(stage_2_card, &1))
      end)

    legal_target_cards =
      Enum.filter(target_cards, fn target_card ->
        Enum.any?(stage_2_cards, &rare_candy_evolves_from?(&1, target_card))
      end)

    legal_stage_2_cards ++ legal_target_cards
  end

  defp rare_candy_choice_cards(_cards, _player_id, _current_turn), do: []

  defp rare_candy_stage_2_cards(cards, player_id) do
    cards
    |> Enum.filter(&rare_candy_stage_2_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp rare_candy_target_cards(cards, player_id, turn_number) do
    cards
    |> Enum.filter(&rare_candy_target_card?(&1, player_id, turn_number))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp energy_switch_source_cards(cards, player_id) do
    cards
    |> Enum.filter(&energy_switch_source_card?(&1, player_id))
    |> Enum.sort_by(&{&1.attached_to_card_instance_id, &1.position, &1.instance_id})
  end

  defp energy_switch_target_cards(cards, player_id) do
    cards
    |> Enum.filter(&energy_switch_target_card?(&1, player_id))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp maybe_hide_when_bench_full(choices, cards, player_id, %{params: %{destination: :bench}}) do
    if bench_space(cards, player_id) > 0, do: choices, else: []
  end

  defp maybe_hide_when_bench_full(choices, _cards, _player_id, _choice_step), do: choices

  defp bench_space(cards, player_id) do
    occupied = Enum.count(cards, &(&1.owner_player_id == player_id and &1.zone == :bench))
    max(5 - occupied, 0)
  end

  defp matches_search_filter?(%CardInstance{} = card, filter) do
    require_search_filter(card, filter) == :ok
  end

  defp require_all_search_filters(cards, filter) do
    cards
    |> Enum.map(&require_search_filter(&1, filter))
    |> collect_ok_results()
  end

  defp require_all_in_top_deck(_game_id, _player_id, [], _look_count, _effect_key), do: :ok

  defp require_all_in_top_deck(game_id, player_id, target_cards, look_count, effect_key) do
    with {:ok, deck_cards} <- CardStore.cards_in_zone(game_id, player_id, :deck) do
      top_card_ids = deck_cards |> Enum.take(look_count) |> MapSet.new(& &1.id)

      if Enum.all?(target_cards, &MapSet.member?(top_card_ids, &1.id)) do
        :ok
      else
        {:error, {:target_not_in_top_deck, effect_key, look_count}}
      end
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, stage: :basic, max_hp: 70}) do
    require_poffin_targets([card])
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, stage: stage}) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :pokemon, stage: ^stage}} ->
        :ok

      {:ok, %{supertype: :pokemon, stage: actual_stage}} ->
        {:error, {:wrong_pokemon_stage, card.card_id, actual_stage, stage}}

      {:ok, metadata} ->
        {:error, {:not_pokemon, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, stages: stages})
       when is_list(stages) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :pokemon, stage: stage}} ->
        if stage in stages do
          :ok
        else
          {:error, {:wrong_pokemon_stage, card.card_id, stage, stages}}
        end

      {:ok, metadata} ->
        {:error, {:not_pokemon, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, rule_box?: false}) do
    require_non_rule_box_pokemon_card(card.card_id)
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, type: type}) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :pokemon, types: types}} when is_list(types) ->
        if type in types do
          :ok
        else
          {:error, {:wrong_pokemon_type, card.card_id, types, type}}
        end

      {:ok, %{supertype: :pokemon, type: ^type}} ->
        :ok

      {:ok, %{supertype: :pokemon, type: actual_type}} ->
        {:error, {:wrong_pokemon_type, card.card_id, actual_type, type}}

      {:ok, metadata} ->
        {:error, {:not_pokemon, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon}) do
    require_pokemon_card(card.card_id)
  end

  defp require_search_filter(%CardInstance{} = card, %{
         kind: :energy,
         energy_type: :basic,
         provides: provides
       }) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, energy_type: :basic, provides: energy_provides}}
      when is_list(energy_provides) ->
        if provides in energy_provides do
          :ok
        else
          {:error, {:wrong_energy_provider, card.card_id, energy_provides, provides}}
        end

      {:ok, %{supertype: :energy, energy_type: energy_type}} ->
        {:error, {:wrong_energy_type, card.card_id, energy_type, :basic}}

      {:ok, metadata} ->
        {:error, {:not_energy, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{
         kind: :trainer,
         trainer_type: trainer_type,
         name_contains: name_fragment
       })
       when is_binary(name_fragment) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :trainer, trainer_type: ^trainer_type, name: name}}
      when is_binary(name) ->
        if String.contains?(name, name_fragment) do
          :ok
        else
          {:error, {:trainer_name_missing_fragment, card.card_id, name_fragment}}
        end

      {:ok, %{supertype: :trainer, trainer_type: actual_type}} ->
        {:error, {:wrong_trainer_type, card.card_id, actual_type, trainer_type}}

      {:ok, metadata} ->
        {:error, {:not_trainer, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :trainer, trainer_type: trainer_type}) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :trainer, trainer_type: ^trainer_type}} ->
        :ok

      {:ok, %{supertype: :trainer, trainer_type: actual_type}} ->
        {:error, {:wrong_trainer_type, card.card_id, actual_type, trainer_type}}

      {:ok, metadata} ->
        {:error, {:not_trainer, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :energy}) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy}} -> :ok
      {:ok, metadata} -> {:error, {:not_energy, metadata.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{any: filters}) when is_list(filters) do
    if Enum.any?(filters, &(require_search_filter(card, &1) == :ok)) do
      :ok
    else
      {:error, {:no_matching_search_filter, card.card_id}}
    end
  end

  defp require_search_filter(_card, _filter), do: {:error, :unsupported_search_filter}

  defp require_required_search_groups(_target_cards, nil), do: :ok

  defp require_required_search_groups(target_cards, required_groups)
       when is_list(required_groups) do
    required_groups
    |> Enum.map(fn group ->
      expected_count = Map.get(group, :count, 1)
      actual_count = Enum.count(target_cards, &matches_search_filter?(&1, group.filter))

      if actual_count == expected_count do
        :ok
      else
        {:error, {:wrong_search_group_count, group.filter, actual_count, expected_count}}
      end
    end)
    |> collect_ok_results()
  end

  defp required_search_groups_available?(_choices, nil), do: true

  defp required_search_groups_available?(choices, required_groups)
       when is_list(required_groups) do
    Enum.all?(required_groups, fn group ->
      expected_count = Map.get(group, :count, 1)
      Enum.count(choices, &matches_search_filter?(&1, group.filter)) >= expected_count
    end)
  end

  defp special_energy_card?(%CardInstance{card_id: card_id}) do
    match?({:ok, %{supertype: :energy, energy_type: :special}}, CardCatalog.fetch(card_id))
  end

  defp crispin_basic_energy_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :deck and
      require_basic_energy(card.card_id) == :ok and
      match?({:ok, _type}, basic_energy_type(card))
  end

  defp crispin_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_pokemon_card(card.card_id) == :ok
  end

  defp crispin_has_different_energy_types?(energy_cards) do
    energy_cards
    |> Enum.map(&basic_energy_type/1)
    |> Enum.flat_map(fn
      {:ok, type} -> [type]
      {:error, _reason} -> []
    end)
    |> Enum.uniq()
    |> length()
    |> Kernel.>=(2)
  end

  defp basic_energy_type(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :energy, energy_type: :basic, provides: [type | _types]}}
      when is_atom(type) ->
        {:ok, type}

      {:ok, %{supertype: :energy, energy_type: :basic}} ->
        {:error, {:unknown_basic_energy_type, card_id}}

      {:ok, %{supertype: :energy}} ->
        {:error, :not_basic_energy}

      {:ok, _metadata} ->
        {:error, :not_energy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp selected_crispin_cards(cards, player_id) do
    energy_cards = Enum.filter(cards, &crispin_basic_energy_card?(&1, player_id))
    target_cards = Enum.filter(cards, &crispin_target_card?(&1, player_id))

    case {energy_cards, target_cards} do
      {[hand_energy_card], []} ->
        {:ok, {hand_energy_card, nil, nil}}

      {[hand_energy_card, attach_energy_card], [target_card]} ->
        with :ok <- require_different_basic_energy_types(hand_energy_card, attach_energy_card) do
          {:ok, {hand_energy_card, attach_energy_card, target_card}}
        end

      {[], _target_cards} ->
        {:error, :missing_crispin_energy_choices}

      {[_energy_card], [_target_card]} ->
        {:error, :crispin_single_energy_choice_cannot_attach}

      {[_energy_card], target_cards} when length(target_cards) > 1 ->
        {:error, {:too_many_crispin_target_pokemon, length(target_cards)}}

      {energy_cards, _target_cards} when length(energy_cards) > 2 ->
        {:error, {:too_many_crispin_energy_choices, length(energy_cards)}}

      {[_energy_card, _attach_energy_card], []} ->
        {:error, :missing_crispin_target_pokemon}

      {[_energy_card, _attach_energy_card], target_cards} when length(target_cards) > 1 ->
        {:error, {:too_many_crispin_target_pokemon, length(target_cards)}}

      _other ->
        {:error, :invalid_crispin_choices}
    end
  end

  defp selected_rare_candy_cards(cards, player_id, turn_number) do
    stage_2_cards = Enum.filter(cards, &rare_candy_stage_2_card?(&1, player_id))
    target_cards = Enum.filter(cards, &rare_candy_target_card?(&1, player_id, turn_number))

    case {stage_2_cards, target_cards} do
      {[stage_2_card], [target_card]} ->
        {:ok, {stage_2_card, target_card}}

      {[], [_target_card]} ->
        {:error, :missing_rare_candy_stage_2_choice}

      {[_stage_2_card], []} ->
        {:error, :missing_rare_candy_basic_target}

      {stage_2_cards, [_target_card]} when length(stage_2_cards) > 1 ->
        {:error, {:too_many_rare_candy_stage_2_choices, length(stage_2_cards)}}

      {[_stage_2_card], target_cards} when length(target_cards) > 1 ->
        {:error, {:too_many_rare_candy_basic_targets, length(target_cards)}}

      _other ->
        {:error, :invalid_rare_candy_choices}
    end
  end

  defp rare_candy_stage_2_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :hand and
      require_stage_2_pokemon(card.card_id) == :ok
  end

  defp rare_candy_target_card?(%CardInstance{} = card, player_id, turn_number) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_basic_pokemon(card.card_id) == :ok and
      require_in_play_pokemon_zone(card) == :ok and
      require_can_evolve_target(card, turn_number) == :ok
  end

  defp rare_candy_evolves_from?(%CardInstance{} = stage_2_card, %CardInstance{} = target_card) do
    require_rare_candy_evolves_from(stage_2_card.card_id, target_card.card_id) == :ok
  end

  defp require_different_basic_energy_types(hand_energy_card, attach_energy_card) do
    case {basic_energy_type(hand_energy_card), basic_energy_type(attach_energy_card)} do
      {{:ok, hand_type}, {:ok, attach_type}} when hand_type == attach_type ->
        {:error, {:crispin_energy_types_must_differ, hand_type}}

      {{:ok, _hand_type}, {:ok, _attach_type}} ->
        :ok

      {{:error, reason}, _other} ->
        {:error, reason}

      {_other, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp energy_switch_source_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :attached and
      is_binary(card.attached_to_card_instance_id) and require_basic_energy(card.card_id) == :ok
  end

  defp energy_switch_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_pokemon_card(card.card_id) == :ok
  end

  defp selected_energy_switch_source(cards, player_id) do
    case Enum.filter(cards, &energy_switch_source_card?(&1, player_id)) do
      [energy_card] -> {:ok, energy_card}
      [] -> {:error, :missing_energy_switch_source}
      _multiple -> {:error, :ambiguous_energy_switch_source}
    end
  end

  defp selected_energy_switch_target(cards, player_id) do
    case Enum.filter(cards, &energy_switch_target_card?(&1, player_id)) do
      [target_card] -> {:ok, target_card}
      [] -> {:error, :missing_energy_switch_target}
      _multiple -> {:error, :ambiguous_energy_switch_target}
    end
  end

  defp require_energy_switch_target_changed(
         %CardInstance{attached_to_card_instance_id: target_card_instance_id},
         %CardInstance{id: target_card_instance_id}
       ) do
    {:error, :energy_switch_target_must_be_different_pokemon}
  end

  defp require_energy_switch_target_changed(%CardInstance{}, %CardInstance{}), do: :ok

  defp require_all_special_energy(cards) do
    cards
    |> Enum.map(&require_special_energy(&1.card_id))
    |> collect_ok_results()
  end

  defp matches_recover_discard_to_hand_filter?(%CardInstance{} = card, filter) do
    require_recover_discard_to_hand_filter(card, filter) == :ok
  end

  defp require_all_recover_discard_to_hand_filters(cards, filter) do
    cards
    |> Enum.map(&require_recover_discard_to_hand_filter(&1, filter))
    |> collect_ok_results()
  end

  defp require_recover_discard_to_hand_filter(%CardInstance{} = card, %{any: filters})
       when is_list(filters) do
    if Enum.any?(filters, &(require_recover_discard_to_hand_filter(card, &1) == :ok)) do
      :ok
    else
      {:error, {:no_matching_recover_discard_filter, card.card_id}}
    end
  end

  defp require_recover_discard_to_hand_filter(%CardInstance{} = card, %{
         kind: :pokemon,
         rule_box?: false
       }) do
    require_non_rule_box_pokemon_card(card.card_id)
  end

  defp require_recover_discard_to_hand_filter(%CardInstance{} = card, %{kind: :pokemon}) do
    require_pokemon_card(card.card_id)
  end

  defp require_recover_discard_to_hand_filter(%CardInstance{} = card, %{
         kind: :energy,
         energy_type: :basic
       }) do
    require_basic_energy(card.card_id)
  end

  defp require_recover_discard_to_hand_filter(%CardInstance{} = card, _filter) do
    require_night_stretcher_target(card.card_id)
  end

  defp discard_attached_energy_card(game, %CardInstance{} = card) do
    with {:ok, position} <- CardStore.next_discard_position(game.id, card.owner_player_id) do
      update(card, :discard, %{position: position, attached_to_card_instance_id: nil})
    end
  end

  defp maybe_attach_crispin_energy(_game, nil, nil), do: {:ok, {nil, nil}}

  defp maybe_attach_crispin_energy(
         %Game{} = game,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card
       ) do
    with {:ok, position} <- CardStore.next_attachment_position(game.id, target_card.id),
         {:ok, attached_energy} <-
           update(energy_card, :attach_from_deck, %{
             attached_to_card_instance_id: target_card.id,
             position: position
           }),
         {:ok, recovered_special_condition} <-
           StadiumEffects.recover_special_condition(game.id, target_card) do
      {:ok, {attached_energy, recovered_special_condition}}
    end
  end

  defp crispin_moved_card_payloads(moved_hand_energy_card, nil, nil) do
    [moved_card_payload(moved_hand_energy_card, :deck, :hand)]
  end

  defp crispin_moved_card_payloads(
         moved_hand_energy_card,
         moved_attached_energy_card,
         %CardInstance{} = target_card
       ) do
    [
      moved_card_payload(moved_hand_energy_card, :deck, :hand),
      moved_card_payload(moved_attached_energy_card, :deck, :attached,
        to_attached_to_card_instance_id: target_card.id
      )
    ]
  end

  defp rare_candy_evolution_payloads(
         evolved_card,
         evolved_under_card,
         reparented_attachments,
         target_zone,
         source_target_card_instance_id
       ) do
    [
      moved_card_payload(evolved_card, :hand, target_zone,
        evolves_from_card_instance_id: evolved_under_card.id,
        preserved_damage: evolved_card.damage,
        cleared_status: true
      ),
      moved_card_payload(evolved_under_card, target_zone, :attached,
        to_attached_to_card_instance_id: evolved_card.id
      )
    ] ++
      Enum.map(reparented_attachments, fn attachment ->
        moved_card_payload(attachment, :attached, :attached,
          from_attached_to_card_instance_id: source_target_card_instance_id,
          to_attached_to_card_instance_id: evolved_card.id
        )
      end)
  end

  defp energy_switch_move_payload(card, source_target_card_instance_id, target_card_instance_id) do
    %{
      instance_id: card.id,
      card_id: card.card_id,
      owner_player_id: card.owner_player_id,
      from_zone: :attached,
      to_zone: :attached,
      from_attached_to_card_instance_id: source_target_card_instance_id,
      to_attached_to_card_instance_id: target_card_instance_id,
      to_position: card.position
    }
  end

  defp search_cards_moved_payload(card, effect, moved_targets) do
    moved_cards =
      EventPayloads.moved_cards(moved_targets, :deck, search_effect_destination_zone(effect))

    maybe_put_reveal_payload(
      %{
        reason: :effect_resolution,
        source: EventPayloads.card_source(card),
        effect_key: effect.key,
        cards: moved_cards
      },
      card,
      effect,
      moved_cards
    )
  end

  defp maybe_put_reveal_payload(payload, card, %{params: %{reveal: true}}, moved_cards) do
    payload
    |> Map.put(:public_reveal, true)
    |> Map.put(:source_card_id, card.card_id)
    |> Map.put(:revealed_cards, moved_cards)
  end

  defp maybe_put_reveal_payload(payload, _card, _effect, _moved_cards), do: payload

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp moved_card_payload(card, from_zone, to_zone, opts \\ []) do
    Map.merge(
      %{
        instance_id: card.id,
        card_id: card.card_id,
        owner_player_id: card.owner_player_id,
        from_zone: from_zone,
        to_zone: to_zone,
        to_position: card.position
      },
      Map.new(opts)
    )
  end

  defp prompt_payload(game_id, choice_key, legal_choice_ids, min, max) do
    maybe_put_prompt_choice_labels(
      %{
        choice_key: Atom.to_string(choice_key),
        legal_choices: legal_choice_ids,
        min: min,
        max: max
      },
      game_id,
      choice_key,
      legal_choice_ids
    )
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         :rare_candy_evolve_basic_to_stage_2,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&rare_candy_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         :search_basic_energy_split_hand_attach_to_pokemon,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&crispin_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         :move_basic_energy_between_own_pokemon,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&energy_switch_choice_label(&1, cards_by_id))

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(payload, _game_id, _choice_key, _legal_choice_ids),
    do: payload

  defp energy_switch_choice_label(%CardInstance{zone: :attached} = card, cards_by_id) do
    target_name =
      cards_by_id
      |> Map.get(card.attached_to_card_instance_id)
      |> card_name("attached Pokémon")

    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Source Basic Energy attached to #{target_name}"
    }
  end

  defp energy_switch_choice_label(%CardInstance{} = card, _cards_by_id) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Target Pokémon in #{Atom.to_string(card.zone)}"
    }
  end

  defp crispin_choice_label(%CardInstance{zone: :deck} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "Basic Energy in deck. Select one to add to hand, or choose two different types plus a target Pokémon to attach the second."
    }
  end

  defp crispin_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Target Pokémon in #{Atom.to_string(card.zone)} for a second selected Energy."
    }
  end

  defp rare_candy_choice_label(%CardInstance{zone: :hand} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Stage 2 Pokémon in hand. Select it with one compatible Basic Pokémon in play."
    }
  end

  defp rare_candy_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "Basic Pokémon in #{Atom.to_string(card.zone)}. Select it with a compatible Stage 2 card from hand."
    }
  end

  defp card_name(nil, fallback), do: fallback

  defp card_name(%CardInstance{card_id: card_id}, fallback) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{name: name}} when is_binary(name) -> name
      {:ok, _card} -> fallback
      {:error, _reason} -> fallback
    end
  end

  defp in_play_zone_sort(:active), do: 0
  defp in_play_zone_sort(:bench), do: 1
  defp in_play_zone_sort(_zone), do: 2

  defp effect_step(definition, choice_key) do
    Enum.find(definition.effects, &(&1.key == choice_key))
  end

  defp maybe_shuffle_and_write_deck_shuffled(
         %Game{} = game,
         turn,
         %GamePlayer{} = player,
         card,
         %{params: %{shuffle_after: true}} = effect
       ) do
    with {:ok, shuffled_deck} <- shuffle_deck_for_effect(game, turn, player, card, effect) do
      write_effect_deck_shuffled(game, turn, player.player_id, card, effect, shuffled_deck)
    end
  end

  defp maybe_shuffle_and_write_deck_shuffled(_game, _turn, _player, _card, _effect),
    do: {:ok, nil}

  defp return_hand_to_deck(game_id, player_id, hand_cards) do
    with {:ok, deck_count} <- CardStore.deck_count(game_id, player_id) do
      hand_cards
      |> Enum.with_index(deck_count + 1)
      |> Enum.map(fn {card, position} ->
        update(card, :shuffle_into_deck, %{attached_to_card_instance_id: nil, position: position})
      end)
      |> collect_results()
    end
  end

  defp shuffle_deck_for_effect(%Game{} = game, turn, %GamePlayer{} = player, card, effect) do
    context = effect_rng_context(player.player_id, turn, card, effect)

    with {:ok, cards} <- CardStore.cards_in_zone(game.id, player.player_id, :deck) do
      cards
      |> shuffle_cards(game.rng_seed, context)
      |> Enum.with_index(1)
      |> Enum.map(fn {card, position} -> update(card, :reorder_deck, %{position: position}) end)
      |> collect_results()
    end
  end

  defp shuffle_cards(cards, seed, context) when is_binary(seed),
    do: Rng.shuffle(cards, seed, context)

  defp shuffle_cards(cards, _seed, _context), do: Enum.shuffle(cards)

  defp shuffle_each_player_hand_into_deck_then_draw(
         game,
         turn,
         action_player,
         card,
         effect,
         affected_players
       ) do
    affected_players
    |> Enum.map(
      &shuffle_hand_into_deck_then_draw_for_player(game, turn, action_player, &1, card, effect)
    )
    |> collect_results()
  end

  defp shuffle_hand_into_deck_then_draw_for_player(
         %Game{} = game,
         turn,
         action_player,
         affected_player,
         card,
         effect
       ) do
    with {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, affected_player.player_id, :hand),
         returned_card_ids = MapSet.new(hand_cards, & &1.id),
         {:ok, _returned_to_deck} <-
           return_hand_to_deck(game.id, affected_player.player_id, hand_cards),
         {:ok, shuffled_deck} <-
           shuffle_deck_for_effect(game, turn, affected_player, card, effect),
         returned_cards = Enum.filter(shuffled_deck, &MapSet.member?(returned_card_ids, &1.id)),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, affected_player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: affected_player.player_id,
             cards: EventPayloads.moved_cards(returned_cards, :hand, :deck)
           }),
         {:ok, _event} <-
           write_effect_deck_shuffled(
             game,
             turn,
             affected_player.player_id,
             card,
             effect,
             shuffled_deck
           ),
         {:ok, draw_count} <- draw_count_for_effect(game.id, affected_player.player_id, effect),
         {:ok, drawn_cards} <- draw_cards_for_effect(game, affected_player, draw_count),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, affected_player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: affected_player.player_id,
             cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand)
           }) do
      {:ok,
       %{
         player_id: affected_player.player_id,
         action_player_id: action_player.player_id,
         returned_card_count: length(returned_cards),
         drawn_card_count: length(drawn_cards)
       }}
    end
  end

  defp write_effect_deck_shuffled(
         %Game{} = game,
         turn,
         affected_player_id,
         card,
         effect,
         shuffled_deck
       ) do
    payload =
      maybe_put_effect_rng_payload(
        %{
          source: EventPayloads.card_source(card),
          effect_key: effect.key,
          affected_player_id: affected_player_id,
          shuffle: "trainer_effect",
          card_count: length(shuffled_deck)
        },
        game,
        turn,
        affected_player_id,
        card,
        effect
      )

    write_event_and_snapshot(game.id, :deck_shuffled, affected_player_id, payload)
  end

  defp maybe_put_effect_rng_payload(
         payload,
         %Game{rng_seed: seed} = game,
         turn,
         player_id,
         card,
         effect
       )
       when is_binary(seed) do
    Map.merge(payload, %{
      rng_algorithm: game.rng_algorithm || Rng.algorithm(),
      rng_context: effect_rng_context_label(player_id, turn, card, effect),
      rng_seed_source: game.rng_seed_source
    })
  end

  defp maybe_put_effect_rng_payload(payload, %Game{}, _turn, _player_id, _card, _effect),
    do: payload

  defp effect_rng_context(player_id, turn, card, effect) do
    {:trainer_effect_shuffle, player_id, turn.turn_number, card.card_id, effect.key}
  end

  defp effect_rng_context_label(player_id, turn, card, effect) do
    "trainer_effect_shuffle:#{player_id}:turn_#{turn.turn_number}:#{card.card_id}:#{effect.key}"
  end

  defp require_each_player_can_draw_after_hand_shuffle(game, affected_players, effect) do
    affected_players
    |> Enum.map(&require_can_draw_after_hand_shuffle(game, &1, effect))
    |> collect_ok_results()
  end

  defp require_can_draw_after_hand_shuffle(%Game{} = game, %GamePlayer{} = player, effect) do
    with {:ok, draw_count} <- draw_count_for_effect(game.id, player.player_id, effect),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, player.player_id, :hand),
         {:ok, deck_count} <- CardStore.deck_count(game.id, player.player_id) do
      available_after_shuffle = deck_count + length(hand_cards)

      if available_after_shuffle >= draw_count do
        :ok
      else
        {:error, {:cannot_draw_card_effect_from_deck, draw_count, available_after_shuffle}}
      end
    end
  end

  defp draw_count_for_effect(game_id, player_id, %{
         params:
           %{full_prize_count: full_prize_count, full_prize_draw_count: full_prize_draw_count} =
             params
       }) do
    with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player_id, :prize) do
      if length(prizes) == full_prize_count do
        {:ok, full_prize_draw_count}
      else
        {:ok, Map.fetch!(params, :draw_count)}
      end
    end
  end

  defp draw_count_for_effect(_game_id, _player_id, %{params: %{draw_count: draw_count}}),
    do: {:ok, draw_count}

  defp draw_cards_for_effect(%Game{} = game, %GamePlayer{} = player, draw_count) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, draw_count),
         :ok <- require_enough_deck_cards(cards, draw_count),
         {:ok, starting_position} <-
           CardStore.next_hand_position_result(game.id, player.player_id) do
      draw_cards_to_hand(cards, starting_position)
    end
  end

  defp require_enough_deck_cards(cards, count) when length(cards) == count, do: :ok

  defp require_enough_deck_cards(cards, count) do
    {:error, {:cannot_draw_card_effect_from_deck, count, length(cards)}}
  end

  defp draw_cards_to_hand(cards, starting_position) do
    cards
    |> Enum.with_index(starting_position)
    |> Enum.map(fn {card, position} -> update(card, :draw_to_hand, %{position: position}) end)
    |> collect_results()
  end

  defp opponent_active_card(game_id, player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      case Enum.filter(cards, &(&1.owner_player_id != player_id and &1.zone == :active)) do
        [active_card] -> {:ok, active_card}
        [] -> {:error, :missing_opponent_active_pokemon}
        _multiple -> {:error, :ambiguous_opponent_active_pokemon}
      end
    end
  end

  defp opponent_switch_payload(active_card, bench_card) do
    [
      switched_card_payload(active_card, :active, :bench),
      switched_card_payload(bench_card, :bench, :active)
    ]
  end

  defp switched_card_payload(card, from_zone, to_zone) do
    %{
      instance_id: card.id,
      card_id: card.card_id,
      owner_player_id: card.owner_player_id,
      from_zone: from_zone,
      to_zone: to_zone,
      to_position: card.position
    }
  end

  defp require_all_owned_in_zone(cards, player_id, zone) do
    cards
    |> Enum.map(fn card ->
      with :ok <- require_card_owned_by_player(card, player_id) do
        require_card_zone(card, zone)
      end
    end)
    |> collect_ok_results()
  end

  defp require_all_in_zone(cards, zone) do
    cards
    |> Enum.map(&require_card_zone(&1, zone))
    |> collect_ok_results()
  end

  defp require_all_opponent_cards(cards, player_id) do
    cards
    |> Enum.map(&require_opponent_card(&1, player_id))
    |> collect_ok_results()
  end

  defp require_opponent_card(%CardInstance{owner_player_id: player_id}, player_id) do
    {:error, :target_not_opponent_card}
  end

  defp require_opponent_card(%CardInstance{}, _player_id), do: :ok

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
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
end

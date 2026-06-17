defmodule Prizmo.TcgEngine.CardPlay do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      require_basic_team_rocket_pokemon_card: 1,
      require_basic_pokemon: 1,
      require_energy: 1,
      require_basic_energy: 1,
      require_mega_evolution_pokemon_ex_card: 1,
      require_night_stretcher_target: 1,
      require_non_rule_box_pokemon_card: 1,
      require_poffin_targets: 1,
      require_pokemon_card: 1,
      require_rare_candy_evolves_from: 2,
      require_special_energy: 1,
      require_stage_2_pokemon: 1,
      require_team_rocket_pokemon_card: 1,
      require_trainer_type: 2
    ]

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [
      require_ace_spec_available: 3,
      require_can_evolve_target: 2,
      require_card_owned_by_player: 2,
      require_card_zone: 2,
      evolve_action_for_zone: 1,
      require_evolution_allowed_this_turn: 1,
      require_in_play_pokemon_zone: 1,
      require_supporter_available: 5
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
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.ItemLocks
  alias Prizmo.TcgEngine.PendingEffects
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.TrainerPlay
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @coin_faces [:heads, :tails]

  def require_playable_trainer_definition(
        %Game{} = game,
        %Turn{} = turn,
        %GamePlayer{} = player,
        %CardInstance{} = card,
        player_id,
        definition
      ) do
    with :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         {:ok, metadata} <- require_trainer_type(card.card_id, [definition.trainer_type]),
         :ok <-
           require_supporter_available(player, metadata, game, turn,
             allow_first_turn_when_going_first?:
               definition.first_turn_supporter_allowed_when_going_first?
           ),
         :ok <- ItemLocks.require_item_unlocked_if_item(metadata, game.id, player_id, turn),
         :ok <- require_ace_spec_available(player, metadata, game.id),
         :ok <- require_effect_available(game, turn, player, definition) do
      {:ok, metadata}
    end
  end

  def require_trainer_card(
        %Game{} = game,
        %Turn{} = turn,
        %GamePlayer{} = player,
        %CardInstance{} = card,
        player_id,
        expected_card_id,
        allowed_types,
        opts \\ []
      ) do
    with :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         :ok <- Prizmo.TcgEngine.Requirements.require_card_id(card, expected_card_id),
         {:ok, metadata} <- require_trainer_type(card.card_id, allowed_types),
         :ok <- require_supporter_available(player, metadata, game, turn, opts),
         :ok <- ItemLocks.require_item_unlocked_if_item(metadata, game.id, player_id, turn) do
      require_ace_spec_available(player, metadata, game.id)
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
      case effect.type do
        :flip_coin_then_discard_opponent_attached_energy ->
          resolve_coin_flip_then_discard_opponent_attached_energy(
            game,
            turn,
            player,
            card,
            definition,
            effect,
            choices
          )

        _other ->
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
  end

  defp resolve_coin_flip_then_discard_opponent_attached_energy(
         game,
         turn,
         player,
         card,
         definition,
         effect,
         choices
       ) do
    with {:ok, result} <- flip_coin_for_effect(game, turn, player, card, effect),
         {:ok, _event} <-
           write_effect_coin_flipped(game, turn, player.player_id, card, effect, result) do
      case result do
        :heads ->
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

        :tails ->
          complete_play_card_resolution(game, turn, player, card, effect)
      end
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :flip_coin_then_discard_opponent_attached_energy} = effect,
         target_ids
       ) do
    with {:ok, [target_energy_card]} <-
           validate_opponent_attached_energy_discard_effect(
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
         %{type: :switch_own_active_with_bench} = effect,
         target_ids
       ) do
    with {:ok, [bench_card]} <-
           validate_own_bench_switch_effect(game.id, player.player_id, effect, target_ids),
         {:ok, active_card} <- own_active_card(game.id, player.player_id),
         bench_position = bench_card.position,
         {:ok, moved_active_card} <-
           update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
         {:ok, moved_bench_card} <-
           update(bench_card, :promote_to_active, %{position: 1, status: nil}),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards: [
               switched_card_payload(moved_active_card, :active, :bench),
               switched_card_payload(moved_bench_card, :bench, :active)
             ]
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :opponent_hand_to_bottom_then_draw_if_any} = effect,
         _target_ids
       ) do
    with {:ok, opponent_player} <- CardStore.get_opponent(game.id, player.player_id),
         :ok <- require_opponent_prize_count_at_most(game.id, player.player_id, effect),
         {:ok, bottomed_cards} <-
           shuffle_hand_to_bottom_of_deck(game, turn, opponent_player, card, effect),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: opponent_player.player_id,
             cards: EventPayloads.moved_cards(bottomed_cards, :hand, :deck),
             destination: :deck_bottom
           }),
         {:ok, drawn_cards} <-
           maybe_draw_after_opponent_hand_bottomed(game, opponent_player, bottomed_cards, effect),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: opponent_player.player_id,
             cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :attach_basic_psychic_energy_from_discard_to_benched_psychic_pokemon} = effect,
         target_ids
       ) do
    with {:ok, {energy_card, target_card}} <-
           validate_wondrous_patch_effect(game.id, player.player_id, effect, target_ids),
         :ok <- attach_basic_energy_from_discard(game.id, [energy_card], [target_card]),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: player.player_id,
             cards: wondrous_patch_attached_energy_payloads(energy_card, target_card)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :draw_until_hand_size} = effect,
         _target_ids
       ) do
    with {:ok, target_hand_size} <- draw_until_hand_size_target(game.id, player.player_id, effect),
         {:ok, drawn_cards} <- draw_until_hand_size_for_effect(game, player, target_hand_size),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: player.player_id,
             cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
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
         %{type: :recover_discard_to_deck} = effect,
         target_ids
       ) do
    with {:ok, target_cards} <-
           validate_recover_discard_to_deck_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_targets} <-
           CardStore.shuffle_discard_cards_into_deck(game.id, player.player_id, target_cards),
         moved_cards = EventPayloads.moved_cards(moved_targets, :discard, :deck),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards: moved_cards,
             public_reveal: true,
             public_note: sacred_ash_public_note(length(moved_targets)),
             source_card_id: card.card_id,
             revealed_cards: moved_cards
           }),
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
         %{type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand} = effect,
         target_ids
       ) do
    with {:ok, target_card} <-
           validate_wallys_compassion_effect(game.id, player.player_id, effect, target_ids),
         healed_damage = target_card.damage,
         {:ok, healed_card} <- update(target_card, :set_damage, %{damage: 0}),
         {:ok, attached_cards} <- CardStore.attached_cards(game.id, target_card.id),
         energy_cards = Enum.filter(attached_cards, &energy_card?/1),
         {:ok, returned_energy_cards} <-
           energy_cards
           |> Enum.map(&CardStore.move_attached_card_to_hand(game.id, player.player_id, &1))
           |> collect_results(),
         returned_energy_payloads =
           wallys_compassion_returned_energy_payloads(returned_energy_cards, target_card.id),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: player.player_id,
             healed_card_instance_id: healed_card.id,
             healed_damage: healed_damage,
             source_card_id: card.card_id,
             public_note:
               wallys_compassion_public_note(
                 healed_card,
                 healed_damage,
                 length(returned_energy_cards)
               ),
             public_reveal: true,
             revealed_cards: returned_energy_payloads,
             cards: returned_energy_payloads
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
         %{type: :switch_team_rocket_bench_and_opponent_bench_to_active} = effect,
         target_ids
       ) do
    with {:ok, own_active_card} <- own_active_card(game.id, player.player_id),
         {:ok, {own_bench_card, opponent_bench_card}} <-
           validate_team_rockets_giovanni_effect(game.id, player.player_id, effect, target_ids),
         {:ok, opponent_active_card} <- opponent_active_card(game.id, player.player_id),
         own_bench_position = own_bench_card.position,
         opponent_bench_position = opponent_bench_card.position,
         {:ok, moved_own_active_card} <-
           update(own_active_card, :move_active_to_bench, %{
             position: own_bench_position,
             status: nil
           }),
         {:ok, moved_own_bench_card} <-
           update(own_bench_card, :promote_to_active, %{position: 1, status: nil}),
         {:ok, moved_opponent_active_card} <-
           update(opponent_active_card, :move_active_to_bench, %{
             position: opponent_bench_position,
             status: nil
           }),
         {:ok, moved_opponent_bench_card} <-
           update(opponent_bench_card, :promote_to_active, %{position: 1, status: nil}),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards:
               team_rockets_giovanni_switch_payload(
                 moved_own_active_card,
                 moved_own_bench_card,
                 moved_opponent_active_card,
                 moved_opponent_bench_card
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
         %{type: :damage_any_opponent_pokemon, amount: amount} = effect,
         target_ids
       ) do
    with {:ok, [target_pokemon]} <-
           validate_opponent_in_play_damage_target(game.id, player.player_id, target_ids),
         {:ok, _damage_result} <-
           resolve_attack_damage_to_target(game.id, target_pokemon, amount, card, effect) do
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
         :ok <-
           require_each_player_can_draw_after_hand_shuffle(game, player, affected_players, effect),
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

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :turn_bonus_attack_damage_to_opponent_active_pokemon_ex} = effect,
         _target_ids
       ) do
    complete_play_card_resolution(game, turn, player, card, effect)
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :discard_opponent_item_cards_from_hand} = effect,
         target_ids
       ) do
    with {:ok, opponent} <- CardStore.get_opponent(game.id, player.player_id),
         {:ok, target_cards} <- validate_eri_effect(game.id, player.player_id, effect, target_ids),
         {:ok, _discarded} <-
           CardStore.discard_cards_from_hand(game.id, opponent.player_id, target_cards),
         {:ok, _event} <-
           maybe_write_cards_moved_event(
             game.id,
             opponent.player_id,
             target_cards,
             card,
             effect
           ) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :opponent_discards_to_hand_size} = effect,
         target_ids
       ) do
    with {:ok, opponent} <- CardStore.get_opponent(game.id, player.player_id),
         {:ok, to_discard} <-
           validate_xerosics_effect(game.id, player.player_id, effect, target_ids),
         {:ok, _discarded} <-
           CardStore.discard_cards_from_hand(game.id, opponent.player_id, to_discard),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, opponent.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: opponent.player_id,
             cards: EventPayloads.moved_cards(to_discard, :hand, :discard)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes} = effect,
         target_ids
       ) do
    with {:ok, target_cards} <-
           validate_rosa_effect(game.id, player.player_id, effect, target_ids),
         {:ok, {basic_energy, stage2_target}} <-
           selected_rosa_cards(target_cards, player.player_id, effect),
         stage2_targets = List.duplicate(stage2_target, length(basic_energy)),
         :ok <- attach_basic_energy_from_discard(game.id, basic_energy, stage2_targets),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             affected_player_id: player.player_id,
             cards: rosa_attached_energy_payloads(basic_energy, stage2_targets)
           }) do
      complete_play_card_resolution(game, turn, player, card, effect)
    end
  end

  defp complete_play_card_effect(
         game,
         turn,
         player,
         card,
         %{type: :kieran_switch_or_damage_bonus} = effect,
         target_ids
       ) do
    case target_ids do
      [] ->
        # Damage bonus mode: complete immediately, +30 checked at attack time
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
                 kieran_effect: "damage",
                 result: :completed
               }),
             :ok <- PendingEffects.complete_resolving_for_game(game.id) do
          GameStore.get_game(game.id)
        end

      [bench_card_id] ->
        # Switch mode: switch own active with chosen bench Pokémon
        with {:ok, bench_card} <- CardStore.get_card(game.id, bench_card_id),
             :ok <- require_card_owned_by_player(bench_card, player.player_id),
             :ok <- require_card_zone(bench_card, :bench),
             {:ok, active_card} <- own_active_card(game.id, player.player_id),
             bench_position = bench_card.position,
             {:ok, _moved_active_card} <-
               update(active_card, :move_active_to_bench, %{
                 position: bench_position,
                 status: nil
               }),
             {:ok, _moved_bench_card} <-
               update(bench_card, :promote_to_active, %{position: 1, status: nil}),
             {:ok, _event} <-
               write_event_and_snapshot(game.id, :effect_completed, player.player_id, %{
                 turn_id: turn.id,
                 source: EventPayloads.card_source(card),
                 effect_key: effect.key,
                 status: :completed
               }),
             {:ok, _event} <-
               write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
                 reason: :effect_resolution,
                 source: EventPayloads.card_source(card),
                 effect_key: effect.key,
                 cards: [
                   switched_card_payload(active_card, :active, :bench),
                   switched_card_payload(bench_card, :bench, :active)
                 ]
               }),
             {:ok, _event} <-
               write_event_and_snapshot(game.id, :card_play_completed, player.player_id, %{
                 turn_id: turn.id,
                 card_instance_id: card.id,
                 card_id: card.card_id,
                 kieran_effect: "switch",
                 result: :completed
               }),
             :ok <- PendingEffects.complete_resolving_for_game(game.id) do
          GameStore.get_game(game.id)
        end

      _invalid ->
        {:error, :invalid_kieran_target_count}
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
         {:ok, prompt_player_id} <-
           choice_prompt_player_id(game.id, player.player_id, definition, choice_key),
         {:ok, pending_effect} <-
           PendingEffects.upsert_awaiting(
             game,
             player,
             card,
             choices,
             phase,
             choice_key,
             prompt_player_id
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
             player_id: prompt_player_id,
             payload:
               prompt_payload(
                 game.id,
                 prompt_player_id,
                 choice_key,
                 legal_choice_ids,
                 min,
                 max
               )
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

  defp require_effect_available(
         %Game{} = game,
         %Turn{} = turn,
         %GamePlayer{} = player,
         definition
       ) do
    case EffectRunner.first_effect(definition) do
      {:ok, %{type: :draw_until_hand_size} = effect} ->
        require_draw_until_hand_size_effect(game.id, player.player_id, effect)

      {:ok, %{type: :shuffle_each_player_hand_into_deck_then_draw} = effect} ->
        case effect.params do
          %{requires_own_pokemon_knocked_out_last_turn: true} ->
            require_previous_turn_own_knockout(game.id, turn, player.player_id, effect)

          %{requires_team_rocket_knockout_last_turn: true} ->
            require_previous_turn_team_rocket_knockout(game.id, turn, player.player_id, effect)

          _other ->
            :ok
        end

      {:ok, %{type: :opponent_hand_to_bottom_then_draw_if_any} = effect} ->
        require_opponent_prize_count_at_most(game.id, player.player_id, effect)

      {:ok, %{type: :opponent_discards_to_hand_size} = effect} ->
        require_xerosics_effect_available(game.id, player.player_id, effect)

      {:ok, %{type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes} = effect} ->
        require_rosa_effect_available(game.id, player.player_id, effect)

      {:ok, _effect} ->
        :ok

      {:error, :missing_effect_definition} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_draw_until_hand_size_effect(game_id, player_id, effect) do
    with {:ok, target_hand_size} <- draw_until_hand_size_target(game_id, player_id, effect),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, player_id, :hand),
         {:ok, deck_count} <- CardStore.deck_count(game_id, player_id) do
      remaining_hand_size_after_play = max(length(hand_cards) - 1, 0)
      required_draw_count = max(target_hand_size - remaining_hand_size_after_play, 0)

      if required_draw_count > 0 and deck_count > 0 do
        :ok
      else
        {:error, :draw_until_hand_size_has_no_effect}
      end
    end
  end

  defp require_previous_turn_team_rocket_knockout(game_id, %Turn{} = turn, player_id, %{
         params: %{requires_team_rocket_knockout_last_turn: true}
       }) do
    with {:ok, previous_turn} <- previous_turn(game_id, turn.turn_number),
         :ok <- require_previous_turn_was_opponents_turn(previous_turn, player_id),
         {:ok, previous_turn_knockout_events} <-
           knockout_prize_events_for_turn(game_id, previous_turn.id) do
      if Enum.any?(
           previous_turn_knockout_events,
           &team_rocket_knockout_for_player?(&1, player_id)
         ) do
        :ok
      else
        {:error, :team_rockets_archer_requires_team_rocket_ko_during_opponents_last_turn}
      end
    end
  end

  defp require_previous_turn_team_rocket_knockout(_game_id, _turn, _player_id, _effect), do: :ok

  defp require_previous_turn_own_knockout(game_id, %Turn{} = turn, player_id, %{
         params: %{requires_own_pokemon_knocked_out_last_turn: true}
       }) do
    with {:ok, previous_turn} <- previous_turn(game_id, turn.turn_number),
         :ok <- require_previous_turn_was_opponents_turn(previous_turn, player_id),
         {:ok, previous_turn_knockout_events} <-
           knockout_prize_events_for_turn(game_id, previous_turn.id) do
      if Enum.any?(
           previous_turn_knockout_events,
           &any_knockout_for_player?(&1, player_id)
         ) do
        :ok
      else
        {:error, :unfair_stamp_requires_own_pokemon_ko_during_opponents_last_turn}
      end
    end
  end

  defp require_previous_turn_own_knockout(_game_id, _turn, _player_id, _effect), do: :ok

  defp require_opponent_prize_count_at_most(game_id, player_id, %{
         params: %{requires_opponent_prize_count_at_most: max_prize_count}
       })
       when is_binary(game_id) and is_binary(player_id) and is_integer(max_prize_count) do
    with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id),
         {:ok, prizes} <- CardStore.cards_in_zone(game_id, opponent_player.player_id, :prize) do
      if length(prizes) <= max_prize_count do
        :ok
      else
        {:error, :special_red_card_requires_opponent_3_or_fewer_prizes_remaining}
      end
    end
  end

  defp require_opponent_prize_count_at_most(_game_id, _player_id, _effect), do: :ok

  defp require_more_prizes_than_opponent(game_id, player_id, _effect) do
    with {:ok, player} <- CardStore.get_player(game_id, player_id),
         {:ok, opponent} <- CardStore.get_opponent(game_id, player_id),
         {:ok, player_prizes} <-
           CardStore.cards_in_zone(game_id, player.player_id, :prize),
         {:ok, opponent_prizes} <-
           CardStore.cards_in_zone(game_id, opponent.player_id, :prize) do
      if length(player_prizes) > length(opponent_prizes) do
        :ok
      else
        {:error, :rosa_requires_strictly_more_prizes_than_opponent}
      end
    end
  end

  defp require_xerosics_effect_available(game_id, player_id, effect) do
    with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, opponent_player.player_id, :hand) do
      discard_count = xerosics_discard_count(hand_cards, effect)

      if discard_count > 0 do
        :ok
      else
        {:error, :xerosics_machinations_has_no_effect}
      end
    end
  end

  defp require_rosa_effect_available(game_id, player_id, effect) do
    with :ok <- require_more_prizes_than_opponent(game_id, player_id, effect),
         {:ok, cards} <- CardStore.list_cards(game_id) do
      energy_cards = rosa_discard_energy_choice_cards(cards, player_id)
      target_cards = rosa_stage_2_choice_cards(cards, player_id)

      cond do
        energy_cards == [] ->
          {:error, :rosa_requires_basic_energy_in_discard}

        target_cards == [] ->
          {:error, :rosa_requires_stage_2_in_play}

        true ->
          :ok
      end
    end
  end

  defp any_knockout_for_player?(%GameEvent{payload: payload}, player_id) do
    payload
    |> Map.get("knockouts", [])
    |> Enum.any?(fn
      %{"knocked_out_player_id" => ^player_id} -> true
      _other -> false
    end)
  end

  defp previous_turn(_game_id, turn_number) when turn_number <= 1,
    do: {:error, :team_rockets_archer_requires_team_rocket_ko_during_opponents_last_turn}

  defp previous_turn(game_id, turn_number) do
    case TurnStore.list_all_turns(game_id) do
      {:ok, turns} ->
        turns
        |> Enum.find(&(&1.turn_number == turn_number - 1))
        |> case do
          %Turn{} = turn ->
            {:ok, turn}

          nil ->
            {:error, :team_rockets_archer_requires_team_rocket_ko_during_opponents_last_turn}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_previous_turn_was_opponents_turn(
         %Turn{active_player_id: active_player_id},
         player_id
       ) do
    if active_player_id == player_id do
      {:error, :team_rockets_archer_requires_team_rocket_ko_during_opponents_last_turn}
    else
      :ok
    end
  end

  defp knockout_prize_events_for_turn(game_id, turn_id) do
    GameEvent
    |> Ash.Query.filter(
      game_id == ^game_id and turn_id == ^turn_id and type == "take_knockout_prizes"
    )
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp team_rocket_knockout_for_player?(%GameEvent{payload: payload}, player_id) do
    payload
    |> Map.get("knockouts", [])
    |> Enum.any?(fn
      %{"knocked_out_player_id" => ^player_id, "knocked_out_card_id" => card_id} ->
        require_team_rocket_pokemon_card(card_id) == :ok

      _other ->
        false
    end)
  end

  defp validate_search_deck_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_search_deck_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_search_filters(target_cards, Map.get(effect.params, :filter)),
         :ok <-
           require_required_search_groups(target_cards, Map.get(effect.params, :required_groups)),
         :ok <- require_max_search_groups(target_cards, Map.get(effect.params, :max_groups)) do
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
         :ok <- require_all_search_filters(target_cards, Map.get(effect.params, :filter)) do
      {:ok, target_cards}
    end
  end

  defp validate_crispin_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids) do
      selected_crispin_cards(target_cards, player_id)
    end
  end

  defp validate_wallys_compassion_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids) do
      selected_wallys_compassion_target(target_cards, player_id)
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

  defp validate_own_bench_switch_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :bench) do
      {:ok, target_cards}
    end
  end

  defp validate_opponent_in_play_damage_target(game_id, player_id, target_ids) do
    with {:ok, target_ids} <-
           EffectRunner.validate_choice_selection(%{min_count: 1, max_count: 1}, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_opponent_cards(target_cards, player_id),
         :ok <- require_all_in_zone(target_cards, [:active, :bench]) do
      {:ok, target_cards}
    end
  end

  defp validate_team_rockets_giovanni_effect(game_id, player_id, effect, target_ids) do
    with {:ok, active_card} <- own_active_card(game_id, player_id),
         :ok <- require_team_rocket_pokemon_card(active_card.card_id),
         {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids) do
      selected_team_rockets_giovanni_cards(target_cards, player_id)
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

  defp validate_opponent_attached_energy_discard_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_opponent_cards(target_cards, player_id),
         :ok <- require_all_in_zone(target_cards, :attached),
         :ok <- require_all_energy_cards(target_cards) do
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

  defp validate_recover_discard_to_deck_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :discard),
         :ok <- require_all_recover_discard_to_hand_filters(target_cards, effect.params.filter) do
      {:ok, target_cards}
    end
  end

  defp validate_xerosics_effect(game_id, player_id, effect, target_ids) do
    with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, opponent_player.player_id, :hand),
         discard_count when discard_count > 0 <- xerosics_discard_count(hand_cards, effect),
         {:ok, target_ids} <-
           EffectRunner.validate_choice_selection(
             %{params: %{count: discard_count}},
             target_ids,
             :wrong_xerosics_discard_count
           ),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, opponent_player.player_id, :hand) do
      {:ok, target_cards}
    else
      0 -> {:error, :xerosics_machinations_has_no_effect}
      {:error, _reason} = error -> error
    end
  end

  defp validate_eri_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <- EffectRunner.validate_choice_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_eri_targets(game_id, player_id, target_cards) do
      {:ok, target_cards}
    end
  end

  defp validate_rosa_effect(game_id, player_id, effect, target_ids) do
    with :ok <- require_more_prizes_than_opponent(game_id, player_id, effect),
         {:ok, target_ids} <-
           EffectRunner.validate_choice_selection(effect, target_ids, :wrong_rosa_choice_count),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         {:ok, {_energy_cards, _target_card}} <-
           selected_rosa_cards(target_cards, player_id, effect) do
      {:ok, target_cards}
    end
  end

  defp validate_wondrous_patch_effect(game_id, player_id, effect, target_ids) do
    with {:ok, target_ids} <-
           EffectRunner.validate_choice_selection(
             effect,
             target_ids,
             :wrong_wondrous_patch_choice_count
           ),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids) do
      selected_wondrous_patch_cards(target_cards, player_id)
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

  defp move_search_targets(
         game,
         _turn,
         player,
         %{params: %{destination: :deck_top}},
         target_cards
       ) do
    CardStore.move_deck_cards_to_top(game.id, player.player_id, target_cards)
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
  defp search_effect_destination_zone(%{params: %{destination: :deck_top}}), do: :deck
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
         %{type: :flip_coin_then_discard_opponent_attached_energy},
         _current_turn
       ) do
    cards
    |> opponent_attached_energy_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :opponent_discards_to_hand_size} = choice_step,
         _current_turn
       ) do
    cards
    |> xerosics_opponent_hand_choice_cards(player_id, choice_step)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :discard_opponent_item_cards_from_hand},
         _current_turn
       ) do
    cards
    |> eri_opponent_item_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes},
         _current_turn
       ) do
    cards
    |> rosa_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :attach_basic_psychic_energy_from_discard_to_benched_psychic_pokemon},
         _current_turn
       ) do
    cards
    |> wondrous_patch_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand},
         _current_turn
       ) do
    cards
    |> wallys_compassion_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(cards, player_id, %{type: :switch_own_active_with_bench}, _current_turn) do
    cards
    |> own_bench_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :switch_team_rocket_bench_and_opponent_bench_to_active},
         _current_turn
       ) do
    cards
    |> team_rockets_giovanni_choice_cards(player_id)
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

  defp effect_choice_ids(cards, player_id, %{type: :damage_any_opponent_pokemon}, _current_turn) do
    cards
    |> opponent_in_play_choice_cards(player_id)
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

  defp effect_choice_ids(
         cards,
         player_id,
         %{type: :recover_discard_to_deck} = choice_step,
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

  defp effect_choice_ids(cards, player_id, %{type: :kieran_switch_or_damage_bonus}, _current_turn) do
    cards
    |> own_bench_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(_cards, _player_id, choice_step, _current_turn) do
    {:error, {:unsupported_choice_step, choice_step.key, choice_step.type}}
  end

  defp draw_until_hand_size_target(game_id, player_id, %{params: %{hand_size: hand_size} = params}) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      if all_own_pokemon_in_play_are_team_rocket?(cards, player_id) do
        {:ok, Map.get(params, :team_rocket_hand_size, hand_size)}
      else
        {:ok, hand_size}
      end
    end
  end

  defp all_own_pokemon_in_play_are_team_rocket?(cards, player_id) do
    in_play_cards =
      Enum.filter(cards, &(&1.owner_player_id == player_id and &1.zone in [:active, :bench]))

    in_play_cards != [] and
      Enum.all?(in_play_cards, &(require_team_rocket_pokemon_card(&1.card_id) == :ok))
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

      _other ->
        effect_choice_ids(cards, player_id, choice_step, current_turn)
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
    case dynamic_prompt_choice_bounds(
           game_id,
           player_id,
           definition,
           choice_key,
           legal_choice_ids
         ) do
      {:ok, {min, max}} ->
        {min, min(max, length(legal_choice_ids))}

      :error ->
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
  end

  defp dynamic_prompt_choice_bounds(game_id, player_id, definition, choice_key, legal_choice_ids) do
    case effect_step(definition, choice_key) do
      %{type: :opponent_discards_to_hand_size} = effect ->
        with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id),
             {:ok, hand_cards} <-
               CardStore.cards_in_zone(game_id, opponent_player.player_id, :hand) do
          discard_count = xerosics_discard_count(hand_cards, effect)
          {:ok, {discard_count, discard_count}}
        else
          _other -> :error
        end

      %{type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes} = effect ->
        case CardStore.list_cards(game_id) do
          {:ok, cards} ->
            energy_count =
              cards
              |> rosa_discard_energy_choice_cards(player_id)
              |> length()
              |> min(Map.get(effect.params, :max_targets, 2))

            if energy_count > 0 and legal_choice_ids != [] do
              {:ok, {2, energy_count + 1}}
            else
              :error
            end

          _other ->
            :error
        end

      _other ->
        :error
    end
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
      |> Enum.filter(&matches_search_filter?(&1, Map.get(choice_step.params, :filter)))
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
      |> Enum.filter(&matches_search_filter?(&1, Map.get(choice_step.params, :filter)))

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

  defp own_bench_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :bench))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp team_rockets_giovanni_choice_cards(cards, player_id) do
    with %CardInstance{} = active_card <-
           Enum.find(cards, &(&1.owner_player_id == player_id and &1.zone == :active)),
         :ok <- require_team_rocket_pokemon_card(active_card.card_id) do
      own_bench_cards =
        cards
        |> Enum.filter(&team_rockets_giovanni_own_bench_card?(&1, player_id))
        |> Enum.sort_by(&{&1.position, &1.instance_id})

      opponent_bench_cards =
        cards
        |> Enum.filter(&team_rockets_giovanni_opponent_bench_card?(&1, player_id))
        |> Enum.sort_by(&{&1.owner_player_id, &1.position, &1.instance_id})

      if Enum.empty?(own_bench_cards) or Enum.empty?(opponent_bench_cards) do
        []
      else
        own_bench_cards ++ opponent_bench_cards
      end
    else
      _other -> []
    end
  end

  defp wallys_compassion_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&wallys_compassion_target_card?(&1, player_id))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
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

  defp xerosics_opponent_hand_choice_cards(cards, player_id, choice_step) do
    hand_cards =
      cards
      |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :hand))
      |> Enum.sort_by(&{&1.position, &1.instance_id})

    if xerosics_discard_count(hand_cards, choice_step) > 0 do
      hand_cards
    else
      []
    end
  end

  defp eri_opponent_item_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&eri_item_hand_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp rosa_choice_cards(cards, player_id) do
    energy_cards = rosa_discard_energy_choice_cards(cards, player_id)
    target_cards = rosa_stage_2_choice_cards(cards, player_id)

    if energy_cards == [] or target_cards == [] do
      []
    else
      energy_cards ++ target_cards
    end
  end

  defp rosa_discard_energy_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&rosa_basic_energy_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp rosa_stage_2_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&rosa_stage_2_target_card?(&1, player_id))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp wondrous_patch_choice_cards(cards, player_id) do
    energy_cards = wondrous_patch_discard_energy_choice_cards(cards, player_id)
    target_cards = wondrous_patch_benched_psychic_choice_cards(cards, player_id)

    if energy_cards == [] or target_cards == [] do
      []
    else
      energy_cards ++ target_cards
    end
  end

  defp wondrous_patch_discard_energy_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&wondrous_patch_basic_psychic_energy_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp wondrous_patch_benched_psychic_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&wondrous_patch_benched_psychic_target_card?(&1, player_id))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
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

  defp opponent_attached_energy_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(
      &(&1.owner_player_id != player_id and &1.zone == :attached and energy_card?(&1))
    )
    |> Enum.sort_by(
      &{&1.owner_player_id, &1.attached_to_card_instance_id, &1.position, &1.instance_id}
    )
  end

  defp opponent_in_play_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone in [:active, :bench]))
    |> Enum.sort_by(&{zone_to_int(&1.zone), &1.position, &1.instance_id})
  end

  defp zone_to_int(:active), do: 0
  defp zone_to_int(:bench), do: 1
  defp zone_to_int(_), do: 99

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

  defp require_search_filter(%CardInstance{} = card, %{
         kind: :pokemon,
         team_rocket?: true,
         stage: :basic
       }) do
    require_basic_team_rocket_pokemon_card(card.card_id)
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, stage: :basic, max_hp: 70}) do
    require_poffin_targets([card])
  end

  defp require_search_filter(%CardInstance{}, nil), do: :ok

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

  defp require_max_search_groups(_target_cards, nil), do: :ok

  defp require_max_search_groups(target_cards, max_groups) when is_list(max_groups) do
    max_groups
    |> Enum.map(fn group ->
      max_count = Map.get(group, :count, 1)
      actual_count = Enum.count(target_cards, &matches_search_filter?(&1, group.filter))

      if actual_count <= max_count do
        :ok
      else
        {:error, {:too_many_search_group_targets, group.filter, actual_count, max_count}}
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

  defp energy_card?(%CardInstance{card_id: card_id}), do: require_energy(card_id) == :ok

  defp crispin_basic_energy_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :deck and
      require_basic_energy(card.card_id) == :ok and
      match?({:ok, _type}, basic_energy_type(card))
  end

  defp crispin_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_pokemon_card(card.card_id) == :ok
  end

  defp rosa_basic_energy_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :discard and
      require_basic_energy(card.card_id) == :ok
  end

  defp rosa_stage_2_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_stage_2_pokemon(card.card_id) == :ok
  end

  defp wondrous_patch_basic_psychic_energy_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :discard and
      require_search_filter(card, %{kind: :energy, energy_type: :basic, provides: :psychic}) ==
        :ok
  end

  defp wondrous_patch_benched_psychic_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :bench and
      require_search_filter(card, %{kind: :pokemon, type: :psychic}) == :ok
  end

  defp eri_item_hand_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id != player_id and card.zone == :hand and
      match?({:ok, _metadata}, require_trainer_type(card.card_id, [:item]))
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

  defp selected_rosa_cards(cards, player_id, effect) do
    energy_cards = Enum.filter(cards, &rosa_basic_energy_card?(&1, player_id))
    target_cards = Enum.filter(cards, &rosa_stage_2_target_card?(&1, player_id))
    max_targets = Map.get(effect.params, :max_targets, 2)

    if length(cards) == length(energy_cards) + length(target_cards) do
      case {energy_cards, target_cards} do
        {[energy_card], [target_card]} ->
          {:ok, {[energy_card], target_card}}

        {[energy_card_1, energy_card_2], [target_card]} ->
          {:ok, {[energy_card_1, energy_card_2], target_card}}

        {[], [_target_card]} ->
          {:error, :missing_rosa_basic_energy_choice}

        {[_energy_card | _rest], []} ->
          {:error, :missing_rosa_stage_2_choice}

        {[], []} ->
          {:error, :missing_rosa_choices}

        {energy_cards, [_target_card]} when length(energy_cards) > max_targets ->
          {:error, {:too_many_rosa_basic_energy_choices, length(energy_cards), max_targets}}

        {[_energy_card | _rest], target_cards} when length(target_cards) > 1 ->
          {:error, {:too_many_rosa_stage_2_choices, length(target_cards)}}

        _other ->
          {:error, :invalid_rosa_choices}
      end
    else
      {:error, :invalid_rosa_choices}
    end
  end

  defp selected_wondrous_patch_cards(cards, player_id) do
    energy_cards = Enum.filter(cards, &wondrous_patch_basic_psychic_energy_card?(&1, player_id))
    target_cards = Enum.filter(cards, &wondrous_patch_benched_psychic_target_card?(&1, player_id))

    case {energy_cards, target_cards} do
      {[energy_card], [target_card]} ->
        {:ok, {energy_card, target_card}}

      {[], _target_cards} ->
        {:error, :wondrous_patch_requires_basic_psychic_energy_in_discard}

      {_energy_cards, []} ->
        {:error, :wondrous_patch_requires_benched_psychic_target}

      {energy_cards, target_cards} ->
        {:error, {:wrong_wondrous_patch_target_mix, length(energy_cards), length(target_cards)}}
    end
  end

  defp selected_team_rockets_giovanni_cards(cards, player_id) do
    own_bench_cards = Enum.filter(cards, &team_rockets_giovanni_own_bench_card?(&1, player_id))

    opponent_bench_cards =
      Enum.filter(cards, &team_rockets_giovanni_opponent_bench_card?(&1, player_id))

    case {own_bench_cards, opponent_bench_cards} do
      {[own_bench_card], [opponent_bench_card]} ->
        {:ok, {own_bench_card, opponent_bench_card}}

      {[], [_opponent_bench_card]} ->
        {:error, :missing_team_rockets_giovanni_own_bench_choice}

      {[_own_bench_card], []} ->
        {:error, :missing_team_rockets_giovanni_opponent_bench_choice}

      {[], []} ->
        {:error, :missing_team_rockets_giovanni_choices}

      {own_cards, [_opponent_bench_card]} when length(own_cards) > 1 ->
        {:error, {:too_many_team_rockets_giovanni_own_bench_choices, length(own_cards)}}

      {[_own_bench_card], opponent_cards} when length(opponent_cards) > 1 ->
        {:error, {:too_many_team_rockets_giovanni_opponent_bench_choices, length(opponent_cards)}}

      _other ->
        {:error, :invalid_team_rockets_giovanni_choices}
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

  defp team_rockets_giovanni_own_bench_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone == :bench and
      require_team_rocket_pokemon_card(card.card_id) == :ok
  end

  defp team_rockets_giovanni_opponent_bench_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id != player_id and card.zone == :bench and
      require_pokemon_card(card.card_id) == :ok
  end

  defp wallys_compassion_target_card?(%CardInstance{} = card, player_id) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and card.damage > 0 and
      require_mega_evolution_pokemon_ex_card(card.card_id) == :ok
  end

  defp rare_candy_target_card?(%CardInstance{} = card, player_id, turn_number) do
    card.owner_player_id == player_id and card.zone in [:active, :bench] and
      require_basic_pokemon(card.card_id) == :ok and
      require_in_play_pokemon_zone(card) == :ok and
      require_can_evolve_target(card, turn_number) == :ok
  end

  defp selected_wallys_compassion_target(cards, player_id) do
    case Enum.filter(cards, &wallys_compassion_target_card?(&1, player_id)) do
      [target_card] -> {:ok, target_card}
      [] -> {:error, :missing_wallys_compassion_target}
      targets -> {:error, {:too_many_wallys_compassion_targets, length(targets)}}
    end
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

  defp require_all_energy_cards(cards) do
    cards
    |> Enum.map(&require_energy(&1.card_id))
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

  defp flip_coin_for_effect(%Game{rng_seed: seed}, turn, %GamePlayer{} = player, card, effect)
       when is_binary(seed) do
    Rng.choice(
      @coin_faces,
      seed,
      effect_coin_flip_rng_context(player.player_id, turn, card, effect)
    )
  end

  defp flip_coin_for_effect(%Game{}, _turn, _player, _card, _effect),
    do: {:ok, Enum.random(@coin_faces)}

  defp write_effect_coin_flipped(%Game{} = game, turn, player_id, card, effect, result) do
    payload =
      maybe_put_effect_coin_flip_rng_payload(
        %{
          turn_id: turn.id,
          source: EventPayloads.card_source(card),
          source_card_id: card.card_id,
          effect_key: effect.key,
          result: result
        },
        game,
        turn,
        player_id,
        card,
        effect
      )

    write_event_and_snapshot(game.id, :coin_flipped, player_id, payload)
  end

  defp maybe_put_effect_coin_flip_rng_payload(
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
      rng_context: effect_coin_flip_rng_context_label(player_id, turn, card, effect),
      rng_seed_source: game.rng_seed_source
    })
  end

  defp maybe_put_effect_coin_flip_rng_payload(
         payload,
         %Game{},
         _turn,
         _player_id,
         _card,
         _effect
       ), do: payload

  defp effect_coin_flip_rng_context(player_id, turn, card, effect) do
    {:trainer_effect_coin_flip, player_id, turn.turn_number, card.card_id, effect.key}
  end

  defp effect_coin_flip_rng_context_label(player_id, turn, card, effect) do
    "trainer_effect_coin_flip:#{player_id}:turn_#{turn.turn_number}:#{card.card_id}:#{effect.key}"
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

  defp rosa_attached_energy_payloads(energy_cards, target_cards) do
    energy_cards
    |> Enum.zip(target_cards)
    |> Enum.map(fn {energy_card, target_card} ->
      moved_card_payload(energy_card, :discard, :attached,
        to_attached_to_card_instance_id: target_card.id
      )
    end)
  end

  defp wondrous_patch_attached_energy_payloads(energy_card, target_card) do
    [
      moved_card_payload(energy_card, :discard, :attached,
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

  defp wallys_compassion_returned_energy_payloads(returned_energy_cards, target_card_instance_id) do
    Enum.map(returned_energy_cards, fn returned_energy_card ->
      moved_card_payload(returned_energy_card, :attached, :hand,
        from_attached_to_card_instance_id: target_card_instance_id
      )
    end)
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

  defp sacred_ash_public_note(1), do: "Sacred Ash shuffled 1 Pokémon from discard into the deck."

  defp sacred_ash_public_note(card_count),
    do: "Sacred Ash shuffled #{card_count} Pokémon from discard into the deck."

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

  defp prompt_payload(game_id, player_id, choice_key, legal_choice_ids, min, max) do
    maybe_put_prompt_choice_labels(
      %{
        choice_key: Atom.to_string(choice_key),
        legal_choices: legal_choice_ids,
        min: min,
        max: max
      },
      game_id,
      player_id,
      choice_key,
      legal_choice_ids
    )
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :opponent_discards_to_hand_size,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&xerosics_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :discard_opponent_item_cards_from_hand,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&eri_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :attach_basic_energy_from_discard_to_stage2_if_more_prizes,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&rosa_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :attach_basic_psychic_energy_from_discard_to_benched_psychic_pokemon,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&wondrous_patch_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&wallys_compassion_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
         :switch_own_active_with_bench,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&switch_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
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
         _player_id,
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
         _player_id,
         :search_deck_for_item_tool_supporter_stadium,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&secret_box_choice_label/1)

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         player_id,
         :switch_team_rocket_bench_and_opponent_bench_to_active,
         legal_choice_ids
       ) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards_by_id = Map.new(cards, &{&1.id, &1})

        labels =
          legal_choice_ids
          |> Enum.map(&Map.get(cards_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&team_rockets_giovanni_choice_label(&1, player_id))

        Map.put(payload, :legal_choice_labels, labels)

      {:error, _reason} ->
        payload
    end
  end

  defp maybe_put_prompt_choice_labels(
         payload,
         game_id,
         _player_id,
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

  defp maybe_put_prompt_choice_labels(
         payload,
         _game_id,
         _player_id,
         _choice_key,
         _legal_choice_ids
       ), do: payload

  defp team_rockets_giovanni_choice_label(
         %CardInstance{owner_player_id: player_id} = card,
         player_id
       ) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Your Benched Team Rocket Pokémon to switch into the Active Spot first."
    }
  end

  defp team_rockets_giovanni_choice_label(%CardInstance{} = card, _player_id) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "Opponent Benched Pokémon to switch into the Active Spot after your Team Rocket switch."
    }
  end

  defp xerosics_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Card in your hand. Discard enough chosen cards until you have 3 cards remaining."
    }
  end

  defp eri_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Item card in your opponent's revealed hand. Choose up to 2 Item cards to discard."
    }
  end

  defp rosa_choice_label(%CardInstance{zone: :discard} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Basic Energy in your discard pile to attach with Rosa's Encouragement."
    }
  end

  defp rosa_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "Your Stage 2 Pokémon in #{Atom.to_string(card.zone)} to receive all selected Basic Energy cards."
    }
  end

  defp wondrous_patch_choice_label(%CardInstance{zone: :discard} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Basic Psychic Energy in your discard pile to attach with Wondrous Patch."
    }
  end

  defp wondrous_patch_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Your Benched Psychic Pokémon to receive the selected Basic Psychic Energy."
    }
  end

  defp wallys_compassion_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "Damaged Mega Evolution Pokémon ex in #{Atom.to_string(card.zone)}. Wally's Compassion heals it, then returns its attached Energy to hand."
    }
  end

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

  defp switch_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail: "Your Benched Pokémon to switch into the Active Spot."
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

  defp secret_box_choice_label(%CardInstance{} = card) do
    %{
      id: card.id,
      label: card_name(card, card.card_id),
      detail:
        "#{secret_box_trainer_type_label(card.card_id)} in deck. Secret Box accepts at most one of each Trainer category."
    }
  end

  defp secret_box_trainer_type_label(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{trainer_type: trainer_type}}
      when trainer_type in [:item, :tool, :supporter, :stadium] ->
        trainer_type |> Atom.to_string() |> String.capitalize()

      _other ->
        "Trainer"
    end
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

  defp choice_prompt_player_id(game_id, player_id, definition, choice_key) do
    case effect_step(definition, choice_key) do
      %{type: :opponent_discards_to_hand_size} ->
        with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id) do
          {:ok, opponent_player.player_id}
        end

      _other ->
        {:ok, player_id}
    end
  end

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

  defp shuffle_hand_to_bottom_of_deck(%Game{} = game, turn, %GamePlayer{} = player, card, effect) do
    context =
      {:trainer_effect_hand_shuffle_to_bottom, player.player_id, turn.turn_number, card.card_id,
       effect.key}

    with {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, player.player_id, :hand),
         {:ok, deck_count} <- CardStore.deck_count(game.id, player.player_id) do
      hand_cards
      |> shuffle_cards(game.rng_seed, context)
      |> Enum.with_index(deck_count + 1)
      |> Enum.map(fn {card, position} ->
        update(card, :shuffle_into_deck, %{attached_to_card_instance_id: nil, position: position})
      end)
      |> collect_results()
    end
  end

  defp maybe_draw_after_opponent_hand_bottomed(
         %Game{} = game,
         %GamePlayer{} = player,
         [_first | _rest],
         %{
           params: %{draw_count: draw_count}
         }
       ) do
    draw_cards_for_effect(game, player, draw_count)
  end

  defp maybe_draw_after_opponent_hand_bottomed(%Game{}, %GamePlayer{}, [], _effect) do
    {:ok, []}
  end

  defp maybe_write_cards_moved_event(_game_id, _player_id, [], _card, _effect), do: {:ok, nil}

  defp maybe_write_cards_moved_event(game_id, player_id, cards, card, effect) do
    write_event_and_snapshot(game_id, :cards_moved, player_id, %{
      reason: :effect_resolution,
      source: EventPayloads.card_source(card),
      effect_key: effect.key,
      affected_player_id: player_id,
      cards: EventPayloads.moved_cards(cards, :hand, :discard)
    })
  end

  defp require_all_eri_targets(game_id, player_id, target_cards) do
    with {:ok, opponent_player} <- CardStore.get_opponent(game_id, player_id),
         :ok <- require_all_owned_in_zone(target_cards, opponent_player.player_id, :hand) do
      require_all_item_cards(target_cards)
    end
  end

  defp require_all_item_cards(target_cards) do
    target_cards
    |> Enum.map(fn card ->
      case require_trainer_type(card.card_id, [:item]) do
        {:ok, _metadata} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
    |> collect_ok_results()
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
    with {:ok, draw_count} <-
           shuffle_each_player_draw_count(game.id, action_player, affected_player, effect),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, affected_player.player_id, :hand),
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

  defp shuffle_each_player_draw_count(
         _game_id,
         %GamePlayer{player_id: action_player_id},
         %GamePlayer{player_id: affected_player_id},
         %{
           params: %{
             player_draw_count: player_draw_count,
             opponent_draw_count: opponent_draw_count
           }
         }
       ) do
    if affected_player_id == action_player_id do
      {:ok, player_draw_count}
    else
      {:ok, opponent_draw_count}
    end
  end

  defp shuffle_each_player_draw_count(game_id, _action_player, affected_player, effect) do
    draw_count_for_effect(game_id, affected_player.player_id, effect)
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

  defp require_each_player_can_draw_after_hand_shuffle(
         game,
         action_player,
         affected_players,
         effect
       ) do
    affected_players
    |> Enum.map(&require_can_draw_after_hand_shuffle(game, action_player, &1, effect))
    |> collect_ok_results()
  end

  defp require_can_draw_after_hand_shuffle(%Game{} = game, %GamePlayer{} = player, effect) do
    require_can_draw_after_hand_shuffle(game, player, player, effect)
  end

  defp require_can_draw_after_hand_shuffle(
         %Game{} = game,
         %GamePlayer{} = action_player,
         %GamePlayer{} = player,
         effect
       ) do
    with {:ok, draw_count} <-
           shuffle_each_player_draw_count(game.id, action_player, player, effect),
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

  defp draw_until_hand_size_for_effect(%Game{} = game, %GamePlayer{} = player, target_hand_size) do
    with {:ok, hand_cards} <- CardStore.cards_in_zone(game.id, player.player_id, :hand),
         desired_draw_count = max(target_hand_size - length(hand_cards), 0),
         {:ok, cards} <- CardStore.deck_cards_for_player(player.id, desired_draw_count),
         {:ok, starting_position} <-
           CardStore.next_hand_position_result(game.id, player.player_id) do
      draw_cards_to_hand(cards, starting_position)
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

  defp xerosics_discard_count(hand_cards, %{params: %{target_hand_size: target_hand_size}}) do
    max(length(hand_cards) - target_hand_size, 0)
  end

  defp resolve_attack_damage_to_target(game_id, target_pokemon, amount, source_card, effect) do
    current_damage = target_pokemon.damage || 0
    new_damage = current_damage + amount

    with {:ok, updated_target} <-
           update(target_pokemon, :set_damage, %{damage: new_damage}),
         {:ok, _event} <-
           write_event_and_snapshot(
             game_id,
             :resolve_declared_attack,
             target_pokemon.owner_player_id,
             %{
               source_card_id: source_card.card_id,
               source_card_instance_id: source_card.id,
               effect_key: effect.key,
               target_card_id: target_pokemon.card_id,
               target_card_instance_id: target_pokemon.id,
               damage_dealt: amount,
               resulting_damage: new_damage
             }
           ) do
      {:ok, updated_target}
    end
  end

  defp own_active_card(game_id, player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      case Enum.filter(cards, &(&1.owner_player_id == player_id and &1.zone == :active)) do
        [active_card] -> {:ok, active_card}
        [] -> {:error, :missing_active_pokemon}
        _multiple -> {:error, :ambiguous_active_pokemon}
      end
    end
  end

  defp opponent_switch_payload(active_card, bench_card) do
    [
      switched_card_payload(active_card, :active, :bench),
      switched_card_payload(bench_card, :bench, :active)
    ]
  end

  defp team_rockets_giovanni_switch_payload(
         own_active_card,
         own_bench_card,
         opponent_active_card,
         opponent_bench_card
       ) do
    [
      switched_card_payload(own_active_card, :active, :bench),
      switched_card_payload(own_bench_card, :bench, :active),
      switched_card_payload(opponent_active_card, :active, :bench),
      switched_card_payload(opponent_bench_card, :bench, :active)
    ]
  end

  defp wallys_compassion_public_note(%CardInstance{} = target_card, healed_damage, 0)
       when healed_damage > 0 do
    "Wally's Compassion healed all damage from #{card_name(target_card, target_card.card_id)}."
  end

  defp wallys_compassion_public_note(%CardInstance{} = target_card, healed_damage, 1)
       when healed_damage > 0 do
    "Wally's Compassion healed all damage from #{card_name(target_card, target_card.card_id)} and returned 1 attached Energy card to hand."
  end

  defp wallys_compassion_public_note(
         %CardInstance{} = target_card,
         healed_damage,
         returned_energy_count
       )
       when healed_damage > 0 do
    "Wally's Compassion healed all damage from #{card_name(target_card, target_card.card_id)} and returned #{returned_energy_count} attached Energy cards to hand."
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

  defp attach_basic_energy_from_discard(game_id, energy_cards, target_cards)
       when is_list(energy_cards) and is_list(target_cards) do
    energy_cards
    |> Enum.zip(target_cards)
    |> Enum.reduce_while(:ok, fn {energy, target}, :ok ->
      case Prizmo.TcgEngine.Mechanics.attach_energy_from_discard(
             game_id,
             energy,
             target
           ) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end

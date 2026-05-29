defmodule Prizmo.TcgEngine.CardPlay do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [require_pokemon_card: 1, require_trainer_type: 2]

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [
      require_ace_spec_available: 2,
      require_card_owned_by_player: 2,
      require_card_zone: 2,
      require_supporter_available: 2
    ]

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
  alias Prizmo.TcgEngine.Prompt
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

  def resolve_play_card_costs(game, turn, player, card, metadata, definition, choices) do
    with {:ok, cost} <- CostRunner.first_cost(definition),
         {:ok, _event} <-
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
  end

  def resume_pending_effect(%Game{} = game, pending_effect, choice_key, submitted_choice) do
    state = pending_effect.state || %{}

    with {:ok, player} <-
           Prizmo.TcgEngine.PlayerStore.get_player(game.id, Map.fetch!(state, "player_id")),
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
         {:ok, discarded_trainer} <-
           TrainerPlay.discard_trainer_card(game, player, card, metadata),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :played_trainer_discarded,
             source: EventPayloads.card_source(card),
             cards: EventPayloads.moved_cards([discarded_trainer], :hand, :discard)
           }) do
      resolve_play_card_effects(game, turn, player, card, definition, choices)
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

  defp complete_play_card_effect(game, turn, player, card, effect, target_ids) do
    with {:ok, target_card} <-
           validate_search_deck_effect(game.id, player.player_id, effect, target_ids),
         {:ok, moved_target} <-
           CardStore.move_deck_card_to_hand(game.id, player.player_id, target_card),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards: EventPayloads.moved_cards([moved_target], :deck, :hand)
           }),
         {:ok, _event} <- maybe_write_deck_shuffled(game.id, player.player_id, card, effect),
         {:ok, _event} <-
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
           legal_choice_ids(game.id, player.player_id, card.id, definition, choice_key),
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
             payload: %{
               choice_key: Atom.to_string(choice_key),
               legal_choices: legal_choice_ids,
               min: ChoiceValidator.count_for(definition, choice_key),
               max: ChoiceValidator.count_for(definition, choice_key)
             }
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
    with {:ok, target_id} <- EffectRunner.validate_search_deck_selection(effect, target_ids),
         {:ok, target_card} <- CardStore.get_card(game_id, target_id),
         :ok <- require_card_owned_by_player(target_card, player_id),
         :ok <- require_card_zone(target_card, :deck),
         :ok <- require_search_filter(target_card, effect.params.filter) do
      {:ok, target_card}
    end
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon}),
    do: require_pokemon_card(card.card_id)

  defp legal_choice_ids(game_id, player_id, action_card_id, definition, choice_key) do
    cond do
      Enum.any?(definition.costs, &(&1.key == choice_key)) ->
        with {:ok, hand} <- CardStore.cards_in_zone(game_id, player_id, :hand) do
          {:ok, hand |> Enum.reject(&(&1.id == action_card_id)) |> Enum.map(& &1.id)}
        end

      Enum.any?(definition.effects, &(&1.key == choice_key)) ->
        with {:ok, deck} <- CardStore.cards_in_zone(game_id, player_id, :deck) do
          deck
          |> Enum.filter(fn card -> require_pokemon_card(card.card_id) == :ok end)
          |> Enum.map(& &1.id)
          |> then(&{:ok, &1})
        end

      true ->
        {:error, {:unknown_choice_key, choice_key}}
    end
  end

  defp maybe_write_deck_shuffled(
         game_id,
         player_id,
         card,
         %{params: %{shuffle_after: true}} = effect
       ) do
    write_event_and_snapshot(game_id, :deck_shuffled, player_id, %{
      source: EventPayloads.card_source(card),
      effect_key: effect.key
    })
  end

  defp maybe_write_deck_shuffled(_game_id, _player_id, _card, _effect), do: {:ok, nil}

  defp require_all_owned_in_zone(cards, player_id, zone) do
    cards
    |> Enum.map(fn card ->
      with :ok <- require_card_owned_by_player(card, player_id) do
        require_card_zone(card, zone)
      end
    end)
    |> collect_ok_results()
  end

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end
end

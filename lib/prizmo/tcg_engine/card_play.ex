defmodule Prizmo.TcgEngine.CardPlay do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements,
    only: [
      require_non_rule_box_pokemon_card: 1,
      require_poffin_targets: 1,
      require_pokemon_card: 1,
      require_trainer_type: 2
    ]

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

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

  def required_choices_available?(cards, %CardInstance{} = action_card, definition)
      when is_list(cards) do
    Enum.all?(choice_steps(definition), fn choice_step ->
      case legal_choice_ids(cards, action_card.owner_player_id, action_card.id, choice_step) do
        {:ok, legal_choice_ids} ->
          required_choice_count_available?(legal_choice_ids, definition, choice_step.key)

        {:error, _reason} ->
          false
      end
    end)
  end

  def require_required_choices_available(game_id, player_id, action_card_id, definition)
      when is_binary(game_id) and is_binary(player_id) and is_binary(action_card_id) do
    Enum.reduce_while(choice_steps(definition), :ok, fn choice_step, :ok ->
      with {:ok, legal_choice_ids} <-
             legal_choice_ids(game_id, player_id, action_card_id, definition, choice_step.key),
           :ok <- require_required_choice_count(legal_choice_ids, definition, choice_step.key) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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
           write_event_and_snapshot(game.id, :cards_moved, player.player_id, %{
             reason: :effect_resolution,
             source: EventPayloads.card_source(card),
             effect_key: effect.key,
             cards:
               EventPayloads.moved_cards(
                 moved_targets,
                 :deck,
                 search_effect_destination_zone(effect)
               )
           }),
         {:ok, _event} <- maybe_write_deck_shuffled(game.id, player.player_id, card, effect) do
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
           legal_choice_ids(game.id, player.player_id, card.id, definition, choice_key),
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
             payload: %{
               choice_key: Atom.to_string(choice_key),
               legal_choices: legal_choice_ids,
               min: min,
               max: max
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
    with {:ok, target_ids} <- EffectRunner.validate_search_deck_selection(effect, target_ids),
         {:ok, target_cards} <- CardStore.get_cards(game_id, target_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_search_filters(target_cards, effect.params.filter) do
      {:ok, target_cards}
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

  defp search_effect_destination_zone(%{params: %{destination: :bench}}), do: :bench
  defp search_effect_destination_zone(%{params: %{destination: :hand}}), do: :hand

  defp effect_choice_ids(cards, player_id, %{type: :search_deck} = choice_step) do
    cards
    |> search_deck_choice_cards(player_id, choice_step)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(cards, player_id, %{type: :switch_opponent_bench_to_active}) do
    cards
    |> opponent_bench_choice_cards(player_id)
    |> Enum.map(& &1.id)
    |> then(&{:ok, &1})
  end

  defp effect_choice_ids(_cards, _player_id, choice_step) do
    {:error, {:unsupported_choice_step, choice_step.key, choice_step.type}}
  end

  defp legal_choice_ids(game_id, player_id, action_card_id, definition, choice_key) do
    cond do
      Enum.any?(definition.costs, &(&1.key == choice_key)) ->
        with {:ok, hand} <- CardStore.cards_in_zone(game_id, player_id, :hand) do
          {:ok, hand |> Enum.reject(&(&1.id == action_card_id)) |> Enum.map(& &1.id)}
        end

      Enum.any?(definition.effects, &(&1.key == choice_key)) ->
        with {:ok, cards} <- CardStore.list_cards(game_id) do
          effect_choice_ids(cards, player_id, effect_step(definition, choice_key))
        end

      true ->
        {:error, {:unknown_choice_key, choice_key}}
    end
  end

  defp legal_choice_ids(cards, player_id, action_card_id, choice_step) do
    case choice_step.type do
      :discard_from_hand ->
        cards
        |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :hand))
        |> Enum.reject(&(&1.id == action_card_id))
        |> Enum.map(& &1.id)
        |> then(&{:ok, &1})

      type when type in [:search_deck, :switch_opponent_bench_to_active] ->
        effect_choice_ids(cards, player_id, choice_step)

      _other ->
        {:error, {:unsupported_choice_step, choice_step.key, choice_step.type}}
    end
  end

  defp choice_steps(definition), do: definition.costs ++ definition.effects

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

    {min, max}
  end

  defp maybe_cap_bench_choice_max(max, game_id, player_id, %{params: %{destination: :bench}}) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} -> min(max, bench_space(cards, player_id))
      {:error, _reason} -> max
    end
  end

  defp maybe_cap_bench_choice_max(max, _game_id, _player_id, _choice_step), do: max

  defp search_deck_choice_cards(cards, player_id, choice_step) do
    cards
    |> Enum.filter(&(&1.owner_player_id == player_id and &1.zone == :deck))
    |> Enum.filter(&matches_search_filter?(&1, choice_step.params.filter))
    |> maybe_hide_when_bench_full(cards, player_id, choice_step)
  end

  defp opponent_bench_choice_cards(cards, player_id) do
    cards
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :bench))
    |> Enum.sort_by(&{&1.owner_player_id, &1.position, &1.instance_id})
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

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, stage: :basic, max_hp: 70}) do
    require_poffin_targets([card])
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon, rule_box?: false}) do
    require_non_rule_box_pokemon_card(card.card_id)
  end

  defp require_search_filter(%CardInstance{} = card, %{kind: :pokemon}) do
    require_pokemon_card(card.card_id)
  end

  defp require_search_filter(_card, _filter), do: {:error, :unsupported_search_filter}

  defp effect_step(definition, choice_key) do
    Enum.find(definition.effects, &(&1.key == choice_key))
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

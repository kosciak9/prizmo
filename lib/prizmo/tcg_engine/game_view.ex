defmodule Prizmo.TcgEngine.GameView do
  @moduledoc false

  alias Prizmo.TcgEngine.AttackAccess
  alias Prizmo.TcgEngine.AttackCosts
  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameSetup
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.GameView.ActionAffordances
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.SpecialConditions
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @doc "Returns a viewer-scoped read model for the persisted game state."
  def for_player(game_id, viewer_player_id)
      when is_binary(game_id) and is_binary(viewer_player_id) do
    with {:ok, game} <- GameStore.get_game(game_id),
         {:ok, players} <- PlayerStore.list_players(game.id),
         :ok <- require_viewer(players, viewer_player_id),
         {:ok, cards} <- CardStore.list_cards(game.id),
         {:ok, events} <- list_events(game),
         {:ok, mulligan_stats} <- GameSetup.mulligan_stats(game, players),
         {:ok, setup} <- maybe_setup(game.id),
         {:ok, current_turn} <- maybe_current_turn(game.id),
         {:ok, awaiting_prompts} <- list_awaiting_prompts(game.id) do
      prompts = viewer_prompts(awaiting_prompts, viewer_player_id)
      attached_cards_by_target = attached_cards_by_target(cards)

      {:ok,
       %{
         game_id: game.id,
         viewer_player_id: viewer_player_id,
         status: stringify(game.status),
         flow_state: stringify(game.flow_state),
         active_player_id: game.active_player_id,
         first_player_id: game.first_player_id,
         winner_player_id: game.winner_player_id,
         coin_toss_calling_player_id: game.coin_toss_calling_player_id,
         coin_toss_call: stringify(game.coin_toss_call),
         coin_toss_result: stringify(game.coin_toss_result),
         coin_toss_winner_player_id: game.coin_toss_winner_player_id,
         starting_player_chosen_by_player_id: game.starting_player_chosen_by_player_id,
         cursor_index: game.cursor_index,
         latest_event_index: game.latest_event_index,
         awaiting_prompt_player_ids: awaiting_prompt_player_ids(awaiting_prompts),
         setup: setup_view(setup),
         current_turn: turn_view(current_turn, cards, viewer_player_id),
         action_affordances:
           ActionAffordances.for_viewer(
             game,
             current_turn,
             players,
             cards,
             prompts,
             viewer_player_id,
             awaiting_prompt_player_ids(awaiting_prompts)
           ),
         stadium: stadium_view(cards, attached_cards_by_target),
         players:
           player_views(
             players,
             cards,
             viewer_player_id,
             attached_cards_by_target,
             mulligan_stats
           ),
         events: Enum.map(events, &event_view/1),
         prompts: Enum.map(prompts, &prompt_view(&1, cards, attached_cards_by_target))
       }}
    end
  end

  def for_player(_game_id, _viewer_player_id), do: {:error, :invalid_game_view_arguments}

  defp require_viewer(players, viewer_player_id) do
    if Enum.any?(players, &(&1.player_id == viewer_player_id)) do
      :ok
    else
      {:error, :viewer_player_not_found}
    end
  end

  defp maybe_setup(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one()
  end

  defp maybe_current_turn(game_id), do: TurnStore.latest_turn(game_id)

  defp list_events(%Game{} = game) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game.id and index <= ^game.cursor_index)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp list_awaiting_prompts(game_id) do
    Prompt
    |> Ash.Query.filter(game_id == ^game_id and status == :awaiting_choice)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read()
  end

  defp viewer_prompts(prompts, viewer_player_id) do
    Enum.filter(prompts, &(&1.player_id == viewer_player_id))
  end

  defp awaiting_prompt_player_ids(prompts) do
    prompts
    |> Enum.map(& &1.player_id)
    |> Enum.uniq()
  end

  defp setup_view(nil), do: nil

  defp setup_view(%Setup{} = setup) do
    %{
      id: setup.id,
      status: stringify(setup.status)
    }
  end

  defp turn_view(nil, _cards, _viewer_player_id), do: nil

  defp turn_view(%Turn{} = turn, cards, viewer_player_id) do
    pending_attack_effect_type = pending_attack_effect_type(turn, cards)

    pending_attack_copy_choices =
      pending_attack_copy_choices(turn, cards, pending_attack_effect_type)

    pending_attack_blocked_attack_choices =
      pending_attack_blocked_attack_choices(turn, cards, pending_attack_effect_type)

    pending_attack_opponent_hand_discard_choices =
      pending_attack_opponent_hand_discard_choices(
        turn,
        cards,
        pending_attack_effect_type,
        viewer_player_id
      )

    pending_attack_opponent_pokemon_damage_choices =
      pending_attack_opponent_pokemon_damage_choices(
        turn,
        cards,
        pending_attack_effect_type
      )

    %{
      id: turn.id,
      turn_number: turn.turn_number,
      active_player_id: turn.active_player_id,
      status: stringify(turn.status),
      visible: turn.visible?,
      pending_attack_id: stringify(turn.pending_attack_id),
      pending_attack_effect_type: stringify(pending_attack_effect_type),
      pending_attack_requires_switch_target:
        pending_attack_effect_type == :switch_self_with_bench,
      pending_attack_requires_discarded_energy:
        pending_attack_effect_type in [
          :damage_per_discarded_own_basic_energy,
          :discard_defending_energy_on_coin_heads,
          :discard_energy_from_own_bench_for_bonus_damage,
          :discard_attached_energy_for_bonus_damage,
          :discard_attached_energy_then_damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects
        ],
      pending_attack_requires_returned_energy:
        pending_attack_effect_type == :return_attached_energy_to_hand,
      pending_attack_requires_shuffled_energy:
        pending_attack_effect_type ==
          :shuffle_attached_energy_into_deck_then_damage_opponent_bench,
      pending_attack_requires_bench_damage_target:
        pending_attack_effect_type in [
          :damage_opponent_bench,
          :shuffle_attached_energy_into_deck_then_damage_opponent_bench
        ],
      pending_attack_requires_bench_damage_counters:
        pending_attack_effect_type == :opponent_bench_damage_counters,
      pending_attack_requires_opponent_pokemon_damage_targets:
        pending_attack_effect_type in [
          :damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects,
          :discard_attached_energy_then_damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects
        ],
      pending_attack_opponent_pokemon_damage_choices:
        pending_attack_opponent_pokemon_damage_choices,
      pending_attack_requires_coin_result:
        pending_attack_effect_type in [
          :bonus_damage_on_coin_heads,
          :discard_defending_energy_on_coin_heads,
          :paralyze_defender_on_coin_heads,
          :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads
        ],
      pending_attack_requires_heads_count:
        pending_attack_effect_type == :bonus_damage_per_coin_heads_count,
      pending_attack_requires_copied_attack:
        pending_attack_effect_type == :copy_opponent_active_tera_pokemon_attack,
      pending_attack_copy_choices: pending_attack_copy_choices,
      pending_attack_requires_blocked_attack:
        pending_attack_effect_type == :defending_pokemon_cannot_use_selected_attack_next_turn,
      pending_attack_blocked_attack_choices: pending_attack_blocked_attack_choices,
      pending_attack_requires_opponent_hand_discard:
        pending_attack_effect_type == :discard_one_card_from_opponent_hand,
      pending_attack_opponent_hand_discard_choices: pending_attack_opponent_hand_discard_choices,
      pending_attacker_card_instance_id: turn.pending_attacker_card_instance_id,
      pending_defender_card_instance_id: turn.pending_defender_card_instance_id
    }
  end

  defp pending_attack_effect_type(
         %Turn{pending_attack_id: attack_id, pending_attacker_card_instance_id: attacker_id},
         cards
       )
       when not is_nil(attack_id) and not is_nil(attacker_id) do
    with %CardInstance{} = attacker_card <- Enum.find(cards, &(&1.id == attacker_id)),
         {:ok, %{effect: effect}} when is_map(effect) <-
           AttackAccess.fetch_attack(attacker_card.game_id, attacker_card, attack_id) do
      AttackEffects.type(effect)
    else
      _other -> nil
    end
  end

  defp pending_attack_effect_type(%Turn{}, _cards), do: nil

  defp pending_attack_copy_choices(
         %Turn{pending_defender_card_instance_id: defender_id},
         cards,
         :copy_opponent_active_tera_pokemon_attack
       )
       when not is_nil(defender_id) do
    with %CardInstance{} = defender_card <- Enum.find(cards, &(&1.id == defender_id)),
         {:ok, choices} <- AttackEffects.copyable_attack_choices(defender_card) do
      choices
    else
      _other -> []
    end
  end

  defp pending_attack_copy_choices(%Turn{}, _cards, _pending_attack_effect_type), do: []

  defp pending_attack_blocked_attack_choices(
         %Turn{pending_defender_card_instance_id: defender_id},
         cards,
         :defending_pokemon_cannot_use_selected_attack_next_turn
       )
       when not is_nil(defender_id) do
    with %CardInstance{} = defender_card <- Enum.find(cards, &(&1.id == defender_id)),
         {:ok, choices} <- AttackEffects.blockable_attack_choices(defender_card) do
      choices
    else
      _other -> []
    end
  end

  defp pending_attack_blocked_attack_choices(%Turn{}, _cards, _pending_attack_effect_type), do: []

  defp pending_attack_opponent_hand_discard_choices(
         %Turn{active_player_id: active_player_id},
         cards,
         :discard_one_card_from_opponent_hand,
         active_player_id
       ) do
    cards
    |> Enum.filter(&(&1.owner_player_id != active_player_id and &1.zone == :hand))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
    |> Enum.map(&pending_attack_card_choice/1)
  end

  defp pending_attack_opponent_hand_discard_choices(
         %Turn{},
         _cards,
         _pending_attack_effect_type,
         _viewer_player_id
       ),
       do: []

  defp pending_attack_opponent_pokemon_damage_choices(
         %Turn{active_player_id: active_player_id},
         cards,
         pending_attack_effect_type
       )
       when pending_attack_effect_type in [
              :damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects,
              :discard_attached_energy_then_damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects
            ] do
    cards
    |> Enum.filter(&(&1.owner_player_id != active_player_id and &1.zone in [:active, :bench]))
    |> Enum.sort_by(&{in_play_zone_sort(&1.zone), &1.position, &1.instance_id})
    |> Enum.map(&pending_attack_card_choice/1)
  end

  defp pending_attack_opponent_pokemon_damage_choices(
         %Turn{},
         _cards,
         _pending_attack_effect_type
       ), do: []

  defp in_play_zone_sort(:active), do: 0
  defp in_play_zone_sort(:bench), do: 1
  defp in_play_zone_sort(_zone), do: 2

  defp pending_attack_card_choice(%CardInstance{} = card) do
    catalog = catalog_card(card.card_id)

    %{
      id: card.id,
      card_id: card.card_id,
      name: Map.get(catalog, :name, card.card_id),
      image: Map.get(catalog, :image),
      category: stringify(Map.get(catalog, :category)),
      stage: stringify(Map.get(catalog, :stage))
    }
  end

  defp stadium_view(cards, attached_cards_by_target) do
    cards
    |> cards_in_zone(:stadium)
    |> List.first()
    |> card_view(attached_cards_by_target)
  end

  defp player_views(players, cards, viewer_player_id, attached_cards_by_target, mulligan_stats) do
    cards_by_player = Enum.group_by(cards, & &1.owner_player_id)

    Enum.map(players, fn player ->
      player_cards = Map.get(cards_by_player, player.player_id, [])
      viewer? = player.player_id == viewer_player_id
      player_mulligan_stats = Map.fetch!(mulligan_stats, player.player_id)

      %{
        player_id: player.player_id,
        deck_key: player.deck_key,
        energy_attached_this_turn: player.energy_attached_this_turn?,
        supporter_played_this_turn: player.supporter_played_this_turn?,
        retreated_this_turn: player.retreated_this_turn?,
        ace_spec_played_this_game: player.ace_spec_played_this_game?,
        setup_ready: player.setup_ready?,
        mulligans_taken: player_mulligan_stats.mulligans_taken,
        mulligan_bonus_draws_taken: player_mulligan_stats.mulligan_bonus_draws_taken,
        mulligan_bonus_draws_available: player_mulligan_stats.mulligan_bonus_draws_available,
        deck_count: zone_count(player_cards, :deck),
        hand_count: zone_count(player_cards, :hand),
        prize_count: zone_count(player_cards, :prize),
        discard_count: zone_count(player_cards, :discard),
        active:
          player_cards
          |> cards_in_zone(:active)
          |> List.first()
          |> card_view(attached_cards_by_target),
        bench:
          player_cards
          |> cards_in_zone(:bench)
          |> Enum.map(&card_view(&1, attached_cards_by_target)),
        hand: private_hand_view(player_cards, viewer?, attached_cards_by_target),
        discard:
          player_cards
          |> cards_in_zone(:discard)
          |> Enum.map(&card_view(&1, attached_cards_by_target))
      }
    end)
  end

  defp private_hand_view(player_cards, true, attached_cards_by_target) do
    player_cards
    |> cards_in_zone(:hand)
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp private_hand_view(_player_cards, false, _attached_cards_by_target), do: []

  defp attached_cards_by_target(cards) do
    cards
    |> Enum.reject(&is_nil(&1.attached_to_card_instance_id))
    |> Enum.group_by(& &1.attached_to_card_instance_id)
    |> Map.new(fn {target_id, attached_cards} ->
      {target_id, sort_attached_cards(attached_cards)}
    end)
  end

  defp sort_attached_cards(cards) do
    Enum.sort_by(cards, &{&1.position, &1.instance_id})
  end

  defp cards_in_zone(cards, zone) do
    cards
    |> Enum.filter(&(&1.zone == zone))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp zone_count(cards, zone), do: Enum.count(cards, &(&1.zone == zone))

  defp card_view(nil, _attached_cards_by_target), do: nil

  defp card_view(%CardInstance{} = card, attached_cards_by_target) do
    card
    |> card_summary()
    |> Map.put(
      :attached_cards,
      attached_card_views(card.id, attached_cards_by_target)
    )
  end

  defp attached_card_views(card_id, attached_cards_by_target) do
    attached_cards_by_target
    |> Map.get(card_id, [])
    |> Enum.map(&card_summary/1)
  end

  defp card_summary(%CardInstance{} = card) do
    catalog = catalog_card(card.card_id)
    rules_summary = rules_summary(card.card_id, catalog)

    %{
      id: card.id,
      instance_id: card.instance_id,
      card_id: card.card_id,
      name: Map.get(catalog, :name, card.card_id),
      image: Map.get(catalog, :image),
      category: stringify(Map.get(catalog, :category)),
      stage: stringify(Map.get(catalog, :stage)),
      rules_status: rules_summary.status,
      rules_label: rules_summary.label,
      rules_note: rules_summary.note,
      executable_attack_count: rules_summary.executable_attack_count,
      unsupported_attack_count: rules_summary.unsupported_attack_count,
      unsupported_ability_count: rules_summary.unsupported_ability_count,
      unsupported_actions: unsupported_action_summaries(card.card_id, catalog),
      owner_player_id: card.owner_player_id,
      zone: stringify(card.zone),
      position: card.position,
      damage: card.damage,
      status: stringify(card.status),
      status_conditions: card |> SpecialConditions.conditions() |> Enum.map(&Atom.to_string/1),
      attached_to_card_instance_id: card.attached_to_card_instance_id,
      evolves_from_card_instance_id: card.evolves_from_card_instance_id,
      turn_entered_play: card.turn_entered_play
    }
  end

  defp event_view(%GameEvent{} = event) do
    event
    |> public_event_details()
    |> Map.merge(%{
      id: event.id,
      index: event.index,
      type: event.type,
      player_id: event.player_id,
      turn_id: event.turn_id
    })
  end

  defp public_event_details(%GameEvent{type: "opening_hand_mulligan", payload: payload}) do
    revealed_cards = public_revealed_cards(payload, "returned_cards")
    card_count = payload_integer(payload, "returned_card_count") || length(revealed_cards)
    mulligan_number = payload_integer(payload, "mulligan_number")

    %{
      public_note: opening_hand_mulligan_note(card_count, mulligan_number),
      public_card_count: card_count,
      public_revealed_cards: revealed_cards
    }
  end

  defp public_event_details(%GameEvent{type: "mulligan_bonus_drawn", payload: payload}) do
    card_count = payload_integer(payload, "card_count") || 0

    %{
      public_note: "Drew #{card_count} optional mulligan bonus #{pluralize("card", card_count)}.",
      public_card_count: card_count,
      public_revealed_cards: []
    }
  end

  defp public_event_details(%GameEvent{type: "energy_attach_effect_drawn", payload: payload}) do
    card_count = payload_integer(payload, "card_count") || 0
    card_name = payload_card_name(payload, "energy_card_id", "Special Energy")

    %{
      public_note: "#{card_name} drew #{card_count} #{pluralize("card", card_count)}.",
      public_card_count: card_count,
      public_revealed_cards: []
    }
  end

  defp public_event_details(%GameEvent{type: "coin_flipped", payload: payload}) do
    card_name = payload_card_name(payload, "source_card_id", "Trainer")

    result =
      payload
      |> payload_value("result")
      |> stringify()
      |> case do
        nil -> "a coin"
        value -> value
      end

    %{
      public_note: "#{card_name} flipped #{result}.",
      public_card_count: 0,
      public_revealed_cards: []
    }
  end

  defp public_event_details(%GameEvent{type: "pokemon_checkup_effect_resolved", payload: payload}) do
    %{
      public_note:
        payload_value(payload, "public_note") ||
          "Pokémon Checkup resolved supported Ability effects.",
      public_card_count: 0,
      public_revealed_cards: []
    }
  end

  defp public_event_details(%GameEvent{type: "resolve_declared_attack", payload: payload}) do
    case payload_value(payload, "effect_type") do
      "lock_opponent_items_next_turn" ->
        card_name = payload_card_name(payload, "item_lock_source_card_id", "Itchy Pollen")

        %{
          public_note: "#{card_name} prevents the opponent from playing Item cards next turn.",
          public_card_count: 0,
          public_revealed_cards: []
        }

      "move_opponent_attached_energy_between_pokemon" ->
        if payload_value(payload, "moved_energy?") == true do
          energy_name = payload_card_name(payload, "moved_opponent_energy_card_id", "Energy")

          from_name =
            payload_card_name(payload, "moved_opponent_energy_from_card_id", "opponent Pokémon")

          to_name =
            payload_card_name(payload, "moved_opponent_energy_to_card_id", "opponent Pokémon")

          %{
            public_note: "Moved #{energy_name} from #{from_name} to #{to_name}.",
            public_card_count: 0,
            public_revealed_cards: []
          }
        else
          default_public_event_details()
        end

      "discard_one_card_from_opponent_hand" ->
        revealed_cards = public_revealed_cards(payload, "discarded_cards")

        %{
          public_note:
            payload_value(payload, "public_note") ||
              "Claw of Darkness revealed the opponent's hand and discarded #{length(revealed_cards)} #{pluralize("card", length(revealed_cards))}.",
          public_card_count: length(revealed_cards),
          public_revealed_cards: revealed_cards
        }

      "reveal_opponent_hand" ->
        revealed_cards = public_revealed_cards(payload, "revealed_cards")

        %{
          public_note:
            payload_value(payload, "public_note") ||
              "The opponent revealed #{length(revealed_cards)} #{pluralize("card", length(revealed_cards))} in hand.",
          public_card_count: length(revealed_cards),
          public_revealed_cards: revealed_cards
        }

      _other ->
        case payload_value(payload, "public_note") do
          note when is_binary(note) and note != "" ->
            %{
              public_note: note,
              public_card_count: 0,
              public_revealed_cards: []
            }

          _other ->
            default_public_event_details()
        end
    end
  end

  defp public_event_details(%GameEvent{type: "stadium_effect_used", payload: payload}) do
    card_name = payload_card_name(payload, "source_card_id", "Stadium")
    card_count = payload_integer(payload, "card_count") || 0

    %{
      public_note:
        payload_value(payload, "public_note") ||
          "#{card_name} resolved for #{card_count} #{pluralize("card", card_count)}.",
      public_card_count: card_count,
      public_revealed_cards: []
    }
  end

  defp public_event_details(%GameEvent{type: "ability_used", payload: payload}) do
    case payload_value(payload, "ability_id") do
      "adrena_brain" ->
        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Munkidori")} used Adrena-Brain.",
          public_card_count: 0,
          public_revealed_cards: []
        }

      "teal_dance" ->
        card_count = payload_integer(payload, "drawn_card_count") || 0

        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Teal Mask Ogerpon ex")} used Teal Dance.",
          public_card_count: card_count,
          public_revealed_cards: []
        }

      "flip_the_script" ->
        card_count = payload_integer(payload, "drawn_card_count") || 0

        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Fezandipiti ex")} used Flip the Script.",
          public_card_count: card_count,
          public_revealed_cards: []
        }

      "last_ditch_catch" ->
        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Meowth ex")} used Last-Ditch Catch.",
          public_card_count: 0,
          public_revealed_cards: []
        }

      "jewel_seeker" ->
        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Noctowl")} used Jewel Seeker.",
          public_card_count: 0,
          public_revealed_cards: []
        }

      "subjugating_chains" ->
        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_instance_id", "Pecharunt ex")} used Subjugating Chains.",
          public_card_count: 0,
          public_revealed_cards: []
        }

      "lunar_cycle" ->
        card_count = payload_integer(payload, "drawn_card_count") || 0

        %{
          public_note:
            payload_value(payload, "public_note") ||
              "#{payload_card_name(payload, "source_card_id", "Lunatone")} used Lunar Cycle.",
          public_card_count: card_count,
          public_revealed_cards: []
        }

      _other ->
        default_public_event_details()
    end
  end

  defp public_event_details(%GameEvent{type: "cards_moved", payload: payload}) do
    if payload_value(payload, "public_reveal") == true do
      revealed_cards = public_revealed_cards(payload, "revealed_cards")
      card_name = payload_card_name(payload, "source_card_id", "Card effect")

      %{
        public_note:
          payload_value(payload, "public_note") ||
            revealed_cards_note(card_name, length(revealed_cards)),
        public_card_count: length(revealed_cards),
        public_revealed_cards: revealed_cards
      }
    else
      default_public_event_details()
    end
  end

  defp public_event_details(%GameEvent{}) do
    default_public_event_details()
  end

  defp default_public_event_details do
    %{
      public_note: nil,
      public_card_count: 0,
      public_revealed_cards: []
    }
  end

  defp revealed_cards_note(card_name, 0), do: "#{card_name} revealed no cards."

  defp revealed_cards_note(card_name, 1), do: "#{card_name} revealed 1 card."

  defp revealed_cards_note(card_name, card_count),
    do: "#{card_name} revealed #{card_count} cards."

  defp opening_hand_mulligan_note(card_count, nil) do
    "Revealed a #{card_count}-card opening hand with no Basic Pokémon and took a mulligan."
  end

  defp opening_hand_mulligan_note(card_count, mulligan_number) do
    "Revealed a #{card_count}-card opening hand with no Basic Pokémon and took mulligan ##{mulligan_number}."
  end

  defp public_revealed_cards(payload, key) do
    payload
    |> payload_list(key)
    |> Enum.map(&payload_card_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&public_revealed_card/1)
  end

  defp payload_card_id(card_payload) when is_map(card_payload),
    do: payload_value(card_payload, "card_id")

  defp payload_card_id(_card_payload), do: nil

  defp public_revealed_card(card_id) when is_binary(card_id) do
    catalog = catalog_card(card_id)

    %{
      card_id: card_id,
      name: Map.get(catalog, :name, card_id),
      image: Map.get(catalog, :image),
      category: stringify(Map.get(catalog, :category)),
      stage: stringify(Map.get(catalog, :stage))
    }
  end

  defp payload_card_name(payload, key, fallback) do
    case payload_value(payload, key) do
      card_id when is_binary(card_id) ->
        card_id
        |> catalog_card()
        |> Map.get(:name, fallback)

      _other ->
        fallback
    end
  end

  defp payload_list(payload, key) do
    case payload_value(payload, key) do
      list when is_list(list) -> list
      _other -> []
    end
  end

  defp payload_integer(payload, key) do
    case payload_value(payload, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _other -> nil
    end
  end

  defp payload_value(payload, key) when is_map(payload) and is_binary(key) do
    case payload_atom_key(key) do
      nil -> Map.get(payload, key)
      atom_key -> Map.get(payload, key) || Map.get(payload, atom_key)
    end
  end

  defp payload_atom_key("card_count"), do: :card_count
  defp payload_atom_key("card_id"), do: :card_id
  defp payload_atom_key("energy_card_id"), do: :energy_card_id
  defp payload_atom_key("effect_type"), do: :effect_type
  defp payload_atom_key("item_lock_source_card_id"), do: :item_lock_source_card_id
  defp payload_atom_key("mulligan_number"), do: :mulligan_number
  defp payload_atom_key("moved_energy?"), do: :moved_energy?
  defp payload_atom_key("moved_opponent_energy_card_id"), do: :moved_opponent_energy_card_id

  defp payload_atom_key("moved_opponent_energy_from_card_id"),
    do: :moved_opponent_energy_from_card_id

  defp payload_atom_key("moved_opponent_energy_to_card_id"), do: :moved_opponent_energy_to_card_id
  defp payload_atom_key("public_note"), do: :public_note
  defp payload_atom_key("public_reveal"), do: :public_reveal
  defp payload_atom_key("revealed_cards"), do: :revealed_cards
  defp payload_atom_key("returned_card_count"), do: :returned_card_count
  defp payload_atom_key("returned_cards"), do: :returned_cards
  defp payload_atom_key("source_card_id"), do: :source_card_id
  defp payload_atom_key(_key), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _count), do: "#{word}s"

  defp prompt_view(%Prompt{} = prompt, cards, attached_cards_by_target) do
    %{
      id: prompt.id,
      prompt_type: prompt.prompt_type,
      status: stringify(prompt.status),
      player_id: prompt.player_id,
      payload: prompt_payload(prompt, cards, attached_cards_by_target)
    }
  end

  defp prompt_payload(%Prompt{payload: payload} = prompt, cards, attached_cards_by_target) do
    payload
    |> put_prompt_card_views(
      "legal_choice_cards",
      legal_choice_cards(prompt, cards, attached_cards_by_target)
    )
    |> put_prompt_card_views(
      "inspected_cards",
      inspected_cards(prompt, cards, attached_cards_by_target)
    )
  end

  defp put_prompt_card_views(payload, _key, []), do: payload
  defp put_prompt_card_views(payload, key, card_views), do: Map.put(payload, key, card_views)

  defp inspected_cards(
         %Prompt{payload: payload, player_id: player_id},
         cards,
         attached_cards_by_target
       ) do
    cards_by_id = Map.new(cards, &{&1.id, &1})

    payload
    |> Map.get("inspected_card_ids", [])
    |> case do
      ids when is_list(ids) -> ids
      _other -> []
    end
    |> Enum.map(&Map.get(cards_by_id, &1))
    |> Enum.filter(fn
      %CardInstance{owner_player_id: ^player_id} -> true
      _other -> false
    end)
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{prompt_type: "choose_knockout_prizes"},
         _cards,
         _attached_cards_by_target
       ), do: []

  defp legal_choice_cards(
         %Prompt{
           payload: %{"choice_key" => "discard_opponent_item_cards_from_hand"} = payload,
           player_id: player_id
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :hand))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload:
             %{"choice_key" => "switch_team_rocket_bench_and_opponent_bench_to_active"} = payload
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.zone == :bench))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload:
             %{
               "choice_key" => "switch_opponent_bench_to_active_then_switch_own_active_with_bench"
             } = payload
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.zone == :bench))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload: %{"choice_key" => "switch_opponent_bench_to_active"} = payload,
           player_id: player_id
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :bench))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload: %{"choice_key" => "discard_opponent_attached_energy_if_heads"} = payload,
           player_id: player_id
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :attached))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload: %{"choice_key" => "discard_opponent_special_energy"} = payload,
           player_id: player_id
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :attached))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{
           payload:
             %{"choice_key" => "discard_opponent_tool_and_special_energy_from_same_pokemon"} =
               payload,
           player_id: player_id
         },
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.owner_player_id != player_id and &1.zone == :attached))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{payload: %{"choice_key" => "discard_attached_tools"} = payload},
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(&(&1.zone == :attached))
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp legal_choice_cards(
         %Prompt{payload: payload, player_id: player_id},
         cards,
         attached_cards_by_target
       ) do
    payload
    |> prompt_choice_card_instances(cards)
    |> Enum.filter(fn
      %CardInstance{owner_player_id: ^player_id} -> true
      _other -> false
    end)
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp prompt_choice_card_instances(payload, cards) do
    cards_by_id = Map.new(cards, &{&1.id, &1})

    payload
    |> Map.get("legal_choices", [])
    |> case do
      ids when is_list(ids) -> ids
      _other -> []
    end
    |> Enum.map(&Map.get(cards_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp catalog_card(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> card
      {:error, _reason} -> %{}
    end
  end

  defp rules_summary(_card_id, %{id: nil}) do
    rules_summary(
      :unknown,
      "Catalog missing",
      "This card could not be resolved in the committed catalog."
    )
  end

  defp rules_summary(card_id, %{supertype: :trainer} = card) do
    case EngineCardRegistry.fetch(card_id) do
      {:ok, %{play_window: :action_window}} ->
        rules_summary(
          :engine_defined,
          "Engine-defined",
          "This Trainer has authored engine behavior and appears as a Play action when costs and timing are legal."
        )

      {:ok, _definition} ->
        rules_summary(
          :partial,
          "Timing pending",
          "This Trainer has authored behavior, but its play window is not exposed in the current action surface."
        )

      {:error, _reason} ->
        generic_trainer_rules_summary(card)
    end
  end

  defp rules_summary(_card_id, %{supertype: :energy, energy_type: :basic}) do
    rules_summary(
      :generic,
      "Generic Energy",
      "Basic Energy can attach through the generic engine action."
    )
  end

  defp rules_summary(_card_id, %{supertype: :energy, energy_type: :special} = card) do
    if supported_special_energy?(card) do
      rules_summary(
        :engine_defined,
        "Engine-defined Energy",
        "This Special Energy provides its supported Energy type and enforces its authored engine text."
      )
    else
      rules_summary(
        :partial,
        "Special text pending",
        "This Energy can attach through the generic engine action; special card text is not executable yet."
      )
    end
  end

  defp rules_summary(_card_id, %{supertype: :energy}) do
    rules_summary(
      :partial,
      "Special text pending",
      "This Energy can attach through the generic engine action; special card text is not executable yet."
    )
  end

  defp rules_summary(card_id, %{supertype: :pokemon} = card) do
    %{executable: executable_attack_count, unsupported: unsupported_attack_count} =
      attack_support_counts(card_id, card)

    unsupported_ability_count = unsupported_ability_count(card)

    cond do
      unsupported_attack_count == 0 and unsupported_ability_count == 0 and
          executable_attack_count > 0 ->
        rules_summary(
          :engine_defined,
          "Executable attacks",
          "This Pokémon has executable attacks for the current engine slice.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      executable_attack_count > 0 ->
        rules_summary(
          :partial,
          "Partial attacks",
          "Some attacks are executable; unsupported attacks or abilities are omitted from legal actions.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      unsupported_attack_count > 0 or unsupported_ability_count > 0 ->
        rules_summary(
          :unsupported,
          "Card text pending",
          "Generic board actions can still use this Pokémon, but attacks or abilities are not executable yet.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      true ->
        rules_summary(
          :generic,
          "Generic Pokémon",
          "Setup, Bench, evolution, retreat, attachments, and other generic board actions can use this Pokémon."
        )
    end
  end

  defp rules_summary(_card_id, _card) do
    rules_summary(
      :unknown,
      "Catalog only",
      "This card is known to the catalog, but the engine has no executable card-specific behavior for it yet."
    )
  end

  defp rules_summary(status, label, note) do
    rules_summary(status, label, note, 0, 0, 0)
  end

  defp rules_summary(
         status,
         label,
         note,
         executable_attack_count,
         unsupported_attack_count,
         unsupported_ability_count
       ) do
    %{
      status: Atom.to_string(status),
      label: label,
      note: note,
      executable_attack_count: executable_attack_count,
      unsupported_attack_count: unsupported_attack_count,
      unsupported_ability_count: unsupported_ability_count
    }
  end

  defp unsupported_trainer_label(%{trainer_type: trainer_type})
       when trainer_type not in [nil, :unknown] do
    "Unsupported #{trainer_type |> Atom.to_string() |> String.capitalize()}"
  end

  defp unsupported_trainer_label(_card), do: "Unsupported Trainer"

  defp generic_trainer_rules_summary(%{trainer_type: :stadium} = card) do
    if StadiumEffects.supported_stadium?(card) do
      rules_summary(
        :engine_defined,
        "Engine-defined Stadium",
        "This Stadium can be played generically and its authored Stadium text is enforced by the engine."
      )
    else
      rules_summary(
        :partial,
        "Generic Stadium",
        "This Stadium can be played through the generic engine action; printed Stadium text may still be pending."
      )
    end
  end

  defp generic_trainer_rules_summary(%{trainer_type: :tool} = card) do
    if ToolEffects.supported_tool?(card) do
      rules_summary(
        :engine_defined,
        "Engine-defined Tool",
        "This Tool attaches generically and its authored Tool text is enforced by the engine."
      )
    else
      rules_summary(
        :partial,
        "Generic Tool",
        "This Tool can attach through the generic engine action; printed Tool text may still be pending."
      )
    end
  end

  defp generic_trainer_rules_summary(card) do
    rules_summary(
      :unsupported,
      unsupported_trainer_label(card),
      "Known catalog card; Trainer text has no executable engine behavior yet, so no Play button appears."
    )
  end

  defp unsupported_action_summaries(card_id, %{supertype: :pokemon} = card) do
    unsupported_attack_summaries(card_id, card) ++ unsupported_ability_summaries(card)
  end

  defp unsupported_action_summaries(card_id, %{supertype: :trainer} = card) do
    if supported_trainer_text?(card) do
      []
    else
      case EngineCardRegistry.fetch(card_id) do
        {:ok, %{play_window: :action_window}} ->
          []

        {:ok, _definition} ->
          unsupported_trainer_summaries(
            card,
            "This Trainer has authored behavior, but that timing window is not exposed in the current action surface."
          )

        {:error, _reason} ->
          unsupported_trainer_summaries(
            card,
            unsupported_trainer_summary_reason(card)
          )
      end
    end
  end

  defp unsupported_action_summaries(_card_id, %{supertype: :energy, energy_type: :basic}), do: []

  defp unsupported_action_summaries(_card_id, %{supertype: :energy} = card) do
    unsupported_energy_summaries(card)
  end

  defp unsupported_action_summaries(_card_id, _card), do: []

  defp supported_trainer_text?(%{trainer_type: :stadium} = card),
    do: StadiumEffects.supported_stadium?(card)

  defp supported_trainer_text?(%{trainer_type: :tool} = card),
    do: ToolEffects.supported_tool?(card)

  defp supported_trainer_text?(_card), do: false

  defp unsupported_attack_summaries(card_id, %{attacks: attacks}) when is_map(attacks) do
    attacks
    |> Enum.sort_by(fn {attack_id, _attack} -> Atom.to_string(attack_id) end)
    |> Enum.flat_map(fn {attack_id, attack} ->
      case CardCatalog.fetch_attack(card_id, attack_id) do
        {:ok, _attack} -> []
        {:error, reason} -> [unsupported_attack_summary(attack_id, attack, reason)]
      end
    end)
  end

  defp unsupported_attack_summaries(_card_id, _card), do: []

  defp unsupported_attack_summary(attack_id, attack, reason) do
    %{
      kind: "attack",
      id: Atom.to_string(attack_id),
      name: Map.get(attack, :name) || format_action_id(attack_id),
      reason: unsupported_attack_reason(reason),
      text: blank_to_nil(Map.get(attack, :raw_effect)),
      cost: AttackCosts.stringify_cost(AttackCosts.attack_cost(attack)),
      damage: attack_damage(attack)
    }
  end

  defp unsupported_attack_reason({:unsupported_attack_effect, _card_id, _attack_id, effect_type}) do
    "Attack effect #{effect_type |> stringify() |> format_action_id()} is not executable in this engine slice yet."
  end

  defp unsupported_attack_reason(_reason) do
    "Attack text has no executable engine behavior yet, so no Declare command appears."
  end

  defp unsupported_ability_summaries(%{abilities: abilities}) when is_map(abilities) do
    abilities
    |> Enum.sort_by(fn {ability_id, _ability} -> Atom.to_string(ability_id) end)
    |> Enum.flat_map(fn {ability_id, ability} ->
      if present_text?(Map.get(ability, :raw_effect)) and is_nil(Map.get(ability, :effect)) do
        [
          %{
            kind: "ability",
            id: Atom.to_string(ability_id),
            name: Map.get(ability, :name) || format_action_id(ability_id),
            reason: "Ability text has no executable engine behavior yet.",
            text: blank_to_nil(Map.get(ability, :raw_effect)),
            cost: [],
            damage: nil
          }
        ]
      else
        []
      end
    end)
  end

  defp unsupported_ability_summaries(_card), do: []

  defp unsupported_trainer_summaries(card, reason) do
    if present_text?(Map.get(card, :raw_effect)) do
      [
        %{
          kind: "trainer",
          id: nil,
          name: Map.get(card, :name) || "Trainer",
          reason: reason,
          text: blank_to_nil(Map.get(card, :raw_effect)),
          cost: [],
          damage: nil
        }
      ]
    else
      []
    end
  end

  defp unsupported_trainer_summary_reason(%{trainer_type: :stadium}) do
    "This Stadium can be played generically, but its printed Stadium text is not executable yet."
  end

  defp unsupported_trainer_summary_reason(%{trainer_type: :tool}) do
    "This Tool can attach generically, but its printed Tool text is not executable yet."
  end

  defp unsupported_trainer_summary_reason(_card) do
    "Trainer text has no executable engine behavior yet, so no Play command appears."
  end

  defp attack_damage(%{damage: damage}) when is_integer(damage), do: Integer.to_string(damage)
  defp attack_damage(%{damage: damage}) when is_binary(damage), do: damage
  defp attack_damage(_attack), do: nil

  defp unsupported_energy_summaries(card) do
    if present_text?(Map.get(card, :raw_effect)) and not supported_special_energy?(card) do
      [
        %{
          kind: "energy",
          id: nil,
          name: Map.get(card, :name) || "Special Energy",
          reason: unsupported_energy_reason(card),
          text: blank_to_nil(Map.get(card, :raw_effect)),
          cost: [],
          damage: nil
        }
      ]
    else
      []
    end
  end

  defp unsupported_energy_reason(%{name: "Team Rocket's Energy"}) do
    "This Special Energy has narrow attack-cost provider support, but attachment restrictions and remaining printed text are not executable yet."
  end

  defp unsupported_energy_reason(%{provides: provides})
       when is_list(provides) and provides != [] do
    "This Special Energy can provide its printed Energy for attack costs, but remaining printed effects are not executable yet."
  end

  defp unsupported_energy_reason(_card) do
    "This Special Energy can attach through the generic engine action, but its printed Energy rule or effects are not executable yet."
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :provides_every_type_when_attached_to_stage_2,
           provider_count: provider_count
         },
         provides: provides
       })
       when is_integer(provider_count) and provider_count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :provides_every_type_when_attached_to_basic},
         provides: provides
       })
       when is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
           max_targets: max_targets
         },
         provides: provides
       })
       when is_integer(max_targets) and max_targets > 0 and is_list(provides) do
    :psychic in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :draw_cards_on_attach_from_hand, count: count},
         provides: provides
       })
       when is_integer(count) and count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :place_damage_counters_on_attacker_if_damaged_as_active_by_attack,
           count: count
         },
         provides: provides
       })
       when is_integer(count) and count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :prevent_opponent_attack_effects_to_attached_pokemon,
           required_attached_pokemon_type: :fighting
         },
         provides: provides
       })
       when is_list(provides) do
    :fighting in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon},
         provides: provides
       })
       when is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :team_rocket_energy_attachment_and_dual_provides},
         name: "Team Rocket's Energy"
       }),
       do: true

  defp supported_special_energy?(_card), do: false

  defp format_action_id(value) when is_atom(value),
    do: value |> Atom.to_string() |> format_action_id()

  defp format_action_id(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_action_id(value), do: value |> to_string() |> format_action_id()

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)

    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil

  defp attack_support_counts(card_id, %{attacks: attacks}) when is_map(attacks) do
    Enum.reduce(attacks, %{executable: 0, unsupported: 0}, fn {attack_id, _attack}, counts ->
      case CardCatalog.fetch_attack(card_id, attack_id) do
        {:ok, _attack} -> Map.update!(counts, :executable, &(&1 + 1))
        {:error, _reason} -> Map.update!(counts, :unsupported, &(&1 + 1))
      end
    end)
  end

  defp attack_support_counts(_card_id, _card), do: %{executable: 0, unsupported: 0}

  defp unsupported_ability_count(%{abilities: abilities}) when is_map(abilities) do
    Enum.count(abilities, fn {_ability_id, ability} ->
      present_text?(Map.get(ability, :raw_effect)) and is_nil(Map.get(ability, :effect))
    end)
  end

  defp unsupported_ability_count(_card), do: 0

  defp present_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp present_text?(_text), do: false

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value
end

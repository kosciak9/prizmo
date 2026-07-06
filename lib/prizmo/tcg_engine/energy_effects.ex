defmodule Prizmo.TcgEngine.EnergyEffects do
  @moduledoc false

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.HpEffects
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.SpecialConditions
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  @telepathic_psychic_choice_key :bench_basic_psychic_from_deck_when_attached_to_psychic
  @bubbly_water_energy_effect :water_pokemon_special_condition_immunity_energy
  @special_conditions [:asleep, :burned, :confused, :paralyzed, :poisoned]
  @prism_energy_basic_types [
    :grass,
    :fire,
    :water,
    :lightning,
    :psychic,
    :fighting,
    :darkness,
    :metal
  ]

  @type effect_event :: %{type: atom(), payload: map()}

  @spec provided_types(CardInstance.t(), CardInstance.t() | nil) :: [atom()]
  def provided_types(%CardInstance{} = energy_card, attached_target_card \\ nil) do
    case CardCatalog.fetch(energy_card.card_id) do
      {:ok,
       %{
         supertype: :energy,
         effect: %{type: :provides_every_type_when_attached_to_basic},
         provides: provides
       }} ->
        if attached_to_basic_pokemon?(energy_card, attached_target_card) do
          @prism_energy_basic_types
        else
          normalize_provides(provides)
        end

      {:ok, %{supertype: :energy, name: "Team Rocket's Energy"}} ->
        [:psychic, :darkness]

      {:ok, %{supertype: :energy, provides: provides}} when is_list(provides) ->
        provides

      {:ok, %{supertype: :energy}} ->
        []

      {:ok, _other} ->
        []

      {:error, _reason} ->
        []
    end
  end

  @spec provides_type?(CardInstance.t(), atom(), CardInstance.t() | nil) :: boolean()
  def provides_type?(%CardInstance{} = energy_card, type, attached_target_card \\ nil)
      when is_atom(type) do
    type in provided_types(energy_card, attached_target_card)
  end

  @spec after_attach_from_hand(
          Game.t(),
          Turn.t(),
          GamePlayer.t(),
          CardInstance.t(),
          CardInstance.t()
        ) ::
          {:ok, effect_event() | nil} | {:error, term()}
  def after_attach_from_hand(
        %Game{} = game,
        %Turn{} = turn,
        %GamePlayer{} = player,
        %CardInstance{} = energy_card,
        %CardInstance{} = target_card
      ) do
    with {:ok, catalog_card} <- CardCatalog.fetch(energy_card.card_id) do
      case Map.get(catalog_card, :effect) do
        nil ->
          {:ok, nil}

        %{type: :prevent_opponent_attack_effects_to_attached_pokemon} ->
          {:ok, nil}

        %{type: :team_rocket_energy_attachment_and_dual_provides} ->
          require_team_rocket_energy_target(energy_card, target_card)

        %{type: :grass_pokemon_hp_plus_20_energy} ->
          {:ok, nil}

        %{type: :place_damage_counters_on_attacker_if_damaged_as_active_by_attack} ->
          {:ok, nil}

        %{type: @bubbly_water_energy_effect} ->
          recover_special_condition(game.id, energy_card, target_card)

        %{type: :bench_basic_psychic_from_deck_when_attached_to_psychic, max_targets: max_targets}
        when is_integer(max_targets) and max_targets > 0 ->
          bench_basic_psychic_from_deck_when_attached_to_psychic(
            game,
            turn,
            player,
            energy_card,
            target_card,
            max_targets
          )

        %{type: :draw_cards_on_attach_from_hand, count: count}
        when is_integer(count) and count > 0 ->
          draw_cards_on_attach(game, player, energy_card, target_card, count)

        %{type: effect_type} ->
          {:error, {:unsupported_energy_effect, energy_card.card_id, effect_type}}

        effect ->
          {:error, {:invalid_energy_effect, energy_card.card_id, effect}}
      end
    end
  end

  @spec recover_special_condition(String.t(), CardInstance.t(), CardInstance.t()) ::
          {:ok, effect_event() | nil} | {:error, term()}
  def recover_special_condition(
        game_id,
        %CardInstance{} = energy_card,
        %CardInstance{} = target_card
      )
      when is_binary(game_id) do
    with {:ok, energy_metadata} <- CardCatalog.fetch(energy_card.card_id) do
      if special_condition_immunity_energy?(energy_metadata) do
        recover_card_special_condition(game_id, energy_card, target_card)
      else
        {:ok, nil}
      end
    end
  end

  @spec status_condition_prevention_payload(String.t(), CardInstance.t(), atom() | nil) ::
          {:prevented, map()} | :not_prevented
  def status_condition_prevention_payload(game_id, %CardInstance{} = card, status)
      when is_binary(game_id) do
    with true <- special_condition?(status),
         true <- in_play_pokemon?(card),
         {:ok, %CardInstance{} = source_energy} <-
           attached_special_condition_immunity_energy(game_id, card) do
      {:prevented, prevention_payload(source_energy, card, status)}
    else
      _other -> :not_prevented
    end
  end

  @doc """
  Applies Spiky Energy-style reactive Special Energy effects after attack damage.

  These effects inspect the defender's pre-damage attachment stack because the
  Energy still triggers when its attached Pokémon is Knocked Out by the attack.
  """
  def apply_reactive_damage_counter_energy_if_needed(
        game_id,
        attacking_player_id,
        %CardInstance{} = attacker_card,
        %CardInstance{} = defender_card,
        defender_attached_cards,
        damage_result
      )
      when is_binary(game_id) and is_binary(attacking_player_id) and
             is_list(defender_attached_cards) and
             is_map(damage_result) do
    cond do
      defender_card.owner_player_id == attacking_player_id ->
        {:ok, %{}}

      defender_card.zone != :active ->
        {:ok, %{}}

      Map.get(damage_result, :damage, 0) <= 0 ->
        {:ok, %{}}

      true ->
        with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id),
             sources =
               reactive_damage_counter_energy_sources(defender_attached_cards, defender_metadata),
             false <- Enum.empty?(sources),
             {:ok, current_attacker_card} <- CardStore.get_card(game_id, attacker_card.id),
             true <- in_play_pokemon?(current_attacker_card) do
          counter_count = total_reactive_damage_counter_count(sources)

          place_damage_counters_on_attacker(
            game_id,
            current_attacker_card,
            counter_count,
            sources
          )
        else
          true -> {:ok, %{}}
          false -> {:ok, %{}}
          {:error, _reason} = error -> error
        end
    end
  end

  @spec resume_pending_effect(
          Game.t(),
          Prompt.t(),
          PendingEffect.t(),
          String.t(),
          String.t(),
          [String.t()]
        ) :: {:ok, Game.t()} | {:error, term()}
  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :energy_effect, effect_key: @telepathic_psychic_choice_key} =
          pending_effect,
        player_id,
        "bench_basic_psychic_from_deck_when_attached_to_psychic",
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_prompt_choice_count(prompt, selected_card_instance_ids),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, selected_cards} <- CardStore.get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(selected_cards, player_id, :deck),
         :ok <- require_basic_psychic_pokemon_cards(selected_cards),
         {:ok, turn} <- TurnStore.current_turn(game.id),
         {:ok, moved_cards} <-
           CardStore.move_deck_cards_to_bench(
             game.id,
             player_id,
             selected_cards,
             turn.turn_number
           ),
         {:ok, _event} <-
           maybe_write_benched_cards_event(game.id, player_id, pending_effect, moved_cards),
         {:ok, player} <- CardStore.get_player(game.id, player_id),
         {:ok, shuffled_deck} <-
           shuffle_deck_after_attach_effect(game, turn, player, pending_effect),
         {:ok, _event} <-
           write_deck_shuffled_event(game, turn, player, pending_effect, shuffled_deck),
         {:ok, pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.put(
                 pending_effect.state || %{},
                 "selected_card_instance_ids",
                 Enum.map(moved_cards, & &1.id)
               )
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :energy_attach_effect_completed, player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             effect_key: Atom.to_string(@telepathic_psychic_choice_key),
             source: source_payload(pending_effect),
             target_card_instance_id:
               Map.get(pending_effect.state || %{}, "target_card_instance_id"),
             selected_card_instance_ids: Enum.map(moved_cards, & &1.id)
           }) do
      GameStore.get_game(game.id)
    end
  end

  def resume_pending_effect(
        %Game{},
        %Prompt{},
        %PendingEffect{} = pending_effect,
        _player_id,
        choice_key,
        _selected_card_instance_ids
      ) do
    {:error, {:unsupported_energy_attach_prompt, pending_effect.effect_key, choice_key}}
  end

  defp require_team_rocket_energy_target(
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card
       ) do
    with {:ok, target_catalog_card} <- CardCatalog.fetch(target_card.card_id) do
      if team_rocket_pokemon?(target_catalog_card) do
        {:ok, nil}
      else
        {:error,
         {:team_rocket_energy_requires_team_rocket_pokemon, energy_card.card_id,
          target_card.card_id}}
      end
    end
  end

  defp team_rocket_pokemon?(%{supertype: :pokemon, name: "Team Rocket's " <> _name}), do: true
  defp team_rocket_pokemon?(_card), do: false

  defp recover_card_special_condition(
         game_id,
         %CardInstance{} = source_energy,
         %CardInstance{} = target_card
       ) do
    with {:ok, current_target_card} <- CardStore.get_card(game_id, target_card.id) do
      if recoverable_special_condition?(game_id, current_target_card) do
        with {:ok, _card} <- update(current_target_card, :set_status, %{status: nil}),
             {:ok, _card} <-
               update(current_target_card, :set_markers, %{
                 markers: SpecialConditions.clear_condition_markers(current_target_card)
               }) do
          {:ok,
           %{
             type: :energy_special_conditions_recovered,
             payload: recovery_payload(source_energy, current_target_card)
           }}
        end
      else
        {:ok, nil}
      end
    end
  end

  defp recoverable_special_condition?(game_id, %CardInstance{} = card) do
    Enum.any?(SpecialConditions.conditions(card), &special_condition?/1) and
      in_play_pokemon?(card) and
      match?({:ok, %CardInstance{}}, attached_special_condition_immunity_energy(game_id, card))
  end

  defp attached_special_condition_immunity_energy(game_id, %CardInstance{} = card) do
    if pokemon_has_type?(card, :water) do
      with {:ok, attached_cards} <- CardStore.attached_cards(game_id, card.id) do
        {:ok, Enum.find(attached_cards, &special_condition_immunity_energy?/1)}
      end
    else
      {:ok, nil}
    end
  end

  defp special_condition_immunity_energy?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> special_condition_immunity_energy?(card)
      {:error, _reason} -> false
    end
  end

  defp special_condition_immunity_energy?(%{
         supertype: :energy,
         effect: %{type: @bubbly_water_energy_effect, required_attached_pokemon_type: :water},
         provides: provides
       })
       when is_list(provides) do
    :water in provides
  end

  defp special_condition_immunity_energy?(_card), do: false

  defp pokemon_has_type?(%CardInstance{card_id: card_id}, type) when is_atom(type) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, types: types}} when is_list(types) -> type in types
      {:ok, %{supertype: :pokemon, type: ^type}} -> true
      _other -> false
    end
  end

  defp recovery_payload(%CardInstance{} = source_energy, %CardInstance{} = card) do
    recovered_statuses = Enum.map(SpecialConditions.conditions(card), &Atom.to_string/1)

    %{
      source: EventPayloads.card_source(source_energy),
      effect_key: @bubbly_water_energy_effect,
      card_instance_id: card.id,
      card_id: card.card_id,
      owner_player_id: card.owner_player_id,
      recovered_status: List.first(recovered_statuses),
      recovered_statuses: recovered_statuses,
      energy_card_id: source_energy.card_id,
      energy_card_instance_id: source_energy.id,
      target_card_instance_id: card.id
    }
  end

  defp prevention_payload(%CardInstance{} = source_energy, %CardInstance{} = card, status) do
    %{
      protected_card_instance_id: card.id,
      prevented_status: Atom.to_string(status),
      status_prevention_source_card_id: source_energy.card_id,
      status_prevention_source_card_instance_id: source_energy.id,
      status_prevention_source_effect_id: @bubbly_water_energy_effect,
      status_prevention_source_player_id: source_energy.owner_player_id
    }
  end

  defp special_condition?(status), do: status in @special_conditions

  defp reactive_damage_counter_energy_sources(attached_cards, defender_metadata) do
    Enum.flat_map(attached_cards, fn
      %CardInstance{card_id: card_id} = attached_card ->
        case CardCatalog.fetch(card_id) do
          {:ok,
           %{
             supertype: :energy,
             energy_type: :special,
             effect:
               %{
                 type: :place_damage_counters_on_attacker_if_damaged_as_active_by_attack,
                 count: count
               } = effect
           }}
          when is_integer(count) and count > 0 ->
            if attached_pokemon_matches_required_type?(defender_metadata, effect) do
              [
                %{
                  card_id: attached_card.card_id,
                  card_instance_id: attached_card.id,
                  damage_counter_count: count
                }
              ]
            else
              []
            end

          _other ->
            []
        end

      _attached_card ->
        []
    end)
  end

  defp attached_pokemon_matches_required_type?(%{types: types}, %{
         required_attached_pokemon_type: required_type
       })
       when is_list(types) and is_atom(required_type) do
    required_type in types
  end

  defp attached_pokemon_matches_required_type?(_defender_metadata, _effect), do: true

  defp in_play_pokemon?(%CardInstance{zone: zone}) when zone in [:active, :bench], do: true
  defp in_play_pokemon?(_card), do: false

  defp total_reactive_damage_counter_count(sources) do
    Enum.reduce(sources, 0, &(&2 + &1.damage_counter_count))
  end

  defp place_damage_counters_on_attacker(_game_id, _attacker_card, counter_count, _sources)
       when counter_count <= 0 do
    {:ok, %{}}
  end

  defp place_damage_counters_on_attacker(
         game_id,
         %CardInstance{} = attacker_card,
         counter_count,
         sources
       ) do
    damage = counter_count * 10
    resulting_damage = attacker_card.damage + damage

    with {:ok, knocked_out?} <-
           HpEffects.damage_knocks_out?(game_id, attacker_card, resulting_damage),
         {:ok, attacker_card} <-
           update(attacker_card, :set_damage, %{damage: resulting_damage}),
         {:ok, knocked_out?} <-
           maybe_discard_reactive_damage_counter_knockout(game_id, attacker_card, knocked_out?) do
      {:ok,
       %{
         spiky_energy_attacker_card_instance_id: attacker_card.id,
         spiky_energy_damage: damage,
         spiky_energy_damage_counter_count: counter_count,
         spiky_energy_resulting_damage: resulting_damage,
         spiky_energy_source_card_ids: Enum.map(sources, & &1.card_id),
         spiky_energy_source_card_instance_ids: Enum.map(sources, & &1.card_instance_id),
         self_knocked_out?: knocked_out?
       }}
    end
  end

  defp maybe_discard_reactive_damage_counter_knockout(_game_id, _attacker_card, false) do
    {:ok, false}
  end

  defp maybe_discard_reactive_damage_counter_knockout(
         game_id,
         %CardInstance{} = attacker_card,
         true
       ) do
    with {:ok, _discarded_cards} <-
           discard_reactive_damage_counter_knockout_stack(game_id, attacker_card) do
      {:ok, true}
    end
  end

  defp discard_reactive_damage_counter_knockout_stack(game_id, %CardInstance{} = attacker_card) do
    with {:ok, stack_cards} <- CardStore.attached_cards(game_id, attacker_card.id) do
      [attacker_card | stack_cards]
      |> Enum.map(fn card ->
        with {:ok, position} <- CardStore.next_discard_position(game_id, card.owner_player_id) do
          update(card, :discard, %{
            position: position,
            damage: 0,
            status: nil,
            attached_to_card_instance_id: nil,
            evolves_from_card_instance_id: nil
          })
        end
      end)
      |> collect_results()
    end
  end

  defp attached_to_basic_pokemon?(
         %CardInstance{
           game_id: game_id,
           attached_to_card_instance_id: attached_to_card_instance_id
         },
         nil
       )
       when is_binary(game_id) and is_binary(attached_to_card_instance_id) do
    case CardStore.get_card(game_id, attached_to_card_instance_id) do
      {:ok, attached_target_card} -> basic_pokemon?(attached_target_card)
      _other -> false
    end
  end

  defp attached_to_basic_pokemon?(_energy_card, %CardInstance{} = attached_target_card) do
    basic_pokemon?(attached_target_card)
  end

  defp attached_to_basic_pokemon?(_energy_card, _attached_target_card), do: false

  defp basic_pokemon?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, stage: :basic}} -> true
      _other -> false
    end
  end

  defp normalize_provides(provides) when is_list(provides), do: provides
  defp normalize_provides(_provides), do: []

  defp bench_basic_psychic_from_deck_when_attached_to_psychic(
         %Game{} = game,
         %Turn{} = turn,
         %GamePlayer{} = player,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         max_targets
       ) do
    if psychic_pokemon?(target_card) do
      with {:ok, legal_choice_cards} <-
             telepathic_psychic_legal_choice_cards(game.id, player.player_id),
           {:ok, bench_space} <- bench_space(game.id, player.player_id) do
        max_choice_count = min(max_targets, min(length(legal_choice_cards), bench_space))

        case max_choice_count do
          0 ->
            with {:ok, shuffled_deck} <-
                   shuffle_deck_after_attach_effect(game, turn, player, energy_card) do
              {:ok,
               %{
                 type: :deck_shuffled,
                 payload:
                   deck_shuffled_payload(
                     game,
                     turn,
                     player,
                     energy_card,
                     target_card,
                     shuffled_deck,
                     legal_choice_count: length(legal_choice_cards)
                   )
               }}
            end

          _count ->
            create_telepathic_psychic_prompt(
              game,
              turn,
              player,
              energy_card,
              target_card,
              legal_choice_cards,
              max_choice_count
            )
        end
      end
    else
      {:ok, nil}
    end
  end

  defp create_telepathic_psychic_prompt(
         %Game{} = game,
         %Turn{} = turn,
         %GamePlayer{} = player,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         legal_choice_cards,
         max_choice_count
       ) do
    legal_choice_ids = Enum.map(legal_choice_cards, & &1.id)

    with {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game.id,
             source_type: :energy_effect,
             source_card_instance_id: energy_card.id,
             source_card_id: energy_card.card_id,
             controller_player_id: player.player_id,
             current_player_id: player.player_id,
             effect_key: @telepathic_psychic_choice_key,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "energy_effect",
               "effect_type" => Atom.to_string(@telepathic_psychic_choice_key),
               "player_id" => player.player_id,
               "source_card_instance_id" => energy_card.id,
               "source_card_id" => energy_card.card_id,
               "target_card_instance_id" => target_card.id
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: player.player_id,
             effect_key: @telepathic_psychic_choice_key,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game.id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: player.player_id,
             payload: %{
               "choice_key" => Atom.to_string(@telepathic_psychic_choice_key),
               "legal_choices" => legal_choice_ids,
               "legal_choice_labels" => telepathic_psychic_choice_labels(legal_choice_cards),
               "min" => 0,
               "max" => max_choice_count,
               "source_card_instance_id" => energy_card.id,
               "source_card_id" => energy_card.card_id,
               "target_card_instance_id" => target_card.id
             }
           }) do
      {:ok,
       %{
         type: :energy_attach_effect_prompt_created,
         payload: %{
           energy_card_id: energy_card.card_id,
           energy_card_instance_id: energy_card.id,
           target_card_instance_id: target_card.id,
           effect_type: Atom.to_string(@telepathic_psychic_choice_key),
           pending_effect_id: pending_effect.id,
           prompt_id: prompt.id,
           prompt_created?: true,
           search_legal_choice_count: length(legal_choice_ids),
           max_choice_count: max_choice_count
         }
       }}
    end
  end

  defp telepathic_psychic_legal_choice_cards(game_id, player_id) do
    with {:ok, deck_cards} <- CardStore.cards_in_zone(game_id, player_id, :deck) do
      {:ok, Enum.filter(deck_cards, &basic_psychic_pokemon?/1)}
    end
  end

  defp bench_space(game_id, player_id) do
    with {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      {:ok, max(5 - length(bench_cards), 0)}
    end
  end

  defp basic_psychic_pokemon?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, stage: :basic} = card} -> psychic_card?(card)
      _other -> false
    end
  end

  defp psychic_pokemon?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon} = card} -> psychic_card?(card)
      _other -> false
    end
  end

  defp psychic_card?(card) when is_map(card) do
    Map.get(card, :type) == :psychic or :psychic in List.wrap(Map.get(card, :types))
  end

  defp telepathic_psychic_choice_labels(cards) do
    Enum.map(cards, fn card ->
      %{
        "id" => card.id,
        "label" => card_name(card.card_id),
        "detail" => "Basic Psychic Pokémon from your deck to put onto your Bench."
      }
    end)
  end

  defp card_name(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{name: name}} when is_binary(name) and name != "" -> name
      _other -> card_id
    end
  end

  defp require_prompt_choice_count(%Prompt{payload: payload}, selected_card_instance_ids) do
    min = prompt_bound(payload, "min", 0)
    max = prompt_bound(payload, "max", min)
    count = length(selected_card_instance_ids)

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

  defp require_unique_ids(ids) do
    if length(Enum.uniq(ids)) == length(ids) do
      :ok
    else
      {:error, :duplicate_card_instance_ids}
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

  defp require_all_owned_in_zone(cards, player_id, zone) do
    if Enum.all?(cards, &(&1.owner_player_id == player_id and &1.zone == zone)) do
      :ok
    else
      {:error, {:invalid_energy_effect_targets, zone}}
    end
  end

  defp require_basic_psychic_pokemon_cards(cards) do
    if Enum.all?(cards, &basic_psychic_pokemon?/1) do
      :ok
    else
      {:error, :telepathic_psychic_energy_requires_basic_psychic_targets}
    end
  end

  defp maybe_write_benched_cards_event(_game_id, _player_id, _pending_effect, []), do: {:ok, nil}

  defp maybe_write_benched_cards_event(game_id, player_id, pending_effect, moved_cards) do
    write_event_and_snapshot(game_id, :cards_moved, player_id, %{
      reason: :effect_resolution,
      source: source_payload(pending_effect),
      effect_key: pending_effect.effect_key,
      affected_player_id: player_id,
      cards: EventPayloads.moved_cards(moved_cards, :deck, :bench)
    })
  end

  defp shuffle_deck_after_attach_effect(
         %Game{} = game,
         %Turn{} = turn,
         %GamePlayer{} = player,
         %CardInstance{} = energy_card
       ) do
    context =
      {:energy_attach_effect_search, player.player_id, turn.turn_number, energy_card.card_id}

    with {:ok, cards} <- CardStore.cards_in_zone(game.id, player.player_id, :deck) do
      cards
      |> shuffle_cards(game.rng_seed, context)
      |> Enum.with_index(1)
      |> Enum.map(fn {card, position} -> update(card, :reorder_deck, %{position: position}) end)
      |> collect_results()
    end
  end

  defp shuffle_deck_after_attach_effect(
         %Game{} = game,
         %Turn{} = turn,
         %GamePlayer{} = player,
         %PendingEffect{
           source_card_id: source_card_id
         }
       ) do
    context = {:energy_attach_effect_search, player.player_id, turn.turn_number, source_card_id}

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

  defp write_deck_shuffled_event(%Game{} = game, turn, player, pending_effect, shuffled_deck) do
    payload =
      maybe_put_rng_metadata(
        %{
          source: source_payload(pending_effect),
          effect_key: pending_effect.effect_key,
          affected_player_id: player.player_id,
          shuffle: "energy_attach_effect",
          card_count: length(shuffled_deck),
          target_card_instance_id: Map.get(pending_effect.state || %{}, "target_card_instance_id")
        },
        turn,
        player,
        pending_effect,
        game
      )

    write_event_and_snapshot(game.id, :deck_shuffled, player.player_id, payload)
  end

  defp deck_shuffled_payload(game, turn, player, energy_card, target_card, shuffled_deck, opts) do
    payload = %{
      source: EventPayloads.card_source(energy_card),
      effect_key: @telepathic_psychic_choice_key,
      affected_player_id: player.player_id,
      shuffle: "energy_attach_effect",
      card_count: length(shuffled_deck),
      target_card_instance_id: target_card.id,
      search_legal_choice_count: Keyword.get(opts, :legal_choice_count, 0)
    }

    maybe_put_rng_metadata(payload, turn, player, energy_card, game)
  end

  defp maybe_put_rng_metadata(
         payload,
         %Turn{} = turn,
         %GamePlayer{} = player,
         source,
         %Game{rng_seed: seed} = game
       )
       when is_binary(seed) do
    source_card_id = source_card_id(source)

    Map.merge(payload, %{
      rng_algorithm: game.rng_algorithm || Rng.algorithm(),
      rng_context:
        energy_attach_rng_context_label(player.player_id, turn.turn_number, source_card_id),
      rng_seed_source: game.rng_seed_source
    })
  end

  defp maybe_put_rng_metadata(payload, _turn, _player, _source, _game), do: payload

  defp energy_attach_rng_context_label(player_id, turn_number, source_card_id) do
    Enum.join(
      [
        "energy_attach_effect_search",
        player_id,
        Integer.to_string(turn_number),
        source_card_id
      ],
      ":"
    )
  end

  defp source_card_id(%CardInstance{card_id: card_id}), do: card_id
  defp source_card_id(%PendingEffect{source_card_id: card_id}), do: card_id

  defp source_payload(%PendingEffect{} = pending_effect) do
    %{
      type: :card,
      card_id: pending_effect.source_card_id,
      card_instance_id: pending_effect.source_card_instance_id
    }
  end

  defp draw_cards_on_attach(
         %Game{} = game,
         %GamePlayer{} = player,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         count
       ) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, count),
         :ok <- require_enough_deck_cards(cards, count),
         {:ok, starting_position} <-
           CardStore.next_hand_position_result(game.id, player.player_id),
         {:ok, drawn_cards} <- draw_cards_to_hand(cards, starting_position) do
      {:ok,
       %{
         type: :energy_attach_effect_drawn,
         payload: %{
           energy_card_id: energy_card.card_id,
           energy_card_instance_id: energy_card.id,
           target_card_instance_id: target_card.id,
           effect_type: "draw_cards_on_attach_from_hand",
           card_count: length(drawn_cards),
           cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand)
         }
       }}
    end
  end

  defp require_enough_deck_cards(cards, count) when length(cards) == count, do: :ok

  defp require_enough_deck_cards(cards, count),
    do: {:error, {:cannot_draw_energy_attach_effect_from_deck, count, length(cards)}}

  defp draw_cards_to_hand(cards, starting_position) do
    cards
    |> Enum.with_index(starting_position)
    |> Enum.map(fn {card, position} -> update(card, :draw_to_hand, %{position: position}) end)
    |> collect_results()
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

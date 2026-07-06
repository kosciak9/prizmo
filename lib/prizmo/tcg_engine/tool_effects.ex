defmodule Prizmo.TcgEngine.ToolEffects do
  @moduledoc false

  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardMetadataRequirements
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.HpEffects
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  @handheld_fan_card_id "TWM-150"
  @luxray_card_id "TWM-158"
  @powerglass_effect :attach_basic_energy_from_discard_to_attached_active_at_end_of_turn
  @powerglass_choice_key Atom.to_string(@powerglass_effect)
  @powerglass_prompted_turn_marker "powerglass_prompted_turn"

  @supported_tool_effect_types [
    :retreat_cost_reduction,
    :retreat_cost_reduction_with_low_hp_free_retreat,
    :bonus_attack_damage_to_pokemon_ex,
    :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
    :move_energy_from_attacker_to_defender_bench_on_damage,
    :bench_limit_8_with_tera_in_play_else_discard_to_5,
    :reduce_attack_cost_by_colorless_if_more_prizes_remaining,
    :draw_cards_if_damaged_as_active_by_attack,
    :reduce_opponents_knockout_prize_count_by_one,
    :attached_pokemon_hp_modifier,
    :place_damage_counters_on_attacker_if_damaged_as_active_by_attack,
    @powerglass_effect
  ]

  def supported_tool?(%{supertype: :trainer, trainer_type: :tool, effect: %{type: type}})
      when type in @supported_tool_effect_types, do: true

  def supported_tool?(_card), do: false

  def supported_tool_card?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> supported_tool?(card)
      {:error, _reason} -> false
    end
  end

  def end_turn_prompt_available?(game_id, player_id, %Turn{} = turn)
      when is_binary(game_id) and is_binary(player_id) do
    case eligible_powerglass_effect(game_id, player_id, turn) do
      {:ok, nil} -> false
      {:ok, _effect} -> true
      {:error, _reason} -> false
    end
  end

  def create_end_turn_prompt(%Game{} = game, %Turn{active_player_id: player_id} = turn) do
    case eligible_powerglass_effect(game.id, player_id, turn) do
      {:ok, nil} ->
        {:ok, game}

      {:ok, %{source_tool: source_tool, target_card: target_card, choices: choice_cards}} ->
        create_powerglass_prompt(game, turn, source_tool, target_card, choice_cards)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :tool_effect, effect_key: @powerglass_effect} = pending_effect,
        player_id,
        @powerglass_choice_key,
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_prompt_choice_count(prompt, selected_card_instance_ids),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids) do
      resolve_powerglass_choice(
        game,
        prompt,
        pending_effect,
        player_id,
        selected_card_instance_ids
      )
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
    {:error, {:unsupported_tool_effect_prompt, pending_effect.effect_key, choice_key}}
  end

  @doc """
  Returns additive attack damage from active Tool effects attached to the attacker.

  Tool damage text is applied before Weakness and Resistance by `AttackDamage`.
  """
  def attack_damage_bonus(
        game_id,
        %CardInstance{} = attacker_card,
        %CardInstance{} = defender_card
      )
      when is_binary(game_id) do
    cond do
      StadiumEffects.tools_have_no_effect?(game_id) ->
        {:ok, 0}

      defender_card.zone != :active ->
        {:ok, 0}

      true ->
        with {:ok, attacker_metadata} <- CardCatalog.fetch(attacker_card.card_id),
             {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id),
             true <- pokemon_ex?(defender_metadata),
             {:ok, attachments} <- CardStore.attached_cards(game_id, attacker_card.id) do
          bonus_damage =
            Enum.reduce(attachments, 0, fn attached_card, total ->
              total + attack_damage_bonus_from_tool(attached_card, attacker_metadata)
            end)

          {:ok, bonus_damage}
        else
          false -> {:ok, 0}
          {:error, _reason} = error -> error
        end
    end
  end

  @doc """
  Returns how many fewer Prize cards an attacking opponent should take when the
  target Pokémon is Knocked Out by damage from that opponent's attack.
  """
  def knockout_prize_reduction(game_id, %CardInstance{} = target_card) when is_binary(game_id) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         {:ok, target_catalog_card} <- CardCatalog.fetch(target_card.card_id),
         {:ok, attachments} <- CardStore.attached_cards(game_id, target_card.id) do
      case Enum.map(attachments, &knockout_prize_reduction_from_tool(&1, target_catalog_card)) do
        [] -> 0
        reductions -> Enum.max(reductions)
      end
    else
      true -> 0
      _other -> 0
    end
  end

  @doc """
  Applies Handheld Fan's effect after attack damage: moves one Energy from the
  attacking Pokémon to the defending player's bench if the defender had TWM-150
  attached and damage was dealt.
  """
  def apply_handheld_fan_if_needed(
        game_id,
        _attacking_player_id,
        attacker_card,
        defender_card,
        damage_result,
        opts
      ) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         true <- Map.get(damage_result, :damage, 0) > 0,
         true <- handheld_fan_attached?(game_id, defender_card),
         {:ok, energy_card} <- get_handheld_fan_energy_card(game_id, attacker_card, opts),
         {:ok, bench_target} <- get_handheld_fan_bench_target(game_id, defender_card, opts) do
      move_energy_to_bench(game_id, energy_card, bench_target)
    else
      true -> {:ok, nil}
      false -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Applies Luxray's effect after attack damage: draws 2 cards for the defender's
  player if the defender's Active had TWM-158 attached and damage was dealt.
  """
  def apply_luxray_draw_if_needed(
        game_id,
        _attacking_player_id,
        _attacker_card,
        defender_card,
        damage_result
      ) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         true <- Map.get(damage_result, :damage, 0) > 0,
         true <- luxray_attached?(game_id, defender_card),
         {:ok, player} <- CardStore.get_player(game_id, defender_card.owner_player_id),
         {:ok, _drawn} <- draw_cards_for_player(game_id, player, 2) do
      {:ok, %{type: :luxray_draw_triggered, count: 2, player_id: player.id}}
    else
      true -> {:ok, nil}
      false -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Applies Punk Helmet-style reactive Tool effects after attack damage.

  These effects must inspect the defender's pre-damage attachment stack because
  the Tool still triggers when its attached Pokémon is Knocked Out by the attack.
  """
  def apply_reactive_damage_counter_tools_if_needed(
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
      StadiumEffects.tools_have_no_effect?(game_id) ->
        {:ok, %{}}

      defender_card.owner_player_id == attacking_player_id ->
        {:ok, %{}}

      defender_card.zone != :active ->
        {:ok, %{}}

      Map.get(damage_result, :damage, 0) <= 0 ->
        {:ok, %{}}

      true ->
        with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id),
             sources = reactive_damage_counter_sources(defender_attached_cards, defender_metadata),
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

  defp luxray_attached?(game_id, %CardInstance{id: defender_id}) do
    case CardStore.attached_cards(game_id, defender_id) do
      {:ok, attachments} ->
        Enum.any?(attachments, &(&1.card_id == @luxray_card_id))

      _other ->
        false
    end
  end

  defp draw_cards_for_player(game_id, player, count) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, count) do
      cards
      |> Enum.map(&CardStore.move_deck_card_to_hand(game_id, player.player_id, &1))
      |> collect_results()
    end
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp reactive_damage_counter_sources(attached_cards, defender_metadata) do
    Enum.flat_map(attached_cards, fn
      %CardInstance{card_id: card_id} = attached_card ->
        case CardCatalog.fetch(card_id) do
          {:ok,
           %{
             supertype: :trainer,
             trainer_type: :tool,
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
           update_card(attacker_card, :set_damage, %{damage: resulting_damage}),
         {:ok, knocked_out?} <-
           maybe_discard_reactive_damage_counter_knockout(game_id, attacker_card, knocked_out?) do
      {:ok,
       %{
         punk_helmet_attacker_card_instance_id: attacker_card.id,
         punk_helmet_damage: damage,
         punk_helmet_damage_counter_count: counter_count,
         punk_helmet_resulting_damage: resulting_damage,
         punk_helmet_source_card_ids: Enum.map(sources, & &1.card_id),
         punk_helmet_source_card_instance_ids: Enum.map(sources, & &1.card_instance_id),
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
          update_card(card, :discard, %{
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

  defp update_card(%CardInstance{} = card, action, attrs) do
    Prizmo.TcgEngine.Operation.update(card, action, attrs)
  end

  defp eligible_powerglass_effect(game_id, player_id, %Turn{} = turn) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         {:ok, active_card} <- active_card(game_id, player_id),
         {:ok, attached_cards} <- CardStore.attached_cards(game_id, active_card.id),
         {:ok, discard_cards} <- CardStore.cards_in_zone(game_id, player_id, :discard) do
      source_tool = Enum.find(attached_cards, &eligible_powerglass_tool?(&1, turn))
      basic_energy_cards = Enum.filter(discard_cards, &basic_energy_card?/1)

      case {source_tool, basic_energy_cards} do
        {nil, _cards} ->
          {:ok, nil}

        {%CardInstance{}, []} ->
          {:ok, nil}

        {%CardInstance{} = tool, cards} ->
          {:ok, %{source_tool: tool, target_card: active_card, choices: cards}}
      end
    else
      true -> {:ok, nil}
      {:error, :active_card_not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_card(game_id, player_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active) do
      case active_cards do
        [%CardInstance{} = card | _cards] -> {:ok, card}
        [] -> {:error, :active_card_not_found}
      end
    end
  end

  defp eligible_powerglass_tool?(%CardInstance{} = attached_card, %Turn{} = turn) do
    powerglass_tool?(attached_card) and not powerglass_prompted_this_turn?(attached_card, turn)
  end

  defp powerglass_tool?(%CardInstance{card_id: card_id}) do
    match?(
      {:ok, %{supertype: :trainer, trainer_type: :tool, effect: %{type: @powerglass_effect}}},
      CardCatalog.fetch(card_id)
    )
  end

  defp powerglass_prompted_this_turn?(%CardInstance{markers: markers}, %Turn{
         turn_number: turn_number
       }) do
    Map.get(markers || %{}, @powerglass_prompted_turn_marker) == turn_number
  end

  defp put_powerglass_prompt_marker(%CardInstance{markers: markers}, %Turn{
         turn_number: turn_number
       }) do
    Map.put(markers || %{}, @powerglass_prompted_turn_marker, turn_number)
  end

  defp basic_energy_card?(%CardInstance{card_id: card_id}) do
    CardMetadataRequirements.require_basic_energy(card_id) == :ok
  end

  defp create_powerglass_prompt(
         %Game{} = game,
         %Turn{} = turn,
         %CardInstance{} = source_tool,
         %CardInstance{} = target_card,
         choice_cards
       ) do
    legal_choice_ids = Enum.map(choice_cards, & &1.id)

    with {:ok, _source_tool} <-
           update(source_tool, :set_markers, %{
             markers: put_powerglass_prompt_marker(source_tool, turn)
           }),
         {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game.id,
             source_type: :tool_effect,
             source_card_instance_id: source_tool.id,
             source_card_id: source_tool.card_id,
             controller_player_id: target_card.owner_player_id,
             current_player_id: target_card.owner_player_id,
             effect_key: @powerglass_effect,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "tool_effect",
               "effect_type" => @powerglass_choice_key,
               "player_id" => target_card.owner_player_id,
               "source_card_instance_id" => source_tool.id,
               "source_card_id" => source_tool.card_id,
               "target_card_instance_id" => target_card.id,
               "legal_choice_ids" => legal_choice_ids
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: target_card.owner_player_id,
             effect_key: @powerglass_effect,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game.id,
             turn_id: turn.id,
             pending_effect_id: pending_effect.id,
             prompt_type: "select_cards",
             player_id: target_card.owner_player_id,
             payload: %{
               "choice_key" => @powerglass_choice_key,
               "legal_choices" => legal_choice_ids,
               "legal_choice_labels" => basic_energy_choice_labels(choice_cards),
               "min" => 0,
               "max" => 1,
               "source_card_instance_id" => source_tool.id,
               "source_card_id" => source_tool.card_id,
               "target_card_instance_id" => target_card.id
             }
           }),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :prompt_created, target_card.owner_player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             choice_key: @powerglass_effect,
             prompt_type: :select_cards,
             source_card_instance_id: source_tool.id,
             source_card_id: source_tool.card_id,
             target_card_instance_id: target_card.id
           }) do
      GameStore.get_game(game.id)
    end
  end

  defp resolve_powerglass_choice(
         %Game{} = game,
         %Prompt{} = prompt,
         %PendingEffect{} = pending_effect,
         player_id,
         []
       ) do
    with {:ok, _pending_effect} <- complete_powerglass_pending_effect(pending_effect, []),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :tool_effect_completed, player_id, %{
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             effect_key: @powerglass_effect,
             source_card_instance_id: pending_effect.source_card_instance_id,
             source_card_id: pending_effect.source_card_id,
             target_card_instance_id:
               Map.get(pending_effect.state || %{}, "target_card_instance_id"),
             selected_card_instance_ids: [],
             skipped?: true
           }) do
      GameStore.get_game(game.id)
    end
  end

  defp resolve_powerglass_choice(
         %Game{} = game,
         %Prompt{} = _prompt,
         %PendingEffect{} = pending_effect,
         player_id,
         [
           energy_card_instance_id
         ]
       ) do
    with {:ok, source_tool} <- CardStore.get_card(game.id, pending_effect.source_card_instance_id),
         {:ok, target_card_instance_id} <- powerglass_target_card_instance_id(pending_effect),
         {:ok, target_card} <- CardStore.get_card(game.id, target_card_instance_id),
         {:ok, energy_card} <- CardStore.get_card(game.id, energy_card_instance_id),
         :ok <- require_powerglass_source_attached_to_target(source_tool, target_card),
         :ok <- require_active_owned_target(target_card, player_id),
         :ok <- require_basic_energy_in_discard(energy_card, player_id),
         {:ok, position} <- CardStore.next_attachment_position(game.id, target_card.id),
         {:ok, attached_energy} <-
           update(energy_card, :attach_from_discard, %{
             attached_to_card_instance_id: target_card.id,
             position: position
           }),
         {:ok, _pending_effect} <-
           complete_powerglass_pending_effect(pending_effect, [attached_energy.id]),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :tool_effect_resolution,
             source: EventPayloads.card_source(source_tool),
             effect_key: @powerglass_effect,
             affected_player_id: player_id,
             target_card_instance_id: target_card.id,
             cards: EventPayloads.moved_cards([attached_energy], :discard, :attached),
             public_note: "Powerglass attached a Basic Energy from the discard pile."
           }) do
      GameStore.get_game(game.id)
    end
  end

  defp complete_powerglass_pending_effect(
         %PendingEffect{} = pending_effect,
         selected_card_instance_ids
       ) do
    update(pending_effect, :complete, %{
      current_player_id: nil,
      state:
        Map.put(
          pending_effect.state || %{},
          "selected_card_instance_ids",
          selected_card_instance_ids
        )
    })
  end

  defp powerglass_target_card_instance_id(%PendingEffect{state: state}) do
    case Map.fetch(state || %{}, "target_card_instance_id") do
      {:ok, target_card_instance_id} -> {:ok, target_card_instance_id}
      :error -> {:error, :missing_powerglass_target_card_instance_id}
    end
  end

  defp require_powerglass_source_attached_to_target(
         %CardInstance{zone: :attached, attached_to_card_instance_id: target_id} = source_tool,
         %CardInstance{id: target_id}
       ) do
    if powerglass_tool?(source_tool), do: :ok, else: {:error, :not_powerglass_tool}
  end

  defp require_powerglass_source_attached_to_target(%CardInstance{}, %CardInstance{}),
    do: {:error, :powerglass_not_attached_to_target}

  defp require_active_owned_target(
         %CardInstance{zone: :active, owner_player_id: player_id},
         player_id
       ), do: :ok

  defp require_active_owned_target(
         %CardInstance{zone: zone, owner_player_id: owner_player_id},
         player_id
       ),
       do: {:error, {:invalid_powerglass_target, zone, owner_player_id, player_id}}

  defp require_basic_energy_in_discard(
         %CardInstance{zone: :discard, owner_player_id: player_id} = energy_card,
         player_id
       ) do
    CardMetadataRequirements.require_basic_energy(energy_card.card_id)
  end

  defp require_basic_energy_in_discard(
         %CardInstance{zone: zone, owner_player_id: owner_player_id},
         player_id
       ),
       do: {:error, {:invalid_powerglass_energy, zone, owner_player_id, player_id}}

  defp require_prompt_choice_count(%Prompt{payload: payload}, selected_card_instance_ids) do
    min = Map.get(payload, "min", 0)
    max = Map.get(payload, "max", 1)
    count = length(selected_card_instance_ids)

    if count >= min and count <= max do
      :ok
    else
      {:error, {:wrong_powerglass_choice_count, count, min, max}}
    end
  end

  defp require_unique_ids(card_instance_ids) do
    if length(Enum.uniq(card_instance_ids)) == length(card_instance_ids) do
      :ok
    else
      {:error, :duplicate_powerglass_card_instance_ids}
    end
  end

  defp require_prompt_legal_choices(%Prompt{payload: payload}, selected_card_instance_ids) do
    legal_choice_ids = Map.get(payload, "legal_choices", [])

    case Enum.reject(selected_card_instance_ids, &(&1 in legal_choice_ids)) do
      [] -> :ok
      illegal_ids -> {:error, {:illegal_powerglass_choice, illegal_ids}}
    end
  end

  defp basic_energy_choice_labels(choice_cards) do
    Enum.map(choice_cards, fn %CardInstance{card_id: card_id} ->
      case CardCatalog.fetch(card_id) do
        {:ok, %{name: name}} when is_binary(name) -> "#{name} (#{card_id})"
        _other -> card_id
      end
    end)
  end

  defp handheld_fan_attached?(game_id, %CardInstance{id: defender_id}) do
    case CardStore.attached_cards(game_id, defender_id) do
      {:ok, attachments} ->
        Enum.any?(attachments, &(&1.card_id == @handheld_fan_card_id))

      _other ->
        false
    end
  end

  defp get_handheld_fan_energy_card(game_id, %CardInstance{id: attacker_id}, opts) do
    attachment_id = Map.get(opts, :handheld_fan_attachment_id)

    if is_nil(attachment_id) do
      {:error, :handheld_fan_requires_energy_attachment_id}
    else
      case CardStore.get_card(game_id, attachment_id) do
        {:ok, %CardInstance{zone: :attached, attached_to_card_instance_id: ^attacker_id} = card} ->
          {:ok, card}

        {:ok, _card} ->
          {:error, :handheld_fan_attachment_not_found_on_attacker}

        {:error, _reason} ->
          {:error, :handheld_fan_attachment_not_found}
      end
    end
  end

  defp get_handheld_fan_bench_target(
         game_id,
         %CardInstance{owner_player_id: defender_player_id},
         opts
       ) do
    target_id = Map.get(opts, :handheld_fan_target_id)

    if is_nil(target_id) do
      {:error, :handheld_fan_requires_bench_target_id}
    else
      case CardStore.get_card(game_id, target_id) do
        {:ok, %CardInstance{owner_player_id: ^defender_player_id, zone: :bench} = card} ->
          {:ok, card}

        {:ok, _card} ->
          {:error, :handheld_fan_invalid_bench_target}

        {:error, _reason} ->
          {:error, :handheld_fan_bench_target_not_found}
      end
    end
  end

  defp move_energy_to_bench(game_id, energy_card, bench_target) do
    with {:ok, position} <- CardStore.next_attachment_position(game_id, bench_target.id),
         changeset =
           Ash.Changeset.for_update(energy_card, :reparent_attachment, %{
             attached_to_card_instance_id: bench_target.id,
             position: position
           }),
         {:ok, _moved_energy} <- Ash.update(changeset) do
      {:ok,
       %{
         type: :handheld_fan_energy_moved,
         energy_card_instance_id: energy_card.id,
         from_card_instance_id: energy_card.attached_to_card_instance_id,
         to_card_instance_id: bench_target.id
       }}
    end
  end

  defp knockout_prize_reduction_from_tool(%CardInstance{card_id: card_id}, %{name: target_name})
       when is_binary(target_name) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :reduce_opponents_knockout_prize_count_by_one, amount: amount} = effect
       }}
      when is_integer(amount) and amount > 0 ->
        if attached_pokemon_matches_prize_reduction?(target_name, effect), do: amount, else: 0

      _other ->
        0
    end
  end

  defp knockout_prize_reduction_from_tool(%CardInstance{}, _target_card), do: 0

  defp attack_damage_bonus_from_tool(%CardInstance{card_id: card_id}, attacker_metadata)
       when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :bonus_attack_damage_to_pokemon_ex, bonus_damage: bonus_damage}
       }}
      when is_integer(bonus_damage) and bonus_damage > 0 ->
        bonus_damage

      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{
           type: :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
           bonus_damage: bonus_damage
         }
       }}
      when is_integer(bonus_damage) and bonus_damage > 0 ->
        if Map.get(attacker_metadata, :rule_box?, false), do: 0, else: bonus_damage

      _other ->
        0
    end
  end

  defp pokemon_ex?(%{supertype: :pokemon, suffix: "ex"}), do: true

  defp pokemon_ex?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex")
  end

  defp pokemon_ex?(_metadata), do: false

  defp attached_pokemon_matches_prize_reduction?(target_name, %{
         required_attached_pokemon_name_prefix: prefix
       })
       when is_binary(target_name) and is_binary(prefix) do
    String.starts_with?(target_name, prefix)
  end

  defp attached_pokemon_matches_prize_reduction?(_target_name, %{
         required_attached_pokemon_name_prefix: _prefix
       }),
       do: false

  defp attached_pokemon_matches_prize_reduction?(_target_name, _effect), do: true

  def retreat_cost_reductions(%CardInstance{} = attached_to_card, attached_cards)
      when is_list(attached_cards) do
    Enum.flat_map(attached_cards, fn
      %CardInstance{} = card ->
        case retreat_cost_reduction(attached_to_card, card) do
          amount when amount > 0 ->
            [
              %{
                amount: amount,
                card_id: card.card_id,
                card_instance_id: card.id
              }
            ]

          _amount ->
            []
        end

      _card ->
        []
    end)
  end

  def retreat_cost_reductions(game_id, %CardInstance{} = attached_to_card, attached_cards)
      when is_binary(game_id) and is_list(attached_cards) do
    if StadiumEffects.tools_have_no_effect?(game_id) do
      []
    else
      Enum.flat_map(attached_cards, fn
        %CardInstance{} = card ->
          case retreat_cost_reduction(game_id, attached_to_card, card) do
            amount when amount > 0 ->
              [
                %{
                  amount: amount,
                  card_id: card.card_id,
                  card_instance_id: card.id
                }
              ]

            _amount ->
              []
          end

        _card ->
          []
      end)
    end
  end

  def retreat_cost_reduction(game_id, %CardInstance{} = attached_to_card, %CardInstance{
        card_id: card_id
      })
      when is_binary(game_id) and is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :retreat_cost_reduction, energy_type: :colorless, amount: amount}
       }}
      when is_integer(amount) and amount > 0 ->
        amount

      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{
           type: :retreat_cost_reduction_with_low_hp_free_retreat,
           amount: amount,
           remaining_hp_max: remaining_hp_max
         }
       }}
      when is_integer(amount) and amount > 0 and is_integer(remaining_hp_max) and
             remaining_hp_max >= 0 ->
        if remaining_hp_at_most?(game_id, attached_to_card, remaining_hp_max) do
          printed_retreat_cost(attached_to_card)
        else
          amount
        end

      {:ok, _card} ->
        0

      {:error, _reason} ->
        0
    end
  end

  def retreat_cost_reduction(%CardInstance{} = attached_to_card, %CardInstance{card_id: card_id})
      when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :retreat_cost_reduction, energy_type: :colorless, amount: amount}
       }}
      when is_integer(amount) and amount > 0 ->
        amount

      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{
           type: :retreat_cost_reduction_with_low_hp_free_retreat,
           amount: amount,
           remaining_hp_max: remaining_hp_max
         }
       }}
      when is_integer(amount) and amount > 0 and is_integer(remaining_hp_max) and
             remaining_hp_max >= 0 ->
        if remaining_hp_at_most?(attached_to_card, remaining_hp_max) do
          printed_retreat_cost(attached_to_card)
        else
          amount
        end

      {:ok, _card} ->
        0

      {:error, _reason} ->
        0
    end
  end

  defp remaining_hp_at_most?(%CardInstance{card_id: card_id, damage: damage}, max_remaining_hp)
       when is_integer(max_remaining_hp) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, hp: hp}} when is_integer(hp) ->
        max(hp - (damage || 0), 0) <= max_remaining_hp

      _other ->
        false
    end
  end

  defp remaining_hp_at_most?(game_id, %CardInstance{} = card, max_remaining_hp)
       when is_binary(game_id) and is_integer(max_remaining_hp) do
    case HpEffects.remaining_hp(game_id, card) do
      {:ok, remaining_hp} -> remaining_hp <= max_remaining_hp
      _other -> false
    end
  end

  defp printed_retreat_cost(%CardInstance{card_id: card_id}) do
    case CardMetadataRequirements.retreat_cost(card_id) do
      {:ok, retreat_cost} when is_integer(retreat_cost) and retreat_cost > 0 -> retreat_cost
      _other -> 0
    end
  end
end

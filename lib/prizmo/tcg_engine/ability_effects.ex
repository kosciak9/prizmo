defmodule Prizmo.TcgEngine.AbilityEffects do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [pokemon_hp: 1]
  import Prizmo.TcgEngine.EventLog, only: [write_event_and_snapshot: 4]
  import Prizmo.TcgEngine.Operation, only: [update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [require_all_owned_in_zone: 3, require_unique_ids: 1]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @adrena_brain_card_id "TWM-095"
  @adrena_brain_ability_id :adrena_brain
  @adrena_brain_effect_type :move_damage_counters
  @adrena_brain_marker_key "ability_used:adrena_brain"
  @adrena_brain_marker_atom_key :"ability_used:adrena_brain"
  @adrena_brain_max_counters 3
  @adrena_brain_required_type :darkness
  @teal_dance_card_id "TWM-025"
  @teal_dance_ability_id :teal_dance
  @teal_dance_effect_type :attach_basic_grass_energy_from_hand_to_self_then_draw
  @teal_dance_marker_key "ability_used:teal_dance"
  @teal_dance_marker_atom_key :"ability_used:teal_dance"
  @teal_dance_draw_count 1
  @teal_dance_required_type :grass
  @flip_the_script_card_id "ASC-142"
  @flip_the_script_ability_id :flip_the_script
  @flip_the_script_effect_type :draw_if_own_pokemon_knocked_out_last_turn
  @flip_the_script_marker_key "ability_used:flip_the_script"
  @flip_the_script_marker_atom_key :"ability_used:flip_the_script"
  @flip_the_script_draw_count 3
  @flip_the_script_unavailable_reason :flip_the_script_requires_own_pokemon_ko_during_opponents_last_turn
  @last_ditch_catch_card_id "POR-062"
  @last_ditch_catch_ability_id :last_ditch_catch
  @last_ditch_effect_type :search_supporter_when_benched_from_hand
  @last_ditch_marker_ability_id :last_ditch
  @jewel_seeker_card_id "SCR-115"
  @jewel_seeker_ability_id :jewel_seeker
  @jewel_seeker_effect_type :search_trainer_cards_when_evolved_with_tera_in_play
  @jewel_seeker_unavailable_reason :jewel_seeker_requires_tera_pokemon_in_play
  @seething_spirit_card_id "JTG-024"
  @seething_spirit_ability_id :seething_spirit
  @seething_spirit_effect_type :attach_basic_energy_from_discard_to_own_pokemon
  @psychic_draw_ability_id :psychic_draw
  @psychic_draw_effect_type :evolution_draw
  @recon_directive_ability_id :recon_directive
  @recon_directive_effect_type :top_two_choose_one_to_hand_other_to_bottom
  @run_away_draw_ability_id :run_away_draw
  @run_away_draw_effect_type :draw_then_shuffle_self_into_deck
  @cursed_blast_ability_id :cursed_blast
  @cursed_blast_effect_type :damage_counters_to_opponent_pokemon_then_self_knock_out
  @damp_card_id "ASC-039"
  @damp_ability_id :damp
  @fan_call_card_id "SCR-118"
  @fan_call_ability_id :fan_call

  def adrena_brain_card_id, do: @adrena_brain_card_id
  def adrena_brain_ability_id, do: @adrena_brain_ability_id
  def adrena_brain_max_counters, do: @adrena_brain_max_counters
  def teal_dance_card_id, do: @teal_dance_card_id
  def teal_dance_ability_id, do: @teal_dance_ability_id
  def teal_dance_draw_count, do: @teal_dance_draw_count
  def flip_the_script_card_id, do: @flip_the_script_card_id
  def flip_the_script_ability_id, do: @flip_the_script_ability_id
  def flip_the_script_draw_count, do: @flip_the_script_draw_count
  def last_ditch_catch_card_id, do: @last_ditch_catch_card_id
  def last_ditch_catch_ability_id, do: @last_ditch_catch_ability_id
  def jewel_seeker_card_id, do: @jewel_seeker_card_id
  def jewel_seeker_ability_id, do: @jewel_seeker_ability_id
  def seething_spirit_card_id, do: @seething_spirit_card_id
  def seething_spirit_ability_id, do: @seething_spirit_ability_id
  def psychic_draw_ability_id, do: @psychic_draw_ability_id
  def recon_directive_ability_id, do: @recon_directive_ability_id
  def run_away_draw_ability_id, do: @run_away_draw_ability_id
  def cursed_blast_ability_id, do: @cursed_blast_ability_id
  def damp_ability_id, do: @damp_ability_id
  def fan_call_card_id, do: @fan_call_card_id
  def fan_call_ability_id, do: @fan_call_ability_id

  def adrena_brain_source?(%CardInstance{card_id: @adrena_brain_card_id}), do: true
  def adrena_brain_source?(%CardInstance{}), do: false

  def teal_dance_source?(%CardInstance{card_id: @teal_dance_card_id}), do: true
  def teal_dance_source?(%CardInstance{}), do: false

  def flip_the_script_source?(%CardInstance{card_id: @flip_the_script_card_id}), do: true
  def flip_the_script_source?(%CardInstance{}), do: false

  def last_ditch_catch_source?(%CardInstance{card_id: @last_ditch_catch_card_id}), do: true
  def last_ditch_catch_source?(%CardInstance{}), do: false

  def jewel_seeker_source?(%CardInstance{card_id: @jewel_seeker_card_id}), do: true
  def jewel_seeker_source?(%CardInstance{}), do: false

  def seething_spirit_source?(%CardInstance{} = source) do
    match?({:ok, _effect}, seething_spirit_effect(source))
  end

  def psychic_draw_source?(%CardInstance{} = source) do
    match?({:ok, _effect}, psychic_draw_effect(source))
  end

  def recon_directive_source?(%CardInstance{} = source) do
    match?({:ok, _effect}, recon_directive_effect(source))
  end

  def run_away_draw_source?(%CardInstance{} = source) do
    match?({:ok, _effect}, run_away_draw_effect(source))
  end

  def cursed_blast_source?(%CardInstance{} = source) do
    match?({:ok, _effect}, cursed_blast_effect(source))
  end

  def damp_active?(game_id) when is_binary(game_id) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} -> Enum.any?(cards, &damp_active_card?/1)
      {:error, _reason} -> false
    end
  end

  def fan_call_source?(%CardInstance{card_id: @fan_call_card_id}), do: true
  def fan_call_source?(%CardInstance{}), do: false

  def require_self_knock_out_ability_not_blocked(game_id) when is_binary(game_id) do
    if damp_active?(game_id) do
      {:error, :self_knock_out_abilities_blocked_by_damp}
    else
      :ok
    end
  end

  def adrena_brain_available?(%CardInstance{} = source, attached_cards, %Turn{} = turn)
      when is_list(attached_cards) do
    adrena_brain_source?(source) and in_play?(source) and
      not adrena_brain_used_this_turn?(source, turn) and
      Enum.any?(attached_cards, &darkness_energy?/1)
  end

  def require_adrena_brain_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with :ok <- require_adrena_brain_source(source),
         :ok <- require_in_play(source),
         :ok <- require_adrena_brain_unused(source, turn),
         {:ok, attached_cards} <- CardStore.attached_cards(game_id, source.id) do
      require_attached_darkness_energy(source, attached_cards)
    end
  end

  def teal_dance_available?(%CardInstance{} = source, hand_cards, %Turn{} = turn)
      when is_list(hand_cards) do
    teal_dance_source?(source) and in_play?(source) and
      not teal_dance_used_this_turn?(source, turn) and
      Enum.any?(hand_cards, &basic_grass_energy?/1)
  end

  def require_teal_dance_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with :ok <- require_teal_dance_source(source),
         :ok <- require_in_play(source),
         :ok <- require_teal_dance_unused(source, turn),
         {:ok, hand_cards} <- CardStore.cards_in_zone(game_id, source.owner_player_id, :hand) do
      require_hand_basic_grass_energy(source, hand_cards)
    end
  end

  def flip_the_script_available?(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    require_flip_the_script_available(game_id, source, turn) == :ok
  end

  def require_flip_the_script_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with :ok <- require_flip_the_script_source(source),
         :ok <- require_in_play(source),
         :ok <- require_flip_the_script_unused(game_id, source.owner_player_id, turn) do
      require_own_pokemon_knocked_out_during_opponents_last_turn(
        game_id,
        turn,
        source.owner_player_id
      )
    end
  end

  def require_last_ditch_catch_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with {:ok, _effect} <- last_ditch_catch_effect(source),
         :ok <- require_in_play(source) do
      require_last_ditch_unused(game_id, source.owner_player_id, turn)
    end
  end

  def jewel_seeker_available?(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    require_jewel_seeker_available(game_id, source, turn) == :ok
  end

  def require_jewel_seeker_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with {:ok, _effect} <- jewel_seeker_effect(source),
         :ok <- require_in_play(source),
         :ok <- require_evolved_this_turn(source, turn),
         :ok <- require_own_tera_pokemon_in_play(game_id, source.owner_player_id) do
      require_ability_unused(source, turn, @jewel_seeker_ability_id)
    end
  end

  def jewel_seeker_legal_choice_cards(cards) when is_list(cards) do
    Enum.filter(cards, &jewel_seeker_target?/1)
  end

  def jewel_seeker_choice_labels(cards) when is_list(cards) do
    Enum.map(cards, fn card ->
      case CardCatalog.fetch(card.card_id) do
        {:ok, %{name: name}} -> name
        _ -> card.card_id
      end
    end)
  end

  def last_ditch_catch_legal_choice_cards(cards) when is_list(cards) do
    Enum.filter(cards, &last_ditch_catch_target?/1)
  end

  def last_ditch_catch_choice_labels(cards) when is_list(cards) do
    Enum.map(cards, fn card ->
      case CardCatalog.fetch(card.card_id) do
        {:ok, %{name: name}} -> name
        _ -> card.card_id
      end
    end)
  end

  def seething_spirit_available?(%CardInstance{} = source, discard_cards, %Turn{} = turn)
      when is_list(discard_cards) do
    seething_spirit_source?(source) and in_play?(source) and
      Enum.any?(discard_cards, &basic_energy?/1) and
      not ability_used_this_turn?(source, turn, @seething_spirit_ability_id)
  end

  def require_seething_spirit_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with {:ok, _effect} <- seething_spirit_effect(source),
         :ok <- require_in_play(source),
         {:ok, discard_cards} <-
           CardStore.cards_in_zone(game_id, source.owner_player_id, :discard),
         :ok <- require_discard_basic_energy(source, discard_cards) do
      require_ability_unused(source, turn, @seething_spirit_ability_id)
    end
  end

  def psychic_draw_available?(%CardInstance{} = source, %Turn{} = turn) do
    require_psychic_draw_available(source, turn) == :ok
  end

  def require_psychic_draw_available(%CardInstance{} = source, %Turn{} = turn) do
    with {:ok, _effect} <- psychic_draw_effect(source),
         :ok <- require_in_play(source),
         :ok <- require_evolved_this_turn(source, turn) do
      require_ability_unused(source, turn, @psychic_draw_ability_id)
    end
  end

  def recon_directive_available?(%CardInstance{} = source, deck_cards, %Turn{} = turn)
      when is_list(deck_cards) do
    recon_directive_source?(source) and in_play?(source) and deck_cards != [] and
      not ability_used_this_turn?(source, turn, @recon_directive_ability_id)
  end

  def require_recon_directive_available(%CardInstance{} = source, deck_cards, %Turn{} = turn)
      when is_list(deck_cards) do
    with {:ok, _effect} <- recon_directive_effect(source),
         :ok <- require_in_play(source),
         :ok <- require_non_empty_deck(source, deck_cards) do
      require_ability_unused(source, turn, @recon_directive_ability_id)
    end
  end

  def run_away_draw_available?(%CardInstance{} = source, %Turn{} = turn) do
    require_run_away_draw_available(source, turn) == :ok
  end

  def require_run_away_draw_available(%CardInstance{} = source, %Turn{} = turn) do
    with {:ok, _effect} <- run_away_draw_effect(source),
         :ok <- require_in_play(source) do
      require_ability_unused(source, turn, @run_away_draw_ability_id)
    end
  end

  def cursed_blast_available?(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    require_cursed_blast_available(game_id, source, turn) == :ok
  end

  def require_cursed_blast_available(game_id, %CardInstance{} = source, %Turn{} = turn)
      when is_binary(game_id) do
    with {:ok, _effect} <- cursed_blast_effect(source),
         :ok <- require_in_play(source),
         :ok <- require_self_knock_out_ability_not_blocked(game_id) do
      require_ability_unused(source, turn, @cursed_blast_ability_id)
    end
  end

  def fan_call_available?(%CardInstance{} = source, %Turn{} = turn) do
    require_fan_call_available(source, turn) == :ok
  end

  def require_fan_call_available(%CardInstance{} = source, %Turn{} = turn) do
    with {:ok, _effect} <- fan_call_effect(source),
         :ok <- require_in_play(source),
         :ok <- require_fan_call_first_turn(turn) do
      require_ability_unused(source, turn, @fan_call_ability_id)
    end
  end

  def psychic_draw_count(%CardInstance{} = source) do
    with {:ok, %{draw_count: draw_count}} <- psychic_draw_effect(source) do
      {:ok, draw_count}
    end
  end

  def run_away_draw_count(%CardInstance{} = source) do
    with {:ok, %{draw_count: draw_count}} <- run_away_draw_effect(source) do
      {:ok, draw_count}
    end
  end

  def jewel_seeker_max_targets(%CardInstance{} = source) do
    with {:ok, %{max_targets: max_targets}} <- jewel_seeker_effect(source) do
      {:ok, max_targets}
    end
  end

  def cursed_blast_counters(%CardInstance{} = source) do
    with {:ok, %{counters: counters}} <- cursed_blast_effect(source) do
      {:ok, counters}
    end
  end

  def require_adrena_brain_source(%CardInstance{card_id: @adrena_brain_card_id} = source) do
    with {:ok, %{max_counters: @adrena_brain_max_counters}} <- adrena_brain_effect(source) do
      :ok
    end
  end

  def require_adrena_brain_source(%CardInstance{} = source) do
    {:error, {:wrong_card_for_ability, @adrena_brain_card_id, source.card_id}}
  end

  def require_teal_dance_source(%CardInstance{card_id: @teal_dance_card_id} = source) do
    with {:ok, %{draw_count: @teal_dance_draw_count}} <- teal_dance_effect(source) do
      :ok
    end
  end

  def require_teal_dance_source(%CardInstance{} = source) do
    {:error, {:wrong_card_for_ability, @teal_dance_card_id, source.card_id}}
  end

  def require_flip_the_script_source(%CardInstance{card_id: @flip_the_script_card_id} = source) do
    with {:ok, %{draw_count: @flip_the_script_draw_count}} <- flip_the_script_effect(source) do
      :ok
    end
  end

  def require_flip_the_script_source(%CardInstance{} = source) do
    {:error, {:wrong_card_for_ability, @flip_the_script_card_id, source.card_id}}
  end

  def require_adrena_brain_unused(%CardInstance{} = source, %Turn{} = turn) do
    if adrena_brain_used_this_turn?(source, turn) do
      {:error, {:ability_already_used_this_turn, source.id, @adrena_brain_ability_id}}
    else
      :ok
    end
  end

  def require_teal_dance_unused(%CardInstance{} = source, %Turn{} = turn) do
    if teal_dance_used_this_turn?(source, turn) do
      {:error, {:ability_already_used_this_turn, source.id, @teal_dance_ability_id}}
    else
      :ok
    end
  end

  def require_flip_the_script_unused(game_id, player_id, %Turn{} = turn)
      when is_binary(game_id) and is_binary(player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      player_cards = Enum.filter(cards, &(&1.owner_player_id == player_id))

      if flip_the_script_used_this_turn?(player_cards, turn) do
        {:error, {:ability_already_used_this_turn, player_id, @flip_the_script_ability_id}}
      else
        :ok
      end
    end
  end

  def put_adrena_brain_used_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@adrena_brain_marker_key, %{
      "ability_id" => Atom.to_string(@adrena_brain_ability_id),
      "source_card_id" => @adrena_brain_card_id,
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number
    })
  end

  def put_teal_dance_used_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@teal_dance_marker_key, %{
      "ability_id" => Atom.to_string(@teal_dance_ability_id),
      "source_card_id" => @teal_dance_card_id,
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number
    })
  end

  def put_flip_the_script_used_marker(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> normalize_markers()
    |> Map.put(@flip_the_script_marker_key, %{
      "ability_id" => Atom.to_string(@flip_the_script_ability_id),
      "source_card_id" => @flip_the_script_card_id,
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number
    })
  end

  def put_last_ditch_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @last_ditch_marker_ability_id)
  end

  def put_jewel_seeker_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @jewel_seeker_ability_id)
  end

  def put_seething_spirit_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @seething_spirit_ability_id)
  end

  def put_psychic_draw_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @psychic_draw_ability_id)
  end

  def put_recon_directive_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @recon_directive_ability_id)
  end

  def put_run_away_draw_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @run_away_draw_ability_id)
  end

  def put_cursed_blast_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @cursed_blast_ability_id)
  end

  def put_fan_call_used_marker(%CardInstance{} = source, %Turn{} = turn) do
    put_ability_used_marker(source, turn, @fan_call_ability_id)
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :ability_effect, effect_key: @jewel_seeker_ability_id} =
          pending_effect,
        player_id,
        _choice_key,
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with {:ok, max_targets} <-
           jewel_seeker_max_targets_from_pending_effect(game.id, pending_effect),
         :ok <- require_max_target_count(selected_card_instance_ids, max_targets),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, target_cards} <- CardStore.get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_jewel_seeker_targets(target_cards),
         {:ok, moved_cards} <- move_deck_targets_to_hand(game.id, player_id, target_cards),
         moved_cards_payload = EventPayloads.moved_cards(moved_cards, :deck, :hand),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :ability_effect_resolution,
             source: pending_effect_source_payload(pending_effect),
             source_card_id: pending_effect.source_card_id,
             effect_key: pending_effect.effect_key,
             cards: moved_cards_payload,
             public_reveal: true,
             revealed_cards: moved_cards_payload
           }),
         {:ok, _shuffled_deck} <-
           shuffle_deck_after_ability_search(game, player_id, @jewel_seeker_ability_id),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :deck_shuffled, player_id, %{
             source: pending_effect_source_payload(pending_effect),
             effect_key: pending_effect.effect_key
           }),
         {:ok, _game} <- complete_pending_effect(pending_effect, selected_card_instance_ids) do
      GameStore.get_game(game.id)
    end
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :ability_effect, effect_key: @last_ditch_catch_ability_id} =
          pending_effect,
        player_id,
        _choice_key,
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_max_target_count(selected_card_instance_ids, 1),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, target_cards} <- CardStore.get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck) do
      case target_cards do
        [] ->
          complete_pending_effect(pending_effect, selected_card_instance_ids)

        [_supporter_card] = target_cards ->
          with :ok <- require_all_last_ditch_targets(target_cards),
               {:ok, turn} <- TurnStore.current_turn(game.id),
               {:ok, source_card} <-
                 CardStore.get_card(game.id, pending_effect.source_card_instance_id),
               {:ok, marked_source_card} <-
                 update(source_card, :set_markers, %{
                   markers: put_last_ditch_used_marker(source_card, turn)
                 }),
               {:ok, _event} <-
                 write_event_and_snapshot(game.id, :ability_used, player_id, %{
                   turn_id: turn.id,
                   source: EventPayloads.card_source(marked_source_card),
                   source_card_id: marked_source_card.card_id,
                   source_card_instance_id: marked_source_card.id,
                   ability_id: Atom.to_string(@last_ditch_catch_ability_id),
                   effect_type: @last_ditch_effect_type,
                   public_note: "Meowth ex used Last-Ditch Catch."
                 }),
               {:ok, moved_cards} <- move_deck_targets_to_hand(game.id, player_id, target_cards),
               moved_cards_payload = EventPayloads.moved_cards(moved_cards, :deck, :hand),
               {:ok, _event} <-
                 write_event_and_snapshot(game.id, :cards_moved, player_id, %{
                   reason: :ability_effect_resolution,
                   source: EventPayloads.card_source(marked_source_card),
                   source_card_id: marked_source_card.card_id,
                   effect_key: pending_effect.effect_key,
                   cards: moved_cards_payload,
                   public_reveal: true,
                   revealed_cards: moved_cards_payload
                 }),
               {:ok, _shuffled_deck} <-
                 shuffle_deck_after_ability_search(game, player_id, @last_ditch_catch_ability_id),
               {:ok, _event} <-
                 write_event_and_snapshot(game.id, :deck_shuffled, player_id, %{
                   source: pending_effect_source_payload(pending_effect),
                   effect_key: pending_effect.effect_key
                 }) do
            complete_pending_effect(pending_effect, selected_card_instance_ids)
          end
      end
    end
  end

  def resume_pending_effect(
        %Game{} = game,
        %Prompt{} = prompt,
        %PendingEffect{source_type: :ability_effect, effect_key: @fan_call_ability_id} =
          pending_effect,
        player_id,
        _choice_key,
        selected_card_instance_ids
      )
      when is_binary(player_id) and is_list(selected_card_instance_ids) do
    with :ok <- require_max_target_count(selected_card_instance_ids, 3),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, target_cards} <- CardStore.get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(target_cards, player_id, :deck),
         :ok <- require_all_fan_call_targets(target_cards),
         {:ok, moved_cards} <- move_deck_targets_to_hand(game.id, player_id, target_cards),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :cards_moved, player_id, %{
             reason: :ability_effect_resolution,
             source: pending_effect_source_payload(pending_effect),
             effect_key: pending_effect.effect_key,
             cards: EventPayloads.moved_cards(moved_cards, :deck, :hand)
           }),
         {:ok, _shuffled_deck} <-
           shuffle_deck_after_ability_search(game, player_id, @fan_call_ability_id),
         {:ok, _event} <-
           write_event_and_snapshot(game.id, :deck_shuffled, player_id, %{
             source: pending_effect_source_payload(pending_effect),
             effect_key: pending_effect.effect_key
           }),
         {:ok, _game} <- complete_pending_effect(pending_effect, selected_card_instance_ids) do
      GameStore.get_game(game.id)
    end
  end

  def adrena_brain_used_this_turn?(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> adrena_brain_marker()
    |> marker_matches_turn?(turn)
  end

  def teal_dance_used_this_turn?(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> teal_dance_marker()
    |> marker_matches_turn?(turn)
  end

  def flip_the_script_used_this_turn?(cards, %Turn{} = turn) when is_list(cards) do
    Enum.any?(cards, &flip_the_script_used_this_turn?(&1, turn))
  end

  def flip_the_script_used_this_turn?(%CardInstance{markers: markers}, %Turn{} = turn) do
    markers
    |> flip_the_script_marker()
    |> marker_matches_turn?(turn)
  end

  def ability_used_this_turn?(%CardInstance{markers: markers}, %Turn{} = turn, ability_id)
      when is_atom(ability_id) do
    markers
    |> ability_marker(ability_id)
    |> marker_matches_turn?(turn)
  end

  def require_own_pokemon_knocked_out_during_opponents_last_turn(
        game_id,
        %Turn{} = turn,
        player_id
      )
      when is_binary(game_id) and is_binary(player_id) do
    with {:ok, previous_turn} <- previous_turn(game_id, turn.turn_number),
         :ok <- require_previous_turn_was_opponents_turn(previous_turn, player_id),
         {:ok, previous_turn_knockout_events} <-
           knockout_prize_events_for_turn(game_id, previous_turn.id) do
      if Enum.any?(previous_turn_knockout_events, &any_knockout_for_player?(&1, player_id)) do
        :ok
      else
        {:error, @flip_the_script_unavailable_reason}
      end
    end
  end

  def movable_damage_counter_count(%CardInstance{damage: damage}) when is_integer(damage) do
    damage
    |> max(0)
    |> div(10)
    |> min(@adrena_brain_max_counters)
  end

  def movable_damage_counter_count(%CardInstance{}), do: 0

  def require_damage_counter_count(counters, %CardInstance{} = from_card)
      when is_integer(counters) do
    max_counters = movable_damage_counter_count(from_card)

    cond do
      counters < 1 ->
        {:error, {:invalid_damage_counter_count, counters, 1, max_counters}}

      counters > max_counters ->
        {:error, {:not_enough_damage_counters, from_card.id, counters, max_counters}}

      true ->
        :ok
    end
  end

  def require_damage_counter_count(counters, %CardInstance{} = from_card) do
    {:error,
     {:invalid_damage_counter_count, counters, 1, movable_damage_counter_count(from_card)}}
  end

  def damage_for_counters(counters) when is_integer(counters), do: counters * 10

  def darkness_energy?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, name: "Team Rocket's Energy"}} ->
        true

      {:ok, %{supertype: :energy, provides: provides}} when is_list(provides) ->
        @adrena_brain_required_type in provides

      {:ok, _metadata} ->
        false

      {:error, _reason} ->
        false
    end
  end

  def basic_grass_energy?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, energy_type: :basic, provides: provides}}
      when is_list(provides) ->
        @teal_dance_required_type in provides

      {:ok, _metadata} ->
        false

      {:error, _reason} ->
        false
    end
  end

  def basic_energy?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, energy_type: :basic}} -> true
      {:ok, _metadata} -> false
      {:error, _reason} -> false
    end
  end

  def require_basic_energy(%CardInstance{} = energy_card) do
    if basic_energy?(energy_card) do
      :ok
    else
      {:error, {:not_basic_energy, energy_card.id}}
    end
  end

  def require_basic_grass_energy(%CardInstance{} = energy_card) do
    if basic_grass_energy?(energy_card) do
      :ok
    else
      {:error, {:missing_basic_energy_type, energy_card.id, @teal_dance_required_type}}
    end
  end

  defp require_in_play(%CardInstance{} = source) do
    if in_play?(source) do
      :ok
    else
      {:error, {:ability_source_not_in_play, source.id, source.zone}}
    end
  end

  defp in_play?(%CardInstance{zone: zone}), do: zone in [:active, :bench]

  defp damp_active_card?(%CardInstance{card_id: @damp_card_id, zone: zone})
       when zone in [:active, :bench], do: true

  defp damp_active_card?(%CardInstance{}), do: false

  defp require_attached_darkness_energy(%CardInstance{} = source, attached_cards) do
    if Enum.any?(attached_cards, &darkness_energy?/1) do
      :ok
    else
      {:error, {:missing_attached_energy_type, source.id, @adrena_brain_required_type}}
    end
  end

  defp require_hand_basic_grass_energy(%CardInstance{} = source, hand_cards) do
    if Enum.any?(hand_cards, &basic_grass_energy?/1) do
      :ok
    else
      {:error, {:missing_hand_basic_energy_type, source.id, @teal_dance_required_type}}
    end
  end

  defp require_discard_basic_energy(%CardInstance{} = source, discard_cards) do
    if Enum.any?(discard_cards, &basic_energy?/1) do
      :ok
    else
      {:error, {:missing_discard_basic_energy, source.id}}
    end
  end

  defp require_evolved_this_turn(
         %CardInstance{
           evolves_from_card_instance_id: evolves_from,
           turn_entered_play: turn_number
         },
         %Turn{turn_number: turn_number}
       )
       when not is_nil(evolves_from) do
    :ok
  end

  defp require_evolved_this_turn(%CardInstance{} = source, %Turn{} = turn) do
    {:error,
     {:ability_requires_evolved_this_turn, source.id, source.evolves_from_card_instance_id,
      source.turn_entered_play, turn.turn_number}}
  end

  defp require_non_empty_deck(%CardInstance{}, [_first | _rest]), do: :ok

  defp require_non_empty_deck(%CardInstance{} = source, []) do
    {:error, {:ability_requires_cards_in_deck, source.id}}
  end

  defp require_own_tera_pokemon_in_play(game_id, player_id)
       when is_binary(game_id) and is_binary(player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      if Enum.any?(cards, &own_tera_pokemon_in_play?(&1, player_id)) do
        :ok
      else
        {:error, @jewel_seeker_unavailable_reason}
      end
    end
  end

  defp require_ability_unused(%CardInstance{} = source, %Turn{} = turn, ability_id) do
    if ability_used_this_turn?(source, turn, ability_id) do
      {:error, {:ability_already_used_this_turn, source.id, ability_id}}
    else
      :ok
    end
  end

  defp adrena_brain_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @adrena_brain_ability_id),
         %{
           type: @adrena_brain_effect_type,
           max_counters: max_counters,
           requires_attached_type: @adrena_brain_required_type
         } <- effect do
      {:ok, %{max_counters: max_counters}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @adrena_brain_ability_id,
          @adrena_brain_effect_type}}
    end
  end

  defp teal_dance_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @teal_dance_ability_id),
         %{
           type: @teal_dance_effect_type,
           count: draw_count
         } <- effect do
      {:ok, %{draw_count: draw_count}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @teal_dance_ability_id, @teal_dance_effect_type}}
    end
  end

  defp flip_the_script_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @flip_the_script_ability_id),
         %{
           type: @flip_the_script_effect_type,
           count: draw_count
         } <- effect do
      {:ok, %{draw_count: draw_count}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @flip_the_script_ability_id,
          @flip_the_script_effect_type}}
    end
  end

  defp jewel_seeker_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @jewel_seeker_ability_id),
         %{
           type: @jewel_seeker_effect_type,
           max_targets: max_targets
         } <- effect do
      {:ok, %{max_targets: max_targets}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @jewel_seeker_ability_id,
          @jewel_seeker_effect_type}}
    end
  end

  defp seething_spirit_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: %{type: @seething_spirit_effect_type}} <-
           Map.get(abilities, @seething_spirit_ability_id) do
      {:ok, %{}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @seething_spirit_ability_id,
          @seething_spirit_effect_type}}
    end
  end

  defp psychic_draw_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @psychic_draw_ability_id),
         %{
           type: @psychic_draw_effect_type,
           count: draw_count
         } <- effect do
      {:ok, %{draw_count: draw_count}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @psychic_draw_ability_id,
          @psychic_draw_effect_type}}
    end
  end

  defp recon_directive_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: %{type: @recon_directive_effect_type}} <-
           Map.get(abilities, @recon_directive_ability_id) do
      {:ok, %{}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @recon_directive_ability_id,
          @recon_directive_effect_type}}
    end
  end

  defp run_away_draw_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @run_away_draw_ability_id),
         %{
           type: @run_away_draw_effect_type,
           count: draw_count
         } <- effect do
      {:ok, %{draw_count: draw_count}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @run_away_draw_ability_id,
          @run_away_draw_effect_type}}
    end
  end

  defp cursed_blast_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: effect} <- Map.get(abilities, @cursed_blast_ability_id),
         %{
           type: @cursed_blast_effect_type,
           counters: counters
         } <- effect do
      {:ok, %{counters: counters}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @cursed_blast_ability_id,
          @cursed_blast_effect_type}}
    end
  end

  defp last_ditch_catch_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: %{type: @last_ditch_effect_type}} <-
           Map.get(abilities, @last_ditch_catch_ability_id) do
      {:ok, %{}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @last_ditch_catch_ability_id,
          @last_ditch_effect_type}}
    end
  end

  defp fan_call_effect(%CardInstance{card_id: card_id}) do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: %{type: :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn}} <-
           Map.get(abilities, @fan_call_ability_id) do
      {:ok, %{}}
    else
      _other ->
        {:error,
         {:unsupported_ability_effect, card_id, @fan_call_ability_id,
          :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn}}
    end
  end

  defp require_fan_call_first_turn(%Turn{turn_number: turn_number}) when turn_number <= 2, do: :ok

  defp require_fan_call_first_turn(%Turn{}), do: {:error, :fan_call_only_available_on_first_turn}

  defp own_tera_pokemon_in_play?(
         %CardInstance{owner_player_id: player_id, zone: zone} = card,
         player_id
       )
       when zone in [:active, :bench] do
    CardCatalog.tera_pokemon?(card.card_id)
  end

  defp own_tera_pokemon_in_play?(%CardInstance{}, _player_id), do: false

  defp require_last_ditch_unused(game_id, player_id, %Turn{} = turn)
       when is_binary(game_id) and is_binary(player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      player_cards = Enum.filter(cards, &(&1.owner_player_id == player_id))

      if Enum.any?(
           player_cards,
           &ability_used_this_turn?(&1, turn, @last_ditch_marker_ability_id)
         ) do
        {:error, {:ability_already_used_this_turn, player_id, @last_ditch_marker_ability_id}}
      else
        :ok
      end
    end
  end

  defp adrena_brain_marker(markers) when is_map(markers) do
    Map.get(markers, @adrena_brain_marker_key) || Map.get(markers, @adrena_brain_marker_atom_key)
  end

  defp adrena_brain_marker(_markers), do: nil

  defp teal_dance_marker(markers) when is_map(markers) do
    Map.get(markers, @teal_dance_marker_key) || Map.get(markers, @teal_dance_marker_atom_key)
  end

  defp teal_dance_marker(_markers), do: nil

  defp flip_the_script_marker(markers) when is_map(markers) do
    Map.get(markers, @flip_the_script_marker_key) ||
      Map.get(markers, @flip_the_script_marker_atom_key)
  end

  defp flip_the_script_marker(_markers), do: nil

  defp put_ability_used_marker(
         %CardInstance{markers: markers, card_id: card_id},
         %Turn{} = turn,
         ability_id
       ) do
    markers
    |> normalize_markers()
    |> Map.put(ability_marker_key(ability_id), %{
      "ability_id" => Atom.to_string(ability_id),
      "source_card_id" => card_id,
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number
    })
  end

  defp ability_marker(markers, ability_id) when is_map(markers) and is_atom(ability_id) do
    Map.get(markers, ability_marker_key(ability_id))
  end

  defp ability_marker(_markers, _ability_id), do: nil

  defp ability_marker_key(ability_id), do: "ability_used:#{ability_id}"

  defp previous_turn(_game_id, turn_number) when turn_number <= 1,
    do: {:error, @flip_the_script_unavailable_reason}

  defp previous_turn(game_id, turn_number) do
    case TurnStore.list_all_turns(game_id) do
      {:ok, turns} ->
        turns
        |> Enum.find(&(&1.turn_number == turn_number - 1))
        |> case do
          %Turn{} = turn -> {:ok, turn}
          nil -> {:error, @flip_the_script_unavailable_reason}
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
      {:error, @flip_the_script_unavailable_reason}
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

  defp any_knockout_for_player?(%GameEvent{payload: payload}, player_id) do
    payload
    |> Map.get("knockouts", [])
    |> Enum.any?(fn
      %{"knocked_out_player_id" => ^player_id} -> true
      _other -> false
    end)
  end

  defp marker_matches_turn?(marker, %Turn{id: turn_id, turn_number: turn_number})
       when is_map(marker) do
    marker_value(marker, "turn_id", :turn_id) == turn_id or
      marker_value(marker, "turn_number", :turn_number) == turn_number
  end

  defp marker_matches_turn?(_marker, %Turn{}), do: false

  defp marker_value(marker, string_key, atom_key) do
    Map.get(marker, string_key) || Map.get(marker, atom_key)
  end

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}

  defp require_max_target_count(target_ids, max) when is_list(target_ids) do
    if length(target_ids) <= max do
      :ok
    else
      {:error, {:too_many_targets, length(target_ids), max}}
    end
  end

  defp require_prompt_legal_choices(%Prompt{payload: payload}, selected_card_instance_ids) do
    legal_choices = Map.get(payload, "legal_choices", [])

    if Enum.all?(selected_card_instance_ids, &(&1 in legal_choices)) do
      :ok
    else
      {:error, :invalid_prompt_choice}
    end
  end

  defp require_all_fan_call_targets(cards) when is_list(cards) do
    results = Enum.map(cards, &require_fan_call_target/1)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      first_error = Enum.find(results, &match?({:error, _}, &1))
      first_error || :ok
    end
  end

  defp require_fan_call_target(%CardInstance{} = card) do
    with {:ok, metadata} <- CardCatalog.fetch(card.card_id),
         true <- metadata.supertype == :pokemon || {:error, {:not_pokemon, card.card_id}},
         true <- colorless_pokemon?(metadata) || {:error, {:not_colorless, card.card_id}},
         {:ok, hp} <- pokemon_hp(card.card_id),
         true <- hp <= 100 || {:error, {:hp_too_high, card.card_id, hp, 100}} do
      :ok
    end
  end

  defp require_all_last_ditch_targets(cards) when is_list(cards) do
    results = Enum.map(cards, &require_last_ditch_target/1)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      first_error = Enum.find(results, &match?({:error, _}, &1))
      first_error || :ok
    end
  end

  defp require_last_ditch_target(%CardInstance{} = card) do
    with {:ok, metadata} <- CardCatalog.fetch(card.card_id),
         true <- metadata.supertype == :trainer || {:error, {:not_trainer, card.card_id}},
         true <- metadata.trainer_type == :supporter || {:error, {:not_supporter, card.card_id}} do
      :ok
    end
  end

  defp require_all_jewel_seeker_targets(cards) when is_list(cards) do
    results = Enum.map(cards, &require_jewel_seeker_target/1)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      first_error = Enum.find(results, &match?({:error, _}, &1))
      first_error || :ok
    end
  end

  defp require_jewel_seeker_target(%CardInstance{} = card) do
    with {:ok, metadata} <- CardCatalog.fetch(card.card_id),
         true <- metadata.supertype == :trainer || {:error, {:not_trainer, card.card_id}} do
      :ok
    end
  end

  defp colorless_pokemon?(%{supertype: :pokemon, types: types}) when is_list(types) do
    :colorless in types
  end

  defp colorless_pokemon?(%{supertype: :pokemon, type: :colorless}), do: true
  defp colorless_pokemon?(_), do: false

  defp last_ditch_catch_target?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :trainer, trainer_type: :supporter}} -> true
      _other -> false
    end
  end

  defp jewel_seeker_target?(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :trainer}} -> true
      _other -> false
    end
  end

  defp jewel_seeker_max_targets_from_pending_effect(game_id, %PendingEffect{} = pending_effect)
       when is_binary(game_id) do
    with {:ok, source_card} <- CardStore.get_card(game_id, pending_effect.source_card_instance_id) do
      jewel_seeker_max_targets(source_card)
    end
  end

  defp move_deck_targets_to_hand(_game_id, _player_id, []), do: {:ok, []}

  defp move_deck_targets_to_hand(game_id, player_id, target_cards) do
    target_cards
    |> Enum.reduce_while({:ok, []}, fn card, {:ok, acc} ->
      case CardStore.move_deck_card_to_hand(game_id, player_id, card) do
        {:ok, moved_card} -> {:cont, {:ok, [moved_card | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, moved_cards} -> {:ok, Enum.reverse(moved_cards)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp shuffle_deck_after_ability_search(%Game{} = game, player_id, effect_key) do
    context = {:ability_deck_shuffle, player_id, effect_key}

    with {:ok, cards} <- CardStore.cards_in_zone(game.id, player_id, :deck) do
      cards
      |> Rng.shuffle(game.rng_seed, context)
      |> reorder_deck_cards()
    end
  end

  defp complete_pending_effect(%PendingEffect{} = pending_effect, selected_card_instance_ids) do
    with {:ok, _pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.put(
                 pending_effect.state || %{},
                 "selected_card_instance_ids",
                 selected_card_instance_ids
               )
           }) do
      GameStore.get_game(pending_effect.game_id)
    end
  end

  defp reorder_deck_cards(cards) do
    cards
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {card, position}, {:ok, acc} ->
      case update(card, :reorder_deck, %{position: position}) do
        {:ok, updated_card} -> {:cont, {:ok, [updated_card | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reordered} -> {:ok, Enum.reverse(reordered)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pending_effect_source_payload(%PendingEffect{} = pending_effect) do
    %{
      card_id: pending_effect.source_card_id,
      card_instance_id: pending_effect.source_card_instance_id
    }
  end
end

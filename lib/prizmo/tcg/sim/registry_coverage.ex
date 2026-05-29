defmodule Prizmo.Tcg.Sim.RegistryCoverage do
  @moduledoc """
  Coverage report for the known metadata-backed simulator deck pool.

  This is the Phase 5 bridge report while executable card behavior remains in
  local overlays and static metadata comes from the committed TCGdex cache for
  every known deck card.
  """

  alias Prizmo.Tcg.Cards.Metadata
  alias Prizmo.Tcg.Data.TCGdex
  alias Prizmo.Tcg.Sim.CardRegistry

  @implemented_card_behaviors %{
    "MEG-119" => :lillies_determination,
    "SCR-133" => :crispin,
    "MEG-114" => :boss_orders,
    "POR-076" => :judge,
    "PFL-087" => :dawn,
    "POR-071" => :crushing_hammer,
    "TEF-144" => :buddy_buddy_poffin,
    "POR-081" => :poke_pad,
    "SVI-186" => :pokegear_3_0,
    "MEG-131" => :ultra_ball,
    "ASC-196" => :night_stretcher,
    "TWM-165" => :unfair_stamp,
    "MEG-127" => :risky_ruins,
    "DRI-180" => :team_rockets_watchtower,
    "PFL-085" => :battle_cage,
    "WHT-084" => :hilda,
    "TWM-155" => :lanas_aid,
    "MEG-125" => :rare_candy,
    "TWM-148" => :enhanced_hammer,
    "TWM-143" => :bug_catching_set,
    "TWM-149" => :festival_grounds,
    "TWM-163" => :secret_box,
    "DRI-168" => :sacred_ash,
    "DRI-170" => :team_rockets_archer,
    "DRI-171" => :team_rockets_ariana,
    "DRI-173" => :team_rockets_factory,
    "DRI-174" => :team_rockets_giovanni,
    "DRI-177" => :team_rockets_proton,
    "DRI-178" => :team_rockets_transceiver,
    "TWM-154" => :kieran,
    "JTG-143" => :black_belts_training,
    "SSP-170" => :cyrano,
    "TEF-145" => :ciphermaniacs_codebreaking,
    "MEG-115" => :energy_switch,
    "WHT-080" => :brave_bangle,
    "TWM-158" => :lucky_helmet,
    "SSP-169" => :counter_gain,
    "TWM-150" => :handheld_fan,
    "ASC-181" => :air_balloon,
    "MEG-117" => :forest_of_vitality,
    "MEG-132" => :wallys_compassion
  }

  @implemented_effect_types MapSet.new([
                              :active_damage_counters_per_hand_card,
                              :active_draw_once_per_turn,
                              :attach_basic_energy_from_discard_to_self,
                              :bench_basic_psychic_from_deck_when_attached_to_psychic,
                              :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
                              :bonus_damage_if_defender_pokemon_ex,
                              :bonus_damage_if_moved_from_bench_to_active_this_turn,
                              :bonus_damage_on_coin_heads,
                              :bonus_damage_per_coin_heads_count,
                              :bonus_damage_per_energy_attached_to_defender,
                              :choose_switch_active_or_turn_bonus_attack_damage_to_opponent_active_pokemon_ex_or_v,
                              :confuse_defender_active,
                              :damage_per_own_basic_pokemon_in_play,
                              :damage_one_opponent_pokemon,
                              :damage_only_if_stadium_in_play,
                              :damage_unaffected_by_effects_on_opponent_active,
                              :damage_per_own_team_rocket_pokemon_in_play,
                              :discard_hand_then_draw,
                              :discard_3_then_search_item_tool_supporter_stadium_to_hand,
                              :draw_until_hand_size_or_more_if_all_own_pokemon_are_team_rocket,
                              :draw_if_own_pokemon_knocked_out_last_turn,
                              :draw_cards_if_damaged_as_active_by_attack,
                              :draw_after_playing_team_rocket_supporter,
                              :draw_then_shuffle_self_into_deck,
                              :draw_when_attached_from_hand,
                              :evolution_draw,
                              :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand,
                              :lock_opponent_items_next_turn,
                              :move_basic_energy_between_own_pokemon,
                              :move_damage_counters,
                              :opponent_bench_damage_counters,
                              :opponent_cannot_play_ace_spec_if_tool_attached,
                              :pokemon_lose_self_knock_out_abilities,
                              :prevent_attack_damage_to_non_rule_box_bench,
                              :prevent_attack_damage_and_effects_to_bench,
                              :prevent_damage_counters_to_bench_from_opponent_pokemon_effects,
                              :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads,
                              :prevent_opponent_attack_effects_to_attached_pokemon,
                              :recover_trainer_from_discard_to_hand,
                              :reduce_attack_cost_by_colorless_if_more_prizes_remaining,
                              :return_attacker_and_attached_to_hand,
                              :search_deck_for_cards_to_top,
                              :search_pokemon_to_hand,
                              :search_pokemon_ex_to_hand,
                              :search_basic_team_rocket_pokemon_to_hand,
                              :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn,
                              :search_deck_for_card_to_hand_if_active_has_festival_lead,
                              :search_team_rocket_supporter_to_hand,
                              :search_supporter_when_benched_from_hand,
                              :self_damage,
                              :shuffle_each_player_hand_into_deck_then_draw_if_team_rocket_knocked_out,
                              :shuffle_self_and_attached_into_deck,
                              :special_condition_immunity_for_pokemon_with_energy,
                              :switch_active_team_rocket_with_benched_team_rocket_then_gust_opponent,
                              :switch_self_with_bench,
                              :top_n_choose_grass_pokemon_or_basic_grass_energy_to_hand,
                              :top_n_choose_supporter_to_hand,
                              :top_two_choose_one_to_hand_other_to_bottom,
                              :turn_bonus_attack_damage_to_opponent_active_pokemon_ex
                            ])

  def report do
    deck_index = deck_index()

    cards = Enum.map(TCGdex.known_card_ids(), &card_report(&1, deck_index))

    %{
      source: :metadata_cache_with_registry_overlays,
      decks: deck_reports(),
      cards: cards,
      summary: summary(cards)
    }
  end

  def deck_reports do
    Enum.map(known_decks(), fn deck ->
      counts = deck.module.counts()
      card_ids = Enum.map(counts, &elem(&1, 0))

      %{
        id: deck.id,
        name: deck.name,
        module: deck.module,
        source_url: deck.module.source_url(),
        card_count: Enum.sum(Enum.map(counts, &elem(&1, 1))),
        unique_card_count: length(card_ids),
        unsupported_card_ids: Enum.reject(card_ids, &supported_card?/1)
      }
    end)
  end

  defp card_report(card_id, deck_index) do
    decks = Map.get(deck_index, card_id, [])

    case CardRegistry.fetch(card_id) do
      {:ok, card} ->
        card_report(card_id, card.name, decks, :metadata_cached, behavior_families(card_id, card))

      {:error, {:unsupported_card, ^card_id}} ->
        metadata_card_report(card_id, decks)

      {:error, {:metadata_not_cached, ^card_id}} ->
        missing_metadata_card_report(card_id, decks)
    end
  end

  defp metadata_card_report(card_id, decks) do
    case Metadata.fetch(card_id) do
      {:ok, metadata} ->
        card_report(
          card_id,
          metadata.name,
          decks,
          :metadata_cached,
          behavior_families(card_id, metadata)
        )

      {:error, {:metadata_not_cached, ^card_id}} ->
        missing_metadata_card_report(card_id, decks)
    end
  end

  defp missing_metadata_card_report(card_id, decks) do
    card_report(card_id, card_id, decks, :metadata_missing, [
      %{family: :card, id: nil, name: card_id, status: :behavior_missing}
    ])
  end

  defp card_report(card_id, name, decks, metadata_status, families) do
    %{
      card_id: card_id,
      name: name,
      decks: decks,
      metadata_status: metadata_status,
      behavior_status: aggregate_behavior_status(families),
      behavior_families: families
    }
  end

  defp behavior_families(card_id, metadata) do
    case card_supertype(metadata) do
      :pokemon -> ability_families(metadata) ++ attack_families(card_id, metadata)
      :trainer -> trainer_families(card_id, metadata)
      :energy -> energy_families(metadata)
      _supertype -> []
    end
  end

  defp trainer_families(card_id, metadata) do
    family = Map.fetch!(metadata, :trainer_type)

    case Map.fetch(@implemented_card_behaviors, card_id) do
      {:ok, behavior} ->
        [%{family: family, id: behavior, name: metadata.name, status: :implemented}]

      :error ->
        [%{family: family, id: nil, name: metadata.name, status: card_effect_status(metadata)}]
    end
  end

  defp energy_families(metadata) do
    effect = Map.get(metadata, :effect)

    [
      %{
        family: :energy,
        id: Map.get(effect || %{}, :type, :energy_attachment),
        name: metadata.name,
        status: card_effect_status(metadata)
      }
    ]
  end

  defp ability_families(metadata) do
    metadata
    |> Map.get(:abilities, %{})
    |> Enum.map(fn {ability_id, ability} ->
      %{
        family: :ability,
        id: ability_id,
        name: ability.name,
        status: card_effect_status(ability)
      }
    end)
  end

  defp attack_families(card_id, metadata) do
    metadata
    |> Map.get(:attacks, %{})
    |> Enum.map(fn {attack_id, attack} ->
      %{
        family: :attack,
        id: attack_id,
        name: attack.name,
        status: attack_status(card_id, attack)
      }
    end)
  end

  defp attack_status(_card_id, %{effect: effect}), do: effect_status(effect)

  defp attack_status(_card_id, attack) do
    cond do
      raw_effect?(attack) -> :behavior_missing
      plain_damage?(Map.get(attack, :damage)) -> :generic_damage_only
      true -> :behavior_missing
    end
  end

  defp card_effect_status(%{effect: effect}), do: effect_status(effect)

  defp card_effect_status(entry),
    do: if(raw_effect?(entry), do: :behavior_missing, else: :implemented)

  defp plain_damage?(damage) when is_integer(damage), do: damage > 0

  defp plain_damage?(damage) when is_binary(damage) do
    case Integer.parse(damage) do
      {parsed_damage, ""} -> parsed_damage > 0
      _other -> false
    end
  end

  defp plain_damage?(_damage), do: false

  defp raw_effect?(entry) do
    case Map.get(entry, :raw_effect) do
      raw_effect when raw_effect in [nil, ""] -> false
      _raw_effect -> true
    end
  end

  defp effect_status(nil), do: :implemented

  defp effect_status(%{type: effect_type}) do
    if MapSet.member?(@implemented_effect_types, effect_type) do
      :implemented
    else
      :unsupported_effect
    end
  end

  defp effect_status(_effect), do: :unsupported_effect

  defp aggregate_behavior_status([]), do: :implemented

  defp aggregate_behavior_status(families) do
    statuses = Enum.map(families, & &1.status)

    cond do
      :unsupported_effect in statuses -> :unsupported_effect
      :behavior_missing in statuses -> :behavior_missing
      Enum.all?(statuses, &(&1 == :generic_damage_only)) -> :generic_damage_only
      true -> :implemented
    end
  end

  defp summary(cards) do
    %{
      card_count: length(cards),
      deck_card_count: Enum.count(cards, &(&1.decks != [])),
      metadata_statuses: status_counts(cards, :metadata_status),
      behavior_statuses: status_counts(cards, :behavior_status),
      behavior_family_statuses: behavior_family_statuses(cards)
    }
  end

  defp status_counts(rows, key) do
    rows
    |> Enum.frequencies_by(&Map.fetch!(&1, key))
    |> Enum.sort_by(fn {status, _count} -> status end)
    |> Map.new()
  end

  defp behavior_family_statuses(cards) do
    cards
    |> Enum.flat_map(& &1.behavior_families)
    |> Enum.frequencies_by(& &1.status)
    |> Enum.sort_by(fn {status, _count} -> status end)
    |> Map.new()
  end

  defp deck_index do
    known_decks()
    |> Enum.flat_map(fn deck ->
      Enum.map(deck.module.counts(), fn {card_id, _count} -> {card_id, deck.id} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {card_id, deck_ids} -> {card_id, Enum.sort(deck_ids)} end)
  end

  defp known_decks do
    Enum.map(TCGdex.known_deck_modules(), fn module ->
      %{id: module.id(), name: module.name(), module: module}
    end)
  end

  defp card_supertype(metadata), do: Map.get(metadata, :supertype) || Map.get(metadata, :category)

  defp supported_card?(card_id), do: match?({:ok, _card}, CardRegistry.fetch(card_id))
end

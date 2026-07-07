defmodule Prizmo.Tcg.Cards.Behaviors.TWM do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "TWM-014" do
    attack(:smash_kick, effect: nil)
    attack(:branch_poke, effect: nil)
  end

  card "TWM-015" do
    ability(:boom_boom_groove,
      effect: %{type: :search_deck_for_card_to_hand_if_active_has_festival_lead}
    )

    attack(:beat, effect: nil)
  end

  card "TWM-017" do
    attack(:tumbling_attack,
      damage: 10,
      effect: %{type: :bonus_damage_on_coin_heads, bonus_damage: 20}
    )
  end

  card "TWM-018" do
    ability(:festival_lead,
      effect: %{type: :may_attack_twice_if_festival_grounds_in_play}
    )

    attack(:do_the_wave,
      damage: 0,
      effect: %{type: :damage_per_own_benched_pokemon, damage_per_pokemon: 20}
    )
  end

  card "TWM-025" do
    tag(:tera)

    ability(:teal_dance,
      effect: %{type: :attach_basic_grass_energy_from_hand_to_self_then_draw, count: 1}
    )

    attack(:myriad_leaf_shower,
      damage: 30,
      effect: %{type: :bonus_damage_per_energy_attached_to_both_active, bonus_damage: 30}
    )
  end

  card "TWM-039" do
    attack(:allure, damage: 0, effect: %{type: :draw_after_attack, count: 2})

    attack(:ground_melter,
      damage: 60,
      effect: %{type: :bonus_damage_if_stadium_in_play_then_discard_stadium, bonus_damage: 60}
    )
  end

  card "TWM-044" do
    ability(:festival_lead,
      effect: %{type: :may_attack_twice_if_festival_grounds_in_play}
    )

    attack(:whirlpool,
      effect: %{type: :discard_defending_energy_on_coin_heads}
    )
  end

  card "TWM-052" do
    attack(:damage_beat,
      damage: 0,
      effect: %{type: :damage_per_defender_damage_counter, damage_per_counter: 20}
    )

    attack(:crazy_headbutt,
      effect: %{type: :discard_attached_energy_from_attacker, discard_count: 1}
    )
  end

  card "TWM-053" do
    ability(:freezing_shroud,
      effect: %{
        type: :pokemon_checkup_damage_to_pokemon_with_abilities_except_names,
        damage_counters: 1,
        except_names: ["Froslass"]
      }
    )

    attack(:frost_smash, effect: nil)
  end

  card "TWM-057" do
    attack(:numbing_water, effect: %{type: :paralyze_defender_on_coin_heads})
  end

  card "TWM-064" do
    tag(:tera)

    attack(:sob,
      effect: %{type: :defending_pokemon_cannot_retreat_next_turn}
    )

    attack(:torrential_pump,
      effect: %{
        type: :shuffle_attached_energy_into_deck_then_damage_opponent_bench,
        energy_count: 3,
        bench_damage: 120
      }
    )
  end

  card "TWM-080" do
    ability(:teleporter, effect: %{type: :shuffle_self_and_attached_into_deck})
    attack(:beam, effect: nil)
  end

  card "TWM-112" do
    tag(:tera)

    ability(:cornerstone_stance,
      effect: %{type: :prevent_attack_damage_from_opponent_pokemon_with_abilities}
    )

    attack(:demolish,
      damage: 140,
      effect: %{type: :damage_unaffected_by_weakness_resistance_and_effects_on_opponent_active}
    )
  end

  card "TWM-082" do
    attack(:strange_hacking,
      effect: %{type: :confuse_defender_active_then_move_opponent_damage_counters}
    )

    attack(:psychic,
      damage: 10,
      effect: %{type: :bonus_damage_per_energy_attached_to_defender, bonus_damage: 50}
    )
  end

  card "TWM-095" do
    ability(:adrena_brain,
      effect: %{type: :move_damage_counters, max_counters: 3, requires_attached_type: :darkness}
    )

    attack(:mind_bend, effect: %{type: :confuse_defender_active})
  end

  card "TWM-106" do
    attack(:shinobi_blade,
      effect: %{type: :search_card_to_hand, min_targets: 0, max_targets: 1}
    )

    attack(:mirage_barrage,
      damage: 0,
      effect: %{
        type:
          :discard_attached_energy_then_damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects,
        discard_count: 2,
        damage: 120,
        target_count: 2
      }
    )
  end

  card "TWM-126" do
    attack(:find_a_friend,
      damage: 0,
      effect: %{type: :search_pokemon_to_hand}
    )

    attack(:rolling_tackle, effect: nil)
  end

  card "TWM-128" do
    attack(:petty_grudge, effect: nil)
    attack(:bite, effect: nil)
  end

  card "TWM-129" do
    ability(:recon_directive,
      effect: %{type: :top_two_choose_one_to_hand_other_to_bottom}
    )

    attack(:dragon_headbutt, effect: nil)
  end

  card "TWM-130" do
    tag(:tera)

    attack(:jet_headbutt, effect: nil)

    attack(:phantom_dive,
      effect: %{type: :opponent_bench_damage_counters, total_counters: 6}
    )
  end

  card "TWM-131" do
    ability(:attract_customers,
      effect: %{
        type: :top_six_choose_supporter_to_hand_then_shuffle,
        look_count: 6,
        max_targets: 1,
        trainer_type: :supporter
      }
    )

    attack(:surf, damage: 50, effect: nil)
  end

  card "TWM-141" do
    ability(:seasoned_skill,
      effect: %{type: :reduce_attack_cost_by_colorless_per_opponent_prize_taken}
    )

    attack(:blood_moon, damage: 240, effect: %{type: :attacker_cannot_attack_next_turn})
  end

  card "TWM-143" do
    card_effect(
      effect: %{
        type: :top_n_choose_grass_pokemon_or_basic_grass_energy_to_hand,
        count: 7,
        max_targets: 2
      }
    )
  end

  card "TWM-149" do
    card_effect(effect: %{type: :special_condition_immunity_for_pokemon_with_energy})
  end

  card "TWM-150" do
    card_effect(effect: %{type: :move_energy_from_attacker_to_defender_bench_on_damage})
  end

  card "TWM-153" do
    card_effect(effect: %{type: :pokemon_tools_have_no_effect})
  end

  card "TWM-154" do
    card_effect(
      effect: %{
        type:
          :choose_switch_active_or_turn_bonus_attack_damage_to_opponent_active_pokemon_ex_or_v,
        bonus_damage: 30
      }
    )
  end

  card "TWM-155" do
    card_effect(
      effect: %{
        type: :recover_non_rule_box_pokemon_and_basic_energy_from_discard_to_hand,
        max_targets: 3
      }
    )
  end

  card "TWM-158" do
    card_effect(effect: %{type: :draw_cards_if_damaged_as_active_by_attack, count: 2})
  end

  card "TWM-163" do
    card_effect(
      effect: %{
        type: :discard_3_then_search_item_tool_supporter_stadium_to_hand,
        discard_count: 3,
        trainer_types: [:item, :tool, :supporter, :stadium]
      }
    )
  end

  card "TWM-165" do
    card_effect(
      effect: %{
        type: :shuffle_each_player_hand_into_deck_then_draw,
        own_draw_count: 5,
        opponent_draw_count: 2,
        requires_own_pokemon_knocked_out_during_opponents_last_turn?: true
      }
    )
  end
end

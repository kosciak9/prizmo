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

  card "TWM-080" do
    ability(:teleporter, effect: %{type: :shuffle_self_and_attached_into_deck})
    attack(:beam, effect: nil)
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
    attack(:jet_headbutt, effect: nil)

    attack(:phantom_dive,
      effect: %{type: :opponent_bench_damage_counters, total_counters: 6}
    )
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

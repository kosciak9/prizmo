defmodule Prizmo.Tcg.Cards.Behaviors.TEF do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "TEF-023" do
    attack(:slight_intrusion,
      damage: 30,
      effect: %{
        type: :slight_intrusion_coin_flip_search_deck_on_heads_self_damage,
        self_damage: 10
      }
    )
  end

  card "TEF-024" do
    ability(:spherical_shield,
      effect: %{type: :prevent_attack_damage_and_effects_to_bench}
    )

    attack(:psychic,
      damage: 10,
      effect: %{type: :bonus_damage_per_energy_attached_to_defender, bonus_damage: 30}
    )
  end

  card "TEF-025" do
    tag(:tera)

    ability(:rapid_vernier,
      effect: %{type: :switch_self_with_active_when_benched_and_move_energy_to_self}
    )

    attack(:prism_edge,
      effect: %{type: :attacker_cannot_attack_next_turn}
    )
  end

  card "TEF-081" do
    tag(:future)

    ability(:cobalt_command,
      effect: %{
        type: :future_pokemon_attack_damage_bonus_to_opponent_active,
        bonus_damage: 20,
        excluded_card_id: "TEF-081"
      }
    )

    attack(:twin_shotels,
      damage: 0,
      effect: %{
        type: :damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects,
        damage: 50,
        target_count: 2
      }
    )
  end

  card "TEF-123" do
    attack(:bellowing_thunder,
      damage: 0,
      effect: %{type: :damage_per_discarded_own_basic_energy, damage_per_energy: 70}
    )

    attack(:burst_roar,
      damage: 0,
      effect: %{type: :discard_hand_then_draw, count: 6}
    )
  end

  card "TEF-128" do
    attack(:gnaw, effect: nil)

    attack(:dig,
      effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}
    )
  end

  card "TEF-129" do
    ability(:run_away_draw,
      effect: %{type: :draw_then_shuffle_self_into_deck, count: 3}
    )

    attack(:land_crush, effect: nil)
  end

  card "TEF-145" do
    card_effect(effect: %{type: :search_deck_for_cards_to_top, count: 2})
  end

  card "TEF-146" do
    card_effect(effect: %{type: :discard_opponent_item_cards_from_hand, max_count: 2})
  end

  card "TEF-152" do
    card_effect(effect: %{type: :attached_pokemon_hp_modifier, amount: 100})
  end

  card "TEF-154" do
    card_effect(effect: %{type: :bonus_attack_damage_to_pokemon_ex, bonus_damage: 50})
  end

  card "TEF-159" do
    card_effect(
      effect: %{
        type: :retreat_cost_reduction_with_low_hp_free_retreat,
        energy_type: :colorless,
        amount: 1,
        remaining_hp_max: 30
      }
    )
  end

  card "TEF-161" do
    card_effect(effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon})
  end
end

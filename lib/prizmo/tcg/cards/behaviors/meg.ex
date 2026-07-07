defmodule Prizmo.Tcg.Cards.Behaviors.MEG do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "MEG-008" do
    attack(:razor_leaf, effect: nil)
  end

  card "MEG-009" do
    attack(:push_down, effect: %{type: :switch_opponent_active_with_bench_chosen_by_opponent})
  end

  card "MEG-010" do
    ability(:wild_growth,
      effect: %{type: :basic_grass_energy_provides_double_grass_non_stacking}
    )

    attack(:solar_beam, effect: nil)
  end

  card "MEG-074" do
    ability(:lunar_cycle,
      effect: %{
        type: :discard_basic_fighting_energy_from_hand_then_draw_if_solrock_in_play,
        discard_count: 1,
        draw_count: 3,
        required_card_id: "MEG-075",
        required_energy_type: :fighting
      }
    )

    attack(:power_gem, effect: nil)
  end

  card "MEG-075" do
    attack(:cosmic_beam,
      damage: 70,
      effect: %{
        type: :damage_only_if_own_bench_has_card_id_unaffected_by_weakness_resistance,
        required_card_id: "MEG-074"
      }
    )
  end

  card "MEG-086" do
    attack(:terminal_period,
      damage: 0,
      effect: %{type: :knock_out_defender_if_exact_damage_counters, damage_counters: 6}
    )

    attack(:claw_of_darkness, effect: %{type: :discard_one_card_from_opponent_hand})
  end

  card "MEG-104" do
    ability(:run_errand, effect: %{type: :active_draw_once_per_turn, count: 2})

    attack(:rapid_fire_combo,
      damage: 200,
      effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: 50}
    )
  end

  card "MEG-055" do
    ability(:psychic_draw, effect: %{type: :evolution_draw, count: 2})
    attack(:super_psy_bolt, effect: nil)
  end

  card "MEG-054" do
    attack(:teleportation_attack,
      damage: 10,
      effect: %{type: :switch_self_with_bench}
    )
  end

  card "MEG-056" do
    ability(:psychic_draw, effect: %{type: :evolution_draw, count: 3})

    attack(:powerful_hand,
      damage: 0,
      effect: %{type: :active_damage_counters_per_hand_card, counters_per_card: 2}
    )
  end

  card "MEG-117" do
    card_effect(
      effect: %{
        type: :same_turn_grass_evolution_exception,
        except_first_turn?: true
      }
    )
  end

  card "MEG-115" do
    card_effect(effect: %{type: :move_basic_energy_between_own_pokemon})
  end

  card "MEG-116" do
    card_effect(
      effect: %{
        type: :search_deck_for_basic_fighting_energy_or_basic_fighting_pokemon
      }
    )
  end

  card "MEG-127" do
    card_effect(effect: %{type: :damage_on_bench_for_basic_non_darkness})
  end

  card "MEG-129" do
    card_effect(
      effect: %{
        type: :switch_active_water_with_benched_water_once_per_turn,
        required_pokemon_type: :water
      }
    )
  end

  card "MEG-130" do
    card_effect(effect: %{type: :switch_own_active_with_bench})
  end

  card "MEG-132" do
    card_effect(
      effect: %{type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand}
    )
  end

  card "MEG-088" do
    attack(:clutch, effect: %{type: :defending_pokemon_cannot_retreat_next_turn})
  end

  card "MEG-094" do
    attack(:gobble_down,
      damage: 0,
      effect: %{type: :damage_per_own_prize_taken, damage_per_prize: 80}
    )

    attack(:huge_bite,
      effect: %{type: :base_damage_if_defender_has_damage_counters, base_damage: 30}
    )
  end
end

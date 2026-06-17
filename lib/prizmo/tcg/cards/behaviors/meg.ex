defmodule Prizmo.Tcg.Cards.Behaviors.MEG do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

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

  card "MEG-127" do
    card_effect(effect: %{type: :damage_on_bench_for_basic_non_darkness})
  end

  card "MEG-130" do
    card_effect(effect: %{type: :switch_own_active_with_bench})
  end

  card "MEG-132" do
    card_effect(
      effect: %{type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand}
    )
  end
end

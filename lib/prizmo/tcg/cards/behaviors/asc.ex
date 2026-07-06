defmodule Prizmo.Tcg.Cards.Behaviors.ASC do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "ASC-008" do
    attack(:growl,
      effect: %{
        type: :defending_pokemon_attacks_do_less_damage_next_turn,
        reduction: 20
      }
    )

    attack(:seed_bomb, effect: nil)
  end

  card "ASC-016" do
    attack(:itchy_pollen, effect: %{type: :lock_opponent_items_next_turn})
  end

  card "ASC-039" do
    ability(:damp, effect: %{type: :pokemon_lose_self_knock_out_abilities})
    attack(:ram, effect: nil)
  end

  card "ASC-047" do
    attack(:resentful_refrain,
      damage: 0,
      effect: %{type: :damage_per_opponent_hand_card, damage_per_card: 50}
    )

    attack(:absolute_snow,
      damage: 150,
      effect: %{type: :sleep_defender_active}
    )
  end

  card "ASC-121" do
    tag(:tera)

    attack(:orichalcum_fang,
      damage: 50,
      effect: %{type: :bonus_damage_if_own_pokemon_knocked_out_last_turn, bonus_damage: 120}
    )

    attack(:impact_blow,
      damage: 200,
      effect: %{type: :attacker_cannot_attack_next_turn}
    )
  end

  card "ASC-142" do
    ability(:flip_the_script,
      effect: %{type: :draw_if_own_pokemon_knocked_out_last_turn, count: 3}
    )

    attack(:cruel_arrow, effect: %{type: :damage_any_opponent_pokemon, amount: 20})
  end

  card "ASC-162" do
    attack(:comet_punch,
      damage: 0,
      effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: 30}
    )

    attack(:wicked_impact,
      damage: 120,
      effect: %{type: :bonus_damage_if_team_rocket_supporter_played_this_turn, bonus_damage: 100}
    )
  end

  card "ASC-181" do
    card_effect(
      effect: %{
        type: :retreat_cost_reduction,
        energy_type: :colorless,
        amount: 2
      }
    )
  end

  card "ASC-197" do
    card_effect(effect: %{type: :tera_attack_cost_increase, amount: 1})
  end

  card "ASC-216" do
    card_effect(effect: %{type: :provides_every_type_when_attached_to_basic})
  end
end

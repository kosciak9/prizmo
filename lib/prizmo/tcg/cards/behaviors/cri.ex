defmodule Prizmo.Tcg.Cards.Behaviors.CRI do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "CRI-061" do
    attack(:bounce_back,
      effect: %{type: :switch_opponent_active_with_bench_chosen_by_opponent}
    )

    attack(:metallic_hammer,
      damage: 150,
      effect: %{
        type: :discard_attached_energy_for_bonus_damage,
        energy_type: :metal,
        discard_count: 3,
        bonus_damage: 150
      }
    )
  end

  card "CRI-070" do
    ability(:watchful_eye,
      effect: %{type: :prevent_damage_counter_moves_between_pokemon}
    )

    attack(:bite, effect: nil)
  end

  card "CRI-080" do
    card_effect(
      effect: %{
        type: :discard_two_cards_to_draw_one,
        discard_count: 2,
        draw_count: 1
      }
    )
  end

  card "CRI-082" do
    card_effect(
      effect: %{
        type: :opponent_hand_to_bottom_then_draw_if_any,
        draw_count: 3,
        requires_opponent_prize_count_at_most: 3
      }
    )
  end

  card "CRI-084" do
    card_effect(
      effect: %{
        type: :water_pokemon_special_condition_immunity_energy,
        required_attached_pokemon_type: :water
      }
    )
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.TEF do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "TEF-024" do
    ability(:spherical_shield,
      effect: %{type: :prevent_attack_damage_and_effects_to_bench}
    )

    attack(:psychic,
      effect: %{type: :bonus_damage_per_energy_attached_to_defender, bonus_damage: 30}
    )
  end

  card "TEF-123" do
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

  card "TEF-161" do
    card_effect(effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon})
  end
end

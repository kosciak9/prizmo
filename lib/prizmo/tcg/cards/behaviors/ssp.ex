defmodule Prizmo.Tcg.Cards.Behaviors.SSP do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SSP-056" do
    ability(:snow_sink,
      effect: %{type: :discard_stadium_when_benched_from_hand}
    )

    attack(:icicle_loop,
      effect: %{type: :return_attached_energy_to_hand}
    )
  end

  card "SSP-076" do
    ability(:skyliner,
      effect: %{type: :basic_pokemon_have_no_retreat_cost}
    )

    attack(:eon_blade,
      effect: %{type: :attacker_cannot_attack_next_turn}
    )
  end

  card "SSP-087" do
    attack(:electromagnetic_sonar,
      effect: %{type: :recover_trainer_from_discard_to_hand}
    )

    attack(:gnaw, effect: nil)
  end

  card "SSP-111" do
    attack(:coordinated_throwing,
      damage: 0,
      effect: %{type: :damage_per_own_basic_pokemon_in_play, damage_per_pokemon: 20}
    )
  end

  card "SSP-169" do
    card_effect(
      effect: %{type: :reduce_attack_cost_by_colorless_if_more_prizes_remaining, amount: 1}
    )
  end

  card "SSP-177" do
    card_effect(effect: %{type: :stage_2_pokemon_hp_modifier, amount: -30})
  end

  card "SSP-170" do
    card_effect(effect: %{type: :search_pokemon_ex_to_hand, max_targets: 3})
  end

  card "SSP-191" do
    card_effect(effect: %{type: :draw_cards_on_attach_from_hand, count: 4})
  end
end

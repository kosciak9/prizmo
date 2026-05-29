defmodule Prizmo.Tcg.Cards.Behaviors.SSP do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

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

  card "SSP-170" do
    card_effect(effect: %{type: :search_pokemon_ex_to_hand, max_targets: 3})
  end
end

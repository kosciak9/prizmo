defmodule Prizmo.Tcg.Cards.Behaviors.SCR do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SCR-012" do
    attack(:spray_fluid, effect: nil)
  end

  card "SCR-114" do
    attack(:triple_stab,
      damage: 0,
      effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: 10}
    )
  end

  card "SCR-115" do
    ability(:jewel_seeker,
      effect: %{type: :search_trainer_cards_when_evolved_with_tera_in_play, max_targets: 2}
    )

    attack(:speed_wing, effect: nil)
  end

  card "SCR-118" do
    ability(:fan_call,
      effect: %{
        type: :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn,
        max_targets: 3
      }
    )

    attack(:assault_landing, effect: %{type: :damage_only_if_stadium_in_play})
  end

  card "SCR-131" do
    card_effect(effect: %{type: :bench_limit_8_with_tera_in_play_else_discard_to_5})
  end

  card "SCR-135" do
    card_effect(
      effect: %{
        type: :attach_basic_energy_from_discard_to_benched_colorless_if_tera_in_play,
        max_targets: 2
      }
    )
  end

  card "SCR-136" do
    card_effect(effect: %{type: :grand_tree_evolve_basic_then_stage_1_from_deck})
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.DRI do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "DRI-010" do
    ability(:flower_curtain,
      effect: %{type: :prevent_attack_damage_to_non_rule_box_bench}
    )

    attack(:smash_kick, effect: nil)
  end

  card "DRI-019" do
    attack(:take_down, effect: %{type: :self_damage, damage: 10})
  end

  card "DRI-020" do
    ability(:charging_up,
      effect: %{type: :attach_basic_energy_from_discard_to_self}
    )

    attack(:rocket_rush,
      damage: 0,
      effect: %{type: :damage_per_own_team_rocket_pokemon_in_play, damage_per_pokemon: 30}
    )
  end

  card "DRI-170" do
    card_effect(
      effect: %{
        type: :shuffle_each_player_hand_into_deck_then_draw_if_team_rocket_knocked_out,
        player_draw: 5,
        opponent_draw: 3
      }
    )
  end

  card "DRI-171" do
    card_effect(
      effect: %{
        type: :draw_until_hand_size_or_more_if_all_own_pokemon_are_team_rocket,
        hand_size: 5,
        team_rocket_hand_size: 8
      }
    )
  end

  card "DRI-173" do
    card_effect(effect: %{type: :draw_after_playing_team_rocket_supporter, count: 2})
  end

  card "DRI-174" do
    card_effect(
      effect: %{
        type: :switch_active_team_rocket_with_benched_team_rocket_then_gust_opponent
      }
    )
  end

  card "DRI-177" do
    card_effect(effect: %{type: :search_basic_team_rocket_pokemon_to_hand, max_targets: 3})
  end

  card "DRI-178" do
    card_effect(effect: %{type: :search_team_rocket_supporter_to_hand})
  end
end

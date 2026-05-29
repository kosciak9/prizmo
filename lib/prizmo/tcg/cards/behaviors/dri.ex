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

  card "DRI-051" do
    ability(:repelling_veil,
      effect: %{type: :prevent_attack_effects_to_basic_team_rocket_pokemon}
    )

    attack(:dark_frost,
      effect: %{type: :bonus_damage_if_attacker_has_team_rocket_energy, bonus_damage: 60}
    )
  end

  card "DRI-081" do
    ability(:power_saver,
      effect: %{type: :cannot_attack_unless_own_team_rocket_pokemon_in_play, count: 4}
    )

    attack(:erasure_ball,
      effect: %{
        type: :discard_energy_from_own_bench_for_bonus_damage,
        max_discards: 2,
        bonus_damage: 60
      }
    )
  end

  card "DRI-087" do
    attack(:gemstone_mimicry,
      effect: %{type: :copy_opponent_active_tera_pokemon_attack}
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

  card "DRI-182" do
    card_effect(effect: %{type: :team_rocket_energy_attachment_and_dual_provides})
  end
end

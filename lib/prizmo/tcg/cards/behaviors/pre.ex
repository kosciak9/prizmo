defmodule Prizmo.Tcg.Cards.Behaviors.PRE do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "PRE-021" do
    ability(:festival_lead,
      effect: %{type: :may_attack_twice_if_festival_grounds_in_play}
    )

    attack(:rapid_draw,
      effect: %{type: :draw_after_attack, count: 2}
    )
  end

  card "PRE-035" do
    attack(:come_and_get_you,
      damage: 0,
      effect: %{type: :put_up_to_3_duskull_from_discard_to_bench}
    )

    attack(:mumble, effect: nil)
  end

  card "PRE-036" do
    ability(:cursed_blast,
      effect: %{type: :damage_counters_to_opponent_pokemon_then_self_knock_out, counters: 5}
    )

    attack(:will_o_wisp, effect: nil)
  end

  card "PRE-037" do
    ability(:cursed_blast,
      effect: %{type: :damage_counters_to_opponent_pokemon_then_self_knock_out, counters: 13}
    )

    attack(:shadow_bind, effect: %{type: :defending_pokemon_cannot_retreat_next_turn})
  end

  card "PRE-086" do
    attack(:jewel_breaker,
      damage: 100,
      effect: %{type: :bonus_damage_if_defender_tera_pokemon, bonus_damage: 230}
    )
  end
end

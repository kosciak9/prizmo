defmodule Prizmo.Tcg.Cards.Behaviors.SFA do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SFA-039" do
    ability(:subjugating_chains,
      effect: %{type: :subjugating_chains_switch_and_poison}
    )

    attack(:irritated_outburst,
      damage: 0,
      effect: %{type: :damage_per_opponent_prize_taken, damage_per_prize: 60}
    )
  end

  card "SFA-040" do
    ability(:ace_nullifier,
      effect: %{type: :opponent_cannot_play_ace_spec_if_tool_attached}
    )

    attack(:magnetic_blast, effect: nil)
  end

  card "SFA-064" do
    card_effect(effect: %{type: :opponent_discards_to_hand_size, target_hand_size: 3})
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.SVP do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "SVP-149" do
    ability(:toxic_subjugation,
      effect: %{type: :extra_poison_damage_counters_during_pokemon_checkup, damage_counters: 5}
    )

    attack(:poison_chain,
      effect: %{type: :poison_defender_active_and_prevent_retreat_next_turn}
    )
  end
end

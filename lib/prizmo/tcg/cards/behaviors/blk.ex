defmodule Prizmo.Tcg.Cards.Behaviors.BLK do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "BLK-040" do
    attack(:slight_shift,
      effect: %{type: :move_opponent_attached_energy_between_pokemon}
    )

    attack(:beam, effect: nil)
  end

  card "BLK-067" do
    ability(:metallic_signal,
      effect: %{
        type: :search_evolution_metal_pokemon_to_hand,
        max_targets: 2
      }
    )

    attack(:protect_charge,
      effect: %{
        type: :attacker_takes_less_damage_from_attacks_next_turn,
        reduction: 30
      }
    )
  end
end

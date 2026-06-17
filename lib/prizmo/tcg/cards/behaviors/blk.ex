defmodule Prizmo.Tcg.Cards.Behaviors.BLK do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "BLK-040" do
    attack(:slight_shift,
      effect: %{type: :move_opponent_attached_energy_between_pokemon}
    )

    attack(:beam, effect: nil)
  end
end

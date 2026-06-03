defmodule Prizmo.Tcg.Cards.Behaviors.POR do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "POR-086" do
    card_effect(effect: %{type: :grass_pokemon_hp_plus_20_energy})
  end

  card "POR-088" do
    card_effect(
      effect: %{
        type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
        max_targets: 2
      }
    )
  end

  card "POR-062" do
    ability(:last_ditch_catch,
      effect: %{type: :search_supporter_when_benched_from_hand, last_ditch?: true}
    )

    attack(:tuck_tail,
      cost: [:colorless, :colorless, :colorless],
      damage: 60,
      effect: %{type: :return_attacker_and_attached_to_hand}
    )
  end
end

defmodule Prizmo.Tcg.Cards.Behaviors.POR do
  @moduledoc false

  use Prizmo.Tcg.Cards.DSL

  card "POR-088" do
    card_effect(
      effect: %{
        type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
        max_targets: 2
      }
    )
  end
end

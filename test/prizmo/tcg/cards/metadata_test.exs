defmodule Prizmo.Tcg.Cards.MetadataTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Cards.Metadata

  test "normalizes cached Pokemon metadata without behavior overlays" do
    metadata = Metadata.fetch!("TWM-130")

    assert metadata.id == "TWM-130"
    assert metadata.tcgdex_id == "sv06-130"
    assert metadata.name == "Dragapult ex"
    assert metadata.category == :pokemon
    assert metadata.types == [:dragon]
    assert metadata.hp == 320
    assert metadata.stage == :stage_2
    assert metadata.evolves_from == "Drakloak"
    assert metadata.suffix == "ex"
    assert metadata.rule_box?
    assert metadata.retreat_count == 1
    assert metadata.retreat_cost == [:colorless]
    assert metadata.legal == %{expanded: true, standard: true}

    assert metadata.attacks["phantom_dive"] == %{
             cost: [:fire, :psychic],
             damage: 200,
             id: "phantom_dive",
             name: "Phantom Dive",
             raw_effect:
               "Put 6 damage counters on your opponent's Benched Pokémon in any way you like."
           }
  end

  test "normalizes cached Trainer metadata and preserves raw printed effect" do
    metadata = Metadata.fetch!("TWM-165")

    assert metadata.name == "Unfair Stamp"
    assert metadata.category == :trainer
    assert metadata.trainer_type == :item
    assert metadata.ace_spec?
    assert metadata.regulation_mark == "H"
    assert metadata.raw_effect =~ "Each player shuffles their hand into their deck."
  end

  test "normalizes cached Energy metadata" do
    metadata = Metadata.fetch!("POR-088")

    assert metadata.name == "Telepathic Psychic Energy"
    assert metadata.category == :energy
    assert metadata.energy_type == :normal
    assert metadata.raw_effect =~ "provides {P} Energy"

    assert metadata.set == %{
             card_count: %{"official" => 88, "total" => 124},
             id: "me03",
             logo: "https://assets.tcgdex.net/en/me/me03/logo",
             name: "Perfect Order",
             symbol: "https://assets.tcgdex.net/univ/me/me03/symbol"
           }
  end

  test "reports uncached metadata without hitting the network" do
    assert Metadata.fetch("NOPE-000") == {:error, {:metadata_not_cached, "NOPE-000"}}
    refute Metadata.cached?("NOPE-000")
  end
end

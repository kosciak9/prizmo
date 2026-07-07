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

  test "normalizes BLK-067 Genesect ex metadata" do
    metadata = Metadata.fetch!("BLK-067")

    assert metadata.tcgdex_id == "sv10.5b-067"
    assert metadata.name == "Genesect ex"
    assert metadata.category == :pokemon
    assert metadata.types == [:metal]
    assert metadata.hp == 220
    assert metadata.stage == :basic
    assert metadata.suffix == "ex"
    assert metadata.rule_box?
    assert metadata.retreat_count == 2
    assert metadata.resistances == [%{type: :grass, value: "-30"}]
    assert metadata.weaknesses == [%{type: :fire, value: "x2"}]

    assert metadata.abilities["metallic_signal"].raw_effect =~
             "search your deck for up to 2 Evolution {M} Pokémon"

    assert metadata.attacks["protect_charge"] == %{
             cost: [:metal, :metal, :colorless],
             damage: 150,
             id: "protect_charge",
             name: "Protect Charge",
             raw_effect:
               "During your opponent's next turn, this Pokémon takes 30 less damage from attacks (after applying Weakness and Resistance)."
           }
  end

  test "normalizes cached TWM-052 Glalie metadata" do
    metadata = Metadata.fetch!("TWM-052")

    assert metadata.tcgdex_id == "sv06-052"
    assert metadata.name == "Glalie"
    assert metadata.category == :pokemon
    assert metadata.types == [:water]
    assert metadata.hp == 120
    assert metadata.stage == :stage_1
    assert metadata.evolves_from == "Snorunt"
    refute metadata.rule_box?
    assert metadata.retreat_count == 2
    assert metadata.weaknesses == [%{type: :metal, value: "×2"}]

    assert metadata.attacks["damage_beat"] == %{
             cost: [:water],
             damage: "20×",
             id: "damage_beat",
             name: "Damage Beat",
             raw_effect:
               "This attack does 20 damage for each damage counter on your opponent's Active Pokémon."
           }

    assert metadata.attacks["crazy_headbutt"] == %{
             cost: [:water, :colorless, :colorless],
             damage: 140,
             id: "crazy_headbutt",
             name: "Crazy Headbutt",
             raw_effect: "Discard an Energy from this Pokémon."
           }
  end

  test "normalizes cached Greninja shared cluster metadata" do
    froakie = Metadata.fetch!("CRI-020")
    frogadier = Metadata.fetch!("CRI-021")
    greninja = Metadata.fetch!("TWM-106")
    grand_tree = Metadata.fetch!("SCR-136")

    assert froakie.tcgdex_id == "me04-020"
    assert froakie.name == "Froakie"
    assert froakie.stage == :basic
    assert froakie.types == [:water]
    assert froakie.hp == 70
    assert froakie.attacks["collect"].raw_effect == "Draw a card."

    assert frogadier.tcgdex_id == "me04-021"
    assert frogadier.name == "Frogadier"
    assert frogadier.stage == :stage_1
    assert frogadier.evolves_from == "Froakie"
    assert frogadier.attacks["summoning_jutsu"].raw_effect =~ "up to 3 Pokémon"

    assert greninja.tcgdex_id == "sv06-106"
    assert greninja.name == "Greninja ex"
    assert greninja.stage == :stage_2
    assert greninja.evolves_from == "Frogadier"
    assert greninja.types == [:fighting]
    assert greninja.hp == 310
    assert greninja.rule_box?
    assert greninja.attacks["shinobi_blade"].damage == 170
    assert greninja.attacks["mirage_barrage"].raw_effect =~ "Discard 2 Energy"

    assert grand_tree.tcgdex_id == "sv07-136"
    assert grand_tree.name == "Grand Tree"
    assert grand_tree.category == :trainer
    assert grand_tree.trainer_type == :stadium
    assert grand_tree.ace_spec?
    assert grand_tree.raw_effect =~ "Stage 1 Pokémon that evolves from 1 of their Basic Pokémon"
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

  test "normalizes cached TEF-147 Explorer's Guidance metadata" do
    metadata = Metadata.fetch!("TEF-147")

    assert metadata.tcgdex_id == "sv05-147"
    assert metadata.name == "Explorer's Guidance"
    assert metadata.category == :trainer
    assert metadata.trainer_type == :supporter
    refute metadata.ace_spec?
    assert metadata.regulation_mark == "H"

    assert metadata.raw_effect ==
             "Look at the top 6 cards of your deck and put 2 of them into your hand. Discard the other cards."
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

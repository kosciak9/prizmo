defmodule Prizmo.Tcg.Sim.CardRegistryTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Cards.Metadata
  alias Prizmo.Tcg.Sim.CardRegistry

  test "fetch uses cached Pokemon metadata as the static base" do
    metadata = Metadata.fetch!("TWM-130")
    card = CardRegistry.fetch!("TWM-130")

    assert card.name == metadata.name
    assert card.supertype == metadata.category
    assert card.tcgdex_id == metadata.tcgdex_id
    assert card.legal == metadata.legal
    assert card.retreat_cost == metadata.retreat_cost
    assert card.evolves_from_name == "Drakloak"

    assert card.attacks.phantom_dive.raw_effect ==
             metadata.attacks["phantom_dive"].raw_effect

    assert card.attacks.phantom_dive.cost == metadata.attacks["phantom_dive"].cost

    assert card.attacks.phantom_dive.effect == %{
             type: :opponent_bench_damage_counters,
             total_counters: 6
           }
  end

  test "fetch preserves temporary evolution id shim for current reducers" do
    card = CardRegistry.fetch!("TWM-130")

    assert card.evolves_from_name == "Drakloak"
    assert card.evolves_from == "TWM-129"
  end

  test "fetch uses cached Trainer and Energy raw effects" do
    unfair_stamp = CardRegistry.fetch!("TWM-165")
    telepathic_energy = CardRegistry.fetch!("POR-088")

    assert unfair_stamp.raw_effect == Metadata.fetch!("TWM-165").raw_effect
    assert unfair_stamp.raw_effect =~ "Each player shuffles their hand into their deck."
    assert unfair_stamp.ace_spec?

    assert telepathic_energy.raw_effect == Metadata.fetch!("POR-088").raw_effect
    assert telepathic_energy.energy_type == :special
    assert telepathic_energy.tcgdex_energy_type == :normal
    assert telepathic_energy.provides == [:psychic]

    assert telepathic_energy.effect == %{
             type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
             max_targets: 2
           }
  end

  test "fetch infers current-engine basic energy fields from cached basic energy metadata" do
    psychic_energy = CardRegistry.fetch!("MEE-005")

    assert psychic_energy.name == Metadata.fetch!("MEE-005").name
    assert psychic_energy.energy_type == :basic
    assert psychic_energy.tcgdex_energy_type == :normal
    assert psychic_energy.provides == [:psychic]
  end

  test "fetch_attack overlays Rabsca Psychic variable damage behavior" do
    assert {:ok, attack} = CardRegistry.fetch_attack("TEF-024", :psychic)

    assert attack.damage == 10
    assert attack.raw_effect =~ "30 more damage for each Energy"

    assert attack.effect == %{
             type: :bonus_damage_per_energy_attached_to_defender,
             bonus_damage: 30
           }
  end
end

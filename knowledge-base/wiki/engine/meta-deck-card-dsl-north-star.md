# Meta Deck, TCGdex, Card DSL, and LiveView Play North Star

Updated: 2026-05-30

Status: historical. This note captured the simulator-era north star. The current north star is [Ash-backed TCG Engine and Playtest UI North Star](ash-backed-tcg-engine-playtest-north-star.md), which makes `lib/prizmo/tcg_engine/` canonical and targets a playable React SPA playtest UI with an Electric Streams data-feed spike.

## Scope

This was the prior north-star implementation plan for moving the Pokémon TCG simulator from two fixed decklists to a maintainable meta-deck platform.

Goals:

- Add four more meta decks from Limitless: Raging Bolt Ogerpon 27599, Festival Lead 27445, Lopunny Dudunsparce 27514, and Rocket's Mewtwo 27459.
- Support all cards needed by those decks and allow any supported deck to play any other supported deck.
- Use TCGdex API/cache as the source for static card metadata: name, type/category, HP, stage, retreat, weakness/resistance when available and normalizable, trainer type, energy type, regulation/legality, images, and raw attack/ability/effect text.
- Do not hand-write static card metadata except temporary compatibility shims or explicit overrides for API gaps.
- Author only executable behavior: attacks, abilities, effects, timing hooks, special conditions, replacement/prevention effects, and exact rules interpretations.
- Add a later very basic Phoenix LiveView UI for two human players to play supported decks.

## Current baseline

- The current simulator is pure Elixir under `lib/prizmo/tcg/sim`.
- It supports Dragapult 27431 vs Alakazam/Dudunsparce 27147 end-to-end as scripted engine actions.
- The existing hand-written registry is the thing to replace or refactor behind a compatibility facade.
- There is no UI yet.

## Target supported deck pool

Existing supported decks:

- Dragapult 27431
- Alakazam/Dudunsparce 27147

New supported decks:

- Raging Bolt Ogerpon 27599
- Festival Lead 27445
- Lopunny Dudunsparce 27514
- Rocket's Mewtwo 27459

The target is pairwise support: any two supported deck modules can start a game, setup, play legal turns, and resolve supported card effects.

## Data and source-of-truth policy

- Prizmo card IDs remain public simulator IDs in `SET-localId` form, for example `TEF-123`.
- Limitless is the deck source and provides deck quantities plus `SET`/`localId` extracted from card links.
- TCGdex uses IDs like `sv05-123`; map Prizmo set abbreviations through TCGdex `set.abbreviation.official`.
- Store external source IDs, but keep Prizmo IDs as public simulator IDs.
- Commit the TCGdex cache and use it in normal tests.
- Network access is opt-in only; normal tests must not hit the network.
- Use `Req` for HTTP clients.

The key architectural decision is that TCGdex owns **static card facts** and Prizmo owns **executable semantics**.

TCGdex/cache should provide:

- card name;
- category/supertype;
- Pokémon type, HP, stage, suffix, retreat, raw weakness/resistance data where available;
- Trainer type;
- Energy type;
- regulation mark and legality;
- image and set identity;
- raw printed attack, Ability, and Trainer text.

Prizmo-authored behavior should provide:

- exact attack execution;
- exact Ability execution;
- Trainer/Tool/Stadium/Energy effects;
- timing hooks;
- prevention/replacement effects;
- exact targeting and hidden-information semantics;
- rulings, exceptions, and project-owned regression tests.

Agents should not copy TCGdex static fields into hand-written maps except as temporary compatibility shims or explicit overrides. If an override is needed, the coverage report should flag it with the reason and source.

Suggested cache layout:

- `priv/tcg/cards/tcgdex/sets.json`
- `priv/tcg/cards/tcgdex/cards/TEF-123.json`

## Metadata architecture

Candidate modules:

- `Prizmo.Tcg.Data.LimitlessDeck`
- `Prizmo.Tcg.Data.TCGdex`
- `Prizmo.Tcg.Cards.Metadata`
- `Prizmo.Tcg.Cards.Registry`

Metadata structs should be generated or normalized from cached TCGdex JSON. `CardRegistry.fetch/1` becomes a compatibility facade that combines the authored behavior overlay with metadata cache records.

Static fields come from the API/cache. Behavior DSL overlays executable fields only. Unsupported raw text should produce explicit unsupported behavior errors when reached, not silent no-ops.

Manual metadata overrides are allowed only for API gaps. Each override needs an explicit comment and should appear as a warning in coverage reports.

Recommended resolution order for `CardRegistry.fetch/1` during migration:

1. Load normalized metadata for the Prizmo card ID from cache.
2. Load behavior overlay for the same Prizmo card ID, if present.
3. Merge metadata plus behavior into the current engine-compatible shape.
4. If a requested attack, Ability, or effect has raw text but no behavior overlay, return an explicit unsupported-behavior error at action time.

This lets the project migrate without a rewrite. Existing cards can remain available while the internal source of static fields moves from the hand-written registry to TCGdex cache.

Compatibility rule: current simulator tests must stay green after every migration step. Do not replace the registry and DSL in one large change.

## Deck import pipeline

The Limitless scraper should fetch a deck page, extract card rows matching `/cards/{SET}/{localId}`, preserve quantity, name/archetype when possible, and validate that the total count is 60.

The TCGdex resolver should map set abbreviations to TCGdex set IDs and fetch all card data needed for imported decks.

Planned mix tasks:

```sh
mix prizmo.deck.import 27599
mix prizmo.deck.import 27599 --module RagingBolt27599
mix prizmo.deck.import 27599 --refresh
mix prizmo.cards.sync
mix prizmo.cards.coverage
mix prizmo.cards.check
```

Current import-path decision: checked-in static deck modules are the accepted path for the first playable meta-deck milestone. A future `mix prizmo.deck.import` task remains desirable for repeatability, but it is not required before the UI phase as long as each supported deck has a committed `Decklist` module, committed TCGdex metadata, and pairwise smoke coverage through `Prizmo.Tcg.Data.TCGdex.known_deck_modules/0`.

Generated deck modules should be committed and use a deck macro with fields such as:

```elixir
deck id: "27599",
     name: "Raging Bolt Ogerpon",
     source_url: "https://limitlesstcg.com/decks/list/27599",
     counts: [...],
     card_ids: [...],
     validate: true
```

## Behavior DSL architecture

Important decision: the DSL must not hand-write static card data. Static metadata comes from the TCGdex cache. The DSL references card IDs and defines executable behavior only.

Desired shape:

```elixir
defmodule Prizmo.Tcg.Cards.Behaviors.TWM do
  use Prizmo.Tcg.Cards.DSL

  card "TWM-130" do
    attack :phantom_dive do
      deal_damage(200, :defending_active)
      place_damage_counters(:opponents_bench, total: 6)
    end
  end
end
```

The DSL may validate that referenced attacks and abilities exist in TCGdex metadata by name or generated slug. It should compile behavior overlay manifests keyed by Prizmo card ID and attack/ability IDs.

The DSL should produce coverage metadata and clear compile/runtime errors. Runtime errors should identify the card, behavior family, deck, and missing primitive or ruling where possible.

DSL responsibilities:

- reference a Prizmo card ID that already exists in metadata cache;
- bind behavior to printed attacks, Abilities, or play effects;
- validate that referenced names/slugs exist in the cached raw metadata;
- define executable behavior using primitives and hooks;
- emit a behavior manifest for coverage tooling;
- allow escape hatches for unusual cards, but make those escape hatches visible in coverage.

DSL non-responsibilities:

- storing HP, stage, type, retreat, card category, legality, or images;
- parsing natural-language card text into executable behavior;
- silently approximating a card whose exact effect is not implemented.

This is the preferred shape because it makes imported card data cheap while keeping exact gameplay semantics reviewable in code.

## Engine hook system

Hooks are needed to avoid brittle reducer-specific checks.

Candidate hook phases:

- `before_play_trainer`
- `before_ability`
- `before_attack_declared`
- `modify_damage`
- `before_damage`
- `after_damage`
- `after_knockout`
- `before_prize_choice`
- `after_prize_choice`
- `before_switch`
- `after_switch`
- `on_attach_energy`
- `on_attach_tool`
- `on_evolve`
- `on_end_turn`
- `on_pokemon_checkup`

Initial hook-sensitive migrations:

- Genesect ACE Nullifier
- Budew Itchy Pollen
- Team Rocket's Watchtower
- Rabsca Spherical Shield
- Handheld Fan

Hook returns should start with `{:ok, state}` and `{:halt, reason}`. Later additions can include prompts and effect additions.

## Behavior and effect primitives

The behavior layer needs primitives for:

- Search
- Draw
- Shuffle hand into deck
- Attach, move, and discard Energy
- Damage, damage counters, healing, prevention, and modification
- Switch, gust, and retreat
- Special conditions
- Prize flow
- Markers and usage limits

## Coverage model

Coverage statuses:

- `metadata_cached`
- `behavior_missing`
- `generic_damage_only`
- `implemented`
- `implemented_with_tests`
- `unsupported_effect`
- `needs_ruling`

Coverage is tracked per card and per behavior family. Supported decks cannot contain `behavior_missing` or `unsupported_effect` for reachable normal-play effects.

`mix prizmo.cards.coverage` should report card, decks, metadata status, behavior status, tests, and final status.

A deck is **supported** only when:

- it has exactly 60 cards;
- every card has cached metadata;
- every normally reachable attack, Ability, Trainer effect, Tool effect, Stadium effect, Energy effect, and rule-box interaction has behavior coverage;
- every unsupported or unresolved effect fails explicitly before it can corrupt state;
- representative tests exist for each unique behavior family in the deck;
- the deck passes setup and pairwise smoke tests against the supported deck pool.

Cards may exist as `metadata_cached` before their deck is supported. This is expected. Metadata import is not the same as playable support.

## Phased plan

### Phase 0: freeze baseline

- Keep Dragapult 27431 vs Alakazam/Dudunsparce 27147 green.
- Added `mix prizmo.cards.coverage` for the current registry: reports the two fixed decks, legacy-registry metadata status, behavior status, and generic-damage-only attack coverage.

### Phase 1: import decks and metadata

- Added a deck macro foundation for generated/static deck modules: source identity,
  names, quantities, `card_ids/0`, and compile-time 60-card validation now live in
  `Prizmo.Tcg.Sim.Decklist`.
- Imported Raging Bolt Ogerpon 27599 as a static deck module using the deck macro.
- Imported Festival Lead 27445 as a static deck module using the deck macro.
- Imported Lopunny Dudunsparce 27514 as a static deck module using the deck macro.
- Imported Rocket's Mewtwo 27459 as a static deck module using the deck macro.
- Added `Prizmo.Tcg.Data.TCGdex` plus opt-in `mix prizmo.cards.sync` network sync for cache generation.
- Cached TCGdex set metadata for the 15 deck-pool sets and card metadata for 101 unique cards across all six known deck modules under `priv/tcg/cards/tcgdex`.
- Keep importer/cache tests offline by default; tag network tests as `:external`.

### Phase 2: metadata-backed registry facade

- Added `Prizmo.Tcg.Cards.Metadata` to read normalized static facts from the committed TCGdex cache for representative Pokémon, Trainer, and Energy cards without changing engine behavior yet.
- Converted `CardRegistry.fetch/1` into a compatibility facade for the existing supported registry IDs.
- Static card data now comes from normalized cached TCGdex metadata in the facade, including raw printed attack, Ability, Trainer, and Energy text.
- Existing authored attack, Ability, and Energy behavior is overlaid onto the metadata-backed base.
- The old hand-written registry entries are now temporary behavior overlays plus explicit compatibility shims for current reducer gaps such as Prizmo-ID evolution links and weakness/resistance cache gaps.
- Added tests proving fetched registry metadata comes from cache for representative Pokémon, Trainer, and Energy cards, and that cached raw attack text without an executable overlay fails explicitly.
- Updated `mix prizmo.cards.coverage` to report `metadata_backed_registry` and `metadata_cached` for the 44 current fixed-deck cards.

### Phase 3: behavior DSL foundation

- Added initial `Prizmo.Tcg.Cards.DSL` executable-behavior manifest foundation.
- DSL `card` declarations now validate referenced card IDs and attack/Ability IDs against cached TCGdex metadata at compile time.
- Added first representative behavior manifest module, `Prizmo.Tcg.Cards.Behaviors.TWM`, declaring Dragapult ex `Phantom Dive` executable effect overlay without moving static facts out of the metadata cache.
- Ported Dragapult ex `Jet Headbutt` as the first representative plain-damage DSL manifest entry, relying on cached TCGdex damage/cost metadata without adding a static overlay.
- Ported Drakloak `Recon Directive` as the first representative Ability DSL manifest entry, relying on cached TCGdex Ability metadata and adding only the executable effect overlay.
- Ported Unfair Stamp as the first representative Item card-effect DSL manifest entry, relying on cached TCGdex Trainer metadata and adding only the executable shuffle/draw eligibility overlay.
- Ported Lana's Aid as the first representative Supporter card-effect DSL manifest entry, relying on cached TCGdex Trainer metadata and adding only the executable discard-recovery overlay.
- Ported Air Balloon as the first representative Tool card-effect DSL manifest entry, relying on cached TCGdex Trainer metadata and adding only the executable retreat-cost reduction overlay.
- Ported Forest of Vitality as the first representative Stadium card-effect DSL manifest entry, relying on cached TCGdex Trainer metadata and adding only the executable same-turn Grass Evolution exception overlay.
- Ported Telepathic Psychic Energy as the first representative Special Energy card-effect DSL manifest entry, relying on cached TCGdex Energy metadata and adding only the executable attach/search overlay.
- Port representative existing cards before broad migration.
- Start with cards that demonstrate different behavior families: plain damage, attack effect, Ability, Item, Supporter, Tool, Stadium, and Special Energy.

### Phase 4: effect primitives and hooks

- Added first hook runner, `Prizmo.Tcg.Sim.Hooks`, with a `:before_play_trainer` phase.
- Migrated Genesect `ACE Nullifier` ACE SPEC prevention out of the engine reducer-specific check and into the `:before_play_trainer` hook path while preserving existing reducer error behavior.
- Migrated Budew `Itchy Pollen` Item-card prevention into the `:before_play_trainer` hook path while preserving existing reducer error behavior.
- Migrated Team Rocket's Watchtower Colorless Ability prevention into the `:before_ability` hook path while preserving existing reducer error behavior.
- Migrated Rabsca `Spherical Shield` opponent attack-effect bench damage prevention into the `:before_damage` hook path while preserving the existing Phantom Dive prevention behavior.
- Migrated Handheld Fan attack-triggered Energy movement into the `:after_damage` hook path while preserving existing declared-attack resolution behavior.
- Add the first hook system.
- Migrate hook-sensitive current effects one by one.
- Avoid card-specific checks embedded in generic reducers.

### Phase 5: new meta-deck behavior families

- Implemented Rabsca `Psychic` as a variable-damage attack primitive and TEF DSL manifest entry, closing the remaining fixed-deck `behavior_missing` coverage gap before broader new-deck behavior-family work.
- Expanded `mix prizmo.cards.coverage` to report all six known deck modules and all 101 cached cards, exposing imported-deck `behavior_missing` and `generic_damage_only` gaps for Phase 5 prioritization.
- Implemented Energy Switch `MEG-115` as the first new imported-deck Item behavior slice, with a DSL manifest entry and reducer action for moving a Basic Energy between the player's Pokémon.
- Registered all deck-pool Basic Energy cards through metadata-only registry overlays, allowing `MEE-001`, `MEE-003`, `MEE-004`, and `MEE-006` to use cache-derived static facts and inferred provided Energy types.
- Implemented Pokégear 3.0 `SVI-186` as a top-seven Supporter search Item behavior slice, with a DSL manifest entry and reducer action that keeps static Trainer text in the TCGdex cache.
- Implemented Bug Catching Set `TWM-143` as a top-seven Grass Pokémon / Basic Grass Energy search Item behavior slice, with a DSL manifest entry and reducer action that validates target eligibility from cached TCGdex static facts.
- Implemented Team Rocket's Transceiver `DRI-178` as a Team Rocket Supporter search Item behavior slice, with a DSL manifest entry and reducer action that validates target eligibility from cached TCGdex static facts even before those Supporters have executable overlays.
- Implemented Team Rocket's Proton `DRI-177` as a Basic Team Rocket's Pokémon search Supporter behavior slice, with a DRI DSL manifest entry, reducer action, and exact first-player first-turn Supporter exception while keeping target eligibility sourced from cached TCGdex static facts.
- Implemented Ciphermaniac's Codebreaking `TEF-145` as a two-card deck search/top-deck ordering Supporter behavior slice, with a DSL manifest entry and reducer action while keeping static Supporter text in the TCGdex cache.
- Implemented Cyrano `SSP-170` as a Pokémon ex deck-search Supporter behavior slice, with an SSP DSL manifest entry and reducer action that validates target eligibility from cached TCGdex static facts.
- Implemented Wally's Compassion `MEG-132` as a Mega Evolution Pokémon ex healing Supporter behavior slice, with a DSL manifest entry and reducer action that validates target eligibility from cached TCGdex static facts and returns attached Energy only when damage was healed.
- Implemented Brave Bangle `WHT-080` as a Tool damage-modifier behavior slice, with a WHT DSL manifest entry and `:modify_damage` hook that adds damage before Weakness/Resistance only for non-rule-box attackers hitting the opponent's Active Pokémon ex.
- Implemented Lucky Helmet `TWM-158` as a Tool after-damage draw behavior slice, with a TWM DSL manifest entry and `:after_damage` hook that draws 2 cards when the attached Active Pokémon is damaged by an opponent's attack.
- Implemented Black Belt's Training `JTG-143` as a Supporter turn-wide damage-modifier behavior slice, with a JTG DSL manifest entry and `:modify_damage` hook that adds 40 damage before Weakness/Resistance to attacks hitting the opponent's Active Pokémon ex.
- Implemented Kieran `TWM-154` as a choose-one Supporter behavior slice, with a TWM DSL manifest entry, reducer choices for switching the player's Active Pokémon or granting +30 turn-wide attack damage, and a `:modify_damage` hook that applies the bonus before Weakness/Resistance to the opponent's Active Pokémon ex/V.
- Implemented Grookey `TWM-014` as an explicit imported-deck plain-damage behavior slice, with TWM DSL manifest entries and registry overlays for `Smash Kick` and `Branch Poke` that keep static cost/damage facts in the TCGdex cache.
- Implemented Applin `SCR-012` as an explicit imported-deck plain-damage behavior slice, with an SCR DSL manifest entry and registry overlay for `Spray Fluid` that keeps static cost/damage facts in the TCGdex cache.
- Implemented Team Rocket's Tarountula `DRI-019` as an imported-deck self-damage attack behavior slice, with a DRI DSL manifest entry and registry overlay for `Take Down` that keeps static attack damage/cost facts in the TCGdex cache.
- Implemented Buneary `PFL-083` as an imported-deck switch/plain-damage attack behavior slice, with a PFL DSL manifest entry and registry overlay for `Run Around` and `Kick` that keeps static attack damage/cost facts in the TCGdex cache.
- Ported Dreepy `TWM-128` from the legacy generic-damage overlay to explicit TWM DSL manifest entries for `Petty Grudge` and `Bite`, keeping static attack damage/cost facts in the TCGdex cache.
- Implemented Passimian `SSP-111` as an imported-deck variable-damage attack behavior slice, with an SSP DSL manifest entry and registry overlay for `Coordinated Throwing` that counts the player's Basic Pokémon in play while keeping static attack text in the TCGdex cache.
- Implemented Applin `TWM-017` as an imported-deck coin-based variable-damage attack behavior slice, with a TWM DSL manifest entry and registry overlay for `Tumbling Attack` that requires explicit `coin_result` params while keeping static attack text in the TCGdex cache.
- Implemented Applin `TWM-126` as an imported-deck search/plain-damage attack behavior slice, with TWM DSL manifest entries and a registry overlay for `Find a Friend` and `Rolling Tackle` that keep static attack text, cost, and damage facts in the TCGdex cache.
- Implemented Abra `TWM-080` as an imported-deck Active-only shuffle Ability/plain-damage attack behavior slice, with TWM DSL manifest entries, a registry overlay for `Teleporter` and `Beam`, and a reducer Ability path that shuffles Abra plus attached cards into the deck while keeping static facts in the TCGdex cache.
- Implemented Shaymin `DRI-010` as an imported-deck bench-protection Ability/plain-damage attack behavior slice, with a DRI DSL manifest entry, registry overlay for `Flower Curtain` and `Smash Kick`, and a `:before_damage` hook that prevents attack damage to the player's non-rule-box Benched Pokémon while preserving damage-counter effects.
- Ported Psyduck `ASC-039` to explicit ASC DSL manifest entries for `Damp` and plain-damage `Ram`, keeping static Ability text, attack cost, and damage facts in the TCGdex cache while reducing imported-deck generic-damage coverage.
- Ported Genesect `SFA-040` `Magnetic Blast` to an explicit SFA DSL manifest entry and registry overlay, keeping static attack cost and damage facts in the TCGdex cache while reducing imported-deck generic-damage coverage.
- Ported Dunsparce `JTG-120` to an explicit JTG DSL manifest entry for `Trading Places` and plain-damage `Ram`, keeping static attack text, cost, and damage facts in the TCGdex cache while reducing generic-damage coverage shared by Alakazam/Dudunsparce 27147 and Lopunny Dudunsparce 27514.
- Ported Drakloak `TWM-129` `Dragon Headbutt` to an explicit TWM DSL manifest entry and registry overlay, keeping static attack cost and damage facts in the TCGdex cache while reducing Dragapult 27431 generic-damage coverage.
- Implemented Team Rocket's Spidops `DRI-020` as an imported-deck discard-Energy attachment Ability and Team Rocket's Pokémon in-play variable-damage attack behavior slice, with a DRI DSL manifest entry, registry overlay, reducer action, and discard-to-attachment lifecycle transition while keeping static Ability and attack text in the TCGdex cache.
- Implemented Thwackey `TWM-015` as an imported-deck conditional deck-search Ability/plain-damage attack behavior slice, with a TWM DSL manifest entry, registry overlay, and reducer action that checks cached Festival Lead Ability metadata on the player's Active Pokémon while keeping static Ability and attack text in the TCGdex cache.
- Implemented Team Rocket's Ariana `DRI-171` as an imported-deck Supporter draw behavior slice, with a DRI DSL manifest entry, registry overlay, and reducer action that draws until 5 cards or until 8 cards when all of the player's Pokémon in play are Team Rocket's Pokémon while keeping static Supporter text in the TCGdex cache.
- Ported Dudunsparce `TEF-129` `Land Crush` to an explicit TEF DSL manifest entry and registry overlay, keeping cached attack cost and damage as the static source of truth while reducing generic-damage coverage shared by Alakazam/Dudunsparce 27147 and Lopunny Dudunsparce 27514.
- Ported Dedenne `SSP-087` `Gnaw` to an explicit SSP DSL manifest entry and registry overlay, keeping cached attack cost and damage as the static source of truth while reducing Alakazam/Dudunsparce 27147 generic-damage coverage.
- Ported Kadabra `MEG-055` `Super Psy Bolt` to an explicit MEG DSL manifest entry and registry overlay, keeping cached attack cost and damage as the static source of truth while reducing Alakazam/Dudunsparce 27147 generic-damage coverage.
- Ported Dragapult ex `TWM-130` `Jet Headbutt` to an explicit TWM DSL manifest entry and registry overlay, keeping cached attack cost and damage as the static source of truth while reducing Dragapult 27431 generic-damage coverage.
- Ported Dunsparce `TEF-128` `Gnaw` to an explicit TEF DSL manifest entry and registry overlay, keeping cached attack cost and damage as the static source of truth while eliminating the last generic-damage-only coverage family for that attack.
- Implemented Dunsparce `TEF-128` `Dig` as a coin-gated next-turn attack damage/effect prevention behavior slice, with a TEF DSL manifest entry, registry overlay, and hook-backed prevention marker while keeping static attack cost, damage, and text in the TCGdex cache.
- Implemented Counter Gain `SSP-169` as an imported-deck Tool attack-cost reduction behavior slice, with an SSP DSL manifest entry, registry overlay, and attack-cost validation that removes one Colorless requirement only while the attached Pokémon's player has more Prize cards remaining than the opponent.
- Implemented Team Rocket's Giovanni `DRI-174` as an imported-deck Supporter switch/gust behavior slice, with a DRI DSL manifest entry, registry overlay, and reducer action that requires switching the player's Active Team Rocket's Pokémon with a Benched Team Rocket's Pokémon before gusting an opponent's Benched Pokémon.
- Implemented Team Rocket's Archer `DRI-170` as an imported-deck Supporter comeback-hand-refresh behavior slice, with a DRI DSL manifest entry, registry overlay, Team Rocket-specific last-turn KO eligibility marker, and reducer action that shuffles both players' hands into their decks before drawing 5 cards for the player and 3 for the opponent.
- Implemented Fan Rotom `SCR-118` as an imported-deck first-turn Colorless Pokémon search Ability and Stadium-conditional attack behavior slice, with an SCR DSL manifest entry, registry overlay, reducer Ability path, and Stadium-gated damage primitive while keeping static Ability and attack text in the TCGdex cache.
- Implemented Battle Cage `PFL-085` as an imported-deck Stadium prevention behavior slice, with a PFL DSL manifest entry, registry overlay, and `:before_damage` hook that prevents damage counters from opponent Pokémon attack/Ability effects from being placed on Benched Pokémon while preserving static Stadium text in the TCGdex cache.
- Implemented Secret Box `TWM-163` as an imported-deck ACE SPEC Item discard/search behavior slice, with a TWM DSL manifest entry, registry overlay, and reducer action that requires discarding 3 other hand cards before searching cached Trainer subtypes for up to one Item, Tool, Supporter, and Stadium while preserving static Item text in the TCGdex cache.
- Implemented Mist Energy `TEF-161` as an imported-deck Special Energy prevention behavior slice, with a TEF DSL manifest entry, registry overlay for `{C}` Energy provision, and hook-backed prevention of opponent attack effects and damage-counter effects done to the attached Pokémon while preserving static Special Energy text in the TCGdex cache.
- Implemented Mega Kangaskhan ex `MEG-104` as an imported-deck Active-only draw Ability and coin-count variable-damage attack behavior slice, with a MEG DSL manifest entry, registry overlay, reducer Ability path, and explicit `heads_count` attack parameter while keeping static Ability and attack text in the TCGdex cache.
- Implemented Festival Grounds `TWM-149` as an imported-deck Stadium special-condition recovery/immunity behavior slice, with a TWM DSL manifest entry, registry overlay, and engine wiring that clears Special Conditions from Pokémon with Energy attached and prevents new Special Conditions while keeping static Stadium text in the TCGdex cache.
- Implemented Mega Lopunny ex `PFL-084` as an imported-deck moved-from-Bench variable-damage attack slice, with a PFL DSL manifest entry, registry overlay, and turn marker for Pokémon that move from Bench to Active while keeping static attack text and damage facts in the TCGdex cache.
- Implemented Team Rocket's Factory `DRI-173` as an imported-deck Stadium draw behavior slice, with a DRI DSL manifest entry, registry overlay, turn marker for Team Rocket Supporters played from hand, and once-per-turn reducer action while keeping static Stadium text in the TCGdex cache.
- Implemented Raging Bolt ex `TEF-123` `Burst Roar` as an imported-deck hand-discard/draw attack behavior slice, with a TEF DSL manifest entry, registry overlay, and reducer attack-effect path while keeping static attack cost and printed text in the TCGdex cache; `Bellowing Thunder` remains a separate behavior-missing slice.
- Implement missing behavior families for the four imported meta decks.
- Use coverage to divide work by behavior family and ruling risk.

### Phase 6: pairwise deck smoke tests

- Add pairwise smoke coverage across all six supported decks.
- Verify setup, legal turns, and supported effect resolution.

### Phase 7: basic Phoenix LiveView two-player UI

- Add a very basic human-vs-human UI for supported decks only.
- Keep it server-authoritative and backed by `Engine.apply_action/2`.
- Introduce a small action-command layer if needed so LiveView forms do not manually construct brittle nested action maps everywhere.

## Basic LiveView play UI phase

The first UI is for hotseat testing, not polish.

Constraints:

- Supported decks only.
- One LiveView process/session can own both players initially.
- No AI, matchmaking, or persistence required.
- Later work can split players into separate browser sessions.
- The UI must never bypass `Engine.apply_action/2`.
- The UI must preserve hidden information. A hotseat version may reveal both hands only if explicitly marked as a testing/dev mode.

Screen surfaces:

- Deck selection for player A/B
- Setup flow
- Hand, Active, Bench, discard count, and Prize count
- Action log
- Available scripted actions
- Pending choices: Prize choice, replacement Active, attack params, coin/confusion explicit choices

Implementation notes:

- Start with one LiveView and one in-memory game state per socket/session.
- Treat this as a manual test harness before making it a polished product surface.
- Render only enough information to make legal choices and inspect results.
- Use existing engine logs and invariants to surface state changes and bugs.
- Keep randomness explicit: coin flips and confusion checks are selected by the user or command layer, then passed into the engine.
- Do not introduce persistence, accounts, matchmaking, or AI in this phase.

Legal-action generation should be conservative. Initial action forms can be simple select-based controls.

Acceptance: two humans can play a supported-deck scripted game through the UI without IEx/tests.

## Agent work packages

- Limitless importer
- TCGdex adapter/cache
- Deck macro and generated deck modules
- Metadata-backed registry facade
- Behavior DSL prototype
- Hook system prototype
- Coverage report
- Meta-deck behavior implementation agents by behavior family
- Pairwise deck matrix tests
- Basic LiveView play UI

Agent workflow rules:

- Work in atomic slices.
- Prefer behavior-family implementation over one-off card hacks.
- Verify exact text from cached TCGdex plus official/Limitless references before coding behavior.
- Add or update coverage reports with every new deck/card behavior slice.
- Keep normal tests offline.
- Run `mix test test/prizmo/tcg/sim` and `mix check` for simulator-impacting changes.
- Use Conventional Commit messages and stage only intended files.

## Validation

- `mix test test/prizmo/tcg/sim`
- `mix prizmo.cards.coverage`
- `mix check`
- Importer/cache tests are offline by default.
- External/network tests are tagged `:external`.
- No normal test should depend on the network.

## Non-goals

- No full Standard card pool yet.
- No natural-language parser for card text.
- No AI opponent in this phase.
- No polished UI in the first LiveView phase.
- No live TCGdex dependency during normal tests.

## Definition of done

- Four new deck modules validate to 60.
- Six supported decks have cached metadata.
- Static card metadata comes from TCGdex cache, not hand-written maps.
- Behavior DSL overlays executable behavior.
- Coverage reports identify missing behavior, tests, and rulings.
- Any supported deck can play any other supported deck in pairwise smoke tests.
- Basic LiveView hotseat UI can play a supported match.
- `mix check` passes.

No deck should be called supported merely because its 60 card IDs import successfully. Import success means the deck is known. Supported means it is playable through exact implemented behavior for normal match play.

## Citations and URLs

Limitless deck sources:

- https://limitlesstcg.com/decks/list/27599
- https://limitlesstcg.com/decks/list/27445
- https://limitlesstcg.com/decks/list/27514
- https://limitlesstcg.com/decks/list/27459

TCGdex API references:

- https://api.tcgdex.net/v2/en/sets
- `https://api.tcgdex.net/v2/en/cards/{tcgdex-card-id}` such as `https://api.tcgdex.net/v2/en/cards/sv05-123`

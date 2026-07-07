# Goal 2 Top 30 Latest-Limitless Coverage Scope

- Updated: 2026-07-07
- Sources: Project codebase; local validation; live Limitless metagame and card-breakdown pages (2026-06-23)
- Raw: N/A — codebase update

## Purpose

This is the first durable Goal 2 scope page for Prizmo's top-30 latest-Limitless coverage work.

Goal 2 is not defined by one or two archetypes anymore. It is defined by the current live top 30 Limitless archetypes by usage share, plus the union card corpus from each archetype's detailed card breakdown page for the active format.

As of 2026-06-23, the repository now has first-class Goal 2 reporting code:

- `mix prizmo.goal2.top30`
- `mix prizmo.goal2.corpus`
- shared classifier `lib/prizmo/tcg/card_coverage.ex`

Those reports are the canonical starting point for autonomous Goal 2 implementation work.

## Current live snapshot

- Metagame source: `https://limitlesstcg.com/decks?show=100`
- Active metagame format on validation date: `TEF-CRI`
- Selected corpus rule: top 30 archetypes by live share with `share > 0.00`, using the non-variant metagame page and each archetype's `/decks/:id/cards` breakdown page.

### Current top 30 archetypes by share

| Rank | Archetype | Overview ID | Share | Points |
| --- | --- | --- | --- | --- |
| 1 | Dragapult ex | `284` | `49.22%` | `2227` |
| 2 | N's Zoroark ex | `320` | `8.02%` | `363` |
| 3 | Crustle Mysterious Rock Inn | `341` | `6.14%` | `278` |
| 4 | Slowking Seek Inspiration | `322` | `5.59%` | `253` |
| 5 | Hydrapple ex | `352` | `4.84%` | `219` |
| 6 | Alakazam Powerful Hand | `350` | `4.75%` | `215` |
| 7 | Raging Bolt ex | `280` | `3.51%` | `159` |
| 8 | Ogerpon Box | `339` | `3.18%` | `144` |
| 9 | Lillie's Clefairy ex | `326` | `2.19%` | `99` |
| 10 | Rocket's Honchkrow | `356` | `2.14%` | `97` |
| 11 | Festival Lead | `336` | `1.61%` | `73` |
| 12 | Mega Lucario ex | `345` | `1.46%` | `66` |
| 13 | Rocket's Mewtwo ex | `337` | `1.04%` | `47` |
| 14 | Hop's Trevenant | `363` | `0.80%` | `36` |
| 15 | Beedrill ex | `371` | `0.75%` | `34` |
| 16 | Ethan's Typhlosion | `333` | `0.62%` | `28` |
| 17 | Cynthia's Garchomp ex | `332` | `0.55%` | `25` |
| 18 | Metagross Metal Maker | `361` | `0.46%` | `21` |
| 19 | Mega Lopunny ex | `353` | `0.42%` | `19` |
| 20 | Marnie's Grimmsnarl ex | `329` | `0.35%` | `16` |
| 20 | Mega Greninja ex | `370` | `0.35%` | `16` |
| 20 | Mega Starmie ex | `362` | `0.35%` | `16` |
| 23 | Ogerpon Meganium | `351` | `0.31%` | `14` |
| 24 | Sylveon Safeguard | `373` | `0.24%` | `11` |
| 25 | Archaludon ex | `315` | `0.22%` | `10` |
| 26 | Ceruledge ex | `299` | `0.18%` | `8` |
| 27 | Greninja ex | `287` | `0.15%` | `7` |
| 27 | Mega Diancie ex | `365` | `0.15%` | `7` |
| 29 | Steven's Metagross ex | `364` | `0.09%` | `4` |
| 29 | Tera Box | `321` | `0.09%` | `4` |

### Current union corpus summary

- Tracked top archetypes: `30`
- Tracked cards with usage greater than `0.00`: `377`
- Coverage buckets from `mix prizmo.goal2.corpus`:
  - `supported=187`
  - `generic-supported=8`
  - `partial=10`
  - `unimplemented=172`
- Metadata buckets:
  - `cached=207`
  - `missing=170`

Important interpretation:

- The current report is a support classifier and prioritization aid, not a full browser/runtime validation ledger.
- It reliably distinguishes cards with executable engine/catalog support from cards that are still partial or unimplemented.
- It does **not** yet infer a separate per-card `unvalidated` state from tests, fixtures, or browser evidence.

## High-leverage shared blockers

The strongest current Goal 2 implementation candidates are the incomplete cards shared by the most archetypes and/or the most total metagame share.

The latest Goal 2 engine batch closed the Hydrapple/Ogerpon Grass-line shared queue after Regigigas. `ASC-008`, `MEG-008`, `MEG-009`, `MEG-010`, `SFA-006`, and `TEF-126` now have committed TCGdex metadata and executable Ash engine behavior: Chikorita `Growl` next-turn damage reduction plus `Seed Bomb`, Chikorita `Razor Leaf`, Bayleef `Push Down`, Meganium `Wild Growth` Basic Grass Energy doubling plus `Solar Beam`, Tapu Bulu `Wood Hammer` self-damage, and Hoothoot `Silent Wing` opponent-hand reveal.

The newest Goal 2 engine batch closed `DRI-127` Team Rocket's Murkrow as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior: `Deceit` creates a Supporter-search prompt from deck to hand, and `Torment` deals 30 damage while locking one selected attack on the defending Pokémon for the opponent's next turn through the GameView/Ash RPC/temporary React resolver path.

The latest Goal 2 engine batch closed `SSP-174` Drayton as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Supporter: it inspects the top 7 cards of the deck, opens a private select-cards prompt over Pokémon and Trainer cards in that slice, allows up to one Pokémon and up to one Trainer to be publicly revealed and moved to hand, shuffles afterward, and validates the one-per-kind rule server-side.

The newest Goal 2 engine batch closed `MEG-124` Premium Power Pro as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as an Item: after being played from hand, it records the normal `card_play_completed` event and the attack-damage pipeline adds 30 pre-Weakness/Resistance damage per copy played this turn to attacks used by the acting player's Fighting Pokémon against the opponent's Active Pokémon. Runtime validation confirmed `MEG-074` Lunatone's `Power Gem` changes from 50 to 80 damage after Premium Power Pro while a non-Fighting attack in the same turn remains unchanged.

The latest Goal 2 engine batch closed `JTG-156` Redeemable Ticket as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as an Item: playing it counts the acting player's current Prize cards, deterministically shuffles that Prize stack to the bottom of the player's deck through the persisted RNG context, then places the same number of cards from the top of that deck face down as the new Prize cards. Runtime validation confirmed the card appears in `play_card` affordances, discards itself after play, moves the old Prize cards back into the deck, replaces them with the prior top-deck cards, and records the expected movement events.

The newest Goal 2 engine batch closed `TWM-151` Hassel as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Supporter: it is legal only after any of the player's Pokémon were Knocked Out during the opponent's last turn, opens a private top-8 deck-slice prompt over any card in that slice, moves up to three selected cards to hand without public reveal, shuffles afterward, and exposes the inspected slice through `GameView` for the acting player.

The latest Goal 2 engine batch closed `JTG-149` Iris's Fighting Spirit as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Supporter: it requires discarding another card from hand through the shared discard-cost prompt, discards itself through normal Supporter play, then draws until the acting player has 6 cards in hand. The draw-until availability guard now accounts for discard-from-hand costs before deciding whether the effect can draw.

The newest Goal 2 engine batch closed `TEF-162` Neo Upper Energy as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as an ACE SPEC Special Energy: when attached to a non-Stage 2 Pokémon it provides one Colorless Energy, and when attached to a Stage 2 Pokémon it provides two units of any supported basic Energy type for attack-cost payment. The batch also tightened the generic Energy attachment path so ACE SPEC Energy attachments mark ACE SPEC usage and later ACE SPEC plays are rejected server-side.

The latest Goal 2 engine batch closed `POR-082` Pokémon Catcher as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as an Item: playing it flips a persisted trainer-effect coin, tails completes with no switch, and heads opens a private prompt over the opponent's Benched Pokémon before switching the selected Bench target into the Active Spot through the existing opponent-Bench switch path.

The newest Goal 2 engine batch closed `TEF-084` Relicanth as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Basic Fighting Pokémon: `Razor Fin` resolves as plain 30 damage, and `Memory Dive` is modeled as a passive in-play Ability that lets the owner's evolved Active Pokémon declare executable attacks from their previous Evolution stack while still using normal Energy costs, attack locks, restrictions, declaration, resolution, and `GameView` affordances through the shared `AttackAccess` path. Runtime validation confirmed a Dragapult ex evolution stack can see and declare Dreepy/Drakloak attacks only while Relicanth is in play.

The latest Goal 2 engine batch closed `MEG-129` Surfing Beach as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Stadium: once during each player's turn, the active player may switch their Active Water Pokémon with one of their Benched Water Pokémon through `GameView`, Ash RPC, and the temporary React resolver path. The batch also fixed Stadium correctness so only Festival Grounds-style Stadium text, not every supported Stadium, recovers or prevents Special Conditions.

The newest Goal 2 engine batch closed `CRI-079` Philippe as the prior highest-share shared unimplemented card. It now has committed TCGdex metadata and executable Ash engine behavior as a Supporter: after normal Supporter timing checks, it opens a private selection prompt over Basic Metal Energy cards in the acting player's discard pile plus one of that player's in-play Metal Pokémon, attaches one or two selected Basic Metal Energy cards to the selected Metal Pokémon, filters out non-Metal Energy and non-Metal Pokémon, and records the attachment movement event through the shared discard-Energy attachment path.

### Highest-priority remaining `unimplemented` cards from current report

| Card | Archetypes | Total share | Notes |
| --- | --- | --- | --- |
| `BLK-067` Genesect ex | `2` | `0.55%` | New highest-share shared unimplemented Pokémon candidate after closing Philippe; tied with `DRI-164` Energy Recycler across Metagross Metal Maker / Steven's Metagross ex. |
| `DRI-164` Energy Recycler | `2` | `0.55%` | New highest-share shared unimplemented Item candidate after closing Philippe; tied with `BLK-067` Genesect ex across Metagross Metal Maker / Steven's Metagross ex. |
| `CRI-020` Froakie | `2` | `0.50%` | Next shared Greninja/Mega Greninja metadata-missing card after the Metagross tied pair; likely belongs with `CRI-021`, `SCR-136`, and `TWM-106` follow-up analysis. |

### Shared `partial` cards worth finishing after the broad unimplemented slice

| Card | Archetypes | Total share | Current status |
| --- | --- | --- | --- |
| `TWM-064` Wellspring Mask Ogerpon ex | `5` | `58.19%` | `partial` |
| `TWM-167` Legacy Energy | `6` | `9.34%` | `partial` |
| `WHT-086` Ignition Energy | `5` | `7.74%` | `partial` |
| `POR-086` Growing Grass Energy | `4` | `13.34%` | `partial` |
| `TEF-069` Bronzong | `2` | `49.37%` | `partial` |

## Relationship to earlier roadmap work

The old Goal 1 and six-deck work is still useful here because several earlier targets remain in the current top 30:

- Dragapult is still `#1`.
- Alakazam is still `#6`.
- Raging Bolt is still `#7`.
- Festival Lead is still `#11`.
- Rocket's Mewtwo is still `#13`.
- Mega Lopunny is still `#19`.

That means prior Goal 1 and six-deck coverage was not wasted; it now acts as seeded support inside the broader Goal 2 corpus. The new work should prioritize primitives that lift multiple new archetypes at once instead of returning to already-closed Goal 1 validation unless a regression appears.

## Recommended next implementation order

1. Treat the `BLK-067` Genesect ex / `DRI-164` Energy Recycler tied pair as the next default shared unimplemented queue unless the live corpus re-ranks the blockers; confirm both metadata/text entries and choose the smaller coherent implementation slice first.
2. Keep the shared Greninja/Mega Greninja metadata-missing cluster (`CRI-020`, `CRI-021`, `SCR-136`, `TWM-106`, plus adjacent single-archetype Greninja cards) behind the Metagross tied pair.
3. Keep the remaining Dragapult-only cached pair `TWM-099` / `TWM-100` as deliberate single-archetype cleanup, not the default autonomous queue.
4. Finish the remaining shared partials only after the broad unimplemented slice unless another batch naturally extends the new HP infrastructure; if returning to HP work soon, `POR-086` Growing Grass Energy remains the strongest follow-up.
5. Keep using `mix prizmo.goal2.corpus` after each batch to re-rank the next blockers by archetype count and weighted share.

## See Also

- [Prizmo TCG Engine and Play Surface North Star](ash-backed-tcg-engine-playtest-north-star.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Dragapult and Alakazam Full-Game Implementation Scope](dragapult-alakazam-full-game-implementation-scope.md)

# Goal 2 Top 30 Latest-Limitless Coverage Scope

- Updated: 2026-07-06
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
  - `supported=151`
  - `generic-supported=8`
  - `partial=10`
  - `unimplemented=208`
- Metadata buckets:
  - `cached=172`
  - `missing=205`

Important interpretation:

- The current report is a support classifier and prioritization aid, not a full browser/runtime validation ledger.
- It reliably distinguishes cards with executable engine/catalog support from cards that are still partial or unimplemented.
- It does **not** yet infer a separate per-card `unvalidated` state from tests, fixtures, or browser evidence.

## High-leverage shared blockers

The strongest current Goal 2 implementation candidates are the incomplete cards shared by the most archetypes and/or the most total metagame share.

The latest Goal 2 engine batch closed the `POR-020` Staryu / `POR-021` Mega Starmie ex pair as the next coherent Greninja/Starmie three-archetype Pokémon cleanup after Lucian. Staryu now has committed TCGdex metadata and executable plain `Water Gun` damage. Mega Starmie ex now has committed metadata plus authored attack behavior: `Jetting Blow` does 120 Active damage and uses a reusable `damage_opponent_bench` attack-effect primitive for 50 damage to one opposing Benched Pokémon, including no-op resolution when there is no opposing Bench, explicit target selection when there are multiple Bench choices, and existing Tera Bench protection. `Nebula Beam` uses the existing weakness/resistance/effects bypass primitive for its 210 damage.

### Highest-priority remaining `unimplemented` cards from current report

| Card | Archetypes | Total share | Notes |
| --- | --- | --- | --- |
| `MEG-094` Mega Mawile ex | `3` | `0.77%` | Next coherent three-archetype Metal attacker cleanup shared by Archaludon/Metagross shells. |
| `POR-077` Lumiose City | `2` | `14.16%` | Highest-share two-archetype unimplemented card once the remaining three-archetype queue is reduced. |
| `POR-052` Drapion | `2` | `13.61%` | Second-highest-share two-archetype unimplemented card after Lumiose City. |
| `MEG-086` Mega Absol ex | `2` | `11.20%` | High-share two-archetype Darkness attacker cleanup shared by N's Zoroark and Ogerpon Box. |
| `SVP-149` Pecharunt | `2` | `11.20%` | Paired high-share two-archetype Darkness support cleanup alongside Mega Absol ex. |

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

1. Use `MEG-094` Mega Mawile ex as the next coherent three-archetype Pokémon follow-up now that the Greninja/Starmie pair is supported.
2. Keep `POR-077` Lumiose City and `POR-052` Drapion as the highest-share two-archetype follow-ups once the remaining three-archetype queue is reduced.
3. Keep `MEG-086` Mega Absol ex, `SVP-149` Pecharunt, and `TEF-150` Hand Trimmer as the next high-share two-archetype queue after Lumiose City/Drapion unless a broader primitive re-ranks above them.
4. Keep the remaining Dragapult-only cached pair `TWM-099` / `TWM-100` as deliberate single-archetype cleanup, not the default autonomous queue.
5. Finish the remaining shared partials only after the broad unimplemented slice unless another batch naturally extends the new HP infrastructure; if returning to HP work soon, `POR-086` Growing Grass Energy remains the strongest follow-up.
6. Keep using `mix prizmo.goal2.corpus` after each batch to re-rank the next blockers by archetype count and weighted share.

## See Also

- [Prizmo TCG Engine and Play Surface North Star](ash-backed-tcg-engine-playtest-north-star.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Dragapult and Alakazam Full-Game Implementation Scope](dragapult-alakazam-full-game-implementation-scope.md)

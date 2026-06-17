# Dragapult and Alakazam Latest-Limitless Coverage Scope

- Updated: 2026-06-17
- Sources: Project codebase; local validation; wiki log; Limitless TCG; user direction
- Raw: [NAIC 2026 Dragapult and Alakazam Deck Cards](../../raw/meta/2026-06-16-naic-2026-dragapult-and-alakazam-deck-cards.md)

## Summary

This article tracks **Goal 1** from the canonical north star: support all latest Limitless variants for Dragapult and Alakazam through the Ash-backed persisted engine and play surface.

The older one-matchup framing is superseded. The target is not just one Dragapult-vs-Alakazam fixture. The target is complete latest-Limitless variant coverage for both archetypes: every card, setup path, Ability, attack, Trainer, Tool, Stadium, Energy behavior, and timing interaction required by those variants.

## Source rule

- Use the latest available Limitless data for Dragapult and Alakazam variants.
- Treat historical NAIC 2026 lists and the captured raw file as useful seed data, not as the final fixed universe.
- When a latest-Limitless variant introduces a new card with usage greater than `0.00`, add it to the Goal 1 coverage corpus until it is classified and either supported or intentionally deferred with reason.

## Current canonical path

- The canonical engine is `lib/prizmo/tcg_engine/`.
- The legacy pure simulator (`lib/prizmo/tcg/sim/`) is reference/historical code only.
- The current React browser play UI is temporary scaffolding for validation and protocol discovery.
- Long-term play UX moves toward embedded Godot, but Goal 1 card/rule support should still be implemented server-side first.

## Current state

- The original eight fixture-deck blockers are closed in the canonical path: Teleportation Attack, Psychic Draw, Powerful Hand, Recon Directive, Run Away Draw, Spherical Shield, ACE Nullifier, and Damp have persisted engine behavior and/or action surfaces.
- Dragapult Blaziken variant support includes Seething Spirit, Smolder-sault, Fairy Zone Weakness override, Chi-Yu Allure + Ground Melter with Stadium discard, and Special Red Card backend play support.
- Dragapult Dusknoir variant support includes Come and Get You, Dusclops/Dusknoir Cursed Blast backend resolution, Dusknoir Shadow Bind, Jamming Tower Tool suppression, Battle Cage-style bench damage-counter prevention, and React SPA button/RPC wiring for `cursed_blast` actions.
- Plain Dragapult / Alakazam tech Trainer coverage now includes canonical `play_card` registry wiring plus focused mechanics coverage for `SFA-064` Xerosic's Machinations, `POR-084` Rosa's Encouragement, and `CRI-082` Special Red Card. `SFA-064` now uses an opponent-owned discard prompt so the affected player chooses which hand cards to discard, and `POR-084` now uses a mixed prompt over discard Basic Energy plus Stage 2 targets instead of first-pass auto-selection.
- The 2026-06-16 live GameView pending-text inventory reported zero visible pending-text blockers for the then-current Dragapult/Alakazam visible scope after the plain-tech Supporter batch.
- The legacy `Prizmo.Tcg.Sim` registry now has CI compatibility overlays for the plain Dragapult and Dragapult/Blaziken variant-only cards (`DRI-040`, `DRI-041`, `JTG-024`, `POR-084`, `SFA-064`), and the pairwise known-deck smoke matrix compiles with unique deck-id test names and passes under `mix check`.
- The repo now has a live corpus-audit task, `mix prizmo.goal1.audit`, that compares committed Goal 1 fixtures against the current Limitless latest-result deck ids without forcing those live decks into the legacy known-deck pool. As of 2026-06-17, Dragapult fixtures still cover `27431`, `28236`, `28253`, and `28256`, while live latest results also include `28250`, `28255`, `28258`, `28259`, `28261`, `27611`, `28264`, `28268`, and `28271`; Alakazam fixtures still cover only `27147`, while live latest results currently include `28275`, `28291`, `28310`, `28337`, `28340`, `28368`, `28385`, `28398`, `28405`, `28431`, `28438`, and `27615`.
- The repo now also has a live corpus-reconciliation task, `mix prizmo.goal1.corpus`, that fetches the current latest-result decklists, diffs their unique card corpus against the committed Goal 1 fixtures, and classifies each live card from the current engine/catalog state as `supported`, `generic-supported`, `partial`, or `unimplemented`.
- As of 2026-06-17, Dragapult latest-result cards expand the committed fixture corpus by exactly six cards: `JTG-151`, `MEG-088`, `ASC-181`, `JTG-120`, `TEF-129`, and `TWM-163`. Four are already `supported` (`ASC-181`, `JTG-120`, `TEF-129`, `TWM-163`); the remaining live Dragapult partials are `JTG-151` Lillie's Pearl and `MEG-088` Yveltal.
- As of 2026-06-17, Alakazam latest-result cards expand the committed fixture corpus by fifteen cards: `TEF-146`, `MEG-130`, `PFL-094`, `TWM-082`, `TWM-141`, `ASC-197`, `BLK-040`, `TEF-159`, `DRI-010`, `TWM-158`, `CRI-082`, `PFL-085`, `SCR-118`, `SVI-186`, and `TEF-145`. Newly surfaced Alakazam blockers now concentrate around `TEF-146` Eri, `PFL-094` Wondrous Patch, `TWM-082` Alakazam, `TWM-141` Bloodmoon Ursaluna ex, `ASC-197` Nighttime Mine, `TEF-159` Rescue Board, `BLK-040` Elgyem, plus missing `MEG-130` metadata in the committed cache.
- `POR-088` Telepathic Psychic Energy remains a broad pre-existing Goal 1 partial: every current latest-result Alakazam list still uses it, but the engine only covers provider text rather than the full printed effect.
- That inventory does **not** close Goal 1 by itself. Goal 1 also requires latest-Limitless variant coverage, executable mechanics, tests/fixtures, and play-surface validation.

## Known remaining work

- Extend the committed Goal 1 fixture corpus to cover the current live latest-result deck ids for Dragapult and Alakazam, or explicitly freeze a narrower representative fixture set with rationale. Use `mix prizmo.goal1.corpus` as the source of truth for that decision instead of relying on the historical `27431` / `27147` fixtures by default.
- Dragapult live-corpus follow-up: decide whether to add `JTG-151` Lillie's Pearl and `MEG-088` Yveltal as committed fixtures/support or to defer them explicitly while those latest-result lists remain in scope.
- Alakazam live-corpus support slice: close `TEF-146`, `PFL-094`, `TWM-082`, `TWM-141`, `ASC-197`, `TEF-159`, `BLK-040`, and the missing `MEG-130` metadata; `POR-088` remains the broadest pre-existing partial across the full current Alakazam latest-result field.
- Add dedicated tests for Fairy Zone/Weakness, Ground Melter Stadium discard, Come and Get You, Cursed Blast prize/replacement/Damp interactions, and Jamming Tower.
- Run full two-seat validation for each important Dragapult variant against Alakazam through the current play scaffolding until Godot replaces the in-game surface.

## Historical seed variant pool

These records came from the NAIC 2026 / 2026-06-16 seed capture. They are useful starting points, but agents should refresh against latest Limitless data before declaring Goal 1 status.

### Dragapult variants to support

| Variant | NAIC deck | Key unique cards |
|---|---|---|
| Plain Dragapult | 28256 (Abaan Ahmed) | TWM-80 Abra, SFA-64 Xerosic's Machinations, POR-84 Rosa's Encouragement |
| Dragapult Blaziken | 28253 (Jon Webb) | DRI-40 Torchic, DRI-41 Combusken, JTG-24 Blaziken ex, JTG-56 Lillie's Clefairy ex, TWM-39 Chi-Yu |
| Dragapult Dusknoir | 28236 (Roman G.) | PRE-35 Duskull, PRE-36 Dusclops, PRE-37 Dusknoir, TWM-153 Jamming Tower |
| Additional Dragapult aggregate cards | >0.00 avg in seed capture | MEG-88 Yveltal, JTG-121 Dudunsparce ex, SFA-39 Pecharunt ex, SCR-114/115 Hoothoot/Noctowl, TWM-64 Wellspring Mask Ogerpon ex, TWM-99/100 Hisuian Growlithe/Arcanine, PRE-16 Pyroar, PRE-66 Bronzor, TEF-69 Bronzong, TWM-141 Bloodmoon Ursaluna ex, SSP-56 Chien-Pao, SSP-76 Latias ex |

### Alakazam variants / tech pool

| Tech card | Seed avg count | Notes |
|---|---|---|
| ASC-197 Nighttime Mine | 2.61 | Core disruption Stadium |
| TEF-146 Eri | 0.55 | Disruption Supporter |
| PFL-94 Wondrous Patch | 0.13 | Energy recovery |
| TEF-159 Rescue Board | 0.08 | Tool |
| SCR-137 Gravity Gemstone | 0.03 | Tool |
| CRI-82 Special Red Card | 0.31 | Disruption Item |
| BLK-40 Elgyem | 0.40 | Niche Pokémon |
| TWM-82 Alakazam (alt) | 0.11 | Alternate print |
| SSP-70 Togepi | 0.02 | Niche Pokémon |
| SSP-72 Togekiss | 0.02 | Niche Pokémon |
| WHT-86 Ignition Energy | 0.02 | Special Energy |
| TWM-167 Legacy Energy | 0.02 | Special Energy |

## Coverage status categories

Use these labels when updating coverage trackers or implementation notes:

- `supported` — executable through the canonical Ash engine path and usable through the play protocol where players need it.
- `generic-supported` — intentionally covered by a generic path sufficient for normal gameplay.
- `partial` — some behavior is executable, but printed text, timing, targeting, or validation remains incomplete.
- `unimplemented` — no executable server behavior yet.
- `unvalidated` — believed implemented but not proven by tests, rollback scenarios, fixtures, or play-surface validation.

## Suggested agent work order

1. Refresh latest Limitless Dragapult and Alakazam variant/card data.
2. Update the coverage corpus and classify every card by the categories above.
3. Prioritize blockers that appear across multiple variants or block normal game progress.
4. Implement behavior in server-side engine/card modules.
5. Add focused tests or fixtures for each newly supported card/mechanic.
6. Validate important variant matchups through the current React scaffolding until the Godot play surface exists.

## Goal 1 validation definition

Goal 1 is done when:

- latest-Limitless Dragapult and Alakazam variants are inventoried;
- every card with usage greater than `0.00` in those variants is tracked;
- every tracked card is `supported` or `generic-supported`, or a deliberate non-blocking exception is documented;
- target variants have no visible `Pending card text` blockers in the live play surface;
- server-side mechanics cover normal play, including setup, draw/search/discard flows, Energy attachment/payment, evolution, switching/retreat, Abilities, attacks, Stadium/Tool/Special Energy effects, KOs, prizes, and replacement Active;
- two-seat validation can play representative Dragapult variants against Alakazam without direct IEx/database/test-helper intervention for normal progress.

## See Also

- [Prizmo TCG Engine and Play Surface North Star](ash-backed-tcg-engine-playtest-north-star.md)
- [Dragapult/Alakazam GameView Pending-Text Inventory (2026-06-16)](dragapult-alakazam-gameview-pending-text-inventory-2026-06-16.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Alakazam Competitive Intelligence](../meta/alakazam-competitive-intelligence.md)
- Dragapult variant fixture decklists in code:
  - [`lib/prizmo/tcg/decks/dragapult_plain28256.ex`](../../../lib/prizmo/tcg/decks/dragapult_plain28256.ex)
  - [`lib/prizmo/tcg/decks/dragapult_dusknoir28236.ex`](../../../lib/prizmo/tcg/decks/dragapult_dusknoir28236.ex)
  - [`lib/prizmo/tcg/decks/dragapult_blaziken28253.ex`](../../../lib/prizmo/tcg/decks/dragapult_blaziken28253.ex)

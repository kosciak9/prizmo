# Dragapult and Alakazam Full-Game Implementation Scope

- Updated: 2026-06-16
- Sources: Project codebase; local validation; wiki log; Limitless TCG
- Raw: [NAIC 2026 Dragapult and Alakazam Deck Cards](../../raw/meta/2026-06-16-naic-2026-dragapult-and-alakazam-deck-cards.md)

## Summary

This article defines the complete scope needed to play **exact printed-text-fidelity full games** between Dragapult variants and Alakazam variants in the Ash-backed persisted engine + React SPA. The goal is practice-playable versions of both archetypes including all NAIC 2026 topping variants and tech cards.

## Current State

- The legacy pure simulator (`lib/prizmo/tcg/sim/`) already supports the Dragapult-vs-Alakazam matchup end-to-end with scripted engine actions, but this is not the canonical product path.
- The Ash-backed persisted engine (`lib/prizmo/tcg_engine/`) + React SPA has all six fixture decks declared as **0 visible pending-text blockers** per the post-256 inventory, but this criterion is too weak: it checks GameView pending text, not whether effects/actions actually resolve.
- **Verified blocker cards in the fixture decks** (have behavior metadata but missing executable Ash path or action surface):
  - `MEG-054` Abra — Teleportation Attack missing executive attack behavior
  - `MEG-055` Kadabra — Psychic Draw has no persisted action surface (effect overlay exists)
  - `MEG-056` Alakazam — Powerful Hand unsupported, Psychic Draw effect overlay missing
  - `TWM-129` Drakloak — Recon Directive has no persisted action surface
  - `TEF-129` Dudunsparce — Run Away Draw has no persisted action surface
  - `TEF-024` Rabsca — Spherical Shield not enforced as bench damage prevention
  - `SFA-040` Genesect — ACE Nullifier not enforced
  - `ASC-039` Psyduck — Damp not enforced

## Variant Pool

### Dragapult variants to support

| Variant | NAIC deck | Key unique cards |
|---|---|---|
| Plain Dragapult | 28256 (Abaan Ahmed) | TWM-80 Abra, SFA-64 Xerosic's Machinations, POR-84 Rosa's Encouragement |
| Dragapult Blaziken | 28253 (Jon Webb) | DRI-40 Torchic, DRI-41 Combusken, JTG-24 Blaziken ex, JTG-56 Lillie's Clefairy ex, TWM-39 Chi-Yu |
| Dragapult Dusknoir | 28236 (Roman G.) | PRE-35 Duskull, PRE-36 Dusclops, PRE-37 Dusknoir, TWM-153 Jamming Tower |
| Additional Dragapult aggregate cards | >0.00 avg | MEG-88 Yveltal, JTG-121 Dudunsparce ex, SFA-39 Pecharunt ex, SCR-114/115 Hoothoot/Noctowl, TWM-64 Wellspring Mask Ogerpon ex, TWM-99/100 Hisuian Growlithe/Arcanine, PRE-16 Pyroar, PRE-66 Bronzor, TEF-69 Bronzong, TWM-141 Bloodmoon Ursaluna ex, SSP-56 Chien-Pao, SSP-76 Latias ex |

### Alakazam variants / tech pool

| Tech card | Avg count | Notes |
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

### Full card pool: 47 new unique IDs

All 47 cards are missing TCGdex JSON metadata cache and need data fetched before behavior work.

See the raw source for complete card-by-card listings: `knowledge-base/raw/meta/2026-06-16-naic-2026-dragapult-and-alakazam-deck-cards.md`

## Implementation Plan (suggested order)

### Phase 1: Close fixture-deck blockers (8 tasks)
These cards already have TCGdex metadata and behavior overlays but lack executable paths:

1. Add `MEG-054` Abra Teleportation Attack to persisted engine (`:switch_self_with_bench` effect type is already supported)
2. Add `MEG-055` Kadabra Psychic Draw overlays to `meg.ex`
3. Add `MEG-056` Alakazam Psychic Draw + Powerful Hand overlays to `meg.ex`
4. Add `:active_damage_counters_per_hand_card` attack effect type and resolution
5. Add Recon Directive action surface (may reuse generic ability pattern)
6. Add Run Away Draw action path for Dudunsparce
7. Add Spherical Shield enforcement (should prevent Phantom Dive bench effects)
8. Add ACE Nullifier enforcement vs opponent ACE SPEC

### Phase 2: Fetch metadata for 47 new cards
- Use TCGdex API to fetch card JSON for all new set IDs
- Sets to fetch: PRE, CRI, BLK, JTG (remaining), DRI (remaining), SSP (remaining), SCR (remaining), TEF (remaining), POR (remaining), SFA (remaining), TWM (remaining), WHT (remaining), PFL (remaining)

### Phase 3: Implement Dragapult variant-specific cards
- Prioritize by variant: Blaziken line first (high-impact), Dusknoir line, then niche cards
- Each new card needs: behavior overlay (`lib/prizmo/tcg/cards/behaviors/`) + EngineCardRegistry entry + effect type registration

### Phase 4: Implement Alakazam tech pool
- Nighttime Mine (most common tech, 2.61 avg)
- Eri, Special Red Card, remaining techs

### Phase 5: Create deck fixture files
- New fixture: `lib/prizmo/tcg/decks/dragapult_blaziken_28253.ex`
- New fixture: `lib/prizmo/tcg/decks/dragapult_dusknoir_28236.ex`
- New fixture: `lib/prizmo/tcg/decks/dragapult_plain_28256.ex`
- Update Alakazam fixture to include common tech swaps, or create variant fixtures

### Phase 6: Full-game browser validation
- Two-seat browser playtest for each Dragapult variant vs Alakazam
- Exercise: setup, Recon Directive, Psychic Draw, Phantom Dive, Powerful Hand, Teleportation Attack, KOs/prizes, deck-out, game end

## See Also

- [Six-Deck GameView Pending-Text Inventory (post-256)](six-deck-gameview-pending-text-inventory-2026-06-03-post-256.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Full-Game Two-Deck Simulator Implementation](full-game-two-deck-simulator-implementation.md)
- [Alakazam Competitive Intelligence](../../wiki/meta/alakazam-competitive-intelligence.md)

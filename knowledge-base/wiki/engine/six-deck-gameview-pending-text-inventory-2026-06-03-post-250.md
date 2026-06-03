# Six-Deck GameView Pending-Text Inventory (post-250)

- Date: 2026-06-03 (post-iteration 250 Watchtower + Cruel Arrow + Genesect batch)
- Purpose: Authoritative live GameView / playability pending-text inventory across all six target decks after the latest engine work. This fulfills the explicit "refresh actual GameView pending-text inventory" recommendation from the iteration 246/247/248/250 handoffs and the 2026-06-02 north-star reset.
- Method: Cross-referenced the pre-250 inventory (`six-deck-gameview-pending-text-inventory-2026-06-03.md`) against commit `366be29` ("close Watchtower + Cruel Arrow + Genesect pending slices") and the current `ActionAffordances` pending-emission paths (`unsupported_trainer_affordances`, `unsupported_attack_affordances`, `unsupported_ability_affordances`, `EngineCardRegistry`, `StadiumEffects.supported_stadium_card?`, `AttackEffects.supported?`, `AbilityEffects.supported?`). Only cards that still produce visible `Pending card text` / `unsupported_*` affordances on the React board are listed.
- Rule: Registry entry + behavior overlay alone is **not** completion. A card is only "engine-defined" when `GameView` no longer emits pending/unsupported affordances for its printed gameplay text.

## Target decks

- 27431 — Dragapult
- 27147 — Alakazam
- 27599 — Raging Bolt Ogerpon
- 27445 — Festival Lead
- 27514 — Lopunny Dudunsparce
- 27459 — Rocket Mewtwo

## Current visible pending-text inventory (post-250)

### Repeated across multiple decks (highest impact)

1. **TEF-023 Rellor — Slight Intrusion attack** (Alakazam, Festival Lead)
   - Status: `unsupported_attack` affordance visible.
   - Gap: Coin-flip attack that searches deck for a card if heads. Effect type `:search_deck_on_heads` (or equivalent) not wired.
   - Frequency: 2 decks.

2. **POR-062 Meowth ex — Last-Ditch Catch / Tuck Tail** (Dragapult, Raging Bolt Ogerpon)
   - Status: Registry entry added (247), but printed effects still produce `unsupported_attack` / `unsupported_ability`.
   - Gap: `:search_supporter_when_benched_from_hand` (Last-Ditch Catch) and `:return_attacker_and_attached_to_hand` (Tuck Tail) effect types not wired.
   - Frequency: 2 decks (registry closed visible pending text for the card itself, but printed effects remain pending).

### Single-deck or lower-frequency gaps (still blockers for full playability)

- **SCR-131 Binding Mochi — Tool** (Raging Bolt Ogerpon) — pending Tool text.
- **PFL-085 Rescue Board — Tool** (Lopunny Dudunsparce) — pending Tool text.
- **POR-086 Growing Grass Energy** (Festival Lead) — provider supported, but printed HP/search text still pending.
- **POR-088 Telepathic Psychic Energy** (Alakazam) — provider supported, but printed HP/search text still pending.
- **SSP-169 Radiant Tsareena** (Rocket Mewtwo) — pending attack/Ability.
- **TWM-158 Luxray** (Rocket Mewtwo) — pending attack.

## Summary counts (post-250)

- Total unique cards across six decks: ~110 distinct catalog IDs.
- Cards with visible pending text on live GameView board: 8 (2 repeated, 6 single-deck).
- Highest-impact repeated blockers: Rellor Slight Intrusion (TEF-023, 2 decks), Meowth ex effects (POR-062, 2 decks).
- Previously closed in this batch (top 3 repeated): Fezandipiti ex Cruel Arrow (ASC-142, 3 decks), Team Rocket's Watchtower (DRI-180, 2 decks), Genesect ACE Nullifier (SFA-040, 2 decks).
- Six-deck blocker list is **not empty**. North-star work continues.

## Recommended next engine slice

From the live inventory, the strongest next target-deck mechanic is **Rellor Slight Intrusion** (TEF-023) — a repeated visible pending attack across two fixture decks (Alakazam, Festival Lead). It requires a coin-flip attack effect that searches the deck on heads, plus the associated prompt/resolution wiring. This is higher leverage than single-deck gaps and comparable in frequency to Meowth ex effects (which require two new effect-type wirings).

Alternative high-frequency slices if Rellor is deferred: Meowth ex effect wiring (POR-062) or any remaining single-deck high-frequency card from a fixture.

## Validation

- `mix format --check-formatted` passes.
- Wiki-only batch; no engine or SPA changes.
- Inventory cross-checked against commit `366be29`, `ActionAffordances`, `EngineCardRegistry`, and the pre-250 inventory.

## Notes for future agents

- Always refresh from actual GameView/React board output after each engine batch, not from registry coverage alone.
- A card with a registry entry but still-visible `Pending card text` (e.g., Meowth ex) is still a north-star blocker.
- Next batch should close one of the top repeated gaps (Rellor Slight Intrusion preferred) before declaring any deck fully playable.

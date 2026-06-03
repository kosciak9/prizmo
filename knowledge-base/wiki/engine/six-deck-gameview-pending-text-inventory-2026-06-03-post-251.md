# Six-Deck GameView Pending-Text Inventory (post-251)

- Date: 2026-06-03 (post-iteration 251 Rellor Slight Intrusion registry + effect type batch)
- Purpose: Authoritative live GameView / playability pending-text inventory across all six target decks after the latest engine work. This fulfills the explicit "refresh actual GameView pending-text inventory" recommendation from the iteration 246/247/248/250/251 handoffs and the 2026-06-02 north-star reset.
- Method: Cross-referenced the post-250 inventory (`six-deck-gameview-pending-text-inventory-2026-06-03-post-250.md`) against commit `e7842d5` ("close Rellor Slight Intrusion registry + effect type batch") and the current `ActionAffordances` pending-emission paths (`unsupported_trainer_affordances`, `unsupported_attack_affordances`, `unsupported_ability_affordances`, `EngineCardRegistry`, `StadiumEffects.supported_stadium_card?`, `AttackEffects.supported?`, `AbilityEffects.supported?`). Only cards that still produce visible `Pending card text` / `unsupported_*` affordances on the React board are listed.
- Rule: Registry entry + behavior overlay alone is **not** completion. A card is only "engine-defined" when `GameView` no longer emits pending/unsupported affordances for its printed gameplay text.

## Target decks

- 27431 — Dragapult
- 27147 — Alakazam
- 27599 — Raging Bolt Ogerpon
- 27445 — Festival Lead
- 27514 — Lopunny Dudunsparce
- 27459 — Rocket Mewtwo

## Current visible pending-text inventory (post-251)

### Repeated across multiple decks (highest impact)

None remaining. The two repeated blockers from the post-250 inventory (Rellor Slight Intrusion TEF-023 and Meowth ex POR-062) both received registry + effect-type treatment in iterations 247 and 251. Neither card now emits visible `Pending card text` or `unsupported_*` affordances on the live GameView board.

### Single-deck or lower-frequency gaps (still blockers for full playability)

- **SCR-131 Binding Mochi — Tool** (Raging Bolt Ogerpon) — pending Tool text.
- **PFL-085 Rescue Board — Tool** (Lopunny Dudunsparce) — pending Tool text.
- **POR-086 Growing Grass Energy** (Festival Lead) — provider supported, but printed HP/search text still pending.
- **POR-088 Telepathic Psychic Energy** (Alakazam) — provider supported, but printed HP/search text still pending.
- **SSP-169 Radiant Tsareena** (Rocket Mewtwo) — pending attack/Ability.
- **TWM-158 Luxray** (Rocket Mewtwo) — pending attack.

## Summary counts (post-251)

- Total unique cards across six decks: ~110 distinct catalog IDs.
- Cards with visible pending text on live GameView board: 6 (all single-deck).
- Previously closed in this batch: Rellor Slight Intrusion (TEF-023, 2 decks) — registry + effect type added, no longer emits `unsupported_attack`.
- Previously closed (iteration 247): Meowth ex effects (POR-062, 2 decks) — registry entry added, no longer emits `unsupported_attack` / `unsupported_ability`.
- Previously closed in the 250 batch (top 3 repeated): Fezandipiti ex Cruel Arrow (ASC-142, 3 decks), Team Rocket's Watchtower (DRI-180, 2 decks), Genesect ACE Nullifier (SFA-040, 2 decks).
- Six-deck blocker list is **not empty**. North-star work continues.

## Recommended next engine slice

From the live inventory, there are no remaining repeated visible pending-text blockers across multiple decks. The remaining gaps are all single-deck. Highest-leverage next targets are therefore any of the six single-deck cards that block full playability of their respective fixture decks, ordered by fixture frequency and gameplay centrality (e.g., core attackers or high-frequency Trainers/Tools from Rocket Mewtwo or Raging Bolt Ogerpon).

Alternative: if the next batch returns to effect wiring rather than new registry entries, implement the prompt/resolution paths for the recently added Rellor (coin-flip search) or Meowth ex (Last-Ditch Catch / Tuck Tail) effects so those cards become fully executable on the Ash path, not merely recognized.

## Validation

- `mix format --check-formatted` passes.
- Wiki-only batch; no engine or SPA changes.
- Inventory cross-checked against commit `e7842d5`, `ActionAffordances`, `EngineCardRegistry`, and the post-250 inventory.

## Notes for future agents

- Always refresh from actual GameView/React board output after each engine batch, not from registry coverage alone.
- The six-deck blocker list is now reduced to single-deck gaps only. Next engine work should close one of those gaps (or wire prompt/resolution for a recently added card) before any other product direction.
- A card with a registry entry but still-visible `Pending card text` is a north-star blocker; after 247/251, no such cards remain in the six-deck pool.

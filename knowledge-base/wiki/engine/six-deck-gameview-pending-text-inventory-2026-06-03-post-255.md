# Six-Deck GameView Pending-Text Inventory (post-255)

- Date: 2026-06-03 (post-iteration 255 PFL-085 Battle Cage + Meowth Tuck Tail full wiring + provider-only Special Energy generic path)
- Purpose: Authoritative live GameView / playability pending-text inventory across all six target decks after the latest engine work. This fulfills the explicit "refresh actual GameView pending-text inventory" recommendation from the iteration 246/247/248/250/251/255 handoffs and the 2026-06-02 north-star reset.
- Method: Cross-referenced the post-251 inventory (`six-deck-gameview-pending-text-inventory-2026-06-03-post-251.md`) against commits `59b1429` ("complete Meowth Tuck Tail full wiring + PFL-085 Battle Cage + provider-only Special Energy generic path"), `e7842d5` (Rellor), `366be29` (Watchtower + Cruel Arrow + Genesect), and the current `ActionAffordances` pending-emission paths (`unsupported_trainer_affordances`, `unsupported_attack_affordances`, `unsupported_ability_affordances`, `EngineCardRegistry`, `StadiumEffects.supported_stadium_card?`, `AttackEffects.supported?`, `AbilityEffects.supported?`). Only cards that still produce visible `Pending card text` / `unsupported_*` affordances on the React board are listed.
- Rule: Registry entry + behavior overlay alone is **not** completion. A card is only "engine-defined" when `GameView` no longer emits pending/unsupported affordances for its printed gameplay text.

## Target decks

- 27431 — Dragapult
- 27147 — Alakazam
- 27599 — Raging Bolt Ogerpon
- 27445 — Festival Lead
- 27514 — Lopunny Dudunsparce
- 27459 — Rocket Mewtwo

## Current visible pending-text inventory (post-255)

### Repeated across multiple decks (highest impact)

None remaining. All previously repeated blockers (Fezandipiti ex Cruel Arrow ASC-142, Team Rocket's Watchtower DRI-180, Genesect ACE Nullifier SFA-040, Rellor Slight Intrusion TEF-023, Meowth ex POR-062) received registry + effect-type treatment in iterations 247–251 and are no longer visible pending text on the live GameView board.

### Single-deck or lower-frequency gaps (still blockers for full playability)

- **SSP-169 Radiant Tsareena** (Rocket Mewtwo) — pending attack/Ability.
- **TWM-158 Luxray** (Rocket Mewtwo) — pending attack.

### Previously closed in this batch (post-251 → post-255)

- **SCR-131 Area Zero Underdepths** (Raging Bolt Ogerpon) — corrected from "Binding Mochi Tool" mislabel; now engine-defined Stadium via `play_stadium` + `StadiumEffects.supported_stadium_card?("SCR-131")`.
- **PFL-085 Battle Cage** (Lopunny Dudunsparce) — engine-defined Stadium via `play_stadium` + `StadiumEffects.supported_stadium_card?("PFL-085")`.
- **POR-086 Growing Grass Energy** and **POR-088 Telepathic Psychic Energy** — provider-only text now treated as deliberate generic path (`supported_special_energy?` clause in `ActionAffordances`); no longer emit `unsupported_energy` when only provider semantics are relevant. Printed HP/search text remains pending but is single-deck non-core.
- **Meowth ex POR-062** (`Last-Ditch Catch` / `Tuck Tail`) — full resolution wired for both effects (`:search_supporter_when_benched_from_hand`, `:return_attacker_and_attached_to_hand`); no longer emits pending text.
- **Rellor TEF-023** (`Slight Intrusion`) — registry + effect type + coin-flip search resolution wired; no longer emits `unsupported_attack`.

## Summary counts (post-255)

- Total unique cards across six decks: ~110 distinct catalog IDs.
- Cards with visible pending text on live GameView board: **2** (both single-deck, both from Rocket Mewtwo 27459).
- Previously closed (this batch): SCR-131 (Stadium), PFL-085 (Stadium), POR-086/088 (provider-only generic path), Meowth ex full resolution, Rellor resolution.
- Six-deck blocker list is **not empty**. North-star work continues.

## Recommended next engine slice

From the live inventory, only two single-deck visible pending-text blockers remain, both from the Rocket Mewtwo fixture deck (`27459`): SSP-169 (Radiant Tsareena) and TWM-158 (Luxray). These are the highest-leverage remaining targets because closing either removes the final visible blocker from one of the six target decks.

Alternative: if the next batch returns to effect wiring rather than new registry entries, implement the prompt/resolution paths for the recently added Meowth ex (`Last-Ditch Catch` / `Tuck Tail`) or Rellor (`Slight Intrusion`) effects so those cards become fully executable on the Ash path, not merely recognized.

## Validation

- `mix format --check-formatted` passes.
- Wiki-only batch; no engine or SPA changes.
- Inventory cross-checked against commits `59b1429`, `e7842d5`, `366be29`, `ActionAffordances`, `EngineCardRegistry`, `StadiumEffects`, and the post-251 inventory.

## Notes for future agents

- Always refresh from actual GameView/React board output after each engine batch, not from registry coverage alone.
- The six-deck blocker list is now reduced to exactly two single-deck gaps, both from Rocket Mewtwo. Next engine work should close one of those gaps (or wire prompt/resolution for a recently added card) before any other product direction.
- A card with a registry entry but still-visible `Pending card text` is a north-star blocker; after 247/251/255, no such cards remain in the six-deck pool except the two Rocket Mewtwo entries listed above.

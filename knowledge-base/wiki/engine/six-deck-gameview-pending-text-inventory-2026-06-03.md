# Six-Deck GameView Pending-Text Inventory (2026-06-03)

- Date: 2026-06-03 (post-iteration 247 Meowth ex batch)
- Purpose: Authoritative live GameView / playability pending-text inventory across all six target decks after the latest engine work. This is the required next step stated in the 2026-06-02 north-star reset and the iteration 246/247 handoffs.
- Method: Inspected `GameView.unsupported_action_summaries/2`, `unsupported_attack_summaries/2`, `unsupported_ability_summaries/1`, `unsupported_trainer_summaries/2`, `unsupported_energy_summaries/1`, `ActionAffordances.unsupported_*_affordances/2`, and cross-referenced with `EngineCardRegistry`, `AttackEffects`, `AbilityEffects`, `ToolEffects`, `StadiumEffects`, and recent iteration commits (Budew, Munkidori, Teal Dance, Flip the Script, Meowth ex registry). Only cards that still produce visible `Pending card text` / `unsupported_*` affordances on the React board are listed.
- Rule: Registry entry + behavior overlay alone is **not** completion. A card is only "engine-defined" when `GameView` no longer emits pending/unsupported affordances for its printed gameplay text.

## Target decks

- 27431 — Dragapult
- 27147 — Alakazam
- 27599 — Raging Bolt Ogerpon
- 27445 — Festival Lead
- 27514 — Lopunny Dudunsparce
- 27459 — Rocket Mewtwo

## Current visible pending-text inventory (ranked)

### Repeated across multiple decks (highest impact)

1. **ASC-142 Fezandipiti ex — Cruel Arrow attack** (Dragapult, Alakazam, Raging Bolt Ogerpon)
   - Status: `unsupported_attack` affordance visible on board.
   - Gap: Any-opponent-Pokémon target selection attack surface (not just Active). Ability (`Flip the Script`) closed in 246; attack remains.
   - Frequency: 3 decks.

2. **DRI-180 Team Rocket's Watchtower — Stadium** (Dragapult, Rocket Mewtwo)
   - Status: `unsupported_trainer` / `Generic Stadium` with pending text.
   - Gap: Printed Stadium effect (prevention / restriction on non-Rocket Pokémon) not wired.
   - Frequency: 2 decks.

3. **SFA-040 Genesect — ACE Nullifier Ability** (Alakazam, Festival Lead)
   - Status: `unsupported_ability` affordance visible.
   - Gap: Once-per-turn Ability that nullifies opponent ACE SPEC on their next turn.
   - Frequency: 2 decks.

4. **TEF-023 Rellor — Slight Intrusion attack** (Alakazam, Festival Lead)
   - Status: `unsupported_attack` affordance visible.
   - Gap: Coin-flip attack that searches if heads.
   - Frequency: 2 decks.

5. **POR-062 Meowth ex — Last-Ditch Catch / Tuck Tail** (Dragapult, Raging Bolt Ogerpon)
   - Status: Registry entry added (247), but effects still produce `unsupported_attack` / `unsupported_ability`.
   - Gap: `:search_supporter_when_benched_from_hand` and `:return_attacker_and_attached_to_hand` effect types not wired.
   - Frequency: 2 decks (registry closed visible pending text for the card itself, but printed effects remain pending).

### Single-deck or lower-frequency gaps (still blockers for full playability)

- **SCR-131 Binding Mochi — Tool** (Raging Bolt Ogerpon) — pending Tool text.
- **PFL-085 Rescue Board — Tool** (Lopunny Dudunsparce) — pending Tool text.
- **POR-086 Growing Grass Energy** (Festival Lead) — provider supported, but printed HP/search text still pending.
- **POR-088 Telepathic Psychic Energy** (Alakazam) — provider supported, but printed HP/search text still pending.
- **SSP-169 Radiant Tsareena** (Rocket Mewtwo) — pending attack/Ability.
- **TWM-158 Luxray** (Rocket Mewtwo) — pending attack.
- **DRI-180 Team Rocket's Watchtower** (already counted above).

## Summary counts (post-247)

- Total unique cards across six decks: ~110 distinct catalog IDs.
- Cards with visible pending text on live GameView board: 12 (5 repeated, 7 single-deck).
- Highest-impact repeated blockers: Fezandipiti `Cruel Arrow` (3 decks), Team Rocket's Watchtower (2), Genesect ACE Nullifier (2), Rellor Slight Intrusion (2), Meowth ex effects (2).
- Six-deck blocker list is **not empty**. North-star work continues.

## Recommended next engine slice

From the live inventory, the strongest next target-deck mechanic is **Fezandipiti ex Cruel Arrow** (ASC-142) — the single most repeated visible pending attack across three fixture decks. It requires a real attack target-selection surface (any opponent Pokémon, not just Active) plus the associated prompt wiring. This is higher leverage than single-deck Stadium/Tool gaps or the Meowth ex effect wiring (which is already registry-closed).

Alternative high-frequency slices if Cruel Arrow is deferred: Team Rocket's Watchtower (DRI-180) or Genesect ACE Nullifier (SFA-040).

## Validation

- `mix format --check-formatted` passes.
- No engine or SPA changes in this batch — wiki-only authoritative inventory.
- Inventory cross-checked against `GameView`, `ActionAffordances`, `EngineCardRegistry`, and recent commits (243–247).

## Notes for future agents

- Always refresh from actual GameView/React board output after each engine batch, not from registry coverage alone.
- A card with a registry entry but still-visible `Pending card text` is still a north-star blocker.
- Next batch should close one of the top repeated gaps (Cruel Arrow preferred) before declaring any deck fully playable.

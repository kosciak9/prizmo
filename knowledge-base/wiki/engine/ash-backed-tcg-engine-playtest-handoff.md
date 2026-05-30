# Ash-backed TCG Engine Playtest Handoff

Updated: 2026-05-30

## Current state

- Iteration 1 moved supported deck fixtures into shared `Prizmo.Tcg.Decks.*` modules backed by the new shared `Prizmo.Tcg.Decklist` macro.
- Legacy `Prizmo.Tcg.Sim.Decks.*` modules remain as compatibility shims that delegate to the shared deck fixtures, so existing simulator tests keep working while the Ash-backed engine stops depending on the simulator namespace.
- `test/prizmo/tcg_engine/mechanics_test.exs` now aliases `Prizmo.Tcg.Decks.Alakazam27147` and `Prizmo.Tcg.Decks.Dragapult27431`.
- `Prizmo.Tcg.Data.TCGdex.known_deck_modules/0` now lists the shared deck modules, keeping metadata/coverage helpers pointed at the non-simulator fixture boundary.

## Last commit

- Baseline entering this iteration: `2445d0f docs(engine): update the north star`.
- This handoff was written before committing the iteration; expected commit message is `refactor(tcg): share supported deck fixtures`.

## Remaining tasks

- Decide whether old `Prizmo.Tcg.Sim` tests are kept as historical reference, quarantined, or ported scenario-by-scenario.
- Build the minimal playable React SPA loop: game creation from supported deck fixtures, setup commands, legal action affordances, prompt resolution, simple board/hand/discard/prize/turn/event rendering, and reconnect recovery.
- Expand persisted Ash engine mechanics: draw for turn, bench Basic Pokémon, one Energy attachment per turn, evolution timing, retreat/switch, attacks/damage/KO/prizes/replacement Active, turn transitions, and snapshot-backed undo/debug support.
- Continue migrating executable card behavior into engine-owned definitions with explicit unsupported-behavior tracking.
- Spike Electric Streams only after the command/read loop has enough event shape to publish safely.

## Blockers

- None known from this iteration.

## Recommended next atomic task

- Add a small engine/UI-facing supported deck catalog or game-creation boundary over `Prizmo.Tcg.Decks.*`, so the React SPA can list supported fixtures and create Ash-backed games without knowing deck modules directly.

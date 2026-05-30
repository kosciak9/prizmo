# Ash-backed TCG Engine Playtest Handoff

Updated: 2026-05-30

## Current state

- Iteration 1 moved supported deck fixtures into shared `Prizmo.Tcg.Decks.*` modules backed by the new shared `Prizmo.Tcg.Decklist` macro.
- Legacy `Prizmo.Tcg.Sim.Decks.*` modules remain as compatibility shims that delegate to the shared deck fixtures, so existing simulator tests keep working while the Ash-backed engine stops depending on the simulator namespace.
- `test/prizmo/tcg_engine/mechanics_test.exs` now aliases `Prizmo.Tcg.Decks.Alakazam27147` and `Prizmo.Tcg.Decks.Dragapult27431`.
- Iteration 2 added `Prizmo.Tcg.Decks` as the shared supported fixture catalog and `Prizmo.TcgEngine.SupportedDecks` as the engine/UI boundary for resolving stable `deck_key` strings into engine deck modules.
- `Prizmo.Tcg.Data.TCGdex.known_deck_modules/0` now delegates to `Prizmo.Tcg.Decks.modules/0`, keeping metadata/coverage helpers pointed at the non-simulator fixture boundary without duplicating the deck list.
- `Prizmo.TcgEngine.Game` now exposes generic Ash actions for `list_supported_decks` and `create_from_supported_decks`, and `Prizmo.TcgEngine` exposes them through AshTypescript RPC as `listSupportedTcgDecks` and `createTcgEngineGame`.
- The SPA Ash client wrapper exports these generated functions as `runListSupportedTcgDecks` and `runCreateTcgEngineGame`.
- Iteration 3 added `Prizmo.TcgEngine.Game.start_setup_command`, exposed through the domain as `Prizmo.TcgEngine.start_setup_game/1` and through AshTypescript RPC as `startTcgEngineSetup`.
- The SPA Ash client wrapper exports the generated setup command as `runStartTcgEngineSetup`, with `StartTcgEngineSetupInput` and `StartTcgEngineSetupResult` types.
- The setup command delegates to `Prizmo.TcgEngine.Mechanics.start_setup/1`, so it writes the persisted setup record, `start_setup` event, and snapshot instead of using the bare state-machine update.

## Last commit

- Baseline entering iteration 3: `7ffe8da feat(tcg): expose supported engine deck games`.
- This handoff was written before committing iteration 3; expected commit message is `feat(tcg): expose setup command rpc`.

## Remaining tasks

- Decide whether old `Prizmo.Tcg.Sim` tests are kept as historical reference, quarantined, or ported scenario-by-scenario.
- Build the minimal playable React SPA loop: wire game creation and setup start to the new RPCs, expose the remaining setup commands, expose legal action affordances, prompt resolution, simple board/hand/discard/prize/turn/event rendering, and reconnect recovery.
- Expand persisted Ash engine mechanics: draw for turn, bench Basic Pokémon, one Energy attachment per turn, evolution timing, retreat/switch, attacks/damage/KO/prizes/replacement Active, turn transitions, and snapshot-backed undo/debug support.
- Continue migrating executable card behavior into engine-owned definitions with explicit unsupported-behavior tracking.
- Spike Electric Streams only after the command/read loop has enough event shape to publish safely.

## Blockers

- None known from this iteration.

## Recommended next atomic task

- Expose the next setup command through an engine-owned Ash/RPC action, likely `draw_opening_hand`, delegating to `Prizmo.TcgEngine.Mechanics.draw_opening_hand/1` and returning the persisted `Game` so the SPA can advance from `setup`/`waiting_to_draw` into `hands_drawn` without direct test-helper or IEx intervention.

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
- Iteration 4 added `Prizmo.TcgEngine.Game.draw_opening_hand_command`, exposed through the domain as `Prizmo.TcgEngine.draw_opening_hand_for_game/1` and through AshTypescript RPC as `drawTcgEngineOpeningHand`.
- The SPA Ash client wrapper exports the generated draw command as `runDrawTcgEngineOpeningHand`, with `DrawTcgEngineOpeningHandInput` and `DrawTcgEngineOpeningHandResult` types.
- The draw-opening-hand command delegates to `Prizmo.TcgEngine.Mechanics.draw_opening_hand/1`, so it writes the persisted setup transition, `draw_opening_hand` event, and snapshot instead of moving cards directly.
- Iteration 5 added `Prizmo.TcgEngine.Game.choose_active_from_hand_command`, exposed through the domain as `Prizmo.TcgEngine.choose_active_from_hand_for_game/3` and through AshTypescript RPC as `chooseTcgEngineActiveFromHand`.
- The SPA Ash client wrapper exports the generated active-choice command as `runChooseTcgEngineActiveFromHand`, with `ChooseTcgEngineActiveFromHandInput` and `ChooseTcgEngineActiveFromHandResult` types.
- The choose-active command delegates to `Prizmo.TcgEngine.Mechanics.choose_active_from_hand/3`, so it validates setup status, ownership, hand zone, Basic Pokémon status, and empty Active Spot before writing the `choose_active_from_hand` event and snapshot.
- Iteration 6 added `Prizmo.TcgEngine.Game.choose_setup_bench_from_hand_command`, exposed through the domain as `Prizmo.TcgEngine.choose_setup_bench_from_hand_for_game/3` and through AshTypescript RPC as `chooseTcgEngineSetupBenchFromHand`.
- The SPA Ash client wrapper exports the generated setup-bench command as `runChooseTcgEngineSetupBenchFromHand`, with `ChooseTcgEngineSetupBenchFromHandInput` and `ChooseTcgEngineSetupBenchFromHandResult` types.
- The choose-setup-bench command delegates to `Prizmo.TcgEngine.Mechanics.choose_setup_bench_from_hand/3`, so it validates setup status, ownership, hand zone, Basic Pokémon status, and next Bench position before writing the `choose_setup_bench_from_hand` event and snapshot.
- Iteration 7 added `Prizmo.TcgEngine.Game.place_prizes_command`, exposed through the domain as `Prizmo.TcgEngine.place_prizes_for_game/1` and through AshTypescript RPC as `placeTcgEnginePrizes`.
- The SPA Ash client wrapper exports the generated prize-placement command as `runPlaceTcgEnginePrizes`, with `PlaceTcgEnginePrizesInput` and `PlaceTcgEnginePrizesResult` types.
- The place-prizes command delegates to `Prizmo.TcgEngine.Mechanics.place_prizes/1`, so it validates setup status, Active Pokémon presence, and absence of existing prizes before writing the `place_prizes` event and snapshot.
- Iteration 8 added `Prizmo.TcgEngine.Game.complete_setup_command`, exposed through the domain as `Prizmo.TcgEngine.complete_setup_for_game/1` and through AshTypescript RPC as `completeTcgEngineSetup`.
- The SPA Ash client wrapper exports the generated setup-completion command as `runCompleteTcgEngineSetup`, with `CompleteTcgEngineSetupInput` and `CompleteTcgEngineSetupResult` types.
- The complete-setup command delegates to `Prizmo.TcgEngine.Mechanics.complete_setup/1`, so it validates setup status, Active Pokémon presence, and six Prize cards per player before writing the `complete_setup` event and snapshot and transitioning the game to `:in_progress`.
- Iteration 9 added `Prizmo.TcgEngine.Game.start_next_turn_command`, exposed through the domain as `Prizmo.TcgEngine.start_next_turn_for_game/1` and through AshTypescript RPC as `startNextTcgEngineTurn`.
- The SPA Ash client wrapper exports the generated turn-start command as `runStartNextTcgEngineTurn`, with `StartNextTcgEngineTurnInput` and `StartNextTcgEngineTurnResult` types.
- The start-next-turn command delegates to `Prizmo.TcgEngine.Mechanics.start_next_turn/1`, so it validates the game is `:in_progress`, chooses the next player/turn number, resets that player's turn flags, creates the persisted `Turn`, writes the `start_next_turn` event, snapshots it, and returns the refreshed `Game`.

## Last commit

- Baseline entering iteration 9: `34ecc8b feat(tcg): expose setup completion rpc`.
- This handoff was written before committing iteration 9; expected commit message is `feat(tcg): expose start next turn rpc`.

## Remaining tasks

- Decide whether old `Prizmo.Tcg.Sim` tests are kept as historical reference, quarantined, or ported scenario-by-scenario.
- Build the minimal playable React SPA loop: wire game creation, setup start, draw-opening-hand, active choice, setup Bench choice, prize placement, setup completion, and turn start to the new RPCs; expose draw/skip draw/action-window boundaries, legal action affordances, prompt resolution, simple board/hand/discard/prize/turn/event rendering, and reconnect recovery.
- Expand persisted Ash engine mechanics: draw for turn, bench Basic Pokémon, one Energy attachment per turn, evolution timing, retreat/switch, attacks/damage/KO/prizes/replacement Active, turn transitions, and snapshot-backed undo/debug support.
- Continue migrating executable card behavior into engine-owned definitions with explicit unsupported-behavior tracking.
- Spike Electric Streams only after the command/read loop has enough event shape to publish safely.

## Blockers

- None known from this iteration.

## Recommended next atomic task

- Expose the next turn-progress command through an engine-owned Ash/RPC action, likely `draw_tcg_engine_card_for_turn(game_id, player_id)` or `draw_tcg_engine_for_turn(game_id, player_id)`, delegating to `Prizmo.TcgEngine.Mechanics.draw_for_turn/2` and returning the persisted `Game` so the SPA can move from a `:start` turn toward the action window without direct test-helper or IEx intervention.

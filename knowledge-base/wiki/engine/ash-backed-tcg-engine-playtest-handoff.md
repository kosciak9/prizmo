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
- Iteration 10 added `Prizmo.TcgEngine.Game.draw_for_turn_command`, exposed through the domain as `Prizmo.TcgEngine.draw_for_turn_for_game/2` and through AshTypescript RPC as `drawTcgEngineCardForTurn`.
- The SPA Ash client wrapper exports the generated draw-for-turn command as `runDrawTcgEngineCardForTurn`, with `DrawTcgEngineCardForTurnInput` and `DrawTcgEngineCardForTurnResult` types.
- The draw-for-turn command delegates to `Prizmo.TcgEngine.Mechanics.draw_for_turn/2`, so it validates game/turn/player state, draws one card for the active player, writes the `draw_for_turn` event, snapshots it, and returns the refreshed `Game`; existing deck-out handling remains inside the mechanics layer.
- Iteration 11 added `Prizmo.TcgEngine.Game.open_action_window_command`, exposed through the domain as `Prizmo.TcgEngine.open_action_window_for_game/1` and through AshTypescript RPC as `openTcgEngineActionWindow`.
- The SPA Ash client wrapper exports the generated open-action-window command as `runOpenTcgEngineActionWindow`, with `OpenTcgEngineActionWindowInput` and `OpenTcgEngineActionWindowResult` types.
- The open-action-window command delegates to `Prizmo.TcgEngine.Mechanics.open_action_window/1`, so it validates the game is `:in_progress`, transitions the current turn from `:drawn` to `:action_window`, writes the `open_action_window` event, snapshots it, and returns the refreshed `Game`.
- Iteration 12 added `Prizmo.TcgEngine.Game.skip_draw_for_turn_command`, exposed through the domain as `Prizmo.TcgEngine.skip_draw_for_turn_for_game/2` and through AshTypescript RPC as `skipTcgEngineDrawForTurn`.
- The SPA Ash client wrapper exports the generated skip-draw command as `runSkipTcgEngineDrawForTurn`, with `SkipTcgEngineDrawForTurnInput` and `SkipTcgEngineDrawForTurnResult` types.
- The skip-draw command delegates to `Prizmo.TcgEngine.Mechanics.skip_draw_for_turn/2`, so it validates game/turn/player state, transitions the current turn from `:start` to `:action_window`, writes the `skip_draw_for_turn` event, snapshots it, and returns the refreshed `Game`.
- Iteration 13 added `Prizmo.TcgEngine.GameView` plus `Prizmo.TcgEngine.GameView.Fields` as a viewer-scoped read model for persisted engine games.
- `Prizmo.TcgEngine.Game.get_state` is exposed through the domain as `Prizmo.TcgEngine.get_game_state/2` and through AshTypescript RPC as `getTcgEngineGameState`.
- The SPA Ash client wrapper exports the generated read action as `runGetTcgEngineGameState`, with `GetTcgEngineGameStateInput` and `GetTcgEngineGameStateResult` types.
- The read model includes game status/cursors, setup status, current turn, public stadium, per-player deck/hand/prize/discard counts, public Active/Bench/discard card summaries, the viewer's private hand only, viewer awaiting prompts, and chronological event metadata without event payloads.
- Hidden-zone behavior verified this iteration: a valid viewer sees their own hand cards, the opponent hand is represented by count plus an empty `hand` list, and non-player viewers are rejected at the Ash action boundary.
- Iteration 14 replaced the placeholder SPA home route with a minimal TCG playtest shell.
- The shell calls `runListSupportedTcgDecks`, `runCreateTcgEngineGame`, and `runGetTcgEngineGameState` through the SPA Ash client, and `lib/prizmo_web/spa/lib/ash/client.ts` now re-exports the generated field-selection types needed by callers.
- Browser users can choose supported fixture decks, create a persisted player 1 versus player 2 game, switch the viewer between players, reconnect by game ID via local storage or pasted UUID, refresh state, and inspect status/cursors/setup/current turn, public board zones, deck/hand/prize/discard counts, viewer hand, event metadata, and viewer prompts.
- Iteration 15 added the first write command to the SPA shell.
- The shell now calls `runStartTcgEngineSetup` for the selected game, invalidates the viewer-scoped game-state query, and surfaces setup command pending/error state plus the refreshed setup status and `start_setup` event metadata.
- Iteration 16 added the next setup write command to the SPA shell.
- The shell now calls `runDrawTcgEngineOpeningHand` when setup is in `waiting_to_draw`, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed deck/hand counts and `draw_opening_hand` event metadata.
- Iteration 17 added the first setup choice write command to the SPA shell.
- The shell now calls `runChooseTcgEngineActiveFromHand` for a selected Basic Pokémon in the current viewer's visible hand when setup is in `hands_drawn` and that viewer has no Active Pokémon, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus the refreshed Active Spot.
- Iteration 18 added the optional setup Bench choice write command to the SPA shell.
- The shell now calls `runChooseTcgEngineSetupBenchFromHand` for a selected Basic Pokémon in the current viewer's visible hand after that viewer has chosen an Active Pokémon, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus the refreshed Bench count/list.
- Iteration 19 added the setup Prize placement write command to the SPA shell.
- The shell now calls `runPlaceTcgEnginePrizes` once both players have chosen Active Pokémon and no Prizes are placed, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed Prize counts and `prizes_placed` setup status.
- Iteration 20 added the setup completion write command to the SPA shell.
- The shell now calls `runCompleteTcgEngineSetup` once setup status is `prizes_placed`, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed completed setup and game status.
- Iteration 21 added the first turn-start write command to the SPA shell.
- The shell now calls `runStartNextTcgEngineTurn` once setup is completed, the game is `in_progress`, and no current turn exists, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed current-turn status.
- Iteration 22 added the draw-for-turn write command to the SPA shell.
- The shell now calls `runDrawTcgEngineCardForTurn` for the current turn's active player while the persisted current turn is in `start` status, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed turn status/deck and hand counts.
- Iteration 23 added the alternate draw-step write command to the SPA shell.
- The shell now calls `runSkipTcgEngineDrawForTurn` for the current turn's active player while the persisted current turn is in `start` status, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed `action_window` turn status.
- Iteration 24 added the open-action-window write command to the SPA shell.
- The shell now calls `runOpenTcgEngineActionWindow` while the persisted current turn is in `drawn` status, invalidates the viewer-scoped game-state query, and surfaces pending/error state plus refreshed `action_window` turn status.
- Iteration 25 added viewer-scoped legal action affordances to the persisted game-state read model and SPA shell.
- Awaiting prompts now surface as `choose_prompt` affordances for the prompted viewer before any other action-window affordance. Otherwise, only the active viewer during `action_window` receives informational command affordances for engine-defined card play, benching Basic Pokémon, attaching Energy, and ending the turn.
- The SPA now requests `actionAffordances` through `getTcgEngineGameState` and renders a Viewer legal actions panel with source/target/prompt/choice-key counts. These affordances are not execution controls yet.
- Setup start, opening-hand draw, setup Active choice, setup Bench choice, setup Prize placement, setup completion, first turn start, draw-for-turn, skip-draw, and open-action-window are clickable in the browser shell; action-window affordances are visible, while execution controls for those actions and prompt resolution controls still need UI wiring.
- Iteration 26 added `Prizmo.TcgEngine.Game.ActionCommands` as an Ash resource fragment for the new `play_card_command`, keeping `Prizmo.TcgEngine.Game` under the Credo module-length limit while exposing generic card play through the existing persisted mechanics layer.
- `Prizmo.TcgEngine` now exposes `play_card_for_game/3` and AshTypescript RPC `playTcgEngineCard`; the SPA Ash client re-exports it as `runPlayTcgEngineCard`.
- The Viewer legal actions panel now renders `Play ...` buttons for visible `play_card` source cards and calls the new command with empty upfront choices. This starts Ultra Ball's persisted pending-effect/prompt flow from the browser, then invalidates the viewer-scoped game-state query.
- Iteration 27 added `Prizmo.TcgEngine.Game.ActionCommands.choose_prompt_command`, exposed through the domain as `Prizmo.TcgEngine.choose_prompt_for_game/4` and through AshTypescript RPC as `chooseTcgEnginePrompt`.
- The SPA Ash client re-exports the generated prompt command as `runChooseTcgEnginePrompt`, with `ChooseTcgEnginePromptInput` and `ChooseTcgEnginePromptResult` types.
- The viewer-scoped game-state read model now enriches awaiting prompt payloads with private `legal_choice_cards` summaries for the prompted player only, allowing prompt UIs to show card names for hand/deck choices without publishing them to the opponent's view.
- The Viewer prompts panel now renders selectable legal card choices and submits selected IDs through the new prompt command. Ultra Ball's `discard_two_from_hand` cost prompt and `search_deck_for_pokemon` effect prompt can now complete from the browser after the generic play-card command starts the flow.
- Iteration 28 added `Prizmo.TcgEngine.Game.ActionCommands.play_basic_to_bench_command`, exposed through the domain as `Prizmo.TcgEngine.play_basic_to_bench_for_game/3` and through AshTypescript RPC as `playTcgEngineBasicToBench`.
- The SPA Ash client re-exports the generated Bench command as `runPlayTcgEngineBasicToBench`, with `PlayTcgEngineBasicToBenchInput` and `PlayTcgEngineBasicToBenchResult` types.
- The Viewer legal actions panel now renders `Bench ...` buttons for visible `play_basic_to_bench` source cards, calls the new command, and invalidates the viewer-scoped game-state query. Basic Pokémon can now move from hand to the next Bench slot from the browser action window.

## Last commit

- Baseline entering iteration 28: `b099351 feat(spa): wire prompt choice submission`.
- This handoff was written before committing iteration 28; expected commit message is `feat(spa): wire bench basic command`.

## Remaining tasks

- Decide whether old `Prizmo.Tcg.Sim` tests are kept as historical reference, quarantined, or ported scenario-by-scenario.
- Build the minimal playable React SPA loop beyond prompt resolution and Bench commands: continue execution controls for remaining visible legal action affordances and run two-browser refresh/reconnect validation.
- Expand persisted Ash engine mechanics: bench Basic Pokémon, one Energy attachment per turn, evolution timing, retreat/switch, attacks/damage/KO/prizes/replacement Active, turn transitions, and snapshot-backed undo/debug support.
- Continue migrating executable card behavior into engine-owned definitions with explicit unsupported-behavior tracking.
- Spike Electric Streams only after the command/read loop has enough event shape to publish safely.

## Blockers

- None known from this iteration.

## Recommended next atomic task

- Expose and wire the existing persisted `attach_energy` mechanic as an Ash/RPC command and SPA legal-action control so the active viewer can choose an Energy from hand and a Pokémon in play during the action window.

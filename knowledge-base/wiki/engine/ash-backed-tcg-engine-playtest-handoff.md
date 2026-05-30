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
- Iteration 29 added `Prizmo.TcgEngine.Game.ActionCommands.attach_energy_command`, exposed through the domain as `Prizmo.TcgEngine.attach_energy_for_game/4` and through AshTypescript RPC as `attachTcgEngineEnergy`.
- The SPA Ash client re-exports the generated Attach Energy command as `runAttachTcgEngineEnergy`, with `AttachTcgEngineEnergyInput` and `AttachTcgEngineEnergyResult` types.
- The Viewer legal actions panel now renders one `Attach ... to ...` button for each visible Energy-from-hand/source and in-play Pokémon/target pair, calls the new command, and invalidates the viewer-scoped game-state query. The persisted mechanics layer enforces active-player/action-window state and the once-per-turn Energy attachment flag.
- Iteration 30 added `Prizmo.TcgEngine.Game.ActionCommands.end_turn_command`, exposed through the domain as `Prizmo.TcgEngine.end_turn_for_game/2` and through AshTypescript RPC as `endTcgEngineTurn`.
- The SPA Ash client re-exports the generated End Turn command as `runEndTcgEngineTurn`, with `EndTcgEngineTurnInput` and `EndTcgEngineTurnResult` types.
- The Viewer legal actions panel now renders an `End ... turn` button for the existing `end_turn` affordance, calls the new command, and invalidates the viewer-scoped game-state query. The persisted mechanics layer enforces active-player/action-window state, transitions the current turn to `:ended`, writes the `end_turn` event, and snapshots it.
- Iteration 31 updated the SPA turn controls so `runStartNextTcgEngineTurn` is enabled when the persisted current turn has status `ended`, not only before the first turn exists.
- The Turn commands panel copy now describes starting the first or next persisted turn, and the Start Turn button labels ended turns as `Start next turn` while still preventing duplicate starts during in-progress turn statuses.
- Iteration 32 ran the documented two-browser Playwright playtest validation and found a real viewer-isolation blocker: Refresh/reload could reset a Player 2 browser session to Player 1 because the SPA persisted both game ID and viewer in a shared localStorage session object.
- The SPA now stores the shared game ID in localStorage but stores the selected viewer in tab-scoped sessionStorage, removes the legacy combined localStorage session on writes, and preserves Player 2 across Refresh/reload even while a same-origin Player 1 tab refreshes the same game.
- The Dragapult fixture order now starts new games with Moltres, Ultra Ball, and Fire Energy so the narrow browser playtest can cover setup Active, Attach Energy, Ultra Ball cost/effect prompts, searched Basic-to-Bench, End Turn, and Start next turn without many draw/end-turn cycles. The fixture card counts are unchanged.
- Manual-tester results before the viewer fix: Player 1 completed the functional flow but reported viewer switching; Player 2 selected Abra and verified hidden hand behavior until Refresh reset the viewer and exposed Player 1 state. Focused same-origin two-tab validation passed after the fix, but the full two-manual-tester milestone should be rerun.
- Iteration 33 reran the manual-tester milestone and hardened the SPA further after the agents still reported viewer flips: session updates are now functional, storage is synced from committed React state, game-state query functions read `game_id`/viewer from the query key instead of a render closure, and the workbench refuses to render any returned read model whose `viewerPlayerId` differs from the tab's current viewer.
- Focused same-origin two-tab validation now preserves Player 1 and Player 2 through repeated `Refresh state` clicks and reloads, with the board viewer badge matching the header viewer.
- An explicit isolated Playwright two-context diagnostic created game `f23cfd94-744c-473e-9c1e-2be2ba747b2e` and passed the full browser scenario: setup, Player 1 Moltres Active, Player 2 Abra Active, prizes/setup completion, turn 1 start/draw/open, Fire Energy attachment, Ultra Ball cost/effect prompts, Munkidori Bench, End Turn, Player 2 next turn, and reload recovery with hidden hands isolated.
- Manual-tester subagents still reported viewer flips on post-fix games, but their behavior is inconsistent with the isolated-context diagnostic and appears to come from the validation harness sharing or contending over one browser/session. Treat the manual-tester milestone as not formally satisfied until the testers can be guaranteed separate browser contexts.
- Iteration 34 reduced noise in the React playtest action/prompt panels: prompt cards now summarize the choice key, required selection count, and legal-choice count while keeping the raw prompt payload behind a collapsed debug disclosure.
- Action affordance cards now show command/prompt status without repeating the internal action key, and source/target/prompt/choice-key counts are tucked behind a collapsed action metadata disclosure.
- Iteration 35 added `Prizmo.TcgEngine.Game.ActionCommands.retreat_command`, exposed through the domain as `Prizmo.TcgEngine.retreat_active_for_game/4` and through AshTypescript RPC as `retreatTcgEngineActive`.
- Viewer action affordances now include `Retreat Active Pokémon` when the active viewer is in the action window, has not retreated this turn, has a Benched Pokémon target, and has enough attached Energy IDs to pay the Active Pokémon's catalog retreat cost.
- The SPA legal-actions panel now renders retreat buttons for each legal Bench target and required Energy payment combination, calls the new RPC command, and invalidates the viewer-scoped game-state query. Attached Energy labels may fall back to card instance IDs until attached cards are included in the read model/UI.
- Iteration 36 added public one-level `attached_cards`/`attachedCards` to top-level game-state card summaries, including Active, Bench, Stadium, viewer hand, discard, and prompt legal-choice card views.
- The SPA now requests nested `attachedCards`, renders attached cards under each visible `CardPill`, and indexes those nested cards in `visibleCardsById`, so retreat payment buttons can show attached Energy names instead of fallback card instance IDs.
- A rollback smoke verified Moltres with attached Fire Energy appears in `player_1.active.attached_cards` and that the retreat affordance's source ID matches the visible attached Energy.
- Iteration 37 added `Prizmo.TcgEngine.AttackCosts` to validate attack Energy costs from attached Energy providers and updated `Mechanics.declare_attack/3` to accept string attack IDs, fetch attack metadata for declaration, validate attached Energy, and persist `declare_attack` with pending attack state.
- `Prizmo.TcgEngine.CardCatalog.fetch_attack_for_declaration/2` now returns printed attack metadata without requiring executable damage/effect behavior, so declaration can be separated from later attack resolution.
- `Prizmo.TcgEngine.Game.ActionCommands.declare_attack_command` is exposed through the domain as `Prizmo.TcgEngine.declare_attack_for_game/3` and through AshTypescript RPC as `declareTcgEngineAttack`; the SPA client re-exports it as `runDeclareTcgEngineAttack`.
- Viewer action affordances now include one `declare_attack` entry per paid attack on the active viewer's Active Pokémon, with `attack_id`, `attack_name`, `attack_cost`, `attack_damage`, source Active ID, and opponent Active target ID.
- The SPA legal-actions panel now renders attack declaration buttons and calls the new RPC command. This moves the turn to `attack_declared`; damage/effects/KO/prize resolution and attack finish controls are intentionally still follow-up work.
- Iteration 38 added `Prizmo.TcgEngine.Game.ActionCommands.resolve_declared_attack_command` and `finish_attack_command`, exposed through the domain as `Prizmo.TcgEngine.resolve_declared_attack_for_game/2` and `Prizmo.TcgEngine.finish_attack_for_game/2` and through AshTypescript RPC as `resolveTcgEngineDeclaredAttack` and `finishTcgEngineAttack`.
- The SPA Ash client re-exports the new generated RPC calls as `runResolveTcgEngineDeclaredAttack` and `runFinishTcgEngineAttack`.
- The React playtest workbench now renders an Attack resolution panel while the current turn is `attack_declared` or `attack_resolving`; the active viewer can resolve the declared attack and then finish it to end the turn.
- A Tidewave rollback smoke staged Dreepy `Petty Grudge` and verified the full persisted state path: `declare_attack` → `attack_declared`, `resolve_declared_attack` → `attack_resolving` with 10 damage applied, then `finish_attack` → `ended` with persisted events.

## Last commit

- Baseline entering iteration 38: `24db2d7 feat(tcg-engine): declare paid attacks`.
- This handoff was written before committing iteration 38; expected commit message is `feat(tcg-engine): resolve declared attacks`.

## Remaining tasks

- Decide whether old `Prizmo.Tcg.Sim` tests are kept as historical reference, quarantined, or ported scenario-by-scenario.
- Build the minimal playable React SPA loop beyond prompt resolution, Bench commands, Attach Energy, attached-card board visibility, Retreat, paid attack declaration, static/executable attack resolution and finish controls, End Turn, next-turn progression, deterministic playtest fixture order, hardened tab-scoped viewer identity, and reduced prompt/action debug noise: rerun the full two-browser/manual-tester playtest milestone only after the validation harness can guarantee separate browser contexts, then address any remaining command-loop gaps it exposes.
- Expand persisted Ash engine mechanics: broader attack effects, damage/KO/prizes/replacement Active, switch effects, evolution UI/RPC wiring, turn transitions, and snapshot-backed undo/debug support.
- Continue migrating executable card behavior into engine-owned definitions with explicit unsupported-behavior tracking.
- Spike Electric Streams only after the command/read loop has enough event shape to publish safely.

## Blockers

- No known code blocker after the iteration 33 viewer hardening, isolated-context playtest pass, iteration 34 action/prompt clarity pass, iteration 35 retreat command pass, iteration 36 attached-card visibility pass, iteration 37 paid attack declaration pass, and iteration 38 static/executable attack resolution/finish pass.
- Attack resolution currently depends on `Prizmo.TcgEngine.CardCatalog.fetch_attack/2`; paid attacks with raw text but missing executable behavior can still be declared and will fail at resolution until their behavior is migrated or unsupported declaration is made explicit.
- Validation blocker: the available manual-tester subagents still appear to share/contend over one browser/session, so their reported viewer flips are not reliable proof of independent-browser behavior. The documented manual-tester milestone needs a harness that guarantees separate browser contexts before it can be marked formally complete.

## Recommended next atomic task

- Migrate the deterministic playtest fixture's `PFL-014` Moltres `Fighting Wings` attack into engine-owned executable behavior, then validate the browser-visible paid attack path can declare, resolve, finish, and start the next turn without hitting an unsupported-attack resolution error.

# Dragapult/Alakazam GameView Pending-Text Inventory (2026-06-16)

- Updated: 2026-06-17 (post representative browser validation)
- Scope: authoritative live `GameView` / playability pending-text inventory for the current north-star target decks only (27431 Dragapult, 27147 Alakazam). This fulfills the explicit north-star definition that "complete gameplay means the live play surface has no visible `Pending card text` for target-deck gameplay."
- Method: cross-referenced post-256 six-deck inventory, recent commits (91b0386 and prior), current `ActionAffordances` pending-emission paths, `EngineCardRegistry`, effect-type registries, and the `dragapult-alakazam-full-game-implementation-scope.md` blocker list. Only cards that still produce visible `Pending card text` / `unsupported_*` affordances on the React board are listed.

## Result

**Zero visible pending-text blockers for core Dragapult and Alakazam cards after the 2026-06-16 plain-tech Supporter batch.**

- Dragapult fixture variants (28256 plain, 28253 Blaziken, 28236 Dusknoir) and Alakazam baseline (27147) now have no cards that emit `Pending card text`, `unsupported_attack`, `unsupported_ability`, `unsupported_trainer`, `unsupported_tool`, `unsupported_stadium`, or `unsupported_energy` affordances on the live board for their printed gameplay text.
- The three remaining plain Dragapult tech Supporters (`TWM-080` Mega Lopunny ex, `SFA-064` Xerosic's Machinations, `POR-084` Rosa's Encouragement) received behavior overlays (or registry coverage) in the latest batch and are now past the visible pending-text blocker stage.
- Alakazam tech fixture/support work remains documented as future scope (ASC-197, TEF-146, PFL-094, TEF-159, SCR-137, CRI-082 Special Red Card fixture/test coverage) but none of those cards appear as visible pending text on the current Alakazam board.
- Representative browser validation is now complete for the key Dragapult trio against live Alakazam Dudunsparce `28275`: Dusknoir `28236`, Blaziken `28253`, and plain `28256` each reached Turn 2 player-2 action window through the normal two-seat setup flow, and the Blaziken run also exercised a mulligan reveal plus compensation draw with no visible `Pending card text` blockers.

## Remaining documented work (non-blocker)

- Alakazam tech fixture/support work (common swaps) — not yet visible pending text.
- Broader live play-surface validation beyond the representative Dragapult trio — deeper mid-game turn lines and/or additional latest-result lists when those runs provide new signal.

## Recommended next (selection rules applied)

The north-star definition is now satisfied for visible `Pending card text` on the live Dragapult/Alakazam play surface, and the representative setup/pass browser-validation slice is now closed. Highest-leverage next batch per current north-star/handoff guidance:

1. **Broader latest-result play-surface validation** beyond the representative `28236` / `28253` / `28256` trio, prioritizing deeper mid-game turn lines or additional live deck ids that have not yet been exercised in-browser.
2. **Alakazam tech fixture/support slice** if a real visible pending-text gap appears after adding common tech swaps to the Alakazam fixture.

Do not pick UI polish, Electric Streams, or non-target deck work until the documented Dragapult/Alakazam remaining work list is closed or a new visible blocker appears.

**North-star milestone status:** The first milestone ("every card needed by the supported Dragapult/Alakazam fixture scope must be playable through the canonical Ash engine or a deliberate generic behavior path with full mechanics for its printed gameplay text") is met for visible pending text. Subsequent work can continue on the remaining documented items above.

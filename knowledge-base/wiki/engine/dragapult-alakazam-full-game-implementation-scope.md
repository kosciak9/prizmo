# Dragapult and Alakazam Latest-Limitless Coverage Scope

- Updated: 2026-06-23
- Sources: Project codebase; local validation; wiki log; Limitless TCG; user direction
- Raw: [NAIC 2026 Dragapult and Alakazam Deck Cards](../../raw/meta/2026-06-16-naic-2026-dragapult-and-alakazam-deck-cards.md)

## Summary

This article tracks **Goal 1** from the canonical north star: support all latest Limitless variants for Dragapult and Alakazam through the Ash-backed persisted engine and play surface.

The older one-matchup framing is superseded. The target is not just one Dragapult-vs-Alakazam fixture. The target is complete latest-Limitless variant coverage for both archetypes: every card, setup path, Ability, attack, Trainer, Tool, Stadium, Energy behavior, and timing interaction required by those variants.

## Source rule

- Use the latest available Limitless data for Dragapult and Alakazam variants.
- Treat historical NAIC 2026 lists and the captured raw file as useful seed data, not as the final fixed universe.
- When a latest-Limitless variant introduces a new card with usage greater than `0.00`, add it to the Goal 1 coverage corpus until it is classified and either supported or intentionally deferred with reason.

## Current canonical path

- The canonical engine is `lib/prizmo/tcg_engine/`.
- The legacy pure simulator (`lib/prizmo/tcg/sim/`) is reference/historical code only.
- The current React browser play UI is temporary scaffolding for validation and protocol discovery.
- Long-term play UX moves toward embedded Godot, but Goal 1 card/rule support should still be implemented server-side first.

## Current state

- The original eight fixture-deck blockers are closed in the canonical path: Teleportation Attack, Psychic Draw, Powerful Hand, Recon Directive, Run Away Draw, Spherical Shield, ACE Nullifier, and Damp have persisted engine behavior and/or action surfaces.
- Dragapult Blaziken variant support includes Seething Spirit, Smolder-sault, Fairy Zone Weakness override, Chi-Yu Allure + Ground Melter with Stadium discard, and Special Red Card backend play support.
- Dragapult Dusknoir variant support includes Come and Get You, Dusclops/Dusknoir Cursed Blast backend resolution, Dusknoir Shadow Bind, Jamming Tower Tool suppression, Battle Cage-style bench damage-counter prevention, and React SPA button/RPC wiring for `cursed_blast` actions.
- Plain Dragapult / Alakazam tech Trainer coverage now includes canonical `play_card` registry wiring plus focused mechanics coverage for `SFA-064` Xerosic's Machinations, `POR-084` Rosa's Encouragement, and `CRI-082` Special Red Card. `SFA-064` now uses an opponent-owned discard prompt so the affected player chooses which hand cards to discard, and `POR-084` now uses a mixed prompt over discard Basic Energy plus Stage 2 targets instead of first-pass auto-selection.
- The 2026-06-16 live GameView pending-text inventory reported zero visible pending-text blockers for the then-current Dragapult/Alakazam visible scope after the plain-tech Supporter batch.
- The legacy `Prizmo.Tcg.Sim` registry now has CI compatibility overlays for the plain Dragapult and Dragapult/Blaziken variant-only cards (`DRI-040`, `DRI-041`, `JTG-024`, `POR-084`, `SFA-064`), and the pairwise known-deck smoke matrix compiles with unique deck-id test names and passes under `mix check`.
- The repo now has a live corpus-audit task, `mix prizmo.goal1.audit`, that compares committed Goal 1 fixtures against the current Limitless latest-result deck ids without forcing those live decks into the legacy known-deck pool.
- The committed Goal 1 live Dragapult fixture corpus now tracks the current latest-result deck ids directly: `28236`, `28250`, `28253`, `28255`, `28256`, `28258`, `28259`, `28261`, `27611`, `28264`, `28268`, and `28271`. Historical fixture `27431` remains available as a general supported deck, but it is no longer treated as the canonical live Goal 1 Dragapult fixture set.
- The committed Goal 1 live Alakazam fixture corpus now tracks the current latest-result deck ids directly through dedicated modules under `lib/prizmo/tcg/goal_1/decks/`: `28275`, `28291`, `28310`, `28337`, `28340`, `28368`, `28385`, `28398`, `28405`, `28431`, `28438`, and `27615`. Historical fixture `27147` remains available as a general supported deck, but it is no longer treated as the canonical live Goal 1 Alakazam fixture set.
- The repo now also has a live corpus-reconciliation task, `mix prizmo.goal1.corpus`, that fetches the current latest-result decklists, diffs their unique card corpus against the committed Goal 1 fixtures, and classifies each live card from the current engine/catalog state as `supported`, `generic-supported`, `partial`, or `unimplemented`.
- As of 2026-06-17, Dragapult latest-result cards expand the committed fixture corpus by exactly six cards: `JTG-151`, `MEG-088`, `ASC-181`, `JTG-120`, `TEF-129`, and `TWM-163`. All six are now `supported`. `MEG-088` Yveltal now resolves `Clutch` through the canonical attack-effect lock path, and `JTG-151` Lillie's Pearl now reduces the opponent's Prize take by 1 when an attached Lillie's Pokémon is Knocked Out by damage from an opponent's attack.
- As of 2026-06-17, Alakazam latest-result cards expand the committed fixture corpus by fifteen cards: `TEF-146`, `MEG-130`, `PFL-094`, `TWM-082`, `TWM-141`, `ASC-197`, `BLK-040`, `TEF-159`, `DRI-010`, `TWM-158`, `CRI-082`, `PFL-085`, `SCR-118`, `SVI-186`, and `TEF-145`.
- The latest Alakazam support follow-up fully closed the live Alakazam latest-result corpus on the canonical path. `BLK-040` Elgyem now has an executable `Slight Shift` declared-attack resolution path that moves an opponent's attached Energy to another opponent Pokémon through the Ash attack-resolution surface plus SPA controls, `TWM-082` Alakazam now has both its executable `Psychic` attack (`10 + 50` per Energy attached to the opponent's Active) and its full `Strange Hacking` attack surface, and `POR-088` Telepathic Psychic Energy now has its attach-trigger prompt/resolution path. When `POR-088` is attached from hand to one of your Psychic Pokémon, the canonical Ash path now opens a prompt over legal Basic Psychic Pokémon in deck, benches the chosen targets, shuffles the deck with persisted RNG metadata, and resumes cleanly through the normal prompt system.
- After the `POR-088` batch, `mix prizmo.goal1.corpus` reports Alakazam live coverage at `supported=38`, `generic-supported=1`, `partial=0`, `unimplemented=0`; there are no current latest-result Alakazam cards left in a non-full-support state.
- After the Dragapult live-fixture batch, `mix prizmo.goal1.audit` reports no missing or stale committed Goal 1 fixtures for either archetype, and `mix prizmo.goal1.corpus` reports Dragapult fixture-card parity with the live latest-result set (`live unique cards: 49`, `committed fixture unique cards: 49`) alongside full live coverage (`supported=46`, `generic-supported=3`, `partial=0`, `unimplemented=0`).
- The supported-deck launcher path now exposes the full Goal 1 browser-validation pool through `Prizmo.TcgEngine.SupportedDecks` and the React SPA without widening the legacy known-deck smoke matrix. `Prizmo.Tcg.Decks.playtest_modules/0` now drives the 30 launchable playtest fixtures (12 Dragapult latest-result lists, 12 Alakazam latest-result lists, plus 6 historical/reference decks), duplicate deck names are disambiguated with deck ids in the UI, and the default fixture pairing now starts on a Dragapult-versus-Alakazam matchup instead of an intra-Dragapult mirror. The older `Prizmo.Tcg.Decks.modules/0` / `Prizmo.Tcg.Data.TCGdex.known_deck_modules/0` pool intentionally stays narrower so legacy `Prizmo.Tcg.Sim` pairwise smoke coverage remains green.
- Supported Goal 1 fixture creation now matches the open-deck RNG path instead of creating unseeded/unshuffled tables. `Prizmo.TcgEngine.SupportedDecks.create_game/2` now always creates shuffled fixture games with engine-owned RNG metadata, generates a fresh seed by default, and accepts explicit `rng_seed` input through the Ash action / SPA fixture launcher so browser-validation runs can be reproduced exactly when setup or mid-game issues surface.
- The repo now has a Goal 1 seed-search helper, `Prizmo.Tcg.Goal1.SeedFinder`, plus `mix prizmo.goal1.seed_search` for finding deterministic **fixture-mode** opening hands that contain specific target cards while still requiring normal opening Basics by default. This is now the fastest way to produce reproducible prompt-heavy Goal 1 validation boards. Regular premade/open-deck games still use synthetic deck keys (`player-1-open-deck` / `player-2-open-deck`) for shuffle context, so their opening hands will not match fixture-key seed predictions one-to-one.
- The regular-premade launcher now clears the editable decklist text and disables board creation while newly selected premades are still reloading into the text editors. This removes a race where quick deck switching could otherwise create a regular board before both editors had visibly resynced.
- `test/prizmo/tcg_engine/mechanics_test.exs` now has dedicated Goal 1 validation for Fairy Zone weakness remapping, Chi-Yu `Ground Melter` Stadium discard, `Come and Get You` discard-to-bench prompt flow, `Cursed Blast` knockout prize/replacement flow plus `Damp` blocking, and `Jamming Tower` suppressing `JTG-151` Lillie's Pearl Prize reduction. That validation batch also fixed a real canonical-engine bug in `lib/prizmo/tcg_engine/attack_damage.ex`: Fairy Zone now checks the attacking player's in-play source when remapping an opposing Darkness Pokémon's Weakness to Psychic.
- Representative Goal 1 two-seat browser validation is now complete for the three important Dragapult variants against the live Alakazam Dudunsparce fixture `28275`: Dusknoir `28236` (`04f89b2d-b424-49a0-bef2-21a9eb2b2c00`), Blaziken `28253` (`af57a106-1b5d-47eb-99c2-93dee8c0cb17`), and plain Dragapult `28256` (`7625fcfd-f9ef-42ab-a8da-8c3c1e24e613`). Each run used separate player-1/player-2 browser tabs, completed coin toss, starting-player choice, opening Active selection, opening Bench selection when available, setup-ready, prize/setup completion, Turn 1 player-1 action window, player-1 pass, and Turn 2 player-2 action window without IEx/database intervention. The Blaziken run also exercised player-2 mulligan reveal plus player-1 compensation draw through the normal UI path. No visible `Pending card text` blockers surfaced during those representative flows.
- Broader/deeper seeded latest-result browser validation now includes live Dragapult `28250` versus live Alakazam `28310` in supported game `01234059-e7b7-4297-9883-1d8c4e625200` with explicit seed `goal1-28250-vs-28310-seed-a`. That run exercised two player-1 mulligans with public reveal, player-2 optional 2-card mulligan compensation draw, player-1 `Buddy-Buddy Poffin` prompt resolution into `Dreepy` + `Dunsparce`, a turn-1 Darkness attachment to `Munkidori`, and player-2 `POR-088` Telepathic Psychic Energy attach-trigger prompt/resolution on Turn 2 by attaching to `Abra`, benching one extra `Abra`, shuffling, and cleanly resuming to the next player action window. No visible `Pending card text` blockers surfaced during those mid-game lines.
- Broader/deeper seeded latest-result browser validation also now includes live Dragapult `28258` versus live Alakazam `28337` in supported game `cd714f85-6509-44e4-b95e-04c9e7ef5130` with explicit seed `goal1-28258-vs-28337-seed-b-139`. The seed-search helper predicted player-1 `Dragapult ex` + `Darkness Energy` + `Team Rocket's Watchtower` + `Judge` + `Dreepy` + `Secret Box` + `Rare Candy` and player-2 `Abra` + `Abra` + `Genesect` + `Wondrous Patch` + `Battle Cage` + `Hilda` + `POR-088`; the live browser game reproduced those exact opening hands in fixture mode, completed setup through Turn 1 player-1 action window, and then opened the full `Secret Box` discard-three prompt with six legal discard choices. No visible `Pending card text` blockers surfaced during that setup-to-prompt line.
- Broader/deeper seeded latest-result browser validation now also includes live Dragapult `28268` versus live Alakazam `28340` in supported game `5f68306f-78ff-4dd1-87f0-e0310c7c7980` with explicit seed `goal1-28268-vs-28340-seed-a-210`. That run reproduced the predicted opening hands, completed setup with `Munkidori` versus `Elgyem` + `Psyduck`, passed cleanly from player-1 Turn 1 to player-2 Turn 2, exposed `Play Eri` in the browser action surface, opened the full acting-player `discard_opponent_item_cards_from_hand` prompt over four revealed opponent Item cards (`Buddy-Buddy Poffin`, `Unfair Stamp`, and two `Poké Pad` copies), and resolved the prompt by discarding `Buddy-Buddy Poffin` plus `Unfair Stamp` before returning to the same turn's normal action window. This run surfaced and fixed two real canonical-path defects: the read-model helper behind `GameView.ActionAffordances` had drifted from the engine's supported effect-choice set and was hiding `TEF-146` Eri from the UI, and the Eri resolution path was incorrectly feeding `{:ok, metadata}` tuples into `collect_ok_results/1` when validating selected Item cards.
- Broader/deeper seeded latest-result browser validation now includes live Dragapult `28255` versus live Alakazam `28291` in supported game `6bda3111-866a-4808-9d24-337cc1440df4` with explicit seed `goal1-28255-vs-28291-seed-283`. That run reproduced player-1 `MEG-088` Yveltal and player-2 `TEF-145` Ciphermaniac's Codebreaking in opening hands, completed setup, and passed to player-2 Turn 2. It surfaced and fixed a real canonical-path defect: `CardPlay.search_deck_choice_cards/3` assumed every `:search_deck` effect had a `filter`, so `GameView.for_player/2` crashed for Ciphermaniac's unfiltered two-card deck-top search. The fix also added canonical `:deck_top` resolution support, and the replayed browser flow opened the full `search_deck_for_cards_to_top` prompt, resolved two chosen deck cards, and returned to the action window with no console errors.
- Broader/deeper seeded latest-result browser validation now also includes live Dragapult `28261` versus live Alakazam `28431` in supported game `1fe1c721-dd05-47ac-b2a2-9b50f777d28f` with explicit seed `goal1-28261-vs-28431-seed-14`. That run completed setup through player-2 Turn 2, exposed `Play Pokégear 3.0`, opened the top-7 Supporter prompt, exercised the no-hit edge case (`0` legal Supporter choices), submitted the empty choice, shuffled/resolved, and returned to the same action window with no console errors.
- Broader/deeper seeded latest-result browser validation now also includes live Dragapult `28264` versus live Alakazam `28405` in supported game `1afd27a4-ae9e-4e4e-aa88-3e594ee5eba2` with explicit seed `goal1-28264-vs-28405-twm082-935`. That line first surfaced a real Goal 1 correctness bug in the canonical evolution timing path: on player-2 Turn 2 (player 2's first turn), the SPA exposed `Play Rare Candy`, the engine opened a `rare_candy_evolve_basic_to_stage_2` prompt over `Abra` plus `TWM-082` Alakazam, and the illegal Stage 2 evolution resolved. The follow-up fix moved first-turn evolution timing from the old global `turn_number > 1` assumption to the actual acting player's first-turn rule and threaded that rule through generic `evolve_from_hand`, Rare Candy prompt legality/validation, and `GameView.ActionAffordances`. Replaying the same seeded setup after the fix reached the identical player-2 Turn 2 state with no `Play Rare Candy` affordance, `Prizmo.TcgEngine.Requirements.require_evolution_allowed_this_turn/2` now returns `{:error, :cannot_evolve_on_first_turn}` for `{2, "player_2"}`, and a direct backend retry on the in-hand `MEG-125` now rejects with `{:error, {:not_enough_legal_choices, :rare_candy_evolve_basic_to_stage_2, 2, 0}}`. Continuing the same seeded browser game beyond that corrected state then fully reached the intended `TWM-082` validation slice: player-2 Turn 2 attached `POR-088` Telepathic Psychic Energy to `Abra`, resolved the attach-trigger prompt in browser with mixed `Abra` + `Elgyem` deck choices, passed to player-1 Turn 3, absorbed `Petty Grudge`, and reached player-2 Turn 4 with a legal `Play Rare Candy` affordance. The Turn 4 Rare Candy prompt exposed only the two valid in-play `Abra` targets, evolved the active `Abra` into `TWM-082` Alakazam with `POR-088` still attached, and immediately exposed both `Psychic` and `Strange Hacking` buttons. The browser replay then resolved `Strange Hacking` on a no-damage opponent board with no extra prompt, applied Confused to the opponent's Active `Dreepy`, advanced cleanly to player-1 Turn 5, and showed no console errors or visible `Pending card text` blockers.
- Attempted broader/deeper validation for live Dragapult `28271` versus live Alakazam `28438` in supported game `f3944df2-c9e7-423e-9dda-9575a6192f49` with explicit seed `goal1-28271-vs-28438-seed-8` surfaced a fresh Goal 1 blocker. The browser flow reached player-2 Turn 2 with `SCR-118` Fan Rotom Active and `Abra` Benched, but `GameView.action_affordances` exposed no `Fan Call` command. Treat `SCR-118`'s previous full-support classification as stale/too broad: its card catalog and attack metadata are present, but its first-turn Ability still needs a canonical Ability command/prompt path plus React wiring before Goal 1 can count it as play-surface supported.
- That inventory does **not** close Goal 1 by itself. Goal 1 also requires latest-Limitless variant coverage, executable mechanics, tests/fixtures, and play-surface validation.

## Known remaining work

- Current live latest-result cards and committed fixtures for both Dragapult and Alakazam are now aligned on the canonical Ash path, and the explicit mechanics-test gap for Fairy Zone/Weakness, Ground Melter Stadium discard, Come and Get You, Cursed Blast prize/replacement/Damp interactions, and Jamming Tower is now closed.
- Representative two-seat browser validation is now complete for the important Dragapult trio (`28236`, `28253`, `28256`) against Alakazam `28275`.
- `SCR-118` Fan Rotom `Fan Call` is now closed on the canonical engine + play-surface path, but only after a second follow-up batch corrected two defects that the first implementation left behind. The Ash engine batch added the `use_fan_rotom_fan_call_command` action, pending-effect prompt flow, and `GameView.ActionAffordances` metadata, but the replayed `28271` versus `28438` browser run proved the SPA still lacked an executable `Fan Call` button because `Prizmo.TcgEngine` had not exposed the new action through `typescript_rpc` / code-interface wiring and `index.tsx` had no `fan_call` action renderer. The follow-up batch added the RPC/client/SPA command path, replayed the same seeded matchup in supported game `3f8b85eb-c0c9-4e04-81fa-79667e01a80f`, confirmed Turn 2 `Fan Call` button visibility and prompt resolution over the three legal `Dunsparce` deck copies, and then fixed a second correctness bug from the same replay: `AbilityEffects.require_fan_call_available/2` previously allowed `Fan Call` again on later turns. The engine now rejects later-turn reuse with `:fan_call_only_available_on_first_turn`, and the browser-confirmed Turn 4 state no longer shows a `Fan Call` affordance.
- The latest `28264` versus `28405` replay also closed a broader Goal 1 timing defect that affected both generic hand evolutions and Rare Candy. Evolution timing now keys off the acting player's actual first turn rather than only the global turn counter, so player 2 can no longer evolve on Turn 2 just because the match's overall turn number is greater than 1. The continued replay now also closes the specific `TWM-082` browser-validation follow-up on that same seed: legal Turn 4 Rare Candy evolution plus `Strange Hacking` attack resolution are both proven on the live play surface.
- Remaining live validation work is broader and deeper: continue two-seat play-surface runs across more of the latest-result Goal 1 fixture pool and keep pushing beyond setup/pass into additional mid-game turn lines when those runs provide new coverage signal. The fixture launcher now supports explicit RNG seeds, and `mix prizmo.goal1.seed_search` can now preselect promising fixture seeds before opening the browser. Prefer regression-fixture mode when reproducing seed-search hits, because regular premade/open-deck creation uses different synthetic deck-key shuffle context. The `28264` / `28405` `TWM-082` line is now browser-validated through a legal Turn 4 attack, so prefer unexplored latest-result seeds unless evolution timing, Rare Candy targeting, or `TWM-082` attack resolution changes again.

## Historical seed variant pool

These records came from the NAIC 2026 / 2026-06-16 seed capture. They are useful starting points, but agents should refresh against latest Limitless data before declaring Goal 1 status.

### Dragapult variants to support

| Variant | NAIC deck | Key unique cards |
|---|---|---|
| Plain Dragapult | 28256 (Abaan Ahmed) | TWM-80 Abra, SFA-64 Xerosic's Machinations, POR-84 Rosa's Encouragement |
| Dragapult Blaziken | 28253 (Jon Webb) | DRI-40 Torchic, DRI-41 Combusken, JTG-24 Blaziken ex, JTG-56 Lillie's Clefairy ex, TWM-39 Chi-Yu |
| Dragapult Dusknoir | 28236 (Roman G.) | PRE-35 Duskull, PRE-36 Dusclops, PRE-37 Dusknoir, TWM-153 Jamming Tower |
| Additional Dragapult aggregate cards | >0.00 avg in seed capture | MEG-88 Yveltal, JTG-121 Dudunsparce ex, SFA-39 Pecharunt ex, SCR-114/115 Hoothoot/Noctowl, TWM-64 Wellspring Mask Ogerpon ex, TWM-99/100 Hisuian Growlithe/Arcanine, PRE-16 Pyroar, PRE-66 Bronzor, TEF-69 Bronzong, TWM-141 Bloodmoon Ursaluna ex, SSP-56 Chien-Pao, SSP-76 Latias ex |

### Alakazam variants / tech pool

| Tech card | Seed avg count | Notes |
|---|---|---|
| ASC-197 Nighttime Mine | 2.61 | Core disruption Stadium |
| TEF-146 Eri | 0.55 | Disruption Supporter |
| PFL-94 Wondrous Patch | 0.13 | Energy recovery |
| TEF-159 Rescue Board | 0.08 | Tool |
| SCR-137 Gravity Gemstone | 0.03 | Tool |
| CRI-82 Special Red Card | 0.31 | Disruption Item |
| BLK-40 Elgyem | 0.40 | Niche Pokémon |
| TWM-82 Alakazam (alt) | 0.11 | Alternate print |
| SSP-70 Togepi | 0.02 | Niche Pokémon |
| SSP-72 Togekiss | 0.02 | Niche Pokémon |
| WHT-86 Ignition Energy | 0.02 | Special Energy |
| TWM-167 Legacy Energy | 0.02 | Special Energy |

## Coverage status categories

Use these labels when updating coverage trackers or implementation notes:

- `supported` — executable through the canonical Ash engine path and usable through the play protocol where players need it.
- `generic-supported` — intentionally covered by a generic path sufficient for normal gameplay.
- `partial` — some behavior is executable, but printed text, timing, targeting, or validation remains incomplete.
- `unimplemented` — no executable server behavior yet.
- `unvalidated` — believed implemented but not proven by tests, rollback scenarios, fixtures, or play-surface validation.

## Suggested agent work order

1. Refresh latest Limitless Dragapult and Alakazam variant/card data.
2. Update the coverage corpus and classify every card by the categories above.
3. Prioritize blockers that appear across multiple variants or block normal game progress.
4. Implement behavior in server-side engine/card modules.
5. Add focused tests or fixtures for each newly supported card/mechanic.
6. Validate important variant matchups through the current React scaffolding until the Godot play surface exists.

## Goal 1 validation definition

Goal 1 is done when:

- latest-Limitless Dragapult and Alakazam variants are inventoried;
- every card with usage greater than `0.00` in those variants is tracked;
- every tracked card is `supported` or `generic-supported`, or a deliberate non-blocking exception is documented;
- target variants have no visible `Pending card text` blockers in the live play surface;
- server-side mechanics cover normal play, including setup, draw/search/discard flows, Energy attachment/payment, evolution, switching/retreat, Abilities, attacks, Stadium/Tool/Special Energy effects, KOs, prizes, and replacement Active;
- two-seat validation can play representative Dragapult variants against Alakazam without direct IEx/database/test-helper intervention for normal progress.

## See Also

- [Prizmo TCG Engine and Play Surface North Star](ash-backed-tcg-engine-playtest-north-star.md)
- [Dragapult/Alakazam GameView Pending-Text Inventory (2026-06-16)](dragapult-alakazam-gameview-pending-text-inventory-2026-06-16.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Alakazam Competitive Intelligence](../meta/alakazam-competitive-intelligence.md)
- Dragapult variant fixture decklists in code:
  - [`lib/prizmo/tcg/decks/dragapult_plain28256.ex`](../../../lib/prizmo/tcg/decks/dragapult_plain28256.ex)
  - [`lib/prizmo/tcg/decks/dragapult_dusknoir28236.ex`](../../../lib/prizmo/tcg/decks/dragapult_dusknoir28236.ex)
  - [`lib/prizmo/tcg/decks/dragapult_blaziken28253.ex`](../../../lib/prizmo/tcg/decks/dragapult_blaziken28253.ex)

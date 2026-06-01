# Open-Deck RNG TCG Engine and Card-First Playtest UI North Star

- Updated: 2026-06-01
- Sources: Project codebase; local validation; wiki log; Electric documentation (2026-05-30)
- Raw: [Electric Streams documentation notes](../../raw/engine/2026-05-30-electric-streams-docs.md)

## Scope

This is the current north star for Prizmo's Pokémon TCG work: an Ash-backed, server-authoritative rules engine where two humans can start from arbitrary supported decklists, use persisted RNG for setup, shuffles, prizes, and draws, and play through a card-first browser UI built for experienced Pokémon TCG players.

The goal is not yet complete Standard card-effect coverage, an AI opponent, an exact PTCGL clone, or post-game coaching. The near-term goal is a real playtest loop: players bring decklists, the engine performs normal random setup without preseeded draws, unsupported card effects are surfaced explicitly, and the UI feels like a dense competitive card table rather than a tutorial, test bench, or white-space-heavy debug surface.

## Current baseline

- `lib/prizmo/tcg_engine/` is the canonical engine path.
- The engine is persisted with Ash resources for games, players, turns, card instances, prompts, pending effects, setup, game events, and snapshots.
- Card play is generic and registry-driven for the first Ultra Ball-style flow, including costs, effects, prompts, pending continuations, and domain-fact events.
- `Prizmo.TcgEngine.CardCatalog` now owns the engine catalog boundary. It builds catalog records from committed TCGdex metadata plus authored behavior manifests instead of delegating to `Prizmo.Tcg.Sim.CardRegistry`.
- `Prizmo.TcgEngine.Decklists` now accepts arbitrary deck payloads made of catalog card IDs through the Ash `create_from_decklists` / TypeScript RPC `create_open_deck_tcg_engine_game` path. It validates deck size, duplicate card rows, catalog resolution, and Basic Pokémon presence before creating persisted games. Open-deck creation now assigns a fresh seed by default or accepts an explicit deterministic seed, persists `rng_seed`, `rng_seed_source`, and `rng_algorithm` on the game, reorders each player's deck through engine-owned shuffle, and records per-player `deck_shuffled` domain facts/snapshots before setup starts. The React SPA create/reconnect rail now defaults to a minimal open-deck creation flow: two pasted decklists, client-side 60-card parsing/aggregation, an optional deterministic seed field, and automatic navigation into the existing board after the Ash RPC succeeds. It accepts direct catalog-ID rows plus common PTCGL/Limitless-style rows such as `4 Dragapult ex TWM 130`, normalizes set/number pairs to catalog IDs, skips section headings, and shows normalized-row feedback before creation. Browser validation on 2026-06-01 confirmed that an explicit-seed open-deck game can move through coin toss, opening hands, Active choices, optional setup Bench, prize placement, setup completion, first-turn draw, first action window, refresh recovery, and a second viewer tab without direct database or IEx intervention. The viewer read model now exposes per-card rules-coverage status, attack/ability support counts, and named unsupported attack/ability/Trainer text summaries. The React board surfaces partial or unsupported card text with hand notices, card badges, card detail callouts, and a separate non-clickable `Pending card text` action group for visible unsupported commands while preserving hidden opponent hands. Mulligan/setup edge cases, richer random-choice facts, broader unsupported timing/cost semantics, broader generic mechanics, and benchmarked UI density/polish remain follow-up work.
- Later on 2026-06-01, a true two-independent-browser validation superseded the earlier single-context/second-tab gap for the currently supported open-deck setup/pass slice. Two separate browser contexts created/rejoined explicit-seed game `302a39ed-d15b-4fcb-8a13-80eb2eed71be`, completed coin toss, starting-player choice, opening Active choices, setup readiness, prize placement, setup completion, first-turn draw/action window, Player 1 `Pass`, reload recovery, and Player 2 Turn 2 action-window priority while preserving hidden opponent hands. Remaining milestone gaps are broader setup edge cases, richer random-choice facts, additional generic mechanics/card behavior, and the benchmarked card-table UI density/polish.
- Iteration 191 advanced the richer random/setup fact gap without changing public game visibility. Seeded games now resolve coin tosses through `Prizmo.TcgEngine.Rng.choice/3` using a stable `coin_toss:<caller>:<call>` context when `rng_seed` is present, so explicit-seed setup begins from reproducible engine-owned randomness instead of process RNG. Opening-hand, prize-placement, and turn-draw events now persist hidden card-move payloads with player, card, source zone, destination zone, and destination position. The viewer-scoped `GameView` still omits `rng_seed` and event payloads, preserving the current public/private read-model boundary while leaving enough persisted facts for engine regression checks and future replay/debug tooling.
- Iteration 192 closed the first mulligan/setup edge for arbitrary open decks. While setup is waiting for opening Active choices, a player with a drawn opening hand, no Active, and no Basic Pokémon in hand can now submit a server-authoritative `mulligan_opening_hand` command. The engine shuffles that hand back into the player's deck, redraws 7 cards, records an `opening_hand_mulligan` domain fact with stable seeded RNG context and hidden moved-card payloads, keeps `rng_seed` and event payloads out of viewer-scoped `GameView`, and exposes a compact React command rail button only to the affected viewer. This handles no-Basic redraws; official opponent compensation draws/reveal semantics remain future setup-edge work.
- Iteration 193 added the next official mulligan compensation slice without broadening hidden-zone visibility. Once both players have opening Active Pokémon and setup is in the Bench-choice window, a player can draw up to one optional bonus card per unresolved opponent `opening_hand_mulligan`. The engine derives mulligan and bonus counts from cursor-scoped domain events, writes a `mulligan_bonus_drawn` event/snapshot with hidden moved-card payloads, rejects overdraws, and exposes per-player `mulligans_taken`, `mulligan_bonus_draws_taken`, and `mulligan_bonus_draws_available` in the viewer read model. The React setup rail shows a compact draw button before setup-ready when bonus cards are available. Full no-Basic reveal presentation and browser validation of the mulligan path remain follow-ups.
- Iteration 194 added the public no-Basic reveal presentation layer for the mulligan setup path without exposing hidden payload internals. Viewer-scoped events now include `public_note`, `public_card_count`, and `public_revealed_cards` for `opening_hand_mulligan`, derived only from the previously revealed no-Basic hand's card identities/names/images/stages. They still omit raw event payloads, card instance IDs, deck positions, newly drawn cards, and RNG seed data. `mulligan_bonus_drawn` events also get a public count note. The React event history renders the reveal note and compact card thumbnails so the opponent can verify the no-Basic hand from the normal play surface. Two-independent-browser validation of the full mulligan-plus-bonus flow remains a follow-up.
- Iteration 195 closed that two-independent-browser validation gap for the supported no-Basic mulligan plus compensation-draw path. Two isolated browser contexts drove explicit-seed open-deck game `762faa63-a747-430a-ab00-b4ce3b59158a` from pasted decklists through coin toss, starting-player choice, Player 1 no-Basic mulligan, public seven-card Drakloak reveal in both event histories, Player 1 Dreepy Active choice, Player 2 Abra Active choice, Player 2 one-card mulligan bonus draw, both setup-ready commands, prize placement, setup completion, Turn 1 action-window entry, and reload recovery. Browser automation reported zero console errors, page errors, or non-font failed requests. SQL and read-model checks confirmed the 17-event sequence, explicit seed metadata, viewer-safe public reveal/bonus notes, hidden raw payloads/RNG seed, and hidden opponent hands. The validation used intentionally artificial deterministic decklists to force the setup edge and was kept as a regression/playtest artifact; the wrong-seed exploratory game was deleted with SQL verification.
- Iteration 196 closed a Special Energy safety gap for arbitrary open decks without claiming full card-effect support. `Prizmo.TcgEngine.CardCatalog` now infers `[:colorless]` Energy provision from committed Special Energy metadata that says it provides `{C}` Energy, so cards such as Enriching Energy and Mist Energy can pay generic Colorless attack costs once attached. Viewer-scoped card summaries now include named `energy` unsupported-action entries for Special Energy raw text, and the action affordance read model emits blocked `unsupported_energy` entries in the existing `Pending card text` rail for visible Special Energy text. This keeps generic attachment playable while making unsupported attachment restrictions, prevention effects, and on-attach effects explicit instead of silent. At that point, Mist Energy prevention and Team Rocket's Energy attachment restrictions still remained future card-behavior work.
- Iteration 197 turned the first Special Energy text from pending into executable Ash-engine behavior. Enriching Energy (`SSP-191`) now has an authored behavior overlay, and the generic `attach_energy` command applies its attach-from-hand draw-4 effect server-side, writing a separate `energy_attach_effect_drawn` domain fact/snapshot with hidden moved-card payloads plus a viewer-safe public event note. Its visible card summary now reports `engine_defined` with no unsupported-action entries and no blocked `unsupported_energy` affordance, while still preserving pending visibility for other unsupported Special Energy text. Validation used a rollback-only in-progress fixture scenario to prove the command path, event payload, hand count, public note, and read-model status without changing durable playtest games.
- Iteration 198 closed the next Special Energy mismatch between committed behavior overlays and the Ash engine. Mist Energy (`TEF-161`) now attaches through the normal generic Energy command, is treated as engine-defined in the viewer read model, and prevents opponent attack effects currently routed through Ash effect-prevention hooks from affecting the attached Pokémon while still allowing attack damage. Team Rocket's Energy (`DRI-182`) now attaches only to Team Rocket's Pokémon through the server command and keeps its existing two-unit Psychic/Darkness attack-cost provider semantics; illegal attachment rolls back with an explicit `:team_rocket_energy_requires_team_rocket_pokemon` error. Both cards no longer show `unsupported_energy` pending-text affordances when their supported text is visible. Rollback validation confirmed Mist attachment/read-model status, Team Rocket legal attachment/read-model status, Team Rocket illegal attachment rejection, and Mist preventing Munkidori's `Mind Bend` Confusion while preserving 60 damage.
- Iteration 199 made the next provider-only Special Energy slice safer for arbitrary open decks. `Prizmo.TcgEngine.CardCatalog` now infers typed Special Energy providers from committed TCGdex text shaped like `it provides {G} Energy` / `it provides {P} Energy`, so Growing Grass Energy (`POR-086`) can pay Grass or Colorless costs and Telepathic Psychic Energy (`POR-088`) can pay Psychic or Colorless costs after attachment. Their unresolved HP/search text remains explicitly pending in the viewer read model and blocked `unsupported_energy` affordances, but generic attachment no longer rolls back solely because those behavior overlays are not fully executable yet.
- Iteration 200 moved the next high-frequency Trainer search effects onto the generic Ash engine play-card path. Buddy-Buddy Poffin (`TEF-144`) and Poké Pad (`POR-081`) now have engine card definitions instead of pending Trainer-only read-model status. The generic `play_card` flow supports no-cost Trainers, min/max search choices, deck-search filters for Basic Pokémon with 70 HP or less and non-rule-box Pokémon, hand or Bench destinations, and prompt max counts capped by current Bench space. Poffin now discards, prompts for `search_deck_for_basic_pokemon_to_bench`, benches selected legal targets, records shuffle/completion events, and completes the pending effect; Poké Pad can resolve a non-rule-box Pokémon search to hand. The React prompt submit copy recognizes both new choice keys. Rollback validation covered engine/read-model behavior without changing durable playtest games.
- Iteration 201 moved Boss's Orders (`MEG-114`) onto the same generic Ash engine `play_card` path as the recent Trainer work. Boss is now an engine-defined Supporter, appears as a normal Play affordance when the opponent has a Bench, discards/marks the Supporter through generic Trainer handling, prompts for `switch_opponent_bench_to_active`, exposes only public opponent Bench cards as legal prompt choices, switches the opponent Active with the selected Bench Pokémon, and completes the pending effect without a deck shuffle. This turns a high-frequency gust effect already present in battle logs and fixtures into product-path behavior instead of a hidden direct mechanics helper.
- Iteration 202 moved Lillie's Determination (`MEG-119`) onto the generic Ash engine `play_card` path as a no-choice Supporter shuffle/draw effect. The engine now discards/marks the Supporter through generic Trainer handling, shuffles the player's remaining hand into their deck with engine-owned RNG when `rng_seed` is present, records hidden hand-to-deck and deck-to-hand moved-card payloads plus a `deck_shuffled` fact with RNG metadata but no seed, draws 8 cards while the player has exactly 6 Prizes remaining and 6 otherwise, and completes without prompts. The viewer read model now treats Lillie as engine-defined and exposes it as a normal Play source instead of pending Trainer text while preserving hidden opponent hands.
- Iteration 203 moved Judge (`POR-076`) onto the generic Ash engine `play_card` path as a no-choice both-player shuffle/draw Supporter. The engine now supports `shuffle_each_player_hand_into_deck_then_draw`, validates every affected player can draw the required cards after shuffling before mutating state, discards/marks Judge through generic Trainer handling, shuffles each player's hand into their own deck with per-player seeded RNG contexts, draws 4 cards for each player, and records per-player hidden moved-card payloads plus `deck_shuffled` facts with RNG algorithm/context/source but no `rng_seed`. The viewer read model treats Judge as engine-defined, exposes it as a Play source, and still preserves hidden opponent hands after the effect.
- Iteration 204 moved Enhanced Hammer (`TWM-148`) onto the generic Ash engine `play_card` path as a deterministic Item answer to Special Energy. Enhanced Hammer is now engine-defined when an opponent has an attached Special Energy, discards through the existing no-cost Trainer flow, prompts for exactly one opponent attached Special Energy, exposes that public attached card in the viewer prompt payload, rejects Basic Energy submissions, discards the selected Special Energy to its owner's discard pile while clearing its attachment, and completes through the normal effect/card-play event sequence. This makes a high-frequency Item from supported fixtures playable without broadening hidden-zone visibility or implementing coin-gated Hammer effects.
- Iteration 205 generalized the existing `search_deck` Trainer effect enough to support multi-category required searches, then moved Dawn (`PFL-087`) and Hilda (`WHT-084`) onto the generic Ash engine `play_card` path. Search effects can now expose one prompt over a combined legal-choice pool while requiring selected cards to satisfy exact category groups before resolution. Dawn requires one Basic, one Stage 1, and one Stage 2 Pokémon and moves them to hand; Hilda requires one Evolution Pokémon and one Energy card and moves both to hand. Both Supporters discard/mark through generic Trainer handling, record normal hidden deck-to-hand payloads plus `deck_shuffled` and completion facts, appear as engine-defined Play sources only when their required groups are available, and no longer surface as pending Trainer text in the viewer read model.
- Iteration 206 moved Energy Switch (`MEG-115`) onto the generic Ash engine `play_card` path as an Item that moves one attached Basic Energy between the active player's own Pokémon. The engine now exposes a `move_basic_energy_between_own_pokemon` prompt only when a valid source Energy and different target Pokémon exist, labels the prompt choices as source/target roles for the React surface, revalidates the exact one-Energy/one-Pokémon selection at resolution, reparents the Energy attachment without consuming the once-per-turn manual attachment, records an attached-to-attached move payload, and treats Energy Switch as engine-defined instead of pending Trainer text.
- Iteration 207 moved Night Stretcher (`ASC-196`) onto the generic Ash engine `play_card` path as an Item discard-recovery effect. The engine now exposes a `recover_pokemon_or_basic_energy_from_discard` prompt only when the active player has an own Pokémon or Basic Energy card in discard, excludes invalid discard cards such as Trainers, discards Night Stretcher through the normal no-cost Trainer flow, moves the selected discard card to hand, records a generic discard-to-hand move payload, completes the pending effect/card-play sequence, and treats Night Stretcher as engine-defined instead of pending Trainer text.
- Iteration 208 moved Crispin (`SCR-133`) onto the generic Ash engine `play_card` path and tightened Trainer search-shuffle correctness. Generic `search_deck` Trainer effects now physically reorder the remaining deck with engine-owned RNG before writing `deck_shuffled`, using stable seeded `trainer_effect_shuffle:<player>:turn_<n>:<card_id>:<effect_key>` contexts and preserving the no-`rng_seed` viewer/event boundary. Crispin is an engine-defined Supporter that requires two Basic Energy cards of different types in deck plus one own in-play Pokémon target, discards/marks the Supporter, moves the first selected Energy to hand, attaches the second from deck without spending the manual once-per-turn Energy attachment, records deck-to-hand/deck-to-attached move payloads, shuffles the remaining deck, and exposes React prompt copy/labels that make the selection order explicit. Partial one-Energy Crispin use remains intentionally unsupported in this first slice.
- Iteration 209 moved Rare Candy (`MEG-125`) onto the generic Ash engine `play_card` path as a bounded Item evolution shortcut. The engine now recognizes cached Stage 2 → Stage 1 → Basic ancestry, exposes a two-card prompt only when a compatible Stage 2 is in hand and an eligible Basic Pokémon in play can evolve under first-turn/this-turn restrictions, discards Rare Candy through the normal Trainer flow, evolves the Stage 2 into the Basic's Active or Bench slot while preserving damage and reparenting attachments, moves the Basic under the evolution, records a card-move payload, completes the pending effect/card-play sequence, and surfaces Rare Candy-specific prompt labels/copy in the React prompt UI. This covers the normal Basic-to-Stage-2 shortcut, not every evolution-related Ability that may trigger when a Pokémon evolves.
- The temporary Phoenix channel and temporary TCG SPA route were removed.
- The old `Prizmo.Tcg.Sim` reducer still exists as legacy/reference code and still has tests, but it is no longer the canonical engine target.
- Recent iterations have repeatedly advanced one long-lived preseeded playtest game. That game remains useful for engine-correctness validation, regression checks, UI smoke tests, and incremental mechanic work. It is not the final product target by itself. North-star work should keep moving the system toward open-deck, RNG-backed game creation plus card-first UI density, while still using fixtures whenever they are the best way to prove correctness.

## Product north star

The first playable product surface should be an experienced-player React SPA game client over the Ash-backed engine, not a debug-first test harness or rules tutorial.

It should let two humans:

1. create or join a game from decklists rather than only hand-picked fixtures;
2. complete normal RNG-backed setup, including shuffling, opening hands, prizes, mulligan-relevant state, and initial Active or Bench choices where supported;
3. see each player's public board, discard, prizes remaining, deck count, turn state, and legal action affordances;
4. see the current player's private hand and prompts with compact card imagery;
5. submit commands through Phoenix/Ash actions;
6. resolve prompts and pending effects;
7. watch a chronological event log without raw payload noise in the normal play path;
8. refresh or reconnect without losing game state or the random sequence history.

### Open-deck and RNG expectations

- The normal product path should accept arbitrary decklists that can be resolved through the committed card catalog. Fixture-only game creation remains valid for tests, regression, demos, and narrow mechanic validation, but it is not sufficient as the final product path.
- "Playable by any deck" means any valid decklist should load, validate, shuffle, set prizes, draw opening hands, and enter normal setup or play without crashes. Complete executable behavior for every card remains incremental. Unsupported effects must be visible as unsupported or unavailable actions, never silent no-ops.
- Setup and draws must use engine-owned RNG. Preseeded hands, scripted prize maps, and manually ordered draws are only acceptable in explicit tests, demos, or replay fixtures.
- RNG must be persisted enough for trust and replay. Store the game seed or equivalent random source metadata, record shuffle and random-choice domain facts, and make seeded test runs deterministic while production-like games default to fresh randomness.
- The database remains the source of truth. Clients never pick hidden-zone order, prize placement, or random outcomes locally.

### Experienced-player card table expectations

The UI should assume users know Pokémon TCG. It should show what they can do, not explain the game at length. Keep teaching copy, raw IDs, debug counters, payloads, and diagnostic controls out of the normal play path.

Use card imagery aggressively and efficiently:

- Card fronts for visible hand cards, Active, Bench, discard top, revealed cards, selected prompt options, and detail previews.
- Pokémon card backs for face-down prizes, decks, hidden opponent hand cards, unrevealed search results, and any other hidden physical card representation.
- Compact, high-density hand presentation that avoids large empty scroll regions. Large hands should fan, overlap, scale, wrap, or open a focused tray instead of wasting vertical space.
- Zones should be spatial and instantly legible: opponent side, player side, Active, Bench, Stadium, prizes, deck, discard, Lost Zone if added, and action/prompt rail.
- Legal actions should be compact affordances attached to the relevant cards or zones where possible. A separate action list is acceptable as a fallback, not as the dominant board.
- The layout should be visually appealing and serious, aligned with [The Tournament Instrument](../../../DESIGN.md), but not a PTCGL clone. PTCGL is a useful interaction-quality reference, while Prizmo should stay denser, calmer, and more useful for competitive practice.

### UI benchmark requirement

Before a substantial UI layout or polish batch, perform and record a short benchmark pass in the wiki or the batch log. The benchmark should inspect at least:

1. one Pokémon-specific digital reference such as PTCGL;
2. one physical or tabletop Pokémon TCG layout reference such as tournament table coverage, Limitless-style deck/play records, or high-quality gameplay videos;
3. one other digital TCG reference such as Magic Arena, Hearthstone, Yu-Gi-Oh Master Duel, Marvel Snap, or another relevant client.

Extract concrete layout lessons: board geometry, hand density, card scale, face-down card treatment, action affordance placement, prompt presentation, opponent information, and how much explanatory copy is present. Then state what Prizmo will adopt or reject before editing the UI.

Validation target: the playable loop should be testable by two independent browser sessions, each controlling one player. A milestone is not considered playtest-ready until those two browser sessions can create an RNG-backed game from decklists, complete the supported setup path, perform supported actions through the UI, and recover after refresh without direct database, IEx, or test-helper intervention.

## Engine principles

- The Ash engine is the write authority.
- UI clients submit commands; they do not mutate game state locally.
- Events are domain facts, not internal execution plans.
- Prompts and pending effects are explicit continuations.
- Hidden information is never published to a public view or public stream.
- Card rules stay separate from UI visualization/action affordances.
- Static metadata comes from the committed TCGdex cache; executable behavior is Prizmo-authored.
- Effects should remain data-first with explicit module/function fallback for unusual cards.
- Hooks should use explicit `{Module, function}` callbacks and phase-specific contexts.
- Randomness is engine-owned, persisted, and replayable. Tests can provide seeds, but product play should not depend on pre-arranged draws.
- Deck support expands from generic setup and generic mechanics outward. Unsupported card effects should block or degrade explicitly instead of preventing deck loading.

## Stream north star: Electric Streams as a candidate game-data feed

Source notes: [Electric Streams documentation notes](../../raw/engine/2026-05-30-electric-streams-docs.md).

Electric Streams is a strong candidate for the game-data stream because it provides append-only durable streams, offset-based replay, browser-friendly SSE, JSON message mode, and idempotent producer support.

The preferred architecture to explore:

```text
React SPA command -> Phoenix/Ash action -> Postgres transaction
                                      -> persisted GameEvent/GameSnapshot
                                      -> idempotent stream append after commit
React SPA view    <- Electric JSON stream catch-up/SSE tail
React SPA refresh <- Ash read model or stream replay from saved offset
```

Important boundary: Electric should be a delivery and replay layer, not the rules authority. The database remains the durable source of truth for commands, validation, prompts, and hidden state.

### Candidate stream shape

- One game stream per game for public facts and public board deltas.
- Optional per-player private streams for private hand, hidden-zone outcomes, and prompts.
- JSON mode for structured messages.
- One message per committed domain event, or one batched array per engine transaction.
- Event payload includes at least `game_id`, event sequence, event type, actor/player if applicable, visibility, and a stable reference to the persisted `GameEvent`.
- Browser consumers catch up from `offset=-1`, then tail with SSE.
- Clients store the last `Stream-Next-Offset` and resume from it on reconnect.

### Why this is promising

- Playtest clients can reconnect and replay without a custom WebSocket replay protocol.
- Event streams match the engine's existing domain-fact event direction.
- SSE fits the first React SPA better than rebuilding the temporary channel stack.
- Idempotent producers give a path for safe retry when publishing database events to streams.
- Historical stream reads can support debugger, replay, and coaching tools later.

### Risks to validate before adopting

- Hidden-information filtering must be exact and tested.
- The database-to-stream bridge must be idempotent and observable.
- Stream append timing must not expose rolled-back events.
- Local development needs a reliable durable-streams server or adapter.
- Cloud/auth integration must not leak stream URLs or private player streams.
- Retention policies must preserve enough history for replay/debugging.
- Durable State/StreamDB may not match domain-event semantics; avoid adopting them until a simple JSON event stream spike is proven.

## Immediate implementation plan

### 1. Keep the north star distinct from the next step

- The north star describes the target product experience, not a ban on fixture-driven or scripted validation work.
- Preseeded fixtures, deterministic seeds, current-game handoffs, and narrow scenario tests are allowed and often desirable when they prove engine correctness, prevent regressions, or validate a UI path.
- When choosing between similarly feasible tasks, prefer coherent batches that advance arbitrary deck loading, RNG-backed setup, card-front/card-back rendering, hand density, benchmarked board layout, or generic mechanics that make arbitrary decks safer.
- If the highest-value feasible step is another fixture-backed mechanic or current-game validation, do it, but record why it moves the north star or protects correctness.

### 2. Build open-deck RNG game creation

- Add or harden decklist ingestion for normal game creation. Decks should resolve through `Prizmo.TcgEngine.CardCatalog` and report unresolved cards clearly.
- Validate deck shape enough for supported play: deck size, recognizable card records, Basic Pokémon availability for setup, and copy-limit warnings or errors as appropriate.
- Keep the optional explicit RNG seed path available for tests and reproducible dev runs, and expose it cleanly from the browser decklist-entry surface when useful.
- Continue expanding persisted random/setup facts beyond the current per-player `deck_shuffled` facts, especially mulligans, prize placement, and any later random choices.
- Replace any remaining product-path preseeded hands and scripted prize maps with the existing engine-owned shuffled deck order, opening hand draw, prize placement, and top-deck order.
- Validate setup end-to-end from open decklists: different fresh seeds should produce different hands/prizes, while the same explicit seed is deterministic.

### 3. Make any loaded deck safe to start

- Allow decklists with incomplete card behavior to enter setup when their metadata is known.
- Keep generic mechanics available across decks: draw for turn, bench Basic Pokémon, attach Energy, evolve when metadata supports it, retreat, pass, damage, KO, prize-taking, and replacement Active.
- Track unsupported actions explicitly in legal affordances, logs, and card detail views. Unsupported behavior should be a visible product state, not a crash or silent fallback.
- Expand behavior manifests card-by-card after the generic arbitrary-deck path is trustworthy.

### 4. Benchmark and rebuild the card table UI

- Before changing layout, record a short benchmark pass as described above.
- Replace text-heavy zone placeholders with reusable card-surface components using real card fronts and Pokémon card backs.
- Rework prizes, deck, discard, opponent hand, player hand, Active, and Bench to use card scale and spatial hierarchy efficiently.
- Fix hand density so large hands remain playable without long scrolling through white space.
- Move explanatory copy out of the main board. Use compact labels, icons, hover/focus detail, and card-attached actions for players who already know the game.
- Keep diagnostics available outside the normal play path for agents and debugging.

### 5. Expand core engine mechanics

Port or reimplement the old simulator's valuable rules into `Prizmo.TcgEngine` in small verified slices:

- draw for turn;
- bench Basic Pokémon;
- attach one Energy per turn;
- evolve with timing restrictions;
- retreat and switch;
- attack declaration, cost validation, damage, KO, prizes, and replacement Active;
- end turn and turn start effects;
- mulligan handling and setup edge cases for arbitrary decklists;
- undo/debug support through snapshots, not client-side state mutation.

### 6. Migrate card behavior to engine definitions

- Keep `Prizmo.TcgEngine.Cards.Registry` as the behavior registry for engine-playable cards.
- Use the catalog only for static metadata and metadata-backed predicates.
- Convert old simulator-specific card actions into generic costs, effects, operations, prompts, and hooks.
- Track unsupported behavior explicitly instead of silently falling back.

### 7. Spike Electric Streams

- Run a local durable-streams server in development.
- Publish committed `GameEvent` records for one game into a JSON stream.
- Add a small React subscriber that catches up from `-1` and tails with SSE.
- Verify reconnect/resume using saved offsets.
- Verify duplicate-publish retry behavior with an idempotent producer strategy.
- Verify a public/private stream split for hidden information before using streams for real playtests.

## First milestone definition of done

The first milestone is complete when two humans can create and play a supported slice from decklists through the browser UI without touching IEx or tests:

- each player can provide or select a decklist that is not a hand-ordered draw fixture;
- game creation persists player decklists and engine-owned RNG metadata;
- setup uses RNG-backed shuffle, opening hands, prize placement, and setup choices where supported;
- repeated fresh games can produce different hands/prizes, and explicit seeded games are reproducible for tests;
- both players can see correct public/private views with card fronts and card backs for the major physical card zones;
- loaded decks with unsupported card behavior do not crash setup or generic play. Unsupported actions are clearly blocked or marked;
- core generic actions work through the UI for supported cards and states;
- legal actions are compact and visible without tutorial-style explanations dominating the board;
- hand, prize, deck, discard, Active, and Bench layout is benchmarked and space-efficient enough for real play;
- turn transitions and command blocking are enforced;
- events and snapshots are persisted;
- the UI can reconnect and recover current state;
- validation can be run by two browser sessions playing as separate players;
- the normal browser surface reads as a competitive card table, not a debug bench;
- `mix check` passes.

## Non-goals for the first milestone

- Full Standard support.
- AI opponent.
- Mobile-native renderer.
- Production-grade card animation, foil, tilt, or 3D renderer effects.
- PTCGL log import/replay.
- Replacing Ash/Postgres persistence with streams.
- Full executable behavior for every card in arbitrary imported decklists.
- Teaching new players how Pokémon TCG works inside the main play surface.

## Key decisions captured

- Canonical rules engine: `lib/prizmo/tcg_engine/`.
- Near-term product target: arbitrary decklist game creation with engine-owned persisted RNG, plus a card-first experienced-player React SPA playtest UI.
- Stream direction: explore Electric Streams for durable event delivery/replay, with Ash/Postgres remaining authoritative.
- Legacy simulator: reference only until useful scenarios are ported or deleted.
- UI transport: do not revive the temporary Phoenix channel unless Electric or plain HTTP/SSE spikes fail.
- UI layout work must benchmark Pokémon TCG and other TCG table layouts before substantial polish batches.

## See Also

- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [Meta Deck, TCGdex, Card DSL, and LiveView Play North Star](meta-deck-card-dsl-north-star.md)
- [Full-Game Two-Deck Simulator Implementation](full-game-two-deck-simulator-implementation.md)
- [TCG Client Renderer Options](tcg-client-renderer-options.md)

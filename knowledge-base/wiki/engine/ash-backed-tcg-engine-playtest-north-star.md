# Ash-backed TCG Engine and Playtest UI North Star

Updated: 2026-05-30

## Scope

This is the current north star for Prizmo's Pokémon TCG work: an Ash-backed, server-authoritative rules engine plus a playable browser UI for two-human playtesting.

The goal is not yet a complete Standard simulator, AI opponent, polished renderer, or post-game coach. The near-term goal is a tight loop where supported card behavior can be implemented, played through the UI, observed as events, and corrected quickly.

## Current baseline

- `lib/prizmo/tcg_engine/` is the canonical engine path.
- The engine is persisted with Ash resources for games, players, turns, card instances, prompts, pending effects, setup, game events, and snapshots.
- Card play is generic and registry-driven for the first Ultra Ball-style flow, including costs, effects, prompts, pending continuations, and domain-fact events.
- `Prizmo.TcgEngine.CardCatalog` now owns the engine catalog boundary. It builds catalog records from committed TCGdex metadata plus authored behavior manifests instead of delegating to `Prizmo.Tcg.Sim.CardRegistry`.
- The temporary Phoenix channel and temporary TCG SPA route were removed.
- The old `Prizmo.Tcg.Sim` reducer still exists as legacy/reference code and still has tests, but it is no longer the canonical engine target.

## Product north star

The first playable product surface should be a thin React SPA playtest client over the Ash-backed engine.

It should let two humans:

1. create or join a game with supported deck fixtures;
2. complete setup;
3. see each player's public board, discard, prizes remaining, turn state, and legal action affordances;
4. see the current player's private hand and prompts;
5. submit commands through Phoenix/Ash actions;
6. resolve prompts and pending effects;
7. watch a chronological event log;
8. refresh or reconnect without losing the game state.

This UI is for playtesting engine correctness first. Visual polish and advanced renderer choices are secondary until the command/event loop feels reliable.

Validation target: the playable loop should be testable by two independent manual-tester subagents, each controlling a separate Playwright browser instance as one player. A milestone is not considered playtest-ready until those two browser sessions can complete the target scenario through the UI without direct database, IEx, or test-helper intervention.

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

### 1. Remove remaining legacy coupling from engine tests

- Move supported deck fixtures out of `Prizmo.Tcg.Sim.Decks` into an engine-owned or shared deck namespace.
- Update `test/prizmo/tcg_engine/mechanics_test.exs` to stop aliasing `Prizmo.Tcg.Sim.Decks.*`.
- Decide whether old simulator tests are kept as historical reference, quarantined, or ported scenario-by-scenario.

### 2. Build the minimal playable loop

- Expose game creation from supported deck fixtures.
- Expose setup commands through Ash/Phoenix endpoints.
- Expose legal action affordances from engine state and prompt state.
- Implement choose-prompt UI for pending effects.
- Render a simple public board, active Pokémon, bench, hand, deck count, discard, prizes remaining, current turn, and event log.
- Prioritize correctness and debuggability over animation.

### 3. Expand core engine mechanics

Port or reimplement the old simulator's valuable rules into `Prizmo.TcgEngine` in small verified slices:

- draw for turn;
- bench Basic Pokémon;
- attach one Energy per turn;
- evolve with timing restrictions;
- retreat and switch;
- attack declaration, cost validation, damage, KO, prizes, and replacement Active;
- end turn and turn start effects;
- undo/debug support through snapshots, not client-side state mutation.

### 4. Migrate card behavior to engine definitions

- Keep `Prizmo.TcgEngine.Cards.Registry` as the behavior registry for engine-playable cards.
- Use the catalog only for static metadata and metadata-backed predicates.
- Convert old simulator-specific card actions into generic costs, effects, operations, prompts, and hooks.
- Track unsupported behavior explicitly instead of silently falling back.

### 5. Spike Electric Streams

- Run a local durable-streams server in development.
- Publish committed `GameEvent` records for one game into a JSON stream.
- Add a small React subscriber that catches up from `-1` and tails with SSE.
- Verify reconnect/resume using saved offsets.
- Verify duplicate-publish retry behavior with an idempotent producer strategy.
- Verify a public/private stream split for hidden information before using streams for real playtests.

## First milestone definition of done

The first milestone is complete when two humans can play a narrow supported scenario through the browser UI without touching IEx or tests:

- game setup completes;
- both players can see correct public/private views;
- at least one generic Trainer prompt flow works end-to-end;
- turn transitions and command blocking are enforced;
- events and snapshots are persisted;
- the UI can reconnect and recover current state;
- validation can be run by two subagents playing as separate players in two Playwright browser instances;
- `mix check` passes.

## Non-goals for the first milestone

- Full Standard support.
- AI opponent.
- Mobile-native renderer.
- High-polish card animations.
- PTCGL log import/replay.
- Replacing Ash/Postgres persistence with streams.

## Key decisions captured

- Canonical rules engine: `lib/prizmo/tcg_engine/`.
- Near-term product target: playable React SPA playtest UI.
- Stream direction: explore Electric Streams for durable event delivery/replay, with Ash/Postgres remaining authoritative.
- Legacy simulator: reference only until useful scenarios are ported or deleted.
- UI transport: do not revive the temporary Phoenix channel unless Electric or plain HTTP/SSE spikes fail.

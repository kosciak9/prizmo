# Prizmo TCG Engine and Play Surface North Star

- Updated: 2026-06-17
- Sources: Project codebase; local validation; wiki log; user direction; Electric documentation (2026-05-30)
- Raw: [Electric Streams documentation notes](../../raw/engine/2026-05-30-electric-streams-docs.md)

## Purpose

This is the canonical current goal page for Prizmo's Pokémon TCG work. A new agent with no prior context should read this page first, understand the goal order, and choose work that moves the project toward the next milestone.

Prizmo is building a server-authoritative competitive Pokémon TCG practice engine. The immediate work is not post-game coaching, six-deck-first fixture expansion, browser-first product UX, Electric Streams, AI opponents, or all-card support. The immediate work is latest-Limitless competitive card coverage, server-side game resolution, and a better play surface.

## Canonical goal ladder

### Goal 1 — Dragapult + Alakazam latest-Limitless completeness

Support all latest Limitless variants for both Dragapult and Alakazam.

Done means:

- the current latest Limitless Dragapult and Alakazam variant universe is inventoried;
- every card, ability, attack, setup path, and rule interaction required by those variants is classified;
- every target card is engine-defined, deliberately generic-supported, or explicitly tracked as a blocker;
- covered variants can play through the Ash engine and play surface without unsupported-card or visible `Pending card text` blockers;
- validation proves real game progress through setup, attaching, evolving, searching/drawing, Abilities, Trainers, attacks, KOs, prizes, replacement Active choices, and turn continuation where those variants require them.

### Goal 2 — Top 30 latest-Limitless archetype coverage

Support the complete card breakdown for the top 30 Limitless archetypes by usage, using the latest available Limitless data.

Done means:

- the top 30 archetypes by usage are identified from latest Limitless data;
- their complete card breakdown forms the coverage corpus;
- every card in that corpus with usage greater than `0.00` is tracked;
- each card/mechanic has a supported, partial, unimplemented, or unvalidated status;
- implementation priority favors cards/mechanics that unblock the most archetypes.

### Goal 3 — React shell + embedded Godot play surface

Move the in-game experience away from browser React as the final play surface. React remains the product shell; Godot becomes the actual play surface.

Responsibility split:

- **Server/Ash/Postgres:** canonical game state, rules, legal actions, prompts, pending effects, hidden information, RNG, persistence, and machine resolution.
- **React web shell:** deck selection, game selection, session setup, auth/account/product flows, overlays, and wrapper around the embedded play surface.
- **Temporary React browser play UI:** scaffolding/reference for protocol discovery and engine validation, not the long-term play experience.
- **Godot play surface:** board rendering, card interactions, targeting UX, animations, feedback, and play feel.

React and Godot clients consume a stable play protocol and emit commands. They must not reimplement rules.

### Goal 4 — Native mobile path

Move toward a native mobile product using React Native as the shell with embedded Godot as the play surface.

Goal 4 preserves the same architecture as Goal 3:

- React Native owns mobile product shell concerns.
- Embedded Godot owns in-game rendering and interactions.
- The server remains authoritative.
- The same play protocol is reused instead of adding mobile-only rules logic.

### Goal 5 — Complete card coverage

Expand beyond latest-Limitless/meta coverage to all possible cards.

This is intentionally after the competitive coverage, Godot play-surface, and native mobile pathway goals. Do not choose broad all-card work before it unblocks Goals 1 or 2 unless the user explicitly redirects.

## How agents should choose next work

### If working on Goal 1

1. Inspect latest Limitless Dragapult and Alakazam variants.
2. Update the coverage tracker with missing cards, missing mechanics, pending text, and validation state.
3. Implement missing behavior in `lib/prizmo/tcg_engine/` and related card behavior/registry modules, not in the client.
4. Add or update fixtures and tests that prove variants can progress without unsupported-card or pending-text blockers.
5. Validate through focused tests, rollback scenarios, or browser scaffolding when the UI path matters.

Useful questions:

- Which latest-Limitless Dragapult/Alakazam card is unimplemented or only partially implemented?
- Which blocker affects the most real variants?
- Does the live play surface still show `Pending card text` for a target card?
- Can a real player submit the required command through the current Ash/read-model path?

### If working on Goal 2

1. Determine the latest top 30 Limitless archetypes by usage.
2. Build the complete card corpus from those archetypes' card breakdowns.
3. Include every card in that corpus with usage greater than `0.00`.
4. Prioritize shared card primitives, high-frequency Trainers, common Energy/Tool/Stadium effects, and mechanics that unblock many archetypes.
5. Keep status explicit: `supported`, `generic-supported`, `partial`, `unimplemented`, or `unvalidated`.

### If working on Goal 3

1. Treat the current React browser game UI as temporary scaffolding.
2. Move card-specific and rules-specific decisions out of React and into server-provided prompts, legal actions, and view models.
3. Define or refine the shared play protocol consumed by both React scaffolding and Godot.
4. Keep Godot focused on rendering, interaction, animation, target selection, and feedback.
5. Keep React focused on product shell concerns around the play surface.

Good Goal 3 work reduces coupling in `lib/prizmo_web/spa/features/home/routes/index.tsx`, improves the `GameView`/affordance contract, or makes the protocol easier for Godot to consume.

### If working on Goal 4

1. Preserve the React shell/Godot play-surface split when moving to React Native.
2. Reuse the same server protocol.
3. Avoid mobile-only game logic.
4. Validate embedded Godot lifecycle, device performance, orientation/resizing, auth/session handoff, and bridge boundaries early.

### If working on Goal 5

Only broaden to all possible cards after the meta coverage and play-surface architecture goals are established, or when a supposedly broad primitive directly unblocks Goal 1 or Goal 2.

## Engine principles

- The Ash engine is the write authority.
- UI clients submit commands; they do not mutate game truth locally.
- Events are domain facts, not internal execution plans.
- Prompts and pending effects are explicit continuations.
- Hidden information is never published to a public view or public stream.
- Card rules stay separate from UI visualization/action affordances.
- Static metadata comes from the committed TCGdex cache; executable behavior is Prizmo-authored.
- Effects should remain data-first with explicit module/function fallback for unusual cards.
- Hooks should use explicit `{Module, function}` callbacks and phase-specific contexts.
- Randomness is engine-owned, persisted, and replayable. Tests can provide seeds, but product play should not depend on pre-arranged draws.
- Unsupported card effects should block or degrade explicitly instead of becoming silent client behavior.

## Coverage and validation terms

- **Latest Limitless data:** use current/latest Limitless archetype and deck/card breakdown data when building coverage targets, not a fixed historical snapshot.
- **Variant:** a materially distinct deck list within an archetype, usually identified by Limitless deck/list data and tech-card composition.
- **Coverage corpus:** the set of card IDs generated from a goal's latest Limitless source definition.
- **Supported:** executable through the canonical Ash engine path and usable through the play protocol where players need it.
- **Generic-supported:** covered by an intentional generic path sufficient for normal gameplay, such as Basic Energy attachment or plain damage.
- **Partial:** some behavior is executable but printed text, timing, targeting, or validation remains incomplete.
- **Unimplemented:** no executable server behavior yet.
- **Unvalidated:** believed implemented but not proven by tests, rollback scenarios, fixtures, or play-surface validation.

## Current canonical implementation path

- Engine: `lib/prizmo/tcg_engine/`.
- Server read model/protocol seed: `Prizmo.TcgEngine.GameView` and `Prizmo.TcgEngine.GameView.ActionAffordances`.
- Temporary browser scaffolding: `lib/prizmo_web/spa/features/home/routes/index.tsx`.
- Godot experiment area: `game/*` is reserved for explicit Godot work only.
- Legacy simulator: `lib/prizmo/tcg/sim/` is historical/reference code, not the canonical product path.

## Deferred or non-current directions

These may remain valuable, but they are not the immediate selection rule for autonomous agents:

- six-deck-first fixture coverage as the active north star;
- browser React as the final in-game play experience;
- post-game PTCGL log coaching as the current MVP;
- AI opponent work;
- Electric Streams adoption or stream-backed UI transport;
- broad all-card coverage before latest-Limitless competitive coverage;
- UI polish that does not unblock Goal 1, Goal 2, or Goal 3.

## Electric Streams note

Electric Streams remains a possible future delivery/replay layer because it can provide append-only durable streams, offset-based replay, browser-friendly SSE, JSON message mode, and idempotent producer support.

It is explicitly deferred. Electric should be a delivery and replay layer, not the rules authority. The database remains the durable source of truth for commands, validation, prompts, hidden state, and game resolution.

## See Also

- [Dragapult and Alakazam Full-Game Implementation Scope](dragapult-alakazam-full-game-implementation-scope.md)
- [Ash-backed TCG Engine Playtest Handoff](ash-backed-tcg-engine-playtest-handoff.md)
- [TCG Client Renderer Options](tcg-client-renderer-options.md)
- [Cross-Platform TCG Client Architecture](cross-platform-tcg-client-architecture.md)
- [Meta Deck, TCGdex, Card DSL, and LiveView Play North Star](meta-deck-card-dsl-north-star.md)

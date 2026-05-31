# Electric Streams documentation notes

- Source: Multiple Electric documentation pages listed below
- Collected: 2026-05-30
- Published: Unknown
- Type: direct documentation review
- Scope: candidate durable game-data stream for a server-authoritative TCG engine and browser playtest UI

## Sources

- Electric Streams overview: https://electric.ax/docs/streams/
- Electric Streams quickstart: https://electric.ax/docs/streams/quickstart
- TypeScript client: https://electric.ax/docs/streams/clients/typescript
- JSON mode: https://electric.ax/docs/streams/json-mode
- Durable State: https://electric.ax/docs/streams/durable-state

## Verified source notes

### Core stream model

Electric Streams is a hosted implementation of the open Durable Streams protocol. A stream is a URL-addressable, append-only, durable sequence. Producers append events with HTTP `POST`; consumers read with HTTP `GET` from an offset. Streams are ordered, durable, replayable, and cache-friendly.

The protocol supports:

- stream creation with `PUT`;
- appending with `POST`;
- catch-up reads with `GET ?offset=...`;
- metadata checks with `HEAD`;
- stream closure with `Stream-Closed: true`;
- deletion with `DELETE`.

Research implication: this maps naturally to a game event feed where a client can catch up from the beginning or resume from a stored offset.

### Offsets and replay

Every read returns a `Stream-Next-Offset` header. Offsets are opaque strings and should be stored as returned, not parsed. The sentinel offset `-1` reads from the beginning; `now` starts at the current tail.

Research implication: a playtest UI could store the last consumed offset per game tab/session and reconnect without needing bespoke replay protocol code.

### JSON mode

Streams created with `Content-Type: application/json` preserve message boundaries. Each `POST` stores one JSON message, and posting an array stores each element as its own message. `GET` returns a JSON array for the requested range.

Research implication: Prizmo game events can be appended as structured JSON messages, potentially batching all domain events emitted by one engine transaction.

### Live modes

Consumers can tail streams with long-polling or Server-Sent Events. SSE emits `data` events with payloads and `control` events with metadata such as next offset and up-to-date/closed status. Clients reconnect using the last next offset.

Research implication: SSE is a plausible first browser integration for a React SPA board because it gives real-time updates and replay/resume semantics with one HTTP primitive.

### TypeScript client

The `@durable-streams/client` package provides:

- `stream()` for fetch-like read-only consumption;
- `DurableStream` for create, append, read, close, and delete;
- `IdempotentProducer` for exactly-once writes with batching and retries;
- helpers for JSON streams and subscribers.

Research implication: the Volt React SPA can consume a game stream directly through a browser-friendly TypeScript client if authentication and stream URLs are handled safely.

### Idempotent producer support

Durable Streams supports exactly-once append retries using `Producer-Id`, `Producer-Epoch`, and `Producer-Seq` headers. The server deduplicates already accepted sequence numbers and fences stale epochs.

Research implication: an Ash/Phoenix event publisher can use the database event sequence or ID as producer sequence input to avoid duplicate stream appends after retry.

### Durable State

Durable State layers structured `insert`, `update`, and `delete` messages on JSON streams and can materialize client-side state from ordered changes. It is intended for database-style sync semantics on top of streams.

Research implication: this may be useful later for a materialized board-state stream, but the first TCG spike should likely use explicit domain-event JSON plus snapshots to avoid prematurely adopting a generic CRUD protocol for hidden-information game state.

## Fit for Prizmo TCG

Electric Streams is attractive as a delivery and replay layer, not as the rules authority. The Ash-backed engine should remain authoritative for commands, validation, hidden information, and persistence. Streams should publish committed facts or player-filtered view events after the database transaction succeeds.

Promising first shape:

- one public game stream per game for public events and visible board changes;
- optional per-player private streams for hand/deck/prize information and prompts;
- JSON messages keyed by `game_id`, event sequence, domain event type, and visibility;
- browser client catches up from `-1`, then tails with SSE;
- Phoenix remains the command endpoint for play actions.

Open risks:

- hidden-information filtering must be exact;
- the database-to-stream bridge needs idempotent, observable retry semantics;
- local dev and CI need either a self-hosted durable-streams server or a mock/protocol adapter;
- stream retention and game history retention policies must align;
- Electric Cloud credentials and stream URLs must not leak to unauthorized clients.

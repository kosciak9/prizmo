# Knowledge Base Index

## ptcgl
Official and community sources about Pokémon TCG Live as a gameplay data source for coaching.

| Article | Summary | Updated |
| --- | --- | --- |
| [PTCGL Match Data Sources](ptcgl/ptcgl-match-data-sources.md) | Official PTCGL surface plus community parsers/replay tools show that post-game log ingestion is realistic, but unofficial. | 2026-05-26 |
| [PTCGL Battle Log Observability](ptcgl/ptcgl-battle-log-observability.md) | Catalog of what raw battle logs reliably expose and what remains hidden. | 2026-05-26 |

## data
Structured APIs that can enrich logs with card, deck, and tournament context.

| Article | Summary | Updated |
| --- | --- | --- |
| [Card and Tournament Data Sources](data/card-and-tournament-data-sources.md) | Comparison of Pokémon TCG API, TopDeck, and TCGdex for card and event enrichment. | 2026-05-26 |
| [Integration Risk and Access Notes](data/integration-risk-and-access-notes.md) | Risk-ranked view of stable APIs versus community tooling and manual-only surfaces. | 2026-05-26 |

## engine
Research notes for possible future rules-engine, simulator, replay, and card-behavior work.

| Article | Summary | Updated |
| --- | --- | --- |
| [Open-Deck RNG TCG Engine and Card-First Playtest UI North Star](engine/ash-backed-tcg-engine-playtest-north-star.md) | Current north-star plan for arbitrary decklist game creation, persisted engine-owned RNG, an experienced-player card-table React UI, required TCG layout benchmarking, and the later Electric Streams game-data feed spike. | 2026-06-01 |
| [Ash-backed TCG Engine Playtest Handoff](engine/ash-backed-tcg-engine-playtest-handoff.md) | Current operational handoff for the long-lived Ash-backed TCG playtest game, including resume state, validation status, blockers, and the recommended next atomic task. | 2026-06-01 |
| [Card Engine Authoring Models](engine/card-engine-authoring-models.md) | Comparison of code-first, generated-stub, Elixir macro DSL, hybrid metadata/behavior, and coverage-tooling patterns for exact Standard-only PTCG card behavior. | 2026-05-27 |
| [Cross-Platform TCG Client Architecture](engine/cross-platform-tcg-client-architecture.md) | React web/RN app-shell architecture with embedded Godot as the shared gameplay renderer, including web, Android, and iOS integration risks. | 2026-05-28 |
| [Full-Game Two-Deck Simulator Implementation](engine/full-game-two-deck-simulator-implementation.md) | Implementation notes for the ExUnit-first state-machine simulator slice, including undo/redo snapshots and fixed Dragapult vs Alakazam deck skeletons. | 2026-05-28 |
| [Meta Deck, TCGdex, Card DSL, and LiveView Play North Star](engine/meta-deck-card-dsl-north-star.md) | Historical north-star plan for the old simulator-era deck/card DSL migration; superseded by the Ash-backed engine and playtest UI plan. | 2026-05-30 |
| [TCG Client Renderer Options](engine/tcg-client-renderer-options.md) | Renderer/client architecture options for a server-authoritative Pokémon-like TCG, with Godot 2D + GDScript as the strongest touch-first direction. | 2026-05-28 |

## meta
Competitive ecosystem references for decks, tournaments, and manual research.

| Article | Summary | Updated |
| --- | --- | --- |
| [Pokémon TCG Competitive Resource Map](meta/pokemon-tcg-competitive-resource-map.md) | Where to look for tournament history, deep event views, deck-building heuristics, and manual tools like TrainerHill. | 2026-05-26 |
| [Pokémon TCG Practice Tool Surface](meta/pokemon-tcg-practice-tool-surface.md) | Survey of existing Pokémon TCG practice, prep, guide, and community tool categories. | 2026-05-26 |

## product
Product and UX references for turning one played game into actionable improvement.

| Article | Summary | Updated |
| --- | --- | --- |
| [Companion and Session-Loop Patterns](product/companion-and-session-loop-patterns.md) | Companion-app patterns from poker, MTG Arena, and general gaming analytics tools. | 2026-05-26 |
| [Drill and Microtraining Patterns](product/drill-and-microtraining-patterns.md) | Daily-quiz, spaced-review, adaptive-task, and microtool patterns from other products. | 2026-05-26 |
| [First Coaching-Rule Taxonomy](product/first-coaching-rule-taxonomy.md) | First-pass rule categories and confidence guidelines for deterministic post-game coaching. | 2026-05-26 |
| [Learning-Science Patterns for Practice Tools](product/learning-science-patterns-for-practice-tools.md) | Retrieval, spacing, interleaving, and retrospective patterns applicable to practice products. | 2026-05-26 |
| [Post-Game Review Patterns](product/post-game-review-patterns.md) | Review patterns worth borrowing from mature game-analysis products. | 2026-05-26 |
| [Pokémon TCG Coach MVP](product/pokemon-tcg-coach-mvp.md) | A grounded MVP for post-game coaching using pasted/uploaded PTCGL logs plus enrichment APIs. | 2026-05-26 |
| [Pokémon TCG Practice Idea Bank](product/pokemon-tcg-practice-idea-bank.md) | Research-driven concept bank for faster, more effective Pokémon TCG practice modes. | 2026-05-26 |

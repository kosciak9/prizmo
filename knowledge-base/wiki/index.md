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
Canonical roadmap, server-authoritative TCG engine coverage, and React-shell/Godot-play-surface architecture.

| Article | Summary | Updated |
| --- | --- | --- |
| [Dragapult and Alakazam Latest-Limitless Coverage Scope](engine/dragapult-alakazam-full-game-implementation-scope.md) | Goal 1 scope: support all latest Limitless variants for Dragapult and Alakazam through server-side Ash engine behavior, explicit coverage status, and play-surface validation. | 2026-06-23 |
| [Goal 2 Top 30 Latest-Limitless Coverage Scope](engine/goal-2-top-30-latest-limitless-coverage-scope.md) | Goal 2 scope: current top-30 archetype list, first live 377-card corpus snapshot, and the highest-leverage shared blockers from the new Goal 2 reporting pipeline. | 2026-06-23 |
| [Prizmo TCG Engine and Play Surface North Star](engine/ash-backed-tcg-engine-playtest-north-star.md) | Canonical roadmap: Goal 1 is currently closed on known validation state; Goal 2 top 30 Limitless archetype coverage is the next autonomous priority; Goal 3 React shell + embedded Godot play surface; Goal 4 React Native mobile path; Goal 5 all possible cards. | 2026-06-23 |
| [Ash-backed TCG Engine Playtest Handoff](engine/ash-backed-tcg-engine-playtest-handoff.md) | Historical/operational handoff for prior two-deck and six-deck engine work; current agents should follow the canonical latest-Limitless/Godot roadmap instead. | 2026-06-23 |
| [Dragapult/Alakazam GameView Pending-Text Inventory (2026-06-16)](engine/dragapult-alakazam-gameview-pending-text-inventory-2026-06-16.md) | Authoritative live GameView pending-text inventory for the current north-star target decks (Dragapult 27431 variants + Alakazam 27147) confirming zero visible blockers after the plain-tech Supporter batch. | 2026-06-17 |
| [Card Engine Authoring Models](engine/card-engine-authoring-models.md) | Comparison of code-first, generated-stub, Elixir macro DSL, hybrid metadata/behavior, and coverage-tooling patterns for exact Standard-only PTCG card behavior. | 2026-05-27 |
| [Cross-Platform TCG Client Architecture](engine/cross-platform-tcg-client-architecture.md) | Goal 3/4 architecture: React web and React Native product shells wrap embedded Godot as the in-game play surface while the Ash/Postgres server remains authoritative. | 2026-06-17 |
| [Full-Game Two-Deck Simulator Implementation](engine/full-game-two-deck-simulator-implementation.md) | Implementation notes for the ExUnit-first state-machine simulator slice, including undo/redo snapshots and fixed Dragapult vs Alakazam deck skeletons. | 2026-05-28 |
| [Meta Deck, TCGdex, Card DSL, and LiveView Play North Star](engine/meta-deck-card-dsl-north-star.md) | Historical north-star plan for the old simulator-era deck/card DSL migration; superseded by the Ash-backed engine and playtest UI plan. | 2026-05-30 |
| [TCG Client Renderer Options](engine/tcg-client-renderer-options.md) | Renderer/play-surface direction: current React browser gameplay is temporary scaffolding; React/React Native shells should embed a Godot 2D play surface that consumes a server-authoritative protocol. | 2026-06-17 |

## meta
Competitive ecosystem references for decks, tournaments, and manual research.

| Article | Summary | Updated |
| --- | --- | --- |
| [Alakazam Competitive Intelligence](meta/alakazam-competitive-intelligence.md) | Durable Alakazam focus page for NAIC 2026 stats, hostile matchup mechanics, tech-card hypotheses, and future testing priorities. | 2026-06-16 |
| [Pokémon TCG Competitive Resource Map](meta/pokemon-tcg-competitive-resource-map.md) | Where to look for tournament history, deep event views, deck-building heuristics, and manual tools like TrainerHill. | 2026-05-26 |
| [Pokémon TCG Practice Tool Surface](meta/pokemon-tcg-practice-tool-surface.md) | Survey of existing Pokémon TCG practice, prep, guide, and community tool categories. | 2026-05-26 |

## product
Deferred product and UX references for post-game coaching and practice loops; useful later, but not the current engine/play-surface roadmap priority.

| Article | Summary | Updated |
| --- | --- | --- |
| [Companion and Session-Loop Patterns](product/companion-and-session-loop-patterns.md) | Companion-app patterns from poker, MTG Arena, and general gaming analytics tools. | 2026-05-26 |
| [Drill and Microtraining Patterns](product/drill-and-microtraining-patterns.md) | Daily-quiz, spaced-review, adaptive-task, and microtool patterns from other products. | 2026-05-26 |
| [First Coaching-Rule Taxonomy](product/first-coaching-rule-taxonomy.md) | First-pass rule categories and confidence guidelines for deterministic post-game coaching. | 2026-05-26 |
| [Learning-Science Patterns for Practice Tools](product/learning-science-patterns-for-practice-tools.md) | Retrieval, spacing, interleaving, and retrospective patterns applicable to practice products. | 2026-05-26 |
| [Post-Game Review Patterns](product/post-game-review-patterns.md) | Review patterns worth borrowing from mature game-analysis products. | 2026-05-26 |
| [Pokémon TCG Coach MVP](product/pokemon-tcg-coach-mvp.md) | Deferred product research for post-game coaching using pasted/uploaded PTCGL logs plus enrichment APIs; not the current engine/play-surface priority. | 2026-06-17 |
| [Pokémon TCG Practice Idea Bank](product/pokemon-tcg-practice-idea-bank.md) | Research-driven concept bank for faster, more effective Pokémon TCG practice modes. | 2026-05-26 |

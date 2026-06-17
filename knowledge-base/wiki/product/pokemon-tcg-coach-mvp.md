# Pokémon TCG Coach MVP

- Updated: 2026-06-17
- Sources: The Pokémon Company International (Unknown); kagd (Unknown); exinmusic (Unknown); Pokémon TCG API (Unknown); TopDeck.gg (Unknown); TCGdex (Unknown); Chess.com (2025-05-06); JustInBasil (Unknown)
- Raw: [Pokémon TCG Live](../../raw/ptcgl/2026-05-26-pokemon-tcg-live-overview.md); [Pokémon TCG Battle Replay Parser](../../raw/ptcgl/2026-05-26-pokemon-tcg-battle-replay-parser-readme.md); [Pokémon TCG battle replay sample log](../../raw/ptcgl/2026-05-26-pokemon-tcg-battle-replay-sample-log.md); [Pokémon TCG API docs](../../raw/data/2026-05-26-pokemon-tcg-api-docs.md); [TopDeck.gg API – Tournaments V2](../../raw/data/2026-05-26-topdeck-tournaments-v2-docs.md); [TCGdex API docs](../../raw/data/2026-05-26-tcgdex-api-docs.md); [Chess.com Game Review](../../raw/product/2025-05-06-chesscom-game-review.md); [JustInBasil deck-building guide](../../raw/meta/2026-05-26-justinbasil-deck-building-guide.md)

## Summary

Status: deferred product direction. This remains useful product research, but it is not the current roadmap priority. The active roadmap is latest-Limitless server-side TCG engine coverage, then React shell + embedded Godot play surface, then React Native mobile path, before broad all-card support. Post-game PTCGL coaching can return after those foundations are stronger.

The most grounded MVP is a post-game coach built around pasted/uploaded PTCGL logs. It should parse one match, surface only the most important turns, explain a small number of findings, and end with one practice habit or drill.

## Inputs

- required: raw PTCGL battle log text
- optional: player's deck, opponent deck/archetype, event/matchup notes

## Core pipeline

1. Parse the log into turns and structured actions.
2. Build partial state snapshots from public information.
3. Run deterministic rule checks on visible mistakes.
4. Enrich cards and decks via Pokémon TCG API / TCGdex.
5. Add matchup/meta context from TopDeck when useful.
6. Use an LLM to explain findings and answer follow-up questions, but not to invent hidden state.

## Best first rule families

Grounded in the observability limits and coaching categories in the ingested sources:

- missed visible KO or lethal
- redundant gust / overpay for same outcome
- sequencing problems around search, draw, and bench commitment
- board-pressure or prize-race mistakes
- resource-management notes aligned with search, switching, recovery, and damage-control categories

See [First Coaching-Rule Taxonomy](first-coaching-rule-taxonomy.md) for a tighter v1 rule order and confidence framing.

## First review screen

Borrowing from [Post-Game Review Patterns](post-game-review-patterns.md), the MVP should show:

- result
- one-line story of the game
- top 3 findings
- turning turn(s)
- one practice focus for the next few games

## LLM role

Good uses:

- rewrite structured findings into crisp coaching language
- answer questions like "Why was turn 3 bad?"
- cluster repeated mistakes across many matches

Bad uses:

- parsing raw logs as the primary source of truth
- claiming unrevealed opponent knowledge
- making high-confidence recommendations without turn/action evidence

## Product constraints

- The ingested sources support post-game coaching better than live overlay coaching.
- Community log tooling exists, but official API support is not demonstrated in the current source set.
- Enrichment APIs are strong enough to make reviews feel polished even if the core input remains a manual paste/upload.

## Next useful expansions

- leak tracking across multiple matches
- retry/quiz mode on flagged turns
- archetype-aware coaching styles
- a desktop convenience importer if a stable local-file path is later verified

The companion-product references also suggest a longer-term shape where post-game review becomes a broader training loop with session analytics, leak tracking, and custom drills rather than a one-off analyzer.

## See Also

- [PTCGL Match Data Sources](../ptcgl/ptcgl-match-data-sources.md)
- [PTCGL Battle Log Observability](../ptcgl/ptcgl-battle-log-observability.md)
- [Card and Tournament Data Sources](../data/card-and-tournament-data-sources.md)
- [Integration Risk and Access Notes](../data/integration-risk-and-access-notes.md)
- [Pokémon TCG Competitive Resource Map](../meta/pokemon-tcg-competitive-resource-map.md)
- [Post-Game Review Patterns](post-game-review-patterns.md)
- [Companion and Session-Loop Patterns](companion-and-session-loop-patterns.md)
- [First Coaching-Rule Taxonomy](first-coaching-rule-taxonomy.md)

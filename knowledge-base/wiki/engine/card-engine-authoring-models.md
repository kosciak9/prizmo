# Card Engine Authoring Models

- Updated: 2026-05-27
- Sources: Project research synthesis; external card engine repository research
- Raw: N/A — codebase update

## Scope

This note is research-only. It records patterns for authoring and maintaining card behavior in a future **Standard-only**, **exact-within-supported-scope** Pokémon TCG engine. It does not choose an implementation plan.

The main question is: if a future simulator must be faithful enough to rewind a PTCGL game state, branch from a decision point, and let AI agents compare legal alternatives, how should card behavior be represented and maintained?

## Current working conclusion

The strongest candidate pattern is **hybrid authoring**:

1. Store static card metadata separately from executable behavior.
2. Author behavior through a structured compile-time surface: generated stubs in TypeScript-style ecosystems, or potentially an Elixir macro DSL in this app.
3. Implement exact behavior in typed code, not in raw database rows.
4. Use a prefab/helper library for common effects.
5. Treat reprints, errata, ruleset date, and Standard legality as first-class versioned concepts.
6. Track implementation coverage and regression-test coverage explicitly.

This points away from a fully database-driven rules engine. Card data can live in a database, but card behavior needs either typed code or a very carefully designed domain-specific interpreter.

For this Phoenix/Elixir app, the TypeScript projects' source-stub generators should not be copied literally without further research. TypeScript lacks Elixir-style macros, so those projects need generators to create repetitive card classes, set indexes, and registration boilerplate. Elixir could potentially express the same ideas with compile-time macros instead of generated source files.

For example, a future Elixir authoring surface might look more like a card DSL than a folder of generated classes:

```elixir
defset Prizmo.Tcg.Standard.SurgingSparks do
  defcard "Pikachu ex", set: "SSP", number: "057", hp: 200 do
    attack "Topaz Bolt", cost: [:lightning, :lightning, :lightning], damage: 300 do
      discard_all_energy_from_this_pokemon()
    end
  end

  reprint "Nest Ball",
    from: Prizmo.Tcg.Standard.ScarletViolet.NestBall,
    set: "SSP",
    number: "183"
end
```

The macro could compile this into behavior modules/functions, card registrations, coverage manifests, reprint aliases, compile-time validations, and test metadata. That would preserve the useful part of generated stubs while keeping source code more DRY and auditable.

## Authoring model comparison

| Model | Public examples | Strengths | Risks for exact PTCG |
| --- | --- | --- | --- |
| Code-first card classes | [RyuuPlay](https://github.com/keeshii/ryuu-play), [twinleafgg](https://github.com/the-epsd/twinleafgg) | Maximum flexibility; easy to express unusual card effects; type checking; debugger-friendly. | Without generation, prefabs, and coverage tooling it becomes high-boilerplate and hard to audit. |
| Code-first with generated stubs and prefabs | [twinleafgg set stubs](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/generate-set-stubs.ts), [twinleafgg patterns](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/AGENTS-patterns.md) | Best direct PTCG fit found so far: card files are generated, common behavior is prefabbed, and custom code remains available for edge cases. | Still requires strong reviewer discipline and a ruling-backed regression suite. |
| Static metadata plus executable overlays | [TCG ONE carddb](https://github.com/tcgone/carddb), [TCG ONE engine contrib](https://github.com/axpendix/tcgone-engine-contrib), [deckgym-core](https://github.com/bcollazo/deckgym-core) | Clean split between searchable card data and behavior; good foundation for importers, deck search, legality, and generated templates. | Metadata and behavior can drift unless generation and validation are automated. TCG ONE's public repos do not expose the closed runtime engine. |
| DSL/scripted card text | [Forge card scripting API](https://github.com/Card-Forge/forge/wiki/Card-scripting-API) | Scales authoring across huge card pools; compact card files; easier for non-core contributors once the DSL is mature. | DSL semantics become another engine to maintain. Exact PTCG edge cases may require many escape hatches. |
| Typed task/combinator system | [SabberStone card implementation guide](https://github.com/HearthSim/SabberStone/wiki/Implement-Cards), [SabberStone generated card code](https://github.com/HearthSim/SabberStone/blob/master/SabberStoneCore/src/CardSets/Standard/Expert1CardsGen.cs) | Strong middle ground: reusable typed tasks, generated tests, explicit powers/triggers/auras. | Hearthstone is digital-first and has different timing/visibility semantics. Reprint/errata pressure is lower than Pokémon TCG. |
| Mechanic-map plus outlier overlays | [deckgym-core effect mechanic map](https://github.com/bcollazo/deckgym-core/blob/main/src/actions/effect_mechanic_map.rs), [deckgym-core Rare Candy overlay](https://github.com/bcollazo/deckgym-core/blob/main/src/card_logic/rare_candy.rs) | Great for coverage tracking and repeated text patterns; outliers can still be coded manually. | Pokémon TCG Pocket has simpler rules than full Pokémon TCG; mainline PTCG may outgrow text-pattern mapping quickly. |
| Compile-time macro DSL | Elixir-specific candidate; no direct PTCG example verified yet | Could replace much source-stub generation with declarative card definitions, compile-time validation, automatic registration, reprint aliases, and coverage metadata. | Macro overuse can hide control flow and make debugging harder. It still cannot infer exact card behavior from natural-language card text. |

## Borrowable patterns

### 1. Generate behavior stubs or compile-time declarations from card metadata

Generate card behavior files from a canonical card data source, or in Elixir, use macros to declare cards and compile equivalent registrations/manifests. The goal is not source generation itself; the goal is to reduce boilerplate and make missing implementation visible.

Useful references:

- [twinleafgg `generate-set-stubs.ts`](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/generate-set-stubs.ts)
- [TCG ONE implementation template generator](https://github.com/tcgone/carddb/blob/master/tools/src/main/java/tcgone/carddb/tools/ImplTmplGenerator.java)
- [SabberStone generated set code](https://github.com/HearthSim/SabberStone/blob/master/SabberStoneCore/src/CardSets/Standard/Expert1CardsGen.cs)

Research implication: a future Standard-only engine should track generated-or-declared-but-unimplemented cards separately from unsupported cards. In Elixir, further research should compare generated source files against macro declarations for debuggability, compile-time cost, editor support, and contributor friendliness.

### 1a. Distinguish source generation from data/import automation

Elixir macros may reduce source-code generation, but they do not remove the need for automated data workflows. A future engine would still need importers and checkers for:

- current Standard card metadata;
- card text changes;
- official errata;
- promo legality;
- reprint detection;
- regulation marks and format rotation;
- coverage reports;
- missing behavior reports.

Research implication: the Elixir-specific question is not "generation or no generation". It is which artifacts should be data, which should be macro-authored source, and which should be generated reports or import outputs.

### 2. Prefer prefabs/helpers before custom card logic

Card text repeats: draw cards, search deck, attach energy, switch, gust, discard, place damage counters, heal, apply special conditions, prevent damage, once-per-turn ability markers, and so on.

Useful references:

- [twinleafgg PTCG implementation guide](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/AGENTS.md)
- [twinleafgg text-to-code patterns](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/AGENTS-patterns.md)
- [SabberStone task helpers](https://github.com/HearthSim/SabberStone/blob/master/SabberStoneCore/src/Tasks/ComplexTasks.cs)

Research implication: exactness probably depends less on having fewer card files and more on having a small, well-tested vocabulary of effect primitives.

### 3. Model reprints as behavior sharing, not duplicate behavior

Reprints and alternate arts should share behavior where the effective card text is the same. Only metadata should differ.

Useful references:

- [twinleafgg reprint file example](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/set-sword-and-shield/other-prints.ts)
- [TCG ONE reprint/variant logic](https://github.com/tcgone/carddb/blob/master/tools/src/main/java/tcgone/carddb/tools/SetWriter.java)

Research implication: the future engine likely needs a distinct concept of **print identity** versus **behavior identity**.

### 4. Track card coverage like a product surface

For an exact-within-supported-scope simulator, unsupported cards must be visible and explicit. Coverage should not only count implemented cards; it should track behavior families, assigned tests, unresolved rulings, and Standard legality.

Useful references:

- [deckgym-core card status tool](https://github.com/bcollazo/deckgym-core/blob/main/src/bin/card_status.rs)
- [Forge missing cards dashboard](https://github.com/Card-Forge/forge/wiki/Missing-Cards-in-Forge)
- [deckgym-core README coverage badge](https://github.com/bcollazo/deckgym-core/blob/main/README.md)

Potential future metrics:

- Standard-legal prints
- unique behavior families
- implemented behavior families
- behavior families with regression tests
- behavior families blocked by unresolved rulings
- cards intentionally unsupported in current scope

### 5. Build reusable regression catalogs

Many cards should share scenario tests: search-private-zone, fail-to-find, gust target selection, damage prevention, knockout/prize sequencing, once-per-turn ability reset, evolution timing, and so on.

Useful references:

- [twinleafgg reusable test catalog](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/tests/test-catalog.ts)
- [twinleafgg catalog validation spec](https://github.com/the-epsd/twinleafgg/blob/main/ptcg-server/src/sets/tests/test-catalog.spec.ts)
- [SabberStone generated test example](https://github.com/HearthSim/SabberStone/blob/master/SabberStoneCoreTest/src/CardSets/Standard/Expert1CardsGenTest.cs)

Research implication: a future card should not be called exact just because it has code. It should have at least one assigned scenario or ruling-backed regression path.

## Risks for Standard-only exactness

### Source-of-truth risk

Standard-only narrows the set of cards, but it does not eliminate errata, promo legality, reprint legality, or quarterly rules/policy changes.

Research implication: every card behavior and legality judgment probably needs a ruleset date or format version.

### Behavior drift risk

If static metadata is imported from Pokémon TCG API or TCGdex and behavior is implemented elsewhere, the two can drift.

Research implication: importers should flag changed card text, errata, new prints, and reprints that may or may not share behavior.

### DSL risk

Forge proves that scriptable card behavior can scale, but a broad DSL becomes its own language. For PTCG exactness, a general DSL could hide ambiguous timing, target, and hidden-information semantics.

Research implication: if a DSL exists, it should probably be narrow and typed around known PTCG primitives rather than a free-form text interpreter.

### Test-data risk

No public project found so far exposes an official judge-backed golden ruling corpus for current Standard Pokémon TCG.

Research implication: exactness will require a project-owned regression corpus sourced from official rules, official errata, PokéGym Compendium, Japanese Q&A where useful, and real-game logs.

### Contributor workflow risk

Card implementation requires both programming and rules knowledge. Without templates, examples, PR gates, and a coverage dashboard, quality will vary by contributor.

Research implication: the authoring workflow is part of the engine, not an afterthought.

## Open research questions

1. What should be the canonical behavior identity: print, oracle card, normalized card name, or behavior family?
2. How should reprints be modeled: subclass alias, metadata variant, shared behavior module, or macro-level alias?
3. Which Standard-only coverage metrics matter most: legal prints, unique behaviors, implemented behaviors, assigned tests, or ruling confidence?
4. Which effect families deserve first-class prefabs before mass card implementation?
5. What is the minimum ruling/test corpus required before a card behavior can be marked exact?
6. How should private-zone search and fail-to-find be represented in authoring helpers?
7. Which timing hooks need names from day one: before damage, after damage, on attach, on evolve, on switch, on knockout, prize-taking, Pokémon Checkup, end of turn?
8. How should errata and regulation changes be versioned without breaking old replays?
9. Should contributors author behavior directly, through generated stubs, or through an Elixir macro DSL?
10. Can an Elixir macro DSL produce good enough compile errors, stack traces, editor navigation, and coverage metadata for card authors?
11. Should a future engine have a deckgym-style `card_status` tool from the start?

## Provisional research stance

For a future exact Standard-only Pokémon TCG simulator, the most promising authoring direction is:

- static card metadata imported and versioned separately;
- generated card/behavior stubs in non-macro ecosystems, or an Elixir compile-time card DSL in this app;
- typed code for card behavior;
- prefab/helper functions for common PTCG effects;
- first-class reprint and errata handling;
- explicit coverage and regression-test tracking;
- narrow typed effect DSLs only where they reduce repetition without hiding rules semantics.

This remains a research stance, not an implementation decision.

## See Also

- [Open-Deck RNG TCG Engine and Card-First Playtest UI North Star](ash-backed-tcg-engine-playtest-north-star.md)
- [Meta Deck, TCGdex, Card DSL, and LiveView Play North Star](meta-deck-card-dsl-north-star.md)
- [Cross-Platform TCG Client Architecture](cross-platform-tcg-client-architecture.md)

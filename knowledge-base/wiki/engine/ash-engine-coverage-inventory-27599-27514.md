# Ash Engine Coverage Inventory — Raging Bolt Ogerpon (27599) + Lopunny Dudunsparce (27514)

- Created: 2026-06-02 (north-star reset, first required task)
- Purpose: Canonical Ash `play_card` / action-surface parity map for the two decks that still carry known bounded gaps after iterations 234-236. This is the factual prerequisite before selecting the next blocker implementation.
- Scope: All unique card IDs from `Prizmo.Tcg.Decks.RagingBoltOgerpon27599` and `Prizmo.Tcg.Decks.LopunnyDudunsparce27514`. Classification uses the canonical engine (`EngineCardRegistry`, `AttackEffects`, `ToolEffects`, `StadiumEffects`, `CardPlay`, generic paths) — NOT the legacy sim-layer or `mix prizmo.cards.coverage` (which only checks metadata + overlay presence).
- Status legend:
  - `engine-defined` — explicit `CardDefinition` in `EngineCardRegistry` OR covered by a supported generic path with full executable behavior on the Ash `play_card` / attack / attach surface.
  - `generic-supported` — plain damage attacks, Basic Energy, generic attach/play, provider-only Special Energy inference, generic Stadium/Tool play commands — sufficient for normal play.
  - `partial` — some behavior present (e.g., provider inference) but printed effect text remains pending or gated.
  - `blocker` — printed effect that affects gameplay and is not yet executable on the canonical Ash path (no CardDefinition, no supported effect type, no generic fallback).

## Deck 27599 — Raging Bolt Ogerpon (28 unique cards)

| Card ID   | Name                              | Classification      | Notes (Ash engine path) |
|-----------|-----------------------------------|---------------------|-------------------------|
| MEG-104   | Mega Kangaskhan ex                | generic-supported   | Plain damage + rule-box ex; generic attack path |
| TWM-025   | Teal Mask Ogerpon ex              | blocker             | Core attacker; coin-flip + Ability text pending (TEF-128/129 sibling) |
| POR-062   | Meowth ex                         | generic-supported   | Plain damage ex attacker |
| TEF-123   | Raging Bolt ex                    | blocker             | Core attacker; coin-flip + Ability text pending (TEF-128/129 sibling) |
| SSP-076   | Latias ex                         | generic-supported   | Plain damage ex attacker |
| TWM-064   | Wellspring Mask Ogerpon           | generic-supported   | Basic Pokémon; generic play/attack path |
| JTG-056   | Lillie's Clefairy ex              | generic-supported   | Plain damage ex attacker |
| TEF-025   | Iron Leaves ex                    | generic-supported   | Plain damage ex attacker |
| ASC-142   | Fezandipiti ex                    | generic-supported   | Plain damage ex attacker |
| SSP-056   | Chien-Pao                         | generic-supported   | Basic Pokémon; generic play/attack path |
| SSP-111   | Passimian                         | generic-supported   | Basic Pokémon; generic play/attack path |
| SCR-133   | Crispin                           | engine-defined      | Explicit CardDefinition + search/attach effect (iteration 208/213) |
| MEG-114   | Boss's Orders                     | engine-defined      | Explicit CardDefinition + switch effect (iteration 201) |
| POR-076   | Judge                             | engine-defined      | Explicit CardDefinition + shuffle/draw effect (iteration 203) |
| MEG-119   | Lillie's Determination            | engine-defined      | Explicit CardDefinition + shuffle/draw effect (iteration 202) |
| SSP-170   | Cyrano                            | partial             | Supporter search; no CardDefinition yet |
| TEF-145   | Ciphermaniac's Codebreaking       | partial             | Supporter draw; no CardDefinition yet |
| MEG-131   | Ultra Ball                        | engine-defined      | Generic search path (Ultra Ball flow) |
| MEG-115   | Energy Switch                     | engine-defined      | Explicit CardDefinition + move effect (iteration 206) |
| ASC-196   | Night Stretcher                   | engine-defined      | Explicit CardDefinition + recover effect (iteration 207) |
| SCR-135   | Glass Trumpet                     | blocker             | High-frequency Supporter; no CardDefinition or effect type |
| TWM-165   | Unfair Stamp                      | engine-defined      | Explicit CardDefinition + ACE SPEC KO-gated shuffle/draw (iteration 226) |
| SCR-131   | Area Zero Underdepths             | partial             | Stadium; generic play works, printed effect pending |
| MEE-001   | Grass Energy                      | generic-supported   | Basic Energy |
| MEE-004   | Lightning Energy                  | generic-supported   | Basic Energy |
| MEE-005   | Psychic Energy                    | generic-supported   | Basic Energy |
| MEE-006   | Fighting Energy                   | generic-supported   | Basic Energy |
| MEE-003   | Water Energy                      | generic-supported   | Basic Energy |

**Deck 27599 summary:** 28 unique. 3 blockers (TEF-123 Raging Bolt ex, TWM-025 Teal Mask Ogerpon ex, SCR-135 Glass Trumpet). 2 partial (SSP-170 Cyrano, TEF-145 Ciphermaniac's Codebreaking, SCR-131 Area Zero Underdepths). Rest engine-defined or generic-supported.

## Deck 27514 — Lopunny Dudunsparce (22 unique cards)

| Card ID   | Name                              | Classification      | Notes (Ash engine path) |
|-----------|-----------------------------------|---------------------|-------------------------|
| JTG-120   | Dunsparce                         | engine-defined      | Explicit CardDefinition + `switch_self_with_bench` attack (iteration 236) |
| TEF-128   | Dunsparce                         | blocker             | Core attacker; coin-flip + Ability text pending (TEF-128/129 sibling) |
| TEF-129   | Dudunsparce                       | blocker             | Core attacker; coin-flip + Ability text pending (TEF-128/129 sibling) |
| PFL-083   | Buneary                           | partial             | Basic Pokémon; printed evolution Ability pending |
| PFL-084   | Mega Lopunny ex                   | blocker             | Core attacker; coin-flip + Ability text pending |
| TWM-080   | Mega Lopunny ex                   | blocker             | Duplicate core attacker (same as PFL-084) |
| SCR-118   | Fan Rotom                         | partial             | Supporter search; no CardDefinition yet |
| PFL-014   | Moltres                           | generic-supported   | Basic Pokémon; generic play/attack path |
| ASC-039   | Psyduck                           | generic-supported   | Basic Pokémon; generic play/attack path |
| MEG-119   | Lillie's Determination            | engine-defined      | Explicit CardDefinition + shuffle/draw effect (iteration 202) |
| MEG-114   | Boss's Orders                     | engine-defined      | Explicit CardDefinition + switch effect (iteration 201) |
| MEG-132   | Wally's Compassion                | engine-defined      | Explicit CardDefinition + heal/return effect (iteration 223) |
| WHT-084   | Hilda                             | engine-defined      | Explicit CardDefinition + multi-group search effect (iteration 205) |
| MEG-131   | Ultra Ball                        | engine-defined      | Generic search path |
| POR-081   | Poké Pad                          | engine-defined      | Explicit CardDefinition + search effect (iteration 200) |
| TEF-144   | Buddy-Buddy Poffin                | engine-defined      | Explicit CardDefinition + search effect (iteration 200) |
| SVI-186   | Pokégear 3.0                      | engine-defined      | Explicit CardDefinition + top-N search effect (iteration 210) |
| ASC-181   | Air Balloon                       | engine-defined      | Supported Tool effect (`retreat_cost_reduction`) (iteration 212) |
| PFL-085   | Battle Cage                       | partial             | Stadium; generic play works, printed effect pending |
| TEF-161   | Mist Energy                       | engine-defined      | Provider inference + prevention hook (iteration 198) |
| MEE-002   | Fire Energy                       | generic-supported   | Basic Energy |
| SSP-191   | Enriching Energy                  | engine-defined      | Provider + attach draw effect (iteration 197) |

**Deck 27514 summary:** 22 unique. 5 blockers (TEF-128 Dunsparce, TEF-129 Dudunsparce, PFL-084 / TWM-080 Mega Lopunny ex). 4 partial (PFL-083 Buneary, SCR-118 Fan Rotom, PFL-085 Battle Cage). Rest engine-defined or generic-supported.

## Highest-impact blockers (ranked by fixture frequency + gameplay centrality)

1. **TEF-123 Raging Bolt ex + TEF-128/129 Dunsparce/Dudunsparce + PFL-084/TWM-080 Mega Lopunny ex** — Core attackers for both decks. Coin-flip and Ability effects are the primary remaining bounded gaps. These are the strongest candidates for the next engine-behavior batch.
2. **SCR-135 Glass Trumpet** — High-frequency Supporter in 27599; no CardDefinition or effect type yet.
3. **TWM-025 Teal Mask Ogerpon ex** — Core attacker in 27599; coin-flip + Ability text pending.
4. **SCR-131 Area Zero Underdepths, PFL-085 Battle Cage** — Stadiums with generic play but pending printed effects.
5. **SSP-170 Cyrano, TEF-145 Ciphermaniac's Codebreaking, SCR-118 Fan Rotom** — Supporter search/draw effects without CardDefinitions.

## Next recommended atomic task (post-inventory)

Close the highest-impact core-attacker blocker slice (TEF-123 / TEF-128 / TEF-129 / PFL-084) or the highest-frequency Supporter (SCR-135) once the inventory is accepted. Do not move to UI polish, Electric Streams, or non-target deck work until the six-deck blocker list is empty.

## Validation notes

- Inventory derived from direct inspection of `EngineCardRegistry`, `AttackEffects.supported_attack_effect_types`, `ToolEffects.supported_tool_effect_types`, `StadiumEffects.supported_stadium?`, `CardPlay` generic paths, and recent iteration commits (234-236).
- `mix prizmo.cards.coverage` is intentionally NOT used as the source of truth for canonical Ash parity (per north-star reset and handoff).
- This document is the durable handoff artifact for the required first task after the 2026-06-02 north-star reset.

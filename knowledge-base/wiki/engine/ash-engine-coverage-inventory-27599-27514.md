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
| TWM-025   | Teal Mask Ogerpon ex              | engine-defined      | Explicit CardDefinition + real `teal_dance` Ability command for Basic Grass attach from hand then draw 1 (iteration 245; registry entry originally added in iteration 240) |
| POR-062   | Meowth ex                         | partial             | Actual GameView pending remains for `Last-Ditch Catch` Ability and `Tuck Tail` attack |
| TEF-123   | Raging Bolt ex                    | engine-defined      | Core attacker; explicit CardDefinition + effect type (iteration 238) |
| SSP-076   | Latias ex                         | generic-supported   | Plain damage ex attacker |
| TWM-064   | Wellspring Mask Ogerpon           | generic-supported   | Basic Pokémon; generic play/attack path |
| JTG-056   | Lillie's Clefairy ex              | generic-supported   | Plain damage ex attacker |
| TEF-025   | Iron Leaves ex                    | generic-supported   | Plain damage ex attacker |
| ASC-142   | Fezandipiti ex                    | partial             | `Flip the Script` is a real Ability command as of iteration 246; `Cruel Arrow` remains pending attack text until any-opponent-Pokémon attack targeting exists |
| SSP-056   | Chien-Pao                         | generic-supported   | Basic Pokémon; generic play/attack path |
| SSP-111   | Passimian                         | generic-supported   | Basic Pokémon; generic play/attack path |
| SCR-133   | Crispin                           | engine-defined      | Explicit CardDefinition + search/attach effect (iteration 208/213) |
| MEG-114   | Boss's Orders                     | engine-defined      | Explicit CardDefinition + switch effect (iteration 201) |
| POR-076   | Judge                             | engine-defined      | Explicit CardDefinition + shuffle/draw effect (iteration 203) |
| MEG-119   | Lillie's Determination            | engine-defined      | Explicit CardDefinition + shuffle/draw effect (iteration 202) |
| SSP-170   | Cyrano                            | engine-defined      | Explicit CardDefinition + search effect (iteration 242) |
| TEF-145   | Ciphermaniac's Codebreaking       | engine-defined      | Explicit CardDefinition + search/top-deck effect (iteration 242) |
| MEG-131   | Ultra Ball                        | engine-defined      | Generic search path (Ultra Ball flow) |
| MEG-115   | Energy Switch                     | engine-defined      | Explicit CardDefinition + move effect (iteration 206) |
| ASC-196   | Night Stretcher                   | engine-defined      | Explicit CardDefinition + recover effect (iteration 207) |
| SCR-135   | Glass Trumpet                     | engine-defined      | Explicit CardDefinition + effect type registered (iteration 239) |
| TWM-165   | Unfair Stamp                      | engine-defined      | Explicit CardDefinition + ACE SPEC KO-gated shuffle/draw (iteration 226) |
| SCR-131   | Area Zero Underdepths             | partial             | Stadium; generic play works, printed effect pending |
| MEE-001   | Grass Energy                      | generic-supported   | Basic Energy |
| MEE-004   | Lightning Energy                  | generic-supported   | Basic Energy |
| MEE-005   | Psychic Energy                    | generic-supported   | Basic Energy |
| MEE-006   | Fighting Energy                   | generic-supported   | Basic Energy |
| MEE-003   | Water Energy                      | generic-supported   | Basic Energy |

**Deck 27599 summary:** 28 unique. 0 blockers. 3 partial (`POR-062` Meowth ex, `ASC-142` Fezandipiti ex `Cruel Arrow`, `SCR-131` Area Zero Underdepths). Rest engine-defined or generic-supported. TEF-123 Raging Bolt ex, TWM-025 Teal Mask Ogerpon ex, SCR-135 Glass Trumpet, SSP-170 Cyrano, and TEF-145 Ciphermaniac's Codebreaking moved to executable Ash paths in iterations 238-246.

## Deck 27514 — Lopunny Dudunsparce (22 unique cards)

| Card ID   | Name                              | Classification      | Notes (Ash engine path) |
|-----------|-----------------------------------|---------------------|-------------------------|
| JTG-120   | Dunsparce                         | engine-defined      | Explicit CardDefinition + `switch_self_with_bench` attack (iteration 236) |
| TEF-128   | Dunsparce                         | engine-defined      | Core attacker; explicit CardDefinition + effect type (iteration 238) |
| TEF-129   | Dudunsparce                       | engine-defined      | Core attacker; explicit CardDefinition + effect type (iteration 238) |
| PFL-083   | Buneary                           | engine-defined      | `Run Around` switch-self attack has executable metadata; no current catalog Ability text |
| PFL-084   | Mega Lopunny ex                   | engine-defined      | Core attacker; explicit CardDefinition + effect type (iteration 238) |
| TWM-080   | Mega Lopunny ex                   | engine-defined      | Duplicate of PFL-084; explicit CardDefinition (iteration 241) |
| SCR-118   | Fan Rotom                         | engine-defined      | `Fan Call` Ability and `Assault Landing` attack have executable metadata; no pending text in staged GameView scan |
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

**Deck 27514 summary:** 22 unique. 0 blockers. 1 partial (`PFL-085` Battle Cage). Rest engine-defined or generic-supported. TEF-128/129 Dunsparce/Dudunsparce and PFL-084 Mega Lopunny ex moved to engine-defined in iteration 238. TWM-080 (duplicate) moved in iteration 241. SCR-118 Fan Rotom has executable Ability/attack metadata and did not appear as pending in the refreshed staged GameView inventory.

## Remaining partial gaps (ranked by fixture frequency + gameplay centrality)

All documented blockers from the 2026-06-02 coverage inventory are now resolved. Remaining work on decks 27599/27514 is now **actual GameView partial** gaps:

1. **POR-062 Meowth ex** — `Last-Ditch Catch` and `Tuck Tail` still appear as pending text in Dragapult/Raging Bolt scans.
2. **ASC-142 Fezandipiti ex `Cruel Arrow`** — `Flip the Script` is executable as of iteration 246, but the attack still needs any-opponent-Pokémon target selection.
3. **SCR-131 Area Zero Underdepths, PFL-085 Battle Cage** — Stadiums with generic play but pending printed effects.

## Current status (post-iteration 246)

**2026-06-02 batch note (updated):** All documented blockers from the coverage inventory are now resolved. TEF-123/128/129 + PFL-084 core attackers closed in iteration 238. SCR-135 Glass Trumpet closed in iteration 239. TWM-025 Teal Mask Ogerpon ex received a registry entry in iteration 240 and now has a real `Teal Dance` Ash Ability command in iteration 245. TWM-080 (duplicate) closed in iteration 241. SSP-170 Cyrano, TEF-145 Ciphermaniac's Codebreaking, and SCR-118 Fan Rotom closed in iteration 242 via explicit/executable metadata. Fezandipiti ex (`ASC-142`) `Flip the Script` closed in iteration 246 with a real Ability command; `Cruel Arrow` remains pending. The six-deck blocker list documented in this inventory is still empty, but actual GameView pending text remains and drives the next tasks.

Remaining partial gaps (not blockers): prioritize actual GameView pending text such as Meowth ex (`POR-062`), Fezandipiti ex `Cruel Arrow` (`ASC-142`), and remaining Stadium/Tool/Special Energy text over registry-only coverage. If the next batch returns to the product surface, damage counter animation is closed in iteration 245; choose a new UI candidate only after live six-deck playability is refreshed.

## Validation notes

- Inventory derived from direct inspection of `EngineCardRegistry`, `AttackEffects.supported_attack_effect_types`, `ToolEffects.supported_tool_effect_types`, `StadiumEffects.supported_stadium?`, `CardPlay` generic paths, and recent iteration commits (234-236).
- `mix prizmo.cards.coverage` is intentionally NOT used as the source of truth for canonical Ash parity (per north-star reset and handoff).
- This document is the durable handoff artifact for the required first task after the 2026-06-02 north-star reset.

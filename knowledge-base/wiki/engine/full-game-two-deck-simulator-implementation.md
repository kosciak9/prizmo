# Full-Game Two-Deck Simulator Implementation

Updated: 2026-05-28

## Scope

First simulator implementation slice for a full Pokémon TCG game between two fixed Standard decklists:

- Dragapult, Limitless deck 27431: <https://limitlesstcg.com/decks/list/27431>
- Alakazam/Dudunsparce, Limitless deck 27147: <https://limitlesstcg.com/decks/list/27147>

The first interface is ExUnit-only. No Phoenix UI, Ash persistence, AI opponent, or arbitrary deck support is included yet.

## Implemented slice

The implementation starts with explicit state machines rather than card effects:

- `Prizmo.Tcg.Sim.StateMachines.GameLifecycle`
- `Prizmo.Tcg.Sim.StateMachines.TurnLifecycle`
- `Prizmo.Tcg.Sim.StateMachines.PromptLifecycle`
- `Prizmo.Tcg.Sim.StateMachines.CardLifecycle`
- `Prizmo.Tcg.Sim.StateMachines.ZoneMovement`

The first reducer lives in `Prizmo.Tcg.Sim.Engine` and supports:

- constructing a deterministic game from card IDs,
- starting setup,
- drawing opening hands,
- choosing Active Basic Pokémon from hand,
- choosing setup Benched Basic Pokémon from hand,
- placing six Prize cards for each player,
- completing setup into the first turn,
- drawing for turn,
- opening the action window,
- playing a Basic Pokémon to Bench,
- attaching one Energy for turn,
- evolving an in-play Pokémon from a matching Evolution card in hand,
- blocking Evolution on the first turn of the game and blocking Pokémon played/evolved that same turn from evolving again,
- retreating by paying explicit attached Energy costs and enforcing once-per-turn retreat,
- switching Active with a Benched Pokémon without spending retreat for turn,
- applying verified Air Balloon retreat-cost reduction,
- resolving verified Handheld Fan attack-triggered Energy movement,
- playing scripted Trainers to discard,
- playing Stadiums with Stadium replacement/discard,
- attaching Pokémon Tools,
- scripted deck search to hand and Basic-from-deck-to-Bench movement,
- scripted discard-from-hand and recover-discard-to-hand movement,
- card-specific Rare Candy Basic-to-Stage-2 evolution,
- card-specific Buddy-Buddy Poffin low-HP Basic bench search,
- card-specific Ultra Ball discard-two search,
- card-specific Boss's Orders gust/switch,
- card-specific Crushing Hammer / Enhanced Hammer attached-Energy discard checks,
- verified Lillie's Determination shuffle-hand/draw, Crispin Basic Energy search/attach, and Night Stretcher discard recovery slices,
- verified Unfair Stamp KO-last-turn eligibility plus both-player shuffle/draw slice,
- verified Poké Pad non-Rule Box Pokémon search, Dawn staged Pokémon search, and Sacred Ash discard-to-deck recovery slices,
- verified Judge both-player shuffle/draw, Hilda Evolution-plus-Energy search, and Lana's Aid discard recovery slices,
- verified Team Rocket's Watchtower Colorless Pokémon Ability lock slice,
- verified Forest of Vitality same-turn Grass Evolution exception slice,
- verified Risky Ruins Basic non-Dark Bench damage-counter slice,
- verified Rabsca Spherical Shield prevention for attack effects/damage to Benched Pokémon,
- verified Budew Itchy Pollen next-turn Item lock slice,
- verified Moltres Fighting Wings Pokémon ex damage bonus slice,
- verified Munkidori Adrena-Brain damage-counter movement and Mind Bend Confusion slices,
- verified Fezandipiti ex Flip the Script draw and Cruel Arrow targeted-damage slices,
- verified Drakloak Recon Directive, Kadabra/Alakazam Psychic Draw, and Dudunsparce Run Away Draw ability slices,
- declaring scripted attacks and metadata-backed real attacks,
- validating attack costs against attached Energy,
- resolving verified Abra/Dunsparce switch attacks, Alakazam Powerful Hand hand-scaling damage, and Dragapult ex Phantom Dive Active damage plus Benched damage counters,
- resolving verified Rellor Slight Intrusion self-damage,
- storing and resolving pending attack state,
- resolving explicit attack damage,
- knocking out Active Pokémon,
- discarding Knocked Out Pokémon and attachments,
- awarding Prize cards,
- choosing a replacement Active from Bench after KO,
- setting a winner when a player has no Pokémon remaining or takes the final Prize,
- setting a winner on deck-out during draw for turn,
- setting a winner on concession,
- ending turn,
- starting the opponent's next turn,
- rejecting illegal state-machine transitions.

## Undo/redo requirement

The simulator includes `Prizmo.Tcg.Sim.History`.

Every successful `Engine.apply_action/2` records:

- the explicit action,
- the state before the action,
- the state after the action.

`Engine.undo/1` restores the prior snapshot and moves the action to the redo stack. `Engine.redo/1` reapplies the stored after-state. This is intentionally snapshot-based for now because correctness and inspectability matter more than memory efficiency in the ExUnit-first engine.

Undo/redo is currently tested across setup actions, including opening-hand draw and Prize placement, and across combat actions including a KO/prize/win transition.

## State invariants

`Prizmo.Tcg.Sim.Invariants` validates card accounting for each player:

- all card instances are counted across deck, hand, prizes, discard, lost zone, active, bench, attachments, Pokémon Tools, evolution stacks, and the global Stadium,
- the count must match the player's original deck size,
- duplicate instance IDs are rejected.

This is the first guardrail for exact simulation and for future rewind/branching workflows.

## Card/deck skeleton

Static deck modules exist for the two target decklists:

- `Prizmo.Tcg.Sim.Decks.Dragapult27431`
- `Prizmo.Tcg.Sim.Decks.Alakazam27147`

`Prizmo.Tcg.Sim.CardRegistry` lists the supported card IDs and minimal metadata needed by the current engine slice. A small number of card-specific effects are implemented directly in the reducer. Remaining unsupported card IDs, effects, and states fail explicitly.

The current exact-text slice was checked against Limitless card pages for:

- `TWM-128` Dreepy,
- `TWM-129` Drakloak,
- `TWM-130` Dragapult ex,
- `MEG-054` Abra,
- `MEG-055` Kadabra,
- `MEG-056` Alakazam,
- `JTG-120` Dunsparce,
- `TEF-129` Dudunsparce,
- `MEG-119` Lillie's Determination,
- `SCR-133` Crispin,
- `ASC-196` Night Stretcher,
- `TWM-165` Unfair Stamp,
- `POR-081` Poké Pad,
- `PFL-087` Dawn,
- `DRI-168` Sacred Ash,
- `POR-076` Judge,
- `WHT-084` Hilda,
- `TWM-155` Lana's Aid,
- `ASC-181` Air Balloon,
- `DRI-180` Team Rocket's Watchtower,
- `MEG-117` Forest of Vitality,
- `MEG-127` Risky Ruins,
- `TWM-150` Handheld Fan,
- `TEF-023` Rellor,
- `TEF-024` Rabsca,
- `ASC-016` Budew,
- `PFL-014` Moltres,
- `TWM-095` Munkidori,
- `ASC-142` Fezandipiti ex.

## Verification

Current tests cover:

- legal and illegal lifecycle transitions,
- zone movement constraints,
- fixed decklists containing 60 cards each,
- deterministic setup into first turn with Active, Bench, and Prize placement,
- Basic-to-Bench play,
- Energy attachment,
- normal Evolution from hand, including undo and card accounting,
- first-turn Evolution rejection and same-turn Evolution rejection,
- rejection of Evolution onto the wrong Pokémon,
- retreat cost payment, discard, switch, and once-per-turn rejection,
- Air Balloon retreat-cost reduction,
- Handheld Fan moving Energy from the attacker to the Tool holder's Bench when the Active holder is damaged,
- non-retreat switching,
- scripted Trainer/Stadium/Tool/search/discard/recovery movement,
- Rare Candy, Buddy-Buddy Poffin, Ultra Ball, Boss's Orders, Crushing Hammer, and Enhanced Hammer supported-scope behavior,
- Lillie's Determination, Crispin, and Night Stretcher supported-scope behavior,
- Unfair Stamp KO-last-turn eligibility rejection and successful shuffle/draw behavior,
- Poké Pad, Dawn, and Sacred Ash supported-scope behavior,
- Judge, Hilda, and Lana's Aid supported-scope behavior,
- Team Rocket's Watchtower blocking Dudunsparce Run Away Draw,
- Forest of Vitality allowing Rellor to evolve into Rabsca on the same turn after the first turn,
- Risky Ruins placing damage counters on Basic non-Dark Pokémon Benched during a turn,
- Rellor Slight Intrusion opponent damage and self-damage,
- Rabsca Spherical Shield preventing Phantom Dive Benched damage counters,
- Budew Itchy Pollen preventing opponent Item cards during their next turn while allowing Supporters and clearing afterward,
- Moltres Fighting Wings adding damage against Pokémon ex but not non-ex Pokémon,
- Munkidori Adrena-Brain moving damage counters with Darkness Energy attached and Mind Bend applying Confusion,
- Fezandipiti ex Flip the Script drawing after a KO last turn and Cruel Arrow targeting a Benched Pokémon,
- Drakloak Recon Directive, Alakazam Psychic Draw, Dudunsparce Run Away Draw,
- turn handoff to the opponent,
- scripted attack declaration and damage resolution,
- real attack declaration from card metadata,
- Abra/Dunsparce attack switching, Alakazam Powerful Hand, and Dragapult ex Phantom Dive bench-counter distribution,
- attack cost rejection when attached Energy cannot pay,
- KO, discard, Prize, and winner flow,
- replacement Active selection after KO,
- scripted playthroughs for no-Pokémon remaining, final Prize, deck-out, and concession win paths,
- scenario playthroughs for lucky quick KO, unlucky deck-out, a replacement-heavy marathon Prize race, and a cross-deck combo scenario that touches every unique card ID from both fixed decklists,
- undo/redo of successful setup and action-window actions,
- card accounting invariants across setup and undo/redo,
- illegal draw-for-turn from the action window.

Focused validation command used:

```sh
mix format && mix test test/prizmo/tcg/sim
```

Result on 2026-05-28 after Munkidori/Fezandipiti ex batch: 64 simulator tests, 0 failures.

Full project validation also passed via `mix check`: 69 tests, 0 failures.

## Next implementation questions

- Model mulligans as first-class setup state-machine steps.
- Continue expanding real attack metadata and behavior for the rest of the fixed decklists.
- Add ability timing/prompt structure instead of direct optional ability actions.
- Continue replacing scripted draw/recovery effects with card-specific Supporter/Item implementations.
- Add replacement Active prompt handling rather than direct action-only replacement.
- Decide when repeated hard-coded card behavior should be extracted into macros or a DSL.

# Godot card repository validation

- Source: Multiple sources listed below
- Collected: 2026-05-28
- Published: Unknown
- Type: explorer-agent direct repo validation plus selected source checks
- Scope: Godot card-game repos useful for a touch-first Pokémon-like renderer with existing server authority

## Sources

- chun92/card-framework: https://github.com/chun92/card-framework
- kiinii-pixel/Card-Wars: https://github.com/kiinii-pixel/Card-Wars
- db0/godot-card-game-framework: https://github.com/db0/godot-card-game-framework
- rametta/Pali: https://github.com/rametta/Pali
- BananaHolograma/Veneno: https://github.com/BananaHolograma/Veneno
- insideout-andrew/deckbuilder-framework: https://github.com/insideout-andrew/deckbuilder-framework
- hackclub/hackstone: https://github.com/hackclub/hackstone

## Validation table

| Repo | Godot | License | 2D/3D | Usefulness | Verdict |
| --- | --- | --- | --- | --- | --- |
| `chun92/card-framework` | Godot 4.6+ | MIT | 2D | CardManager, Card, Pile, Hand, CardFactory, drag/drop validation, JSON card data, editor previews | **Build-on candidate** |
| `kiinii-pixel/Card-Wars` | Godot 4.4 | GPL-3.0 | 2D with shader tilt | TCG-like card flow, resource-based card data, drag/drop, hover, hand spacing, fighting/discard | **Study only** due GPL |
| `db0/godot-card-game-framework` | Godot 3-era / older | AGPL-3.0 | 2D | Mature card framework and scripting-engine ideas | **Reference only** due AGPL + age |
| `rametta/Pali` | Godot 4.1 | Apache-2.0 | 3D | Simple 3D multiplayer TCG reference | Low value / outdated |
| `BananaHolograma/Veneno` | Godot 4.1 | MIT | 2D | Small playing-card game/demo | Low value |
| `insideout-andrew/deckbuilder-framework` | Godot 4.3 | MIT | 2D | Simple resource/deck/hand/pile mechanics | Minimal reference |
| `hackclub/hackstone` | Godot 4.3 | No license found | 3D | Hearthstone-like 3D card scene ideas | Avoid for production/legal reuse |

## Directly verified source notes

### chun92/card-framework

GitHub README claims:

- “Professional-grade Godot 4.x addon” for 2D card games including Solitaire, TCGs, and deck-building roguelikes.
- Version 1.4.0, Godot 4.6+ compatible.
- MIT license.
- Key features: drag/drop system, flexible containers, JSON card data, editor preview, complete FreeCell implementation, factory patterns, inheritance hierarchy, event system.
- Core architecture: `CardManager`, `Card`, `CardContainer`, `CardFactory`.
- Installation via AssetLib or copying to `res://addons/card-framework`.

Research implication: this is the best permissively licensed Godot 2D card UI base. It should be inspected first if the embedded Godot renderer uses Godot-native card interactions.

### kiinii-pixel/Card-Wars

GitHub README says the project aims to turn Adventure Time Card Wars TCG into a playable video game. Done items include dynamic cards, drag/drop, hover animations, automatic hand spacing, drawing/playing cards, decks, fighting, discard pile, and main menu. It uses JSON/card Resources and dynamic templates. License is GPL-3.0.

Research implication: this is a strong design reference for TCG-specific Godot UI patterns, but GPL means do not copy code into this project unless GPL licensing is intended.

## Practical shortlist

### Build on directly

1. `chun92/card-framework`
   - MIT, active, Godot 4.6+, explicit TCG support, card containers and drag/drop already modeled.
   - Best starting point for a Godot 2D renderer spike.

### Study for concepts only

1. `kiinii-pixel/Card-Wars`
   - Best domain match and useful patterns: dynamic cards, card resources, hand spacing, hover/tilt, fighting/discard zones.
   - GPL-3.0 prevents direct reuse in non-GPL code.
2. `db0/godot-card-game-framework`
   - Mature rules/scripting patterns, but AGPL and older Godot version make it unsuitable as a dependency.

### Skip unless a specific question arises

- `rametta/Pali`: closest 3D TCG label, but older/small/specific.
- `BananaHolograma/Veneno`: small demo.
- `insideout-andrew/deckbuilder-framework`: minimal; only useful for simple Resource/deck signals.
- `hackclub/hackstone`: no license found and early-stage.

## Implementation insight

If using embedded Godot, do not search for a full Pokémon-like framework. Use `chun92/card-framework` as a card interaction/control layer, then build custom containers for Pokémon zones:

- Active Pokémon container
- Bench container
- Prize cards container
- Hand container
- Deck/discard/lost-zone piles
- Action menu overlay
- Legal-target highlighter

The authoritative server still determines legal actions and outcomes. Godot containers should validate only UI affordances, not authoritative rules.

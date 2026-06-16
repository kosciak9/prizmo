# TCG Client Renderer Options

- Updated: 2026-06-16
- Sources: ChatGPT shared conversation/export (2026-05-28); cited GitHub repositories and Godot documentation; Project codebase; user instruction
- Raw: [TCG client renderer AI thread](../../raw/engine/2026-05-28-tcg-client-renderer-ai-thread.md)

## Summary

For a Pokémon-like TCG with an existing authoritative game server, the client should be a thin renderer and command emitter:

```text
server snapshots/events
  → client state projection
  → animated board/card view
  → tap/drag/select command emission
  → server-confirmed animation
```

The strongest direction from the thread is **Godot 2D + GDScript**: native iOS/Android first-class, web as a supported secondary target, server-authoritative protocol, and a touch-first command UI. React + React Three Fiber remains a good browser prototype path, but should be treated as a replaceable renderer rather than the product architecture.

## Core architectural rule

Keep three states separate:

| State | Owner | Purpose |
| --- | --- | --- |
| Server state | Game server | Canonical truth and rules validation |
| View model | Client adapter | Positions, visibility, legal affordances, labels, highlights |
| Interaction/animation state | Renderer | Hover, selection, drag, tweening, optimistic/pending affordances |

Short version:

> Server state decides what is true. The client decides how it feels.

## Renderer-agnostic contract

The client boundary should revolve around boring protocol types, not engine-specific scene nodes:

```ts
type GameCommand =
  | { type: "play_card"; cardId: string; targetZoneId: string }
  | { type: "attach_energy"; cardId: string; targetPokemonId: string }
  | { type: "attack"; attackerId: string; attackId: string }
  | { type: "pass" }

type RenderCard = {
  id: string
  imageUrl: string
  zone: "hand" | "active" | "bench" | "discard" | "prizes"
  position: [number, number, number]
  rotation: [number, number, number]
  selectable: boolean
  legalActions: GameCommand[]
}
```

Even if the first implementation is Godot 2D, this style keeps the protocol/view-model layer portable.

## Option comparison

| Option | Best for | Main risk | Takeaway |
| --- | --- | --- | --- |
| React + R3F web | Fast browser prototype, declarative card/board scene | Native mobile path is fragile; WebView may feel poor | Good first renderer only if disposable |
| React Native + R3F / Expo GL | Staying in React across native mobile | Ecosystem rough edges and GPU quirks | Spike early before committing |
| React Native + Filament | Native 3D from React Native | Less standard TCG/web ecosystem | Interesting watch item, not default |
| Godot 3D + GDScript | Native-feeling game client, camera/animation/touch tools | Web target and 3D picking/camera complexity | Serious option if 3D is required |
| Godot 2D + GDScript | Touch-first TCG with high readability and animation polish | Less spatial spectacle than 3D | Best current direction |
| React web inside WebView | Fastest reuse path | Touch latency, memory, browser/GPU quirks | Prototype only, risky as main mobile UX |

## Recommended path

Start with:

```text
Godot 2D + GDScript
native iOS/Android as first-class targets
web as supported secondary/demo target
WebSocket protocol to existing server
JSON or binary command protocol
no client-side game authority
```

Design the client as “2D with depth,” not flat web UI:

- board mat with clear zones
- cards as animated 2D nodes
- smooth hand fan
- zoomed card preview
- animated movement between zones
- legal-action glows/highlights
- small-screen adaptive layout
- particles and polish used sparingly

Godot mapping:

| Need | Godot primitive |
| --- | --- |
| UI layer | `Control` / `CanvasLayer` |
| Cards/board/animations | `Node2D` |
| Movement/scale/rotation | `Tween` |
| Reusable effects | `AnimationPlayer` |
| Hit detection | `Area2D` |
| Card art | `TextureRect` / `Sprite2D` |

## Touch interaction model

Avoid making drag-and-drop the only primary interaction on mobile. Dense TCG board states make drag-heavy UIs frustrating.

Preferred flow:

```text
tap card
→ show legal actions / legal targets
→ tap target
→ send command
→ animate result after server confirmation
```

Drag can remain as a shortcut:

```text
drag card onto valid target
→ snap/highlight target
→ release sends same command
```

## Source/repo map

| Source | Use for | Caveat |
| --- | --- | --- |
| `colyseus/turnbased-cards-demo` | Multi-client architecture and renderer/server separation | Server stack may not matter if our server already exists |
| `pmndrs/react-three-fiber` | Declarative React 3D scene/component model | Native mobile path should be validated early |
| `TesseractCat/bg3d` | Tabletop interaction metaphors | Three.js + Rust, not React-native/mobile-first |
| `keeshii/ryuu-play` | Pokémon TCG domain modeling and state flow | Not a modern renderer reference |
| `simeydotme/pokemon-cards-css` | Holo/foil/tilt visual polish | Visual inspiration only |
| `thatsprettyfaroutman/markdown-threejs-cards` | Generated/dynamic 3D card surfaces | Likely overkill for mostly image-texture Pokémon cards |
| `expo/expo-three` | React Native Three.js spike | Historically more fragile than web Three.js |
| `margelo/react-native-filament` | Native 3D renderer alternative | Worth watching, not default yet |
| `rametta/Pali` | 3D Godot TCG reference | Low-value/outdated reference after direct validation |
| `db0/godot-card-game-framework` | Card/zone/hand concepts | AGPL-3.0 and Godot 3-era concerns; reference only |
| `chun92/card-framework` | Godot 4.x 2D card UI patterns | Best build-on candidate from direct validation |
| `BananaHolograma/Veneno` | Godot 4 card interaction/animation demo | Small reference |
| `insideout-andrew/deckbuilder-framework` | Draw/shuffle/basic deck mechanics | Basic framework only |
| `hackclub/hackstone` | Godot online card game UX ideas | No license found; avoid production reuse |
| `kiinii-pixel/Card-Wars` | TCG-like Godot/browser friendliness | Study only due GPL-3.0 |

## Validation status

The first direct source validation is captured in [Cross-Platform TCG Client Architecture](cross-platform-tcg-client-architecture.md) and [Godot card repository validation](../../raw/engine/2026-05-28-godot-card-repo-validation.md).

## Current repo experiment boundary

Repo-root `game/*` is reserved for Godot TCG player experiments, including local Godot project/editor artifacts such as `game/ptcg_game/*`. Treat this subtree as intentionally out of scope for Phoenix/Ash/React work: do not edit, delete, format, move, clean, or otherwise manage files under `game/*` unless the user explicitly requests Godot or `game/*` work.

Remaining validation tasks:

- Build a tiny Godot 2D spike that connects to a mocked server event stream, renders hand/active/bench/prizes, and sends one command.
- Test the same spike embedded in React web and React Native iOS/Android early.
- Verify `@borndotcom/react-native-godot` with physical devices, especially iOS, before committing to embedded Godot as core infrastructure.
- Re-check licenses before copying code; `chun92/card-framework` is the only current build-on candidate from the repo validation pass.

## See Also

- [Cross-Platform TCG Client Architecture](cross-platform-tcg-client-architecture.md)
- [Card Engine Authoring Models](card-engine-authoring-models.md)

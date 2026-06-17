# Cross-Platform TCG Client Architecture

- Updated: 2026-06-17
- Sources: Godot docs; Born React Native Godot; Migeran LibGodot; React Three Fiber; React Native Skia; Godot card repositories; Project codebase; user direction
- Raw: [React web/RN renderer research](../../raw/engine/2026-05-28-react-web-rn-renderer-research.md); [Embedded Godot research](../../raw/engine/2026-05-28-embedded-godot-research.md); [Godot card repo validation](../../raw/engine/2026-05-28-godot-card-repo-validation.md); [AI thread capture](../../raw/engine/2026-05-28-tcg-client-renderer-ai-thread.md)

## Goal

This page supports the canonical roadmap's client goals:

- **Goal 3:** React web shell wrapping embedded Godot as the in-game play surface.
- **Goal 4:** React Native shell wrapping embedded Godot as the native mobile pathway.

Godot is for playing the game well. It is not the whole product application.

## Target surfaces

Support three coordinated client surfaces:

1. React web product shell
2. React Native product shell for iOS/Android
3. Embedded Godot gameplay renderer/play surface

The authoritative game server already exists in the Ash/Postgres engine. Clients should render, animate, collect input, send commands, and display server-confirmed state — not own game truth.

The current React browser game UI is temporary scaffolding for engine validation and protocol discovery. It should inform the shared play protocol, but should not be treated as the long-term in-game UX.

## Strong recommendation

Use **React/React Native as the product shell** and **embedded Godot as the gameplay renderer**.

```text
React web shell / React Native shell
  - auth, deck management, game/session selection, settings
  - coaching panels, history, review UI when those product surfaces return
  - overlays, navigation, account/product flows
  - lifecycle wrapper for the embedded Godot play surface

Embedded Godot renderer
  - board/cards/zones/hand/prizes
  - touch-first input and animation
  - targeting UX and visual feedback
  - command emission
  - server-confirmed state animation
```

Do not try to make React, React Native, and Godot all render the same board independently unless a temporary fallback/debug tool is required. Share the **protocol and view-model contract**, not renderer internals. Do not put rules logic into React, React Native, or Godot.

## Why this changed the prior recommendation

The first-pass AI thread treated embedded Godot in React Native as likely WebView-only. Direct source review found a stronger path:

- Godot web export can be embedded into a custom React-owned canvas.
- Godot Android is officially designed as an embeddable Android library.
- `@borndotcom/react-native-godot` provides an MIT RN wrapper for Android and iOS, built on Migeran LibGodot, with `<RTNGodotView />`, separate Godot thread execution, and TypeScript/JavaScript API access.
- iOS embedding still carries fork risk because the practical path relies on Migeran LibGodot rather than normal upstream Godot iOS export docs.

## Platform architecture

### React web

Embed the Godot Web export inside the React app:

```text
React route
  ├─ Shell UI / overlays / side panels
  └─ GodotCanvas
       └─ Godot Web export renders into a supplied <canvas>
```

Godot docs support custom HTML shells and passing an explicit canvas element to `engine.startGame({ canvas })`.

Recommended communication:

- Godot ↔ server over WebSocket for game events/commands.
- Godot ↔ React via `JavaScriptBridge` or `postMessage` only for shell-level events.

### React Native Android

Two viable paths:

1. use `@borndotcom/react-native-godot`; or
2. write a native RN view/module around the official Godot Android library.

Official Android docs support `GodotFragment`, `GodotActivity`, raw `Godot`, `GodotHost`, Android plugins, and bidirectional host/Godot communication. The docs also warn that only one Godot instance is supported per process and orientation/resizing configuration must be handled carefully.

### React Native iOS

Use `@borndotcom/react-native-godot` for a spike, but mark this as the highest-risk part.

Reason: upstream Godot iOS docs focus on exporting a whole Godot app and iOS plugins. The embedded-view path found here uses Migeran LibGodot, which adds lifecycle control and host-surface rendering on Apple platforms.

Risk controls:

- pin Godot/LibGodot versions;
- test on physical iOS devices early;
- verify App Store/update flow assumptions;
- plan for commercial support or direct Migeran contact if this becomes core product infrastructure.

## Communication model

Avoid using the React/RN bridge for high-volume card movement events. Let Godot speak directly to the game server when possible.

```text
Godot renderer
  ├─ receives server snapshots/events
  ├─ maps them to local visual state
  ├─ animates confirmed changes
  └─ sends commands back to server

React/RN shell
  ├─ app lifecycle: pause/resume/start/stop Godot
  ├─ navigation/context: match id, deck/game/session choice, user token, settings
  ├─ overlays: coaching, logs, debug panels when product surfaces need them
  └─ telemetry/product events
```

Bridge only coarse events:

- `match_loaded`
- `selected_card_changed`
- `request_action_overlay`
- `match_finished`
- `open_review_panel`
- `renderer_error`

## Shared contract

Define protocol and render/view-model contracts outside any renderer.

```text
server protocol
  ├─ snapshots/events
  ├─ legal actions
  ├─ command schema
  └─ version/capability negotiation

renderer view model
  ├─ card ids and public/private visibility
  ├─ zone ids: hand, active, bench, prizes, deck, discard, lost zone
  ├─ legal action affordances
  ├─ animation descriptors
  └─ shell event hooks
```

Implementation options:

- TypeScript contracts for React/RN shell.
- JSON Schema or another language-neutral schema to generate/validate TypeScript and GDScript representations.
- Boring JSON first; binary only if payload size or latency demands it.

## Godot renderer shape

Start Godot as a 2D-with-depth renderer:

```text
Godot project
  scenes/
    MatchRenderer.tscn
    BoardView.tscn
    CardView.tscn
    HandView.tscn
    ZoneView.tscn
    ActionMenu.tscn

  scripts/
    network/GameSocket.gd
    protocol/Protocol.gd
    state/GameStore.gd
    state/ViewModelBuilder.gd
    input/TouchController.gd
    views/CardView.gd
    views/ZoneView.gd
```

Adopt or study:

- **Build on:** `chun92/card-framework` for Godot 4.6+, MIT, 2D card containers, hand/pile abstractions, drag/drop validation, JSON card data, and editor previews.
- **Study only:** `kiinii-pixel/Card-Wars` for TCG-specific card flow, resource-based card data, hover/tilt, fighting/discard, and dynamic card templates. Do not copy code due GPL-3.0.
- **Reference only:** `db0/godot-card-game-framework` for scripting-engine ideas. Do not copy code due AGPL and older Godot version.

## React/RN renderer alternatives

Keep these as fallbacks or comparison spikes:

| Renderer | Use if | Why not default if embedded Godot is the goal |
| --- | --- | --- |
| React Three Fiber | Need a React-native gameplay renderer shared across web/RN | RN path has GL/asset/drei rough edges; duplicates Godot renderer |
| React Native Skia | Want pure 2D RN-first renderer with web via CanvasKit | Must build scene graph/hit-testing/game UI infrastructure |
| PixiJS / @pixi/react | Need fast web-only canvas renderer | No RN target |
| RN Views + Reanimated/Gesture Handler | Need shell UI and overlays | Not ideal for dense overlapping card battlefield |
| React Native Filament | Need native 3D model display | No web target and not card-board focused |

## Decision matrix

| Criterion | Embedded Godot | R3F web/RN | RN Skia + web CanvasKit |
| --- | --- | --- | --- |
| Web target | Good via web export/custom canvas | Excellent | Good but WASM setup |
| RN Android | Good via official Android library / RN wrapper | Medium | Good |
| RN iOS | Possible via LibGodot/RN wrapper, highest risk | Medium | Good |
| Touch/game feel | Excellent | Good | Good if built well |
| Renderer sharing | Same Godot project across hosts | High React code sharing | Medium/high draw-code sharing |
| Product shell integration | Needs bridge boundaries | Native React integration | Native React/RN integration |
| Main risk | LibGodot/version/fork risk on iOS | RN GL ecosystem rough edges | Building game framework yourself |

## Suggested spike order

1. **Embedded Godot web spike**
   - React page owns a canvas.
   - Godot Web export starts inside it.
   - Godot sends one shell event to React and one command to a mock server.

2. **Embedded Godot RN spike**
   - Use `@borndotcom/react-native-godot`.
   - Render the same Godot scene in `RTNGodotView`.
   - Test physical Android and iOS devices.

3. **Card framework spike**
   - Add `chun92/card-framework` to the Godot project.
   - Render hand, active, bench, prizes, deck, discard.
   - Implement tap-card → legal actions → tap target → command.

4. **Fallback renderer spike only if needed**
   - R3F or Skia with the same protocol/view-model contract.

## Non-negotiables

- No client-side authority.
- One protocol/view-model contract across all renderers.
- Physical-device tests before committing to mobile renderer architecture.
- Keep bridge messages coarse; do not send every tween/card movement through React/RN.
- Treat iOS embedded Godot as feasible but strategically risky until proven in a small app.

## See Also

- [TCG Client Renderer Options](tcg-client-renderer-options.md)
- [Card Engine Authoring Models](card-engine-authoring-models.md)

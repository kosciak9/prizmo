# React web and React Native renderer research

- Source: Multiple sources listed below
- Collected: 2026-05-28
- Published: Unknown
- Type: direct source review plus explorer-agent synthesis
- Scope: renderer options for a server-authoritative Pokémon-like TCG with React web and React Native iOS/Android targets

## Sources

- React Three Fiber: https://github.com/pmndrs/react-three-fiber
- React Native Skia: https://github.com/Shopify/react-native-skia
- React Native Skia web support: https://shopify.github.io/react-native-skia/docs/getting-started/web/
- Expo GL: https://docs.expo.dev/versions/latest/sdk/gl-view/
- Expo Three: https://github.com/expo/expo-three
- React Native Filament: https://github.com/margelo/react-native-filament
- Pixi React: https://github.com/pixijs/pixi-react
- PixiJS: https://github.com/pixijs/pixijs
- React Native Gesture Handler: https://github.com/software-mansion/react-native-gesture-handler
- React Native Reanimated: https://docs.swmansion.com/react-native-reanimated
- Pokémon cards CSS effects: https://github.com/simeydotme/pokemon-cards-css

## Verified source notes

### React Three Fiber

The R3F README positions `@react-three/fiber` as a React renderer for Three.js with reusable components, pointer events, and `useFrame` render-loop integration. It explicitly says:

- R3F pairs major versions with React versions; `@react-three/fiber@9` pairs with React 19.
- It has a React Native example using `@react-three/fiber/native` and Expo.
- Metro may need asset extension configuration for `glb`, `png`, `jpg`, etc.
- The README claims no runtime overhead over plain Three.js and that everything in Three.js is available.

Research implication: R3F is the strongest single renderer-family option if we want one React-style component model across web and React Native, but the RN path still needs physical-device validation and careful asset loading.

### React Native Skia

The React Native Skia README describes it as high-performance 2D graphics for React Native using Skia, the graphics engine behind Chrome, Android, Flutter, and other products. The web-support docs say:

- Skia runs in the browser through CanvasKit WASM.
- The CanvasKit WASM file is 2.9 MB gzipped and loads asynchronously.
- Web support can use `<WithSkiaWeb />` for code splitting or `LoadSkiaWeb()` before app registration.
- It can be used on projects without installing React Native Web.
- Browser WebGL context limits can matter if many canvases are used.
- Some APIs are unsupported on React Native Web.

Research implication: Skia is a serious 2D shared-renderer option for RN + web if the product wants a React/RN-native 2D renderer rather than Godot. It is not a game engine; hit testing, scene graph, and card interactions must be built.

### DOM/CSS web renderer

`simeydotme/pokemon-cards-css` remains useful as visual inspiration for Pokémon-like card foil/tilt effects. It is not a renderer architecture or mobile sharing path.

Research implication: DOM/CSS can support surrounding web UI and possibly a low-complexity fallback board, but it should not be the main cross-platform gameplay renderer if React Native parity matters.

## Option notes

### React + R3F web/native

Pros:

- Best React-native mental-model continuity between web and RN.
- Same conceptual scene graph and component structure across targets.
- Built-in pointer/raycast event model maps naturally to cards on a 2.5D board.
- Good bridge if the first implementation is React web and the RN app should reuse as much renderer code as possible.

Risks:

- RN path depends on Expo GL / native GL context behavior and asset-loading quirks.
- Many ecosystem helpers are web-biased; `drei/native` coverage is narrower than web.
- 3D adds camera/picking complexity for a game that may work better as 2D with depth.

Best use: React-first spike or fallback renderer when embedded Godot is not ready.

### React Native Skia

Pros:

- High-performance 2D drawing on RN.
- Web path exists via CanvasKit WASM.
- Good fit for a 2D card board with custom shaders, masks, highlights, and animation.
- More native 2D than R3F if the product does not need true 3D.

Risks:

- No built-in card-game scene graph, hit testing, drag/drop, or multiplayer concepts.
- Web boot/loading complexity and extra WASM payload.
- Separate mental model from a Godot gameplay renderer.

Best use: serious React/RN-native 2D renderer option if Godot embedding is rejected.

### PixiJS / @pixi/react

Pros:

- Mature high-performance 2D web renderer.
- Good pointer and sprite model for a browser TCG board.
- Strong alternative to DOM/CSS for web-only gameplay.

Risks:

- Web-only; does not solve React Native sharing.
- Requires a separate RN renderer path.

Best use: browser-only prototype, not the main cross-platform plan.

### React Native Views + Reanimated/Gesture Handler

Pros:

- Best conventional RN touch UX stack.
- Excellent for app shell, overlays, menus, coaching UI, action sheets, and non-board UI.

Risks:

- Cards are native views, not batched game sprites.
- Heavy overlapping animation and particle effects can become awkward.
- No web renderer sharing besides business/view-model logic.

Best use: RN app shell and overlays around a dedicated renderer.

### React Native Filament

Pros:

- Native 3D renderer in RN with modern 3D model support.
- Worth watching for future product/visualization features.

Risks:

- Niche/newer ecosystem.
- No web target.
- More suited to GLB/model scenes than a 2D/2.5D TCG board.

Best use: watch list, not default.

## Research conclusion

For a React web + RN app, share the app shell and protocol/view-model layer in TypeScript. For the gameplay renderer, either:

1. use embedded Godot as the shared game renderer across web/RN; or
2. use R3F if the team wants a React-native renderer first; or
3. use Skia if the team wants a pure 2D RN-first renderer and accepts building game-scene infrastructure.

If embedded Godot is the goal, React/RN renderers should focus on shell/overlays/fallbacks, not duplicate the main board renderer.

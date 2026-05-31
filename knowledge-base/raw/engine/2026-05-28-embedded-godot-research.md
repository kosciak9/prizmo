# Embedded Godot research for React web and React Native

- Source: Multiple sources listed below
- Collected: 2026-05-28
- Published: Unknown
- Type: direct source review plus explorer-agent synthesis
- Scope: embedding Godot 4.x/GDScript as a renderer inside React web and React Native iOS/Android host apps

## Sources

### Official Godot docs

- Custom HTML page for Web export: https://docs.godotengine.org/en/stable/tutorials/platform/web/customizing_html5_shell.html
- JavaScriptBridge singleton: https://docs.godotengine.org/en/stable/tutorials/platform/web/javascript_bridge.html
- HTML5 shell class reference: https://docs.godotengine.org/en/stable/tutorials/platform/web/html5_shell_classref.html
- Exporting for Web: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- Godot Android library: https://docs.godotengine.org/en/stable/tutorials/platform/android/android_library.html
- Android plugins: https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html
- iOS export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- iOS plugins: https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html

### Community / library sources

- Born React Native Godot: https://github.com/borndotcom/react-native-godot
- Migeran LibGodot: https://github.com/migeran/libgodot
- Calico Games React Native Godot: https://github.com/calico-games/react-native-godot
- Godot Android samples / GLTF viewer: https://github.com/m4gr3d/Godot-Android-Samples/tree/master/apps/gltf_viewer

## React web embedding

Official Godot docs support embedding a Web export into a custom HTML page. The minimal shell contains:

```html
<canvas id="canvas"></canvas>
<script src="$GODOT_URL"></script>
<script>
  var engine = new Engine($GODOT_CONFIG);
  engine.startGame();
</script>
```

The docs also show passing a specific DOM canvas to `engine.startGame({ canvas: canvasElement })`. That is the clean path for a React component that owns a canvas ref and starts Godot in that element.

Bidirectional web integration options:

- Godot → JS: `JavaScriptBridge.get_interface("window")`, `eval`, or calling JS functions.
- JS → Godot: `JavaScriptBridge.create_callback()` lets JavaScript call GDScript callbacks, but callbacks must be retained and take a single `Array` argument.
- Host-shell integration: iframe + `postMessage` is possible but is an app-level design, not a special Godot API.
- Server integration: Godot can also connect directly to the existing game server via WebSocket, avoiding a high-volume React/Godot bridge.

Recommended web shape:

```text
React route/app shell
  ├─ React UI: auth, coaching panel, deck picker, overlay menus
  └─ GodotCanvas component
       └─ Godot Web export renders into owned <canvas>

Communication:
  - high-volume game protocol: Godot ↔ server WebSocket
  - shell events: Godot ↔ React via JavaScriptBridge or postMessage
```

Web caveats:

- Web export uses WebAssembly/WebGL constraints; renderer choice and asset size matter.
- Threaded exports may require cross-origin isolation headers; single-threaded mode avoids some hosting friction.
- Godot web is good for embedded/spectator/demo flows, but startup time and mobile browser behavior must be tested early.

## React Native Android embedding

Official Godot docs say the Godot Engine for Android is designed as an Android library. The Android library is packaged as an AAR and supports embedding Godot within existing Android apps. Official docs describe:

- `GodotFragment` / `GodotActivity` / raw `Godot` instance.
- host Activity implementing `GodotHost`.
- passing command-line args such as `--main-pack`.
- bidirectional host/Godot communication via Android plugins and signals.
- a GLTF Viewer sample that embeds Godot as an Android view.

Important official constraints:

- only one Godot Engine instance is supported per process;
- automatic resizing/orientation configuration events are not supported and may crash unless handled/locked;
- Godot project files can live under Android assets or be passed as a PCK/ZIP main pack.

React Native implication: Android embedding is not inherently hacky. A React Native native view/module can host the official Godot Android library, and `@borndotcom/react-native-godot` wraps that style of integration.

## React Native iOS embedding

Official Godot iOS docs focus on exporting a Godot app as a complete Xcode project and on iOS plugins. They do not expose an upstream `GodotView` equivalent to Android’s `GodotFragment` in the normal docs reviewed here.

The practical iOS embedding path found in this research is community/fork based:

- Migeran LibGodot compiles Godot as a static or shared library.
- LibGodot exposes lifecycle control over GDExtension APIs: startup, iteration, shutdown.
- On Apple platforms, LibGodot can render Godot windows into host-provided native surfaces.
- The README describes `DisplayServerEmbedded`, `RenderingNativeSurfaceApple`, and a SwiftUI sample rendering multiple Godot windows on iOS.
- LibGodot notes only one Godot instance per process due to internal singletons/global data.

Risk: this is not normal upstream Godot iOS embedding. It uses Migeran’s LibGodot fork/patch set and therefore creates version-pinning and upgrade risk.

## Born React Native Godot

`@borndotcom/react-native-godot` is the most credible RN embedding wrapper found.

Verified README claims:

- supports Android and iOS;
- built on Migeran LibGodot;
- MIT licensed;
- exposes `<RTNGodotView />`;
- runs Godot on a separate thread, away from the RN JS thread and native main thread;
- can start, stop, restart, pause, and resume the Godot instance;
- allows TypeScript/JavaScript access to the Godot API;
- supports signals, callables, property access, and `runOnGodotThread()` worklets;
- claims production use in Born applications serving millions of users.

Initialization example from the README uses the embedded display driver:

```ts
RTNGodot.createInstance([
  "--verbose",
  "--main-pack", FileSystem.bundleDirectory + "main.pck",
  "--rendering-driver", "opengl3",
  "--rendering-method", "gl_compatibility",
  "--display-driver", "embedded"
])
```

Distribution details:

- the RN package is on npm;
- LibGodot packages are downloaded separately via `yarn download-prebuilt`;
- custom LibGodot builds are supported;
- Android can use exported project folders/assets; iOS examples use PCK files.

Important source mismatch to validate: the LibGodot README says its iOS SwiftUI sample does not support the iOS Simulator due to Godot limitations, while the Born RN README includes a “Run on the iOS Simulator” section. Treat physical-device validation as mandatory before depending on simulator behavior.

## Architecture recommendation from sources

If embedded Godot is a product goal, treat React and React Native as host shells and Godot as the gameplay renderer:

```text
React web shell / React Native shell
  - auth/account/deck selection/coaching UI/settings
  - route/navigation/overlay UI
  - optional debug/state panels

Embedded Godot renderer
  - board/cards/hand/zones/animations/touch input
  - no game authority
  - sends commands to authoritative server
  - receives snapshots/events from authoritative server
```

Prefer direct Godot ↔ server WebSocket for high-frequency game updates. Use the React/RN bridge for shell-level events only:

- match loaded / match closed
- current highlighted card for side panel
- request overlay/action sheet
- debug logs / telemetry
- app lifecycle pause/resume

This reduces bridge pressure and keeps the gameplay renderer portable across web and mobile hosts.

## Main risks

- iOS embedding depends on LibGodot/community tooling, not the normal upstream Godot export path.
- Godot version upgrades may depend on LibGodot and RN wrapper releases.
- Single Godot instance per process affects app architecture.
- Orientation/resizing needs to be controlled and tested on Android.
- Startup time, pack size, hot updates, and asset delivery need product-level decisions.
- The bridge should not carry every card movement if Godot can speak to the server directly.

## Validation spike

Minimum spike:

1. Build a Godot scene with hand/active/bench/prize placeholders and one tap command.
2. Export web and embed in a React component using a canvas override.
3. Embed the same Godot project in React Native using `@borndotcom/react-native-godot`.
4. Send one command from Godot to the server/mock and animate the server-confirmed response.
5. Test on physical Android and iOS, plus desktop web.

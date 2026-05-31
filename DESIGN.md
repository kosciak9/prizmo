---
name: Prizmo
description: A serious Pokémon TCG play and analysis platform with a Vesper-inspired competitive instrument interface.
colors:
  surface-root: "#101010"
  surface-raised: "#161616"
  surface-control: "#1C1C1C"
  surface-selected: "#232323"
  surface-hover: "#282828"
  line-subtle: "#505050"
  text-primary: "#F7F0E8"
  text-muted: "#A0A0A0"
  text-dim: "#7E7E7E"
  accent-primary: "#FFC799"
  accent-primary-hover: "#FFCFA8"
  accent-mint: "#99FFE4"
  danger: "#FF8080"
  attention: "#FF7300"
typography:
  display:
    fontFamily: "'Geist Sans', ui-sans-serif, system-ui, sans-serif"
    fontSize: "2rem"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "'Geist Sans', ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  title:
    fontFamily: "'Geist Sans', ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.01em"
  body:
    fontFamily: "'Geist Sans', ui-sans-serif, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "'Geist Sans', ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "0.04em"
  mono:
    fontFamily: "'Geist Mono Variable', ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.8125rem"
    fontWeight: 500
    lineHeight: 1.45
rounded:
  sm: "6px"
  md: "10px"
  lg: "16px"
  xl: "24px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "32px"
  3xl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.accent-primary}"
    textColor: "{colors.surface-root}"
    rounded: "{rounded.md}"
    padding: "10px 16px"
    typography: "{typography.label}"
  button-primary-hover:
    backgroundColor: "{colors.accent-primary-hover}"
    textColor: "{colors.surface-root}"
    rounded: "{rounded.md}"
    padding: "10px 16px"
    typography: "{typography.label}"
  button-secondary:
    backgroundColor: "{colors.surface-control}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "10px 16px"
    typography: "{typography.label}"
  button-ghost:
    backgroundColor: "{colors.surface-root}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.md}"
    padding: "10px 14px"
    typography: "{typography.label}"
  chip-active:
    backgroundColor: "{colors.surface-selected}"
    textColor: "{colors.accent-primary}"
    rounded: "{rounded.pill}"
    padding: "5px 9px"
    typography: "{typography.label}"
  chip-neutral:
    backgroundColor: "{colors.surface-control}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.pill}"
    padding: "5px 9px"
    typography: "{typography.label}"
  panel-table:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "24px"
  input-default:
    backgroundColor: "{colors.surface-control}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "10px 12px"
    typography: "{typography.body}"
---

# Design System: Prizmo

## 1. Overview

**Creative North Star: "The Tournament Instrument"**

Prizmo is a dark, table-first Pokémon TCG interface for players who treat practice seriously. The visual system adapts Vesper's peppermint and orange dark theme into a product UI: quiet graphite surfaces, precise peach focus, mint advantage signals, and restrained rose errors. The result should feel like a tuned instrument on a tournament table, not a game launcher, spreadsheet, or generic dashboard.

A competitive Pokémon TCG player is reviewing a cup match at a desk in evening light, with the card table, replay rail, and probability instruments open for a long session. Dark mode is the default because the scene is focused, dense, and prolonged; the interface should reduce glare while preserving exact state and fast scanning.

Prizmo rejects PTCGL's casual glossy game client, mobile game reward loops, and spreadsheet-style simulators. It should preserve the feeling of playing cards while making game structure, replay history, odds, and decision points inspectable when they matter.

**Key Characteristics:**

- Dark graphite table surfaces, tuned from Vesper's editor palette.
- Peach for intent: focus, active turn, primary action, current selection.
- Mint for advantage: positive probability, legal readiness, resolved success.
- Dense but composed product UI, with state clarity ahead of decoration.
- Card play remains primary; instruments orbit the table instead of replacing it.

## 2. Colors

The palette is Vesper adapted for a serious product surface: deep dark neutrals, one warm primary accent, one mint analytical signal, and sparse semantic states.

### Primary

- **Vesper Peach** (`accent-primary`): The primary accent for current turn, primary actions, focus rings, links, selected replay steps, and active player perspective. Approximate OKLCH reference: `oklch(86.89% 0.0877 60.68)`.
- **Warm Peach Hover** (`accent-primary-hover`): Hover and pressed feedback for peach controls. Approximate OKLCH reference: `oklch(88.68% 0.0747 60.72)`.

### Secondary

- **Probability Mint** (`accent-mint`): Positive probability, legal-ready confirmations, successful actions, and advantage deltas. Approximate OKLCH reference: `oklch(93.00% 0.1035 175.07)`.

### Tertiary

- **Error Rose** (`danger`): Illegal actions, destructive choices, failed requests, and explicit danger states. Approximate OKLCH reference: `oklch(74.45% 0.1550 21.50)`.
- **Live Orange** (`attention`): Rare attention state for live match following, debug-running status, or time-sensitive spectator conditions. Approximate OKLCH reference: `oklch(71.31% 0.1945 47.88)`.

### Neutral

- **Vesper Black** (`surface-root`): Root background and deepest table field. Approximate OKLCH reference: `oklch(17.30% 0 89.88)`.
- **Active Slate** (`surface-raised`): Primary panels, table trays, and persistent rails. Approximate OKLCH reference: `oklch(20.02% 0 89.88)`.
- **Control Charcoal** (`surface-control`): Inputs, buttons, compact controls, and embedded tools. Approximate OKLCH reference: `oklch(22.64% 0 89.88)`.
- **Selection Graphite** (`surface-selected`): Selected rows, active options, and replay-step backgrounds. Approximate OKLCH reference: `oklch(25.62% 0 89.88)`.
- **Hover Graphite** (`surface-hover`): Hover state for rows, menu items, and quiet interactive surfaces. Approximate OKLCH reference: `oklch(27.68% 0 89.88)`.
- **Warm White** (`text-primary`): Primary text, adapted from Vesper's pure white into a warmer near-white so the product never uses raw white.
- **Instrument Gray** (`text-muted`): Secondary text, labels, inactive icons, and less important metadata. Approximate OKLCH reference: `oklch(70.58% 0 89.88)`.
- **Disabled Gray** (`text-dim`): Placeholder, disabled, stale, and intentionally de-emphasized content. Approximate OKLCH reference: `oklch(59.31% 0 89.88)`.
- **Gutter Gray** (`line-subtle`): Dividers, rule lines, low-emphasis borders, and structural seams. Approximate OKLCH reference: `oklch(43.13% 0 89.88)`.

### Named Rules

**The Table First Rule.** Surfaces stay quiet so the card table, legal state, and player perspective win. If the chrome is louder than the board, the color is wrong.

**The Peach Is Intent Rule.** Peach means active, focused, selected, or chosen. It is forbidden as decorative trim.

**The Mint Means Advantage Rule.** Mint is reserved for positive probability, confirmed success, or legal readiness. Never use mint as a generic secondary brand color.

## 3. Typography

**Display Font:** Geist Sans, with `ui-sans-serif, system-ui, sans-serif` fallbacks.
**Body Font:** Geist Sans, with `ui-sans-serif, system-ui, sans-serif` fallbacks.
**Label/Mono Font:** Geist Sans for labels. Geist Mono Variable for logs, IDs, exact counts, and probability snippets.

**Character:** Geist gives Prizmo a serious tooling edge without turning the interface into a code editor. Use Geist Sans for almost everything; reserve Geist Mono Variable for machine-like evidence, not personality.

### Hierarchy

- **Display** (700, `2rem`, 1.05): Page titles, match-view titles, and major workflow headers only.
- **Headline** (700, `1.5rem`, 1.15): Panel group headings, replay review titles, and puzzle-builder section headers.
- **Title** (600, `1.125rem`, 1.25): Card-zone labels, prompt headings, and active tool titles.
- **Body** (400, `1rem`, 1.6): Explanations, empty states, coaching notes, and readable prose. Cap prose at 65-75ch.
- **Label** (600, `0.75rem`, 0.04em): Compact labels, badges, nav items, action metadata, and table headers.
- **Mono** (500, `0.8125rem`, 1.45): Game IDs, action logs, probability formulas, payload excerpts, exact counts, and replay timestamps.

### Named Rules

**The Instrument Label Rule.** Labels are crisp and compact. Do not use display type, novelty fonts, or oversized labels inside controls.

**The Evidence Mono Rule.** Geist Mono appears only when precision is the content: IDs, logs, odds, timing, and counts. If the text is a sentence, it is not mono.

## 4. Elevation

Prizmo uses tonal layering first and shadow second. Depth comes from the Vesper surface ramp: root, raised, control, selected, and hover. Shadows are reserved for floating menus, drag previews, and temporary overlays that must separate from the table without becoming glassy.

### Shadow Vocabulary

- **Floating Tool** (`0 18px 48px rgba(0, 0, 0, 0.36)`): Popovers, command menus, and temporary tool palettes.
- **Dragged Card** (`0 22px 60px rgba(0, 0, 0, 0.42)`): Drag or hover lift for movable card-like objects.
- **Focus Glow** (`0 0 0 3px rgba(255, 199, 153, 0.24)`): Focus-visible ring around interactive controls. Pair with an outline or border change; do not rely on glow alone.

### Named Rules

**The Tonal First Rule.** A resting surface changes tone before it casts a shadow. If every panel floats, none of them matter.

**The No Glass Table Rule.** Decorative blur, translucent glass cards, and frosted panels are prohibited. The table should feel solid and instrument-grade.

## 5. Components

Components should feel precise and durable: familiar product controls, quiet surfaces, and explicit state. Every interactive component needs default, hover, focus-visible, active, disabled, loading, and error states before it is considered production-ready.

### Buttons

- **Shape:** Controlled and tactile, medium radius (`10px`).
- **Primary:** Vesper Peach on Vesper Black, compact label typography, `10px 16px` padding. Use only for the next decisive action.
- **Hover / Focus:** Hover shifts to Warm Peach Hover. Focus-visible uses a peach ring plus a clear outline or border shift.
- **Secondary:** Control Charcoal with Warm White text for neutral actions.
- **Ghost:** Root surface with Instrument Gray text for low-emphasis actions. Ghost buttons must still have visible hover and focus states.

### Chips

- **Style:** Pill radius (`999px`), compact label typography, and low-height padding.
- **State:** Active chips use Selection Graphite with Vesper Peach text. Neutral chips use Control Charcoal with Instrument Gray text. Mint chips are reserved for legal-ready, success, or positive probability states.

### Cards / Containers

- **Corner Style:** Large table panels use composed rounded corners (`24px`). Smaller tool containers use `16px` or `10px`.
- **Background:** Root for the table field, Active Slate for persistent panels, Control Charcoal for embedded tools, Selection Graphite for selected state.
- **Shadow Strategy:** Resting panels use tonal contrast and subtle borders, not heavy shadows.
- **Border:** Use Gutter Gray sparingly at low opacity. Never use a colored side stripe.
- **Internal Padding:** Main panels start at `24px`; dense rails can use `12px` or `16px`.

### Inputs / Fields

- **Style:** Control Charcoal background, Warm White text, `10px` radius, and a subtle Gutter Gray border.
- **Focus:** Peach border and Focus Glow. The cursor and selected option should read as current intent.
- **Error / Disabled:** Error Rose for invalid state, Disabled Gray for inactive state. Include text or icon support; never rely on color alone.

### Navigation

- **Style:** Navigation is compact and table-adjacent. Use labels over decorative icons unless the icon is immediately recognizable.
- **Default / Hover / Active:** Default uses Instrument Gray, hover uses Warm White on Hover Graphite, active uses Vesper Peach with Selection Graphite.
- **Replay Rail:** Treat replay steps like navigation through time. The current step is peach, branching or alternative lines are tonal, and confirmed outcomes can use mint only when success is semantically true.

### Game-Card Zones

- **Style:** Card zones should read as physical areas on a serious table, not as identical SaaS cards. Vary scale and spacing by game meaning: active, bench, prize, discard, hand, deck, and stadium are different zones.
- **State:** Legal drop targets and selected cards need both color and structure: border, label, icon, or positional cue.
- **Density:** The board may be dense, but the active decision should remain visually discoverable within one glance.

## 6. Do's and Don'ts

### Do:

- **Do** keep the card table primary. Analysis rails, logs, percentages, and replay tools support the board.
- **Do** use Vesper Peach only for active, focused, selected, or chosen states.
- **Do** reserve Probability Mint for positive probability, legal readiness, and resolved success.
- **Do** communicate legality, danger, warnings, and player prompts with text, icons, structure, or position in addition to color.
- **Do** support visible focus, keyboard access for core actions, reduced motion, and WCAG 2.2 AA contrast.
- **Do** use dark tonal layering before shadows.
- **Do** keep motion restrained: 150-250ms state transitions using ease-out quart, quint, or expo curves.

### Don't:

- **Don't** make Prizmo feel like PTCGL's casual glossy game client, a mobile game reward loop, or a spreadsheet-style simulator.
- **Don't** use pure black or pure white in product UI. Vesper's source theme uses them; Prizmo adapts them into tinted product neutrals.
- **Don't** use colored side-stripe borders. A `border-left` or `border-right` greater than 1px as an accent is prohibited.
- **Don't** use gradient text, especially gradient backgrounds clipped to text.
- **Don't** default to glassmorphism, frosted panels, or decorative backdrop blur.
- **Don't** build identical card grids with repeated icon, heading, and text blocks. Game zones and tools need hierarchy by job.
- **Don't** use the hero-metric template for probabilities. Percentages should be contextual instruments, not trophy numbers.
- **Don't** overload mint as a decorative second accent. Mint means advantage or success.
- **Don't** animate layout properties. Motion should convey state, feedback, loading, or reveal only.

# Handoff: Ship Builder UI

## Overview
Redesign of the ship-builder screen (hex-grid ship editor, module list, save/load, presets). Target: Godot 4.x UI (Control nodes / Theme resources), implemented by a developer using GitHub Copilot.

## About the design files
`ship_builder_reference.html` is a **design reference**, not production code — an HTML/CSS mockup of the intended look and behavior. It depends on this project's internal runtime (`support.js`) and will not run standalone outside this project; open it only for visual/structural reference (or ask for exported screenshots). The task is to **recreate this UI in Godot** using Control nodes, a Theme resource, and GDScript for state/interaction — not to embed HTML/web views.

## Fidelity
**High-fidelity.** Colors, spacing, typography, and layout below are final. Icon glyphs (2-letter monospace codes) are placeholders for real module icon art — flag this to the design side if real icons are wanted later.

## Screen: Ship Builder

### Layout (full-screen, ~1920×1080 reference canvas, scales responsively)
- Root: full-bleed dark space background.
- Top-left: instruction line + a HUD stat strip (HP / MASS / EN / CARGO).
- Center-left: large hex-grid build field (fills remaining space between top HUD, right panel, and bottom bar).
- Right: fixed-width (336px) vertical panel stack — Modules card (flexes to fill height), Ship name/Save row, collapsible Presets card.
- Bottom-left: cell-count readout + Rotate / Remove Selected / Validate Layout buttons.
- Bottom-center: status line (docking/context hint).

### Components

**Background**
- Base: near-black `#0a0d12`.
- Two soft radial glows: `rgba(42,60,75,0.35)` bottom-left, `rgba(42,90,100,0.18)` top-right, for atmosphere (large, low-opacity radial gradients, ~700–900px).
- Faint drifting star dots (5 small radial-gradient dots, slow diagonal drift loop, ~90s).

**Top HUD**
- Instruction text: 13px monospace, `#c7d0d8`. Dynamic: "Select a module type, then click an adjacent cell." → "Selected: {Module Name} — click an adjacent cell to place it." when a module is chosen.
- Stat strip: translucent panel `rgba(15,19,24,0.5)` + backdrop blur, 1px border `rgba(85,214,232,0.22)`, radius 4px, padding 9×16.
  - Each stat: small 6px status dot (glow via drop shadow) + 10px monospace label (`#7c8b99`, letter-spacing 0.1em) + 12px monospace value (`#e8edf0`).
  - HP dot: `#7ce8b8` (green — swap to amber `#f2c14e` / red `#e2684a` at low health, thresholds ~50%/20%).
  - EN dot: cyan `#55d6e8`.
  - 1px vertical dividers `rgba(255,255,255,0.1)` between stats.

**Hex grid field**
- Container: rounded 6px, inset 1px border `rgba(85,214,232,0.14)`, background = radial glow + dark linear gradient (`#0d1117` → `#0a0d12`).
- Grid: pointy-top hex outlines (vertex top/bottom, flat left/right edges), stroke `rgba(85,214,232, op)` 1px, near-invisible fill. Opacity per-hex fades from ~0.22 at grid center to ~0.05 at the edges (radial falloff) — reads as depth, not a rigid grid. In Godot: draw with a `TileMap`/custom `_draw()` using `draw_polyline` per hex, or precompute a texture.
- Vignette: radial gradient overlay darkening outer ~40–100% radius over the grid, to focus attention center.
- Placed modules (ship-under-construction): small hex tiles (56×64px at reference scale), same hex clip shape, gradient fill per module type (see module colors below), centered 2-letter glyph, drop-shadow glow (stronger cyan glow on Command Core). Currently-buildable/selected adjacent cell shown as a dashed cyan hex outline with a slow pulse (opacity 0.55↔1, ~2.4s).

**Modules panel** (right, top card)
- Card: `rgba(15,19,24,0.72)` + blur, border `rgba(85,214,232,0.25)`, radius 5px.
- Header: "MODULES" 13px monospace bold, letter-spacing 0.08em, `#e8edf0`.
- Filter tabs below header: All | Structure | Weapons | Utility | Owned. Pill buttons, 10.5px monospace. Active tab: filled `#55d6e8` bg, `#0a0d12` text. Inactive: `rgba(255,255,255,0.03)` bg, `#8fa0ab` text, `rgba(255,255,255,0.08)` border.
- List grouped by category, in order: **Core, Structure, Propulsion, Weapons, Utility, Storage**. Category label: 10.5px monospace, `#5f6d78`, letter-spacing 0.12em, uppercase.
- Module row: hex icon (gradient-filled per module, 2-letter glyph) + name (13px, system font) + "CRAFT" button (right-aligned pill, cyan outline).
  - Owned count: small badge bottom-right of the icon (dark bg, cyan border, cyan 9px monospace number). Hidden if 0.
  - **Default row**: 1px border `rgba(255,255,255,0.06)`, bg `rgba(255,255,255,0.02)`, icon 38×44px, name weight 400, glyph 10px.
  - **Selected row**: 2px border `rgba(85,214,232,0.85)`, bg `rgba(85,214,232,0.16)`, outer glow `0 0 16px rgba(85,214,232,0.18)`, icon enlarged to 48×55px, glyph 12px, name weight 600 / brighter `#f0f6f8`. An expansion strip appears directly below the row (no gap, joined bottom corners) showing `COST · {cost text}` and `OWNED · {count}` in 11px monospace `#8fa0ab` on a faint cyan tint background.
  - Clicking a row toggles selection (click again to deselect); clicking Craft also selects it (stops the row's own click from double-firing).

**Ship name / Save row** (right, middle card)
- Same card treatment. Text input (dark `#0a0d12` bg, cyan 1px border, 12px monospace) + SAVE button (cyan outline pill).

**Presets card** (right, bottom card, collapsible)
- Header row "LOAD FROM PRESET" (12px monospace, `#a8b4bd`) + chevron, click to expand/collapse (starts collapsed).
- Expanded: scrollable list (max-height 150px), each preset row = name (monospace) + "LOAD" affordance (cyan, dimmed), hover highlight `rgba(85,214,232,0.1)`.

**Bottom bar**
- Cell-count pill: `{used}/{max}` (e.g. 63/160), translucent dark panel, cyan border, dropdown chevron (intended as a build-size/grid-scale selector).
- Button group: ROTATE (neutral cyan outline), REMOVE SELECTED (warm/red outline `rgba(226,104,74,0.35)` border, `#d99a86` text — destructive), VALIDATE LAYOUT (neutral cyan outline). All 12px monospace, radius 4px, hover = fill brightens.
- Status line (bottom-center, full width): 12px monospace, `#5f6d78`, e.g. "Near Corporate Station — U: Upgrade B: Build T: Trade".

## Interactions & behavior
- Selecting a module row = "arm" it for placement (mirrors the original click-adjacent-cell mechanic); toggles off on second click.
- Filter tabs re-filter the visible module list instantly (no animation needed beyond the existing 0.12s color/border transitions on rows).
- Presets section is collapsed by default; toggling animates the chevron 180° (0.15s).
- Craft button and row selection are separate actions in this mock (Craft currently just selects, in the real game it should trigger the actual crafting/build action — clarify with design/gameplay if Craft should also auto-arm placement).

## Design tokens
- Background: `#0a0d12` (base), `#0d1117` (panel gradient dark end), `#171d24` (input/card dark fill).
- Cyan accent (primary interactive): `#55d6e8` (mid), `#8fe9f2` (bright/text-on-dark), `#2a8fa3` (deep).
- Amber (warm highlight / propulsion): `#f2c14e`, `#a3822f`.
- Slate (structure/neutral): `#4a5763`, `#2b3542`, `#333f4d`, `#5a6b7a`.
- Warning/destructive: `#e2684a`, `#a35a3a`.
- Text: `#e8edf0` (bright), `#c7d0d8` (default body), `#a8b4bd` / `#8fa0ab` (muted), `#7c8b99` / `#5f6d78` (labels/hints).
- Fonts: monospace (labels, values, HUD, buttons) + system UI sans-serif (module names only). No custom font files needed — use a monospace font available in the target engine (e.g. a bundled mono font in Godot's theme).
- Radius: 3px (small controls/buttons), 4px (medium), 5–6px (cards/panels).
- Hex shape ratio: width : height = 222 : 256 (matches the game's existing hex-tile art spec in `STYLE_GUIDE.md`).

## Assets
No bitmap/vector assets used — everything is gradients, CSS shapes, and text. Module icons are 2-letter monospace glyph placeholders (CC, HL, HH, ST, EN, WM, SA, CB) on gradient-filled hexes; swap for real module icon art from the existing asset set when available. Full module data (name, category, cost, owned count, gradient colors) is in `module_data.json`.

## Files
- `ship_builder_reference.html` — HTML/CSS design reference (view in-browser via the design tool, not standalone).
- `module_data.json` — module/category/preset data backing the mock, ready to adapt into a Godot Resource or JSON-loaded table.
- `STYLE_GUIDE.md` — the game's existing faction art/color-system spec this UI's palette was derived from (Corporate slate/cyan/amber family).

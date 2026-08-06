# Handoff: Ship Upgrade Tree

## Overview
The module-upgrade screen. A left rail lists upgradeable ship systems (Hull, Propulsion, Weapons,
Power, Storage, Sensors, Mining); the main area shows that system's upgrade tree as a radial fan of
nodes, each unlockable once its prerequisites are met. The panel below the rail describes whatever
node the player is pointing at and carries the unlock action.

Companion screen to the existing ship-builder handoff — same game, same palette, same dark-space
treatment.

## About the design files
`upgrade_tree_reference.html` is a **design reference**, not production code. It is a self-contained
HTML/CSS/JS prototype: open it directly in a browser (no server, no build step) to click through the
real interaction — switching categories, hovering nodes, unlocking them, watching branches light up.

The task is to **recreate this screen in the target codebase's own environment** — for this project,
Godot 4.x Control nodes with a Theme resource and GDScript — using its established patterns. Do not
embed the HTML or a web view.

Read `LAYOUT_SPEC.md` alongside this file. It documents the data schema and the polar layout
algorithm in implementation detail; this README covers appearance, behavior and tokens.

## Fidelity
**High-fidelity.** Colors, spacing, typography, geometry and interaction states below are final.

Two known placeholders:
- **Node icons.** Every node currently shows a 2-letter monospace glyph. The data schema already has
  an `icon` slot per node; when art exists, set it and the glyph is replaced automatically. Nothing
  else needs to change. Icons render centered at 52% of the node diameter.
- **Costs** are display strings ("18 Titanium, 8 Wiring"). Replace with a structured cost type wired
  to the real inventory.

## Screens / Views

### Screen: Module Upgrades

Full-screen, two columns. Reference canvas 1920×1080, but the tree scales to fit any panel size.

#### Layout
- Root: full-bleed dark space background, `display:flex`, height 100%.
- **Left rail** — fixed 250px, `rgba(15,19,24,0.55)` + backdrop blur, 1px right border
  `rgba(85,214,232,0.18)`, vertical padding 26px. Contains, top to bottom: screen title, the category
  list, then the detail panel pinned to the bottom of the rail.
- **Main column** — fills the rest. A header row, then the tree area (`flex:1`, `overflow:hidden`).

#### Components

**Background** (same treatment as the ship-builder screen)
- Base `#0a0d12`.
- Two soft radial glows: `rgba(42,60,75,0.30)` bottom-left (~900×700), `rgba(42,90,100,0.16)`
  top-right (~700×500).
- Faint drifting star dots — 4 small radial-gradient dots, slow diagonal drift, 90s loop.
- Behind the tree only: a radial glow tinted to the active category's hue,
  `oklch(0.4 0.08 <hue> / 0.22)` fading out at 70%, anchored to the arc's center.

**Screen title**
- "Module Upgrades", 19px system sans, weight 600, `#e8edf0`, padding `0 22px 20px`.

**Category list**
- Row: `display:flex`, space-between, padding `13px 22px`, cursor pointer, 3px left border,
  0.12s background transition.
- Inactive: transparent bg, transparent left border, label `#a8b4bd` weight 400.
- Hover: bg `rgba(255,255,255,0.04)`.
- Active: bg `oklch(0.78 0.14 <categoryHue> / 0.14)`, left border `oklch(0.78 0.14 <categoryHue>)`,
  label `#f0f6f8` weight 600.
- Label 14.5px system sans. Right-aligned progress `{unlocked}/{total}` in 11px monospace —
  `#5f6d78` inactive, category accent when active.

**Header row** (main column, padding `16px 40px 6px`)
- Left: category name 22px weight 600 `#f0f6f8`, then "Upgrade Tree" 13px monospace `#5f6d78`.
- Right: branch legend (only for categories with coloured branches — currently Weapons): per branch a
  8px dot in the branch hue + 11px monospace name, `#c7d0d8` once that branch root is unlocked else
  `#7c8b99`. Then `{unlocked}/{total} unlocked`, 13px monospace in the category accent.

**Tree** — see `LAYOUT_SPEC.md` for the geometry. Visual treatment per node:

| State | Fill | Border | Glow | Glyph |
|---|---|---|---|---|
| Unlocked | `linear-gradient(155deg, oklch(0.78 0.14 H), oklch(0.4 0.06 H))` | 1px `oklch(0.78 0.14 H)` | `0 0 14px oklch(0.78 0.14 H / 0.4)` | `#0a0d12` |
| Available | `rgba(15,19,24,0.85)` | **2px dashed** `oklch(0.78 0.14 H)` | `0 0 10px … / 0.25` | accent |
| Locked | `rgba(15,19,24,0.6)` | 1px `rgba(255,255,255,0.14)` | none | `#5f6d78` |

- Available nodes pulse: `drop-shadow` 3px → 11px and back, 2.2s ease-in-out, infinite.
- Diameter: 60px root, 54px merge nodes, 48px normal. Glyph 26% of diameter, monospace weight 700.
- **Merge nodes** (2+ prerequisites) are filled with a `135deg` gradient across the hues of *every*
  branch feeding them — the cue that more than one line of research is required. When available,
  their dashed border takes the second branch's hue.
- Connectors: 2.2px `rgba(255,255,255,0.1)` when the parent is locked; 2.2px
  `oklch(0.7 0.07 H / 0.4)` when the parent is unlocked but the child isn't; 3px
  `oklch(0.8 0.1 H / 0.8)` when both ends are unlocked. Round caps and joins.
- Tier guide arcs: 1px dashed (`2 6`) `oklch(0.45 0.05 H / 0.22)`, one per tier.
- Node labels: 13px monospace, 104px wide centred box, line-height 1.25. `#c7d0d8` unlocked,
  `#e8edf0` available, `#5f6d78` locked.

**Detail panel** (bottom of the left rail, margin `auto 16px 0`)
- Card: `rgba(10,13,18,0.6)`, 1px border, radius 6px, padding `14px 16px`, 8px gap.
- Border: node accent when unlocked or available, else `rgba(255,255,255,0.15)`.
- Rows: name 14.5px weight 600 `#f0f6f8` + tier tag ("TIER 3" / "BASE MODULE") 10.5px monospace
  `#5f6d78`; description 12.5px `#a8b4bd` line-height 1.45; `COST · …` 11px monospace `#7c8b99`.
- For merge nodes only, a **REQUIRES ALL** block: 10.5px monospace `#5f6d78` header, then one row per
  prerequisite — 7px dot (branch hue when met, `rgba(255,255,255,0.2)` when not) + 11.5px monospace
  name (`#c7d0d8` met, `#7c8b99` not).
- Button: full width, 12px monospace, letter-spacing 0.05em, padding `9px 12px`, radius 4px.
  - Available: `UNLOCK`, bg `oklch(0.78 0.14 H / 0.15)`, border + text in the node accent.
  - Unlocked: `UNLOCKED`, bg `rgba(255,255,255,0.06)`, border `rgba(255,255,255,0.15)`, text
    `#7ce8b8`, disabled.
  - Locked: `LOCKED`, bg `rgba(255,255,255,0.03)`, border `rgba(255,255,255,0.1)`, text `#5f6d78`,
    disabled.

## Interactions & behavior
- **Category select** — click a rail row to switch trees; clears the current node selection and
  persists the choice (see State).
- **Node hover** — fills the detail panel. Hover takes precedence over the last click, so the panel
  tracks the pointer and never flickers empty on mouse-out (it falls back to the selection).
- **Node click** — if the node is *available*, unlock it and select it. Otherwise just select it, so
  locked nodes can still be inspected. The panel's UNLOCK button performs the same action.
- **Unlock ripple** — unlocking a node re-derives availability for its children, so newly unlockable
  nodes start their dashed pulse immediately and the connector to the parent brightens. There is no
  explicit animation to author; it falls out of the state change. A short scale/glow flourish on the
  unlocked node would be a reasonable engine-side addition.
- **Resize** — the tree is measured and uniformly scaled to fit its area (see `LAYOUT_SPEC.md` §3).
  No breakpoints; the layout is a single scaling composition.
- Transitions in the mock are limited to the 0.12s background fade on category rows and the 2.2s
  availability pulse. Everything else is instant.

## State management
- `unlocked: { [categoryKey]: nodeId[] }` — the save payload. Ids only, so adding upgrades later
  never invalidates an existing save. Root nodes are implicitly owned and are not stored.
- `activeCategory: string` — persisted (mock uses `localStorage['shipUpgrades:lastCategory']`); the
  screen reopens on the last category the player viewed, defaulting to `power`.
- `hover: nodeId | null` and `selected: nodeId | null` — transient. Panel content is
  `hover ?? selected`.
- `scale: number` — derived from the container size on resize.

Derived, not stored — recompute from `unlocked`:
```
isUnlocked(cat, id)  = id === 'root' || unlocked[cat].includes(id)
isAvailable(cat, n)  = !isUnlocked(cat, n.id) && n.parents.every(p => isUnlocked(cat, p))
```
These two predicates are the whole gameplay rule. `parents` is an AND list; arity 2+ *is* the merge
mechanic — there is no separate flag. No data fetching; the tree definitions are static content.

## Design tokens
- Background: `#0a0d12` base, `rgba(15,19,24,0.55)` rail, `rgba(10,13,18,0.6)` detail card,
  `rgba(15,19,24,0.85)` node fill.
- Category hues (OKLCH hue angle, used as `oklch(0.78 0.14 H)` bright and `oklch(0.4 0.06 H)` deep):
  Hull 210, Propulsion 95, Weapons 35, Power 190, Storage 150, Sensors 255, Mining 60.
- Weapons branch hues: Laser 195, Missile 35, Rail 305.
- Text: `#f0f6f8` bright, `#e8edf0` strong, `#c7d0d8` body, `#a8b4bd` muted, `#7c8b99` label,
  `#5f6d78` hint. Success `#7ce8b8`.
- Borders: `rgba(85,214,232,0.18)` rail edge, `rgba(255,255,255,0.14)` locked node,
  `rgba(255,255,255,0.15)` inert card.
- Type scale: 22 / 19 / 14.5 (system sans) · 13 / 12.5 / 11.5 / 11 / 10.5 (monospace).
- Radius: 4px buttons, 6px cards, 50% nodes.
- Geometry constants: `BASE_R 78`, `STEP 104`, `MAX_ANGLE ±72°`, merge radius offset `+0.4 × STEP`.

Colors are authored in OKLCH so a category's whole palette derives from one hue number. If the
target engine has no OKLCH support, precompute each hue's bright/deep pair to sRGB once and store
them on the category resource.

## Assets
No bitmap or vector assets. Everything is gradients, CSS shapes and text.

Node icons are **not yet implemented** — each node shows a 2-letter monospace glyph placeholder. The
`icon` field is reserved in the schema for real art; 89 nodes across 7 categories will eventually
need one. Glyph codes are in `upgrade_data.json` and are intended as a fallback, not final art.

## Files
- `upgrade_tree_reference.html` — self-contained design reference. Opens directly in a browser.
- `upgrade_data.json` — all 7 categories and 89 nodes, plus an inline `_schema` block describing
  every field. Ready to adapt into a Godot Resource or JSON-loaded table.
- `LAYOUT_SPEC.md` — data model, how to add upgrades/branches/categories, and the polar layout
  algorithm (span allocation, mirroring, merge placement, elbow connectors, label anchoring,
  fit-to-panel). Read this before implementing the tree rendering.
- `STYLE_GUIDE.md` — the game's existing faction art/color spec this palette derives from.

# Handoff: Scanner Radar (directional scan replacement)

## Overview
Replaces the ship HUD's existing scanner — a loading bar that resolves into a static "top 5 nearest contacts" text list — with a **directional, time-of-flight radar instrument**. The player aims a beam, fires, and returns arrive progressively as the wavefront reaches each object (1000 units ≈ 1 second, so a 2500u asteroid resolves at 2.5s). Contacts persist on screen until the next scan, and the emitter has a cooldown before it can fire again.

Four alternative presentations of the same underlying scan model are included as design options (1A–1D). **Only one is intended to ship**; the others exist for comparison. 1D was the direction the team responded to most strongly, with 1C second.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behaviour, not production code to copy directly. `Scanner Radar.dc.html` is authored in a bespoke HTML component format used by the design tool; the parts that matter are the `<canvas>` drawing routines and the interaction handlers inside the logic class, which are plain JavaScript and translate directly.

The task is to **recreate these designs in the target codebase's existing environment** (game engine, React HUD layer, canvas/WebGL overlay, etc.) using its established patterns. All four scanners are drawn with the 2D canvas API and a `requestAnimationFrame` loop, so the drawing code ports with little change; the surrounding layout, buttons, and return-list markup should be rebuilt with whatever UI layer the game HUD already uses.

## Fidelity
**High-fidelity.** Colours, typography, geometry, timings, and interaction behaviour are final-intent. Recreate pixel-accurately where the codebase allows. The only deliberately unfinished areas: contact type set is a placeholder sample list, and no audio design exists yet.

---

## Scan model (shared by all four options)

| Constant | Value | Meaning |
| --- | --- | --- |
| `MAXR` | 3000 units | Max scan range. **This is the upgradeable stat** — scanner upgrades increase it. |
| `SPEED` | 1000 units/sec | Wavefront travel speed. Fixed. |
| `COOLDOWN` | 6000 ms | Dead time after the wavefront completes before the emitter can fire again. |
| Scan duration | `MAXR / SPEED` = 3s at base range | Wavefront transit time. |
| Ready-at | `fireTime + MAXR/SPEED*1000 + COOLDOWN` | Full cycle = 9s at base range. |

Sequence of a scan:
1. Player sets beam direction/width (all options except 1B, which is omnidirectional).
2. Player fires. Fire is rejected if `now < readyAt`.
3. Wavefront expands from the ship at 1000u/s. Each frame, any object that is (a) inside the beam arc and (b) at range ≤ current wavefront reach and ≤ MAXR is added to the hit list, timestamped.
4. Each new hit appends a row to the returns list under the display and draws a persistent marker plus a one-second expanding ping ripple.
5. When reach ≥ MAXR the wavefront stops. If no hits, status line reads a "no returns" message.
6. Hits persist — markers and list rows stay on screen — until the next scan clears them.

Sample contact set used in the prototype (bearing in degrees, 0° = right/east, positive = clockwise/down in screen space; range in units):

```
Asteroid   -34°   780     Asteroid    62°   940
Asteroid   -12°  1180     Ice chunk  128°  1660
Ice chunk  -50°  1520     Asteroid   168°  2260
Asteroid   -26°  2050     Derelict  -142°  1340
Wreck      -44°  2480     Asteroid   -96°  2700
```

Contact types and their marker colours: `rock #7ee0a0`, `ice #8fe9f2`, `wreck #f2c14e`.

---

## Screens / Views

All four options share the same column shell:

- Column width **360px**, vertical flex, `gap: 12px`.
- **Header row**: option badge (monospace 11px, `letter-spacing: 0.12em`, dark text `#0a0d12` on the option's accent colour, `padding: 2px 7px`, `border-radius: 3px`) + title (system sans 14px, weight 600, `#c7d0d8`).
- **Display**: 360×360 canvas inside a bordered container, `border-radius: 8px`, 1px border in the option accent at ~14–16% alpha.
- **Control row**: fire button + two monospace 11px readouts, `gap: 12px`.
- **Returns list**: 360px wide, `min-height: 96px`, 1px top border in the accent at 12% alpha, `padding-top: 10px`, rows in a vertical flex with `gap: 5px`. Each row is monospace 12px, `display:flex; gap:10px; align-items:baseline`, animating in with `blipIn` (220ms ease-out, fade + 4px rise). When there are no returns, a single status line renders in `#3d4750` instead.

Fire button: monospace 11px, `letter-spacing: 0.14em`, `padding: 7px 14px`, `border-radius: 3px`, `min-width: 96px`, centred, dark text `#0a0d12` on the accent. While cooling down it swaps to label `COOL 4.3s` (one decimal, updating live) on `rgba(76,90,102,0.35)` with `#6b7784` text, and clicks are ignored.

Canvases are sized for device pixel ratio: backing store `360 * dpr` square, CSS size 360px, context transform `setTransform(dpr,0,0,dpr,0,0)`.

---

### 1A — Directional cone
Accent `#55d6e8`. Button `SCAN`. Readouts: `ARC 46°`, `HDG -30°`.

The familiar circular radar. Ship at centre, range rings at 1000/2000/3000 units (outer ring `rgba(85,214,232,0.34)`, inner rings `0.13`, each labelled in `rgba(107,119,132,0.65)` monospace 10px just inside the ring at the top). Spokes every 45° at `rgba(85,214,232,0.07)`.

- **Beam cone**: wedge from centre to R=150px, filled with a radial gradient `rgba(85,214,232,0.30)` at the centre fading to `0.04` at the rim, stroked `rgba(85,214,232,0.42)`. Because it is a wedge, it widens naturally toward the rim.
- **Handles**: two amber `#f2c14e` triangles just outside the rim (R+11) at the cone edges, rotated to point inward.
- **Interaction**: pointer-down within ±16° of a handle and within R±26px grabs that edge and resizes the arc (clamped 8°–180°, symmetric about the heading); pointer-down inside the cone grabs and rotates it; pointer-down anywhere else snaps the heading to that bearing.
- **Wavefront**: an arc spanning the cone at the current reach radius — 2.5px bright `rgba(143,233,242,0.9)` with a 5px trailing arc at `0.25` seven pixels behind it.
- **Hits**: 8px diamond in the type colour at the polar position, range label in `rgba(199,208,216,0.75)` 8px to its right, plus an expanding ring ripple (radius 4→20px over 1s, alpha 0.5→0).
- **Returns list columns**: index, name, range, signed bearing.

### 1B — Coordinate grid
Accent `#f2c14e`. Button `PULSE`. Readout: `OMNI · 3000u`.

Omnidirectional; no aiming. A square 8×8 grid (`pad` 26px, so the plot is 308px) labelled A–H across the top and 1–8 down the left in `rgba(107,119,132,0.7)` monospace 10px. Grid lines `rgba(242,193,78,0.10)`, outer frame `0.28`. Ship marker at centre: 3.5px `#8fe9f2` dot inside a 7px ring at `rgba(143,233,242,0.4)`.

- **Pulse**: an expanding circle clipped to the grid rect — 2px `rgba(242,193,78,0.75)` with a 4px trail at `0.18`.
- **Hits**: a dashed (3,4) uncertainty circle whose radius is 9% of the contact's range (plus a 6px floor), filled `rgba(126,224,160,0.07)`, stroked `rgba(126,224,160,0.35–0.6)` (brighter for one second after arrival). A 2.5px type-coloured dot marks the estimate centre, and the grid cell label sits just outside the circle.
- Design intent: this option deliberately reports *approximate* positions — "somewhere in D4" — rather than a precise fix.
- **Returns list columns**: cell, name, range, ± error (range × 9%, rounded to 10u).

### 1C — Bearing strip (B-scope)
Accent `#c98fe8`. Button `SWEEP`. Readouts: `SECTOR 70°`, `HDG -30°`.

The circular dial unrolled into a rectangle. Plot area `x0:34, y0:22, w:312, h:308`. **Horizontal axis is bearing −180°→+180°; vertical axis is range, 0 at the bottom, MAXR at the top.**

- Range gridlines every 500u (`rgba(201,143,232,0.07)`, every 1000u at `0.16` and labelled at the left in `rgba(107,119,132,0.75)`). Bearing gridlines every 45° at `rgba(201,143,232,0.08)`, the 0° line at `0.22`, labelled below the plot centred on the tick. **The ±180° labels are deliberately omitted** — they would collide with the neighbouring −135°/+135° labels; the plot border marks the wrap.
- **Sector band**: a vertical band spanning the beam, filled with a vertical gradient from `rgba(201,143,232,0.05)` at the top to `0.24` at the bottom, edges stroked `rgba(201,143,232,0.5)`, with amber `#f2c14e` arrow markers below the plot. The band **wraps**: a sector crossing ±180° renders as two bands, one at each end of the strip.
- **Interaction**: pointer-down within 10° of an edge drags that edge (width clamped 10°–240°); anywhere else re-centres the sector on the clicked bearing and continues to drag it.
- **Sweep**: a horizontal line climbing the strip, drawn only inside the sector band(s) — 2px `rgba(232,200,255,0.95)` with a 26px gradient glow trailing below.
- **Hits**: 10px diamond in the type colour at (bearing, range), a ripple ring as in 1A, and a label `AST 780` in `rgba(199,208,216,0.8)` to the right.
- **Returns list columns**: index, name, range, signed bearing.

### 1D — Return trace (A-scope) — recommended
Accent `#7ee0a0`. Button `PING`. Readouts: `BEAM 40°`, `GAIN 50dB` (computed `60 - beamWidth × 0.25`, rounded — narrower beam reads as higher gain).

An analogue oscilloscope trace. **Horizontal axis is range, not position; vertical axis is signal strength.** Bearing is set separately and is not on the plot.

- **Beam bar** (top): caption `BEAM BEARING — drag to aim` at y=22 in `rgba(107,119,132,0.7)`; a 312×20 bar at y=34 with a 1px `rgba(126,224,160,0.2)` frame and tick marks every 45°. The active beam renders as a `rgba(126,224,160,0.3)` fill with amber `#f2c14e` arrow markers below its edges. The numeric bearing readout right-aligns to the bar's right edge **minus 28px** to clear the help toggle.
- **Beam interaction**: same model as 1C — within 10° of an edge drags that edge (width clamped 6°–120°); elsewhere re-aims and drags.
- **Trace** (plot `x0:34, y0:84, w:312, h:246`): a 260-segment polyline redrawn every frame, stroked 1.4px `rgba(126,224,160,0.92)` with a 6px `rgba(126,224,160,0.55)` shadow for phosphor glow. Baseline sits 14px above the plot floor.
  - Noise: per-sample static (a fixed random array, ±2.5px) plus a slow travelling sine (`sin(now/260 + i*0.7) × 1.4`), both scaled by `0.25 + 0.75 × (range/MAXR)` — **noise grows with distance**, so far contacts are genuinely harder to read.
  - Returns: each hit adds a Gaussian bump at its range. Amplitude = type strength (`wreck 1.0`, `ice 0.78`, `rock 0.62`) × `(1 − range/MAXR × 0.45)` × 72% of plot height. Width σ = `34 + range × 0.012` px — **peaks smear wider the further out they sit**.
- **Legibility affordances** (added deliberately so the display is hard to master but not mysterious): axis captions `RANGE (units) →` under the right end and a rotated `↑ SIGNAL` at the left; a dashed (2,4) noise-floor line at the baseline labelled `noise floor` in `rgba(107,119,132,0.5)`.
- **Transmit line**: a 1.5px `rgba(224,255,236,0.85)` vertical line walking left→right at the wavefront range, with a 40px gradient trail behind it.
- **Peak callouts**: once resolved, each peak gets a dashed leader from just above its apex to a label box — `rgba(10,16,13,0.85)` background, text in the type colour, reading `ASTEROID · 780u` — plus a 2px type-coloured tick at the baseline. Labels **stagger upward in 14px rows** when their boxes would overlap horizontally; the leader line extends to meet the label's final row.
- **Help overlay**: a 20px `?` circle at top-right (1px `rgba(126,224,160,0.4)` border, `#7ee0a0` glyph, hover fill `rgba(126,224,160,0.15)`) toggles a full-panel card at `rgba(8,14,11,0.94)`, 18px padding, monospace 11px / 1.5 line-height in `#9fb3a8`, explaining beam bar, transmit line, peaks, and noise floor, with a `CLOSE` button. Copy is in the prototype file verbatim.
- **Returns list columns**: index, name, range, signed bearing.

---

## Interactions & Behavior

- **Aiming** is pointer-capture based: `pointerdown` on the canvas classifies the grab (edge / body / re-aim), then `pointermove` on the canvas updates the beam until `pointerup`. All angle deltas are normalised into −180…+180 before use, and there is no snapping or inertia.
- **Firing** is rejected silently while cooling down; the button's disabled appearance is the only feedback. Consider adding a short error tone or a shake when wiring this into the game.
- **Cooldown countdown** updates at one-decimal resolution, driven from the same animation frame loop (state is only pushed when the rounded value changes, to avoid a re-render every frame).
- **Ping ripple** on each new hit: 1 second, radius grows from 4→20px, alpha 0.5→0, `rgba(126,224,160,α)`.
- **Return rows** animate in with `blipIn` — 220ms ease-out, `opacity 0→1` and `translateY(4px)→0`.
- **Persistence**: hits and their list rows are cleared only when a new scan starts. No fade-out, no timeout.
- **Idle status lines**: `IDLE — drag arrows to aim, then SCAN` (1A), `IDLE — press PULSE` (1B), `IDLE — drag sector edges, then SWEEP` (1C), `IDLE — drag the beam bar, then PING` (1D). Mid-scan: `SCANNING…`, `PULSE OUTBOUND…`, `SWEEPING…`, `TRANSMITTING…`. Empty result: `NO RETURNS IN ARC`, `NO RETURNS`, `NO RETURNS IN SECTOR`, `NOISE ONLY — NO RETURN`.

## State Management

Per scanner instance:

- `aim` (degrees, −180…180) — beam heading. Not used by 1B.
- `width` (degrees) — beam arc. Clamps: 1A 8–180, 1C 10–240, 1D 6–120. Not used by 1B.
- `t0` (timestamp | null) — scan start; null when idle or complete.
- `hits: [{ object, t }]` — resolved contacts with arrival timestamps.
- `readyAt` (timestamp) — cooldown gate.
- 1D also holds a fixed 260-entry random noise array, generated once at mount so the static pattern is stable between frames.

Aim/width live in a mutable instance object read by the draw loop (so dragging does not force a re-render per frame); only the values shown as text are mirrored into render state. Preserve that split if the target framework re-renders on state change.

Data the real implementation must supply: the contact list for the current sector, each entry needing `{ name, type, bearing, range }` in ship-relative polar coordinates at scan time. Contacts should be sampled **once when the scan fires**, not tracked live — the display represents a snapshot from a pulse, and letting markers follow moving objects would break the fiction.

## Design Tokens

Colours
- Background `#0a0d12`; panel fills `rgba(20,26,33,0.5)` (1B/1C), `rgba(16,22,19,0.6)` (1D).
- Text: primary `#c7d0d8`, secondary `#6b7784`, dim/status `#3d4750`, list muted `#4c5a66`.
- Option accents: 1A cyan `#55d6e8` (bright `#8fe9f2`), 1B amber `#f2c14e`, 1C violet `#c98fe8` (bright `#e8c8ff`), 1D green `#7ee0a0` (bright `#e0ffec`).
- Contact types: rock `#7ee0a0`, ice `#8fe9f2`, wreck `#f2c14e`.
- Handles/arrows: `#f2c14e` in every option.
- Cooldown button: fill `rgba(76,90,102,0.35)`, text `#6b7784`.

These sit inside the project's existing Corporate/neutral HUD palette (see `STYLE_GUIDE.md`): slate hulls, cyan accent family, amber warm highlight. The violet 1C accent is the one new hue — it was introduced to keep four options visually separable and should be dropped or re-derived from the shared oklch band if 1C ships.

Typography
- Instrument text and all readouts: monospace (`ui-monospace, Menlo, monospace`), 10px on canvas, 11px for readouts/buttons, 12px for return rows.
- Letter-spacing: 0.08em on readouts, 0.12em on badges and help headings, 0.14em on buttons.
- Titles and body copy: system sans (`system-ui, -apple-system, Segoe UI, sans-serif`), 22px/600 page title, 14px/600 option titles, 13px body.

Geometry
- Canvas 360×360; polar radius 150px; grid pad 26px; 1C/1D plot insets as listed per option.
- Border radius: 8px displays, 3px buttons and badges, 50% help toggle.
- Column gap 28px between options; page padding 48px.

Timing
- Wavefront 1000 units/sec; cooldown 6s; ping ripple 1s; row entrance 220ms ease-out; noise sine period ~1.6s.

## Assets
None. Every element is drawn with the 2D canvas API or plain DOM — no images, icons, or fonts beyond system stacks. No Anthropic brand assets are used.

## Files
- `Scanner Radar.dc.html` — all four options. Template markup first (layout, buttons, returns lists, 1D help overlay), then the logic class containing the constants, contact list, pointer handlers, and the four `draw*()` routines: `drawPolar` (1A), `drawGrid` (1B), `drawBscope` (1C), `drawScope` (1D).
- `Ship HUD.dc.html` — the existing HUD this scanner sits inside; contains the current small corner radar dial and the bar treatments the scanner should sit alongside.
- `STYLE_GUIDE.md` — project-wide palette and construction rules.
- `support.js` — runtime for the `.dc.html` format. Needed only to open the prototypes in a browser; not part of the design.

To view the prototypes, open `Scanner Radar.dc.html` directly in a browser with `support.js` alongside it.

## Open questions for implementation
- Range is the upgrade axis (`MAXR`). Decide whether upgrades also lower the 1D noise floor or shorten the cooldown.
- No audio design exists. An A-scope in particular wants a transmit chirp and a per-return blip.
- Contact type list is a placeholder; extend `TCOL` and the 1D strength table as real types are added.

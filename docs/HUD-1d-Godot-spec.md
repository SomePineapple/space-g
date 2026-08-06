# Ship HUD (1d) — Godot implementation spec

Reference screenshot: `hud-1d-reference.png` (this folder). Give both files to Claude Code, working inside your Godot project, and point it at your existing HUD scene/script.

## Structure
Build as a `CanvasLayer` with 4 `Control` children, each anchored to a screen corner (not hard-coded pixel positions, so it holds up at other resolutions):

1. **VitalsReadout** — anchor top-left, margin 24px
2. **CargoWidget** — anchor bottom-left, margin 24px
3. **Radar** — anchor bottom-right, margin 24px
4. **CreditsLabel** — anchor top-right, margin 20px (small, secondary)

## Colors (hex, use as Godot `Color`)
- Background/panel: `#171d24` (panel fill), `#12161c` (bar fill)
- Cyan accent: `#55d6e8` (primary), `#8fe9f2` (bright/center dot), `2A8FA3` if a darker cyan is needed
- Health good: `#7ce8b8` · warning: `#f2c14e` · critical: `#e2684a`
- Body text: `#e8edf0` · secondary/dim text: `#7c8b99`
- Material dot colors: Iron `#8a97a3`, Copper `#c97a4a`, Nickel `#c9d3d8`, Titanium `#5f8fa3`, Glass `#8fe9f2`

Font: monospace throughout (e.g. JetBrains Mono / Space Mono — pick one, embed it as a Godot `FontFile` resource so it's not the default editor font).

## 1. VitalsReadout (top-left)
Two rows, 7px gap between them. Each row: a 6×6 glow dot, a 74×5 rounded bar, a number label.
- HP row dot/fill color = health color (good/warning/critical by percentage — >50% good, >20% warning, else critical)
- EN row dot/fill = `#55d6e8` always
- Bar: background `rgba(255,255,255,0.15)`, fill = `TextureProgressBar` or a `ColorRect` clipped to `value/max` width
- Glow: `CanvasItem` self_modulate + a soft `Light2D`/blur shadow, or simplest: a `ColorRect` with a `CanvasGroup`+glow shader; a plain solid dot is an acceptable fallback if shaders are out of scope

## 2. CargoWidget (bottom-left)
- **Chip** (always visible): `PanelContainer` background `rgba(23,29,36,0.55)`, 1px border `rgba(85,214,232,0.3)`, 6/10px padding, border-radius ~3px (`StyleBoxFlat` corner_radius). Contains: small square icon (11×11, fill `rgba(85,214,232,0.15)`, border `rgba(85,214,232,0.45)`), "current/max" label, small triangle chevron that flips 180° on open (`Tween` rotating the icon or swapping to a flipped texture).
- **Dropdown** (toggles on chip click): appears *above* the chip (anchor its bottom edge to the chip's top edge, grows upward — in Godot, anchor the panel's `AnchorBottom`/`OffsetBottom` to the chip and let it expand negative-Y). Width 190px. Background `rgba(15,19,24,0.4)` — **Godot has no CSS `backdrop-filter`**; to get the "see-through/blurred" look, add a `BackBufferCopy` node behind it plus a blur `ShaderMaterial` on the panel, or, simpler and still true to the look, just use the flat semi-transparent fill without blur (looks like tinted glass, no blur) — recommend starting with the flat version and adding blur later if it's worth the shader complexity.
- List rows: dot (8×8, material color) + name (`#c7d0d8`) + qty (`#f2f5f6`), 6px row gap.
- Wire real cargo data in — the list should read from your inventory/resource system, not hardcoded.

## 3. Radar (bottom-right)
- Circular `Control`, no square border (deliberately removed — floats directly over the game view).
- Base: soft radial gradient fill (`GradientTexture2D` radial, cyan-tinted center fading to near-transparent) + a single 1px cyan border ring at the outer edge (`rgba(85,214,232,0.3)`) representing the *max range* boundary.
- **Range rings**: draw one extra faint ring (`rgba(85,214,232,0.16)`) for every 1000 units of scan range, spaced proportionally (ring radius = dial_radius × (ring_value / max_range)). So Range 1800 → 1 inner ring at 1000; Range 3200 → rings at 1000 and 2000. Recompute ring count/positions whenever the ship's radar range upgrades — this is the "expandable" behavior.
- **Sweep**: a wedge/gradient shape rotating continuously (`Tween` or `_process` incrementing `rotation` on a `TextureRect`/`Polygon2D` wedge, ~4s per revolution, linear).
- **Pings**: small dots + an expanding/fading ring pulse per detected signal, colored by signal type (reuse your existing signal-type colors if you have them — this mock used amber/cyan/red-orange as placeholders). Animate with a looping `Tween`: scale 0.5→2.4, opacity 0.9→0, ~2s loop, staggered per ping.
- Center: a small solid cyan dot marking the ship position.
- "RANGE {value}" label below the dial, small monospace, cyan, low-key.

## 4. CreditsLabel
Just a small monospace label, cyan-tinted, top-right. Not a full panel — keep it minimal.

## Notes for whoever (Claude) builds this in Godot
- Use `Control` anchors/margins, not fixed pixel offsets, so the HUD holds up across resolutions/aspect ratios.
- All bars/rings/ping counts should be driven by real ship stats (health, energy, cargo, radar range, detected signals) via signals or a HUD-update method — nothing here is meant to stay hardcoded.
- The blur on the cargo dropdown is the one effect with no direct Godot equivalent; treat it as optional polish (see above) rather than a blocker.
- Match the exact hex colors above rather than eyeballing from the screenshot — screenshots can shift slightly on compression.

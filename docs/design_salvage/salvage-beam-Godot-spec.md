# Salvage beam — Godot implementation spec

Reference stills: `01..06-salvage_beam_phase.png` (this folder), taken at T+0.6 / 1.9 / 4.2 / 6.25 / 7.6 / 9.3. Source mock: `Salvage Beam.dc.html` (scrubbable, same timings). Hand both to whoever builds it.

The whole effect is one 10-second, non-looping sequence driven by a single `AnimationPlayer`. Every visual below is a child of one `SalvageBeam` node so the effect can be instanced per cutter and freed on finish.

## Phase table (the AnimationPlayer timeline)

| t (s) | Phase | What fires |
|---|---|---|
| 0.00 | Lock | Brackets fly in from 96px out to 6px out over 0.8s (ease-out), dashed hex outline fades in, dash offset scrolls at 22 px/s |
| 1.10 | Spool | Charge ring at the muzzle spins (~1 rev/s) and grows; muzzle core brightens 0.4→1.0 alpha over 1.3s |
| 1.55 | Pilot beam | Thin, 32% width, 55% alpha, static contact point at the first vertex |
| 2.40 | Cut | Main beam on. Contact point walks the hex perimeter, **0.6s per edge, 3.6s total**. Camera shake ±1.3px at ~9Hz |
| 6.00 | Sever | Beam off. Flash + radial spark burst, tile gets impulse, atmosphere vents from all six edges for ~0.9s, socket rim starts cooling |
| 7.10 | Mounts fail | Struts on the two dependent modules snap: white flash + spark burst at each break point, pods drift |
| 8.35 | Grapple | Line whips to the tile (0.28s extend), then to pod A at 8.80 and pod B at 8.95 |
| 8.60 | Reel | Tile reels in over 1.35s (ease-in, `u²`), pods over 0.95s from 9.05. Award text appears |
| 10.00 | End | Free the node |

Node names/timings are the contract — if you retune, retune here first, the mock reads from the same table.

## Colors

Corporate palette (matches `STYLE_GUIDE.md`; Ancient and Pirate variants are in the mock's `PAL` table).

| Role | Hex | Notes |
|---|---|---|
| Beam core | `#fff6dc` | push to HDR (×2.5) so glow catches it |
| Beam sheath | `#8fe9f2` | ×1.6 HDR |
| Muzzle / charge ring | `#8fe9f2` | |
| Slag ramp | see below | |
| Hull | `#2b3542` | plate `#333f4d`, edge `#10141a`, rivet `#4a5763` |
| Warm node | `#f2c14e` | corner bolts, award text |
| Space bg | `#070a0e` | |

**Slag cooling `Gradient`** — sample with `age_seconds / 3.0`, clamped:

| offset (s) | color |
|---|---|
| 0.00 | `#fff6dc` |
| 0.05 (0.15s) | `#fff6dc` |
| 0.20 (0.6s) | `#ffd9a0` |
| 0.50 (1.5s) | `#ff8a3c` |
| 1.00 (3.0s) | `#c94a12` |
| beyond | `#5e2b14` (slag, stays) |

## Node tree

```
SalvageBeam (Node2D)
├── Emitter (Node2D)          # muzzle at the cutter's barrel tip
│   ├── ChargeRing (Sprite2D or draw arc, additive)
│   └── MuzzleCore (Sprite2D, additive)
├── Beam (Line2D ×3, additive material, 2 points: muzzle → contact)
│   ├── Sheath  width 16, alpha 0.14
│   ├── Mid     width 7,  alpha 0.42
│   └── Core    width 2.6, alpha 0.95
├── ContactFlare (Sprite2D, additive, radius ~26px, + 1px horizontal streak ×3.4 width)
├── CutLine (Line2D, gradient-coloured, points appended as the cut walks)
├── Reticle (Node2D: 4 bracket sprites + dashed hex Line2D)
├── FX
│   ├── Sparks (GPUParticles2D, one-shot bursts re-emitted along the cut)
│   ├── Vent   (GPUParticles2D, 6 emitters on the tile's edges)
│   ├── Smoke  (GPUParticles2D, alpha 0.22, no additive)
│   ├── Blast  (GPUParticles2D, one-shot at sever)
│   └── Debris (GPUParticles2D with a small quad mesh, or 16 RigidBody2D chunks)
├── FreedTile (RigidBody2D, the hex sprite, gravity_scale 0)
├── FreedModules ×2 (RigidBody2D)
└── Grapple ×3 (Line2D, 14 segments, sine wobble)
```

## Beam

Three stacked `Line2D`s sharing a `CanvasItemMaterial` with `blend_mode = BLEND_MODE_ADD`. Both points are set every frame: `points[0] = muzzle`, `points[1] = contact`.

Flicker is **width only, never position** — position jitter reads as a targeting failure:

```gdscript
var f := 1.0 + 0.18 * sin(t * 41.0) + 0.10 * sin(t * 97.0)
sheath.width = 16.0 * f
mid.width    = 7.0  * f
core.width   = 2.6  * f
```

`ContactFlare` is a radial-gradient sprite, radius `26 + 5 * sin(t * 33)`, plus a thin horizontal streak at 3.4× that radius (the anamorphic cue that sells "hot").

## Cut line

Flat-top-vertex hex, radius 53.8px at the mock's scale (world radius 128 × 0.42 — use your own tile radius). Vertices at −90°, −30°, 30°, 90°, 150°, 210°.

```gdscript
var p := clamp((t - 2.4) / 3.6, 0.0, 1.0)   # perimeter progress
# append a point every ~1/150 of the perimeter; colour each by its own age
var age := (p - u) * 3.6 + max(0.0, t - 6.0)
line.set_point_color(i, slag_gradient.sample(clamp(age / 3.0, 0, 1)))
```

Width `3.4` while `age < 0.6`, else `2.6`. Points behind the head keep ageing after the beam stops — that is what makes the socket rim on the parent ship cool down naturally, and it must persist on the ship (see below), not be freed with the tile.

Sparks emit **at the contact point**, ~85/s during the cut, cone 360°, speed 40–220 px/s, lifetime 0.22–0.85s, plus a downward-ish drift of `60·d²·6`. Colour over lifetime: `#fff6dc` for the first 0.12s, then `#ffd9a0` → `#ff8a3c`.

## Sever and structure

At t=6.0:
- Beam off, one-shot blast burst (130 particles, 60–300 px/s, 0.3–1.1s life).
- `FreedTile` gets linear velocity ≈ `(46, -16)` px/s and angular ≈ `0.42 rad/s`. Slow: this is salvage, not an explosion.
- Six vent emitters on the tile edges fire outward along each edge normal for ~0.9s, cool grey `#b9cdd8`, alpha 0.32, particles growing 1→3.2×.
- 16 debris chunks (2.5–6px squares, hull colours) spray from the socket rim.
- The parent ship swaps the tile for a **socket**: near-black `#05070a` hex fill, diagonal torn-strut hatching clipped inside it, and the slag-gradient rim that keeps cooling for the remaining 4s.

Between 6.0 and 7.1 the struts to the two dependent modules **stretch and stress-flash**: width lerps 4→1.6px, colour walks the slag ramp backwards toward white, and above 60% stress it strobes white at ~10Hz. At 7.1 they snap — burst of 70 white/cyan particles at each break, pods get their own velocity and spin.

Load-bearing rule for gameplay: a module is freed if and only if every tile it is mounted to was removed. The pod on the neighbouring tile in the reference never moves — keep that contrast in the shipped effect, it is what teaches the mechanic.

## Grapple

`Line2D`, 14 segments, extended by lerping the endpoint over 0.28s. Wobble is a sine perpendicular to the line, amplitude `(1-extend)*10` at 9 cycles plus a settle term `5·sin(f*3.4 + t*4)` that decays to zero by 9.8s. On attach, add an additive cyan glow sprite on the hooked body pulsing at ~3Hz. Reel by tweening the body position toward the muzzle with `u²` easing (slow start, fast finish) — a linear reel looks mechanical in a bad way.

## Glow

The one thing that needs project-level setup: add a `WorldEnvironment` with `glow_enabled = true`, `glow_bloom ≈ 0.15`, `glow_hdr_threshold ≈ 1.0`, and push the beam core / sparks / muzzle colours above 1.0. Without HDR glow the additive core reads as a flat white line and the whole effect loses most of its punch. Everything else here works on plain 2D nodes with no shaders.

## Tuning knobs worth exposing

- `cut_duration` (default 3.6s) — the upgradeable stat; faster cutters shorten only this phase, the rest of the timeline is fixed.
- `beam_color` / `sheath_color` — faction variants (Ancient teal `#6fe3d6`, Pirate orange `#ffb35c`) reuse the identical geometry.
- `shake_strength` (default 1.3px) — drop to 0 for the shipyard preview, keep it in combat.

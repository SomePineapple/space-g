# Grapple line — Godot implementation spec

Reference stills: `01..07-grapple_phase.png` (T+0.4 / 1.4 / 2.0 / 3.0 / 5.0 / 6.9 / 8.8). Runnable mock: `Grapple Line.dc.html` (open in a browser, scrub the timeline, drag the ship to tug the line by hand). Starter implementation: `grapple_rope.gd`.

The line is not animated. It is a verlet rope simulated every physics tick; the 10-second sequence below is just the order the API is called in. Everything the reference does — unfurl, whip, slack, flop, snap — falls out of the simulation, so keep the sim and script the calls.

## Sequence

| t (s) | Phase | Call |
|---|---|---|
| 0.00 | Wind-up | Reticle converges on the target, launcher tracks. No rope yet |
| 0.70 | Cast | `fire(target_dir)` — hook gets 820 px/s, line pays out behind it |
| ~1.9 | Bite | Hook enters the hunk's radius: spark burst, `_hook()` latches, hunk gains spin |
| 2.0–3.6 | Wrap | Ten links are drawn onto a closing spiral around the hunk over 0.9s |
| 3.2 | Take-up | Winch reels slack at 300 px/s until the line is taut, then stops |
| 3.6–6.2 | Tug | Ship burns; the taut line drags the hunk |
| 6.2 | Coast | **Thrust cut.** Ship stops, the rope's own momentum carries it forward past the bow, slack blooms, then the line comes taut again with a jolt |
| 7.60 | Winch in | `reel_to(178)` over 2.1s, ease-in-out |
| ~9.6 | Secured | Hunk reaches the collector maw; dust puff, award |

The Coast beat is the one that sells the tool: it only exists because the rope carries momentum independently of the ship. Do not "fix" the overshoot.

## Simulation constants (tuned in the mock, copy them)

| Param | Value | Note |
|---|---|---|
| Nodes | 64 | node 0 is the hook, node N-1 sits on the drum |
| Rest length | 13 px | total capacity 832 px |
| Substep | 1/120 s | two substeps per 60fps frame |
| Constraint iterations | 12 | fewer looks rubbery |
| Damping | 0.997 | zero gravity: this is the only energy loss |
| Cast speed | 820 px/s | |
| Payout slack | hook distance + 60 px | line spools to follow the hook |
| Take-up rate | 300 px/s | stops the moment the line is taut |
| Wrap | 10 links / 0.9 s | spiral 5.4 rad, radius (R+3) → (R−9), −2.4 px per link |
| Load transfer | 0.055 | outermost wrapped link only — see below |
| Hunk speed cap | 52 px/s tugging, 105 px/s winching | mass stand-in |

**Payout matters more than anything else here.** A link leaving the drum must inherit ~98% of the line's current velocity. If new links spawn at rest, the spool acts as a brake and the hook stalls at half range — that was the first thing that went wrong building this.

**Load transfer matters second.** Only the outermost wrapped link pulls the salvage; if every wrapped link pushes the body, ten links pull at once and a hull section flies in like paper. Pair it with a hard velocity cap on the body — the line pulls a few tonnes, it never flings it.

## Node tree

```
GrappleLine (Node2D)          # grapple_rope.gd
├── Rope (Line2D)             # 4 stacked passes, see below
├── Links (MultiMeshInstance2D)   # one small ellipse per segment, alternating flatten
├── Hook (Sprite2D)           # 3-prong claw, rotates to the segment angle
├── Impact (GPUParticles2D)   # one-shot at bite: 46 hot + 16 grey
├── Strain (GPUParticles2D)   # small burst each time the line snaps taut
└── Muzzle (Marker2D)         # node N-1 is pinned here every tick
```

Draw the rope as four passes over the same points: 6px `#10141a` (separation from the hull), 4.2px `#3b4753`, 1.8px `#8a99a8` at 0.75–1.0 alpha by tension, and — above 55% tension only — a 2.2px additive `#8fe9f2` pass whose alpha is `(tension-0.55)*0.9`. That last pass is the whole "this line is loaded" read; without HDR glow enabled it does nothing, so turn glow on in the WorldEnvironment.

Chain links: one ellipse per segment at the segment midpoint, rotated to the segment angle, 6.2 × 3.4 px alternating with 6.2 × 1.5 px. Alternating the flatten is what makes it read as chain rather than rope. For a cable variant, skip the link pass entirely and keep the three strokes.

## Tension

Sum the constraint corrections on the first solver iteration and normalise: `tension = clamp(total_correction / 22, 0, 1)`. Feed it to line brightness, controller rumble, and the winch audio. Crossing from slack to taut (`tension > 0.35` after being below) is a discrete event: fire the jolt (2.4px camera shake decaying at 0.9/tick) and a 10-particle burst at the link nearest the wrap.

## Colors

Corporate palette per `STYLE_GUIDE.md`; Ancient and Pirate variants ship in the mock's `PAL` table.

| Role | Hex |
|---|---|
| Line highlight / glow | `#8fe9f2` |
| Chain body | `#8a99a8` on `#3b4753` |
| Outline | `#10141a` |
| Hull / plate | `#2b3542` / `#333f4d` |
| Warm node, award text | `#f2c14e` |
| Impact sparks | `#fff6dc` → `#ff8a3c` |
| Space | `#070a0e` |

## API in `grapple_rope.gd`

```gdscript
rope.fire(global_position, direction)   # cast
rope.tension                             # 0..1, read every frame
rope.hooked                              # bool
rope.reel_to(178.0, 2.1)                 # winch: target line length, seconds
rope.release()                           # drop the haul, retract
signal hooked(body)                      # emitted on bite
signal secured(body)                     # emitted at the collector
```

The script pins node N-1 to the muzzle each tick, so the line follows the ship for free — including the case the reference is built around, where the ship stops and the rope does not.

## Tuning knobs worth exposing

- `cast_speed` (820) — range upgrade.
- `reel_rate` (2.1s to close) — winch upgrade; the only stat that should change recovery time.
- `wrap_links` (10) — bigger salvage needs more turns; wrap time scales with it.
- `body_speed_cap` — per salvage mass class; this is the "heavy haul" feel, not rope stiffness.

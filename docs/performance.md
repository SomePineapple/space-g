# Rendering Performance

What has been optimised, why it was slow, and where to look next. Numbers here
are measured, not estimated — see "How to measure" to reproduce them.

## Headline result

Measured on `scenes/world/map_tester.tscn` (the main scene) at 2548x1320:

| Metric | Before | After |
| --- | --- | --- |
| FPS | 31 | 140 (vsync cap) |
| Draw calls / frame | 30,564 | 145 |
| Primitives / frame | 1.95M | 69k |
| `TIME_PROCESS` | 31.7 ms | 7.1 ms |

The game was almost entirely CPU-bound in the 2D canvas renderer, submitting
tens of thousands of draw commands per frame. Nothing was GPU-bound, and the
particle systems were never the problem.

## The rule that explains all of it

**Godot's 2D canvas renderer does not batch across separate draw commands.**
Every `draw_circle()`, `draw_line()`, and `draw_colored_polygon()` is its own
draw call — even when consecutive commands share the same texture, colour and
width. This was verified directly: grouping a hull's fills by texture so that
same-texture polygons were emitted back to back changed the draw call count by
exactly zero (674 -> 674).

The only things that collapse into one draw call are commands that are *by
construction* one command:

- `draw_multiline()` — many line segments, one command
- `draw_mesh()` — arbitrary triangles, one command
- `draw_multimesh()` — many instances of one mesh, one command

So the optimisation pattern throughout is always the same: **stop issuing one
command per visual element; build one command that contains all of them.**

A second, easily-missed multiplier: a `ParallaxLayer` with `motion_mirroring`
re-renders its entire item subtree once per visible tile — up to four times.
Any per-element cost on a parallax layer is therefore roughly 4x worse than it
looks.

## What was done

### 1. Starfield — the dominant cost

`scenes/world/starfield_layer.gd`, plus the new
`scenes/world/starfield_star.gdshader`.

Each layer drew 2000 stars as individual `draw_circle()` calls. Godot expands a
circle into a ~64-segment polygon, so each 1-2px star cost one draw call and
~64 primitives. Four layers, multiplied by parallax mirroring, produced ~30k
draw calls and ~1.95M primitives per frame. Hiding the star layers alone took
the scene from 30,564 -> 142 draw calls and 31 -> 144 FPS, which is to say the
starfield *was* the frame budget.

It is now one `MultiMesh` per layer — a unit `QuadMesh` instanced per star,
drawn with a single `draw_multimesh()`. Per-star data rides along as instance
transform (position + diameter), instance colour (tint x brightness) and
instance custom data (flicker speed, phase, strength). The shader shades each
quad into an antialiased disc so the stars keep their round look.

Flicker moved entirely into the vertex shader. Because a steady star just
carries flicker strength `0.0` — which makes the shader's `dip` term `1.0` and
leaves colour and size untouched — steady and flickering stars share one batch.
That removed the static/flicker split, the per-frame `_process`, the per-frame
`queue_redraw()` and the manual view-culling code. The layer now does no
per-frame CPU work at all.

Star positions are unchanged: the RNG call order in `_build_stars()` was kept
identical to the old draw code, including the conditional `randf_range()` that
only runs for non-flickering stars. Changing that order reshuffles every field.

### 2. Ship hulls — the "large ships" cost

`scripts/ships/layout/ship_layout_renderer.gd`.

The hull drew, per hex cell, one textured polygon plus six `draw_line()` calls
for the outline: seven draw calls per cell, interleaved so nothing could batch.

Two changes:

- **Outlines**: every cell's six edges accumulate into one `PackedVector2Array`
  and are emitted as a single `draw_multiline()` for the whole ship.
- **Fills**: textured cells are bucketed by texture and each bucket is merged
  into one `ArrayMesh` (each hex fanned from its first corner into four
  triangles), drawn with one `draw_mesh()` per texture. A 42-cell heavy hull
  uses only 7 distinct textures.

Measured cost of one 24-module / 42-cell `pirate_heavy_one`:

| Version | Draw calls per hull |
| --- | --- |
| Original (`draw_line` per edge) | ~85 |
| Outline batching only | ~43 |
| Outline + per-texture meshes | **6** |

With 12 heavies on screen, outline batching alone took the scene from 1178 to
674 draw calls.

Reordering fills is safe because hex cells never overlap. Outlines are now
drawn on top of all fills rather than per-cell; verified against the original
renderer with a deterministic A/B (same scene, ship at a fixed position and
rotation, camera pinned, same zoom) and the hulls are pixel-consistent.

### 3. Thruster emitters

`scenes/player/ship.gd`, `_update_engine_particles()`.

`GPUParticles2D.set_emitting()` deliberately never early-outs, so assigning
`emitting` unconditionally pushes a RenderingServer command per emitter per
physics frame — three per thruster, and a large hull has many thrusters. It is
now guarded by a change check (`_set_emitting()`), which is safe here because
these emitters are not `one_shot`, so `emitting` is authoritative.

The `amount_ratio = 1.0` writes were removed: `1.0` is already the default and
nothing else in the project writes that property, so they were dead writes that
still cost a server command each.

## Gotchas worth remembering

- **`draw_mesh()` stores only the mesh's RID in the canvas item.** A locally
  built `ArrayMesh` is freed the moment `_draw()` returns, and the renderer
  then logs `Parameter "mesh" is null` *every frame*. The meshes must be kept
  alive on the node — hence `ShipLayoutRenderer._hull_meshes`.
- **Grouping same-texture draw commands does nothing.** Don't spend effort on
  it; go straight to a merged mesh.
- **`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` is the metric to watch**,
  not FPS. Vsync pins FPS at the refresh rate and hides all headroom, so FPS
  only moves once things are already bad. Draw calls show the problem long
  before it becomes visible.
- **A backgrounded game window freezes its main loop.** `await
  get_tree().process_frame` never resumes, and MCP `game_eval` calls that
  await will time out. Force a frame with a screenshot capture instead, then
  read the monitors in a separate call.

## Future considerations

Roughly in order of value-per-effort, if hull or scene cost ever matters again:

1. **Hex art atlas.** The remaining ~6 draw calls per hull are one per distinct
   texture. Packing the faction hex art into a single atlas and remapping UVs
   would make any ship, of any size, exactly **one** `draw_mesh()` plus one
   `draw_multiline()`. This is the single biggest remaining win and the only
   one that makes hull cost independent of ship size.
2. **Cache the hull mesh across redraws.** `_draw()` currently rebuilds the
   meshes and recomputes `hex_corners()` (six trig calls per cell) on every
   redraw. Redraws are rare today — layout changes, module destroyed, detached,
   repaired — so this is not currently hot. It becomes worth doing only if
   something starts redrawing hulls per frame, which it should not.
3. **Merge the parallax star layers.** Four layers are four multimeshes x up to
   four mirror tiles. Since each layer differs only in `motion_scale`, the
   parallax offset could be a shader uniform, collapsing everything to one
   multimesh. Small absolute gain now (~16 draw calls); only worth it if star
   layer count grows.
4. **Audit other per-element `_draw()` loops.** The same one-command-per-element
   trap exists anywhere `_draw()` loops. `scenes/ui/radar_display.gd`,
   `scenes/ui/ship_builder/hex_grid_control.gd` and
   `scenes/ui/upgrades/upgrade_tree_view.gd` all draw many primitives; the UI
   ones matter less because they redraw on interaction rather than per frame,
   but `radar_display.gd` redraws continuously and is worth checking first.
5. **Particles are not currently a problem.** Emitter counts are modest (32 /
   20 / 24 per thruster, 40 per explosion, 10 per spark) and GPU particles cost
   little CPU. The thing to watch is the *number of `GPUParticles2D` nodes*,
   not the particle count: each node is its own draw call and its own process
   dispatch, and a large hull spawns three per thruster. If large ships start
   carrying many engines, consolidating the three per-thruster emitters into
   one, or sharing emitters across thrusters, is the lever.
6. **Only then look at the GPU.** Nothing measured so far has been fill-rate or
   shader bound. Before optimising anything visual, confirm with draw calls and
   `TIME_PROCESS` that the cost is actually where you think it is.

## How to measure

With the project running under the MCP editor integration:

```gdscript
# editor_manage(op="game_eval")
return {
    "fps": Engine.get_frames_per_second(),
    "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
    "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
    "prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
    "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
    "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
}
```

To attribute cost to a specific system, hide it and re-read rather than
guessing. Hiding the star layers is what identified the starfield in the first
place. To get an exact per-object figure, hide every instance, force a frame
via a screenshot capture, read the baseline, then show exactly one and read
again — the difference is that object's true cost, free of culling effects.

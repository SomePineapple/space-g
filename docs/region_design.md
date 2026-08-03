# World Regions

Implements roadmap item **"1.3 Basic world regions"** (a user-supplied spec,
not part of `roadmap.md`/`Roadmap v.2-v.9.md`). Replaces hand-placed,
object-by-object asteroid fields with a small data-driven system: a
`RegionType` resource describes *what a region feels like*, and a
`RegionSpawner` node fills a rectangular area with asteroids that match it.

Scope note: the user floated a "large grid of squares, each square a region
type" universe-generation idea. That's a materially bigger piece of
architecture (world-addressing, cell lookup, possibly streaming) and was
deliberately **not** built — this system is a handful of handcrafted zones
using reusable data, matching how the asteroid field / derelict station /
nebula already work. The grid idea remains a possible future task, not
started.

## Files

- `scripts/world/region_type.gd` — `RegionType extends Resource`. Pure data,
  no scene presence.
- `scripts/world/region_spawner.gd` — `RegionSpawner extends Node2D`. Placed
  in a scene, references a `RegionType`, does the actual spawning.
- `resources/regions/*.tres` — one `.tres` per named region flavor.

## `RegionType` fields

| Field | Meaning |
|---|---|
| `display_name` | Not yet shown in any UI — reserved for future use (e.g. a region-name HUD label). |
| `asteroid_density` | Asteroids per 1,000,000 sq. units (i.e. per 1000×1000 area). A property of the *type*, not a fixed count, so the same `RegionType` can be reused at different area sizes and still feel consistent. |
| `min_spacing` | Minimum center-to-center distance enforced between spawned asteroids. |
| `large_weight` / `medium_weight` / `small_weight` | Relative odds for `Asteroid.SizeTier` on each spawn (normalized, don't need to sum to 1). |
| `asteroid_tint` | Multiplied into each spawned asteroid's `self_modulate` — same technique the faction station wrecks use — so a region reads as visually distinct even before you count asteroids. |

## `RegionSpawner` behavior

- `region_size: Vector2` — width/height of the fill rectangle, centered on
  the spawner's own position.
- `random_seed: int` — seeds a local `RandomNumberGenerator`. Spawning is
  fully deterministic from this seed, so a region looks identical every
  time its scene loads (**stable when revisited** — verified live via a
  forced scene reload producing an identical asteroid count).
- `keep_clear_points: Array[Vector2]` (local space) + `keep_clear_radius` —
  no asteroid spawns within `keep_clear_radius` of any of these points.
  **Convention: always include the position the player arrives at** (an
  arrival gate/marker) so nothing spawns on top of the ship. In practice
  this is usually just `Vector2.ZERO` with the spawner itself placed at the
  gate.
- Target asteroid count = `region_size.x * region_size.y / 1_000_000 *
  asteroid_density`, rounded. Placement uses rejection sampling (30 attempts
  per asteroid) against both `keep_clear_points` and previously placed
  asteroids in the same pass — if a region is asked for more asteroids than
  can actually fit at its `min_spacing`, it silently spawns fewer rather
  than erroring or overlapping. This is expected, graceful degradation, not
  a bug — tune `asteroid_density`/`min_spacing` together if a region needs
  to hit a specific count more exactly.
- **Spawning is deferred past `_ready()`** (`_spawn_region.call_deferred()`).
  Calling `get_tree().current_scene.add_child()` directly inside `_ready()`
  intermittently failed with "Parent node is busy setting up children" when
  the scene root itself was still adding its own children — a real bug
  found via live testing, fixed by deferring the whole spawn pass to idle
  time.

## Current regions

| Region | Scene | Size | Density | Min spacing | Reached via |
|---|---|---|---|---|---|
| Sparse Open Space | `map_tester.tscn` | 5000×4000 | 0.75 | 600 | `SpeedGateToSparse` (speed lane) |
| Small Asteroid Cluster | `map_tester.tscn` | 900×900 | 10.0 | 160 | `SpeedGateToCluster` (speed lane) |
| Standard Asteroid Belt | `asteroid_field.tscn` | 900×700 | 16.0 | 160 | `WarpGateAsteroidField` (scene gate) |
| Dense/Dangerous Belt | `map_tester.tscn` | 2200×1400 | 10.0 | 200 | `SpeedGateToDense` (speed lane) |

Live-tested asteroid counts at these settings: Sparse 14, Cluster 8, Standard
Belt 10, Dense 31 — down significantly from an earlier, much denser first
pass (Sparse ~40-60, Cluster ~27, Dense 88) that the user flagged as
overloading the player with resources. **If regions ever feel too sparse or
too dense again, tune `asteroid_density`/`min_spacing` on the relevant
`.tres` file — no code or scene changes needed.**

The Standard Asteroid Belt replaced 14 hand-placed `Asteroid` nodes in
`asteroid_field.tscn` with a single `RegionSpawner` — its tuned values were
chosen to land close to the original hand-authored count/feel, not derived
from scratch.

## Deliberately not done

- No `RegionType`-driven visual background/tint change (e.g. a nebula-style
  screen tint per region) — explicitly out of scope per the original spec
  ("do not add ... nebula effects yet"). Only the per-asteroid `self_modulate`
  tint differs.
- No unique materials or faction identity per region — also explicitly out
  of scope.
- No grid-of-squares universe addressing system — see "Scope note" above.
- `display_name` isn't surfaced anywhere in the UI yet (no "entering X"
  notification or HUD label) — not asked for.

## Adding a new region

1. Duplicate an existing `.tres` under `resources/regions/`, tune its five
   fields.
2. Add a `RegionSpawner` node to a scene (existing scene or a new
   speed-lane/gate destination), point `region_type` at the new resource,
   set `region_size`, and set `keep_clear_points` to wherever the player
   will actually arrive.
3. Give it a `random_seed` distinct from other spawners in the same scene
   (arbitrary int, just needs to differ so RNG sequences don't collide
   across spawners).

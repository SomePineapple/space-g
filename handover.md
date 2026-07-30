# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up.

## Where things stand

The vertical slice is largely in place: flight movement, camera, asteroids, a
bounded explorable region with a home base, an enemy pirate encounter with
personality-driven AI, weapons (guns + homing missiles), a working ship
builder wired into the flyable ship (including save/load), a salvage/tractor
beam/inventory loop, an upgrade-tree UI, and — just added — the first
planet. **Phase 1–3 of `roadmap.md` and most of Version 0.1 are functionally
done**; the project is at the point of starting **Version 0.2 — Salvage &
Materials** from `Roadmap v.2-v.9.md`.

### Ship building (done, wired into the flyable ship)
- Hex-grid (axial coordinates) layout data model under `scripts/ships/...`:
  `module_type.gd`, `module_placement.gd`, `module_catalog.gd` (still a
  static prototype catalog — documented as a stand-in for real `.tres`
  module resources), `ship_layout.gd` (place/remove/rotate, BFS connectivity,
  `validate_layout()`), `hex_utils.gd`, `ship_layout_renderer.gd`.
- `scenes/ui/ship_builder/` — `hex_grid_control.gd` + `ship_builder_panel.gd`,
  toggled near the home base marker. Grid is now square (zig-zag row-offset
  boundary instead of a diagonal parallelogram), 20x20, taller than before.
  **R** rotates the piece being placed (or a selected placed module), **X**
  deletes a selected placed module. Any visible `"menu_panel"`-grouped
  CanvasLayer (builder, upgrade panel) suspends all `ship_input.gd` polling
  each physics frame, so hotkeys can safely reuse gameplay keys (R is also
  `fire_secondary` in flight).
- **Saving/loading custom ships to disk is implemented** (see recent commit
  `7193cf9`) — no longer "no persistence yet" as an older version of this
  doc said.
- The renderer draws the actual hull from `ShipLayout` on the flyable
  `Ship`, and weapon hardpoints scale/visually change by tier (tier 3 gun
  hardpoint is a hex triangle; projectile size scales with tier).

### Combat
- `hardpoint_gun.gd` — mouse-aimed hitscan/projectile gun hardpoint.
- `hardpoint_missile_launcher.gd` + `missile.gd` — homing missiles with a
  **torpedo-style one-shot propulsion cycle**: creep out of the silo →
  brief engines-off coast (trail off) → main engine ignites and stays on
  for the rest of the flight, homing toward a **live** target reference
  (re-reads `target.global_position` every tick, not a launch-time
  snapshot). Turn rate ramps up over time and is `@export`ed (upgradable
  the same way as `fire_rate`/`projectile_damage` via
  `Ship.apply_missile_modifier()` — no new plumbing needed for future
  upgrade nodes). A persistent per-missile miss offset (rolled once at
  launch, reapplied to the live target position) gives some missiles a
  believable near-miss rather than a guaranteed hit.
- `scenes/enemies/ship_ai.gd` — single AI script for all enemy archetypes,
  driven entirely by a `ShipPersonality` resource (`resources/ai/`:
  rammer, sniper, user/player-controlled). Replaced the old bespoke
  `ai_input.gd` / `missile_cruiser_ai.gd` scripts (deleted). AI ships latch
  a permanent `_alerted` flag the first time they take damage, bypassing
  `detection_range` afterward — a stationary sniper shot from outside its
  detection range now fights back immediately instead of sitting idle.
- `region_boundary.gd` gently pushes the player back inside a radius
  around the home base; a fixed pirate encounter exists in `map_tester.tscn`
  for testing.

### Salvage / economy (exists, but still the "generic currency" stage)
- `scenes/world/salvage.gd` — rarity-tiered drops (Common → Artefact) with
  distinct colors/glow and a "dangerous salvage" pulsing variant, but value
  is still a single generic `int` (`salvage_value`), not the named-material
  system (Steel Alloy / Electronics / Reactor Components) that
  **Version 0.2 of `Roadmap v.2-v.9.md` calls for** — this is the next
  planned piece of work.
- `tractor_beam.gd`, `inventory.gd` — pull salvage in and track it on the
  ship. `upgrade_catalog.gd` / `upgrade_manager.gd` / `upgrade_node.gd` /
  `upgrade_panel.gd` — a working upgrade-tree UI, spending the generic
  currency; will need to change once real materials land.

### World
- `starfield_layer.gd` + a `ParallaxBackground` (`DeepBackground` /
  `DeepStars` / `FarStars` / `MidStars` / `NearStars`) in `map_tester.tscn`.
  Bloom/glow comes from one `WorldEnvironment` node (`glow_enabled`, no
  per-object lights/shaders).
- **First planet added** (`scenes/world/planet.tscn`, texture
  `art/planets/planet_earth_like.png`): purely visual, no collision, no
  script. Placed as a sibling right after `SpaceBackground` and before
  `Ship`/asteroids in `map_tester.tscn` — Godot's default sibling draw
  order puts it above stars and below every gameplay object, which is all
  that was needed (no z-index tricks). The source texture had no alpha
  (a flat square with a near-white background) and was manually
  re-processed to add a soft-edged circular alpha mask before use — if
  more planet textures get added later, check whether they already have
  proper alpha before assuming a raw upload can be used directly.
  **Only one planet type exists; there is no catalog/data-resource system
  for planets** — matches the user's "only one for now" framing, not an
  oversight.

## Decisions made (and why — don't relitigate without reason)

- **Ship-centric, not player-centric architecture.** Ship data lives under
  neutral `scripts/ships/...` / `resources/ships/...`. AI and player ships
  share the same `Ship`/`ship_ai.gd`/`ship_input.gd` split so control source
  is swappable — this is the foundation the whole roadmap's later co-op
  phase leans on.
- **Hex grid with axial coordinates (`Vector2i`)**, not a square grid.
- **Static `ModuleCatalog` is a deliberate, documented prototype shortcut** —
  do not let new systems assume it's permanent; real content should move to
  `.tres` resources under `resources/modules/`.
- **Never silently no-op.** Every rejected ship-builder action surfaces a
  specific reason string through the status label.
- **Exactly one Command Core** is enforced as a current layout rule,
  documented as prototype-specific, not a permanent constraint.
- **Menu-open input suspension is group-based** (`"menu_panel"` group +
  a visibility check in `ship_input.gd`), not per-key special-casing — this
  is why gameplay keys can be safely reused as menu hotkeys, and any future
  menu just needs to join the group to get the same protection for free.
- **Missile torpedo behavior is a one-shot phase sequence** (creep → coast →
  ignite-and-stay-on), explicitly *not* a repeating burst/coast cycle — an
  earlier repeating-cycle implementation was tried and explicitly rejected.
- **Planets are visual-only for now** — no collision, no data resource
  system, one hardcoded instance. Don't build a planet catalog/orbit system
  etc. until it's actually asked for.
- **Increments must be small and individually verified** (per CLAUDE.md) —
  every feature above was tested live via the Godot MCP tools (`game_eval`,
  screenshots) and reported back before moving on.

## Known MCP/tooling gotchas (only relevant if using the godot-ai MCP tools)

- Avoid `for i in range(...)` loops inside `game_eval` test scripts — they
  can silently execute only once. Use sequential explicit statements.
- GDScript has no C-style ternary — use `a if cond else b`.
- A runtime error inside an ad-hoc `game_eval` script (stale node reference,
  out-of-bounds index, etc.) can park the running game in a debugger
  "break" state; every subsequent `game_eval` then fails with
  `EVAL_GAME_NOT_READY` referencing the *old* stale error until you
  `project_manage(op:"stop")` + `project_run` again. Prefer one atomic
  `game_eval` call per test (spawn + manipulate + measure together) over
  relying on state persisting correctly across separate calls.
- After editing a `.tscn`/resource file directly on disk (not through MCP
  node tools) while it's the open scene, use `scene_open(force_reload=true)`
  so the editor picks up the disk version instead of stale in-memory state.
- After regenerating an image file in place (e.g. adding an alpha channel),
  a single `filesystem_manage(op:"reimport")` did not reliably pick up the
  new pixel format in this session — needed a `scan()` + `reimport()` +
  full game restart before `Image.get_format()` reflected the change.
  Verify with a `game_eval` reading the loaded texture's actual format
  rather than trusting the reimport call's return value alone.

## Not yet started (no explicit user request yet — don't start without one)

- **Version 0.2 (`Roadmap v.2-v.9.md`) — Salvage & Materials**, the
  explicitly-stated next planned session: replace generic `salvage_value`
  with named materials (Steel Alloy / Electronics / Reactor Components),
  give ship modules per-material build costs, improve salvage visual
  readability further, improve the extractor/tractor beam feel, and add
  simple pirate AI states (Idle/Suspicious/Alert/Retreating) — note
  `ship_ai.gd`'s damage-triggered `_alerted` latch already covers part of
  "Alert", so check what's genuinely missing before rebuilding it.
- More module types / a real data-driven (non-static) module catalog as
  `.tres` resources.
- A planet catalog/multiple planet instances, orbit/parallax motion for
  planets, or any planet-surface gameplay.
- Second enemy archetype beyond the current rammer/sniper personalities.
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (factions, warp gates, research, co-op) — explicitly out of
  scope until Version 0.2 and nearby milestones are done.

## Suggested next step

The user has already decided: **start Version 0.2 — Salvage & Materials**
from `Roadmap v.2-v.9.md`. Read that file's full section before proposing
an implementation plan, inspect the existing `salvage.gd` /
`upgrade_catalog.gd` / ship-builder cost handling (there currently are no
per-module costs at all — check `module_type.gd` for what fields already
exist before adding new ones), and propose a small first increment (e.g.
just the materials data model and a couple of real material types) rather
than the whole version at once, per CLAUDE.md's incremental-delivery rule.

# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up.

**Read "Most recent session" first** — it's the freshest context and covers
work done after the rest of this file was last updated: reverse engineering
and Manufacturers (both real Version 0.5 systems now), a real severable wing
for `pirate_light_one`, and two bugs (debris art, thruster particles) found
via live testing. The sections below it (mipmap fix/capturable tech/winch,
faction weapon art/recoil, ship building, combat, per-module damage) are
still accurate but predate that work.

## Most recent session (reverse engineering, pirate_light_one's wing, debris/thruster bug fixes, Manufacturers)

Five pieces of work, roughly in order:

- **Committed a large backlog of uncommitted work from the previous session**
  first (faction art assets/importer, railgun/phase lance weapons,
  capturable tech parts, the disabled winch, per-module damage) into two
  logical commits, since none of it had been committed yet.
- **Reverse engineering (Roadmap v.2-v.9 Version 0.5) wired up**: added
  `ModuleType.requires_research`, flagged **only Railgun and Phase Lance**
  (the two faction-exclusive weapons) — deliberately not every
  `is_capturable_tech` module, chosen via `AskUserQuestion` to keep the
  core weapon loop buildable from the start. `Inventory.research()` spends
  one captured part of that type to permanently unlock it; the ship
  builder palette shows a `[LOCKED]` disabled button plus a live-updating
  Research button next to it. Verified live: granting a captured part
  enables the Research button immediately via the `captured_tech_changed`
  signal (no re-open needed), and researching spends it and unlocks the
  palette entry for good.
- **Gave `pirate_light_one` a real severable wing** — it was previously a
  known, accepted gap (see "Per-module ship damage" below, now corrected):
  its Core was completely ringed by all 6 adjacent modules, and every
  other module touched at least two ring cells, so it had zero severable
  points by construction. Fixed by relocating its second engine from hex
  `(2,-1)` to `(3,-2)` and inserting a new single-cell Strut at `(2,-2)`
  as its *only* connection back to the ring (`hull` at `(1,-1)`) — two
  edits to `pirate_light_one.tres`, no code changes. Verified live: forcing
  lethal damage on just that Strut immediately detached the engine while
  the core, both ring hull/weapon cells, the other engine, and the reactor
  all stayed attached. Also incidentally confirmed the repair-over-time
  system's interaction with detachment is correct: the Strut itself (still
  connected the whole time) regrew after the repair delay, but the
  already-detached engine correctly stayed gone (detached modules are
  excluded from regeneration).
  - Struts had no faction art at all before this, so the new wing
    initially rendered as a flat grey-tinted hex, standing out against the
    rest of the ship — the user caught this from a screenshot. Fixed once
    the user supplied `pirate_strut.png`/`corporate_strut.png` (Ancient
    intentionally has none yet) by wiring them into `ModuleType
    .faction_hex_textures` the same way every other module's art loads,
    same mipmap-generation fix as the original faction art batch.
- **Two real bugs found via live testing, not review**:
  - **Severed modules (`ShipDebris`/`CapturedTechPart`) always rendered
    with `ModuleType.hex_texture`**, the single generic fallback image,
    instead of the actual faction-reskinned per-cell art the module was
    showing on the hull a moment earlier — `_debris_visual_data()` now
    uses `get_hex_texture_for_cell()` like `ShipLayoutRenderer` does, and
    both scenes draw with `hex_uv_corners_for_rotation()` (plumbing
    `rotation_steps` through `setup()`) so a rotated placement's severed
    art matches its hull orientation instead of resetting. Verified live:
    forcing a severance now spawns debris carrying `pirate_engine_mk1.png`,
    not a fallback.
  - **Engine thruster particles kept showing on a destroyed/detached
    engine** as long as the ship (or another engine) was still moving,
    since `_update_engine_particles()` only ever checked player/AI thrust
    input, never whether that specific engine's module was still alive.
    Fixed by having `Ship` track each thruster's `placement_id`
    (`_thruster_placement_ids`, parallel to `_thrusters`) and gating each
    one individually via `is_module_destroyed()`. Also repositioned each
    thruster from its hex's center to its trailing edge, so the flame
    visually bursts from the back of its own tile rather than the middle
    — **this took two attempts**: the first tried offsetting toward
    hex-grid-local `-X` and additionally rotated the thruster node itself
    by `_hull_renderer.rotation`, which the user caught as firing sideways
    instead of backward. The actual bug: `_hull_renderer.rotation` is a
    real, measured **+90°** fixed offset between the hex grid's own
    authored axes and the ship's true movement-forward (`+X`) — not zero,
    as an earlier read of the `.tscn` files (no rotation ever authored on
    a `HullRenderer` node) had wrongly suggested. Verified directly via
    `game_eval`: the hex-grid-local direction that actually maps to the
    ship's true backward after that rotation is **`+Y`** (a vertex per
    `HexUtils.hex_corners`, not an edge), and the thruster's own
    `rotation` needed to stay at its default 0 — setting it to
    `_hull_renderer.rotation` was double-applying the offset on top of the
    ship's already-inherited rotation. **Worth remembering for any future
    code that positions/orients something relative to a hex placement**:
    `_hull_renderer.rotation` only ever belongs in a *position* transform
    (matching how `hex_center`/collision shapes/hardpoints already use
    it), never in another node's own `rotation` property, since that
    node's rotation already inherits the ship's real rotation through the
    scene tree.
- **Assessed Roadmap v.2-v.9 Version 0.5 honestly against what's actually
  in the game**, since the user asked to check if it was done: reverse
  engineering now works, but **faction identity is still cosmetic-only**
  — Corporate and Ancient have art/tech but no actual enemy ships exist
  for either (every enemy in `scenes/enemies/` is a Pirate variant or the
  generic missile cruiser), and there's no faction-specific salvage beyond
  generic materials. **Explicitly deferred, not started, per user
  ("we can do the enemy ships later")** — see "Not yet started" below.
- **Added Manufacturers** (Atlas Heavy Industries / Nova Precision / Black
  Market Foundry — Version 0.5's other named sub-feature), designed via
  two rounds of `AskUserQuestion` covering scope (weapons + Reactor/Battery,
  not every module type) and build integration (a separate palette row per
  known manufacturer, not a place-time picker):
  - `scripts/economy/manufacturer.gd`/`manufacturer_catalog.gd`: a small
    stateless `Resource` + prototype catalog (same shape as
    `ModuleCatalog`), keyed by `ModulePlacement.manufacturer_id` (empty =
    generic) rather than exploding the module catalog per variant.
    `stat_modifiers: Dictionary` reuses the *exact* additive-delta
    technique `Ship`'s weapon/missile upgrade tree already uses
    (`node.set(prop, node.get(prop) + delta)`) instead of inventing a
    second modifier mechanism.
  - Weapon/missile modifiers apply at hardpoint spawn time
    (`Ship._apply_manufacturer_modifiers`). Reactor/Battery have no live
    spawned node, so their modifiers apply inside `ShipLayout`'s existing
    `total_energy_generation`/`total_energy_capacity`/`total_mass` sums
    instead (`_manufacturer_stat_delta`).
  - **Black Market Foundry's "dangerous" trait is a real mechanic, not
    just a stat**: `HardpointGun.malfunction_chance` can backfire a shot
    into self-damage on its own hull module via the existing per-module
    damage system (new `Ship.damage_own_module()` public wrapper around
    `_apply_module_damage`) — a genuinely risky weapon can sever its own
    mount if you lean on it.
  - **Discovery is tracked separately from research**: capturing a
    manufacturer-flavored part (`CapturedTechPart` now also carries
    `manufacturer_id`) marks that manufacturer known on `Inventory`
    (`discover_manufacturer`/`is_manufacturer_known`) — "a manufacturer
    exists" and "I can build this module type" are deliberately different
    facts. **Buying from a known manufacturer is an explicit, deliberate
    gap** — left as a data hook for once a station/trading system exists
    (Version 0.6), not built this session, per the user's own framing
    ("can be picked up, but eventually bought too when the user learns
    about them").
  - Ship builder palette grows one row per (module type × known
    manufacturer) once that module type is itself already unlocked (an
    "Atlas Railgun" row before Railgun itself is researched would be
    confusing and unplaceable) — required extracting palette-building into
    its own `_rebuild_palette()` so a newly discovered manufacturer can add
    whole new rows live, not just refresh existing lock state.
  - Seeded one real test case (Black Market Foundry on one of
    `pirate_light_one`'s weapon hardpoints) so the whole loop was
    live-testable rather than only unit-tested. Verified end-to-end via
    the godot-ai MCP tools: the enemy gun's spawned stats matched the
    hand-computed tier/core-distance/manufacturer combination exactly,
    a forced malfunction backfired and damaged its own module by the
    configured amount, capturing it discovered the manufacturer and the
    palette grew the new row immediately, and placing + applying that
    variant on the player's own ship produced a gun with the same
    manufacturer-modified stats. Also verified the Reactor/Battery
    total-based modifier path directly against hand-computed values.

### Still open from this session
- No Corporate or Ancient enemy ship exists — explicitly deferred by the
  user, not an oversight. Faction identity remains cosmetic/tech-only
  until this exists.
- No faction-specific salvage — materials are still fully generic across
  all three factions.
- Buying from a known manufacturer has no UI/economy to hook into yet —
  waits on a Version 0.6 station/trading system.
- Atlas Heavy and Nova Precision have no real in-game seed yet (only
  Black Market Foundry was placed on an actual enemy ship this session) —
  fine for now since the manufacturer system itself doesn't require any
  particular manufacturer to already exist in game data to be correct,
  but worth seeding once Corporate/Ancient enemies (or more pirate
  variants) exist.
- The `hardpoint_winch.gd`/`WinchRope` parse error noted in the previous
  session's "Known MCP/tooling gotchas" was observed again, unchanged, at
  the start of every `project_run` this entire session, purely from
  `recent_errors`/`retained_errors` — never once affected an actual running
  game (scene trees loaded fine, `WinchRope`'s `class_name` is declared
  correctly). Increasingly looks like a genuinely stale/cached editor-log
  entry rather than a real live issue — still not investigated further
  since the winch feature is intentionally disabled anyway.
- The user has an uncommitted edit to `CLAUDE.md` (a new "Communication
  style" section: be extremely concise, minimal narration, terse
  completion reports) sitting in the working tree, deliberately left
  uncommitted/untouched this session since it wasn't part of the
  requested work — worth adopting regardless of whether/when it's
  committed.

## Mipmap fix, capturable tech parts, and a disabled winch grapple session

Four pieces of work, roughly in order:

- **Fixed a real aliasing/clipping regression on the new faction art.** The
  user recalled an old fix from the previous (now-replaced) sprite set:
  `ship_layout_renderer.gd`/`hex_grid_control.gd` both set
  `texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` (still
  there, with a comment explaining hex art is authored much higher-res than
  it renders at). That filter mode is a no-op without an actual mip chain
  baked into the imported texture — checking every `.import` file found all
  6 old ship-art assets had `mipmaps/generate=true`, but **all 61** of the
  newer `resources/exports/{ancient,corporate,pirates}/*.png.import` faction
  assets had `mipmaps/generate=false`, silently defeating the filter for
  every faction sprite. Fixed by flipping all 61 to `true` and
  force-reimporting via `filesystem_manage`. Not yet visually re-confirmed
  in a live play session (only the `.import` metadata + reimport success
  were verified) — worth a quick eyeball pass at different zoom levels.

- **New capturable-tech-parts system** (a "reverse engineering" hook toward
  `Roadmap v.2-v.9.md` Version 0.5, chosen via an explicit `AskUserQuestion`
  covering reward type / drop gate / retrieval method): a severed (not
  destroyed-outright) module that (a) is flagged `ModuleType
  .is_capturable_tech` (Engine, Reactor Mk1, Battery Mk1, all weapon/missile
  hardpoint tiers, Railgun, Phase Lance — not Hull/Heavy Hull/Strut/Core),
  (b) still had at least `capture_health_fraction` (default 0.5) of its own
  condition at the instant of severance, **and** (c) passes a random
  `capture_chance` roll (default 0.35) spawns as a `CapturedTechPart`
  (`scenes/world/captured_tech_part.gd`/`.tscn`) instead of ordinary cosmetic
  `ShipDebris` — see `Ship._roll_capturable`/`_spawn_capturable_part_for`,
  which share cell/color/texture/centroid gathering with the debris path via
  the new `_debris_visual_data()` helper. Captured parts go into a new
  `Inventory` bucket (`add_captured_tech`/`get_captured_tech_count`/
  `get_all_captured_tech`) that deliberately doesn't do anything yet except
  exist — the research/unlock step itself is intentionally deferred, not
  started. Verified live end-to-end via the godot-ai MCP tools (forced
  severances on a weapon hardpoint and a missile rack, confirmed the
  non-capture branch still falls back to plain debris with no errors).

- **Built out a full player-driven winch grapple, then disabled it.** User
  originally asked for a physical retrieval mechanic (cast a rope on 'L',
  attach on touch, hold to reel in) rather than an ambient auto-lock beam;
  this went through several real iterations, each one driven by a genuine
  bug/gap the user caught by actually testing the feel, not just code
  review:
  - `HardpointWinch` (`scenes/player/hardpoint_winch.gd`/`.tscn`) is a real
    buildable hardpoint (`ModuleCatalog.WINCH_HARDPOINT_TYPE_ID`,
    `hardpoint_category = "winch"`) with a **fixed facing** set once from
    the placement's own `rotation_steps` (see `Ship._spawn_hardpoint_winches`)
    — deliberately not mouse-aimed like guns/missiles, since "the rope
    should come out in the direction the room is facing."
  - `WinchRope` (`scenes/player/winch_rope.gd`/`.tscn`) is a verlet-simulated
    rope (14 segments, distance-constrained, small perpetual undulation so
    it reads as slack/organic at rest — there's no real "down" to sag toward
    in top-down space). Anchor/tip endpoint motion is injected into nearby
    free points as real momentum (`_apply_endpoint_drag`) rather than only
    via the stiff constraint solver, so quickly moving the ship (or a
    grappled target) whips the rope along and it keeps swinging afterward —
    confirmed live: a forced leftward "tug" overshot *past* the ship's final
    resting position before swinging back.
  - Extending it can hit a `CapturedTechPart` (always pulled fully to the
    ship, captured on arrival — unchanged since the ambient-beam days) or
    grapple onto anything in `player_ship`/`enemy_ship`/`lockable`
    (other ships, asteroids — `Ship.get_winch_radius()`/
    `Asteroid.get_winch_radius()`). Grappling reuses `Ship.apply_impulse`
    (the same mechanism as weapon recoil) with **equal-and-opposite
    impulses on both ends**, so `velocity += impulse / mass` naturally makes
    the lighter side accelerate more — no explicit weight comparison needed.
    `Asteroid` has no `apply_impulse` at all (genuinely immovable
    `StaticBody2D`), so grappling one always pulls the *ship* toward it —
    the explicit "use the winch as a thruster substitute" ask. Confirmed
    live: holding the reel key moved the ship toward a spawned asteroid
    while the asteroid's own position never changed.
  - **Real bugs found via live testing, not review**: (1) a miss used to
    auto-retract instantly — fixed so the rope now stays paid out at
    whatever length it reached until the player manually reels it back in
    (`State.EXTENDED`). (2) That fix initially only called
    `WinchRope.update_rope()` while the reel key was held, so the anchor
    silently froze in world space the instant the rope went fully extended
    and stopped following the ship at all — caught by the user noticing the
    rope wasn't "staying connected," fixed by always resyncing the anchor
    every frame regardless of input. (3) Added a hard tether cap
    (`HardpointWinch._enforce_tether_limit`) so the ship physically cannot
    thrust farther than the rope's paid-out length from a grappled
    ship/asteroid — verified live by forcing the ship's velocity outward for
    40 straight physics frames against a grappled asteroid; distance
    climbed to exactly the cap and held dead flat. (4) The unattached
    (missed) tip used to stay planted as a dead point in space — fixed so it
    now rigidly follows the ship's current position/facing at whatever
    length it stopped paying out at ("floats with the ship").
  - **Disabled per explicit user request** ("good work in progress ... lets
    disable the idea for now") once all of the above was working: the
    single `ModuleCatalog` registration
    (`types.append(_make(WINCH_HARDPOINT_TYPE_ID, ...))`) is commented out
    with an explanation, so it can't be built/placed and never spawns on any
    ship — but every supporting file (`hardpoint_winch.gd`/`.tscn`,
    `winch_rope.gd`/`.tscn`, `Ship.fire_winch`/`set_winch_reel_input`/
    `get_winch_radius`, `ShipLayout.get_winch_hardpoint_placements`, the
    `fire_winch` input action bound to `L`) is left in place, untouched, to
    pick back up later.

- **Restored `CapturedTechPart` collection via the original `TractorBeam`**
  (`scenes/player/tractor_beam.gd`) once the winch was disabled — otherwise
  captured parts would drop but have no way to ever be collected. The beam
  now also scans the `capturable_tech` group alongside `salvage`, pulling a
  part in and — since it has no `Area2D`/collision of its own to trigger
  pickup on contact the way `Salvage` does — checking the distance itself
  and calling `Ship.capture_tech_part()` once close enough
  (`tech_part_collect_radius`). Verified live: a spawned part 150 units out
  was pulled in and captured within ~2 seconds.

### Still open from this session
- The mipmap fix hasn't been visually re-confirmed in an actual play
  session (only `.import` metadata + successful reimport were checked) —
  worth eyeballing a ship at a couple of zoom levels.
- No UI shows captured-tech counts anywhere yet, and nothing consumes them
  — the research/unlock step is a real, deliberate gap, not an oversight.
- Winch balance numbers (range, fire/reel speed, tether behavior, energy
  costs) were never tuned by feel, only functionally tested — irrelevant
  while disabled, but relevant again if it's picked back up.
- The disabled winch was never tested against a *moving* grappled target
  (only a stationary asteroid) — the tether cap and impulse-pull code paths
  for a grappled ship are untested in practice.

## Faction weapon art + recoil session

Follow-on session to the one that introduced Corporate Alliance/Ancient
Civilisation factions and the Railgun/Phase Lance weapons (that work isn't
detailed further up in this file yet — see git log / `module_catalog.gd` for
`RAILGUN_HARDPOINT_TYPE_ID`/`PHASE_LANCE_HARDPOINT_TYPE_ID` if picking that up
fresh). This session's work, in order:

- **Turret art now renders on the actual gun, not the hull.** `HardpointGun`
  (`scenes/player/hardpoint_gun.gd`/`.tscn`, and its `hardpoint_railgun.gd`/
  `hardpoint_phase_lance.gd`/`hardpoint_missile_launcher.gd` subclasses) gained
  a `Turret` `Sprite2D` child. `set_turret_texture()` draws a faction/tier's
  `turret_360`/`_mk2`/`_mk3` art rotated 90° (the art's authored "barrel
  points up" convention → this project's "barrel points +X" convention) and
  scaled so the image's own barrel tip lands exactly on the existing `Muzzle`
  marker position. The old flat-color `Barrel` polygon is now only a fallback
  for weapons/factions with no turret art yet (Railgun, Phase Lance, and any
  faction without a `turret_360*` file). **This replaced an earlier,
  abandoned approach** where the turret was drawn as a second static texture
  layer on the hull itself (`ModuleType.faction_hex_overlay_textures`) — that
  field still exists and is still used, but only by the *ship builder
  preview* now; the live hull renderer (`ShipLayoutRenderer`) deliberately
  stopped drawing it once the rotating gun took over, to avoid a
  non-rotating "ghost" turret showing through.
- **Multi-hex weapon base plates (tier II/III) are per-cell art, not one
  stretched image.** First attempt stretched a single `laser_cannon_mk2`/
  `mk3` image across the whole 2-/3-hex footprint's bounding box
  (`HexUtils.footprint_bounds`/`footprint_uv_corners` — **since removed**).
  This broke visibly: the art has a large flat-color background margin
  around a small centered mount icon (unlike `mk1`, which fills its canvas
  edge-to-edge), so stretching shrank the real artwork into one corner.
  **Fixed convention**: each tier is exported as one PNG per hex it occupies,
  named `<faction>_<base_name>_<q>_<r>.png` where `q,r` is that cell's own
  axial offset from `ModuleType.footprint_cells` (e.g.
  `corporate_laser_cannon_mk3_0_0`/`_1_0`/`_0_1` for `TRIANGLE_3_CELLS`).
  `FactionArtImporter.load_faction_textures_per_cell(base_name,
  footprint_cells)` loads one dict per cell; `ModuleType
  .faction_hex_textures_per_cell: Array[Dictionary]` stores them;
  `get_hex_texture_for_cell(faction_id, cell_index)` falls back to the old
  single-image `get_hex_texture()` if a cell has no dedicated piece — this is
  why Ancient/Pirates (which only have an unsuffixed `laser_cannon_mk1.png`,
  not yet re-exported with the new convention) still show correctly instead
  of going blank.
- **Rotating a multi-hex weapon didn't rotate its art with it.** A hex
  cell's world corners always sit at the same fixed angles regardless of
  which axial cell it is, so per-cell art stayed visually frozen in its
  original orientation even after `ShipLayout.rotate()` moved each piece to
  a different cell — breaking the seams between pieces. Fixed with
  `HexUtils.hex_uv_corners_for_rotation(rotation_steps)`, which cyclically
  shifts the UV-to-corner mapping so the sampled image itself rotates by
  `rotation_steps * 60°`. Used in both `ship_layout_renderer.gd` and
  `hex_grid_control.gd` wherever a per-cell base texture is drawn. Verified
  live at rotation_steps 0/1/3 — the assembly rotates as one rigid piece.
- **Ship builder was drawing the turret overlay 2-3x per multi-hex weapon**
  (once per occupied hex, since the draw loop is per-cell but the overlay is
  one whole icon meant to span the whole footprint) — looked like
  overlapping duplicate/warped icons. Fixed with a new
  `HexGridControl._draw_hardpoint_overlays()` pass that draws each
  placement's overlay exactly once, centered on the footprint's centroid,
  sized/rotated to roughly match the live `HardpointGun` turret sprite.
- **Real bug, not art**: `resources/ai/personality_user.tres` was missing
  `faction_id` entirely (never actually got saved in an earlier session
  despite being reported as done), so the player silently fell back to the
  script default `"pirate"` and showed the wrong hex set. Fixed by adding
  `faction_id = "corporate"` explicitly to the `.tres`.
- **Recoil "disappeared"**: it was never actually broken —
  `HardpointGun._apply_recoil()`/`Ship.apply_impulse()` (`velocity += impulse
  / mass`) always fired correctly — but `Ship`'s drag (`drag * max_speed ≈
  171 units/sec²` on the default ship) was strong enough to fully cancel the
  small recoil impulse within a single physics frame, making it
  imperceptible. **Note recoil is inversely proportional to ship mass** —
  a heavier ship will always feel less kick per shot at the same
  `recoil_force`, that's intentional. Per explicit user request, bumped
  `recoil_force` up 6x total from where it was at session start: base gun
  4.0 → 24.0, Railgun 10.0 → 48.0, Phase Lance 3.0 → 18.0. Verified live the
  kick now persists ~5 physics frames instead of being erased in <1, with
  rotation still exactly 0 (no return of the "whip" that was deliberately
  removed in an earlier session).
- **Asset-update workflow clarified for the user** (came up when a PNG
  replacement wasn't showing up): overwriting a PNG needs (1) the Godot
  editor to notice and reimport it — usually automatic on regaining focus,
  or force it with `filesystem_manage(op="reimport", paths=[...])` — **and**
  (2) the running game to be stopped/relaunched, since
  `FactionArtImporter._texture_cache` and `ModuleCatalog`'s cached type list
  are both `static var`s that only reset on a fresh game process. A
  brand-new filename (new faction folder, new per-cell piece) needs neither
  step — `FactionArtImporter` checks `ResourceLoader.exists()` at runtime.

- **Ancient and Pirates now have full weapon art too** (added later the same
  session): all three tiers' per-cell base pieces
  (`<faction>_laser_cannon_mk{1,2,3}_<q>_<r>.png`) and all three turret
  overlays (`<faction>_turret_360`/`_mk2`/`_mk3.png`). No code changes were
  needed — `FactionArtImporter`/`ModuleCatalog` are fully faction-agnostic —
  but getting them to actually load surfaced a real MCP-tooling gotcha, see
  below. Verified live for all three factions × all three tiers (`base`/
  `overlay` resolve to the right per-faction file, and a screenshot of an
  isolated tier-3 test ship for both Ancient and Pirate shows the mount
  spanning all 3 hexes coherently, matching Corporate's already-verified
  result).

### Still open from this session
- The ship builder's turret-overlay preview doesn't rotate to match a
  placement's aim the way the live in-game gun does — it's rotated by the
  placement's `rotation_steps` only, a reasonable approximation, not an
  exact match. Not reported as a problem, just a known simplification.

## Where things stand

The vertical slice is well past the original milestone list: flight movement,
camera, asteroids, a bounded explorable region with a home base, a working
ship builder (save/load, build costs, energy stats), a named-material economy
(Steel Alloy / Electronics / Reactor Components), an energy system (reactors/
batteries, thrust and weapon energy costs), a 4-archetype pirate AI
(Raider/Gunship/Missile Boat/Scout) with an Idle→Suspicious→Alert state
machine, and — the most recent major feature — **real per-module ship damage**
with wing detachment. **Version 0.1–0.3 of `Roadmap v.2-v.9.md` are done;
Version 0.4 (Combat Evolution) is in progress** — the per-module damage system
was the "engine failures as combat feedback" item, chosen by the user as
**"real per-module damage"** (not a cosmetic-only effect) via an explicit
`AskUserQuestion` answer.

### Ship building (done, wired into the flyable ship)
- Hex-grid (axial coordinates) layout data model under `scripts/ships/...`:
  `module_type.gd`, `module_placement.gd`, `module_catalog.gd` (still a
  static prototype catalog — documented as a stand-in for real `.tres`
  module resources), `ship_layout.gd` (place/remove/rotate, BFS connectivity,
  `validate_layout()`, plus the newer `find_unreachable_from_core()` used at
  runtime for wing severance — see below), `hex_utils.gd` (now also has
  `pixel_to_axial()`/`_hex_round()`, the inverse of `axial_to_pixel()`, shared
  by the builder's click grid and Ship's impact-point hit detection),
  `ship_layout_renderer.gd`.
- `scenes/ui/ship_builder/` — `hex_grid_control.gd` + `ship_builder_panel.gd`.
  Two-column layout: placeable module list on the right behind a 50%-opacity
  neon-blue background that now correctly covers the *entire* scroll area
  (an earlier version left a gap — fixed by giving palette buttons
  `clip_text = true` + `autowrap_mode` so long cost strings stop inflating
  the container's forced minimum width). **R** rotates, **X** deletes a
  selected module. Any visible `"menu_panel"`-grouped CanvasLayer suspends
  `ship_input.gd` polling each physics frame.
- Per-module build costs exist (`ModuleType.build_costs: Dictionary`,
  material id → amount), checked against `Inventory` in the builder.
- Saving/loading custom ships to disk works. The renderer draws the actual
  hull from `ShipLayout`; weapon hardpoints scale/visually change by tier.

### Economy / energy
- `scripts/economy/materials.gd` (`Materials.STEEL_ALLOY` /
  `ELECTRONICS` / `REACTOR_COMPONENTS`) + `scenes/player/inventory.gd`
  (Dictionary-based multi-material pool) replaced the old generic
  `salvage_value` int.
- Energy: `ModuleType.energy_generation` / `energy_capacity_contribution`
  (Reactor Mk1 / Battery Mk1 modules), `Ship.current_energy` /
  `max_energy` / `energy_generation_rate`, `has_energy()` / `spend_energy()`.
  Thrust, weapon fire, and the tractor beam all draw from the same pool.
  A baseline `base_energy_generation`/`base_energy_capacity` exists so
  ships with no Reactor/Battery still function. **AI ships use the exact
  same energy system as the player** — no separate/simplified AI economy.
- Numpad 5 (`debug_add_resources` input action, `scenes/world/debug_tools.gd`)
  adds 1000 of each material for testing — dev-only, not gameplay.

### Combat
- `hardpoint_gun.gd` / `hardpoint_missile_launcher.gd` + `missile.gd` —
  tier-scaled damage/fire-rate/energy-cost, torpedo-style missile flight
  (creep → coast → ignite-and-stay-on, homing off a **live** target
  reference, not a launch-time snapshot).
- `scenes/enemies/ship_ai.gd` — single AI script for every archetype, driven
  by a `ShipPersonality` resource. State machine: `IDLE → SUSPICIOUS → ALERT`
  (Alert is sticky; Suspicious reverts to Idle if the target leaves
  detection range before the reaction delay elapses; taking damage or
  already being in fire range jumps straight to Alert). Old
  Rammer/Sniper-style resources were replaced by
  `resources/ai/personality_{raider,gunship,missile_boat,scout}.tres`.
- **AI aim is now deliberately imprecise.** `_jittered_aim_point()` spreads
  each AI ship's aim across up to half the target's `get_layout_extent()`,
  re-rolled every 0.35s (not every frame, so the barrel drifts smoothly
  instead of vibrating). Added because AI previously aimed at the exact
  ship origin every shot — see "Per-module damage" below for why that was a
  real problem, not just cosmetic.
- `region_boundary.gd` gently pushes the player back inside a radius around
  the home base; a fixed pirate encounter exists in `map_tester.tscn`.

### Per-module ship damage + wing detachment (new this session, Version 0.4)
This is the big new system. A hit doesn't just drain the ship's overall
`Health` — it also resolves to a specific hex module and can destroy or
sever it independently.

- **`Ship._module_conditions: Dictionary`** (placement_id → current
  condition) is runtime-only state on the `Ship` node, **never stored on the
  `ShipLayout` resource**, because `ShipLayout` resources are shared (not
  duplicated) across every instance of the same enemy scene — storing
  mutable combat state there would let one ship's damage bleed into
  another's.
- **Hit resolution**: `Ship._damage_module_at_point()` converts a world
  impact point → hull-local space → hex coordinate (via
  `HexUtils.pixel_to_axial`) → the specific `ModulePlacement` there, and
  damages it. It also splashes `module_splash_fraction` (0.35) of the
  damage to the hit hex's immediate neighbors — added because landing
  repeated hits on the *exact same hex* on a moving, rotating target is
  very hard without it. **The Command Core is exempt from splash** — it
  ends the ship outright if destroyed, so it should only go down from a
  direct hit, not incidental crossfire aimed at whatever's clustered
  around it.
- **Wing severance**: `ShipLayout.find_unreachable_from_core()` is a BFS
  from the core over non-destroyed placements (never mutates
  `placements`). After any module is destroyed, `Ship._check_for_detachment()`
  calls it; any placement that's no longer reachable is severed
  (`Ship._detach_module()`) — it stops contributing (engines lose thrust,
  weapons stop firing), loses its collision shapes, and spawns a cosmetic
  `ShipDebris` node (`scenes/world/ship_debris.tscn`/`.gd`) that drifts off
  under the ship's velocity + a small kick/spin and fades out after 8s.
  Debris is visual-only — no collision, can't be re-shot or salvaged.
- **A destroyed module is a hole, not solid wreckage** — `_on_module_destroyed()`
  frees that placement's collision shapes too (not just detached ones).
  Without this, a scorched-but-still-attached module kept physically
  blocking shots aimed at whatever was behind it.
- **Core destruction = instant ship death.** Without a core,
  `find_unreachable_from_core()` has no anchor and goes permanently inert,
  so a core-less hulk could otherwise fly around forever with leftover
  modules that can never finish disconnecting. `_on_module_destroyed()`
  special-cases the core: it forces `Health` to zero immediately instead
  of running the normal detachment check.
- **`Ship._check_all_modules_gone()`** forces the ship to actually die once
  every module is destroyed/detached, even if the overall `Health` pool
  hasn't run out — needed because splash damage lets modules collectively
  take more cumulative damage than `Health` ever registers, which could
  otherwise leave a fully-gutted, all-black ship still flying around.
- **New "Strut" module** (`module_catalog.gd`): single-cell, cheap (3 Steel
  Alloy), lower mass/health than Hull. Deliberately fragile connective
  tissue for wings — a cheap way to build a winged/interesting-looking ship
  without over-investing in durability, as opposed to Hull (sturdier,
  costs more).
- **Current module health balance** (tuned this session via live combat
  testing, not just math): Core 140, Hull 50, Heavy Hull 240, Strut 25 —
  see "Decisions made" for why these specific numbers.
- **Fixed since**: `pirate_light_one` previously had every module directly
  adjacent to the core (or with 2+ redundant connections) — architecturally
  a blob with no severable point at all, by construction. A later session
  (see "Most recent session" at the top) gave it a real one-point-of-failure
  Strut-connected wing. `pirate_light_two` and `pirate_heavy_one` haven't
  been audited for the same issue and may still be blobs.

### World
- `starfield_layer.gd` + `ParallaxBackground` layers, bloom via one
  `WorldEnvironment` node.
- One planet (`scenes/world/planet.tscn`), visual-only, no collision, no
  data-resource/catalog system — matches "only one for now" framing.

## Decisions made (and why — don't relitigate without reason)

- **Ship-centric, not player-centric architecture** — AI and player ships
  share the same `Ship`/`ship_ai.gd`/`ship_input.gd` split.
- **Hex grid with axial coordinates (`Vector2i`)**, not a square grid.
- **Static `ModuleCatalog` is a deliberate, documented prototype shortcut.**
- **Never silently no-op** — every rejected ship-builder action surfaces a
  specific reason string.
- **Exactly one Command Core** enforced as a current layout rule.
- **Menu-open input suspension is group-based** (`"menu_panel"` group).
- **Missile torpedo behavior is a one-shot phase sequence**, not a
  repeating burst/coast cycle (explicitly tried and rejected).
- **Planets are visual-only for now** — no catalog/orbit system until asked.
- **Per-module combat state lives only on `Ship`, never on `ShipLayout`**
  — see "Per-module ship damage" above; this is the load-bearing reason the
  whole system is safe to use on shared enemy-scene resources.
- **A destroyed module frees its collision shape; a detached module also
  spawns cosmetic debris and loses its stat contribution** — destruction
  and severance are two related but distinct events, both funnel through
  `is_module_destroyed()` for gameplay-effect checks (fire/thrust gating).
- **The Core is a special case, deliberately**: toughest single module
  (140 HP, more than Hull), exempt from splash damage, and destroying it
  ends the ship immediately rather than leaving orphaned modules with no
  anchor to measure connectivity against.
- **AI aim is intentionally imprecise (spread across the target's hull,
  re-rolled periodically)** — added specifically because AI previously
  aimed at the exact ship origin every single shot, which coincides with
  where the Core sits by convention, making it a guaranteed bullseye the
  instant any armor in front of it broke. This was confirmed empirically
  (see "How the balance numbers were reached" below), not just theorized.
  **This only affects AI-controlled ships** — player weapon accuracy was
  deliberately left untouched.
- **Splash damage (`module_splash_fraction = 0.35`) exists specifically to
  make focused-fire severing achievable** against a moving/rotating target,
  since landing several hits on the exact same hex by pure aim is
  unrealistic. It has a real side effect: modules clustered near each
  other (e.g. everything crowded around the core) take much more effective
  cumulative damage than an isolated module out on a wing — this is why
  the Core specifically had to be made splash-exempt.

### How the balance numbers were reached (worth reading before re-tuning)
The Hull/Heavy Hull/Core/splash numbers above weren't picked from theory —
they came from live testing via the godot-ai MCP tools: building a real
long test ship (core + 2-row heavy-hull wall + rooms behind it) and having
an actual spawned `PirateLightOne` fight it for real (real AI aim, real
projectile physics), not scripted damage calls. That testing found and
fixed, in order: (1) Hull was too tough relative to weapon damage for
wings to ever sever in a real moving fight → lowered Hull health + added
splash. (2) A destroyed-but-attached module still blocked shots to
whatever was behind it → freed its collision shape too. (3) All modules
could reach zero condition while the ship's separate `Health` pool still
had some left, so a fully-gutted ship kept flying → added
`_check_all_modules_gone()`. (4) Once the Core died, leftover modules
could never finish disconnecting → Core death now ends the ship instantly.
(5) A ship's Core died in under a second to just 2 tier-1 guns because
splash let a dense module cluster's damage compound, *and* because AI
literally aims at the exact ship origin (= the Core's location by
convention) → Core buffed + made splash-exempt + AI aim jittered. Each
step was verified by re-running the same live pirate-vs-test-ship scenario
and comparing module-condition traces before/after — if you need to
re-tune these numbers, that's the methodology to repeat, not pure math.

### `_hull_renderer.rotation` is a real, nonzero fixed offset — not just defensive code
`ShipLayoutRenderer.rotation`/`Ship._hull_renderer.rotation` is a measured
**+90°** on every ship checked so far, not the "probably always 0, just
future-proofing" it looks like from grepping `.tscn` files (no `HullRenderer`
node has an authored `rotation` value on disk — it's set some other way).
It rotates the hex grid's own authored axes into the ship's true
movement-forward (`+X`) axis. Consequence: hex-grid-local `-X` is **not**
"the ship's back" — the direction that actually maps to the ship's true
backward after that rotation is hex-grid-local `+Y` (a *vertex*, not an
edge, per `HexUtils.hex_corners`). This only matters when something needs
to be positioned/oriented relative to a hex placement in a direction other
than "at the hex center": always apply `_hull_renderer.rotation` to a
*position* offset (same as `hex_center`/collision shapes/hardpoints already
do), and never to another node's own `rotation` property — that node
already inherits the ship's real rotation through the scene tree, so
adding `_hull_renderer.rotation` on top double-applies it. Confirmed by
directly measuring `_hull_renderer.rotation` via `game_eval` and
solving for the correct direction, not by guessing — see thruster
particle positioning in "Most recent session" for the bug this caused.

### Manufacturers are deliberately separate from Factions
A `Manufacturer` (Atlas Heavy Industries / Nova Precision / Black Market
Foundry) is a stat-modifier profile independent of faction — it answers
"what engineering philosophy built this specific part," not "whose
territory/art is this." A Corporate ship and a Pirate ship can both mount
an Atlas reactor. This is why manufacturer data lives on the individual
`ModulePlacement` (`manufacturer_id`) rather than on `ModuleType` or
`ShipPersonality` — the same module type can exist with or without a
manufacturer, and different placements of the same type can have
different manufacturers. Discovering a manufacturer (via capture) and
researching a locked module type are **two separate gates** on purpose:
knowing "Atlas Heavy exists" and being able to "build a Weapon Hardpoint
I" are different facts, and the ship builder only ever shows a
manufacturer-flavored palette row once *both* are true.

## Known MCP/tooling gotchas (only relevant if using the godot-ai MCP tools)

- **A brand-new asset file (never seen by the editor before) can silently
  fail to import even after both `filesystem_manage(op="scan")` and
  `filesystem_manage(op="reimport", paths=[...])`** — `load()`/
  `ResourceLoader.exists()` on it will return null/false with no error other
  than an editor-log line like `No loader found for resource: ... (expected
  type: unknown)`. Diagnose with `filesystem_manage(op="search",
  name=<file>)`: an already-imported file reports its real type (e.g.
  `"CompressedTexture2D"`); a stuck one reports `"type": ""`. **Fix**: hand-write
  a minimal `.import` stub next to the source file (copy an existing sibling
  `.import`, keep `importer`/`type`, put in any placeholder `uid=` and
  `dest_files=[...]`/`path=` — content doesn't need to be correct) so the
  editor recognizes it as an importable resource, then
  `filesystem_manage(op="scan")` followed by `reimport(paths=[that file])` —
  Godot then overwrites the stub with the real hash-based `.ctex` path
  itself. Confirmed this was the actual cause the one time a freshly
  delivered batch of PNGs "wasn't showing up" even after a normal
  reimport — every affected file was simply missing its `.import` sidecar
  entirely (`ls` the folder to check), not a stale-cache problem.
- Avoid `for i in range(...)` loops inside `game_eval` test scripts — they
  can silently execute only once. Use sequential explicit statements.
- GDScript has no C-style ternary — use `a if cond else b`.
- A runtime error inside an ad-hoc `game_eval` script can park the running
  game in a debugger "break" state; every subsequent `game_eval` then fails
  referencing the *old* stale error until you `project_manage(op:"stop")` +
  `project_run` again.
- `game_eval` calls that `await` for longer than ~8s are aborted
  (`EVAL_HUNG`) — but the awaited code keeps running in the live game
  regardless of the tool timeout, so game state (e.g. a ship dying mid-test)
  still changes even though the call "failed". Poll in shorter chunks
  (≤ ~6-7s of in-game `await` per call) instead of one long loop, and
  always guard follow-up node access with `is_instance_valid()` — a node
  can be freed (e.g. a ship destroyed mid-test) between one `game_eval`
  call and the next.
- `input_action` only sets an action's pressed *state* — it does not
  dispatch a real `InputEvent`, so anything relying on `_unhandled_input`
  won't fire from it. Use `input_key` with the actual bound key instead.
- `get_tree().get_nodes_in_group()` order isn't guaranteed stable across
  calls — filter by `.name` rather than trusting index 0.
- After editing a `.tscn`/resource file directly on disk while it's the
  open scene, use `scene_open(force_reload=true)`.

## Not yet started (no explicit user request yet — don't start without one)

- **Corporate or Ancient enemy ships.** Explicitly deferred by the user
  ("we can do the enemy ships later") after the Version 0.5 gap-check —
  every enemy in `scenes/enemies/` is currently a Pirate variant or the
  generic missile cruiser, so faction identity (art/tech/Manufacturers)
  never actually shows up in combat for the other two factions.
- Faction-specific/unique salvage — materials are still fully generic
  across all three factions; only captured tech parts and (new)
  manufacturer discovery carry any faction/manufacturer identity.
- Buying from a known manufacturer once discovered — waits on a Version
  0.6 station/trading system that doesn't exist yet.
- Give `pirate_light_two`/`pirate_heavy_one` a severability audit —
  `pirate_light_one` was fixed this session (see "Most recent session");
  the others were never checked for the same "zero severable points"
  blob issue.
- Reactor/Battery/Command-Core-adjacent modules other than engines/weapons
  still have no *mechanical* effect when destroyed beyond losing the hex
  (no repair mechanic either).
- Player weapon accuracy/spread — untouched on purpose.
- More module types / a real data-driven (non-static) module catalog as
  `.tres` resources.
- A planet catalog, multiple planet instances, orbit/parallax motion, or
  any planet-surface gameplay.
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (warp gates, research beyond reverse-engineering, co-op).

## Suggested next step

Version 0.4 (Combat Evolution) is now essentially complete —
`pirate_light_one`'s wing was the one known gap. Version 0.5 (Technology &
Factions) has real substance now too (reverse engineering + Manufacturers
both work end-to-end), but its one deliberately-deferred gap is enemy
ships for Corporate/Ancient — faction identity is still cosmetic/tech-only
in actual combat. No specific next item has been chosen yet; candidates on
the table: build a Corporate or Ancient enemy ship (closes the biggest
remaining Version 0.5 gap), audit `pirate_light_two`/`pirate_heavy_one` for
the same severability issue `pirate_light_one` had, or have the **user
actually playtest current combat** (real ship, real weapons, real
pirates) now that per-module damage, wing severance, research gating, and
Manufacturers have all landed without a real playtest pass. Do not start
any of these without the user confirming which first.

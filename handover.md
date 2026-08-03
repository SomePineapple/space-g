# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up. `docs/gotchas.md` has durable GDScript/Godot/MCP
gotchas pulled out of session history — check it before fighting a weird
engine/tooling behavior.

**Read "Most recent session" first.** Sessions older than the two kept in
full below are compressed to short summaries — full narrative detail (exact
iteration steps, every dead end tried) has been trimmed since it's rarely
needed again; if you need it, it's in git history / this file's prior
versions. Design-reference docs (`docs/aienemies.md`, `docs/region_design.md`)
remain the source of truth for the systems they cover, not this file.

## Most recent session (Phase 4.1 Basic Mining Grinder)

Implements a user-supplied "4.1 Basic grinder" spec: a close-range,
contact-operation mining tool that damages asteroids, breaks off
collectible ore fragments, and plugs into the existing Tractor Beam/Storage
pipeline from the two sessions below rather than building a parallel
collection path.

- **New hex module, 2-cell footprint** (`ModuleCatalog.GRINDER_HARDPOINT_TYPE_ID`
  = `"mining_grinder_hardpoint"`, `hardpoint_category="grinder"`,
  `LINE_2_CELLS` — the same footprint constant Railgun/Weapon Hardpoint II
  already use). This is the first hardpoint in the project to combine "spawns
  a real world node" (like Tractor Beam/guns) with "occupies 2 hexes" (like
  Railgun) — the anchor (back) cell is cosmetic, the front cell (footprint
  offset `(1,0)`, rotated with the placement) is the actual grind/contact
  point. Lime-green (`Color(0.65, 0.85, 0.15)`), checked against the existing
  palette per the standing rule — every warm hue (red/orange/yellow/brown)
  was already taken by Weapon/Missile/Reactor/Storage. No dedicated art yet
  — generic flat-tinted hex, same as every other undecorated hardpoint.
- **`scenes/player/hardpoint_grinder.gd`/`.tscn`**: modeled directly on
  `HardpointTractorBeam` (energy-draining pull-model node) but **player-
  toggled, not always-on** — the spec explicitly calls for a G-key toggle
  since continuous damage shouldn't run passively the way a passive tractor
  pull does. `Ship._grinder_active: bool` is flipped by `toggle_grinder()`
  and pulled every physics frame by each mounted `HardpointGrinder` via
  `Ship.is_grinder_active()` (same pull-model as `is_module_destroyed`,
  chosen so a grinder that mounts/repairs mid-toggle picks up current state
  immediately rather than needing a fresh key press). While toggled on and
  an `Asteroid` sits within `contact_range` (55, measured from the asteroid's
  own surface via `get_winch_radius()`, not its center) of the Muzzle: drains
  `energy_cost_per_second` (7) from the shared pool same "spend-or-stop" as
  Tractor Beam/Winch, applies `damage_per_second` (14) via plain
  `Asteroid.take_damage()` — **deliberately not `take_damage_at()`**, since
  that method's knockback/scatter-velocity mechanic (built for one-off
  weapon hits) would make a *held* grind fight the asteroid drifting away
  every frame — and breaks off one collectible ore fragment every
  `fragment_interval` (1.0s) while grinding continues.
- **Fragments are real `Salvage` instances**, not a direct cargo grant —
  spawned at a point between the Muzzle and the asteroid, same rarity odds
  as a normal kill-drop (`Asteroid._roll_ore_rarity()` renamed to public
  `roll_ore_rarity()` so the grinder can call it without duplicating the
  COMMON/ELECTRONICS/ENERGY bands). Being ordinary `Salvage` nodes in the
  `"salvage"` group means the entire existing pipeline applies with zero new
  code: the Tractor Beam pulls them from range, self-collection via hull
  overlap works, `try_add_material`/`storage_full`/the Cargo screen's
  capacity limit all apply unchanged. Nothing here duplicates a reward —
  each fragment is a distinct spawn, and the asteroid's own final on-death
  salvage (unchanged, still exactly one per `_finish_destruction()`) is a
  separate, later event once the fragment loop has already been chipping
  away at Health.
- **Visual feedback**: a pulsing orange `Line2D` beam from Muzzle to the
  asteroid while actively grinding, same technique (and the same "cache the
  additive `CanvasItemMaterial`, don't allocate one per event" gotcha) as
  the Tractor Beam's own beam. Audio explicitly deferred per the spec ("audio
  will come later").
- **Weapons deliberately not nerfed to make this satisfy "standard weapons
  are less effective/unsuitable for mining."** A gun only ever yields
  material on an asteroid's final kill (one salvage per tier, unchanged);
  the grinder yields fragments continuously *while the asteroid is still
  alive*, so it's strictly more resource-efficient per second without
  touching weapon damage numbers — see "Decisions made" below.
- **Starter ship** (`resources/ships/starter_ship_layout.tres`) gained one
  Mining Grinder at anchor `(2,1)`/`rotation_steps=1` (front cell `(3,0)`) —
  the only two adjacent free cells left touching the existing hull cluster
  after Tractor/Radar/Scanner/Storage filled every inner-ring hex; this
  puts the module 3 hex-steps from the Core, physically at the hull's outer
  edge, which is fine (equipment doesn't need to sit centrally) but is worth
  knowing when reasoning about `contact_range` reach from the ship's own
  center.
- **New input action `toggle_grinder`** (**G**, previously unbound),
  matching the existing `toggle_<noun>` convention (`toggle_scan`,
  `toggle_cargo`), wired in `ship_input.gd` on the just-pressed edge.
- **Verified live** via godot-ai MCP end-to-end: spawned a real asteroid at
  the grinder's actual Muzzle position (not the ship's center — the two are
  ~120 units apart given the outer-ring mount point above, a real trap hit
  once during this session's own testing), toggled grinding on, and
  confirmed Health draining, a SMALL-tier asteroid actually dying, and
  cargo (`Inventory.get_cargo_used()`) rising by the correct fragment +
  kill-drop amounts. Separately confirmed the Tractor Beam pulling a
  grinder-style `Salvage` fragment in from 180 units away (within its
  250 max_range) into cargo. Clean launches throughout, no new
  errors/warnings in either the editor or game log across the whole test
  session. Hit and worked around the documented `game_eval` tabs/spaces
  parser gotcha twice more (still current — any indented `if`/`for` block
  in an eval string needs consistent tabs, not spaces, or the game parks in
  a debugger break requiring `project_manage(op="stop")` + a fresh
  `project_run`).
- **Follow-up in the same session: user reported the beam exiting a
  different hex face than the builder's rotation arrow suggested.**
  Investigated end-to-end with live numeric verification (not just hand
  math, which was genuinely error-prone here — `HexUtils.rotate()`'s output
  order does not match `HexUtils.HEX_DIRECTIONS`' own array order, a real
  trap): confirmed via `game_eval` that `HardpointGrinder`'s actual mounted
  rotation matches the true occupied front-hex direction to 5 decimal
  places — **the beam itself was never wrong.** The real bug was
  `hex_grid_control.gd`'s per-placement rotation arrow using `60° *
  rotation_steps - 90°`, an arbitrary "point up by default" formula that
  doesn't correspond to any real hex-neighbor angle (only 0/60/120/180/240/
  300° are ever real), so it could point up to 90° away from a module's own
  real front hex. **Per explicit user request, the fix was reverted** —
  the `- 90°` is being kept on purpose so an unrotated module still visually
  reads as "facing up" in the builder, which matters more for UX than exact
  hex-math accuracy on a decorative preview arrow. The tradeoff (and why the
  real front-hex direction for a multi-hex module is the module's own
  second hex tile, not this arrow) is now spelled out in a comment right at
  the formula, plus a corresponding `docs/gotchas.md` entry so a future
  agent doesn't "helpfully" re-remove the offset. Also corrected that same
  `docs/gotchas.md` entry's older, overly-broad claim ("never add the +90°
  offset to another node's own `.rotation`") — that claim was written
  narrowly around the thruster case and doesn't hold for a fixed-facing
  hardpoint's rotation (Winch/Grinder), which genuinely needs it and is
  confirmed correct.

### Still open from this session
- No dedicated art for the Mining Grinder hex — generic flat-tinted hex like
  every other undecorated hardpoint.
- Audio feedback explicitly deferred by the spec itself ("audio will come
  later") — only the visual beam exists.
- Numbers (`contact_range` 55, `damage_per_second` 14, `energy_cost_per_second`
  7, `fragment_interval` 1.0) are first-pass, not tuned against real play —
  same caveat as every other hex module's initial numbers in this project.
- "One generic mining speed (upgradable?)" — only the flat generic speed was
  built; no upgrade path exists yet (mirrors the Tractor Beam's identical
  "multi-target upgradable later" deferral).
- No AI/pirate ship carries a Grinder or minds one — irrelevant today, same
  scope note as every other hardpoint session.

## Session before that (Phase 3.2 Storage capacity + 3.3 Storage module)

Implements a user-supplied "Phase 3 — Physical Salvage and Cargo / 3.2
Storage capacity" and "3.3 Storage module" spec together in one pass (the
user explicitly asked for both at once since they're directly related).
Builds on the Tractor Beam session directly below — salvage collection
already existed, this session caps it.

- **Cargo capacity lives on `Inventory`** (`scenes/player/inventory.gd`):
  `_cargo_capacity: float`, `get_cargo_capacity()`/`get_cargo_used()` (sum of
  `_material_totals`)/`has_cargo_space(amount)`. Recomputed by `Ship`
  whenever its layout changes (`Ship._apply_layout_cargo_capacity()`, called
  from `_apply_ship_layout()` alongside the existing energy-capacity
  recompute) — same "baseline + layout total, preserve nothing to preserve
  here" shape as `max_energy`. `base_cargo_capacity` (100) is a new `@export`
  on `Ship`, mirroring `base_energy_capacity`.
- **Two parallel collection paths, deliberately kept separate:**
  `Inventory.add_material()` stays completely uncapped — used by ship-builder
  refunds, the debug resource cheat, and `GameState`'s scene-change restore,
  all of which must never fail. A new `Inventory.try_add_material()` is the
  only capacity-checked path, used exclusively by `Salvage` pickup; it
  returns false and emits a new `storage_full` signal instead of exceeding
  capacity. `Ship` exposes both as thin wrappers (`add_material` unchanged,
  new `try_add_material`/`discard_material`). This means a refund or the
  debug cheat *can* push cargo over capacity (allowed, matches "no resources
  silently deleted" — it just blocks further collection until it's back
  under), but real salvage pickup never can.
- **`Salvage.gd` pickup rewritten to reject cleanly instead of always
  consuming.** `_on_body_entered` now calls `_try_collect(body)`, which uses
  `try_add_material` if present. On rejection the salvage node is **not
  freed** — it stays in the world, overlapping the ship, and a new
  `_pending_pickup_body` + `_process()` retry keeps attempting the same
  collection every frame until it succeeds (cargo freed up via discard) or
  the body/overlap goes away (ship drifts off). Without this retry,
  discarding cargo to make room wouldn't free a salvage piece already
  sitting on the hull until it drifted away and back — confirmed via live
  testing that the retry does pick it up the moment space frees, without
  double-applying `is_dangerous` damage (that's now gated behind an actual
  successful collect, not attempted on every rejected touch).
- **New "Cargo Container" module** (`storage_mk1`,
  `scripts/ships/modules/module_catalog.gd`): a plain stat contributor like
  Reactor/Battery (`hardpoint_category=""`, +60 cargo capacity, 8 Steel
  Alloy), not a hardpoint category — storage has no facing/muzzle/HUD gate of
  its own, so unlike Tractor/Radar/Scanner it doesn't need the "pure
  capability flag" treatment, just a new `ModuleType.cargo_capacity_contribution`
  field (mirrors `energy_capacity_contribution`) summed by
  `ShipLayout.total_cargo_capacity()`. No distance-from-core falloff (unlike
  Reactor/Battery's energy penalty) — cargo capacity is just hold space, not
  power delivery, so hex placement doesn't matter. No dedicated art —
  generic flat-tinted hex (brown/tan, checked against the existing palette
  per that standing rule), same as Strut/Tractor/Radar/Scanner.
- **Ship builder module removal now blocks removing a Storage module if the
  ship's *current* held cargo would exceed the reduced capacity**
  (`ship_builder_panel.gd._on_remove_pressed`) — the chosen option from the
  spec's "Prevent removal when over capacity, OR require explicit cargo
  disposal" pair. Checked against the live `Inventory`'s actual usage (not
  the in-progress `working_layout`, since the builder only applies to the
  real ship on close) — the player has to discard cargo first via the new
  Cargo screen. Builder's stats line also gained a `Cargo: used/capacity`
  readout next to the existing Health/Mass/Energy numbers.
- **New dedicated Cargo screen** (`scenes/ui/cargo_panel.gd`/`.tscn`,
  instanced in `map_tester.tscn`): capacity readout, one row per material
  with "Discard 10"/"Discard All" buttons, built procedurally matching
  `trade_panel.gd`'s exact conventions (same background/row constants,
  `"menu_panel"` group membership). Deliberately **not** gated to home-base
  range like Trade/Builder — discarding cargo is something a player may need
  mid-flight, not a base-only activity. New `toggle_cargo` input action
  (**C**, previously unused).
- **HUD feedback** (`scenes/ui/hud.gd`/`.tscn`): the existing always-on
  SalvageLabel now appends `Cargo: used/capacity` to its live material
  readout. New transient "STORAGE FULL" label (fades in instantly, holds,
  fades out over ~2s total) triggered by `Inventory.storage_full`, same
  `Tween`-based pattern as the existing damage flash.
- **Starter ship** (`resources/ships/starter_ship_layout.tres`) gained one
  Cargo Container at (2,0) — adjacent to `hull_a`, the only free neighbor
  cell left once Tractor/Radar/Scanner filled every hex around the Core —
  bringing the default ship to 160 total capacity so default play isn't
  regressed.
- **Real gotcha re-hit, now written into `docs/gotchas.md`:** editing
  `starter_ship_layout.tres` directly on disk while the editor was running
  got silently reverted by `project_run`'s default `autosave=true` writing
  the editor's stale in-memory copy back over the disk edit — the exact
  `.tres`-outside-an-open-scene staleness gotcha noted-but-not-yet-documented
  after the previous session. Recovered by re-applying the edit, then
  `filesystem_manage(op="reimport")` + `scan()` before the next
  `project_run` (passed `autosave=false` from then on this session) — now
  captured as a permanent gotchas.md entry instead of a one-off note here.
  Also hit and documented a second new gotcha: a multi-line `game_eval`
  script mixing tabs/spaces parks the game in a debugger break.
- **Verified live** via godot-ai MCP: `has_cargo_space`/`try_add_material`
  accept under capacity and reject over it without altering `_material_totals`;
  a real spawned `Salvage` node sitting on the ship gets rejected while full
  (stays alive, `_pending_pickup_body` set) and is auto-collected the frame
  enough cargo is discarded to fit it (confirmed via the reference going
  null/freed); HUD's `Cargo: x/y` and the "STORAGE FULL" flash both update
  live. Ship-builder removal-blocking and stats-readout logic were verified
  by code review, not exercised through the builder's UI directly this
  session (no UI automation available) — flagged as untested-in-editor.

### Still open from this session
- No dedicated art for the Cargo Container hex — generic flat-tinted hex.
- Discard is fixed-quantity (10) or all — no arbitrary-amount input field.
- Ship builder's removal-block and stats-readout changes weren't exercised
  through the actual builder UI this session (only verified by reading the
  code) — worth a real playtest pass placing/removing Storage modules.
- Captured tech parts remain a separate, uncapped bucket — cargo capacity
  only applies to `_material_totals` (Steel Alloy/Electronics/Reactor
  Components), by design (see Inventory's own doc comment on that
  distinction), not extended to tech parts.
- No pirate/AI ship carries a Storage module or has any cargo-capacity
  concept — irrelevant today since only the player ship's Inventory is ever
  read, same scope note as every other hex-module session before this one.

## Earlier sessions (compressed)

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

- **Tractor Beam + Radar/Scanner as hex modules (Phase 3.1):** moved the
  always-on `TractorBeam` off `ship.tscn` onto a real hex module
  (`tractor_beam_hardpoint`, `scenes/player/hardpoint_tractor_beam.gd`) —
  after two explicit pivots (player-held single-key version reverted to
  always-on; multi-target-at-once narrowed to exactly one target,
  "upgradable later") landed on: always active while mounted/intact, single
  nearest valid target (`Salvage`/`CapturedTechPart`) in range with clear
  line of sight, drops safely if blocked/out of range/energy. Radar and
  Scanner got the same treatment but as a **"pure capability flag"**
  instead (no spawned node — `Ship.has_radar()`/`has_scanner()` just check
  for an intact hardpoint of that category; `radar_hardpoint`/
  `scanner_hardpoint`, HUD hides live on loss/repair). Radar recolored green
  (was too close to Engine/Tractor's blues), Scanner given magenta. Starter
  ship gained one of each. Two real bugs fixed: a freed-instance-into-typed-
  parameter crash (fix: `is_instance_valid()` inline at the call site, not
  inside a helper — this pattern recurs, see `HardpointGrinder`/
  `HardpointTractorBeam`), and a `.tres`-outside-an-open-scene stale-cache
  issue (now in `docs/gotchas.md`). Verified live throughout.
- **Points of Interest (Phase 2.3):** implements a user-supplied "Phase 2 —
  Information and Discovery / 2.3 Basic points of interest" spec, built
  entirely from existing systems (no new framework). Four hand-placed types
  in `map_tester.tscn`: **Small Pirate Camp** (`scripts/world/poi_camp.gd`,
  radar `"enemy_camp"`, clears once all pirates die — combat/reward needed
  zero new code, reusing existing idle-AI/salvage-drop behavior), **Distress
  Signal** (`distress_signal.gd`/`.tscn`, radar `"distress_beacon"`, clears
  once its child Salvage is collected), **Abandoned Ship** (`scannable.gd`,
  `"Wreck"` category, reused hull/cockpit art tinted/scaled), **Scenic
  Formation** (`scannable.gd`, `"Ancient Formation"`, discovery-only, no
  reward). "Wrecks"/"Abandoned ships" spec bullets were deliberately merged
  into one type; "Simple derelict structures" wasn't built as a separate
  fifth (would have been pure duplication) — confirmed via
  `AskUserQuestion` first. Every POI stayed strictly on one side of the
  Radar/Scanner boundary rule (camp/distress = radar-only, wreck/formation =
  scanner-only). Not a data-driven spawner — four hand-placed instances
  didn't justify one. Verified live (group membership, kill-clears-camp,
  collect-clears-beacon, real Scanner pulses against both scannables).

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

- **Scanner (Phase 2.2) + a radar rework:** implements a user-supplied
  "Phase 2.2 Scanner" spec. Went through several live pivots: single-target
  identify-scan → long-range list scan (one press, 1.5s channel, closest-5
  results — the current shape; a "player writes their own guess"
  memory/journal alternative was explicitly deferred, not built);
  Common/Dense/Rare asteroid composition → count-based clusters ("Asteroid
  Cluster (6)"), proximity-grouped; briefly added then reverted both a
  scannable home station and asteroid-cluster radar blips, establishing the
  **hard Radar/Scanner boundary rule** (radar = live faction/activity,
  short-range; Scanner = off-the-grid identification, long-range) — Radar
  pulled down to 1800, Scanner pushed out to 3600, the reverse of their
  original launch numbers (don't revert without checking). New
  `scripts/world/scannable.gd` (generic duck-typed component — reused again
  by the POI session below and by the later hex-module session).
  `scenes/player/scanner.gd` (`Scanner extends Node2D`) originally shipped
  as a fixed `ship.tscn` child, same as `TractorBeam` at the time — both
  were later turned into hex modules, see the most recent session. Verified
  live throughout, no errors.
- **Radar (Phase 2.1 broad-detection sweep display):** implements a
  user-supplied "Phase 2.1 Radar" spec. New `scenes/ui/radar_display.gd`
  (`extends Control`), child of the always-on HUD `CanvasLayer`, built
  procedurally in `_ready()`. Detection reuses existing groups —
  `"enemy_ship"` → SHIP, `"home_base"` → STATION, plus three categories
  (`"electronic_signal"`/`"enemy_camp"`/`"distress_beacon"`) that were wired
  from day one but had **no live instances until the POI session above**
  finally populated `"enemy_camp"`/`"distress_beacon"`; `"electronic_signal"`
  still has none. Broad-category-only by design — a contact is
  `{offset, category}`, no name/faction/health/identity. Reworked mid-session
  into a classic sweep-reveal model: contacts only become visible "blips"
  once the rotating sweep line crosses their bearing, then fade over time;
  blips are matched to contacts by category + proximity, not node identity.
  Range/position/category set were **all later changed by the Scanner
  session** — see that section above for current numbers, this entry is
  mostly useful for the sweep-reveal mechanic itself. Verified live
  (spawned a pirate, confirmed blip-on-sweep-pass, fade, and removal on
  death). One MCP-tooling detour (frozen-looking live value from an editor
  debugger "break" state) — see `docs/gotchas.md`.
- **Better AI navigation** (obstacle/ship avoidance, stuck recovery,
  combat-distance hysteresis, de-aggro leash): implements a user-supplied
  "1.4 Better AI navigation" spec, full design reference in
  `docs/aienemies.md`. New `scripts/ships/ai/ai_navigator.gd`
  (`AINavigator extends RefCounted`, one per `ShipAI`) blends seek-target
  with a 5-ray obstacle-avoidance fan and ship-separation, fixing three real
  oscillation bugs found via live testing (dead-ahead jitter, ships dodging
  their own pursuit target, reactive ping-pong through tight asteroid
  clusters — the last one was the actual reported symptom). Also added
  stuck detection/recovery (thrust-vs-displacement tracking, reverse-and-turn
  maneuver) and movement-distance hysteresis + a de-aggro leash in
  `ship_ai.gd`. Verified live across several real scenarios, no new errors.
  Still open: stuck-recovery threshold is a fixed constant not scaled to
  ship mass; constants are first-pass; not re-verified against the
  Dense/Dangerous Belt region; `pirate_light_two`/`pirate_heavy_one`
  severability audit remains untouched.
- **Basic world regions** (`scripts/world/region_type.gd` +
  `region_spawner.gd`, full reference in `docs/region_design.md`): data-driven
  `RegionType` resource (density/spacing/size-tier weights/tint) +
  `RegionSpawner` node, applied to `asteroid_field.tscn` (refactored from 14
  hand-placed asteroids) and 3 new zones in `map_tester.tscn` (Sparse Open
  Space, Small Asteroid Cluster, Dense/Dangerous Belt). Density values were
  tuned down once after user feedback ("way too many asteroids") — current
  numbers are the approved second pass, don't revert to first-guess values.
  Scope was explicitly narrowed from a full grid-addressed universe (the
  user's own framing) to this handcrafted-zone approach via `AskUserQuestion`
  — the grid idea is unstarted, not rejected, and is a materially bigger
  architecture change if picked up later. Verified live (determinism, counts,
  clearance around arrival points).
- **Asteroid size tiers, splitting, hit knockback**
  (`scenes/world/asteroid.gd`): 3 size tiers (LARGE/MEDIUM/SMALL) with
  splitting into next-tier fragments on death, 4 visual variants auto-picked
  from `random_seed`, deterministic RNG (same seed → same shape/split
  result), optional `drift_velocity`, and `take_damage_at()` knockback
  reusing the split-scatter mechanism. Asteroids remain `StaticBody2D` — no
  real physics collision response. Verified live. Committed together with
  the region/camera/nebula/wreck work below (one combined commit, user's
  explicit choice).
- **Camera zoom rework + starfield tiling/perf fixes**
  (`camera_shake.gd`/`starfield_layer.gd`): ship-size-driven zoom widened
  50%, scroll-wheel zoom added (zoom-out capped at the ship's own
  `_base_zoom`, zoom-in capped by a flat `scroll_max_zoom`). Starfield
  `field_size`/`star_count` retuned to fix pop-in on large-ship zoom-out
  without the earlier attempt's severe perf hit; still an accepted edge-case
  gap at the most extreme zoom-out on wide monitors. Small-screen star
  flicker addressed with a size-floor bump only (antialiasing was tried,
  reverted — caused a frame-rate regression); not confirmed with the user
  whether that alone fixed it. **This session's changes were not verified
  live in the editor** — flagged to the user at the time.
- **3 more abandoned-station wrecks + a second nebula**
  (`derelict_station.tscn`, `map_tester.tscn`): added pirate/ancient/
  corporate faction station wrecks (same mipmap-generate=false fix as the
  original faction art). Second nebula placed far from the first with its
  own teal tint — the particle cloud itself is still visually identical
  between the two (only tint differs), a known simplification. Verified live.
- **Frame stutter fix** (`tractor_beam.gd`/`warp_gate.gd`): diagnosed a
  reported ~0.5s (actually multi-second, up to ~8.4s) stutter to fresh
  `CanvasItemMaterial`/`ParticleProcessMaterial` allocation on every
  use forcing shader/pipeline recompiles — fixed by caching both as
  `static var`s. See `docs/gotchas.md` for the general lesson. Verified live
  (before/after spike-monitor instrumentation).
- **Version 0.6 (trading, station, warp gates, new locations, nebula)** — a
  large multi-part session, roadmap Version 0.6 now essentially complete:
  - Trading: new `int` Credits currency on `Inventory`, `trade_panel.gd`
    (bound to `T`), `sell_price`/`buy_price` per material (buy always >
    sell).
  - Station: `station.tscn` real visual (was a bare `Marker2D`), always-on
    `station_prompt.gd` prompt, and a real repair mechanic — passive regen
    caps at `passive_repair_cap_fraction` (0.4), paid `Ship.repair_fully()`
    tops everything to 100%.
  - Warp Gates (`warp_gate.gd`): `GATE` mode (instant scene change via a new
    `GameState` autoload carrying Credits/materials/tech/layout/health-
    fraction across scene changes — **per-module condition does not survive
    a warp**, only aggregate Health) and `SPEED_LANE` mode (in-scene dash,
    2.5s ramping camera-shake hold then a fixed-speed 1600px/s dash). Both
    modes are always built in pairs (retrofitted after an early one-way gate
    had no way back).
  - New Locations: `asteroid_field.tscn` (14 dense asteroids),
    `derelict_station.tscn` (darkened/tilted station + salvage, no
    trade/build panels).
  - Nebula (`nebula.gd`): drifting particle cloud + screen tint zone;
    `Ship.is_in_nebula()` (depth-counter) cuts target-lock range to 35%
    inside. Sizing went through a real correction (see `docs/gotchas.md`-
    adjacent lesson: particle *scale* shouldn't track field radius).
  - `RegionBoundary` (the old distance cap around home base) removed
    entirely per explicit request, since the nebula needed to sit outside it.
  - Real bugs found via live testing: a signal-handler arg-count mismatch in
    `trade_panel.gd`; the `GameState` autoload typing bug (now in
    `docs/gotchas.md`); a missing background image layer on 3 new scenes
    causing flat grey backgrounds.
  - Verified live end-to-end for all pieces above.
  - Still open: per-module condition doesn't survive a `GATE` warp
    (accepted); "abandoned wrecks" as a distinct non-station location isn't
    built (now partially addressed by the POI session's Abandoned Ship, but
    the original derelict_station "wrecks" are still station-shaped, not
    ship-shaped); a user-reported performance concern was investigated
    (`fps`/`process`/`node_count`) but inconclusive at the time (later
    resolved by the frame-stutter session above).
- **Reverse engineering, pirate_light_one's wing, debris/thruster fixes,
  Manufacturers** (Roadmap Version 0.5):
  - Reverse engineering: `ModuleType.requires_research` flags only Railgun
    and Phase Lance (not every capturable-tech module, chosen via
    `AskUserQuestion`); `Inventory.research()` spends one captured part to
    permanently unlock a module type; ship builder shows `[LOCKED]` +
    a live Research button.
  - Gave `pirate_light_one` a real severable wing (relocated an engine +
    added a single connecting Strut) — it previously had zero severable
    points by construction. `pirate_light_two`/`pirate_heavy_one` are
    **not** audited for the same issue.
  - Two real bugs fixed: severed-module debris always rendered with the
    generic fallback texture instead of actual faction/rotation-correct art;
    engine thruster particles kept showing on a destroyed engine regardless
    of that specific module's state.
  - Manufacturers (`scripts/economy/manufacturer.gd`/`manufacturer_catalog.gd`):
    stat-modifier profiles (Atlas Heavy Industries / Nova Precision / Black
    Market Foundry) keyed by `ModulePlacement.manufacturer_id`, deliberately
    orthogonal to faction — see "Decisions made" below. Black Market
    Foundry's malfunction-backfire is a real mechanic
    (`Ship.damage_own_module()`). Discovery (via capture) is tracked
    separately from research/unlock. Buying from a known manufacturer has no
    UI yet — waits on the trading system (built in the Version 0.6 session
    above). Verified live end-to-end.
  - Still open: no Corporate/Ancient enemy ship exists (explicitly deferred
    by the user); no faction-specific salvage; Atlas Heavy/Nova Precision
    have no in-game seed yet (only Black Market Foundry was placed on a real
    enemy).
- **Mipmap fix, capturable tech parts, disabled winch grapple**:
  - Fixed the same `mipmaps/generate=false` issue (see `docs/gotchas.md`)
    across all 61 newer faction-art assets.
  - New capturable-tech-parts system: a severed module that's flagged
    `is_capturable_tech`, survived severance with enough condition, and
    passes a capture-chance roll spawns a `CapturedTechPart` instead of
    cosmetic debris, added to a new `Inventory` bucket (research/unlock came
    later, see Manufacturers session above).
  - Built a full player-driven winch grapple (`hardpoint_winch.gd`/
    `winch_rope.gd` — verlet rope, real tether cap, grapple via
    `Ship.apply_impulse`) through several real bug fixes (miss auto-retract,
    frozen anchor, tether cap, dead tip point), then **disabled per explicit
    user request** ("good work in progress... let's disable the idea for
    now") — only the `ModuleCatalog` registration is commented out, every
    supporting file is left in place to pick back up later.
  - Restored `CapturedTechPart` pickup via the existing `TractorBeam` once
    the winch was disabled, so captured parts remain collectible.
  - Still open: winch balance untuned (irrelevant while disabled); no UI
    shows captured-tech counts yet.
- **Faction weapon art + recoil**:
  - Turret art now renders on the actual gun (`HardpointGun`'s `Turret`
    sprite, rotated/scaled to the `Muzzle` marker), replacing an earlier
    hull-overlay approach (still used only by the ship-builder preview).
  - Multi-hex weapon tiers (II/III) use one PNG per occupied hex
    (`<faction>_<name>_<q>_<r>.png`), not one stretched image — fixes a
    margin/stretching visual bug. `HexUtils.hex_uv_corners_for_rotation()`
    keeps per-cell art aligned when a multi-hex weapon rotates.
  - Fixed a real bug: `personality_user.tres` was missing `faction_id`
    entirely, silently falling back to `"pirate"` hex art.
  - Recoil wasn't actually broken — ship drag was cancelling it within one
    physics frame. `recoil_force` bumped 6x across all weapon tiers per
    explicit request. Noted: recoil is inherently inversely proportional to
    ship mass — intentional.
  - Ancient and Pirates given full weapon art (base + turret, all 3 tiers)
    to match Corporate — no code changes needed, `FactionArtImporter` is
    faction-agnostic.

## Where things stand

The vertical slice is well past the original milestone list: flight
movement, camera, asteroids, a bounded explorable region with a home base, a
working ship builder (save/load, build costs, energy stats), a named-
material economy (Steel Alloy / Electronics / Reactor Components), an energy
system (reactors/batteries, thrust and weapon energy costs), a 4-archetype
pirate AI (Raider/Gunship/Missile Boat/Scout) with an Idle→Suspicious→Alert
state machine, real per-module ship damage with wing detachment, data-driven
world regions, asteroid size tiers/splitting, better AI navigation, a
sweep-reveal radar paired with a long-range list scanner, four basic
points of interest (pirate camp, distress signal, abandoned wreck, scenic
formation), a single-target tractor beam, cargo storage capacity with a
placeable Storage module, and a toggleable Mining Grinder that damages
asteroids and breaks off collectible ore fragments. **Version 0.1–0.4 of
`Roadmap v.2-v.9.md` are done; Version 0.5 (reverse engineering +
Manufacturers) has real substance but Corporate/Ancient enemy ships are an
explicitly deferred gap; Version 0.6 (trading, station, warp gates, new
locations, nebula) is essentially complete.** Radar (2.1), Scanner (2.2) and
Points of Interest (2.3) are all implemented from a user-supplied "Phase 2"
spec that isn't part of either tracked roadmap file; Tractor Beam (3.1),
Storage capacity/module (3.2/3.3), and the Mining Grinder (4.1) are from a
separate, later user-supplied spec series (not either tracked roadmap file
either) — see the sessions above for their current shape; Radar/Scanner
numbers were revised multiple times in-session and are current, not
first-draft. **Tractor Beam, Radar, Scanner and the Mining Grinder are hex
modules** rather than fixed ship/HUD components — losing the hex disables
the capability, and the starter ship carries one of each so default play is
unaffected. **Cargo capacity is likewise a hex module** (Storage Container)
but stacks additively on top of a baseline rather than gating a capability
on/off — losing it just shrinks the cargo hold, it doesn't zero it out. The
**Mining Grinder is the only hardpoint so far that's both a spawned world
node (like Tractor Beam) and a 2-cell footprint (like Railgun)**, and the
only one that's player-toggled (**G**) rather than always-on.

### Ship building (done, wired into the flyable ship)
- Hex-grid (axial coordinates) layout data model under `scripts/ships/...`:
  `module_type.gd`, `module_placement.gd`, `module_catalog.gd` (still a
  static prototype catalog, documented as a stand-in for real `.tres`
  resources), `ship_layout.gd` (place/remove/rotate, BFS connectivity,
  `validate_layout()`/`find_unreachable_from_core()`), `hex_utils.gd`,
  `ship_layout_renderer.gd`.
- `scenes/ui/ship_builder/` (`hex_grid_control.gd` + `ship_builder_panel.gd`):
  two-column layout, **R** rotates, **X** deletes. Any visible
  `"menu_panel"`-grouped CanvasLayer suspends `ship_input.gd` polling.
- Per-module build costs (`ModuleType.build_costs`) checked against
  `Inventory`. Saving/loading custom ships to disk works.

### Economy / energy / cargo
- `scripts/economy/materials.gd` + `scenes/player/inventory.gd`
  (Dictionary-based multi-material pool).
- Energy: `ModuleType.energy_generation`/`energy_capacity_contribution`,
  `Ship.current_energy`/`max_energy`/`energy_generation_rate`. Thrust,
  weapon fire, and tractor beam all draw from the same pool. **AI ships use
  the exact same energy system as the player.**
- Numpad 5 (`debug_add_resources`) adds 1000 of each material — dev-only.
  Bypasses cargo capacity on purpose (see Cargo capacity below).
- **Cargo capacity** (Phase 3.2/3.3): `Inventory.get_cargo_capacity()`/
  `get_cargo_used()` (sum of `_material_totals`), recomputed by
  `Ship._apply_layout_cargo_capacity()` from `base_cargo_capacity` (100) +
  `ShipLayout.total_cargo_capacity()` (sum of `ModuleType.
  cargo_capacity_contribution`, no distance-from-core falloff unlike
  energy). New **Storage Container** module (`storage_mk1`, +60 capacity, a
  plain stat contributor like Reactor/Battery, not a hardpoint category).
  Two collection paths: `Inventory.add_material()` stays uncapped (ship-
  builder refunds, the debug cheat above, `GameState` restore all rely on it
  never failing); `Inventory.try_add_material()` is the only capacity-
  checked path, used exclusively by `Salvage` pickup, emitting `storage_full`
  on rejection. Dedicated Cargo screen (`cargo_panel.gd`/`.tscn`, **C** key,
  not home-base-gated) shows per-material totals with Discard 10/Discard
  All buttons; HUD shows a live `Cargo: used/capacity` readout plus a
  transient "STORAGE FULL" flash. Ship builder blocks removing a Storage
  module if current cargo would exceed the reduced capacity.

### Mining (Phase 4.1 Basic grinder)
- `scenes/player/hardpoint_grinder.gd`/`.tscn`: a 2-cell hex module
  (`hardpoint_category="grinder"`, `ModuleCatalog.LINE_2_CELLS`), **player-
  toggled** via `Ship.toggle_grinder()`/`is_grinder_active()` (**G** —
  `ship_input.gd`), unlike every other passive hardpoint. While toggled on
  and an `Asteroid` is within `contact_range` (55, from the asteroid's own
  surface) of the front cell's Muzzle: drains `energy_cost_per_second` (7)
  from the shared pool, applies `damage_per_second` (14) via plain
  `Asteroid.take_damage()` (not `take_damage_at()` — no knockback while
  held), and breaks off one `Salvage` ore fragment every `fragment_interval`
  (1.0s), same rarity odds as a normal kill-drop
  (`Asteroid.roll_ore_rarity()`, made public for this). Fragments are
  ordinary `Salvage` nodes — the Tractor Beam, self-collection, and cargo
  capacity all apply with zero extra code. Weapons aren't nerfed; the
  grinder's edge is continuous partial yield vs. a gun's kill-only drop.
  Starter ship carries one grinder at hex `(2,1)`/`rotation_steps=1`.

### Salvage collection (Phase 3.1 Tractor Beam, Phase 3.2 capacity, Phase 4.1 mining)
- `scenes/player/hardpoint_tractor_beam.gd`/`.tscn`: a hex module
  (`hardpoint_category="tractor"`), always active while mounted and intact,
  no player input. Locks onto the single nearest valid target (`Salvage` or
  `CapturedTechPart`, groups `"salvage"`/`"capturable_tech"`) within
  `max_range` (250) with a clear physics-raycast line of sight, pulls it in,
  drops it safely if blocked/out of range/out of energy — **one target at a
  time by design**, framed as a future upgrade path (more simultaneous
  targets), not built. Costs energy/sec from the ship's shared pool while
  actively pulling.
- Salvage still self-collects via its own `Area2D.body_entered` once it
  physically touches the ship (`scenes/world/salvage.gd`). Pickup now goes
  through `try_add_material` (Storage session): a full cargo hold rejects
  the item instead of consuming it — the Salvage node stays alive,
  overlapping the ship, and retries every frame (`_pending_pickup_body`)
  until capacity frees up or the ship drifts away. Nothing is ever silently
  deleted on rejection.

### Combat
- `hardpoint_gun.gd`/`hardpoint_missile_launcher.gd` + `missile.gd`:
  tier-scaled stats, torpedo-style missile flight homing off a live target
  reference.
- `scenes/enemies/ship_ai.gd`: one AI script for every archetype, driven by
  a `ShipPersonality` resource, `IDLE → SUSPICIOUS → ALERT` state machine.
  AI aim is deliberately imprecise (`_jittered_aim_point()`, re-rolled every
  0.35s) — see "Decisions made" for why. `Ship._finish_destruction()` drops
  `Salvage` on death for any ship with `drops_salvage` true (the default) —
  this is what makes killing Pirate Camp members automatically rewarding,
  no extra code needed.
- `ai_navigator.gd`: obstacle/ship avoidance, stuck recovery, hysteresis —
  see AI navigation session above / `docs/aienemies.md`.

### Per-module ship damage + wing detachment (Version 0.4)
A hit resolves to a specific hex module (world impact point → hex coordinate
via `HexUtils.pixel_to_axial`) and can destroy/sever it independently of the
ship's overall `Health` pool.
- `Ship._module_conditions` is runtime-only state on the `Ship` node, never
  on the shared `ShipLayout` resource.
- Splash damage (`module_splash_fraction` = 0.35) hits neighbors too — the
  Command Core is exempt (only dies from a direct hit).
- `ShipLayout.find_unreachable_from_core()` (BFS) drives severance;
  `Ship._detach_module()` disconnects a wing (loses stats/collision, spawns
  cosmetic `ShipDebris`). A destroyed-but-attached module also frees its
  collision shape (no longer blocks shots to what's behind it).
- Core destruction = instant ship death (no anchor to measure connectivity
  otherwise). `_check_all_modules_gone()` catches the case where splash
  damage guts every module before `Health` itself reaches zero.
- New single-cell "Strut" module: cheap, fragile, connective tissue for
  wings. Current module health balance: Core 140, Hull 50, Heavy Hull 240,
  Strut 25 — reached via live pirate-vs-test-ship combat, not pure math (see
  "Decisions made" for the methodology if re-tuning).

### Information & discovery (Phase 2, ad-hoc spec — not in either roadmap)
- **Radar** (`scenes/ui/radar_display.gd`): live sweep-reveal, bottom-right,
  1800-unit range, "Range: N" label under the circle. Categories: Ship,
  Station, Electronic Signal, Enemy Camp, Distress Beacon — **Enemy Camp and
  Distress Beacon now have live instances** (see Points of Interest below);
  Electronic Signal still has none. Never shows anything Scanner identifies.
  **Requires a Radar hardpoint** (green hex, `hardpoint_category="radar"`,
  see most recent session) — `Ship.has_radar()` gates the whole display,
  checked live every frame so losing/repairing the module shows/hides the
  HUD immediately.
- **Scanner** (`scenes/player/scanner.gd` + `scenes/ui/scanner_display.gd`):
  deliberate long-range pulse (V key), top-right UI, 3600-unit range,
  closest-5 results. Identifies Planet/Wreck/Ancient Formation individually
  (`scripts/world/scannable.gd`) and asteroids as count-named clusters
  ("Asteroid Cluster (6)"). Deliberately excludes the home station and
  anything radar-only (signals/camps/beacons) — "off the grid" objects only.
  **Requires a Scanner hardpoint** (magenta hex, `hardpoint_category=
  "scanner"`, see most recent session) — `toggle_scan()` refuses to start
  without one, and an in-progress channel self-cancels if the module is
  lost mid-scan.
- **Points of Interest** (Phase 2.3, `map_tester.tscn`): four hand-placed
  destinations built entirely from existing systems. `scripts/world/poi_camp.gd`
  (Small Pirate Camp, radar `enemy_camp`), `scripts/world/distress_signal.gd`
  + `scenes/world/distress_signal.tscn` (radar `distress_beacon`),
  `scenes/world/abandoned_ship.tscn` (Scanner "Wreck"),
  `scenes/world/scenic_formation.tscn` (Scanner "Ancient Formation",
  discovery-only, no reward). Each has a real completion/exhausted state
  (camp clears from radar once cleared; beacon clears once its salvage is
  collected; wrecks don't respawn rewards).

### World
- `starfield_layer.gd` + `ParallaxBackground` layers, bloom via one
  `WorldEnvironment` node.
- One planet (`scenes/world/planet.tscn`), visual-only, no data/catalog
  system (scannable, see above).

## Decisions made (and why — don't relitigate without reason)

- **Ship-centric, not player-centric architecture** — AI and player ships
  share the same `Ship`/`ship_ai.gd`/`ship_input.gd` split.
- **Hex grid with axial coordinates (`Vector2i`)**, not a square grid.
- **Static `ModuleCatalog` is a deliberate, documented prototype shortcut.**
- **Never silently no-op** — every rejected ship-builder action surfaces a
  specific reason string.
- **Exactly one Command Core** enforced as a current layout rule.
- **Menu-open input suspension is group-based** (`"menu_panel"` group).
- **Missile behavior is a one-shot torpedo phase sequence**, not a repeating
  burst/coast cycle (explicitly tried and rejected).
- **Planets are visual-only for now** — no catalog/orbit system until asked.
- **Per-module combat state lives only on `Ship`, never `ShipLayout`** — the
  load-bearing reason the damage system is safe on shared enemy-scene
  resources.
- **The Core is a deliberate special case**: toughest single module, exempt
  from splash damage, destroying it ends the ship immediately.
- **AI aim is intentionally imprecise** — added because AI previously aimed
  at the exact ship origin (= the Core's location by convention), making the
  Core a guaranteed bullseye the instant front armor broke. Player accuracy
  is untouched.
- **Splash damage exists specifically to make focused-fire severing
  achievable** against a moving target — side effect: modules clustered near
  each other take more effective cumulative damage than an isolated one,
  which is why the Core had to be splash-exempt.
- **Module health/splash/Core numbers were reached via live combat testing**
  (a real long test ship fought by a real spawned pirate), not math — if
  re-tuning, repeat that methodology rather than guessing from stat sheets.
- **Manufacturers are deliberately separate from Factions.** A `Manufacturer`
  is a stat-modifier profile ("what engineering philosophy built this part")
  independent of faction ("whose territory/art is this") — lives on
  `ModulePlacement.manufacturer_id`, not `ModuleType`/`ShipPersonality`, so
  the same module type can exist with or without one. Discovering a
  manufacturer (via capture) and researching a locked module type are two
  separate gates on purpose.
- **Radar and Scanner are strictly non-overlapping by design.** Radar =
  live faction/activity detection (ships, stations, signals), broad category
  only, never identity. Scanner = deliberate, longer-range identification of
  "off the grid" objects (asteroids, wrecks, planets — never active
  infrastructure, never anything radar already covers). This was corrected
  back into place twice in the Scanner session after both boundaries got
  blurred mid-iteration — treat it as a hard rule, not a preference. The
  Points of Interest session kept every new POI strictly on one side of this
  line (camp/distress = radar-only, wreck/formation = scanner-only, never
  both).
- **Scanner reports asteroids as count-named clusters, never individual
  rock identity** — "Asteroid Cluster (6)" style naming, proximity-grouped.
  Explicitly replaced an earlier Common/Dense/Rare composition-based design
  per user request.
- **Points of Interest reuse existing systems rather than a new framework.**
  No `PointOfInterest` resource/spawner was built — each POI is a small,
  configurable scene (same pattern nebulae/gates already use), and reward/
  combat mechanics (salvage-on-death, idle-until-provoked AI) already
  existed and needed zero new code. Only add a generation framework if a
  much larger number of POIs is requested later.
- **"Wrecks" and "Abandoned ships" are treated as one implemented type**, and
  "Simple derelict structures" wasn't built as a distinct fifth type — all
  three spec bullets describe the same physical shape/mechanic (a scannable
  hulk with finite salvage); building them separately would have been pure
  duplication.
- **Tractor Beam, Radar and Scanner are hex modules, not fixed ship/HUD
  components.** Two flavors of the same idea: Tractor Beam is a spawned
  hardpoint node (needs a muzzle position/beam visual, like weapons/winch),
  while Radar and Scanner are a "pure capability flag" — `Ship.has_radar()`/
  `has_scanner()` just check the layout for an intact hardpoint of that
  category, no spawned world node at all, since neither has a fixed facing
  or world-space visual of its own. Apply the same flag pattern to any
  future module that's really a sensor/HUD gate rather than a physical
  object on the hull.
- **Tractor Beam pulls exactly one target at a time**, not everything in
  range at once — an explicit, repeated user correction (built multi-target
  first, twice) framed as "upgradable later." Don't silently expand this
  without a fresh request.
- **New hardpoint module colors must be visually distinct from existing
  ones** — Radar's first color was too close to Engine/Tractor Beam's blues
  and had to be corrected. Check the existing palette in
  `ModuleCatalog.get_all()` before picking a color for a new module type.
- **Two separate material-add paths on `Inventory` by design:
  `add_material()` uncapped, `try_add_material()` capacity-checked.**
  Refunds (ship-builder removal), the debug resource cheat, and `GameState`
  restore all call `add_material()` and must never fail — capacity is only
  ever enforced on the one path real gameplay collection (Salvage pickup)
  goes through. This means cargo *can* end up over capacity through those
  other paths (allowed — nothing is ever deleted to force it back under),
  it just blocks further real collection until it's back under again.
- **A full cargo hold rejects Salvage pickup instead of destroying the
  item** — the Salvage node stays alive in the world and retries every
  frame it's still overlapping the ship until space frees up or it drifts
  away. Never silently drop salvage on the floor of a full hold.
- **Storage capacity is a plain stat contributor (like Reactor/Battery),
  not a hardpoint category like Tractor/Radar/Scanner.** It has no
  facing/muzzle/HUD gate of its own to need the "pure capability flag"
  treatment — it just raises a number `try_add_material()` checks. Don't
  give it a `hardpoint_category` or a `has_storage()`-style gate unless a
  future spec actually needs one.
- **The Mining Grinder is player-toggled (G), not always-on like the
  Tractor Beam.** Deliberate: it deals continuous damage, so it needs
  explicit activation the way a passive pull-in tool doesn't. Uses a
  pull-model flag (`Ship.is_grinder_active()`, checked every frame by each
  mounted grinder) rather than a pushed command, matching
  `is_module_destroyed`'s existing convention — don't push a one-shot state
  change to hardpoints, let them poll Ship each frame.
- **The grinder damages asteroids via `take_damage()`, not `take_damage_at()`,
  on purpose.** `take_damage_at()`'s knockback/scatter-velocity mechanic was
  built for one-off weapon hits; applying it every frame during a *held*
  grind would fight the asteroid drifting away out of contact range. Any
  future continuous-damage-over-time module should default to plain
  `take_damage()` for the same reason — only a discrete hit should knock
  something back.
- **Weapons were deliberately not nerfed to make the Grinder the better
  mining tool.** A gun only yields material on an asteroid's final kill; the
  Grinder yields fragments continuously while the asteroid is still alive,
  which is strictly more resource-efficient per second without touching any
  weapon stat. If a future request wants weapons *actively* worse at mining
  (not just less efficient), that's a fresh, separate decision — don't
  assume it's implied by this one.
- **The ship builder's rotation-arrow indicator intentionally does NOT
  track the real hex-neighbor direction.** It uses `60° * rotation_steps -
  90°` so an unrotated module always visually points "up," even though the
  actual 6 hex-neighbor directions never include exactly "up" (only
  0/60/120/180/240/300°). This was found and briefly "fixed" (arrow made
  hex-accurate) during the Mining Grinder investigation below, then
  **explicitly reverted by the user** in favor of keeping the simpler
  "points up by default" UX. For a multi-hex module, the module's own
  second hex tile is the real ground truth for its front direction, not
  this arrow — see the comment at `hex_grid_control.gd`'s arrow formula and
  the matching `docs/gotchas.md` entry before touching this again.

## Not yet started (no explicit user request yet — don't start without one)

- **Corporate or Ancient enemy ships.** Explicitly deferred by the user
  ("we can do the enemy ships later") — every enemy in `scenes/enemies/` is
  currently a Pirate variant or the generic missile cruiser, so faction
  identity never actually shows up in combat for the other two factions.
- Faction-specific/unique salvage — materials are fully generic across all
  three factions.
- Buying from a known manufacturer once discovered — the trading system
  exists now (Version 0.6) but nothing wires manufacturer purchase into it.
- Severability audit for `pirate_light_two`/`pirate_heavy_one` — only
  `pirate_light_one` was fixed for the "zero severable points" blob issue.
- Reactor/Battery/other non-engine/weapon modules have no mechanical effect
  beyond losing the hex when destroyed (no repair mechanic either).
- Player weapon accuracy/spread — untouched on purpose.
- More module types / a real data-driven (non-static) module catalog as
  `.tres` resources.
- A planet catalog, multiple planet instances, orbit/parallax motion, or any
  planet-surface gameplay.
- A wreck field that isn't station-shaped (destroyed ships, not stations) —
  partially addressed by the new Abandoned Ship POI, but `derelict_station.tscn`
  itself is still 4 station wrecks in one scene, not ship-shaped wrecks.
- The grid-of-squares universe idea the user floated during the world-
  regions session — unstarted, not rejected; a materially bigger
  architecture change than the regions work actually done.
- The "player writes their own guess" scanner memory/journal design —
  explicitly deferred during the Scanner session's pivot, not rejected;
  bigger scope than the count-based-cluster version actually built.
- Resource deposits and unknown structures as real spawned content — Scanner
  supports the categories, nothing in the game joins those groups yet.
- Electronic Signal as a live radar category — still no in-game instance
  (Enemy Camp and Distress Beacon now have instances via the POI session,
  Electronic Signal doesn't).
- A reusable POI generation/configuration framework (resource + spawner, in
  the `RegionType`/`RegionSpawner` sense) — the 4 current POIs are hand-placed
  scene instances; only worth building if many more POIs are requested.
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (research beyond reverse-engineering, co-op).
- Dedicated art for the Tractor Beam, Radar, and Scanner hexes — all three
  are still generic flat-tinted hexes (distinct colors, no sprite).
- Tractor Beam's multi-target upgrade — explicitly framed as "for later"
  when the single-target limit was imposed, nothing designed yet for what
  unlocks it (a second hardpoint? a per-hardpoint upgrade tier?).
- Dedicated art for the Storage Container hex — generic flat-tinted hex like
  the other undecorated hardpoints.
- Arbitrary-amount cargo discard (currently fixed 10 or all) — no numeric
  input field on the Cargo screen.
- Capacity/cargo effects for captured tech parts — that bucket stays
  separate and uncapped by design, not extended by the Storage session.
- Dedicated art for the Mining Grinder hex — generic flat-tinted hex.
- Mining Grinder audio feedback — explicitly deferred by the 4.1 spec
  itself ("audio will come later").
- Mining Grinder upgrade path ("one generic mining speed (upgradable?)") —
  only the flat generic speed was built, no upgrade tier/tree exists.
- Grinder damage/effectiveness against ships — the spec explicitly scoped
  this to asteroids only ("maybe ships later").

## Suggested next step

No specific next item has been chosen yet. Candidates on the table, most
relevant first:
- Playtest the Mining Grinder for real feel — `contact_range` (55),
  `damage_per_second` (14), `energy_cost_per_second` (7), and
  `fragment_interval` (1.0s) are all first-pass numbers only checked via
  scripted MCP testing (spawned asteroid, toggled grinder, watched
  Health/cargo), not flown by a human. Also worth deciding whether "one
  generic mining speed (upgradable?)" should get an actual upgrade tier now
  that the base tool exists.
- A real playtest pass on Radar (1800) / Scanner (3600) range and Scanner's
  1.5s channel/5-result-cap feel, now that both have been corrected several
  times by feel rather than tuned in one deliberate pass.
- Playtest the Tractor Beam's single-target pull speed/range/energy cost
  for real feel, now that it's mounted on a hex rather than always-on —
  same "corrected by feel, not one deliberate pass" caveat as Radar/Scanner.
- A pass through the Dense/Dangerous Belt region specifically with the
  current AI navigation (tightest asteroid packing, not yet re-checked).
- Audit `pirate_light_two`/`pirate_heavy_one` for the same severability
  issue `pirate_light_one` had.
- Pick up the deferred Version 0.5 gap: no Corporate/Ancient enemy ship
  exists yet.
- Have the user actually playtest current combat end-to-end for the first
  time since per-module damage/wing severance/research gating/Manufacturers
  all landed together.
- Decide whether "abandoned wrecks" should be a distinct non-station
  location (currently same as derelict stations, aside from the new
  Abandoned Ship POI).
- Populate the still-unused Electronic Signal radar category, and/or
  resource deposits/unknown structures on the Scanner side.
- Playtest the 4 new Points of Interest for real (camp difficulty, distress
  signal/wreck reward sizing, whether the reused hull/cockpit art actually
  reads well at normal play zoom, not just the screenshot pass done this
  session).
- Playtest cargo capacity/Storage module for real feel — 160 starting
  capacity, 60/module, 100 base were first-pass numbers, not tuned against
  actual play (how fast salvage fills a hold on a real run, whether hitting
  "STORAGE FULL" happens often enough to matter). Also exercise the ship
  builder's Storage removal-block and Cargo/used stats readout through the
  actual UI — verified by code review this session, not clicked through.

Do not start any of these without the user confirming which first.

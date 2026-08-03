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

## Most recent session (Points of Interest — Phase 2.3)

Implements a user-supplied "Phase 2 — Information and Discovery / 2.3 Basic
points of interest" spec (not part of `roadmap.md`/`Roadmap v.2-v.9.md`, same
ad-hoc spec family as Radar/Scanner above). Deliberately built to use only
existing systems — no new architecture framework.

- **Four distinct POI types shipped** (spec required 3): **Small Pirate
  Camp** (combat + salvage), **Distress Signal** (salvage), **Abandoned
  Ship/Wreck** (salvage), **Scenic Formation** (discovery only, no reward).
  The spec's "Wrecks" and "Abandoned ships" bullets were deliberately merged
  into one type (same physical shape/mechanic — building both would have
  been pure duplication), and "Simple derelict structures" wasn't built as a
  fifth, separate type for the same reason. Confirmed via `AskUserQuestion`
  before building: no standalone "derelict ship" art exists in the project
  (only individual hex-module textures and the large station textures
  `derelict_station.tscn` already reuses), so all new wreck-like visuals
  reuse existing hull/cockpit module PNGs (tinted, scaled up) rather than
  needing new art — same reuse technique the derelict station wrecks already
  established.
- **New `scripts/world/poi_camp.gd`** (`PoiCamp extends Node2D`): marks
  itself into radar's existing `"enemy_camp"` group (radar_display.gd
  required **zero changes** — that category and `"distress_beacon"` were
  wired but unused since the Radar session). Combat and reward needed no new
  code at all: pirate ships already default to `State.IDLE` and only
  escalate once the player is close/hostile (`ship_ai.gd`), and
  `Ship._finish_destruction()` already drops `Salvage` on death. The script's
  only job is tracking its ship children via `tree_exiting` and calling
  `remove_from_group("enemy_camp")` once all are dead — this is the
  "exhausted state, radar contact clears" requirement.
- **New `scripts/world/distress_signal.gd`** + `scenes/world/distress_signal.tscn`:
  joins `"distress_beacon"` (radar-only, deliberately **not** in the
  `"scannable"` group — a live signal is Radar's domain, not Scanner's "off
  the grid" domain, preserving the hard Radar/Scanner boundary rule from the
  Scanner session). Holds child `Salvage` nodes; a hand-drawn pulsing beacon
  light (`_draw()`, no new particle/texture asset) stops once every child
  Salvage is collected, and the node leaves `"distress_beacon"` at the same
  moment — resolved distress calls go quiet instead of pinging forever.
- **New `scenes/world/abandoned_ship.tscn`**: `scannable.gd` component,
  `scan_category = "Wreck"` (same category the derelict-station wrecks use —
  intentional, it's the same kind of object, just a single standalone hulk
  instead of a whole dead station). Two child `Salvage` nodes, no respawn.
- **New `scenes/world/scenic_formation.tscn`**: `scannable.gd`,
  `scan_category = "Ancient Formation"`. Ancient faction's command-core
  texture (tinted teal, scaled up) plus two decorative asteroid instances for
  a "formation" read. Discovery-only — no Salvage children, satisfies the
  spec's "provide combat, salvage, **or** discovery" via discovery alone.
- **Placement**: all four hand-placed directly in `map_tester.tscn` at fresh
  coordinates 1800–3600 units from home base (Pirate Camp (2600,-1800),
  Distress Signal (1800,1800), Abandoned Ship (3200,1200), Scenic Formation
  (-1800,-1900)) — reachable by direct flight, no new warp gates needed.
  Not a data-driven spawner (unlike `RegionSpawner`) — four hand-placed
  instances didn't justify a generation framework, same call already made for
  nebulae/gates elsewhere in this map.
- **Verified live** via godot-ai MCP: clean launch, no new errors/warnings.
  Confirmed group membership for all four (`enemy_camp`, `distress_beacon`,
  `scannable`×2) via `game_eval`; killed both camp pirates via direct damage
  and confirmed salvage dropped + camp left `"enemy_camp"`; collected both
  distress-signal salvage pieces via a direct `_on_body_entered` call and
  confirmed the beacon left `"distress_beacon"`; ran real `Scanner` pulses
  against the wreck and the formation and got back `"Wreck"` /
  `"Ancient Formation"` at the correct distances. One self-inflicted debugger
  break mid-session from a bad `game_eval` script (out-of-bounds array index)
  — recovered via `project_manage(op="stop")` + relaunch, not a real bug (see
  `docs/gotchas.md` if this recurs: a `game_eval` runtime error parks the
  game in a debugger break that does not resume on its own).

### Still open from this session
- POI placement is hand-picked, not reusable generation/configuration in the
  `RegionType`/`RegionSpawner` sense — acceptable for 4 instances, would need
  revisiting if many more POIs are added later.
- Pirate Camp uses a fixed roster of exactly 2 pre-existing pirate scenes
  (`pirate_light_one`, `pirate_med_one`), not a configurable count/mix.
- Resource deposits and "unknown structures" (from the original Scanner 2.2
  spec list) still have no live instances — unrelated to this session, just
  still an open gap from before.
- Visual scale for the reused hull/cockpit module textures was tuned by eye
  from one screenshot pass, not a deliberate art pass.

## Session before that (Scanner — Phase 2.2, plus a radar rework)

Implements a user-supplied "Phase 2 — Information and Discovery / 2.2
Scanner" spec (not part of `roadmap.md`/`Roadmap v.2-v.9.md`, same as the
Radar session before it). Went through several real design pivots based on
live user feedback within the session — the sequence matters for
understanding *why* the current shape looks the way it does, not just what
it is.

- **Iteration 1 (built, then substantially reworked):** a single-target
  channel scan — press scan, nearest not-yet-identified object in range,
  a few seconds to complete, then identified permanently. Asteroids rolled
  a placeholder "Common"/"Dense"/"Rare" composition category.
- **Pivot to long-range list scan** (explicit user choice via
  `AskUserQuestion`, over an alternative "player writes their own guess into
  a memory/journal" design that was **explicitly deferred, not built** —
  worth remembering if revisited later): one press → short channel (1.5s)
  → reports the closest 5 objects + distance in one shot, not a
  continuously-updating display. This is the current shape.
- **Asteroid naming pivot:** "Common/Dense/Rare" was dropped entirely per
  explicit user request — asteroids are now reported as **count-based
  clusters** ("Asteroid" for a lone rock, "Asteroid Cluster (6)" otherwise),
  proximity-grouped (300-unit single-link chaining) so a dense field doesn't
  fill every result slot with the same handful of nearby rocks. Asteroid.gd
  no longer carries any individual scan-identity state at all.
- **Scope correction:** briefly added the home station as scannable
  ("Station"), then **reverted on explicit instruction** — Scanner is
  deliberately "off the grid" objects only (derelicts/natural phenomena),
  never active/living infrastructure. `station.tscn` is back to a bare
  Sprite2D with no script.
- **Radar/Scanner boundary correction:** also briefly added asteroid-cluster
  blips to RadarDisplay (reusing the same clustering idea, sized by count
  instead of text), then **fully reverted on explicit instruction** — radar
  must never show anything Scanner identifies. RadarDisplay is back to
  exactly its prior 5 categories (Ship/Station/ElectronicSignal/EnemyCamp/
  DistressBeacon), no asteroid awareness at all.
- **Range tuning, done live by feel via direct user correction** (not
  math): Scanner range went 1200 → 3600 (off-screen asteroids were going
  undetected). Radar range, which had been bumped to 6000 mid-session for
  the (since-reverted) cluster feature, was explicitly pulled back down to
  1800 — **radar is now the short-range one, Scanner is the long-range one**,
  the reverse of how they first shipped in the Radar session. Don't "fix"
  this back without checking — it was a deliberate, repeated correction.
- **Final layout:** RadarDisplay bottom-right (its original spot), now with
  a persistent "Range: 1800" text label under the circle (new, not
  reverted) making the outer ring's meaning explicit. ScannerDisplay
  (progress bar + result list) top-right — was briefly swapped with radar's
  position mid-session, corrected back on explicit instruction. The two
  never overlap.
- **New `scripts/world/scannable.gd`**: generic duck-typed component
  (`scan_category`, `is_identified`, `mark_identified()`, `identified`
  signal) for objects with no script of their own — attached to
  `planet.tscn` ("Planet") and all 4 derelict-station wreck sprites
  ("Wreck"). Asteroid implements the same surface's spirit directly instead
  (a node can only have one script) but no longer needs individual
  identity — see naming pivot above. **Reused again in the POI session
  above** for the new Abandoned Ship and Scenic Formation POIs.
- **New `scenes/player/scanner.gd`** (`Scanner extends Node2D`), a child of
  `ship.tscn` like `TractorBeam`. Gathers two kinds of result per pulse:
  individual `"scannable"` group members (Planet/Wreck, tracked
  identified/already-known across pulses) and separately-clustered
  `"asteroid"` group members (always fresh, no persistent identity).
  `toggle_scan()` doubles as start/cancel; `Ship.toggle_scan()`/
  `get_scanner()` expose it. New `"scan"` input action, bound to **V**.
- **Verified live repeatedly** via the godot-ai MCP tools across every
  pivot above: clean launches throughout, `game_eval` used to directly
  inspect Scanner/Radar internal state (cluster counts, blip categories,
  result contents) rather than just trusting the code, plus one real
  screenshot confirming final UI placement. No errors introduced at any
  point — only the same pre-existing warnings from before this session
  (case-mismatch scene path, integer-division in `hex_utils.gd`/
  `hex_grid_control.gd`, a `scale`-shadows-`Control.scale` warning in
  `radar_display.gd` that predates this session's edits).

### Still open from this session
- Range values (Scanner 3600, radar 1800) were corrected live by direct user
  feedback through several rounds, not a systematic playtest pass — treat as
  "current, deliberately chosen" rather than "final."
- Scanner's result list is text-only (category — distance), no icon/color
  coding per category the way radar blips have shape/color.
- The deferred "player writes their own guess" memory/journal design
  (option 1 from the original pivot) is unstarted, not rejected — flagged
  as a separate, bigger feature if picked up later.

## Earlier sessions (compressed)

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

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
sweep-reveal radar paired with a long-range list scanner, and four basic
points of interest (pirate camp, distress signal, abandoned wreck, scenic
formation). **Version 0.1–0.4 of `Roadmap v.2-v.9.md` are done; Version 0.5
(reverse engineering + Manufacturers) has real substance but Corporate/
Ancient enemy ships are an explicitly deferred gap; Version 0.6 (trading,
station, warp gates, new locations, nebula) is essentially complete.** Radar
(2.1), Scanner (2.2) and Points of Interest (2.3) are all implemented from a
user-supplied "Phase 2" spec that isn't part of either tracked roadmap file —
see the sessions above for their current shape; Radar/Scanner numbers were
revised multiple times in-session and are current, not first-draft.

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

### Economy / energy
- `scripts/economy/materials.gd` + `scenes/player/inventory.gd`
  (Dictionary-based multi-material pool).
- Energy: `ModuleType.energy_generation`/`energy_capacity_contribution`,
  `Ship.current_energy`/`max_energy`/`energy_generation_rate`. Thrust,
  weapon fire, and tractor beam all draw from the same pool. **AI ships use
  the exact same energy system as the player.**
- Numpad 5 (`debug_add_resources`) adds 1000 of each material — dev-only.

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
- **Scanner** (`scenes/player/scanner.gd` + `scenes/ui/scanner_display.gd`):
  deliberate long-range pulse (V key), top-right UI, 3600-unit range,
  closest-5 results. Identifies Planet/Wreck/Ancient Formation individually
  (`scripts/world/scannable.gd`) and asteroids as count-named clusters
  ("Asteroid Cluster (6)"). Deliberately excludes the home station and
  anything radar-only (signals/camps/beacons) — "off the grid" objects only.
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

## Suggested next step

No specific next item has been chosen yet. Candidates on the table, most
relevant first:
- A real playtest pass on Radar (1800) / Scanner (3600) range and Scanner's
  1.5s channel/5-result-cap feel, now that both have been corrected several
  times by feel rather than tuned in one deliberate pass.
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

Do not start any of these without the user confirming which first.

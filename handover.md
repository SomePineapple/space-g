# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up.

**Read "Most recent session" first** — it's the freshest context and covers
work done after the rest of this file was last updated: ship-size-aware
camera zoom widened + scroll wheel zoom, and a starfield tiling/perf/aliasing
pass. The sections below it (3 more abandoned-station wrecks + a second
nebula, frame-stutter fix, Version 0.6 trading/station/warp-gates/new-
locations/nebula, reverse engineering/Manufacturers, mipmap fix/capturable
tech/winch, faction weapon art/recoil, ship building, combat, per-module
damage) are still accurate but predate this work.

## Most recent session (camera zoom rework + starfield tiling/perf fixes)

Two related pieces of polish, both in `scenes/player/camera_shake.gd` and
`scenes/world/starfield_layer.gd` (+ the 4 region scenes that use it:
`map_tester`, `frontier_system`, `asteroid_field`, `derelict_station`). No
MCP verification this session — changes are untested in the running editor,
flagged to the user each time.

- **Camera zoom widened + scroll wheel added** (`camera_shake.gd`). The
  existing ship-size-driven zoom (`min_zoom`/`max_zoom`, computed from
  `Ship.get_layout_extent()`) was widened 50% (both divided by 1.5) since it
  wasn't zooming out far enough for big ships. Added `MOUSE_BUTTON_WHEEL_UP/
  DOWN` handling in `_unhandled_input` that adjusts a `_manual_zoom_offset`
  on top of the ship-size `_base_zoom`. **Went through two clamp-direction
  iterations before landing on the right one** — first capped zoom-in at a
  flat `scroll_max_zoom` and let zoom-out go arbitrarily far, then the user
  clarified the actual intent: zoom-out should never exceed the ship's own
  `_base_zoom` (so a bigger ship always shows more, and shrinking the ship
  pulls an over-cap zoom back down automatically), while zoom-in is capped by
  a flat `scroll_max_zoom` (0.6 — the old pre-widen max, roughly a 6-hex
  ship's default). Final clamp: `clampf(_base_zoom + _manual_zoom_offset,
  _base_zoom, scroll_max_zoom)`, recomputed both on scroll and on
  `layout_applied`.
- **Starfield pop-in on large-ship zoom-out, found by the user, not a
  review**: with a big ship zoomed far out, stars wouldn't render on the far
  side of the screen until the camera physically panned there. Cause:
  `starfield_layer.gd` sets `motion_mirroring = field_size` per layer, and
  Godot's `ParallaxLayer` mirroring only recomputes how many tiled repeats to
  draw when the camera *pans*, not when zoom changes — so a zoomed-out view
  wider than one `field_size` tile has visibly missing repeats until motion
  triggers a recalculation. **Went through two size iterations balancing
  coverage vs. performance**: first pass jumped `field_size` from
  `(3500, 2000)` to `(9000, 5000)` with `star_count` scaled ~6.4x per layer
  (5000/6400/4800/4200) to preserve density — user reported this caused a
  "massive" perf hit. Settled on `field_size = (6000, 3600)` with a flat
  `star_count = 2000` on every layer (previously varied 650-1000 per depth
  layer) across all 4 scenes. **Known residual limitation**: at the most
  extreme zoom-out (very large ship + wide monitor, e.g. 1920x1080 at the
  ~0.233 zoom floor needs ~8240x4635 world units visible) the tile is still
  smaller than the view, so the original pop-in can partially resurface in
  that edge case — accepted trade-off for performance, not fixed.
- **Small-screen star flicker, also user-reported**: attributed to aliasing
  — 1-2px `draw_circle` stars round to different pixel coverage frame-to-
  frame as the parallax layer scrolls sub-pixel amounts. Tried
  `antialiased=true` on both `draw_circle` calls plus raising the size floor
  (`min_star_size` default 1.0 → 1.2; the smallest layer, DeepStars, raised
  from `0.5`/`0.9` to `1.0`/`1.3` min/max across all 4 scenes) — the
  antialiased circles caused a severe frame-rate regression (Godot's
  per-primitive AA is CPU-tessellated per shape, expensive in bulk at
  ~2000 stars/layer) and were reverted. **Left in place: the size-floor bump
  only** (untested whether that alone is sufficient — not yet confirmed with
  the user). If flicker persists, the next lever to try is project-wide
  2D MSAA (Project Settings → Rendering → Anti-Aliasing) instead of
  per-primitive AA, since it's hardware-accelerated once per frame rather
  than tessellated per circle — not yet attempted.

### Still open from this session
- Confirm with the user whether the size-floor-only fix resolved the
  small-screen flicker, or whether project-wide 2D MSAA is still needed.
- The extreme-zoom-out starfield pop-in edge case (very large ship + wide
  monitor) is a known, accepted gap, not fixed.
- None of this session's changes have been run/verified in the editor yet.

## Session before that (3 more abandoned-station wrecks + a second nebula)

Small, focused follow-on to New Locations (`Roadmap v.2-v.9.md` Version 0.6),
picked up from user-supplied art rather than a fresh feature request.

- **Three new faction station images added as wrecks in `derelict_station.tscn`**:
  `pirate_space_station.png`, `ancient_space_station.png`,
  `corporate_large_station.png` (all brand-new files, never seen by the
  editor before — confirmed via `filesystem_manage(op="search")` returning
  empty `"type"` before a `scan()`). Added as three more darkened/tilted
  `Sprite2D` wrecks alongside the existing `corporate_space_station.png`
  one, each with its own faction-tinted `self_modulate` (pirate reddish,
  ancient blue-grey, corporate grey), spaced apart with 3 extra `Salvage`
  pickups nearby. **Same mipmap gotcha as the original faction-art batch**:
  all three imported with `mipmaps/generate=false` by default, silently
  defeating `ShipLayoutRenderer`'s linear-mipmap filter — fixed by flipping
  to `true` in each `.import` and `filesystem_manage(op="reimport")`.
- **Second nebula added** (`Nebula2` in `map_tester.tscn`), placed far from
  the first (`(-9200, -7800)` vs. the original's `(8000, -6000)`) so their
  6000-radius zones can't overlap, reached by a new teal-ringed speed-lane
  gate pair (`SpeedGateToNebula2`/`SpeedGateFromNebula2`). Gave it a
  distinct teal `tint_color` override on the instance — **the particle
  cloud itself is still the same purple gradient as the first nebula**,
  since `nebula.tscn`'s `Gradient_cloud` sub-resource isn't exposed as an
  `@export`; only the screen tint differs between the two. Known, accepted
  simplification, not a bug.
- Verified live via the godot-ai MCP tools: ran `derelict_station.tscn` and
  `map_tester.tscn`, teleported the ship to each new location via
  `game_eval`, and screenshotted both — all three new wrecks render
  correctly and distinctly, and the second nebula's cloud/tint/gate all work.
  The `GameState`-not-found compile errors reported at each `project_run`
  are the same stale editor-reload-cycle false alarm documented below (not
  a real bug — never affected the actual running game).

### Still open from this session
- Roadmap Version 0.6 New Locations is now: asteroid fields ✓, derelict
  stations ✓ (now with 4 wrecks total, one per faction/tier), nebulae ✓
  (2 exist now), abandoned wrecks — arguably still not a *distinct*
  location from "derelict stations," if the user wants a separate wreck
  field that isn't station-shaped (e.g. destroyed ships, not stations).
- The two nebulae's particle clouds are visually identical (only tint
  differs) — would need a new `@export`-ed color/gradient on `nebula.gd`
  to actually vary, not done since it wasn't asked for.

## Session before that (frame stutter: cached render materials in tractor beam + warp gate)

**Bug report**: user described an occasional ~0.5s stutter while just flying
around, reportedly worse with larger ships. A previous session's performance
check (see below) had looked at `time/fps`/`time/process`/`object/node_count`
and found nothing — this session found the real cause by directly
instrumenting the running game via the godot-ai MCP tools instead of relying
on aggregate editor monitors (which, it turns out, reflect the whole editor
process, not the isolated game — see "Tooling gotchas" below).

- **Diagnosis method**: attached a throwaway `Node` (via `game_eval`,
  `get_tree().root.add_child(...)`) running a script that logs to an array
  whenever a frame's `delta` exceeds 50ms, capturing timestamp, node count,
  draw calls, and ship velocity per spike. Had the user reproduce live while
  polling the array afterward — two rounds, the second with an enriched
  capture, caught it clearly.
- **What the data showed**: not a quick 0.5s blip but sustained multi-second
  freezes (one ran ~8.4s straight at ~7 FPS) with ship velocity at or near
  zero and **draw calls/node count essentially flat throughout** — ruling out
  a script-side O(n) loop or a spawn burst. Flat scene complexity + a
  multi-second main-thread stall is the signature of Godot's Forward+/Vulkan
  renderer compiling a shader/pipeline variant the first time it's actually
  drawn, not a per-frame logic cost.
- **Root cause found by code inspection**, not by direct pipeline profiling
  (Godot doesn't expose that over this MCP setup): two places built a
  **brand-new render material at runtime on every use** instead of reusing
  one — `TractorBeam._additive_material()` (`scenes/player/tractor_beam.gd`)
  called `CanvasItemMaterial.new()` twice per newly-tractored salvage/tech
  part, and `WarpGate._spawn_speed_lines()` (`scenes/world/warp_gate.gd`)
  called `ParticleProcessMaterial.new()`/`CanvasItemMaterial.new()` fresh on
  every speed-lane dash. Each fresh material instance forces the renderer to
  set up its pipeline again even though the properties never actually
  changed (`ParticleProcessMaterial.direction` was the only per-call-varying
  property in the warp gate case).
- **Fix**: both now cache the material as a `static var`, built once and
  reused (the warp gate's `direction` is mutated in place on the cached
  instance before each dash rather than constructing a new material).
- **Why this explains "worse with larger ships"**: not confirmed directly,
  but a larger ship has more hex modules/turrets, so more distinct
  faction/tier textures and particle setups get drawn for the first time as
  the camera (which zooms out further for a larger ship — see
  `camera_shake.gd`'s `_on_layout_applied`) pans across more of the scene —
  plausibly more first-time shader-compile events queueing up, on top of the
  two confirmed repeat-offender call sites above.
- **Verified live**: same spike-monitor instrumentation, before (multiple
  multi-second freeze clusters during 60s of normal play) and after (user
  confirmed no reproduction after specifically mining asteroids and using a
  speed-lane gate a few times, the two changed code paths).
- **Tooling gotcha confirmed this session**: `editor_manage(op="monitors_get")`
  reports the **editor process's** Performance singleton, not the isolated
  running game's — in this project that showed ~23,700 nodes vs. the game's
  real ~230, because it includes the entire editor UI. For real gameplay
  numbers, read `Performance.get_monitor(...)` via `game_eval` inside the
  running game instead.
- **Non-issue investigated and ruled out**: `warp_gate.gd`/`ship.gd` showed
  "Identifier not found: GameState" errors in `logs_read(source="editor")`,
  looking like a regression of a previously-fixed autoload/type-resolution
  bug (see "Most recent session before that" below). Confirmed via
  `game_eval` that `GameState` resolves fine and the ship functions
  correctly in the actual running game — this is editor-side reload-cycle
  noise, not a live bug, consistent with an identical false alarm noted in
  an earlier session for an unrelated script. Not fixed (nothing to fix);
  documented here so it isn't re-investigated from scratch.

### Still open from this session
- The "worse with larger ships" correlation was the user's report, not
  independently confirmed against a specific large ship — the fix addresses
  the two confirmed repeat-offender material-allocation sites, which should
  help regardless of ship size, but if stutters recur specifically tied to
  ship size, the camera-zoom-scales-visible-content angle (see above) is the
  next thing to check, not yet investigated further.
- No general audit was done for other `Material.new()`/`Texture.new()`-style
  per-event runtime allocations elsewhere in the codebase — only the two
  spots that matched this specific symptom were fixed.

## Most recent session before that (Version 0.6: trading, station, warp gates, new locations, nebula)

Built out nearly all of Version 0.6 across several back-to-back requests, in
order: Trading → station visual/interaction/repair → Warp Gates (both
types) → New Locations (asteroid field, derelict station) → Nebula →
several rounds of polish (speed-lane redesign, gate-to-gate arrival,
performance check, cleanup). Roadmap status: **Trading, the station's
trade/repair/build/research loop, and Warp Gates are done. New Locations is
partial** — Asteroid Field and Derelict Station exist; wrecks and additional
nebulae don't yet (only one nebula).

### Trading + Credits
- New `int` Credits currency on `Inventory` (`add_credits`/`spend_credits`/
  `has_credits`/`get_credits`, `credits_changed` signal) — deliberately a
  new currency, not material-for-material barter, chosen via
  `AskUserQuestion`.
- `Materials.DISPLAY_DATA` gained `sell_price`/`buy_price` per material;
  `buy_price > sell_price` always, so round-tripping (sell then buy back)
  strictly loses Credits like a normal trader spread.
- `scenes/ui/trade_panel.gd`/`.tscn` — new `CanvasLayer` panel, same
  `home_base`/`home_base_range` gating and `"menu_panel"` group pattern as
  the existing upgrade/builder panels. Bound to `toggle_trade` (`T`).

### Station: visual, interaction prompt, repair
- The home base went from a bare `Marker2D` to `scenes/world/station.tscn`
  (`corporate_space_station.png`), with a real asset pipeline: mipmap fix
  (same `mipmaps/generate=false` issue as faction art before it), 4x scale,
  `z_index = -1` so it draws behind the ship, bloom via `self_modulate` > 1
  on an alpha-blended sprite (pushes already-bright cyan/white pixels past
  the glow threshold — same trick `engine_thruster.tscn` uses via additive
  blend, applied here to a normal sprite instead), and the source PNG was
  cropped in-place (via a `game_eval`-scripted `Image.get_region()`/
  `save_png()` — no Python/PIL available in this environment) to remove a
  baked-in caption band the artist had left at the bottom.
- **`.tscn` files cannot contain `#` comments** — confirmed directly:
  writing one before a property line silently reverted that property to
  its default with *no load error anywhere*, diagnosed only by comparing
  file content to the live `game_eval`-read value. Applies to every `.tscn`
  edit in this project, not just this one.
- `scenes/ui/station_prompt.gd`/`.tscn` — simple always-present `CanvasLayer`
  that shows "Near Corporate Station — U: Upgrades B: Build T: Trade" when
  the ship is within `home_base_range`, so the three panels are discoverable
  without already knowing the keybinds.
- **Repair is a real mechanic, not just a Credits sink.** Passive
  module-regrowth (`Ship._advance_module_repair`, pre-existing) now caps at
  `passive_repair_cap_fraction` (0.4, exported — "upgradable later" per the
  user) of a module's max condition instead of always reaching 100% — a
  module still becomes *operational* again once it hits the cap (exits
  `_regrowing_placement_ids` there, not at full), it just isn't fully
  healed. `Ship.repair_fully()` (paid, at the station) tops every attached
  module to 100% and heals `Health` to match; cost is
  `get_missing_health() * repair_cost_per_health` (both exported). Verified
  live: passive regen stopped exactly at the 40% threshold and the module
  went functional; the panel's Repair button then fully healed and deducted
  the right Credits amount.

### Warp Gates — two modes, one shared script (`scenes/world/warp_gate.gd`)
`WarpGate.mode` is `GATE` (instant scene change, for destinations you can't
reach any other way) or `SPEED_LANE` (in-scene high-speed dash). **Both are
always built in pairs** — every gate references its partner (by scene node
name for `GATE`, by `NodePath` for `SPEED_LANE`) so there's always a way
back. This was retrofitted onto the first `SPEED_LANE` gate mid-session
after the user pointed out it was one-way with no return.

- **`GATE` mode** uses a new `GameState` autoload (`scripts/game_state.gd`)
  to carry Credits/materials/captured-tech/research/manufacturers/
  layout/health-fraction across `change_scene_to_file` (each region is a
  separate scene, so the old tree — Ship, Inventory, everything — is
  discarded outright). `Ship._ready()` calls `GameState.apply(self)` for
  anything in the `"player_ship"` group. **Per-module condition is not
  preserved across a warp** — only the aggregate Health fraction — a known,
  accepted simplification.
- **Gate arrival is now gate-to-gate, not scene-default-spawn.** Originally
  a `GATE` warp landed wherever that scene's `Ship` node happened to sit.
  Fixed with `WarpGate.destination_arrival_node_name` (set on the
  *departing* gate) → `GameState.pending_arrival_node_name`, consumed once
  in `GameState.apply()` by looking up that name in the new scene and
  snapping the ship there — normally the paired gate. Also cleared
  obstacles from around every gate on both ends (nudged two Home System
  asteroids, moved Asteroid Field's return gate outside the cluster) so
  "large ships can fit through," per explicit request.
- **`SPEED_LANE` mode redesigned mid-session** per detailed feedback: holds
  the ship 2.5s with camera shake ramping up (`Tween.tween_method` driving
  the new `CameraShake.add_shake()` public hook from 0 up to a peak — the
  shake *reads* as ramping because the tween's rising target outpaces the
  camera's own per-frame decay early on, then overtakes it), then dashes at
  a fixed **speed** (1600 px/s, not fixed duration — so distance changes
  travel time, unlike the original version) with white additive
  trail-particle "speed lines" shooting backward past the ship
  (`local_coords = false` so they line up with true travel direction
  regardless of ship rotation). **Camera lag during the dash was a real,
  separate bug**: `Camera2D.position_smoothing_enabled` can't keep up with
  a tweened position jump and visibly "lost" the ship — fixed by disabling
  smoothing for the dash and restoring it after. Verified live: camera's
  `get_screen_center_position()` matched ship position to within 0.003
  units post-dash.
- Player control is suspended for the whole hold+dash via a throwaway node
  added to the `"menu_panel"` group (same mechanism the UI panels use) —
  not a new suspension system.

### New Locations — Asteroid Field, Derelict Station
- `scenes/world/asteroid_field.tscn`: 14 densely-packed asteroids, richer
  ore odds via two new exported thresholds on `asteroid.gd`
  (`common_chance`/`electronics_chance`, defaults unchanged so existing
  Home System asteroids look the same) rather than a second copy of the
  script.
- `scenes/world/derelict_station.tscn`: the same station art, darkened/
  tilted (`self_modulate`, `rotation`) to read as abandoned, with 6
  pre-placed `Salvage` pickups of mixed rarity. No trade/build panels — it's
  not a functioning station.
- **Real bug, found via screenshot, not review**: all three new region
  scenes (`frontier_system`, `asteroid_field`, `derelict_station`) rendered
  a flat grey background instead of black/starry. Cause: `map_tester.tscn`'s
  actual background comes from a full-screen `bg_space.png` Image layer
  (`ParallaxLayer > Sprite2D`, tiled via `motion_mirroring`) — the sparse
  procedural `starfield_layer.gd` star-dot layers alone don't cover the
  screen, and `Environment.background_mode = 3` is `BG_CANVAS` (not `BG_SKY`
  — easy to misread), which falls through to Godot's default grey when
  nothing covers a given pixel. All three new scenes had copied the star
  layers but not the image layer. Fixed by adding it to all three.

### Nebula (`scenes/world/nebula.gd`/`.tscn`)
- A big `Area2D` zone: a drifting purple/magenta `GPUParticles2D` cloud
  (additive blend) plus a translucent full-screen tint that fades in/out on
  enter/exit. A genuine mechanic, not just visual: `Ship.is_in_nebula()`
  (depth-counter, not a bool, so overlapping zones can't prematurely clear
  each other) cuts `ship_input.gd`'s target-lock range to 35% while inside.
- **Sizing was a two-step correction.** User asked for "1/20th the size it
  should be" (literal 20x). Doing that literally (radius 900 → 18000) at
  the original placement made the cloud's particle-emission volume reach
  all the way back to spawn (~9600 units away, well inside an 18000-radius
  sphere), washing the *entire* Home System in nebula tint/particles from
  any vantage point — confirmed via screenshot. Settled on ~6-7x (radius
  6000) instead: still a dramatic, multi-screen-filling landmark, but
  contained to its own area. **Separately**, the first size pass also
  scaled individual particle *scale* up right alongside the radius (to
  50-110), which was wrong — particle size shouldn't track field radius,
  only count/spread should — and produced a solid near-white blowout at
  close range from additive overlap. Fixed by reverting particle scale to
  a modest 15-30 and raising `amount` instead for density across the larger
  area. Both mistakes were caught via live screenshots, not anticipated.
- Reached via a `SPEED_LANE` pair (`SpeedGateToNebula`/`SpeedGateFromNebula`
  in `map_tester.tscn`) — placed far from spawn but well inside the
  now-uncapped region (see below).

### Distance cap removed
`RegionBoundary` (the node that gently pushed the player back inside a
radius of the home base) was removed from `map_tester.tscn` entirely, per
explicit request, once the nebula needed to sit far outside its old radius.
The script (`region_boundary.gd`) is untouched on disk, just unused.
Verified live: a ship placed at (5000, 5000) held position with zero
velocity after 1s of no input.

### Smaller changes this session
- **Home System's two starting pirates were removed** from `map_tester.tscn`
  per request. Couldn't literally "comment out" — `.tscn` has no comment
  syntax (see above) — so the two `[node]` blocks were deleted instead;
  their `ext_resource` entries were left in place so re-adding them is a
  two-line paste.
- **8 more asteroids** (`Asteroid9`–`16`) scattered around Home System,
  further out than the original cluster, clear of every gate/station.
- **Performance check, inconclusive.** User reported perceived slowdowns
  while moving around. Checked `time/fps` (145, stable), `time/process`
  (~2ms), and `object/node_count` (stable, not growing) both idle and while
  moving — found nothing via these metrics. Reported this transparently
  rather than guessing at a fix; if it recurs, knowing which scene and
  whether it's a one-time stutter vs. sustained low FPS would narrow it
  down a lot faster than another blind metrics pass.

### Real bugs found this session (all via live testing, not review)
1. **`trade_panel.gd`'s `_on_state_changed(_value)` connected directly to
   `Health.health_changed`**, which emits two args (`current`, `max`) — every
   hit while the panel existed threw a runtime "Method expected 1
   argument(s)" error. Fixed with a dedicated `_on_health_changed(current,
   max)` handler.
2. **The `GameState` autoload corrupted GDScript's global class resolution
   for the entire project** when its `capture`/`apply` methods were typed
   `Ship`/`ShipLayout` — manifested as a completely unrelated compile error
   in `ship.gd` itself (`Trying to assign value of type 'Resource' to a
   variable of type 'ship_layout.gd'`), reproduced identically even in an
   isolated `ship.tscn`-only run with the `GameState` autoload still
   registered but nothing else changed. Root cause: **autoloads compile
   before the project's other global classes are guaranteed registered** —
   a static type hint to a project-defined class inside an autoload script
   can corrupt type resolution for that class everywhere, not just fail
   locally. **Durable rule: keep autoload script parameters/returns
   untyped (`Node`/`Resource`/`Variant`), never a project `class_name`,
   even though normal (non-autoload) scripts are fine with it.**
3. Background-layer bug (New Locations section above) and the two nebula
   sizing mistakes (Nebula section above) — all found via screenshot, not
   caught by review beforehand.

### Tooling gotchas confirmed/newly found this session
- **Editing `project.godot` directly on disk while the editor is running
  does not take effect** — the live editor doesn't pick up autoload/input
  changes from an external file write. Manually adding `GameState` to
  `[autoload]` this way left the editor's own `autoload_manage(op="list")`
  still reporting it absent, and the *next* MCP write to `project.godot`
  (an unrelated `autoload_manage`/`input_map_manage` call) silently
  overwrote/dropped the manual edit. **Use `autoload_manage`/
  `input_map_manage` for anything in `project.godot`, never a direct file
  edit**, even though direct edits work fine for `.tscn`/`.gd` files.
- **One-line `for x in y: ...` and `if cond: return a else: return b` style
  control flow inside `game_eval` is unreliable** beyond the
  already-known "can silently execute only once" — this session it also
  intermittently returned wrong/empty results for `get_children()` loops
  and `get_child_count()`-sized loops even when the equivalent
  `get_child_count()` call alone reported the correct number. Prefer
  `get_tree().get_nodes_in_group(...)` (reliable all session), direct
  indexed access (`get_child(i)`), or multiple separate single-statement
  `game_eval` calls over any loop/conditional built as one string.
- A `game_eval` runtime error can leave the game in a debugger "break" that
  then causes *later, unrelated* calls to report stale errors from the
  original failure — already known, reconfirmed several times this
  session; `project_manage(op="stop")` + `project_run` clears it.

### Still open from this session
- Per-module condition doesn't survive a `GATE` warp (only aggregate Health
  fraction does) — acceptable for a travel mechanic, would matter if warping
  became usable mid-combat.
- New Locations is not finished: no wrecks, and only one nebula exists
  (roadmap examples: asteroid fields ✓, derelict stations ✓, abandoned
  wrecks ✗, nebulae — one exists, "more nebulae" not requested/built).
- The performance concern was investigated but not resolved — see above.
  Worth a fresh look with more specifics from the user (which scene,
  stutter vs. sustained).
- Home System's other gates (`WarpGateAsteroidField`,
  `WarpGateDerelictStation`, both `SpeedGateDemo*`) got only a light
  clearance pass, not the same explicit-distance audit as
  `WarpGateFrontier`/`SpeedGateDemo` — probably fine, not verified as
  rigorously.

## Two sessions before that (reverse engineering, pirate_light_one's wing, debris/thruster bug fixes, Manufacturers)

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
- A wreck field that isn't station-shaped (destroyed ships, not stations) —
  "abandoned wrecks" and "derelict stations" are arguably the same location
  type right now (4 station wrecks in one scene); see "Most recent session".
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (research beyond reverse-engineering, co-op). **Warp gates
  are done now** — remove from any future "not started" framing.

## Suggested next step

**Version 0.6 (The Living Universe) is essentially complete now**: Trading,
the station's trade/repair/build/research loop, both Warp Gate types
(gate-to-gate arrival, always-paired), and New Locations (Asteroid Field,
Derelict Station with 4 faction wrecks, 2 nebulae) all work end-to-end and
were verified live. The only arguable Version 0.6 gap left is whether
"abandoned wrecks" should be a distinct non-station wreck field (see "Still
open" above) — not confirmed as wanted. No specific next item has been
chosen yet; candidates on the table: the reported-but-unresolved performance
concern (get more specifics from the user first — see "Still open" in the
frame-stutter session below), or pick up a Version 0.5 gap instead (no
Corporate/Ancient enemy ship exists yet — see below). Version 0.4 (Combat
Evolution) is complete. Version 0.5 (Technology & Factions) has real
substance (reverse engineering + Manufacturers both work end-to-end) but its
one deliberately-deferred gap is enemy ships for Corporate/Ancient — faction
identity is still cosmetic/tech-only in actual combat. Also still on the
table from before: audit `pirate_light_two`/`pirate_heavy_one` for the same
severability issue `pirate_light_one` had, or have the **user actually
playtest current combat** for the first time since per-module damage/wing
severance/research gating/Manufacturers all landed. Do not start any of
these without the user confirming which first.

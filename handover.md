# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up.

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
- **Known, accepted limitation**: `pirate_light_one`'s layout has every
  module directly adjacent to the core (or with 2+ redundant connections)
  — it is architecturally a blob with **no severable point at all**, by
  construction, not by any damage-tuning issue. Only `pirate_med_one` (and
  player-built ships with a real thin appendage) currently have a genuine
  severable wing. Giving the light pirates an actual appendage was
  discussed but **not yet done** — see "Suggested next step".

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

## Known MCP/tooling gotchas (only relevant if using the godot-ai MCP tools)

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

- **Give `pirate_light_one` (and possibly other compact pirates) an actual
  severable appendage.** Explicitly flagged as a real gap: it currently has
  zero severable points by construction (see "Per-module ship damage"
  above), so the whole wing-detachment feature never shows up against it in
  ordinary play.
- Stat bonuses/penalties tied to a module's distance from the Core (the
  "cockpit interference" idea from design discussion — sensors better far
  out, power-hungry modules better close in, Struts doubling as power
  relays) — deliberately deferred until the base detachment/balance system
  has been played with more.
- Reactor/Battery/Command-Core-adjacent modules other than engines/weapons
  still have no *mechanical* effect when destroyed beyond losing the hex
  (no repair mechanic either).
- Player weapon accuracy/spread — untouched on purpose this session.
- More module types / a real data-driven (non-static) module catalog as
  `.tres` resources.
- A planet catalog, multiple planet instances, orbit/parallax motion, or
  any planet-surface gameplay.
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (factions, warp gates, research, co-op).

## Suggested next step

No official next roadmap item has been decided yet — this session was spent
reactively testing and rebalancing the per-module damage system the user
chose earlier (engine failures → "real per-module damage"). The natural
next step is for the **user to actually playtest current combat** (their
own ship, real weapons, real pirates — not synthetic MCP tests) now that
Hull/Heavy Hull/Core health and AI aim jitter have all changed, and report
back whether it feels right, too easy, or still too fast. Concrete
candidates already flagged and ready to pick up depending on that feedback:
give `pirate_light_one` a real severable wing (small, self-contained), or
continue the Core-distance stat-bonus idea if the base system feels solid.
Do not start either without the user confirming which (or something else)
first.

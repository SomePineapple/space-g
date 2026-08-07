# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `Roadmap v.2-v.9.md` before continuing.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up. `docs/gotchas.md` has durable GDScript/Godot/MCP
gotchas pulled out of session history — check it before fighting a weird
engine/tooling behavior. **`docs/multiplayer.md` is required reading before
touching ship control, the player-ship lookup, randomness or object spawning**
— those four areas now have deliberate seams in them and it explains what is
and (mostly) is not prepared for multiplayer. **`docs/HUD-1d-Godot-spec.md`
plus `docs/hud-1d-reference.png` are the source of truth for the gameplay
HUD's appearance** — check them before restyling anything under
`scenes/ui/hud*`. **`docs/design_handoff_ship_builder/` and
`docs/design_handoff_upgrade_tree/` are likewise the source of truth for the
ship-builder and module-upgrade screens** — read the whole folder (README,
LAYOUT_SPEC where present, and the JSON) before touching
`scenes/ui/ship_builder/` or `scenes/ui/upgrades/`. **`docs/performance.md`
is required reading before writing or changing any `_draw()` loop, starfield
or particle emitter** — it records why the 2D canvas renderer's lack of
command batching dominated frame cost, how the starfield and hull renderers
were rebuilt around that, and how to measure before optimising.

**Read "Most recent session" first.** Sessions older than the two kept in
full below are compressed to short summaries — full narrative detail (exact
iteration steps, every dead end tried) has been trimmed since it's rarely
needed again; if you need it, it's in git history / this file's prior
versions. Design-reference docs (`docs/aienemies.md`, `docs/region_design.md`)
remain the source of truth for the systems they cover, not this file.

## Most recent session (ship builder + module upgrades rebuilt to their design handoffs; per-instance upgrade system deleted)

Two design handoffs implemented back to back, then a dead-code strip. Both
handoff folders are the source of truth for their screen's appearance — not
this file.

### Ship builder (`docs/design_handoff_ship_builder/`)

Full visual rebuild of `ShipBuilderPanel`; gameplay logic preserved. Three
scoping calls were made via `AskUserQuestion` and should not be relitigated:
real faction hex art in the module icons with the mock's gradient+glyph as
fallback, a static cell-count readout (no build-size dropdown — no such system
exists), and Research/Repair living in the selected row's expansion strip.

New under `scenes/ui/ship_builder/`: `builder_theme.gd` (every colour/metric
from the handoff plus StyleBox and font factories — monospace via `SystemFont`,
no font asset added), `module_presentation.gd` (category grouping/glyphs
derived from `ModuleType`'s own fields rather than a new field on every type),
`module_hex_icon.gd`, `module_list_view.gd`, `builder_stat_strip.gd`,
`builder_presets_card.gd`, `builder_backdrop.gd`. `hex_grid_control.gd` gained
the fading lattice, field glow, vignette, per-module glow, a dashed pulsing
placement preview and responsive cell sizing. `station_prompt.gd` gained
`class_name` + `PROMPT_TEXT` so the builder's status line reuses the string.

Known deviations, all commented in-file: Godot has no cheap `backdrop-filter`,
so cards are translucent-not-blurred; filter tabs are 10px not 10.5px or they
wrap to two rows in the 336px panel.

### Module upgrades (`docs/design_handoff_upgrade_tree/`)

**This one took three corrections to land — read the whole handoff folder
before touching it.** The first attempt kept the game's per-mounted-module
trees and only borrowed the visuals; the user's actual intent was the
handoff's own data model. The final shape:

- **The rail is the seven systems** (Hull, Propulsion, Weapons, Power,
  Storage, Sensors, Mining) and each owns **one ship-wide tree**. There are no
  per-module rows. Weapons is the 17-node tree with Laser/Missile/Rail branch
  hues and three merge nodes.
- **Content is `upgrade_data.json` copied to
  `res://resources/upgrades/upgrade_tree_data.json`** (verbatim apart from
  dropping `_schema`) — 7 categories, 89 nodes. Adding an upgrade is a data
  edit; nothing in code enumerates nodes.
- `ShipUpgradeCatalog` loads it and resolves the handoff's display-string costs
  ("8 Copper, 3 Wiring") against `MaterialCatalog`/`ComponentCatalog` by
  display name. Every name in the data currently resolves.
- `ShipUpgradeService` is the two predicates and nothing else —
  `is_unlocked` / `is_available`. `parents` is an AND list and arity 2+ *is*
  the merge mechanic; there is no separate flag.
- **Unlocks are ship-wide, stored by id per category in `GameState`**
  (`is_upgrade_unlocked`/`unlock_upgrade`/`get_unlocked_upgrades`, plus
  `last_upgrade_category`). Deliberately *not* part of `capture()`/`apply()`:
  those mirror one ship across a warp, whereas unlocks are player progression
  that outlives any hull.

UI under `scenes/ui/upgrades/`: `upgrade_palette.gd` (OKLCH→sRGB so the
handoff's hue-per-category tokens stay as numbers), `upgrade_tree_layout.gd`
(the polar fan — span allocation with mirroring, merge placement at
+0.4×STEP, label anchoring, frame measurement), `upgrade_tree_view.gd`
(drawing and hit-testing only), `upgrade_rail_list.gd`,
`upgrade_detail_panel.gd`. `upgrade_menu.gd` assembles them.

Two things worth knowing before editing the view:
- **The renderer reads only `UpgradeTreeLayout.entries`.** It used to keep its
  own node list too and crashed indexing a stale id when switching categories
  mid-frame. Don't reintroduce a second copy.
- **All trees share one fit scale** — `UpgradeMenu._shared_frame()` unions
  every tree's extent and passes it as the view's reference frame, so nodes
  don't resize when you switch system. Each tree still centres on its own
  extent.

### Dead-code strip

The per-`ModuleInstance` upgrade system (Phase 8.1) was superseded and is
**deleted**: `module_upgrade_catalog.gd`, `module_upgrade_node.gd`,
`module_upgrade_service.gd`, `module_upgrade_tree.gd`, and the long-orphaned
`upgrade_tree_lines.gd`. With them went `ModuleInstance`'s upgrade state
(`unlocked_upgrade_ids`, `get_stat_modifier`, `get_level`, …),
`ShipLayout._instance_stat_delta` and its six call sites,
`HardpointBank._apply_instance_upgrade_modifiers` and its four, and
`Ship.apply_instance_upgrade_effect`. Net −327 lines.

`ModuleInstance` survives as identity/provenance only — the owned-module pool
still needs it so removing and re-placing returns the *same* module.
`HardpointBank.apply_modifiers()` survives and is still used by the
manufacturer path.

### Verified / not verified

Verified live via `game_eval` and real screenshots: both screens render and
match their references; builder place/remove/validate/craft/filter/preset;
upgrade rail switching across all 7 trees, unlocking (costs actually spent),
merge REQUIRES ALL with unmet dots, progress roll-up, persistence across
close/reopen. After the strip: ship stats unchanged (mass 3.25, hp 435, thrust
500, cargo 60, max speed 153.8), 4 hardpoints mount and fire, builder
round-trips. Game log clean throughout.

Not verified: real mouse/keyboard input into either screen (handlers were
called directly — the documented MCP limitation), and no human has played it.

### Still open

- **No upgrade changes ship behaviour.** The handoff authors no stat
  modifiers, so unlocking spends resources and records the id and that is all.
  The user is writing the upgrade list and will hook effects up next. The
  wiring points are `ShipUpgradeService.unlock()` (apply the effect) and
  `HardpointBank.apply_modifiers()` (reach an already-spawned hardpoint
  without rebuilding it); `Ship._refresh_layout_stats()` re-derives aggregates
  without touching health or module condition.
- Node icons are 2-letter glyphs; the schema reserves an `icon` slot.
- `Missiles` as a separate player-facing category is gone — guns and launchers
  are both "Weapons" now.
- Editor-side `PlayerContext`/`GameRng` "not declared" parse errors appear in
  `logs_read(source="editor")` throughout and are pre-existing autoload reload
  artefacts; the *running game* log is the one that matters.

## Session before that (gameplay HUD rebuilt to the "1d" visual spec)

Short, single-purpose session. The user supplied two files in `docs/` —
`HUD-1d-Godot-spec.md` (exact colours, layout, anchoring and behaviour per
widget) and `hud-1d-reference.png` (a mock screenshot of the target) — and
asked for the existing gameplay HUD to be rebuilt against them. **The spec
and the reference image are the source of truth for HUD appearance, not this
file.** Three scoping calls were made via `AskUserQuestion` and should not be
relitigated without reason: full replacement of the old readout (not
side-by-side), the flat tinted-glass dropdown backdrop (not a blur shader),
and the engine default font for now.

- **`HudPalette`** (`scenes/ui/hud_palette.gd`, `RefCounted` + `class_name`,
  no autoload) holds the spec's colours as consts plus `health_color()` and
  `group_digits()`. Written as float literals with the hex in a trailing
  comment because GDScript `const` cannot fold `Color("rrggbb")`.
  **Material dot colours are deliberately NOT in it** — they come from
  `MaterialCatalog.color()` so the HUD can't drift from the cargo/trade/
  crafting panels. This means the material dots don't match the spec's own
  listed hexes; that was a conscious trade against the project's
  "don't duplicate gameplay values" rule.
- **`VitalsReadout`** (`scenes/ui/vitals_readout.gd`) — top-left HP/EN rows:
  glow dot + 74×5 rounded bar + number, HP tinted good/warning/critical at
  >50%/>20%. Drawn in `_draw` rather than built from nested Controls (two
  dots and two capsules vs. six nodes' worth of styleboxes to keep in sync);
  only the two numbers are real `Label`s. Rounded bar ends are a rect plus a
  circle at each end — `draw_rect` has square corners and `draw_line` has no
  round cap.
- **`CargoWidget`** (`scenes/ui/cargo_widget.gd`) — bottom-left chip
  (`used/max` + tweened chevron) toggling a 190px dropdown that grows
  *upward*. The widget anchors bottom-left sized to the chip, and the
  dropdown hangs off negative Y from there — no anchor gymnastics. Reads
  `Inventory` directly (`materials_changed`/`cargo_capacity_changed`), so
  `hud.gd` doesn't relay cargo at all.
- **`RadarDisplay`** restyled, not rewritten: cyan palette, faked radial
  gradient (concentric fills — `draw_circle` takes a flat colour), **one
  faint range ring per 1000 units** so a radar-range upgrade adds rings
  rather than rescaling a fixed pair, a trailing sweep wedge, expanding ping
  pulses (blip `age` doubles as the pulse clock — no per-blip `Tween`), a
  centre ship dot, and a `RANGE N` label. All existing sweep-reveal/blip-
  matching logic is untouched.
- **`hud.gd`/`hud.tscn`** — the old dark background rect and the four stacked
  `Salvage:`/`Health:`/`Energy:`/`Credits:` labels are gone. HUD now only
  routes ship signals to `VitalsReadout`, formats credits as `1,240 CR`, and
  keeps the damage vignette and STORAGE FULL cue. `ScannerDisplay`'s
  `TOP_MARGIN` moved 10 → 52 so it clears the credits readout.

Verified live via `game_eval` + real screenshots against the reference:
corner anchoring at 1250×648, credits formatting, HP bar going amber at 45%,
chip text, and the dropdown opening to 190×130 seated 8px above the chip with
correct per-material counts and a 180°-rotated chevron.

**The chip's actual mouse click is untested.** Injected mouse events don't
reach the viewport GUI in this MCP environment (`gui_get_hovered_control()`
returns null even over the chip) — the same class of limitation as the
C/K/U keybinds in earlier sessions. The handler was called directly instead,
and a scene-wide hit-test confirmed nothing occludes the chip rect, but one
real click is worth doing.

## Earlier session (code review + four-tranche refactor: bugs/perf, DRY, ship.gd decomposition, multiplayer foundations)

A user-requested four-part code review implemented as four tranches, all done
and verified live via `game_eval` (tranches 1–3 committed as `b9122c5`,
`5d09b49`, `cebcaea`). **No human has played any of it.**

- **Tranche 1 — bugs/perf**: destroyed engines no longer leave their thrust
  bonus behind and `max_speed` is re-derived; dictionary indexes on the
  catalogs and `ShipLayout`; cached extents/particles; throttled energy signal;
  winch rope leak.
- **Tranche 2 — DRY**: `DriftingHexPiece`, `ChargedHardpoint`, `BeamVisual`
  bases; `Health.damaged()` replaced four `_last_known_health` copies. Fixed
  the white hull flash re-triggering every frame during regrowth.
- **Tranche 3 — ship.gd 1449 → 779 lines**: four child components on
  `ship.tscn`, all delegated to and relayed for — `HullDamageModel`,
  `HardpointBank`, `WreckageSpawner`, `ShipEnergy`. The loot-drop split was
  deliberately deferred (its exports are overridden in nine scene files; the
  right home is a `LootTable` Resource).
- **Tranche 4 — multiplayer seams**: `ShipIntent` (commands as data, filtered
  by `Role` *on arrival* rather than trusting the sender), `PlayerContext`
  autoload (replaced twelve `get_nodes_in_group("player_ship")[0]` lookups),
  `GameRng` autoload (simulation randomness only — presentation stays on
  global `randf()`), `WorldSpawn`, and `GamePanel` as the base for the five
  gameplay menus. Two real bugs were found and fixed during its verification:
  a station that stopped submitting left its last order latched, and the
  lock-on indicator was destroyed the frame it spawned.

**`docs/multiplayer.md` is the authoritative record here, including a long
"what is still single-player-only" section. Do not infer readiness from the
seams existing.**

## Earlier session (Phase 8.1 Module Upgrades — SUPERSEDED, code deleted)

**Historical only. Almost nothing described here still exists** — the most
recent session replaced this system wholesale with the ship-wide upgrade trees
from `docs/design_handoff_upgrade_tree/`. Kept as a short note so a fresh agent
who meets a stale reference knows what it was.

It built per-`ModuleInstance` upgrades: each specific built module carried its
own `unlocked_upgrade_ids`, so removing and re-placing a module preserved what
had been bought on it. `ModuleUpgradeCatalog`/`ModuleUpgradeNode`/
`ModuleUpgradeService` held ~12 nodes across five `tree_key`s, applied in two
tiers (aggregate `ModuleType` fields summed by `ShipLayout`, plus live
hardpoint node properties pushed at spawn). A radial `ModuleUpgradeTree`
overlay opened from a `UpgradeMenu` category → mounted-instance drilldown.

All of that is deleted. **What survives from it and still matters:**
- `ModuleInstance` and `ModulePlacement.instance`/`ensure_instance()`, now
  identity and provenance only — the owned-module pool is
  `Dictionary[key] -> Array[ModuleInstance]` rather than counts, so a specific
  built module keeps its identity through Build → Place → Remove → re-Place,
  and `GameState` snapshots the real pool across warps.
- `HardpointBank.apply_modifiers()` — additive stat deltas onto an
  already-spawned hardpoint, skipping properties the node lacks. Still used by
  the `Manufacturer.stat_modifiers` path and the intended hook for ship-wide
  upgrade effects.
- The `toggle_upgrades` ("U") binding and the home-base gate on the screen.

Radar/Scanner were flagged then as unwireable for stat modifiers because they
have no per-placement spawned node (`Ship.has_radar()`/`has_scanner()` are
boolean flags). **That is still true** and still applies to the new system —
worth checking before authoring Sensors effects.

## Older session (Phase 5 Crafting & Construction Economy, then a fix-up pass)

Implements a user-supplied "Phase 5 — Crafting and Construction Economy" spec
across three back-to-back requests in the same session: 5.1 (crafting
framework), 5.2 (module construction costs), 5.3 (salvaging constructed
parts), then a fourth request ("fix the limitation") closing two gaps
explicitly flagged at the end of the 5.3 report.

- **5.1 Crafting framework**: new `MaterialCatalog.GLASS` (5th raw material
  — chosen over a glass-free substitute via `AskUserQuestion`; deliberately
  has no `VARIANT_PRIMARY_MATERIAL` of its own in `asteroid.gd`, so it's
  only ever the existing uniform-random "otherwise" pick every asteroid
  variant already rolls among `MaterialCatalog.ALL_IDS` — a source needed
  zero asteroid.gd changes). `scripts/economy/component_type.gd`/
  `component_catalog.gd` (6 components: Metal Sheets, Wiring, Circuit Board,
  Reinforced Steel, Motor, Canister — same static-catalog-prototype pattern
  as `MaterialCatalog`/`ModuleCatalog`) and `crafting_recipe.gd`/
  `crafting_catalog.gd` (one recipe per component, raw-materials-only
  inputs; `CraftingRecipe.input_components` exists for future
  component-on-component chains, unused by any of the 6 initial recipes).
  `Inventory` gained a component pool (`_component_totals`, shares cargo
  capacity with materials — `get_cargo_used()` sums both) and
  `can_craft()`/`craft()` (checked-then-atomic: inputs consumed exactly
  once, output produced exactly once, blocked up front if cargo lacks room
  for the output). New `scenes/ui/crafting_panel.gd`/`.tscn` (**K** key,
  wired into `map_tester.tscn`) — one row per recipe with live
  inputs→owned-output text, a quantity `SpinBox`, a Craft button disabled
  when unaffordable, and a status-label failure/success message.
- **5.2 Module construction costs — the session's biggest architectural
  shift.** Previously `ModuleType.build_costs` (raw materials) were spent
  directly at ship-builder placement time, with unlimited free placement as
  long as materials were on hand. Now placement itself is free; owning a
  module is the gate. `Inventory` gained a third pool
  (`_owned_module_totals`, keyed by `Inventory.owned_module_key(module_type_id,
  manufacturer_id)` — a new static helper shared by `ShipBuilderPanel`'s
  palette and `Ship`'s starter-loadout seeding so both always agree on the
  same key). Each palette row in `ShipBuilderPanel` split into two buttons:
  **Build** (spends `build_costs` — now interpreted as *construction* cost,
  materials and/or crafted components mixed via new `Inventory.has_items`/
  `spend_items`/`add_items` generic helpers — to craft one owned instance)
  and **Select/Place** (free, disabled until `owned > 0`, consumes one owned
  instance on placement). Removing a placed module returns it to owned
  stock, not a raw-material refund. Hull/Engine/Scanner/Storage build costs
  were rewritten to the spec's own component-based examples (e.g. Hull =
  2 Metal Sheets + 1 Reinforced Steel); every other module type's build
  cost was left as plain raw materials — not a scope the spec asked to
  rebalance. **Soft-lock avoidance**: `Ship._seed_starter_owned_modules()`
  grants one owned instance of every module type/manufacturer on the
  starter loadout on a fresh player ship's very first `_ready()` (gated on
  `GameState.has_snapshot()` being false, so a warp-gate scene reload never
  re-grants), in addition to what's already physically mounted — so
  stripping the starter ship down in the builder can never leave the player
  unable to rebuild it. `GameState` now also carries components and owned
  module counts across warp-gate scene changes (previously only materials/
  captured-tech/research/manufacturers survived a warp).
- **5.3 Salvaging constructed parts**: `Salvage` gained a `kind` (MATERIAL |
  COMPONENT) — a component drop carries `component_id`/`component_amount`
  instead of `material_id`/`material_amount`, colored/collected through the
  parallel component path (`Ship`/`Inventory` gained `try_add_component`/
  `add_component`, mirroring the material versions exactly). Asteroid
  mining/`HardpointGrinder` fragments never set `kind`, so they stay
  material-only by construction — components are deliberately combat/wreck
  -exclusive, the alternative route to crafting materials, not a mining
  bonus. `Ship` gained `component_drop_chance`/`rare_component_chance`
  exports (new `ComponentCatalog.COMMON_IDS`/`RARE_IDS` split the 6
  components by how many raw materials they need) so each kill-drop rolls
  material vs. component, then common vs. rare. **Damaged modules already
  existed** as `CapturedTechPart`/`Inventory._captured_tech_totals` (severed
  wings, chance-based, pre-Phase-5) but could previously only be spent via
  `research()` to permanently unlock a locked type — new
  `Inventory.get_repair_cost()`/`can_repair()`/`repair_module()` is a second
  way to spend one: half the module's build cost (materials/components,
  rounded up) converts one captured part into a real owned-and-placeable
  instance. New **Repair** button per capturable module type in
  `ShipBuilderPanel`, next to the existing Research button, showing live
  cost/count. A captured part is structurally never placeable on its own —
  only `repair_module()` ever adds to `_owned_module_totals` from that pool.
- **Fix-up pass** (separate follow-up request, same session): hand-tuned
  `component_drop_chance`/`rare_component_chance` per enemy archetype
  (Scout/Light pirates 0.15/0.15 → Med 0.3/0.25 → Heavy 0.45/0.35 →
  Missile Cruiser 0.55/0.45 with a bumped 3–5 drop count) directly as
  `.tscn` node property overrides — first time this project has hand-edited
  per-instance `Ship` export overrides in an enemy scene file (existing
  precedent was only `drops_salvage = false` on the derelict-station
  region's own player-ship instance). Also gave `abandoned_ship.tscn`,
  `distress_signal.tscn`, and 3 of `derelict_station.tscn`'s 9 salvage
  nodes explicit `kind = 1`/`component_id` overrides so wrecks concretely
  hand out components, not just material.
- **Process miss, not a new discovery: `docs/gotchas.md` already documented
  "`.tscn` files have no comment syntax... silently reverts that property to
  its default" before this session** — this agent added `#` comments to 6
  enemy `.tscn` files anyway, hit exactly that bug (a comment left the very
  next property line at its script default, e.g. `component_drop_chance`
  stuck at 0.3 despite the file text clearly showing `0.45`), and only
  caught it because every override was live-verified via `game_eval`
  afterward rather than trusted from the file text. Fixed by removing every
  `#` comment from the 6 files; wreck-scene edits (no comments used) were
  unaffected. **Lesson: check `docs/gotchas.md` before hand-editing a
  `.tscn`, per this file's own opening instructions — don't rediscover a
  documented gotcha live.**

### Still open from this session
- Recipe ratios (1 output per craft, first-pass material costs),
  construction-cost splits for the 4 rewritten module types, repair's
  "half cost rounded up" rule, and the new per-archetype drop chances are
  all first-pass numbers reached by design reasoning, not real playtest —
  none of Phase 5's economy has been played by a human yet.
- No crafting/building/repair UI icon art — `MaterialType.icon`/
  `ComponentType.icon` both exist as unused placeholder fields.
- Scanner's construction cost uses raw `MaterialCatalog.GLASS` directly for
  the spec's "suitable transparent... component" line item rather than a
  dedicated 7th component — a deliberate scope call, not an oversight, but
  worth revisiting if a real sensor/lens component is ever needed elsewhere.
- Manufacturer-flavored owned-module keys exist (`owned_module_key` takes a
  manufacturer_id) but `repair_module()` only ever produces the generic
  (no-manufacturer) key — a repaired part is always generic, matching
  `Inventory._captured_tech_totals` itself having no manufacturer axis.
- The CraftingPanel/toggle_crafting **K** keybind could not be exercised via
  simulated key input in this MCP session (confirmed a pre-existing,
  environment-wide limitation — the already-shipped Cargo panel's **C** key
  showed the identical non-response — not a regression); panel visibility,
  row rendering, and the underlying craft/build/place/remove logic were all
  verified directly via `game_eval` instead.
- Only `derelict_station.tscn` (3 of 9) and the two small POI wrecks got
  hand-authored component drops this session — `PirateCamp`'s pirates
  inherit their drop table from whichever base pirate `.tscn` they
  instance, not a camp-specific table.

## Earlier sessions (compressed)

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

- **Phase 4.2 Raw materials + mining/collection economy tuning:** replaced
  generic mined scrap with a resource-driven Iron/Copper/Nickel/Titanium set
  (`MaterialType`/`MaterialCatalog`, mirrors `ModuleType`/`ModuleCatalog`,
  chosen to fully replace rather than coexist with the old Steel Alloy/
  Electronics/Reactor Components via `AskUserQuestion`). Each asteroid
  variant rolls one primary material most of the time
  (`Asteroid.roll_ore_material()`); combat kills drop 2–3 independently
  rolled pieces; `MaterialType.yield_multiplier` (material scarcity) and
  `Salvage.amount_multiplier` (per-source yield) are two orthogonal knobs
  multiplied together. Two rounds of live-playtest-driven tuning: mining
  filled cargo far too fast (`HardpointGrinder.fragment_yield_multiplier`
  1.5→0.5) and salvage collection felt wrong, reworked into
  `Ship.get_core_global_position()`-gated self-collection (must reach the
  Command Core specifically, not just graze the hull) plus
  `HardpointTractorBeam` pulling to its own Muzzle instead of the ship's
  center. Verified live via `game_eval` throughout.

- **Ship-builder hex preview art + single-hex Mining Grinder rework:** three
  user-reported follow-ups to the Mining Grinder. Builder placement preview
  now renders the real module texture (`hex_grid_control.gd`'s
  `set_preview()`/`_draw_preview()`) instead of a flat color swatch, with
  the green/red valid/invalid tint as a semi-transparent overlay. Grinder
  footprint shrunk 2 hexes → 1 (`ModuleCatalog.SINGLE_CELL`). Beam exit
  point moved from hex face-centre to hex vertex, then corrected once after
  landing on the wrong vertex — final formula is muzzle-local **-90°** at
  `cell_size * 1.15` reach, verified live via `game_eval` against the
  starter ship's real grinder. Confirmed again: `game_eval` multi-statement
  scripts need tabs, not spaces, or `EVAL_COMPILE_ERROR` (see
  `docs/gotchas.md`).

- **Phase 4.1 Basic Mining Grinder:** first version of the grinder — a
  2-cell hex module (later shrunk to 1, see the session above), modeled on
  `HardpointTractorBeam` but **player-toggled** (`Ship.toggle_grinder()`/
  `is_grinder_active()`, **G**) rather than always-on, since continuous
  damage needs deliberate activation. While toggled on and an `Asteroid` is
  within `contact_range` of the Muzzle: drains energy, applies damage via
  plain `Asteroid.take_damage()` (not `take_damage_at()` — no knockback
  while held, see "Decisions made"), and breaks off one `Salvage` ore
  fragment on a fixed interval — real `Salvage` nodes, so the whole existing
  Tractor Beam/cargo-capacity pipeline applied with zero new code. Weapons
  deliberately not nerfed — the grinder's edge was continuous partial yield
  vs. a gun's kill-only drop (numbers were later retuned twice, see the two
  sessions above). New `toggle_grinder` input (**G**). Follow-up bug hunt in
  the same session: user reported the beam exiting the wrong hex face —
  turned out the beam itself was correct; the ship-builder's rotation-arrow
  formula was the real mismatch, and per explicit user request the arrow
  formula itself was left as-is (reverted after a brief "fix") since its
  "always point up by default" UX mattered more than hex-exact accuracy —
  see "Decisions made" for the standing rule. Verified live end-to-end via
  godot-ai MCP throughout.
- **Storage capacity + Storage module (Phase 3.2/3.3):** cargo capacity on
  `Inventory` (`get_cargo_capacity()`/`get_cargo_used()`, recomputed by
  `Ship._apply_layout_cargo_capacity()` from `base_cargo_capacity` (100) +
  layout total). Two collection paths kept deliberately separate:
  `add_material()` stays uncapped (refunds/debug cheat/`GameState` restore,
  must never fail), `try_add_material()` is the only capacity-checked path
  (real Salvage pickup), emitting `storage_full` on rejection. `Salvage.gd`
  rejects cleanly instead of consuming — stays alive overlapping the ship,
  retries pickup every frame until space frees. New "Cargo Container" module
  (`storage_mk1`, +60 capacity, plain stat contributor like Reactor/Battery,
  not a hardpoint category). Ship builder blocks removing a Storage module
  if current cargo would exceed the reduced capacity. New dedicated Cargo
  screen (**C** key, not home-base-gated) + HUD `Cargo: used/capacity` +
  transient "STORAGE FULL" flash. Starter ship gained one Cargo Container
  (now 160 total capacity). Real gotcha hit and documented: editing a
  `.tres` on disk while the editor runs gets silently reverted by
  `project_run`'s default `autosave=true`. Verified live via MCP; ship-
  builder removal-block/stats-readout were code-reviewed only, not clicked
  through the actual UI.
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
working ship builder (save/load, build costs, energy stats), a resource-
driven raw-material economy (Iron / Copper / Nickel / Titanium, see below),
an energy system (reactors/batteries, thrust and weapon energy costs), a
4-archetype pirate AI (Raider/Gunship/Missile Boat/Scout) with an
Idle→Suspicious→Alert state machine, real per-module ship damage with wing
detachment, data-driven world regions, asteroid size tiers/splitting, better
AI navigation, a sweep-reveal radar paired with a long-range list scanner,
four basic points of interest (pirate camp, distress signal, abandoned
wreck, scenic formation), a single-target tractor beam that draws its
target all the way to the beam itself, cargo storage capacity with a
placeable Storage module, and a toggleable Mining Grinder that damages
asteroids and breaks off collectible ore fragments of the asteroid's own
material. **Version 0.1–0.4 of `Roadmap v.2-v.9.md` are done; Version 0.5
(reverse engineering + Manufacturers) has real substance but
Corporate/Ancient enemy ships are an explicitly deferred gap; Version 0.6
(trading, station, warp gates, new locations, nebula) is essentially
complete.** Radar (2.1), Scanner (2.2) and Points of Interest (2.3) are all
implemented from a user-supplied "Phase 2" spec that isn't part of either
tracked roadmap file; Tractor Beam (3.1), Storage capacity/module (3.2/3.3),
the Mining Grinder (4.1), and Raw Materials (4.2) are from a separate, later
user-supplied spec series (not either tracked roadmap file either) — see the
sessions above for their current shape; Radar/Scanner numbers were revised
multiple times in-session and are current, not first-draft. **Tractor Beam,
Radar, Scanner and the Mining Grinder are hex modules** rather than fixed
ship/HUD components — losing the hex disables the capability, and the
starter ship carries one of each so default play is unaffected. **Cargo
capacity is likewise a hex module** (Storage Container) but stacks
additively on top of a baseline rather than gating a capability on/off —
losing it just shrinks the cargo hold, it doesn't zero it out. The **Mining
Grinder is a single-hex module** that's still both a spawned world node
(like Tractor Beam) and player-toggled (**G**) rather than always-on — the
only hardpoint with either property alone, let alone both. **The old Steel
Alloy/Electronics/Reactor Components material set no longer exists anywhere
in the project** — it was fully replaced by Iron/Copper/Nickel/Titanium
(Phase 4.2), remapped across every build/upgrade/trade cost.
**Self-collecting salvage (no Tractor Beam) now requires actually touching
the Command Core, not just any hull hex** — a piece resting on an outer
module stays uncollected until it drifts further in. **Phase 5 (Crafting &
Construction Economy) is now implemented in full** — a user-supplied spec
series, not part of either tracked roadmap file, same as the Phase 2/3/4
specs before it: a crafting framework turning raw materials into 6
intermediate components (5.1), ship-builder module placement reworked from
"spend materials directly" to "own a built instance, place it for free"
(5.2), and combat/wreck salvage that can hand out raw materials, crafted
components, or damaged modules needing repair before use, instead of only
ever raw materials (5.3). See the sessions above for full detail; **the old
"spend build_costs at placement time" ship-builder model no longer
exists** — `ModuleType.build_costs` is now a construction cost spent only
when a module is *built* (crafted into owned stock), never at placement.
**Module upgrades are ship-wide**, built against
`docs/design_handoff_upgrade_tree/` and opened with the **U** key: seven
system trees (Hull, Propulsion, Weapons, Power, Storage, Sensors, Mining),
89 nodes, unlocks stored by id per category in `GameState`. The earlier
per-`ModuleInstance` upgrade system (Phase 8.1) and the ship-wide
`UpgradeManager`/`UpgradeCatalog` before it **both no longer exist anywhere in
the project**. **No upgrade changes ship behaviour yet** — the handoff authors
no stat modifiers, so unlocking spends resources and records the id and stops
there; the effects pass is the next piece of work and the user is writing the
upgrade list for it. See the Module upgrades section below for the wiring
points.

### Ship building (done, wired into the flyable ship)
- Hex-grid (axial coordinates) layout data model under `scripts/ships/...`:
  `module_type.gd`, `module_placement.gd`, `module_catalog.gd` (still a
  static prototype catalog, documented as a stand-in for real `.tres`
  resources), `ship_layout.gd` (place/remove/rotate, BFS connectivity,
  `validate_layout()`/`find_unreachable_from_core()`), `hex_utils.gd`,
  `ship_layout_renderer.gd`.
- `scenes/ui/ship_builder/` — rebuilt against
  `docs/design_handoff_ship_builder/`, which is the source of truth for its
  appearance. Full-screen (`CanvasLayer` layer 10 so it occludes the HUD):
  backdrop, top instruction line + HP/MASS/EN/CARGO strip, hex field, a 336px
  right column (Modules card, ship name + Save, collapsible Presets), and a
  bottom bar with the cell pill and ROTATE / REMOVE SELECTED / VALIDATE.
  `BuilderTheme` holds every colour and metric plus the StyleBox/font
  factories, and is shared with the upgrade screen. **R** rotates, **X**
  deletes. Any visible `"menu_panel"`-grouped CanvasLayer suspends
  `ship_input.gd` polling. The placement preview renders the actual module
  texture at the real placement rotation under a pulsing dashed cyan/red
  valid-invalid outline.
- **Phase 5.2 ownership model**: each module row is now **Craft** (spends
  `ModuleType.build_costs` — materials and/or crafted components, see
  Crafting below — to craft one owned-but-unplaced instance) plus
  **Select/Place** (free; disabled until at least one instance is owned;
  consumes one owned instance per placement). Removing a placed module
  returns it to owned stock, not a raw-material refund. Owned counts live on
  `Inventory` (`_owned_module_totals`, keyed by
  `Inventory.owned_module_key(module_type_id, manufacturer_id)`), not on
  `ShipLayout`/`ModulePlacement`. A fresh player ship is seeded with one
  owned instance of every starter-loadout module type
  (`Ship._seed_starter_owned_modules()`, first region of a session only) so
  stripping the starter ship down can never soft-lock rebuilding it.
  Research (permanently unlocks a locked type) and Repair (converts one
  captured/damaged part into an owned instance, see Salvage collection
  below) are two buttons in the selected row's expansion strip — a locked type can
  be researched without ever being repaired, and vice versa. Saving/loading
  custom ships to disk works (saves the placement layout only, not owned
  inventory).

### Economy / energy / cargo
- **Raw materials (Phase 4.2)**: `scripts/economy/material_type.gd`
  (`MaterialType extends Resource` — id/display_name/color/icon [unused
  placeholder]/sell_price/buy_price/yield_multiplier) +
  `scripts/economy/material_catalog.gd` (`MaterialCatalog`, same
  build-once-and-cache pattern as `ModuleCatalog`) replace the old static
  `Materials` script entirely. Exactly four materials —
  `MaterialCatalog.IRON`/`COPPER`/`NICKEL`/`TITANIUM` — with an ordered
  `ALL_IDS` array every UI panel/combat-drop roll iterates instead of a
  hardcoded list, so a future fifth material is a two-line addition. Rarer
  materials have a lower `yield_multiplier` (Titanium 0.45 vs. Iron 1.0),
  applied once in `Salvage._ready()` so it affects every source (mining,
  combat, asteroid kill-drops) automatically. `scenes/player/inventory.gd`
  (Dictionary-based multi-material pool, unchanged — already generic over
  material_id strings, no rewrite needed to support the swap).
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
  All buttons; the HUD's bottom-left `CargoWidget` chip shows a live
  `used/max` readout (its dropdown lists per-material counts), plus a
  transient "STORAGE FULL" flash. Ship builder blocks removing a Storage
  module if current cargo would exceed the reduced capacity.

### Crafting & construction economy (Phase 5)
- **Raw materials now include Glass** (`MaterialCatalog.GLASS`, 5th
  material) alongside Iron/Copper/Nickel/Titanium — no asteroid variant
  claims it as a primary, so it's only ever the existing uniform-random
  "otherwise" pick every variant already rolls among `ALL_IDS`.
- **Components** (`scripts/economy/component_type.gd`/`component_catalog.gd`):
  6 intermediate items — Metal Sheets, Wiring, Circuit Board, Reinforced
  Steel, Motor, Canister — held in their own `Inventory` pool
  (`_component_totals`) but sharing the same cargo capacity as materials.
  `ComponentCatalog.COMMON_IDS`/`RARE_IDS` group them by craft cost (single
  vs. double raw-material input) for combat-drop weighting.
- **Crafting** (`scripts/economy/crafting_recipe.gd`/`crafting_catalog.gd`,
  `scenes/ui/crafting_panel.gd`/`.tscn`, **K** key): one recipe per
  component, raw-materials-only inputs. `Inventory.can_craft()`/`craft()`
  check-then-atomically-spend inputs and produce output, blocked up front if
  cargo lacks room for the result — a craft never partially consumes.
  Quantity-selectable per recipe row; disabled when unaffordable.
- **Module construction**: see the Ship building section above —
  `ModuleType.build_costs` is now spent to *build* an owned instance, not to
  place one. Hull/Engine/Scanner/Storage use component-based costs (the
  spec's own examples); every other module type still costs plain raw
  materials.
- **Repair**: see the Salvage collection section below — converts a
  captured/damaged module part into a placeable owned instance.

### Module upgrades (ship-wide trees)

Source of truth: `docs/design_handoff_upgrade_tree/` (README + LAYOUT_SPEC +
`upgrade_data.json`). Read the whole folder before changing this screen.

- **Ship-wide, not per-module.** Seven systems (Hull, Propulsion, Weapons,
  Power, Storage, Sensors, Mining), one tree each, 89 nodes total. Guns and
  launchers are both "Weapons".
- **Content** is `res://resources/upgrades/upgrade_tree_data.json`, a verbatim
  copy of the handoff's `upgrade_data.json` minus its `_schema` block. Adding
  an upgrade is a data edit — no code enumerates nodes. Node fields:
  `id`/`tier`/`parents`/`label`/`glyph`/`desc`/`cost`, optional `icon` and
  `hue` (starts a coloured branch, inherited by descendants).
- **`ShipUpgradeCatalog`** loads it and resolves the handoff's display-string
  costs against `MaterialCatalog`/`ComponentCatalog` by display name, so they
  are spent from the real inventory. An unrecognised name warns rather than
  silently costing nothing.
- **`ShipUpgradeService`** is the whole rule: `is_unlocked` (root is always
  owned) and `is_available` (every parent unlocked). `parents` is an AND list;
  arity 2+ *is* the merge mechanic, there is no separate flag.
- **State** lives in `GameState` — `is_upgrade_unlocked`/`unlock_upgrade`/
  `get_unlocked_upgrades`, ids only, plus `last_upgrade_category`.
  Deliberately outside `capture()`/`apply()`: those mirror one ship across a
  warp, unlocks are player progression that outlives any hull.
- **UI**: `scenes/ui/upgrade_menu.gd` (`UpgradeMenu`, **U** key,
  home-base-gated, `CanvasLayer` layer 10 so it occludes the HUD) plus
  `scenes/ui/upgrades/` — `upgrade_palette.gd` (OKLCH→sRGB; a category's whole
  palette derives from one hue number), `upgrade_tree_layout.gd` (the polar
  fan: span allocation, mirroring in the right half, merges placed from their
  parents' angles at +0.4×STEP, label anchoring that flips near the arc ends),
  `upgrade_tree_view.gd` (drawing + hit-testing), `upgrade_rail_list.gd`,
  `upgrade_detail_panel.gd`. Surfaces/text/StyleBoxes come from the ship
  builder's `BuilderTheme` — same palette, deliberately shared.
- **Two invariants worth not breaking**: the view renders from
  `UpgradeTreeLayout.entries` only (it used to keep a parallel node list and
  crashed on a stale id when switching category mid-frame), and every tree is
  fitted against one shared reference frame (`UpgradeMenu._shared_frame()`) so
  node size doesn't change between systems.
- **Nothing an upgrade unlocks changes ship behaviour yet** — the handoff
  authors no stat modifiers. Unlocking spends resources and records the id.
  Effects hook into `ShipUpgradeService.unlock()`;
  `HardpointBank.apply_modifiers()` reaches an already-spawned hardpoint
  without rebuilding it, and `Ship._refresh_layout_stats()` re-derives
  aggregates without touching health or module condition (a full
  `_apply_ship_layout()` would heal the ship and reset every module).
- **Radar and Scanner still have no per-placement spawned node**
  (`Ship.has_radar()`/`has_scanner()` are boolean flags; `Scanner` is one
  fixed node on `ship.tscn`). Sensors effects will need a pull-at-point-of-use
  mechanism, not the push-at-spawn one everything else uses.

### Mining (Phase 4.1 Basic grinder, Phase 4.2 raw materials)
- `scenes/player/hardpoint_grinder.gd`/`.tscn`: a **single-cell** hex module
  (`hardpoint_category="grinder"`, `ModuleCatalog.SINGLE_CELL`),
  **player-toggled** via `Ship.toggle_grinder()`/`is_grinder_active()`
  (**G** — `ship_input.gd`), unlike every other passive hardpoint. While
  toggled on and an `Asteroid` is within `contact_range` (55, from the
  asteroid's own surface) of the Muzzle: drains `energy_cost_per_second` (7)
  from the shared pool, applies `damage_per_second` (14) via plain
  `Asteroid.take_damage()` (not `take_damage_at()` — no knockback while
  held), and breaks off one `Salvage` ore fragment every `fragment_interval`
  (1.0s) carrying whichever material `Asteroid.roll_ore_material()` rolls
  for that specific rock (see Raw materials below) at
  `fragment_yield_multiplier` (0.5 — deliberately *less* than a plain
  kill-drop per fragment; tuned down from an initial 1.5 after live feedback
  that mining filled cargo far too fast, see most recent session). Fragments
  are ordinary `Salvage` nodes — the Tractor Beam, self-collection, and
  cargo capacity all apply with zero extra code. Weapons aren't nerfed; the
  grinder's edge is the fragments accumulating throughout a grind on top of
  the asteroid's own final kill-drop, not any single fragment outsizing one.
  The Muzzle exits from a **hex vertex, not the hex's face centre** —
  `set_cell_size()` offsets it `cell_size * 1.15` at `-90°` off the module's
  own face-normal rotation, matching the ship builder's placement-facing
  arrow for the same `rotation_steps`. Starter ship carries one grinder at
  hex `(2,1)`/`rotation_steps=1`.
- **Raw materials (Phase 4.2)**: each `Asteroid` variant has one primary
  material (`VARIANT_PRIMARY_MATERIAL`: Rocky→Iron, Rusty→Copper, Icy→Nickel,
  Crystalline→Titanium), rolled `primary_material_chance` (0.8) of the time
  by the public `roll_ore_material()` (used by both the grinder's fragments
  and the asteroid's own on-death kill-drop, so a mined rock stays
  materially consistent with itself); otherwise a uniform-random pick among
  the other three.

### Salvage collection (Phase 3.1 Tractor Beam, Phase 3.2 capacity, Phase 4.1/4.2 mining + collection rework)
- `scenes/player/hardpoint_tractor_beam.gd`/`.tscn`: a hex module
  (`hardpoint_category="tractor"`), always active while mounted and intact,
  no player input. Locks onto the single nearest valid target (`Salvage` or
  `CapturedTechPart`, groups `"salvage"`/`"capturable_tech"`) within
  `max_range` (250) with a clear physics-raycast line of sight — **one
  target at a time by design**, framed as a future upgrade path (more
  simultaneous targets), not built. Costs energy/sec from the ship's shared
  pool while actively pulling. **Pulls the target all the way to this
  hardpoint's own Muzzle** (not the ship's center/hull, see most recent
  session) and collects it there via `Salvage.collect_for()` once within
  `salvage_collect_radius` (20) — a failed collection (full cargo) holds the
  target at the Muzzle and keeps retrying every frame rather than dropping
  it.
- Salvage can still self-collect without a Tractor Beam by physically
  touching the ship (`Area2D.body_entered`, `scenes/world/salvage.gd`), but
  **only once it actually reaches the Command Core specifically**
  (`Ship.get_core_global_position()`/`get_core_collect_radius()`, one
  hex-cell radius) — a piece merely touching an outer hull module doesn't
  collect, it sits there (`_pending_pickup_body` retried every frame,
  `_is_near_core()` gate) until it drifts further in or the ship moves away.
  This is the same retry mechanism a full cargo hold uses (both conditions
  are checked in the same loop): a piece is never silently dropped, just
  held pending until it's both near the Core and there's room for it.
- **Component salvage (Phase 5.3)**: `Salvage.kind` (MATERIAL | COMPONENT) —
  a component drop carries `component_id`/`component_amount` and collects
  through `Ship`/`Inventory`'s `try_add_component`/`add_component`, the
  parallel path to the material versions. Asteroid mining/`HardpointGrinder`
  fragments never set `kind`, so mining stays material-only by
  construction; components are combat/wreck-exclusive — see Combat below.
- **Damaged modules (Phase 5.3)**: a severed wing that survives with enough
  condition and passes `ModuleType.capture_chance` becomes a
  `CapturedTechPart` (pre-Phase-5 mechanic, `Inventory._captured_tech_totals`).
  It's structurally never placeable on its own — only
  `Inventory.repair_module()` (half the module's build cost, rounded up)
  converts one into a real owned instance; `research()` is the other, older
  way to spend one (permanently unlocks a locked type instead). Both draw
  from the same pool but are otherwise independent.

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
- **Phase 5.3 drop weighting**: each kill-drop rolls `Ship.
  component_drop_chance` for material-vs-component, then `rare_component_chance`
  for `ComponentCatalog.COMMON_IDS` vs. `RARE_IDS`. Both are per-instance
  `@export`s, hand-tuned per enemy `.tscn` (Scout/Light pirates 0.15/0.15 →
  Med 0.3/0.25 → Heavy 0.45/0.35 → Missile Cruiser 0.55/0.45 + a bumped 3–5
  drop count) — a harder kill pays out more/rarer components, not just more
  material. `PirateCamp` pirates inherit whichever base `.tscn` they
  instance; there's no camp-specific override.
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
  1800-unit range, "RANGE N" label under the circle, cyan per the 1d HUD
  spec, with one faint range ring per 1000 units of range (so an upgrade
  adds rings rather than rescaling fixed ones). Categories: Ship,
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

### Gameplay HUD (rebuilt to the "1d" spec)
`scenes/ui/hud.tscn` — a `CanvasLayer` with corner-anchored Control widgets,
24px margins, no fixed pixel layout. Appearance is governed by
`docs/HUD-1d-Godot-spec.md` + `docs/hud-1d-reference.png`, not by taste.
- `VitalsReadout` (top-left) — HP/EN dot+bar+number rows, `_draw`-based.
- `CargoWidget` (bottom-left) — `used/max` chip, click toggles an
  upward-growing material list. Subscribes to `Inventory` itself.
- `RadarDisplay` (bottom-right) and `ScannerDisplay` (top-right, below the
  credits label) — both still gate themselves on `Ship.has_radar()`/
  `has_scanner()` every frame.
- `CreditsLabel` (top-right), plus the pre-existing damage vignette and
  STORAGE FULL cue.
- `HudPalette` (`scenes/ui/hud_palette.gd`) is the one place HUD colours
  live — **except material dot colours, which come from
  `MaterialCatalog.color()` on purpose.**
- Known gaps: engine default font (the spec wants an embedded monospace
  `FontFile`; the project ships no `.ttf`), and the cargo dropdown uses the
  spec's flat tinted-glass fallback rather than a `BackBufferCopy` + blur
  shader.

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
- **The Mining Grinder's beam is the one exception that deliberately does
  chase the builder arrow's direction, in the opposite sense of the bullet
  above.** The arrow formula itself stayed untouched (per the decision
  above), but a later session moved the *grinder's own muzzle exit point* to
  the vertex that makes the beam visually line up with what the arrow shows
  — a real, user-reported "beam doesn't point where the arrow says" com-
  plaint, fixed by changing the grinder's geometry rather than the shared
  arrow. Live-verified twice via `game_eval` (a first attempt landed on the
  wrong adjacent vertex, 120° off, before the correct `-90°` muzzle-local
  angle was found) — see the hex-preview/grinder session for the derivation.
  Don't assume this generalizes to Winch or any other fixed-facing
  hardpoint; nothing else has been audited or requested.
- **Raw materials replace the old Steel Alloy/Electronics/Reactor Components
  set entirely, not alongside it.** Confirmed via `AskUserQuestion` before
  building — the alternative (keep the old 3 for building/trading, add the
  new 4 as mining-only) would have left 7 materials total and duplicated
  the "structural/electronics/rare" tiering for no real benefit. Every build
  cost, upgrade cost, and trade price was remapped, not left dual-tracked.
- **Material data is resource-driven (`MaterialType`/`MaterialCatalog`),
  mirroring `ModuleType`/`ModuleCatalog`'s existing "documented prototype
  catalog, not real `.tres` files yet" shape.** Adding a material should stay
  a two-line change (one id const, one `_make()` call) — don't hardcode a
  material list anywhere else; iterate `MaterialCatalog.ALL_IDS` instead.
- **Per-material yield_multiplier and per-source amount_multiplier are two
  separate, orthogonal knobs on Salvage's final amount, multiplied
  together.** yield_multiplier (on `MaterialType`) says "this material is
  scarce regardless of how you got it"; amount_multiplier (on `Salvage`,
  set by the spawner) says "this source yields more/less than baseline
  regardless of which material it happens to be." Don't conflate them when
  tuning — a "materials feel too rare/common" complaint is a
  yield_multiplier problem, a "this specific tool gives too much/little"
  complaint is an amount_multiplier problem.
- **The Mining Grinder's per-fragment yield is deliberately *smaller* than a
  weapon kill-drop's, not bigger.** An initial pass (`fragment_yield_
  multiplier` 1.5, an individual fragment briefly outyielding a kill-drop)
  was corrected to 0.5 after live feedback that mining one Large asteroid
  nearly filled the entire cargo hold in a single ~6s grind. The Grinder's
  edge over a gun is still real — fragments accumulate throughout a grind
  on top of the same final kill-drop every asteroid always releases — but
  it comes from the *total across a full grind*, not from any one fragment.
  If pacing needs to move again, tune `fragment_yield_multiplier` (chip
  size) or `fragment_interval` (chip frequency) on `HardpointGrinder`, not
  the shared `Salvage`/`MaterialType` yield math those other sources rely on
  too.
- **Plain hull-touch self-collection requires reaching the Command Core
  specifically; only a Tractor Beam can collect anywhere else (at its own
  Muzzle).** A user-reported complaint that salvage vanished the instant it
  grazed any outer hull hex. `Ship.get_core_global_position()` resolves the
  Core's actual position from `ship_layout.core_placement_id` rather than
  assuming it sits at the ship's local origin (it usually does, by the
  existing "ship origin = Core" convention, but the check doesn't rely on
  that). A side effect worth remembering: `is_dangerous` mine-style salvage
  can no longer detonate on a first graze against an outer module — it only
  triggers once something actually reaches the Core (or a Tractor Beam
  drags it to its Muzzle). Not requested, not treated as a problem, just a
  consequence of the same fix.
- **Ship-builder module placement is now free; owning a built instance is
  the gate (Phase 5.2).** Replaces the old "spend `build_costs` directly at
  placement" model entirely, not alongside it — mirrors the raw-materials
  "replace, don't dual-track" precedent above. `ModuleType.build_costs` is
  reinterpreted as a *construction* cost, spent only by the new Build
  action; Select/Place and Remove move an owned-instance count, never
  materials, directly.
- **Mining stays raw-material-only; crafted components are combat/wreck
  -exclusive (Phase 5.3).** A deliberate asymmetry, not an oversight —
  `Asteroid`/`HardpointGrinder` never set `Salvage.kind`, so a component
  drop can only ever come from a kill or a hand-placed wreck. This is what
  makes salvage a genuine *second* progression route rather than a faster
  version of mining, per the spec's own framing.
- **Repair and Research are two independent ways to spend one captured tech
  part, not a tiered upgrade of each other.** `research()` permanently
  unlocks a locked module *type* for building; `repair_module()` produces
  one *placeable instance* of any capturable type, locked or not. A type
  can be repaired from captured parts before it's ever researched (if it
  doesn't require research), or researched without ever being repaired.
  Both drain the same `_captured_tech_totals` count, so a part is spent by
  whichever the player picks — there's no rule forcing one before the other.
- **`.tscn` node property blocks cannot safely use `#` comments** — already
  documented in `docs/gotchas.md` before this session, re-confirmed the hard
  way while hand-tuning per-enemy drop-chance exports (a comment line
  silently corrupted the *next* property assignment, leaving it at the
  script default with no load error). Check `docs/gotchas.md` before
  hand-editing a `.tscn`, not after.
- **Module upgrades are ship-wide and driven entirely by
  `docs/design_handoff_upgrade_tree/`.** This is the third upgrade system the
  project has had: a ship-wide `UpgradeManager`/`UpgradeCatalog`, then
  per-`ModuleInstance` trees (Phase 8.1), now the handoff's seven system trees.
  The user corrected the third one into shape across several messages —
  the rail is the seven systems, each with **one** tree; there are no
  per-mounted-module rows and no separate "Missiles" category. Don't
  reintroduce either without a fresh request, and read the whole handoff
  folder (README, LAYOUT_SPEC, `upgrade_data.json`) before changing the screen
  — the first attempt went wrong precisely by implementing the layout spec
  while keeping the game's own content model.
- **Upgrade content is data, not code.** `resources/upgrades/
  upgrade_tree_data.json` is the whole tree; adding an upgrade is a data edit
  and nothing in code enumerates nodes. Keep it that way.
- **The upgrade menu is a dedicated `U`-key screen, not a button inside the
  ship builder.** Built inside the ship builder first; the user found that
  "clunky" and asked for its own key instead — a real, explicit UX correction,
  not a preference call made unprompted. Don't move upgrading back into the
  ship builder without a fresh request.
- **`Inventory`'s owned-module pool must stay a pool of real
  `ModuleInstance`s**, not a `Dictionary[key]->int` count. It was changed from
  counts for the per-instance upgrade system, and although that system is gone
  the pool is still what makes "remove a module and re-place it and it's the
  *same* module" true.
- **A narrow live stat refresh must never reach for the ship builder's full
  `_apply_ship_layout()`.** That call silently heals the ship to full and
  resets every module's condition — correct for "I just applied a rebuilt
  layout at the workbench," wrong for anything smaller.
  `Ship._refresh_layout_stats()` is the narrow path, and
  `HardpointBank.apply_modifiers()` is how a single stat reaches an
  already-spawned hardpoint. Any future live mutation of a running ship's
  stats should follow that shape.
- **Radar and Scanner cannot take push-at-spawn stat modifiers.** They're the
  only hardpoints with no per-placement spawned node (pure capability flags —
  see the Radar/Scanner decision entry above). Before authoring Sensors
  effects, give `Scanner`/`RadarDisplay` a way to pull their modifiers live at
  point of use.


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
  beyond losing the hex when destroyed. (Don't confuse with the new Phase
  5.3 `Inventory.repair_module()` — that converts a captured/damaged part
  into an owned instance, it's not a condition/HP repair-over-time system;
  no such system exists.)
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
- Auditing Weapon/Missile/Railgun/Winch hardpoints for the same builder-
  arrow-vs-real-facing mismatch the Grinder just had fixed — not reported as
  an issue for any of them, so left untouched.
- Visual confirmation (screenshot/live look) of the new texture-based ship
  builder placement preview — code-reviewed only so far.
- Material HUD/inventory icons — `MaterialType.icon` exists as a field but
  no art or UI wiring for it yet, per the 4.2 spec's own "will come later."
- Investigating why `Ship.toggle_grinder()` didn't reliably flip
  `_grinder_active` when called directly via `game_eval` (worked fine via
  direct field assignment) — noticed during live testing, not investigated,
  real "G" keypress input untested.
- Crafting/component/repair icon art — `MaterialType.icon`/`ComponentType.icon`
  both exist as unused placeholder fields, same as the earlier 4.2 material
  icon gap.
- A dedicated "sensor/lens" component for Scanner's construction cost —
  currently uses raw `MaterialCatalog.GLASS` directly instead of inventing a
  7th `ComponentCatalog` entry for one line item; revisit if a real
  sensor-type component is ever needed elsewhere.
- Manufacturer-flavored repair — `repair_module()` only ever produces the
  generic (no-manufacturer) owned key; `CapturedTechPart` does carry a
  `manufacturer_id` but `Inventory._captured_tech_totals` itself has no
  manufacturer axis to preserve it through repair.
- Per-camp or per-region drop-table overrides — `PirateCamp` pirates
  currently just inherit whichever base pirate `.tscn` they instance.
- Component drops for the other 6 of `derelict_station.tscn`'s 9 salvage
  nodes, and for `PirateCamp`/other POIs that still only drop material —
  only 3 of the 9 got hand-authored component overrides this session.
- **Stat effects for any upgrade** — all 89 nodes cost resources and unlock,
  and none of them change ship behaviour. This is the next planned piece and
  the user is authoring the upgrade list for it.
- Sensors effects specifically need a pull-at-point-of-use mechanism first —
  see "Decisions made" above for why Radar/Scanner are different from every
  other hardpoint, not just an oversight.
- Upgrade icon art — every node shows a 2-letter glyph; the data schema
  reserves an `icon` slot per node, sized at 52% of the node diameter.
- An embedded monospace font for the HUD — the 1d spec asks for one
  (JetBrains Mono / Space Mono as a `FontFile` resource); the project ships
  no `.ttf` at all, so the HUD currently uses the engine default. Dropping a
  font in and applying it is a small, self-contained job.
- A real blur behind the cargo dropdown (`BackBufferCopy` + blur
  `ShaderMaterial`) — the spec itself calls this optional polish and
  recommends the flat fallback that's in place.
- Restyling the remaining full-screen panels (Cargo/Trade/Crafting) to match
  the newer palette — the Builder and Upgrade screens have been rebuilt
  against their own design handoffs and share `BuilderTheme`, but the other
  three still use their older look.

## Suggested next step

No specific next item has been chosen yet. Candidates on the table, most
relevant first:
- **Wire stat effects to the upgrade trees.** The user is authoring the
  upgrade list; hooking it up is the agreed next task. Wiring points are in
  the Module upgrades section above. Until it's done, unlocking is a
  resource sink with no gameplay payoff.
- **Look at the two rebuilt screens and the HUD in motion.** The ship builder,
  the upgrade screen and the HUD were all verified by `game_eval` plus
  screenshots, but nobody has clicked through any of them with a real mouse —
  injected mouse events don't reach the viewport GUI in this MCP environment
  (see `docs/gotchas.md`). Cheap to confirm, and it gates further UI work.
- **A real human playtest of the refactor** — four tranches reshaped the ship's
  internals and every input path, verified only by scripted checks. Fly it,
  fight something, mine, build a ship, warp. This outranks everything below.
- **Commit tranche 4** if it is still uncommitted, and decide whether the
  deferred `LootTable` Resource (see tranche 3) is worth doing now.
- **Playtest the upgrade screen once effects exist** — the tree's costs and
  branch structure come straight from the design handoff and have never been
  balanced against the game's actual material economy.
- **A real human playtest of the whole Phase 5 crafting/construction/salvage
  economy** — recipe ratios, the 4 rewritten module construction costs,
  repair's half-cost rule, and every per-archetype drop chance are all
  first-pass numbers reached by design reasoning (see "Still open from this
  session" above), not a single minute of human play.
- **A real human playtest of the whole Phase 4.2 economy + collection
  rework** — raw material yield rates (`MaterialType.yield_multiplier`),
  the retuned Grinder fragment yield (0.5x), the Tractor-Beam-pulls-to-
  Muzzle change, and the Core-touch-required self-collection change were
  all verified via scripted `game_eval` checks this session (numeric
  before/after comparisons, distance checks), not flown by a human. Worth
  confirming mining pacing feels right now, and that requiring the Core
  specifically for un-beamed pickup doesn't feel punishing in practice.
- Playtest the Mining Grinder for real feel — `contact_range` (55),
  `damage_per_second` (14), and `energy_cost_per_second` (7) are still
  first-pass numbers (only `fragment_yield_multiplier`/`fragment_interval`
  were touched this session). Also worth deciding whether "one generic
  mining speed (upgradable?)" should get an actual upgrade tier now that
  the base tool exists.
- Material sell/buy prices and `yield_multiplier` values (Iron/Copper/
  Nickel/Titanium) are first-pass, not tuned against real trading play —
  worth a pass once the base collection rates above feel right.
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

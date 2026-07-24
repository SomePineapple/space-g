# Session Handover — Ship Building Prototype

Purpose: bring a fresh chat up to speed without re-deriving context. Read this,
`CLAUDE.md`, `roadmap.md`, and `vision.md` before continuing.

## Where things stand

The vertical slice has: flight movement, camera, asteroids, a pirate enemy
(spawn on demand), an upgrade-tree UI POC, and — the focus of the last few
sessions — a **ship-building prototype**: a hex-grid layout data model plus a
builder UI, fully standalone from the flyable ship for now.

### Ship building — Increment 1 (done)
Hex-grid (axial coordinates) layout data model:
- `scripts/ships/modules/module_type.gd` — reusable module definitions (Resource)
- `scripts/ships/modules/module_placement.gd` — one placed instance (id, type, hex coord, rotation)
- `scripts/ships/modules/module_catalog.gd` — **static prototype catalog**, explicitly documented as a stand-in for real `.tres` module resources later
- `scripts/ships/layout/ship_layout.gd` — authoritative layout: place/remove/rotate, connectivity (BFS from `core_placement_id`), `validate_layout()`
- `scenes/ui/ship_builder/hex_grid_control.gd` + `ship_builder_panel.gd` — custom-drawn hex grid UI, toggled with **B**
- `resources/ships/starter_ship_layout.tres` — read-only template; the panel duplicates it into an in-memory `working_layout` — **no persistence yet, by design**

### Ship building — Increment 2 (done)
Generalized the model from single-hex to **arbitrary multi-cell footprints**
(`ModuleType.footprint_cells`, rotated via new `scripts/ships/layout/hex_utils.gd`).
Added a directional **Weapon Hardpoint** (1x1, proves rotation matters) and a
**Heavy Hull** (3-cell strip, proves true multi-cell placement/overlap/connectivity).
All placement, removal, rotation, and connectivity checks now operate over full
footprints, not just anchor cells. Verified live via `game_eval` + screenshots.

### Placement preview (done, most recent work)
Added a live hover ghost while placing a module — green if the hovered
position is valid, red if not — with the status label always stating the
specific rejection reason (occupied cell, not adjacent, out of bounds, etc.).
The **Rotate** button is context-sensitive: rotates a selected *placed* module
if one is selected, otherwise rotates the *pending* (not-yet-placed) piece so
you can orient before clicking down. Fixed a bug along the way where
finishing a placement re-evaluated the now-stale hover position and stomped
the "Placed X." confirmation with a false rejection message.

### Enemy spawning (separate small feature, done)
Pressing **P** spawns a pirate enemy at a fixed position via `scenes/world/enemy_spawner.gd`,
replacing a previously-static enemy node in `map_tester.tscn`. Purely so testing
doesn't mean getting insta-killed on scene load.

## Decisions made (and why — don't relitigate without reason)

- **Ship-centric, not player-centric architecture.** Ship data lives under
  neutral `scripts/ships/...` / `resources/ships/...`, not `scenes/player/`.
  The ship-building system must work for any ship, not just the player's.
- **Hex grid with axial coordinates (`Vector2i`)**, not a square grid — was an
  explicit correction from an earlier rejected plan.
- **Template vs. working-copy split**: `template_layout` is loaded read-only;
  `working_layout` is a `.duplicate(true)` in-memory copy. Persistence is
  explicitly out of scope for the current increment — closing/reopening the
  panel in the same run may keep the draft, restarting the game resets it.
- **Static `ModuleCatalog` is a deliberate, documented prototype shortcut.**
  Do not let other systems assume a hard-coded catalog once real content grows
  — it should eventually be `.tres` resources under `resources/modules/`.
  This assumption is also documented directly in code comments.
- **Never silently no-op.** Every rejected action (place/remove/rotate) surfaces
  a specific reason string through the status label — a recurring, explicit
  user requirement, not incidental UI polish.
- **Exactly one Command Core** is enforced as a current layout rule, documented
  as prototype-specific rather than a permanent constraint for all future ship/faction types.
- **The ship builder is intentionally disconnected from the flyable `Ship`**
  for now — no visuals, collision, mass, power, or combat coupling yet. That
  wiring is a distinct future task requiring its own explicit go-ahead.
- **Increments must be small and individually verified** (per CLAUDE.md) — each
  increment above was implemented, tested live via the Godot MCP tools
  (`game_eval`, screenshots), and reported back before starting the next.

## Known MCP/tooling gotchas (only relevant if you use the godot-ai MCP tools)

- Avoid `for i in range(...)` loops inside `game_eval` test scripts — they can
  silently execute only once. Use sequential explicit statements instead.
- GDScript has no C-style ternary (`cond ? a : b`) — use `a if cond else b`.
  Using the wrong form in `game_eval` can leave the game in a persistent
  debugger "break" state; recover with `project_manage(op:"stop")` + `project_run`.
- The editor's log tracking can retain a **stale cached parse-error notice**
  referencing old code even after the file is fixed, surviving `logs_clear`
  and even restarts. Verify suspicious persistent errors with `Grep` across
  the actual file content and/or a functional `game_eval` call before
  believing the code is broken.

## Not yet started (no explicit user request yet — don't start without one)

- Wiring the `ShipLayout` into the actual flyable `Ship` (visuals, collision, stats)
- More module types / real data-driven (non-static) module catalog as `.tres` resources
- Persistence for the ship builder (saving a working layout to disk)
- Second enemy type, salvage collection, upgrade-tree wiring beyond the current POC
- Anything in `vision.md`'s longer-term sections (e.g. crew vision) — these are
  aspirational and explicitly out of scope until the current vertical-slice
  priorities in `roadmap.md`/CLAUDE.md's "Scope control" section are done.

## Suggested next step

Ask the user what's next — options likely include: wiring ship-builder layouts
into the actual ship, adding more module types/content, or moving to the next
roadmap milestone (salvage collection, per CLAUDE.md's scope-control ordering).
Do not assume; this file is context, not a task assignment.


# Godot/GDScript & MCP Tooling Gotchas

Durable technical gotchas confirmed through real sessions. Read before hitting
a similar wall — don't rediscover these from scratch. (Extracted from
`handover.md` to keep that file focused on session history.)

## GDScript / Godot behavior

- **Autoloads compile before other project global classes are guaranteed
  registered.** Typing an autoload's method params/returns as a project
  `class_name` (e.g. `Ship`, `ShipLayout`) can corrupt type resolution for
  that class *project-wide*, causing unrelated compile errors elsewhere (seen
  as a bogus error in `ship.gd` itself). Keep autoload script signatures
  untyped (`Node`/`Resource`/`Variant`) — normal, non-autoload scripts are
  fine with project types.
- **`.tscn` files have no comment syntax.** A `#` line before a property
  silently reverts that property to its default with no load error anywhere.
  Never write `#` comments into a `.tscn`.
- GDScript has no C-style ternary — use `a if cond else b`.
- **`Ship._hull_renderer.rotation` carries a real, measured `+90°` fixed
  offset** between the hex grid's authored axes and the ship's true
  movement-forward (`+X`) — not zero, despite no rotation ever being authored
  on the node in any `.tscn`. hex-grid-local `+Y` (a vertex) maps to true
  backward, not `-X`. Only ever apply this offset to a *position* transform
  (like `hex_center`/collision/hardpoints already do) — never to another
  node's own `rotation` property, since that node already inherits the ship's
  real rotation through the scene tree; adding the offset there double-
  applies it.
- **Constructing render resources (`Material.new()` etc.) fresh per-event
  instead of caching** forces the renderer to recompile a shader/pipeline
  variant on first draw — shows up as sustained multi-second stutters (flat
  draw-call/node counts, not a per-frame cost), not an obvious hot loop.
  Cache such materials as `static var`s and mutate properties in place rather
  than allocating new ones per use.
- `editor_manage(op="monitors_get")` reports the **editor process's**
  Performance singleton, not the isolated running game's (can be 100x the
  real node count). For real gameplay numbers, call
  `Performance.get_monitor(...)` via `game_eval` inside the running game.

## godot-ai MCP tool quirks

- **A brand-new asset file can silently fail to import** even after
  `filesystem_manage(op="scan")` + `reimport()` — `load()`/
  `ResourceLoader.exists()` return null/false, editor log shows `No loader
  found for resource ... (expected type: unknown)`. Diagnose with
  `filesystem_manage(op="search", name=<file>)`: a stuck file reports
  `"type": ""`. Fix: hand-write a minimal `.import` stub copied from a
  sibling file (keep `importer`/`type`, placeholder `uid=`/`dest_files=`),
  then `scan()` + `reimport()` — Godot overwrites the stub with the real
  `.ctex` path itself.
- **New sprite art often imports with `mipmaps/generate=false` by default**,
  silently defeating `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. Check `.import`
  files and flip to `true` + reimport whenever new art stops looking
  filtered/antialiased at zoom. Has recurred across multiple asset batches.
- **Editing `project.godot` directly on disk while the editor is running does
  not take effect**, and the next MCP write via `autoload_manage`/
  `input_map_manage` can silently overwrite the manual edit. Always use
  `autoload_manage`/`input_map_manage` for anything in `project.godot`;
  direct file edits are fine for `.tscn`/`.gd`.
- **One-line `for x in y: ...` / `if a: return b else: return c` control flow
  inside `game_eval` is unreliable** — can silently execute only once, or
  return wrong/empty results even when an equivalent count-only call is
  correct. Prefer `get_tree().get_nodes_in_group(...)`, direct indexed
  access, or multiple separate single-statement `game_eval` calls.
- A runtime error inside a `game_eval` script can park the running game in a
  debugger **"break" state**; every subsequent call then references the
  *old* stale error (including a live value looking "frozen" across polls)
  until `project_manage(op="stop")` + `project_run`.
- `game_eval` calls that `await` longer than ~8s are aborted (`EVAL_HUNG`)
  but the awaited code **keeps running in the live game regardless** — state
  can still change even though the call reports failure. Poll in ≤6-7s
  chunks, guard follow-up node access with `is_instance_valid()`.
- `input_action` only sets an action's pressed *state* — it does not dispatch
  a real `InputEvent`, so anything relying on `_unhandled_input` won't fire.
  Use `input_key` with the actual bound key instead.
- `get_tree().get_nodes_in_group()` order isn't guaranteed stable across
  calls — filter by `.name`, don't trust index 0.
- After editing an open scene's `.tscn`/resource file directly on disk, use
  `scene_open(force_reload=true)`.

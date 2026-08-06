# Multiplayer Foundations

**Status: no networking exists.** Nothing in the project opens a socket, and
`MultiplayerAPI` is untouched. What exists is a set of *seams* — places where
single-player assumptions were removed so that adding networking later is a
change to a few well-marked files rather than a rewrite.

This document records what those seams are, why they're shaped the way they
are, and — most importantly — **what is still single-player-only**, so nobody
mistakes a partially-prepared system for a ready one.

Read this alongside `handover.md`. Tranche 4 of the code review created
everything described here.

---

## The two intended modes

The design targets two shapes, and they pull in different directions. Nearly
every decision below exists because one shape alone would have permitted a
simpler (and wrong for the other) answer.

**Mode 1 — one ship per player.** Several `player_ship`-grouped ships in a
region, each commanded by one peer. The hard part is that "the player's ship"
stops being a single thing.

**Mode 2 — one ship, several players as crew.** One ship; each player occupies
a station (pilot, gunner, …) and may only command part of it. The hard part is
that "the player's input" stops being a single, complete command set.

---

## Seam 1: `ShipIntent` — commands as data, filtered by role

`scripts/ships/ship_intent.gd`

A ship is never commanded by calling methods on it. Every controller builds a
`ShipIntent` — thrust, turn, boost, aim, fire, lock, winch, scan, grinder — and
submits it:

```gdscript
ship.submit_intent(intent, roles)
```

`roles` is a bitmask of `ShipIntent.Role` (`HELM`, `WEAPONS`, `OPERATIONS`).
**The ship filters on arrival; it does not trust the sender.** Fields belonging
to roles the submitter doesn't hold are discarded. This is deliberately the
same operation an authoritative server needs, so `Ship.submit_intent()` is
already the single place a peer's claimed authority gets checked.

Consequences worth knowing:

- **Both modes fall out of the same mechanism.** Mode 1 is one full-role intent
  per ship. Mode 2 is several partial intents merged into one command set.
- **Player and AI are indistinguishable to the ship.** `ship_input.gd` and
  `ship_ai.gd` both just produce intents. A remote peer's intent is a third
  producer of the same thing.
- **Roles nobody submitted for are released each frame**
  (`ShipIntent.clear_roles`). A disconnecting helmsman does not leave the
  throttle latched open. This was a real bug caught in testing, and it is the
  behaviour a dropped connection depends on.
- **Controllers run at `process_physics_priority = -1`** so submissions land
  before the ship consumes them. Without this every input is a frame late.
- **Last submitter for a role wins within a frame.** Two controllers holding
  the same role on one ship is not resolved — it is not currently possible, but
  a lobby must not allow it.

Edge-triggered commands (fire, toggles, lock changes) are one-shot booleans
cleared after consumption; held states (thrust, turn, boost, winch reel) persist
until overwritten. `set_lock` is a separate flag from `locked_target` precisely
so "clear the lock" and "don't touch the lock" stay distinguishable — a
distinction a naive serialisation would lose.

## Seam 2: `PlayerContext` — which ship is *mine*

`scripts/player_context.gd` (autoload)

Twelve scripts previously did `get_tree().get_nodes_in_group("player_ship")[0]`.
That is wrong in mode 1 (arbitrary ship) and insufficient in mode 2 (right ship,
but no notion of which station). `PlayerContext` holds the local player's ship
and `local_roles`.

**The `player_ship` group still exists and is still correct** for questions
about *any* player ship. The distinction is the whole point:

| Question | Use |
| --- | --- |
| Which ship does this HUD/panel/camera belong to? | `PlayerContext.get_ship()` |
| Did a player ship enter this nebula / touch this salvage? | group / collision |
| Which player ship should this enemy target? | group, nearest |
| Which player ships must the region boundary contain? | group, **all of them** |

`region_boundary.gd` and `ship_ai.gd` were both changed to iterate the group
rather than take `[0]` — identical behaviour today, correct behaviour later.

Ship registration happens in `Ship._enter_tree()`, not `_ready()`, because every
node enters the tree before any node is readied. UI reading `get_ship()` from
its own `_ready()` therefore always finds it.

## Seam 3: `GameRng` — simulation randomness vs. decoration

`scripts/game_rng.gd` (autoload)

Named streams derived from one `session_seed`. A host would set the seed once
and send it to joining peers.

**The critical rule, which is easy to get wrong:** only *simulation* randomness
uses `GameRng`. Camera shake, starfield twinkle and particle jitter stay on the
global `randf()`. Not because syncing them is merely unnecessary — because
drawing them from a shared stream would advance it a different number of times
on each machine (different framerates, different things on screen) and desync
every simulation roll downstream. `camera_shake.gd` carries this comment at its
call site.

Streams are independent of each other, but **within** a stream results depend on
call order. That is acceptable for a server-authoritative model (one machine
rolls, the outcome replicates) and would not survive naive lockstep. For things
that genuinely need order-independence there is `GameRng.derive(name, salt)` for
per-entity seeds — the pattern world generation already used
(`RegionSpawner.random_seed` → per-asteroid seeds).

`GameRng.next_id()` replaced identifier generation that mixed in
`Time.get_ticks_usec()`. Wall-clock values can never agree between machines.

## Seam 4: `WorldSpawn` — one place objects enter the region

`scripts/world/world_spawn.gd`

Roughly eighteen copies of `get_tree().current_scene.add_child(thing)` became
`WorldSpawn.attach_at(thing, position)`. Spawns are where authority and
replication have to be enforced, and there was no single point to do it.

Purely local presentation deliberately does **not** route through here and must
not be replicated: Salvage's detached pickup sound, Nebula's fullscreen tint
layer, WarpGate's input-lock node. Each is commented at its site.

## Seam 5: `GamePanel` — UI bound to a context, not a lookup

`scenes/ui/game_panel.gd`

The five gameplay menus share layout, the `menu_panel` group, the home-base
gate, and ship/inventory binding. They bind through `PlayerContext` and rebind
on `ship_changed`, so a panel open across a warp follows the new ship instead of
holding a freed one. In mode 2 every station's panels resolve to the shared
ship automatically.

---

## What is still single-player-only

This is the important half of the document.

**`GameState` is one global snapshot.** `scripts/game_state.gd` holds one
inventory, one layout, one health fraction, carried across warps. Correct for
mode 2 (one ship, one shared hold). **Wrong for mode 1**, which needs
per-player state. This is the single largest remaining assumption.

**Warping is a full `change_scene_to_file`.** One machine's scene change cannot
be another's. Mode 1 needs either per-player region instances or a shared region
with per-player arrival; mode 2 needs the whole crew to move together. Neither
exists. See `warp_gate.gd`.

**No authority model at all.** Every client currently simulates everything
locally: damage resolution, module destruction, loot rolls, AI decisions. The
role filter in `submit_intent()` is the only authority check anywhere, and it
guards inputs, not outcomes.

**No replication of any kind.** No `MultiplayerSynchronizer`, no RPCs, no
spawner. `WorldSpawn` is the hook, unused.

**AI runs on every peer.** `ship_ai.gd` decides independently per machine. Even
with `GameRng` seeded identically, its decisions depend on physics state, which
will diverge. AI must become authority-owned.

**Physics is not deterministic** and should not be assumed to be. Godot's 2D
physics is not lockstep-safe across machines. Plan for state replication, not
input lockstep — this is why `ShipIntent` is shaped as a command set for an
authority rather than a lockstep input frame.

**Camera and input are singular.** One `ShipCamera` per player ship scene, one
`PlayerInput` node, one mouse. Mode 2 needs several stations on one ship, which
means either several `PlayerInput`-alikes with different roles (supported by the
intent seam) or split-screen (not considered).

**`local_roles` is set by nobody.** It defaults to all roles and there is no
lobby, assignment UI, or station concept in the world. The plumbing honours it;
nothing writes it.

**Crew stations do not exist as objects.** `ShipIntent.Role` is three flags. A
real crew mode needs stations as placeable things (a gunnery seat, a helm) tied
to modules, with occupancy — probably built on `ModulePlacement`.

---

## Practical notes for whoever picks this up

- The three role groups are a starting guess, not a design. Splitting
  OPERATIONS, or adding an ENGINEERING role once power routing or damage
  control exists, is expected. `merge_from`/`clear_roles` are the only two
  functions that need to know the field-to-role mapping.
- Adding an autoload requires more than editing `project.godot` — the running
  editor keeps its own `ProjectSettings`. Use the MCP's
  `project_manage(op="settings_set")` as well, or restart the editor. Both
  `PlayerContext` and `GameRng` were added this way.
- New `class_name` scripts are invisible until `filesystem_manage(op="scan")`
  runs with the game stopped. See `docs/gotchas.md`.
- Autoloads must not statically type-hint the project's global classes
  (`Ship`, `ShipLayout`, …). They compile before those are registered and doing
  so corrupts type resolution project-wide. `GameState`, `PlayerContext` and
  `GameRng` all use untyped `Node`/`int` for this reason, and `PlayerContext`
  duplicates `ShipIntent.ALL_ROLES` as the literal `7` — **keep those in step.**

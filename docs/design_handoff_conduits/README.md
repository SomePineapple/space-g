# Handoff: Conduits (automatic, function-coded wiring)

## Overview
Conduits are a new hex-tile type for the Corporate ship-building system: a lighter, open-scaffold hex that carries no module of its own — it only ever routes wire between the reactor and modules. Which colour wire runs through a given hex, and which of its 6 faces are live, is **computed automatically from ship layout**. There is no player assignment step and no player choice: a weapon is always wired red, a thruster is always wired green, a sensor/tractor/cutter is always wired blue, and the route is the shortest path of conduit hexes back to the reactor.

## About the design file
`Spaceship Hex Tiles.dc.html` is a **design reference built in HTML** (a "Design Component" from our design tool) — it is not production code to copy verbatim. It demonstrates the intended art (tile substrate, junction hub, module icons) and, in its script block, a **working reference implementation of the routing algorithm** (hex adjacency, BFS pathfinding, per-face wire-lane geometry). Treat the algorithm as a spec to reimplement in the game's own engine/language, and the SVG art as the visual spec to rebuild as real game assets (or use as-is if the game renders SVG/vector tiles).

## Fidelity
High-fidelity for color, geometry and the routing logic; the module icons standing in for weapon/thruster/sensor/reactor in the demo network are simplified stand-ins for the full catalogue art (which lives elsewhere in the same file) — reuse the full catalogue tiles for real modules, not the demo's compact icons.

## What's new in this file

### 1. The Conduit tile (`corporate_conduit`)
A lighter, open hex — thin scaffold, no plating fill, faint diagonal hatch — versus the heavy plated fill used on every module hex. Defined once in `<defs>` as `#hx-sub-conduit` and reused via `<use>`. Sits in the "Tile catalogue" grid next to `corporate_strut`.

### 2. The junction hub
Every conduit hex has a small **hex-shaped clamp block** at its centre (`#cd-hub` in `<defs>`): a riveted hex plate with a bolt at each of its 6 vertices. Around its 6 faces sit **18 fixed clamp holes** — 3 per face, one lane each for red/green/blue — so a given circuit colour always uses the same physical lane and never crosses another circuit inside the hub. Unused holes render as dark drilled metal; a hole with a circuit running through it fills with that circuit's colour.

The reactor module (`corporate_reactor_mk1`) got the same treatment: its outer ring is now a scaled-up version of the same hex clamp block (all 6 faces, full 3-lane grommet set), since the reactor is the origin of every circuit and should read as a conduit junction itself.

### 3. Wire rendering
A wire segment is drawn as 4 stacked strokes (see `sc-for list="{{ nd.spokes }}"` in the demo, or the reactor's static grommets): a dark recessed **channel** (13px, `#0d1116`), the coloured **cable** on top (9px), a small perpendicular **clamp tick** at the midpoint, and a thin **highlight** core (3px, a lighter tint of the circuit colour) that pulses opacity slowly (2.6–3.4s loop, staggered per colour) to read as "powered," matching the existing corner-beacon pulse convention elsewhere in the file.

**Wire only ever appears on the reactor and on conduit hexes** — a weapon/thruster/sensor module hex itself shows no wire; the module is the endpoint, not a length of cable.

## The routing algorithm (reference implementation in the `<script>` block)

- **Hex adjacency** — `CD_DIRS`: the 6 neighbour offsets for a flat-top hex of this tile's exact size (`[222,0]`, `[111,192]`, `[-111,192]`, `[-222,0]`, `[-111,-192]`, `[111,-192]`), indexed 0–5 clockwise from due‑east. `cdFindDir(a,b)` finds which of the 6 directions connects two adjacent hex centres.
- **Pathing** — `cdPath(nodes, byId, startId, endId)`: plain BFS from the reactor to a target module's id, over whatever nodes are hex-adjacent. Ship layout is just a list of `{id, x, y, type}` nodes in pixel/world space; adjacency is derived from position, not hand-authored.
- **Circuit assignment (fixed, no player input)** — a `targets` list maps each module id to its circuit colour by module *type*: weapons → `red`, propulsion/flight-control → `green`, utility (sensors/tractor/cutter) → `blue`. For each target, `buildConduitNetwork` walks its BFS path and marks, per hex and per direction, which colour(s) traverse that face.
- **Rendering data** — `buildConduitNetwork` turns that live-direction map into per-hex wire-segment geometry (`spokes`) and, for conduit hexes, the 18-hole grommet ring (`grommets`). Every colour has a **fixed lane offset** (`CD_SLOT = { red: -11, green: 0, blue: 11 }`) applied via a *canonical* perpendicular direction (folded to the 0/1/2 half of the 6 directions) — this is the key trick that keeps a wire in the same lane on both ends of a shared edge; using each node's own local direction angle instead causes the bundle to visibly flip/cross at the seam (a bug we hit and fixed during this session).
- **The branch behaviour requested**: when two modules of different colours share the same upstream path (e.g. a weapon and a thruster both routing back through the same conduit hex to the reactor), that shared hex's trunk-facing side carries both colours in their own lanes; at the hex where the paths actually diverge, one lane continues straight through to one module's face while the other lane exits toward the other module's face. Nothing is drawn as a single mixed colour — colours never blend, they run in parallel lanes and separate at the junction.

## Colours (fixed, not themeable per player)
- Red (weapons): cable `#c9433a`, highlight `#ff8f84`
- Green (propulsion & control): cable `#3f9a58`, highlight `#8fe8a8`
- Blue (utility — sensors, tractor, cutter): cable `#3f66c9`, highlight `#8fa8ff`

These are a fixed function code, intentionally distinct from any faction's accent colour (Corporate's own accent cyan is a different hue, ~190°, so it's never confused with the blue utility circuit, ~230°).

## Tweaks exposed in the design file (for exploring the system, not shipped player settings)
- `showRedCircuit` / `showGreenCircuit` / `showBlueCircuit` (booleans) — isolate one circuit at a time in the demo network.
- `conduitFlowAnim` (boolean) — toggle the "powered" pulse.
- Pre-existing: `showGuides`, `showLabels`, `scarLevel`, `hitState`, `hitCount` (unrelated battle-damage system, untouched).

## Demo network (in the file, section "Conduits — automatic, function-coded wiring")
A worked example proving the branching behaviour: Reactor → conduit hex A carries **red+green** together (it feeds both a weapon and a thruster downstream); at A the lanes separate — red continues straight to the weapon, green turns off to the thruster. A second, simpler run — Reactor → conduit hex B → sensor — carries **blue only**, showing the plain pass-through case. Node/target list lives in `renderVals()` as `cdNodes` / `cdTargets`; swap in real ship layouts there to try other topologies.

## Files
- `Spaceship Hex Tiles.dc.html` — the full design reference: tile catalogue (including the new `corporate_conduit` tile and the updated `corporate_reactor_mk1`), the Conduits demo network, and the reference routing algorithm described above.

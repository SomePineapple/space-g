class_name PowerGrid
extends RefCounted

## Which parts of a hull have a power path back to a reactor, and the route each
## one takes. Pure data — no nodes, no drawing — so the ship builder's overlay and
## anything the game grows later read the same answer from the same place.
##
## The model, from docs/spaceg-phase-4-spec-rev3.md §4: a module is powered if a
## structural path exists through occupied hull cells back to a reactor. No
## conduits, no junctions, no routing UI — this is the connectivity graph the hull
## already has, walked from a different starting point.
##
## **Structure conducts; modules are leaves.** A gun, a core or a thruster can be
## *fed* by an adjacent conductor but does not pass power on. That distinction is
## the load-bearing part of the whole model and it is not cosmetic: power and
## attachment are measured over the same hexes, so if every part conducted, "this
## gun has one power path" and "this gun hangs on by one cell" would be the same
## statement — and cutting that cell would knock the gun off into space rather
## than leaving it dark and attached, which is a different mechanic entirely.
## Making only structure conduct is what prises the two graphs apart.
##
## Attachment is still measured from the *core* (ShipLayout.find_unreachable_from_core).
## Power is measured from the *reactors*. Two graphs, deliberately.

## Part types that pass power along rather than only consuming it.
##
## **Only the Conduit** (docs/design_handoff_conduits/). Plating carries no
## circuit: armour is armour, and if it also carried power for free then wiring
## would never be a decision, because a hull is made of plating by definition.
##
## This is what puts a real cost on reach. A part bolted straight onto the
## reactor needs no wiring at all, so a compact ship is cheap to power; a limb
## needs a conduit run out to it, and every cell of that run is a cell not
## spent on armour, and a thinner, softer line for someone to cut. That is the
## blob-versus-limbs trade from the Phase 4 spec §4, paid for in hexes rather
## than asserted.
##
## The Conduit is deliberately not *only* wire — it is a light structural hex
## too, so a run is partial hull rather than a pure tax. It just cannot take a
## hit like plating can, which is the whole reason to armour around it.
##
## Matched by id rather than by a flag on ModuleType because the set is one
## entry. Revisit if a second conductor is ever authored.
const CONDUCTING_TYPE_IDS: Array[String] = [ModuleCatalog.CONDUIT_TYPE_ID]


## The three function circuits (docs/design_handoff_conduits/README.md §Colours).
## Fixed by what a part *does*, never chosen: a weapon is always red, a thruster
## always green, a sensor always blue. There is no player assignment step.
enum Circuit {RED, GREEN, BLUE}

## Cable and highlight per circuit, straight from the handoff. Deliberately
## distinct from any faction accent — Corporate's cyan sits at ~190 degrees and
## the utility blue at ~230, so the two never read as the same wire.
const CIRCUIT_CABLE: Array[Color] = [
	Color("#c9433a"), Color("#3f9a58"), Color("#3f66c9"),
]
const CIRCUIT_HIGHLIGHT: Array[Color] = [
	Color("#ff8f84"), Color("#8fe8a8"), Color("#8fa8ff"),
]
## The recessed channel every cable is bedded into.
const WIRE_CHANNEL_COLOR: Color = Color("#0d1116")

## Which side of the run each circuit's lane sits on. Red one way, blue the other,
## green straight down the middle. Read off the reactor's grommet ring, which
## paints its three holes in exactly this order.
const CIRCUIT_LANE_SIGN: Array[float] = [-1.0, 0.0, 1.0]

## Where each tile physically clamps a cable, as fractions of the hex's
## circumradius: how far out along the face normal the clamp sits, and how far the
## red and blue lanes sit either side of green.
##
## **Measured off the art, per tile, and the two deliberately disagree.** The
## reactor's ring is a scaled-up clamp block, so its three holes sit 0.109R apart
## at a reach of 0.677R; the conduit's hub is a small hex whose 18 holes sit on its
## own six edges, 0.086R apart at an apothem of 0.246R. One shared lane constant —
## which is what the handoff's CD_SLOT amounts to — cannot land in both rings, and
## whichever end it misses gets a cable stopping beside its socket instead of in
## it.
##
## This is also why a run is drawn clamp-to-clamp as one straight stroke rather
## than as two half-segments meeting at the shared edge: each half would be
## perfectly straight and they would still kink where they met, because they are
## aiming at lanes of different widths.
const REACTOR_HUB_REACH: float = 0.6765
const REACTOR_HUB_LANE: float = 0.1093
const CONDUIT_HUB_REACH: float = 0.2462
const CONDUIT_HUB_LANE: float = 0.0861

## Stroke widths at the art's own tile scale: recessed channel, cable, highlight
## core.
##
## The handoff quotes 13/9/3. The cable is 8 here because that is the measured
## diameter of the holes it has to pass through (0.059R), and the channel is 11
## because 13 is wider than the 0.086R pitch between the conduit's lanes — three
## live circuits on one face merged into a single dark trench instead of reading as
## three cables in three holes.
const CD_TILE_WIDTH: float = 222.0
const WIRE_CHANNEL_WIDTH: float = 11.0
const WIRE_CABLE_WIDTH: float = 8.0
const WIRE_HIGHLIGHT_WIDTH: float = 3.0


## Which circuit a part sits on. Green covers control as well as propulsion, so
## the core rides the same lane as the thrusters — it is the flight-critical
## circuit, which is the distinction that matters when one is cut.
static func circuit_for(placement: ModulePlacement) -> int:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return Circuit.BLUE
	if placement.module_type_id == ModuleCatalog.CORE_TYPE_ID:
		return Circuit.GREEN
	if module_type.hardpoint_category == "weapon" or module_type.hardpoint_category == "missile":
		return Circuit.RED
	if module_type.thrust_contribution > 0.0:
		return Circuit.GREEN
	return Circuit.BLUE


## One part's supply line: the placement it feeds and the cell-by-cell route back
## to the reactor that feeds it. `cells[0]` is always a reactor cell and the last
## entry is the powered part's own cell, so the route reads outward from the
## source — which is the direction the builder's overlay animates.
class Route extends RefCounted:
	var placement_id: String = ""
	var cells: Array[Vector2i] = []


## One cable run between two adjacent hexes: which circuit it carries, which two
## cells it spans, and what hardware sits at each end.
##
## No geometry is stored here — see segment_ends(), which derives both ends from
## the measured hub constants, so the art is described in exactly one place.
class Segment extends RefCounted:
	var circuit: int = Circuit.BLUE
	var from_cell: Vector2i = Vector2i.ZERO
	var to_cell: Vector2i = Vector2i.ZERO
	## from_cell's face index pointing at to_cell (see HexUtils.EDGE_DIRECTIONS).
	var face: int = 0
	var from_reactor: bool = false
	var to_reactor: bool = false
	## Whether the far end is more cabling (so the run carries on into its clamp)
	## rather than the module being fed (so it stops at the shared edge).
	var to_hardware: bool = false


## Everything the overlay needs, computed in one walk: which placements are live,
## which are cold, and how the live ones are fed.
##
## `destroyed_ids` lets a caller exclude parts that are already wreckage. The ship
## builder passes nothing (a layout on the bench has no battle damage); the live
## game would pass HullDamageModel's set.
static func solve(layout: ShipLayout, destroyed_ids: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"routes": [], "powered_ids": {}, "unpowered_ids": {}, "reactor_ids": {}, "wire": [],
	}
	if layout == null:
		return result

	# cell -> the cell power arrived from. A reactor cell points at itself, which
	# is what terminates the walk back in _route_from().
	var came_from: Dictionary = {}
	var frontier: Array[Vector2i] = []
	var powered_ids: Dictionary = result["powered_ids"]
	var reactor_ids: Dictionary = result["reactor_ids"]

	for placement in layout.placements:
		if destroyed_ids.has(placement.placement_id) or not _is_reactor(placement):
			continue
		reactor_ids[placement.placement_id] = true
		powered_ids[placement.placement_id] = true
		for cell in layout.get_occupied_cells(placement):
			came_from[cell] = cell
			frontier.append(cell)

	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for neighbor in HexUtils.neighbors(cell):
			if came_from.has(neighbor):
				continue
			var occupant: ModulePlacement = layout.get_placement_at(neighbor)
			if occupant == null or destroyed_ids.has(occupant.placement_id):
				continue
			came_from[neighbor] = cell
			powered_ids[occupant.placement_id] = true
			if _conducts(occupant):
				frontier.append(neighbor)

	# Routes and warnings are for *consumers* only — the parts that would go dark.
	# Structure is not "unpowered" in any sense a player can act on: a hull plate
	# with no reactor path is just a hull plate, and drawing a supply line to one,
	# or flagging it as dead, buries the parts that matter under noise. This was
	# measured rather than assumed: a perfectly ordinary hull put seven plates in
	# the warning list and one gun.
	#
	# Breadth-first, so the first cell of a part that the walk reaches is also its
	# shortest route home — which is the one worth drawing.
	var claimed: Dictionary = {}
	for placement in layout.placements:
		if destroyed_ids.has(placement.placement_id) or not _draws_power(placement):
			continue
		if not powered_ids.has(placement.placement_id):
			result["unpowered_ids"][placement.placement_id] = true
			continue
		if claimed.has(placement.placement_id):
			continue
		for cell in layout.get_occupied_cells(placement):
			if not came_from.has(cell):
				continue
			var route := Route.new()
			route.placement_id = placement.placement_id
			route.cells = _route_from(cell, came_from)
			result["routes"].append(route)
			claimed[placement.placement_id] = true
			break

	result["wire"] = _build_wire(layout, result["routes"], reactor_ids)
	return result


## Every cable run this hull carries: one Segment per traversed edge per circuit.
##
## **Wire is only ever drawn on a conduit or the reactor.** A weapon or thruster
## hex is the endpoint, not a length of cable, so the last run of a route stops at
## the shared edge — see the handoff, §Wire rendering.
##
## Recorded once per edge rather than once per hex per face. The two hexes either
## side of a seam used to each draw their own half; now that the reactor and the
## conduit are known to clamp at different lane widths, halves cannot be made to
## meet, so a run is one stroke that knows both of its own ends.
##
## Routes share their upstream cells, so the same edge is reached repeatedly for
## the same circuit — deduplicated by edge. The walk in solve() is a tree, so no
## edge is ever traversed in both directions and the key needs no ordering.
static func _build_wire(layout: ShipLayout, routes: Array, reactor_ids: Dictionary) -> Array:
	var segments: Array = []
	var seen: Dictionary = {}
	for route: Route in routes:
		var consumer: ModulePlacement = layout.get_placement_by_id(route.placement_id)
		if consumer == null:
			continue
		var circuit: int = circuit_for(consumer)
		for i in route.cells.size() - 1:
			var key: Array = [route.cells[i], route.cells[i + 1], circuit]
			if seen.has(key):
				continue
			seen[key] = true
			var segment: Segment = _build_segment(
				layout, reactor_ids, route.cells[i], route.cells[i + 1], circuit)
			if segment != null:
				segments.append(segment)
	return segments


static func _build_segment(layout: ShipLayout, reactor_ids: Dictionary,
		from_cell: Vector2i, to_cell: Vector2i, circuit: int) -> Segment:
	var from_part: ModulePlacement = layout.get_placement_at(from_cell)
	var to_part: ModulePlacement = layout.get_placement_at(to_cell)
	if from_part == null or to_part == null:
		return null
	var face: int = HexUtils.EDGE_DIRECTIONS.find(to_cell - from_cell)
	if face < 0:
		return null

	var segment := Segment.new()
	segment.circuit = circuit
	segment.from_cell = from_cell
	segment.to_cell = to_cell
	segment.face = face
	segment.from_reactor = reactor_ids.has(from_part.placement_id)
	segment.to_reactor = reactor_ids.has(to_part.placement_id)
	segment.to_hardware = segment.to_reactor or _conducts(to_part)
	# The near end has to be hardware for there to be a clamp to leave from. Every
	# route out of solve() already satisfies this — it starts on a reactor and only
	# ever steps through conductors — so this is the rule stated where it is relied
	# on rather than a case that arises.
	if not segment.from_reactor and not _conducts(from_part):
		return null
	return segment


## Outward unit vector for one of the six faces. Edge `i`'s midpoint lies at
## 60*i degrees (see HexUtils.EDGE_DIRECTIONS).
static func face_normal(face: int) -> Vector2:
	var angle: float = deg_to_rad(60.0 * face)
	return Vector2(cos(angle), sin(angle))


## The perpendicular a lane is measured along.
##
## **Folded to one of three axes rather than taken from the face's own angle.**
## Faces 0-2 and faces 3-5 are the same three axes walked in opposite directions,
## so folding the index by 3 gives both hexes either side of a shared edge the same
## perpendicular — and therefore the same lane for the same colour. Using each
## hex's own outward angle makes the bundle visibly flip and cross at every seam;
## the handoff records hitting exactly that bug and fixing it this way, and the
## reactor art is painted to match: its red grommet sits 9.2 degrees clockwise of
## faces 0-2 and 9.2 anticlockwise of faces 3-5, which is the same physical side of
## the ship both times.
static func canonical_perp(face: int) -> Vector2:
	var angle: float = deg_to_rad(60.0 * (face % 3) + 90.0)
	return Vector2(cos(angle), sin(angle))


## Where one circuit's cable is clamped on this tile for the run leaving through
## `face`, relative to the hex centre — the reactor's grommet ring or the conduit's
## junction hub, whichever this tile actually draws.
static func hub_point(face: int, circuit: int, cell_size: float, is_reactor: bool) -> Vector2:
	var reach: float = REACTOR_HUB_REACH if is_reactor else CONDUIT_HUB_REACH
	var lane: float = REACTOR_HUB_LANE if is_reactor else CONDUIT_HUB_LANE
	return (face_normal(face) * reach
		+ canonical_perp(face) * CIRCUIT_LANE_SIGN[circuit] * lane) * cell_size


## Where a run stops when the far side is the module being fed rather than more
## cabling: on the shared edge, still in the lane the conductor clamped it into, so
## the last stretch stays parallel to whatever else shares the face instead of
## splaying across it.
static func edge_point(face: int, circuit: int, cell_size: float, from_reactor: bool) -> Vector2:
	var lane: float = REACTOR_HUB_LANE if from_reactor else CONDUIT_HUB_LANE
	return (face_normal(face) * (HexUtils.SQRT3 * 0.5)
		+ canonical_perp(face) * CIRCUIT_LANE_SIGN[circuit] * lane) * cell_size


## The two ends of one run, given both its cells' centres in whatever space the
## caller draws in.
##
## One straight line, clamp to clamp. The conduit art runs its own spokes dead
## straight out to each face and the holes at both ends are fixed hardware, so a
## curve between them can only miss the holes it is aiming at.
static func segment_ends(segment: Segment, from_centre: Vector2, to_centre: Vector2,
		cell_size: float) -> PackedVector2Array:
	var start: Vector2 = from_centre + hub_point(
		segment.face, segment.circuit, cell_size, segment.from_reactor)
	if segment.to_hardware:
		return PackedVector2Array([start, to_centre + hub_point(
			(segment.face + 3) % 6, segment.circuit, cell_size, segment.to_reactor)])
	return PackedVector2Array([start, from_centre + edge_point(
		segment.face, segment.circuit, cell_size, segment.from_reactor)])


## Handoff stroke widths scaled to this hull's cell size.
static func wire_width(base_width: float, cell_size: float) -> float:
	return maxf(base_width * (HexUtils.SQRT3 * cell_size) / CD_TILE_WIDTH, 1.0)


## Walks the came-from chain back to the reactor cell that seeded it, then flips
## it so the route reads source-first.
static func _route_from(cell: Vector2i, came_from: Dictionary) -> Array[Vector2i]:
	var reversed_cells: Array[Vector2i] = [cell]
	var current: Vector2i = cell
	while came_from.has(current) and came_from[current] != current:
		current = came_from[current]
		reversed_cells.append(current)
	reversed_cells.reverse()
	return reversed_cells


static func _is_reactor(placement: ModulePlacement) -> bool:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	return module_type != null and module_type.energy_generation > 0.0


static func _conducts(placement: ModulePlacement) -> bool:
	return CONDUCTING_TYPE_IDS.has(placement.module_type_id)


## Parts that have something to lose by going dark: the core, anything with a
## hardpoint on it, anything that pushes, and anything that stores charge.
##
## Derived from what a part *does* rather than from "isn't a conductor". Those
## were the same test while plating conducted, and stopped being the same test the
## moment it didn't — at which point every hull plate started reporting itself as
## an unpowered consumer, which is both wrong and alarming. Armour is inert: it
## neither carries a circuit nor wants one.
static func _draws_power(placement: ModulePlacement) -> bool:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return false
	# A reactor is the source. It carries charge capacity of its own, which would
	# otherwise class it as something needing to be fed — and it would then draw a
	# supply line from itself to itself.
	if _is_reactor(placement):
		return false
	if placement.module_type_id == ModuleCatalog.CORE_TYPE_ID:
		return true
	return not module_type.hardpoint_category.is_empty() \
		or module_type.thrust_contribution > 0.0 \
		or module_type.energy_capacity_contribution > 0.0


## How far each span bows off the straight line between two cell centres, as a
## fraction of that span's length.
##
## Without this a run along one hex row is perfectly straight, because a spline
## through collinear points is a line — which reads as the grid the route was
## derived from rather than as cabling laid through a hull. The bow is applied to
## one consistent side, so a multi-cell route arcs like slack rather than
## zig-zagging. Small on purpose: the line must still obviously pass through the
## cells it actually routes through.
const BOW: float = 0.11


## A rounded polyline through the given points, as a Catmull-Rom spline sampled
## `segments` times per span, bowed so straight runs still curve.
static func smooth(points: PackedVector2Array, segments: int = 8) -> PackedVector2Array:
	if points.size() < 2:
		return points

	# Every span gains a displaced midpoint, and the spline is run through those
	# too — so the curve is forced off the straight line without ever leaving the
	# cells at either end.
	var bowed := PackedVector2Array()
	for i in points.size() - 1:
		bowed.append(points[i])
		var span: Vector2 = points[i + 1] - points[i]
		bowed.append(points[i] + span * 0.5 + span.orthogonal() * BOW)
	bowed.append(points[points.size() - 1])
	points = bowed

	var curved := PackedVector2Array()
	for i in points.size() - 1:
		# Ends are duplicated rather than extrapolated, so the spline starts and
		# finishes exactly on the reactor and the part instead of overshooting them.
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		for step in segments:
			curved.append(_catmull_rom(p0, p1, p2, p3, float(step) / float(segments)))
	curved.append(points[points.size() - 1])
	return curved


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Where along a polyline a given fraction of its total length falls. Used to run
## a pulse outward from the reactor, which is what tells the player which end of
## the line is the source.
static func point_at(polyline: PackedVector2Array, fraction: float) -> Vector2:
	if polyline.is_empty():
		return Vector2.ZERO
	if polyline.size() == 1:
		return polyline[0]

	var total: float = 0.0
	for i in polyline.size() - 1:
		total += polyline[i].distance_to(polyline[i + 1])
	var target: float = total * clampf(fraction, 0.0, 1.0)

	var travelled: float = 0.0
	for i in polyline.size() - 1:
		var span: float = polyline[i].distance_to(polyline[i + 1])
		if travelled + span >= target:
			var into: float = (target - travelled) / span if span > 0.0 else 0.0
			return polyline[i].lerp(polyline[i + 1], into)
		travelled += span
	return polyline[polyline.size() - 1]

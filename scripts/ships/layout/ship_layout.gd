class_name ShipLayout
extends Resource

@export var placements: Array[ModulePlacement] = []
@export var core_placement_id: String = ""

## Derived lookup tables, rebuilt lazily from `placements` — never exported,
## never part of this Resource's saved/duplicated data. get_placement_at()/
## is_occupied()/get_occupied_cells() used to be O(placements x cells) with a
## linear ModuleCatalog scan inside, and they sit under per-hit damage
## resolution, the ship builder's hover redraw and Ship.get_layout_extent().
var _cell_index: Dictionary = {}          # Vector2i -> ModulePlacement
var _placement_index: Dictionary = {}     # String (placement_id) -> ModulePlacement
var _cells_by_placement: Dictionary = {}  # String (placement_id) -> Array[Vector2i]
## Circuit membership, derived from placements' circuit_id the same lazy way and
## invalidated by the same call — there is no second list of circuits to keep in
## step with this one, which is the point of deriving it (see
## ModulePlacement.circuit_id).
var _circuit_members: Dictionary = {}     # String (circuit_id) -> Array[ModulePlacement]
var _circuit_source_ids: Array[String] = []
var _index_dirty: bool = true
## The exact `placements` array the tables above were built from. A
## duplicate()d ShipLayout (warp restore, ship builder's working copy) gets a
## brand-new array, so comparing identity here catches that case even if the
## stale tables were copied across with it — see _ensure_index().
var _indexed_source: Array = []


## Call after mutating `placements` (or a placement's hex_coord/rotation_steps)
## from outside this class. Every mutator in here already does.
func invalidate_index() -> void:
	_index_dirty = true


func _ensure_index() -> void:
	if not _index_dirty and is_same(_indexed_source, placements):
		return

	_cell_index.clear()
	_placement_index.clear()
	_cells_by_placement.clear()
	_circuit_members.clear()
	_circuit_source_ids.clear()

	for placement in placements:
		_placement_index[placement.placement_id] = placement
		var cells: Array[Vector2i] = _compute_occupied_cells(placement)
		_cells_by_placement[placement.placement_id] = cells
		for cell in cells:
			_cell_index[cell] = placement
		if is_circuit_source(placement):
			_circuit_source_ids.append(placement.placement_id)

	# Sources first, so a circuit with no members still gets an (empty) entry and
	# every circuit id in _circuit_source_ids is a valid key below.
	_circuit_source_ids.sort()
	for source_id in _circuit_source_ids:
		_circuit_members[source_id] = [] as Array[ModulePlacement]
	for placement in placements:
		if placement.circuit_id.is_empty() or is_circuit_source(placement):
			continue
		if _circuit_members.has(placement.circuit_id):
			_circuit_members[placement.circuit_id].append(placement)

	_indexed_source = placements
	_index_dirty = false


func total_mass() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			total += module_type.mass_contribution + _manufacturer_stat_delta(placement, "mass_contribution")
	return total


func total_max_health() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			total += module_type.health_contribution
	return total


func total_thrust() -> float:
	var total: float = 0.0
	for placement in placements:
		total += thrust_for(placement)
	return total


## One placement's effective thrust. Split out of total_thrust() so Ship can
## re-sum only the modules that are still alive after damage, rather than
## adjusting thrust_force by the module type's base thrust_contribution.
func thrust_for(placement: ModulePlacement) -> float:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return 0.0
	return module_type.thrust_contribution * efficiency_of(placement)


## How much of its rated output the part mounted here still delivers. A placement
## with no instance yet (a layout straight off disk, before rebuild() stamps one)
## counts as perfect — the alternative is a brand new ship briefly flying as a
## wreck, the same reasoning as HullPaint.is_clean_joint.
func efficiency_of(placement: ModulePlacement) -> float:
	return placement.instance.efficiency() if placement.instance != null else 1.0


# --- Circuits -----------------------------------------------------------------
#
# One circuit per generating module. Every module that draws power or stores it
# belongs to exactly one, chosen by the player in the ship builder; the set of
# circuits and their membership are both derived from `placements` rather than
# stored alongside it, so there is nothing here that can disagree with the hull.
#
# Nothing in this section looks at a hex coordinate. That is deliberate and it is
# the whole design: where a module sits has no bearing on what powers it, so the
# builder stays a question about what ship you want rather than a routing puzzle
# (see docs/rejected/power-conduits.md).


## Whether this module generates, and therefore owns a circuit of its own.
func is_circuit_source(placement: ModulePlacement) -> bool:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	return module_type != null and module_type.energy_generation > 0.0


## The Command Core's own circuit, or "" on a layout with no core.
##
## The core generates a small trickle of its own and can never go dark, which is
## what stops a ship that has lost every reactor from becoming an inert coffin —
## it limps home instead. A ship whose core can lose power is a ship that can
## become unrecoverable, which is a reload rather than a story.
##
## **It is the ship's floor, not one of its circuits.** The player never assigns
## to it and it plays no part in the specialise-versus-redundancy decision; it
## only catches modules when there is no reactor left to hold them (see
## is_fallback_circuit).
func core_circuit_id() -> String:
	return core_placement_id


## Whether the player may move modules onto this circuit. Every circuit except
## the core's — putting things on the core deliberately would make "the floor"
## into a fourth reactor to budget against, which is not what it is for.
func circuit_accepts_members(circuit_id: String) -> bool:
	return not circuit_id.is_empty() and circuit_id != core_circuit_id()


## Whether the core's circuit is currently carrying the ship on its own.
##
## True only while the hull has no working reactor at all. It is what makes a
## Core + thrusters hull fly (badly) before the first reactor is bolted on, and
## what a ship that has lost its last reactor falls back to rather than drifting.
## The instant a reactor exists, modules are re-homed onto it — the floor is
## never a place anything *stays* by choice.
func is_fallback_circuit(circuit_id: String) -> bool:
	return circuit_id == core_circuit_id() and get_assignable_circuit_ids().is_empty()


## Whether this module has anything to lose by having no power: it draws, it
## fires, or it stores charge for something that does. Plain structure (hull,
## spars, wedges, struts, cargo) does not and is never assigned to a circuit —
## listing inert armour as "unpowered" buries the parts that matter under noise.
##
## A circuit source is excluded because it is not a consumer; it carries its own
## id in circuit_id for bookkeeping, not membership.
func needs_circuit(placement: ModulePlacement) -> bool:
	if is_circuit_source(placement):
		return false
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return false
	return module_type.energy_draw > 0.0 \
		or module_type.energy_idle_draw > 0.0 \
		or module_type.energy_cost_per_use > 0.0 \
		or module_type.energy_capacity_contribution > 0.0


## Every circuit on this hull, core first and reactors in a stable order, so
## anything that colours or lists circuits gets the same order every time.
func get_circuit_ids() -> Array[String]:
	_ensure_index()
	var ids: Array[String] = []
	var core_id: String = core_circuit_id()
	if _circuit_members.has(core_id):
		ids.append(core_id)
	for source_id in _circuit_source_ids:
		if source_id != core_id:
			ids.append(source_id)
	return ids


## The reactor circuits only — everything the player may actually assign to.
func get_assignable_circuit_ids() -> Array[String]:
	var ids: Array[String] = []
	for circuit_id in get_circuit_ids():
		if circuit_accepts_members(circuit_id):
			ids.append(circuit_id)
	return ids


func circuit_members(circuit_id: String) -> Array[ModulePlacement]:
	_ensure_index()
	return _circuit_members.get(circuit_id, [] as Array[ModulePlacement])


## Energy/second this circuit's source makes. A damaged reactor makes less — the
## wear equivalent of a weapon firing slower or a thruster pushing softer.
func circuit_generation(circuit_id: String) -> float:
	var source: ModulePlacement = get_placement_by_id(circuit_id)
	if source == null:
		return 0.0
	var module_type: ModuleType = ModuleCatalog.get_by_id(source.module_type_id)
	if module_type == null:
		return 0.0
	var base: float = module_type.energy_generation \
		+ _manufacturer_stat_delta(source, "energy_generation")
	return maxf(base, 0.0) * efficiency_of(source)


## The buffer this circuit holds: its own source's, plus every battery assigned
## to it. A cracked battery holds less charge.
##
## Capacity is what a circuit spends bursts out of, and — once its reactor is
## gone — how long its members keep running before they hand over. It is the
## same number doing both jobs on purpose: a build that can volley hard is a
## build that survives losing a reactor for longer.
func circuit_capacity(circuit_id: String) -> float:
	var total: float = 0.0
	var source: ModulePlacement = get_placement_by_id(circuit_id)
	if source != null:
		total += _capacity_of(source)
	for member in circuit_members(circuit_id):
		total += _capacity_of(member)
	return total


## What this circuit would draw with everything on it running at once. The
## builder's over-commitment warning is measured against this rather than against
## live usage: the player is deciding here, and the question they are deciding is
## "can this circuit carry what I have hung off it", not "is it coping right now".
func circuit_draw(circuit_id: String) -> float:
	var total: float = 0.0
	for member in circuit_members(circuit_id):
		var module_type: ModuleType = ModuleCatalog.get_by_id(member.module_type_id)
		if module_type != null:
			total += module_type.energy_draw + module_type.energy_idle_draw
	return total


## Spare continuous generation. Negative means over-committed.
func circuit_headroom(circuit_id: String) -> float:
	return circuit_generation(circuit_id) - circuit_draw(circuit_id)


func _capacity_of(placement: ModulePlacement) -> float:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return 0.0
	var base: float = module_type.energy_capacity_contribution \
		+ _manufacturer_stat_delta(placement, "energy_capacity_contribution")
	return maxf(base, 0.0) * efficiency_of(placement)


## Ship-wide totals, kept only for readouts that still want one number. Sums over
## circuits rather than over placements so they can never disagree with the
## per-circuit values the ship actually runs on.
func total_energy_generation() -> float:
	var total: float = 0.0
	for circuit_id in get_circuit_ids():
		total += circuit_generation(circuit_id)
	return total


func total_energy_capacity() -> float:
	var total: float = 0.0
	for circuit_id in get_circuit_ids():
		total += circuit_capacity(circuit_id)
	return total


## Puts every powered module that has no valid circuit onto one, and returns
## whether anything moved.
##
## This is also the migration path for layouts authored before circuits existed
## (every .tres in resources/ships/): they simply arrive with the field empty and
## get assigned on load, so no resource file needs hand-editing. Same code runs
## for a fresh placement, a reactor being removed, and an enemy ship loading —
## there is no separate migration to fall out of date.
func ensure_circuits_assigned() -> bool:
	var changed: bool = false
	for placement in placements:
		# A source's circuit_id is its own id. Bookkeeping, so anything walking
		# placements can ask "which circuit is this on" without a special case.
		if is_circuit_source(placement):
			if placement.circuit_id != placement.placement_id:
				placement.circuit_id = placement.placement_id
				changed = true
			continue
		if not needs_circuit(placement):
			if not placement.circuit_id.is_empty():
				placement.circuit_id = ""
				changed = true
			continue
		if _is_valid_membership(placement.circuit_id):
			continue
		# best_circuit_for() reads circuit tables that this loop is invalidating,
		# so the index is refreshed per assignment rather than once up front.
		invalidate_index()
		placement.circuit_id = best_circuit_for(placement)
		changed = true

	if changed:
		invalidate_index()
	return changed


## Whether a module sitting on this circuit should be left where it is. The core
## counts only while it is the fallback, so bolting a reactor onto a hull that
## had none pulls everything off the core and onto it.
func _is_valid_membership(circuit_id: String) -> bool:
	if not circuit_accepts_members(circuit_id):
		return is_fallback_circuit(circuit_id)
	var source: ModulePlacement = get_placement_by_id(circuit_id)
	return source != null and is_circuit_source(source)


## Which circuit a module should go on when nobody has said otherwise: the one
## with the most spare generation, then the one carrying fewest modules, then the
## lowest id so the answer is the same every time the same hull is loaded.
##
## Headroom rather than anything cleverer because it is the rule that most often
## produces a build the player never has to think about — and the players who do
## think about it get an edge by overriding it, which is the right way round.
## `excluded_circuit_ids` lets fail-over redistribute away from a dead reactor.
func best_circuit_for(placement: ModulePlacement, excluded_circuit_ids: Dictionary = {}) -> String:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	var incoming_draw: float = 0.0
	if module_type != null:
		incoming_draw = module_type.energy_draw + module_type.energy_idle_draw

	var best_id: String = ""
	var best_headroom: float = 0.0
	var best_member_count: int = 0
	for circuit_id in get_assignable_circuit_ids():
		if excluded_circuit_ids.has(circuit_id):
			continue
		var headroom: float = circuit_headroom(circuit_id) - incoming_draw
		var member_count: int = circuit_members(circuit_id).size()
		if best_id.is_empty() or headroom > best_headroom \
				or (is_equal_approx(headroom, best_headroom) and member_count < best_member_count):
			best_id = circuit_id
			best_headroom = headroom
			best_member_count = member_count

	# No reactor to take it — or, during fail-over, none left that isn't already
	# gone. The core catches it, which is the difference between a crippled ship
	# and an inert one.
	if best_id.is_empty():
		return core_circuit_id()
	return best_id


## Moves one module onto a circuit. Returns false for a module that has no
## business on one (plain structure, a reactor) or a circuit that cannot take it.
func assign_circuit(placement_id: String, circuit_id: String) -> bool:
	var placement: ModulePlacement = get_placement_by_id(placement_id)
	if placement == null or not needs_circuit(placement):
		return false
	if not _is_valid_membership(circuit_id):
		return false
	if placement.circuit_id == circuit_id:
		return false
	placement.circuit_id = circuit_id
	invalidate_index()
	return true


## No distance-from-core falloff, unlike energy — cargo capacity is just
## physical hold space, not power delivery, so where a Storage module sits
## on the hull doesn't matter.
func total_cargo_capacity() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			total += module_type.cargo_capacity_contribution \
				+ _manufacturer_stat_delta(placement, "cargo_capacity_contribution")
	return total


## Reactor/Battery have no live spawned node (unlike weapons/thrusters), so a
## manufacturer's stat_modifiers for them are applied right here at the total
## level rather than by mutating a node's properties post-spawn — see
## Manufacturer.stat_modifiers.
func _manufacturer_stat_delta(placement: ModulePlacement, field_name: String) -> float:
	var manufacturer: Manufacturer = ManufacturerCatalog.get_by_id(placement.manufacturer_id)
	if manufacturer == null:
		return 0.0
	return manufacturer.stat_modifiers.get(field_name, 0.0)


## Hex-grid distance from the Core's placement to this one. Anchor-cell to
## anchor-cell is close enough for this stat curve — multi-hex modules don't
## need per-cell precision here, unlike hit detection.
func distance_from_core(placement: ModulePlacement) -> int:
	if core_placement_id.is_empty():
		return 0
	var core_placement: ModulePlacement = get_placement_by_id(core_placement_id)
	if core_placement == null:
		return 0
	return HexUtils.distance(placement.hex_coord, core_placement.hex_coord)


func get_thruster_placements() -> Array[ModulePlacement]:
	var thrusters: Array[ModulePlacement] = []
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null and module_type.thrust_contribution > 0.0:
			thrusters.append(placement)
	return thrusters


func get_weapon_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("weapon")


func get_missile_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("missile")


func get_winch_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("winch")


func get_tractor_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("tractor")


func get_radar_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("radar")


func get_scanner_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("scanner")


func get_salvager_hardpoint_placements() -> Array[ModulePlacement]:
	return _get_hardpoint_placements("salvager")


## Matches by ModuleType.hardpoint_category rather than a single fixed id,
## so any tier of weapon/missile hardpoint is found without new lookup code.
func _get_hardpoint_placements(hardpoint_category: String) -> Array[ModulePlacement]:
	var hardpoints: Array[ModulePlacement] = []
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null and module_type.hardpoint_category == hardpoint_category:
			hardpoints.append(placement)
	return hardpoints


func get_placement_at(hex_coord: Vector2i) -> ModulePlacement:
	_ensure_index()
	return _cell_index.get(hex_coord)


func get_placement_by_id(placement_id: String) -> ModulePlacement:
	_ensure_index()
	return _placement_index.get(placement_id)


func get_occupied_cells(placement: ModulePlacement) -> Array[Vector2i]:
	_ensure_index()
	# Falls back to computing directly for a placement that isn't part of this
	# layout (the ship builder passes candidate placements around before they
	# are committed), so callers never need to know which case they're in.
	var cached: Variant = _cells_by_placement.get(placement.placement_id)
	if cached != null and _placement_index.get(placement.placement_id) == placement:
		return cached
	return _compute_occupied_cells(placement)


func _compute_occupied_cells(placement: ModulePlacement) -> Array[Vector2i]:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	var cells: Array[Vector2i] = []
	if module_type == null:
		return cells
	for offset in module_type.footprint_cells:
		cells.append(placement.hex_coord + HexUtils.rotate(offset, placement.rotation_steps))
	return cells


func get_candidate_cells(module_type_id: String, anchor_hex: Vector2i, rotation_steps: int) -> Array[Vector2i]:
	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	var cells: Array[Vector2i] = []
	if module_type == null:
		return cells
	for offset in module_type.footprint_cells:
		cells.append(anchor_hex + HexUtils.rotate(offset, rotation_steps))
	return cells


func is_occupied(hex_coord: Vector2i) -> bool:
	_ensure_index()
	return _cell_index.has(hex_coord)


func can_place(module_type_id: String, anchor_hex: Vector2i, rotation_steps: int) -> bool:
	return get_place_rejection_reason(module_type_id, anchor_hex, rotation_steps) == ""


func get_place_rejection_reason(module_type_id: String, anchor_hex: Vector2i, rotation_steps: int) -> String:
	if ModuleCatalog.get_by_id(module_type_id) == null:
		return "Unknown module type"

	var candidate_cells: Array[Vector2i] = get_candidate_cells(module_type_id, anchor_hex, rotation_steps)

	for cell in candidate_cells:
		if is_occupied(cell):
			return "Cell already occupied"

	if not placements.is_empty():
		var touches_existing: bool = false
		for cell in candidate_cells:
			for neighbor in HexUtils.neighbors(cell):
				if is_occupied(neighbor):
					touches_existing = true
					break
			if touches_existing:
				break
		if not touches_existing:
			return "Must be adjacent to an existing module"

	if module_type_id == ModuleCatalog.CORE_TYPE_ID and not core_placement_id.is_empty():
		return "Only one Command Core allowed"

	return ""


func place(module_type_id: String, anchor_hex: Vector2i, rotation_steps: int, manufacturer_id: String = "") -> ModulePlacement:
	if not can_place(module_type_id, anchor_hex, rotation_steps):
		return null

	var placement := ModulePlacement.new()
	placement.placement_id = GameRng.next_id("p")
	placement.module_type_id = module_type_id
	placement.hex_coord = anchor_hex
	placement.rotation_steps = posmod(rotation_steps, 6)
	placement.manufacturer_id = manufacturer_id
	placements.append(placement)
	invalidate_index()

	if module_type_id == ModuleCatalog.CORE_TYPE_ID:
		core_placement_id = placement.placement_id

	# Placing a reactor opens a new circuit, and placing anything else may need
	# one — either way the player should never have to visit the circuit UI just
	# to make a part work.
	ensure_circuits_assigned()
	return placement


func can_remove(placement_id: String) -> bool:
	return get_remove_rejection_reason(placement_id) == ""


func get_remove_rejection_reason(placement_id: String) -> String:
	if get_placement_by_id(placement_id) == null:
		return "No such module"
	if placement_id == core_placement_id:
		return "Command Core cannot be removed"
	if not _is_connected_excluding(placement_id):
		return "Removing this would disconnect the ship"
	return ""


func remove(placement_id: String) -> bool:
	if not can_remove(placement_id):
		return false

	for i in placements.size():
		if placements[i].placement_id == placement_id:
			placements.remove_at(i)
			invalidate_index()
			# Pulling a reactor off the bench leaves its members pointing at a
			# circuit that no longer exists; they are re-homed onto whatever is
			# left rather than silently orphaned. (Losing one to weapon fire is a
			# different question with a deliberate delay in it — Phase 2.)
			ensure_circuits_assigned()
			return true
	return false


func can_rotate(placement_id: String, steps_delta: int) -> bool:
	return get_rotate_rejection_reason(placement_id, steps_delta) == ""


func get_rotate_rejection_reason(placement_id: String, steps_delta: int) -> String:
	var placement: ModulePlacement = get_placement_by_id(placement_id)
	if placement == null:
		return "No such module"

	var new_rotation: int = posmod(placement.rotation_steps + steps_delta, 6)
	var candidate_cells: Array[Vector2i] = get_candidate_cells(placement.module_type_id, placement.hex_coord, new_rotation)

	for other in placements:
		if other.placement_id == placement_id:
			continue
		for cell in candidate_cells:
			if cell in get_occupied_cells(other):
				return "Rotation would overlap another module"

	return ""


func rotate(placement_id: String, steps_delta: int) -> bool:
	if not can_rotate(placement_id, steps_delta):
		return false
	var placement: ModulePlacement = get_placement_by_id(placement_id)
	placement.rotation_steps = posmod(placement.rotation_steps + steps_delta, 6)
	invalidate_index()
	return true


func validate_layout() -> Array[String]:
	var issues: Array[String] = []

	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for placement in placements:
		if seen_ids.has(placement.placement_id):
			issues.append("Duplicate placement id: %s" % placement.placement_id)
		seen_ids[placement.placement_id] = true

		if ModuleCatalog.get_by_id(placement.module_type_id) == null:
			issues.append("Unknown module type: %s" % placement.module_type_id)
			continue

		for cell in get_occupied_cells(placement):
			if seen_cells.has(cell):
				issues.append("Overlapping cell at %s" % cell)
			seen_cells[cell] = true

		if placement.rotation_steps < 0 or placement.rotation_steps > 5:
			issues.append("Invalid rotation on %s: %d" % [placement.placement_id, placement.rotation_steps])

	if core_placement_id.is_empty() or get_placement_by_id(core_placement_id) == null:
		issues.append("Missing or invalid Command Core")
	elif not _is_connected_excluding(""):
		issues.append("Layout has disconnected modules")

	return issues


func _is_connected_excluding(excluded_placement_id: String) -> bool:
	if core_placement_id.is_empty() or core_placement_id == excluded_placement_id:
		return placements.size() <= 1

	var remaining: Array[ModulePlacement] = []
	for placement in placements:
		if placement.placement_id != excluded_placement_id:
			remaining.append(placement)

	if remaining.size() <= 1:
		return true

	var visited: Dictionary = {}
	var core_placement: ModulePlacement = get_placement_by_id(core_placement_id)
	var frontier: Array[ModulePlacement] = [core_placement]
	visited[core_placement.placement_id] = true

	while not frontier.is_empty():
		var current: ModulePlacement = frontier.pop_back()
		var current_cells: Array[Vector2i] = get_occupied_cells(current)

		for other in remaining:
			if visited.has(other.placement_id):
				continue
			if _footprints_touch(current_cells, get_occupied_cells(other)):
				visited[other.placement_id] = true
				frontier.append(other)

	for placement in remaining:
		if not visited.has(placement.placement_id):
			return false
	return true


func _footprints_touch(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	for cell in cells_a:
		for neighbor in HexUtils.neighbors(cell):
			if neighbor in cells_b:
				return true
	return false


## Which remaining (non-destroyed) placements can no longer reach the core
## through an unbroken chain of adjacent modules, given a set of placement
## ids to treat as gone (destroyed or already detached). Used by Ship at
## runtime to sever wings/appendages that lose their connection mid-fight —
## unlike _is_connected_excluding(), this never mutates placements and can
## report more than one disconnected id at once (a whole severed limb).
func find_unreachable_from_core(gone_placement_ids: Dictionary) -> Array[String]:
	var unreachable: Array[String] = []
	if core_placement_id.is_empty() or gone_placement_ids.has(core_placement_id):
		return unreachable

	var remaining: Array[ModulePlacement] = []
	for placement in placements:
		if not gone_placement_ids.has(placement.placement_id):
			remaining.append(placement)

	var core_placement: ModulePlacement = get_placement_by_id(core_placement_id)
	if core_placement == null:
		return unreachable

	var visited: Dictionary = {}
	var frontier: Array[ModulePlacement] = [core_placement]
	visited[core_placement.placement_id] = true

	while not frontier.is_empty():
		var current: ModulePlacement = frontier.pop_back()
		var current_cells: Array[Vector2i] = get_occupied_cells(current)
		for other in remaining:
			if visited.has(other.placement_id):
				continue
			if _footprints_touch(current_cells, get_occupied_cells(other)):
				visited[other.placement_id] = true
				frontier.append(other)

	for placement in remaining:
		if not visited.has(placement.placement_id):
			unreachable.append(placement.placement_id)
	return unreachable

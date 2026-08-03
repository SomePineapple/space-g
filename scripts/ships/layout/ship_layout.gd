class_name ShipLayout
extends Resource

@export var placements: Array[ModulePlacement] = []
@export var core_placement_id: String = ""

## Energy contribution (Reactor/Battery) falls off the further a module sits
## from the Core, on the idea that power delivery loses efficiency over
## distance ("cockpit interference") — encourages keeping reactors close in
## rather than clustering every module on the core hex regardless of role.
const REACTOR_DISTANCE_PENALTY_PER_CELL: float = 0.08
const REACTOR_DISTANCE_PENALTY_MAX: float = 0.5


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
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			total += module_type.thrust_contribution
	return total


func total_energy_generation() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			var base: float = module_type.energy_generation + _manufacturer_stat_delta(placement, "energy_generation")
			total += base * _core_distance_energy_multiplier(placement)
	return total


func total_energy_capacity() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			var base: float = module_type.energy_capacity_contribution + _manufacturer_stat_delta(placement, "energy_capacity_contribution")
			total += base * _core_distance_energy_multiplier(placement)
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


func _core_distance_energy_multiplier(placement: ModulePlacement) -> float:
	var penalty: float = minf(REACTOR_DISTANCE_PENALTY_PER_CELL * distance_from_core(placement), REACTOR_DISTANCE_PENALTY_MAX)
	return 1.0 - penalty


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
	for placement in placements:
		if hex_coord in get_occupied_cells(placement):
			return placement
	return null


func get_placement_by_id(placement_id: String) -> ModulePlacement:
	for placement in placements:
		if placement.placement_id == placement_id:
			return placement
	return null


func get_occupied_cells(placement: ModulePlacement) -> Array[Vector2i]:
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
	for placement in placements:
		if hex_coord in get_occupied_cells(placement):
			return true
	return false


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
	placement.placement_id = "p_%d_%d" % [placements.size(), randi() % 100000]
	placement.module_type_id = module_type_id
	placement.hex_coord = anchor_hex
	placement.rotation_steps = posmod(rotation_steps, 6)
	placement.manufacturer_id = manufacturer_id
	placements.append(placement)

	if module_type_id == ModuleCatalog.CORE_TYPE_ID:
		core_placement_id = placement.placement_id

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

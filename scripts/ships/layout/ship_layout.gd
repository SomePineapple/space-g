class_name ShipLayout
extends Resource

@export var placements: Array[ModulePlacement] = []
@export var core_placement_id: String = ""


func total_mass() -> float:
	var total: float = 0.0
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			total += module_type.mass_contribution
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


func get_thruster_placements() -> Array[ModulePlacement]:
	var thrusters: Array[ModulePlacement] = []
	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null and module_type.thrust_contribution > 0.0:
			thrusters.append(placement)
	return thrusters


func get_weapon_hardpoint_placements() -> Array[ModulePlacement]:
	var hardpoints: Array[ModulePlacement] = []
	for placement in placements:
		if placement.module_type_id == ModuleCatalog.WEAPON_HARDPOINT_TYPE_ID:
			hardpoints.append(placement)
	return hardpoints


func get_missile_hardpoint_placements() -> Array[ModulePlacement]:
	var hardpoints: Array[ModulePlacement] = []
	for placement in placements:
		if placement.module_type_id == ModuleCatalog.MISSILE_HARDPOINT_TYPE_ID:
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


func place(module_type_id: String, anchor_hex: Vector2i, rotation_steps: int) -> ModulePlacement:
	if not can_place(module_type_id, anchor_hex, rotation_steps):
		return null

	var placement := ModulePlacement.new()
	placement.placement_id = "p_%d_%d" % [placements.size(), randi() % 100000]
	placement.module_type_id = module_type_id
	placement.hex_coord = anchor_hex
	placement.rotation_steps = posmod(rotation_steps, 6)
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

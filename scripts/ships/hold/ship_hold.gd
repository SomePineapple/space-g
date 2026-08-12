class_name ShipHold
extends RefCounted

## The cargo hold as a set of hex bays rather than a number
## (`docs/direction.md` §4, Phase 1 step 5: "a hold of named objects, not a
## table of counts", and the INVENTORY tab in
## `docs/design_handoff_ship_builder_inv/README.md`).
##
## One bay per installed cargo module, each a small hex cluster of its own —
## deliberately not one shared pool, so where a part goes is a real decision and
## a bay lost with its module takes what was in it.
##
## Holds **recovered parts only**. Raw materials and components keep their
## numeric totals (`Inventory.get_cargo_used`): they are amounts by nature, and
## the thing this replaces is the hold of *objects*.
##
## Pure data — no nodes, no signals, keyed entirely by `instance_id`. Inventory
## owns one of these and is the only thing that mutates it. Same reasoning as
## ModuleInstance staying pure data (`docs/multiplayer.md`): a hold that can only
## be described by pointing at live nodes cannot be replicated or saved.

## The hull's own bay, which has no placement of its own to be keyed by.
const BASE_BAY_ID: String = "__hull__"

## A bay's cells, as axial coordinates around its own origin. Index 0 is always
## Vector2i.ZERO, so a one-cell bay is the centre and larger tiers grow outward
## in rings — which is what makes a Mk2 read as a bigger version of a Mk1 rather
## than a different shape.
static func cluster_cells(count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if count <= 0:
		return cells
	cells.append(Vector2i.ZERO)
	var ring: int = 1
	while cells.size() < count:
		# Standard hex ring walk: step out along one direction, then follow the
		# six edges of that ring.
		var coord: Vector2i = HexUtils.EDGE_DIRECTIONS[4] * ring
		for side in HexUtils.EDGE_DIRECTIONS.size():
			for _step in ring:
				if cells.size() >= count:
					return cells
				cells.append(coord)
				coord += HexUtils.EDGE_DIRECTIONS[side]
		ring += 1
	return cells


## placement_id -> {"label": String, "cells": Array[Vector2i],
## "occupancy": Dictionary(Vector2i -> instance_id)}. Keyed by placement so a
## bay survives a rebuild with what was in it, and dies with its module.
var _bays: Dictionary = {}
## Bay order, so the UI and every index-based call agree on which bay is which.
var _order: Array[String] = []


## Re-derives the bays from a layout, keeping the contents of every bay whose
## module is still installed and still the same size. Anything stowed in a bay
## that is gone is dropped and returned, so the caller can decide what happens
## to parts that lost their bay — this class never destroys a part silently.
## `base_cells` is the hull's own built-in bay, which exists so a ship with no
## cargo module can still carry something — the same role `Ship.base_cargo_
## capacity` plays for materials. Without it a fresh hull could not hold the
## part it just cut free, which is the opening of the game.
func rebuild(layout: ShipLayout, base_cells: int = 0) -> Array[String]:
	var previous: Dictionary = _bays
	_bays = {}
	_order = []

	if base_cells > 0:
		_add_bay(BASE_BAY_ID, "SHIP HOLD", cluster_cells(base_cells), previous)

	if layout == null:
		return _displaced(previous)

	for placement in layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null or module_type.hold_cells <= 0:
			continue
		_add_bay(placement.placement_id, module_type.display_name,
			cluster_cells(module_type.hold_cells), previous)

	return _displaced(previous)


## Recreates one bay, carrying over whatever was stowed in cells it still has.
func _add_bay(id: String, label: String, cells: Array[Vector2i], previous: Dictionary) -> void:
	var bay: Dictionary = {"label": label, "cells": cells, "occupancy": {}}
	var old: Dictionary = previous.get(id, {})
	if not old.is_empty():
		for cell in old["occupancy"]:
			if cells.has(cell):
				bay["occupancy"][cell] = old["occupancy"][cell]
	_bays[id] = bay
	_order.append(id)


## Everything that was stowed before this rebuild and has no cell now — its bay
## was destroyed or shrank. Returned rather than deleted: what happens to a part
## that lost its bay is the caller's decision, not this class's.
func _displaced(previous: Dictionary) -> Array[String]:
	var kept: Dictionary = {}
	for key in _bays:
		for cell in _bays[key]["occupancy"]:
			kept[_bays[key]["occupancy"][cell]] = true
	var lost: Array[String] = []
	for instance_id in _all_stowed_ids(previous):
		if not kept.has(instance_id):
			lost.append(instance_id)
	return lost


func bay_count() -> int:
	return _order.size()


func bay_id(index: int) -> String:
	return _order[index] if index >= 0 and index < _order.size() else ""


func bay_label(index: int) -> String:
	var bay: Dictionary = _bay(index)
	return bay.get("label", "") if not bay.is_empty() else ""


func bay_cells(index: int) -> Array[Vector2i]:
	var bay: Dictionary = _bay(index)
	if bay.is_empty():
		return []
	return bay["cells"]


## Which part is in a cell, or "" for an open one.
func occupant(index: int, cell: Vector2i) -> String:
	var bay: Dictionary = _bay(index)
	if bay.is_empty():
		return ""
	return bay["occupancy"].get(cell, "")


func bay_used(index: int) -> int:
	var bay: Dictionary = _bay(index)
	return bay["occupancy"].size() if not bay.is_empty() else 0


func total_cells() -> int:
	var total: int = 0
	for key in _bays:
		total += _bays[key]["cells"].size()
	return total


func used_cells() -> int:
	var total: int = 0
	for key in _bays:
		total += _bays[key]["occupancy"].size()
	return total


func is_stowed(instance_id: String) -> bool:
	for key in _bays:
		if _bays[key]["occupancy"].values().has(instance_id):
			return true
	return false


## Stows a part of `size` cells into `index`, starting at `cell` and flood-filling
## outward across open cells — the handoff's placement rule. All or nothing: a
## part that cannot claim its whole footprint from here claims none of it, so a
## refused stow never leaves a half-placed object behind.
func stow(index: int, cell: Vector2i, instance_id: String, size: int) -> bool:
	var claimed: Array[Vector2i] = claim_from(index, cell, size)
	if claimed.is_empty():
		return false
	var bay: Dictionary = _bay(index)
	for claimed_cell in claimed:
		bay["occupancy"][claimed_cell] = instance_id
	return true


## The cells a part of `size` would take if stowed at `cell`, or an empty array
## if it will not fit from there. Public so the UI can preview a placement
## without committing to it.
func claim_from(index: int, cell: Vector2i, size: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var bay: Dictionary = _bay(index)
	if bay.is_empty() or size <= 0:
		return empty
	if not bay["cells"].has(cell) or bay["occupancy"].has(cell):
		return empty

	var claimed: Array[Vector2i] = [cell]
	var frontier: Array[Vector2i] = [cell]
	while claimed.size() < size and not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbour in HexUtils.neighbors(current):
			if claimed.size() >= size:
				break
			if claimed.has(neighbour):
				continue
			if not bay["cells"].has(neighbour) or bay["occupancy"].has(neighbour):
				continue
			claimed.append(neighbour)
			frontier.append(neighbour)
	return claimed if claimed.size() >= size else empty


## First place a part of `size` fits, tried bay by bay and cell by cell. Used for
## parts that arrive without the player choosing a spot — coming back off the
## hull, or being restored after a region change.
func auto_stow(instance_id: String, size: int) -> bool:
	for index in _order.size():
		for cell in bay_cells(index):
			if stow(index, cell, instance_id, size):
				return true
	return false


## Whether a part of `size` would fit anywhere, without stowing it.
func has_room_for(size: int) -> bool:
	for index in _order.size():
		for cell in bay_cells(index):
			if not claim_from(index, cell, size).is_empty():
				return true
	return false


func release(instance_id: String) -> void:
	for key in _bays:
		var occupancy: Dictionary = _bays[key]["occupancy"]
		for cell in occupancy.keys():
			if occupancy[cell] == instance_id:
				occupancy.erase(cell)


func clear() -> void:
	for key in _bays:
		_bays[key]["occupancy"] = {}


func _bay(index: int) -> Dictionary:
	if index < 0 or index >= _order.size():
		return {}
	return _bays[_order[index]]


func _all_stowed_ids(bays: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key in bays:
		for cell in bays[key]["occupancy"]:
			var instance_id: String = bays[key]["occupancy"][cell]
			if not ids.has(instance_id):
				ids.append(instance_id)
	return ids

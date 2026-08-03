class_name Inventory
extends Node

signal materials_changed(totals: Dictionary)
signal captured_tech_changed(totals: Dictionary)
signal research_unlocked(module_type_id: String)
signal manufacturer_discovered(manufacturer_id: String)
signal credits_changed(amount: int)
signal cargo_capacity_changed(capacity: float)
## Emitted when try_add_material() rejects a pickup for lack of space — a
## live "storage full" cue for the HUD, distinct from materials_changed
## (which only fires on an actual change).
signal storage_full()

var _credits: int = 0
var _material_totals: Dictionary = {}
## Total cargo capacity, recomputed by Ship whenever its layout changes (see
## Ship._apply_layout_cargo_capacity) — kept here rather than derived on the
## fly so try_add_material() has a cheap, always-current limit to check.
var _cargo_capacity: float = 0.0
## module_type_id -> count. Distinct from _material_totals: these are
## specific captured tech parts (see Ship.capture_tech_part), spent one at a
## time to research/unlock a locked ModuleType (see research()).
var _captured_tech_totals: Dictionary = {}
## Set of module_type_id (module_type_id -> true) that have been researched
## and are now buildable despite ModuleType.requires_research. Session-only,
## like the rest of this prototype's economy state.
var _researched_ids: Dictionary = {}
## Set of manufacturer_id (manufacturer_id -> true) discovered by capturing a
## part built by that manufacturer (see Ship.capture_tech_part) — distinct
## from _researched_ids: knowing a manufacturer exists is a separate fact
## from being able to build a given module type. Buying from a known
## manufacturer once a station/trading system exists is a deliberate future
## hook, not implemented yet.
var _known_manufacturer_ids: Dictionary = {}


func get_credits() -> int:
	return _credits


func add_credits(amount: int) -> void:
	_credits += amount
	credits_changed.emit(_credits)


func has_credits(amount: int) -> bool:
	return _credits >= amount


func spend_credits(amount: int) -> bool:
	if not has_credits(amount):
		return false
	_credits -= amount
	credits_changed.emit(_credits)
	return true


func add_material(material_id: String, amount: int) -> void:
	_material_totals[material_id] = get_material_amount(material_id) + amount
	materials_changed.emit(_material_totals)


func get_material_amount(material_id: String) -> int:
	return _material_totals.get(material_id, 0)


func get_all_materials() -> Dictionary:
	return _material_totals


func set_cargo_capacity(capacity: float) -> void:
	_cargo_capacity = capacity
	cargo_capacity_changed.emit(_cargo_capacity)


func get_cargo_capacity() -> float:
	return _cargo_capacity


func get_cargo_used() -> int:
	var total: int = 0
	for material_id in _material_totals:
		total += _material_totals[material_id]
	return total


func has_cargo_space(amount: int) -> bool:
	return get_cargo_used() + amount <= _cargo_capacity


## Capacity-respecting collection path — used by Salvage pickup so a full
## cargo hold rejects new material instead of silently exceeding capacity.
## add_material() itself stays uncapped on purpose: refunds (ship builder
## module removal), the debug resource cheat, and GameState's scene-change
## restore all call it expecting it to never fail.
func try_add_material(material_id: String, amount: int) -> bool:
	if not has_cargo_space(amount):
		storage_full.emit()
		return false
	add_material(material_id, amount)
	return true


## Discards up to amount of material_id, clamped to what's actually held.
## Returns how much was actually discarded (0 if none was held).
func discard_material(material_id: String, amount: int) -> int:
	var available: int = get_material_amount(material_id)
	var discarded: int = mini(available, amount)
	if discarded <= 0:
		return 0
	_material_totals[material_id] = available - discarded
	materials_changed.emit(_material_totals)
	return discarded


func has_materials(costs: Dictionary) -> bool:
	for material_id in costs:
		if get_material_amount(material_id) < costs[material_id]:
			return false
	return true


func spend_materials(costs: Dictionary) -> bool:
	if not has_materials(costs):
		return false
	for material_id in costs:
		_material_totals[material_id] = get_material_amount(material_id) - costs[material_id]
	materials_changed.emit(_material_totals)
	return true


func add_captured_tech(module_type_id: String) -> void:
	_captured_tech_totals[module_type_id] = get_captured_tech_count(module_type_id) + 1
	captured_tech_changed.emit(_captured_tech_totals)


func get_captured_tech_count(module_type_id: String) -> int:
	return _captured_tech_totals.get(module_type_id, 0)


func get_all_captured_tech() -> Dictionary:
	return _captured_tech_totals


## True if module_type_id doesn't need research at all, or already has it.
func is_researched(module_type_id: String) -> bool:
	return _researched_ids.get(module_type_id, false)


## Whether research() would currently succeed — used to enable/disable the
## ship builder's Research button.
func can_research(module_type_id: String) -> bool:
	return not is_researched(module_type_id) and get_captured_tech_count(module_type_id) > 0


## Spends one captured part of module_type_id to permanently unlock it for
## building. Returns false without effect if already researched or no part
## is available to spend.
func research(module_type_id: String) -> bool:
	if not can_research(module_type_id):
		return false
	_captured_tech_totals[module_type_id] = get_captured_tech_count(module_type_id) - 1
	_researched_ids[module_type_id] = true
	captured_tech_changed.emit(_captured_tech_totals)
	research_unlocked.emit(module_type_id)
	return true


func get_researched_ids() -> Array:
	return _researched_ids.keys()


## Bulk-restore for GameState after a scene change — bypasses research()'s
## captured-tech requirement since the tech was already spent when this was
## originally researched.
func set_researched(module_type_id: String) -> void:
	_researched_ids[module_type_id] = true


func is_manufacturer_known(manufacturer_id: String) -> bool:
	return _known_manufacturer_ids.get(manufacturer_id, false)


## Marks a manufacturer known permanently once its part is captured. Does
## nothing if already known (no duplicate signal spam on repeat captures).
func discover_manufacturer(manufacturer_id: String) -> void:
	if is_manufacturer_known(manufacturer_id):
		return
	_known_manufacturer_ids[manufacturer_id] = true
	manufacturer_discovered.emit(manufacturer_id)


func get_known_manufacturer_ids() -> Array:
	return _known_manufacturer_ids.keys()

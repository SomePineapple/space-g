class_name Inventory
extends Node

signal materials_changed(totals: Dictionary)
signal captured_tech_changed(totals: Dictionary)

var _material_totals: Dictionary = {}
## module_type_id -> count. Distinct from _material_totals: these are
## specific captured tech parts (see Ship.capture_tech_part), meant for a
## future reverse-engineering/research system, not something spent like a
## generic material.
var _captured_tech_totals: Dictionary = {}


func add_material(material_id: String, amount: int) -> void:
	_material_totals[material_id] = get_material_amount(material_id) + amount
	materials_changed.emit(_material_totals)


func get_material_amount(material_id: String) -> int:
	return _material_totals.get(material_id, 0)


func get_all_materials() -> Dictionary:
	return _material_totals


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

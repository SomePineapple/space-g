class_name Inventory
extends Node

signal materials_changed(totals: Dictionary)

var _material_totals: Dictionary = {}


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

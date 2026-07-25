class_name UpgradeManager
extends Node

signal upgrade_purchased(id: String)

var unlocked: Dictionary = {}

@onready var _ship: Ship = get_owner()

var _catalog_by_id: Dictionary = {}


func _ready() -> void:
	for node in UpgradeCatalog.get_all():
		_catalog_by_id[node.id] = node


func get_node_data(id: String) -> UpgradeNode:
	return _catalog_by_id.get(id)


func get_all_ids() -> Array:
	return _catalog_by_id.keys()


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func can_purchase(id: String) -> bool:
	var data: UpgradeNode = _catalog_by_id.get(id)
	if data == null or is_unlocked(id):
		return false
	if _ship.get_node("Inventory").total_salvage < data.cost:
		return false
	for req in data.requires:
		if not is_unlocked(req):
			return false
	return true


func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false

	var data: UpgradeNode = _catalog_by_id[id]
	_ship.get_node("Inventory").spend_salvage(data.cost)
	_apply_modifiers(data)
	unlocked[id] = true
	upgrade_purchased.emit(id)
	return true


func _apply_modifiers(data: UpgradeNode) -> void:
	if data.target_node_path == "Weapon":
		for property_name in data.modifiers:
			_ship.apply_weapon_modifier(property_name, data.modifiers[property_name])
		return

	var target: Node = _ship if data.target_node_path == "" else _ship.get_node(data.target_node_path)
	for property_name in data.modifiers:
		var delta: float = data.modifiers[property_name]
		target.set(property_name, target.get(property_name) + delta)

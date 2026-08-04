class_name DebugTools
extends Node

## Testing aid, not a real gameplay feature: grants materials so builder
## costs/upgrades can be tried out without grinding salvage first.
@export var debug_material_amount: int = 1000


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_add_resources"):
		_add_resources_to_player()


func _add_resources_to_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	var inventory: Inventory = players[0].get_node("Inventory")
	for material_id in MaterialCatalog.ALL_IDS:
		inventory.add_material(material_id, debug_material_amount)

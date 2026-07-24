extends CanvasLayer

@onready var _salvage_label: Label = $SalvageLabel

var _inventory: Inventory


func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_inventory = players[0].get_node("Inventory")
	_inventory.salvage_changed.connect(_on_salvage_changed)
	_update_label(_inventory.total_salvage)


func _on_salvage_changed(total: int) -> void:
	_update_label(total)


func _update_label(total: int) -> void:
	_salvage_label.text = "Salvage: %d" % total

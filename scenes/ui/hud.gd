extends CanvasLayer

@onready var _salvage_label: Label = $SalvageLabel
@onready var _health_label: Label = $HealthLabel

var _inventory: Inventory
var _health: Health


func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_inventory = players[0].get_node("Inventory")
	_inventory.salvage_changed.connect(_on_salvage_changed)
	_update_salvage_label(_inventory.total_salvage)

	_health = players[0].get_node("Health")
	_health.health_changed.connect(_on_health_changed)
	_update_health_label(_health.current_health, _health.max_health)


func _on_salvage_changed(total: int) -> void:
	_update_salvage_label(total)


func _update_salvage_label(total: int) -> void:
	_salvage_label.text = "Salvage: %d" % total


func _on_health_changed(current: float, max_health: float) -> void:
	_update_health_label(current, max_health)


func _update_health_label(current: float, max_health: float) -> void:
	_health_label.text = "Health: %d / %d" % [current, max_health]

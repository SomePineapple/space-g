class_name PoiCamp
extends Node2D

## Marker for a "Small Pirate Camp" point of interest (see "2.3 Basic points
## of interest"). Its ship children need no special setup — they already
## default to State.IDLE and only escalate once the player gets close or
## opens fire (see ship_ai.gd), and Ship._finish_destruction() already drops
## Salvage on death — so combat and reward are free. This script's only job
## is to expose the camp to radar's "enemy_camp" category (see
## radar_display.gd) and drop that contact once every ship here is dead, so
## a cleared camp doesn't linger as a permanent blip.

var _tracked_ships: Array[Node] = []


func _ready() -> void:
	add_to_group("enemy_camp")
	for child in get_children():
		if child.is_in_group("enemy_ship"):
			_tracked_ships.append(child)
			child.tree_exiting.connect(_on_ship_gone.bind(child))


func _on_ship_gone(ship: Node) -> void:
	_tracked_ships.erase(ship)
	if _tracked_ships.is_empty():
		remove_from_group("enemy_camp")

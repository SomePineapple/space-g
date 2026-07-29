class_name MissileCruiserAI
extends Node

## Ranged, bulky enemy behavior: holds a preferred distance from the player
## and fires missile salvos instead of rushing in with lasers, contrasting
## with AIInput's aggressive close-range laser behavior.
@export var fire_range: float = 700.0
@export var keep_distance: float = 550.0
@export var aim_tolerance_deg: float = 25.0
@export var turn_response: float = 1.5

@onready var ship: Ship = get_parent()


func _physics_process(_delta: float) -> void:
	var player: Ship = _find_player()
	if player == null:
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var to_player: Vector2 = player.global_position - ship.global_position
	var distance: float = to_player.length()
	var angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)

	ship.set_aim_target(player.global_position)
	ship.set_turn_input(clampf(angle_diff * turn_response, -1.0, 1.0))

	if distance < keep_distance * 0.8:
		ship.set_thrust_input(-1.0)
	elif distance > keep_distance:
		ship.set_thrust_input(1.0)
	else:
		ship.set_thrust_input(0.0)

	var facing_player: bool = absf(angle_diff) < deg_to_rad(aim_tolerance_deg)
	if facing_player and distance < fire_range:
		ship.fire_secondary()


func _find_player() -> Ship:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	return players[0] if players.size() > 0 else null

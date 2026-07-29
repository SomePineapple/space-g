extends Node

@export var fire_range: float = 500.0
@export var keep_distance: float = 300.0
@export var aim_tolerance_deg: float = 10.0
@export var turn_response: float = 2.0
## Ship stays idle until the player comes within this range, so pirates feel
## like something you discover by exploring rather than something that
## rushes you from across the whole region the instant the scene loads.
@export var detection_range: float = 900.0

@onready var ship: Ship = get_parent()


func _physics_process(_delta: float) -> void:
	var player: Ship = _find_player()
	if player == null:
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var to_player: Vector2 = player.global_position - ship.global_position
	var distance: float = to_player.length()

	if distance > detection_range:
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)

	ship.set_aim_target(player.global_position)
	ship.set_turn_input(clampf(angle_diff * turn_response, -1.0, 1.0))
	ship.set_thrust_input(1.0 if distance > keep_distance else 0.0)

	var facing_player: bool = absf(angle_diff) < deg_to_rad(aim_tolerance_deg)
	if facing_player and distance < fire_range:
		ship.fire_primary()
		# No-op for ships with no missile hardpoints equipped, so this one
		# script covers every pirate loadout without per-ship AI variants.
		ship.fire_secondary()


func _find_player() -> Ship:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	return players[0] if players.size() > 0 else null

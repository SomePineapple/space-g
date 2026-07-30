extends Node

## Drives ship.gd's movement/aim/fire inputs entirely from the parent
## Ship's ShipPersonality resource, so one script covers every AI archetype
## (Rammer, Sniper, ...) instead of a bespoke script per ship. Replaces the
## former ai_input.gd and missile_cruiser_ai.gd, whose behaviors are now just
## two ShipPersonality resources (see resources/ai/).

@onready var ship: Ship = get_parent()
@onready var _health: Health = ship.get_node("Health")

## Taking damage counts as noticing an attacker immediately, regardless of
## detection_range — without this, a stationary ship being shot from outside
## its detection range just sits there and never fights back.
var _alerted: bool = false
var _last_known_health: float = -1.0


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, _max: float) -> void:
	if _last_known_health >= 0.0 and current < _last_known_health:
		_alerted = true
	_last_known_health = current


func _physics_process(_delta: float) -> void:
	var personality: ShipPersonality = ship.personality
	if personality == null or personality.is_player_controlled:
		return

	var player: Ship = _find_player()
	if player == null:
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var to_player: Vector2 = player.global_position - ship.global_position
	# Hull-to-hull clearance rather than center-to-center: without this, a
	# large target's own hull extends so far past its center that a
	# "keep_distance" sniper ends up hugging the hull, looking like it
	# closed in like a rammer.
	var distance: float = to_player.length() - player.get_layout_extent() - ship.get_layout_extent()

	if distance > personality.detection_range and not _alerted:
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)
	ship.set_aim_target(player.global_position)
	ship.set_locked_target(player)
	ship.set_turn_input(clampf(angle_diff * personality.turn_response, -1.0, 1.0))

	if personality.retreats_when_too_close and distance < personality.keep_distance * 0.8:
		ship.set_thrust_input(-1.0)
	elif distance > personality.keep_distance:
		ship.set_thrust_input(1.0)
	else:
		ship.set_thrust_input(0.0)

	var facing_player: bool = absf(angle_diff) < deg_to_rad(personality.aim_tolerance_deg)
	if facing_player and distance < personality.fire_range:
		if personality.use_primary_weapon:
			ship.fire_primary()
		if personality.use_secondary_weapon:
			ship.fire_secondary()


func _find_player() -> Ship:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	return players[0] if players.size() > 0 else null

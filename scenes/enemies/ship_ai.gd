extends Node

## Drives ship.gd's movement/aim/fire inputs entirely from the parent
## Ship's ShipPersonality resource, so one script covers every AI archetype
## (Rammer, Sniper, ...) instead of a bespoke script per ship. Replaces the
## former ai_input.gd and missile_cruiser_ai.gd, whose behaviors are now just
## two ShipPersonality resources (see resources/ai/).

enum State { IDLE, SUSPICIOUS, ALERT }

@onready var ship: Ship = get_parent()
@onready var _health: Health = ship.get_node("Health")

var current_state: State = State.IDLE
var _suspicion_elapsed: float = 0.0
var _last_known_health: float = -1.0

## Real weapons fire shouldn't converge on the exact same point every shot —
## without this, every hit lands dead-on the target's origin, which is where
## the Command Core sits by convention on most layouts, making it a
## guaranteed bullseye the instant anything in front of it breaks. Re-rolled
## periodically (not every frame) so the barrel tracks smoothly instead of
## vibrating.
var _aim_jitter_offset: Vector2 = Vector2.ZERO
var _aim_jitter_timer: float = 0.0
const AIM_JITTER_INTERVAL: float = 0.35
const AIM_JITTER_FRACTION: float = 0.5


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)


## Taking damage counts as noticing an attacker immediately, regardless of
## state or detection_range — without this, a stationary ship being shot
## from outside its detection range just sits there and never fights back.
## Alert is sticky: once reached, this ship never de-escalates back down.
func _on_health_changed(current: float, _max: float) -> void:
	if _last_known_health >= 0.0 and current < _last_known_health:
		current_state = State.ALERT
	_last_known_health = current


func _physics_process(delta: float) -> void:
	var personality: ShipPersonality = ship.personality
	if personality == null or personality.is_player_controlled:
		return

	var player: Ship = _find_player()
	if player == null:
		_hold_position()
		return

	var to_player: Vector2 = player.global_position - ship.global_position
	# Hull-to-hull clearance rather than center-to-center: without this, a
	# large target's own hull extends so far past its center that a
	# "keep_distance" sniper ends up hugging the hull, looking like it
	# closed in like a rammer.
	var distance: float = to_player.length() - player.get_layout_extent() - ship.get_layout_extent()

	_update_state(distance, personality, delta)

	match current_state:
		State.IDLE:
			_hold_position()
		State.SUSPICIOUS:
			_track_player(to_player, personality)
		State.ALERT:
			_engage_player(player, to_player, distance, personality, delta)


## Idle -> Suspicious happens on detection; Suspicious -> Alert happens after
## a short reaction delay (or immediately if already in fire range). Alert
## is sticky and never reverts, but Suspicious drops back to Idle if the
## target leaves detection range before the delay elapses.
func _update_state(distance: float, personality: ShipPersonality, delta: float) -> void:
	if current_state == State.ALERT:
		return

	if distance > personality.detection_range:
		current_state = State.IDLE
		_suspicion_elapsed = 0.0
		return

	if current_state == State.IDLE:
		current_state = State.SUSPICIOUS
		_suspicion_elapsed = 0.0

	_suspicion_elapsed += delta
	if distance <= personality.fire_range or _suspicion_elapsed >= personality.suspicion_delay:
		current_state = State.ALERT


func _hold_position() -> void:
	ship.set_thrust_input(0.0)
	ship.set_turn_input(0.0)


## Turns to face the target without moving or firing yet — a readable
## "noticing" beat before combat starts.
func _track_player(to_player: Vector2, personality: ShipPersonality) -> void:
	var angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)
	ship.set_turn_input(clampf(angle_diff * personality.turn_response, -1.0, 1.0))
	ship.set_thrust_input(0.0)


func _engage_player(player: Ship, to_player: Vector2, distance: float, personality: ShipPersonality, delta: float) -> void:
	var angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)
	ship.set_aim_target(_jittered_aim_point(player, delta))
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


## Spreads aim across the target's own silhouette instead of dead-center on
## its origin, re-rolling only every AIM_JITTER_INTERVAL so the barrel drifts
## smoothly rather than vibrating frame to frame.
func _jittered_aim_point(player: Ship, delta: float) -> Vector2:
	_aim_jitter_timer -= delta
	if _aim_jitter_timer <= 0.0:
		_aim_jitter_timer = AIM_JITTER_INTERVAL
		var spread_radius: float = player.get_layout_extent() * AIM_JITTER_FRACTION
		_aim_jitter_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread_radius
	return player.global_position + _aim_jitter_offset


func _find_player() -> Ship:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	return players[0] if players.size() > 0 else null

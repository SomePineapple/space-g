extends Node

## Drives ship.gd's movement/aim/fire inputs entirely from the parent
## Ship's ShipPersonality resource, so one script covers every AI archetype
## (Rammer, Sniper, ...) instead of a bespoke script per ship. Replaces the
## former ai_input.gd and missile_cruiser_ai.gd, whose behaviors are now just
## two ShipPersonality resources (see resources/ai/). Obstacle/ship avoidance
## and stuck recovery are delegated to AINavigator (scripts/ships/ai/
## ai_navigator.gd) — this script stays focused on the combat state machine
## and target selection.

enum State { IDLE, SUSPICIOUS, ALERT }
enum MovementIntent { APPROACH, RETREAT, HOLD }

@onready var ship: Ship = get_parent()
@onready var _health: Health = ship.get_node("Health")

var current_state: State = State.IDLE
var _suspicion_elapsed: float = 0.0
var _last_known_health: float = -1.0
var _navigator: AINavigator = AINavigator.new()
var _movement_intent: MovementIntent = MovementIntent.HOLD

## Once in ALERT, this ship stops chasing again if the target stays beyond
## detection_range * LEASH_RANGE_MULTIPLIER for LEASH_TIMEOUT seconds
## straight — without this, taking a single stray hit made a ship pursue
## forever regardless of distance, since ALERT was otherwise fully sticky.
var _leash_timer: float = 0.0
const LEASH_RANGE_MULTIPLIER: float = 1.6
const LEASH_TIMEOUT: float = 2.5

## Hysteresis band around personality.keep_distance so hovering right at the
## boundary doesn't flip thrust between forward/reverse/off every frame.
const DISTANCE_HYSTERESIS: float = 40.0

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
func _on_health_changed(current: float, _max: float) -> void:
	if _last_known_health >= 0.0 and current < _last_known_health:
		current_state = State.ALERT
		_leash_timer = 0.0
	_last_known_health = current


func _physics_process(delta: float) -> void:
	var personality: ShipPersonality = ship.personality
	if personality == null or personality.is_player_controlled:
		return

	var player: Ship = _find_player()
	if player == null:
		_hold_position()
		return

	if _navigator.update_stuck_recovery(ship, delta):
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
			_track_player(player, to_player, personality, delta)
		State.ALERT:
			_engage_player(player, to_player, distance, personality, delta)


## Idle -> Suspicious happens on detection; Suspicious -> Alert happens after
## a short reaction delay (or immediately if already in fire range). Alert
## reverts to Idle only via the leash timeout below (see _update_leash);
## Suspicious drops back to Idle if the target leaves detection range before
## the delay elapses.
func _update_state(distance: float, personality: ShipPersonality, delta: float) -> void:
	if current_state == State.ALERT:
		_update_leash(distance, personality, delta)
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


## Lets a sticky ALERT state actually end once the target has been far
## outside detection range for a sustained period, rather than chasing
## forever after a single hit or a close pass.
func _update_leash(distance: float, personality: ShipPersonality, delta: float) -> void:
	if distance <= personality.detection_range * LEASH_RANGE_MULTIPLIER:
		_leash_timer = 0.0
		return

	_leash_timer += delta
	if _leash_timer >= LEASH_TIMEOUT:
		current_state = State.IDLE
		_leash_timer = 0.0
		_suspicion_elapsed = 0.0
		_movement_intent = MovementIntent.HOLD
		ship.set_locked_target(null)


func _hold_position() -> void:
	_set_thrust(0.0)
	ship.set_turn_input(0.0)


## Turns to face the target without moving or firing yet — a readable
## "noticing" beat before combat starts. Still avoidance-aware so a ship
## already drifting near an asteroid while noticing doesn't turn straight
## into it.
func _track_player(player: Ship, to_player: Vector2, personality: ShipPersonality, delta: float) -> void:
	var desired_heading: float = _navigator.compute_desired_heading(ship, _safe_direction(to_player), delta, player)
	var angle_diff: float = wrapf(desired_heading - ship.rotation, -PI, PI)
	ship.set_turn_input(clampf(angle_diff * personality.turn_response, -1.0, 1.0))
	_set_thrust(0.0)


func _engage_player(player: Ship, to_player: Vector2, distance: float, personality: ShipPersonality, delta: float) -> void:
	ship.set_aim_target(_jittered_aim_point(player, delta))
	ship.set_locked_target(player)

	# Steering heading blends toward-target with obstacle/ship avoidance;
	# firing accuracy below still checks the *real* angle to the target so
	# weapon behavior in open space (no obstacles nearby) is unchanged. The
	# target itself is excluded from avoidance — otherwise closing to combat
	# range makes the ship treat the very thing it's chasing as an obstacle
	# to dodge, fighting the seek force (see AINavigator.compute_desired_heading).
	var desired_heading: float = _navigator.compute_desired_heading(ship, _safe_direction(to_player), delta, player)
	var steer_angle_diff: float = wrapf(desired_heading - ship.rotation, -PI, PI)
	ship.set_turn_input(clampf(steer_angle_diff * personality.turn_response, -1.0, 1.0))

	_update_movement_intent(distance, personality)
	match _movement_intent:
		MovementIntent.APPROACH:
			_set_thrust(1.0)
		MovementIntent.RETREAT:
			_set_thrust(-1.0)
		MovementIntent.HOLD:
			_set_thrust(0.0)

	var aim_angle_diff: float = wrapf(to_player.angle() - ship.rotation, -PI, PI)
	var facing_player: bool = absf(aim_angle_diff) < deg_to_rad(personality.aim_tolerance_deg)
	if facing_player and distance < personality.fire_range:
		if personality.use_primary_weapon:
			ship.fire_primary()
		if personality.use_secondary_weapon:
			ship.fire_secondary()


## Decides approach/retreat/hold with a hysteresis band around keep_distance
## so the ship commits to a direction instead of flipping thrust every frame
## while sitting right at the boundary.
func _update_movement_intent(distance: float, personality: ShipPersonality) -> void:
	var approach_threshold: float = personality.keep_distance + DISTANCE_HYSTERESIS
	var hold_threshold: float = personality.keep_distance - DISTANCE_HYSTERESIS
	var retreat_threshold: float = personality.keep_distance * 0.8 - DISTANCE_HYSTERESIS

	if not personality.retreats_when_too_close and _movement_intent == MovementIntent.RETREAT:
		_movement_intent = MovementIntent.HOLD

	match _movement_intent:
		MovementIntent.APPROACH:
			if distance <= hold_threshold:
				_movement_intent = MovementIntent.HOLD
		MovementIntent.RETREAT:
			if distance >= hold_threshold:
				_movement_intent = MovementIntent.HOLD
		MovementIntent.HOLD:
			if distance > approach_threshold:
				_movement_intent = MovementIntent.APPROACH
			elif personality.retreats_when_too_close and distance < retreat_threshold:
				_movement_intent = MovementIntent.RETREAT


func _set_thrust(value: float) -> void:
	ship.set_thrust_input(value)
	_navigator.note_movement_attempt(value)


func _safe_direction(to_player: Vector2) -> Vector2:
	return to_player.normalized() if to_player.length() > 0.001 else Vector2.RIGHT.rotated(ship.rotation)


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

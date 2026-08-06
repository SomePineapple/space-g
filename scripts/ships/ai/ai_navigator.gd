class_name AINavigator
extends RefCounted

## Low-level movement helper for ShipAI (scenes/enemies/ship_ai.gd): computes
## obstacle/ship-avoidance steering, detects when the ship is physically
## stuck despite trying to move, and drives a short recovery maneuver. Kept
## separate from ShipAI's combat state machine since "how to move without
## getting stuck" and "when to fight" are different concerns — one instance
## of this class is owned per ShipAI.

const AVOIDANCE_RAY_ANGLES_DEG: Array[float] = [0.0, 30.0, -30.0, 55.0, -55.0]
const AVOIDANCE_RANGE_MARGIN: float = 220.0
const AVOIDANCE_WEIGHT: float = 1.6
const SEPARATION_RADIUS_MARGIN: float = 140.0
const SEPARATION_WEIGHT: float = 1.2

## Desired heading is smoothed rather than snapped to straight toward
## avoidance each frame — without this, a ship passing between two obstacles
## (or losing/regaining a raycast hit frame to frame) visibly whips back and
## forth instead of curving smoothly.
const HEADING_SMOOTHING_RATE: float = 6.0

const STUCK_CHECK_INTERVAL: float = 0.5
const STUCK_DISPLACEMENT_THRESHOLD: float = 18.0
const STUCK_TRIGGER_TIME: float = 1.0
const RECOVERY_DURATION: float = 1.1

## An obstacle sitting almost directly on the path to the target makes the
## raw avoidance vector point nearly straight backward, with no reliable
## left/right signal — below this cross-product magnitude the signal is
## treated as ambiguous rather than trusted frame to frame.
const AMBIGUOUS_LATERAL_EPS: float = 0.05
## Extra sideways push applied once a side has been committed to, so the
## ship keeps curving the same way through an ambiguous patch instead of
## re-deciding (and potentially flip-flopping) every frame.
const STICKY_LATERAL_PUSH: float = 0.6
## Below this blended-vector length, seek and avoidance have nearly
## canceled out — instead of snapping back to "aim at the target" (which
## immediately re-triggers avoidance and produces a fast seek/avoid
## oscillation, visible as spinning in place), the ship holds its current
## heading until the cancellation resolves.
const NEAR_CANCELLATION_THRESHOLD: float = 0.15

## Raycast-based avoidance is reactive: the ship's current heading picks the
## ray directions, which picks the desired heading, which changes the ship's
## heading next frame. Weaving between several closely-spaced asteroids can
## make that loop ping-pong between "avoid this rock" / "avoid that rock"
## fast enough to look like jitter even though each individual decision is
## reasonable. Capping how fast the *raw target angle* itself is allowed to
## swing (independent of how fast the ship then turns to follow it) damps
## that feedback loop; set above every personality's own turn rate so it
## never limits a genuine, deliberate turn.
const MAX_TARGET_ANGLE_RATE: float = deg_to_rad(260.0)

var _smoothed_heading: float = 0.0
var _heading_initialized: bool = false
var _last_target_angle: float = 0.0
var _target_angle_initialized: bool = false
## 0.0 = no side committed yet; ±1.0 = currently favoring that side while
## avoidance is ambiguous. Reset once no obstacle is being avoided at all.
var _avoidance_bias_sign: float = 0.0

var _recovery_check_timer: float = 0.0
var _low_progress_time: float = 0.0
var _last_check_position: Vector2 = Vector2.ZERO
var _attempted_movement_this_window: bool = false
var _recovery_timer: float = 0.0
var _recovery_turn_dir: float = 1.0


## ShipAI calls this whenever it sets a nonzero thrust input, so the stuck
## check only counts "tried to move but didn't" rather than "sat still".
func note_movement_attempt(thrust_input: float) -> void:
	if absf(thrust_input) > 0.01:
		_attempted_movement_this_window = true


## Call once per physics frame before any normal movement decision. Returns
## true while a recovery maneuver is in progress; the caller should skip its
## normal state logic entirely that frame (this already drives thrust/turn).
func update_stuck_recovery(ship: Ship, intent: ShipIntent, delta: float) -> bool:
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		intent.thrust = -1.0
		intent.turn = _recovery_turn_dir
		return true

	_recovery_check_timer += delta
	if _recovery_check_timer < STUCK_CHECK_INTERVAL:
		return false
	_recovery_check_timer = 0.0

	var moved: float = ship.global_position.distance_to(_last_check_position)
	_last_check_position = ship.global_position

	if _attempted_movement_this_window and moved < STUCK_DISPLACEMENT_THRESHOLD:
		_low_progress_time += STUCK_CHECK_INTERVAL
	else:
		_low_progress_time = 0.0
	_attempted_movement_this_window = false

	if _low_progress_time >= STUCK_TRIGGER_TIME:
		_low_progress_time = 0.0
		_recovery_timer = RECOVERY_DURATION
		_recovery_turn_dir = _pick_recovery_turn_direction(ship)
		return true
	return false


## Turns away from whatever's currently blocking the way, if anything was
## detected; otherwise picks an arbitrary side so the ship still breaks out
## of a dead-end with no obstacle directly in front of it.
func _pick_recovery_turn_direction(ship: Ship) -> float:
	var avoidance: Vector2 = compute_avoidance_vector(ship)
	if avoidance.length() > 0.01:
		return signf(ship.transform.x.cross(avoidance))
	return 1.0 if GameRng.stream("ai").randf() < 0.5 else -1.0


## Blends "seek the target" with steering away from nearby asteroids/ships
## into one smoothed desired heading (world-space angle). Callers use this
## for the ship's *turn* input only — weapon aim still tracks the real
## target directly, independent of this avoidance-influenced body heading.
## exclude_target should be the ship currently being pursued, if any — without
## excluding it, the pursuit target itself gets treated as an obstacle to
## dodge once in range, fighting the seek force and producing the same
## seek/avoid oscillation an asteroid dead-ahead does, except aimed at the
## one thing the ship is actually trying to reach.
func compute_desired_heading(ship: Ship, seek_direction: Vector2, delta: float, exclude_target: Node2D = null) -> float:
	var avoidance: Vector2 = compute_avoidance_vector(ship, exclude_target)
	var separation: Vector2 = compute_separation_vector(ship)
	var blended: Vector2 = seek_direction + avoidance * AVOIDANCE_WEIGHT + separation * SEPARATION_WEIGHT

	var target_angle: float
	if blended.length() < NEAR_CANCELLATION_THRESHOLD and _heading_initialized:
		target_angle = _smoothed_heading
	elif blended.length() > 0.001:
		target_angle = blended.angle()
	else:
		target_angle = seek_direction.angle()

	if _target_angle_initialized:
		var max_step: float = MAX_TARGET_ANGLE_RATE * delta
		var angle_delta: float = wrapf(target_angle - _last_target_angle, -PI, PI)
		target_angle = _last_target_angle + clampf(angle_delta, -max_step, max_step)
	_last_target_angle = target_angle
	_target_angle_initialized = true

	if not _heading_initialized:
		_smoothed_heading = target_angle
		_heading_initialized = true
	else:
		_smoothed_heading = lerp_angle(_smoothed_heading, target_angle, clampf(HEADING_SMOOTHING_RATE * delta, 0.0, 1.0))
	return _smoothed_heading


## Fans a few rays out from the ship's current heading and pushes away from
## whatever they hit (asteroids or other ships), weighted by how close the
## hit is. Area2Ds (salvage, nebula zones, ...) never register since ray
## queries only test physics bodies by default.
func compute_avoidance_vector(ship: Ship, exclude_target: Node2D = null) -> Vector2:
	var space_state: PhysicsDirectSpaceState2D = ship.get_world_2d().direct_space_state
	var probe_range: float = ship.get_layout_extent() + AVOIDANCE_RANGE_MARGIN
	var avoidance: Vector2 = Vector2.ZERO
	var any_hit: bool = false
	var strongest_closeness: float = 0.0

	for angle_deg in AVOIDANCE_RAY_ANGLES_DEG:
		var direction: Vector2 = Vector2.RIGHT.rotated(ship.rotation + deg_to_rad(angle_deg))
		var query := PhysicsRayQueryParameters2D.create(ship.global_position, ship.global_position + direction * probe_range)
		query.exclude = [ship]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			continue

		var collider: Object = result["collider"]
		if collider == exclude_target:
			continue
		if not (collider is Asteroid or collider is Ship):
			continue

		var hit_point: Vector2 = result["position"]
		var away: Vector2 = ship.global_position - hit_point
		if away.length() < 0.001:
			continue
		var closeness: float = clampf(1.0 - (hit_point.distance_to(ship.global_position) / probe_range), 0.0, 1.0)
		any_hit = true
		strongest_closeness = maxf(strongest_closeness, closeness)
		avoidance += away.normalized() * closeness

	if not any_hit:
		_avoidance_bias_sign = 0.0
		return Vector2.ZERO

	# A single obstacle sitting almost dead ahead makes "away from hit point"
	# point nearly straight backward with no clear left/right — recomputing a
	# side choice from near-zero noise every frame is what caused the ship to
	# visibly spin in place when hiding directly behind an asteroid. Instead,
	# commit to whichever side the signal clearly favors and keep nudging
	# that way whenever the current signal is too ambiguous to trust.
	var forward: Vector2 = Vector2.RIGHT.rotated(ship.rotation)
	var lateral_signal: float = forward.cross(avoidance)
	if absf(lateral_signal) < AMBIGUOUS_LATERAL_EPS:
		if _avoidance_bias_sign == 0.0:
			_avoidance_bias_sign = 1.0 if GameRng.stream("ai").randf() < 0.5 else -1.0
		avoidance += forward.rotated(PI / 2.0 * _avoidance_bias_sign) * STICKY_LATERAL_PUSH * strongest_closeness
	else:
		_avoidance_bias_sign = signf(lateral_signal)

	return avoidance


## Soft separation from other AI ships even without a direct raycast hit, so
## several pirates converging on the same target don't pack into each
## other's hulls.
func compute_separation_vector(ship: Ship) -> Vector2:
	var separation: Vector2 = Vector2.ZERO
	for other in ship.get_tree().get_nodes_in_group("enemy_ship"):
		if other == ship or not (other is Ship):
			continue
		var desired_gap: float = ship.get_layout_extent() + other.get_layout_extent() + SEPARATION_RADIUS_MARGIN
		var offset: Vector2 = ship.global_position - other.global_position
		var dist: float = offset.length()
		if dist > 0.001 and dist < desired_gap:
			separation += offset.normalized() * (1.0 - dist / desired_gap)
	return separation

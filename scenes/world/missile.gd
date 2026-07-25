class_name Missile
extends Projectile

## Arc peak height, as a fraction of travel distance. Randomised per missile
## so a salvo doesn't all trace the exact same curve.
@export var arc_height_ratio_min: float = 0.22
@export var arc_height_ratio_max: float = 0.5

## Sideways bow away from the straight line to target, also a fraction of
## distance, signed randomly so missiles curve left or right.
@export var lateral_bow_ratio_max: float = 0.18

## Randomises effective flight speed slightly so simultaneous launches
## spread apart in time instead of moving in lockstep.
@export var speed_variance: float = 0.15

var _launch_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO
var _flight_duration: float = 1.0
var _elapsed: float = 0.0
var _has_target: bool = false
var _arc_vector: Vector2 = Vector2.ZERO


## Locks in a curved path toward target_position: a straight ground component
## plus a randomised vertical arc (faking a Z-axis) and a randomised lateral
## bow, both applied as a single sine hump so the missile leaves and lands
## exactly on the line but bulges out mid-flight.
func set_target(target_position: Vector2) -> void:
	_launch_position = global_position
	_target_position = target_position
	_has_target = true
	_elapsed = 0.0

	var distance: float = _launch_position.distance_to(_target_position)
	var travel_direction: Vector2 = _target_position - _launch_position
	var perpendicular: Vector2 = Vector2(-travel_direction.y, travel_direction.x).normalized()

	# Bow outward on whichever side of the ship the launcher sits, rather
	# than a coin-flip direction, so missiles from a left hardpoint sweep
	# left and missiles from a right hardpoint sweep right (a fanned salvo)
	# instead of randomly crossing over each other.
	var side_sign: float = 1.0
	if _shooter != null:
		var hull_offset: Vector2 = _launch_position - _shooter.global_position
		var side: float = hull_offset.dot(perpendicular)
		if absf(side) > 0.01:
			side_sign = signf(side)

	var arc_height: float = distance * randf_range(arc_height_ratio_min, arc_height_ratio_max)
	var lateral_bow: float = distance * randf_range(0.0, lateral_bow_ratio_max) * side_sign
	_arc_vector = Vector2(0, -arc_height) + perpendicular * lateral_bow

	var effective_speed: float = speed * randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	_flight_duration = maxf(distance / effective_speed, 0.05)


func _physics_process(delta: float) -> void:
	if not _has_target:
		super._physics_process(delta)
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / _flight_duration, 0.0, 1.0)

	var ground_position: Vector2 = _launch_position.lerp(_target_position, t)
	global_position = ground_position + _arc_vector * sin(t * PI)

	var ground_velocity: Vector2 = (_target_position - _launch_position) / _flight_duration
	var arc_velocity: Vector2 = _arc_vector * cos(t * PI) * PI / _flight_duration
	var travel_direction: Vector2 = ground_velocity + arc_velocity
	if travel_direction.length() > 0.01:
		rotation = travel_direction.angle()

	if t >= 1.0:
		_destroy()

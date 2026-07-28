class_name Missile
extends Projectile

enum Phase { CREEPING, HOMING }

## Very low acceleration for the initial "spew out" creep, before the
## missile commits to full power and starts homing.
@export var creep_acceleration: float = 60.0

## How long the missile creeps outward at low power before it ignites and
## starts homing. Upgradeable via the "MissileLauncher" tree.
@export var ignition_delay: float = 1.2

## How fast the missile ramps up to its cruise speed (speed, inherited from
## Projectile) once homing starts, rather than instantly moving at full
## speed or speeding up further while turning.
@export var acceleration: float = 900.0

## Turn rate (radians/sec) ramps from _min to _max over turn_rate_ramp_time
## once homing begins, so the missile eases into steering instead of
## snapping straight at the target the instant it starts homing.
@export var turn_rate_min: float = 1.0
@export var turn_rate_max: float = 5.0
@export var turn_rate_ramp_time: float = 0.6

## Every missile aims at a point offset from the true target by up to this
## fraction of the launch distance, so most land close but some visibly miss.
@export var max_miss_offset_ratio: float = 0.2
@export var miss_chance: float = 0.3

const ARRIVAL_DISTANCE: float = 24.0

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _phase: Phase = Phase.CREEPING
var _creep_elapsed: float = 0.0
var _homing_elapsed: float = 0.0
var _current_speed: float = 0.0
var _travel_direction: Vector2 = Vector2.RIGHT


## Locks in an inaccuracy-offset target point, and sets the missile's launch
## heading to the angle from the shooter's cockpit (center) out to this
## silo's mounted position, so hardpoints on different sides of the hull
## naturally spew outward in different directions.
func set_target(target_position: Vector2) -> void:
	var distance: float = global_position.distance_to(target_position)
	var offset_ratio: float = randf() * max_miss_offset_ratio * 0.35
	if randf() < miss_chance:
		offset_ratio = randf_range(max_miss_offset_ratio * 0.6, max_miss_offset_ratio)
	var miss_offset: Vector2 = Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * distance * offset_ratio

	_target_position = target_position + miss_offset
	_has_target = true
	_phase = Phase.CREEPING
	_creep_elapsed = 0.0
	_homing_elapsed = 0.0
	_current_speed = 0.0

	var hull_offset: Vector2 = global_position - _shooter.global_position if _shooter != null else Vector2.ZERO
	_travel_direction = hull_offset.normalized() if hull_offset.length() > 0.01 else transform.x
	rotation = _travel_direction.angle()


func _physics_process(delta: float) -> void:
	if not _has_target:
		super._physics_process(delta)
		return

	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()
		return

	match _phase:
		Phase.CREEPING:
			_current_speed = minf(_current_speed + creep_acceleration * delta, speed)
			global_position += _travel_direction * _current_speed * delta

			_creep_elapsed += delta
			if _creep_elapsed >= ignition_delay:
				_phase = Phase.HOMING
		Phase.HOMING:
			_homing_elapsed += delta
			var turn_rate: float = lerpf(turn_rate_min, turn_rate_max, clampf(_homing_elapsed / turn_rate_ramp_time, 0.0, 1.0))
			var desired_angle: float = (_target_position - global_position).angle()
			var angle_diff: float = wrapf(desired_angle - _travel_direction.angle(), -PI, PI)
			var max_turn: float = turn_rate * delta
			_travel_direction = _travel_direction.rotated(clampf(angle_diff, -max_turn, max_turn))

			_current_speed = minf(_current_speed + acceleration * delta, speed)
			global_position += _travel_direction * _current_speed * delta

			if global_position.distance_to(_target_position) <= ARRIVAL_DISTANCE:
				_destroy()

	rotation = _travel_direction.angle()

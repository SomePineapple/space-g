class_name Missile
extends Projectile

enum Phase { CREEPING, COASTING, HOMING }

## Very low acceleration for the initial "spew out" creep, before the
## missile's ignition burst.
@export var creep_acceleration: float = 60.0

## How long the missile creeps outward at low power before its burst ignites.
## Upgradeable via the "MissileLauncher" tree.
@export var ignition_delay: float = 1.2

## Torpedo-style single propulsion cycle: creep out of the silo, a brief
## engines-off coast to "settle" (no thrust, trail off), then the main
## engine ignites for good and stays on, steering toward the target for
## the rest of the flight.
@export var coast_duration: float = 1

## How fast the missile accelerates once the main engine ignites after the
## coast, up to its cruise speed (speed, inherited from Projectile).
@export var acceleration: float = 900.0

## Turn rate (radians/sec) ramps from _min to _max over turn_rate_ramp_time
## once homing begins, so the missile eases into steering instead of
## snapping straight at the target the instant it starts homing. Exported
## (rather than a fixed constant) so a future upgrade-tree node can raise
## these via Ship.apply_missile_modifier(), same as fire_rate/damage today.
@export var turn_rate_min: float = 0.35
@export var turn_rate_max: float = 1.5
@export var turn_rate_ramp_time: float = 0.6

## Every guided missile aims at a point offset from the true target by up to
## this fraction of the launch distance, so most land close but some
## visibly miss.
@export var max_miss_offset_ratio: float = 0.2
@export var miss_chance: float = 0.2

const ARRIVAL_DISTANCE: float = 24.0

## Live reference for guided missiles so they keep tracking a moving target
## rather than just steering toward where it was at launch. Null once the
## target is destroyed or for an unguided launch; _target_position then
## holds whatever position was last known/aimed at.
var _target_node: Node2D = null
var _target_position: Vector2 = Vector2.ZERO
## Fixed miss offset (world-space vector) rolled once at launch and re-applied
## to the target's current position every frame, so a "miss" still reads as
## a consistent near-target trajectory rather than the aim point wobbling
## around as the target moves.
var _miss_offset: Vector2 = Vector2.ZERO
var _has_target: bool = false
## True for a locked-on launch that steers toward _target_position; false
## for an unguided launch (no lock) that just flies straight outward.
var _guided: bool = false
## Once a guided missile reaches its target point it stops steering but
## keeps flying and stays alive until it hits something or times out,
## instead of detonating in empty space the moment it arrives.
var _reached_target: bool = false
var _phase: Phase = Phase.CREEPING
var _creep_elapsed: float = 0.0
var _coast_elapsed: float = 0.0
var _homing_elapsed: float = 0.0
var _current_speed: float = 0.0
var _travel_direction: Vector2 = Vector2.RIGHT

@onready var _trail: GPUParticles2D = $Trail


## GPUParticles2D billboard size doesn't follow this node's Node2D.scale
## (unlike the Polygon2D visual and collision shape), since the trail runs in
## global coordinates rather than local. Tier-scaled missiles would otherwise
## keep a same-size trail regardless of projectile size, so the process
## material's particle scale is resized to match here instead. Duplicated
## first since Godot caches one process_material per scene, shared by every
## instance.
func _ready() -> void:
	super._ready()
	var trail_material: ParticleProcessMaterial = _trail.process_material.duplicate()
	trail_material.scale_min *= scale.x
	trail_material.scale_max *= scale.x
	_trail.process_material = trail_material
	area_entered.connect(_on_area_entered)


## Locks in an inaccuracy-offset and starts homing toward the target,
## re-reading its live position every frame so a moving target is actually
## chased rather than just its launch-time position.
func launch_toward(target: Node2D) -> void:
	var target_position: Vector2 = target.global_position
	var distance: float = global_position.distance_to(target_position)
	var offset_ratio: float = randf() * max_miss_offset_ratio * 0.35
	if randf() < miss_chance:
		offset_ratio = randf_range(max_miss_offset_ratio * 0.6, max_miss_offset_ratio)
	_miss_offset = Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * distance * offset_ratio

	_target_node = target
	_target_position = target_position + _miss_offset
	_guided = true
	_begin_flight()


## No lock-on target: the missile just spews outward and flies straight,
## with no steering at all.
func launch_outward() -> void:
	_target_node = null
	_guided = false
	_begin_flight()


## Sets the missile's launch heading to the angle from the shooter's
## cockpit (center) out to this silo's mounted position, so hardpoints on
## different sides of the hull naturally spew outward in different
## directions, then resets the flight state shared by both launch modes.
func _begin_flight() -> void:
	_has_target = true
	_reached_target = false
	_phase = Phase.CREEPING
	_creep_elapsed = 0.0
	_coast_elapsed = 0.0
	_homing_elapsed = 0.0
	_current_speed = 0.0
	_trail.emitting = true

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
				_phase = Phase.COASTING
				_trail.emitting = false
		Phase.COASTING:
			# Engines off, holding whatever speed it had — a brief "settling"
			# beat between the silo creep and the main engine igniting.
			global_position += _travel_direction * _current_speed * delta

			_coast_elapsed += delta
			if _coast_elapsed >= coast_duration:
				_phase = Phase.HOMING
				_trail.emitting = true
		Phase.HOMING:
			if _guided and not _reached_target:
				if _target_node != null and is_instance_valid(_target_node):
					_target_position = _target_node.global_position + _miss_offset
				_homing_elapsed += delta
				var turn_rate: float = lerpf(turn_rate_min, turn_rate_max, clampf(_homing_elapsed / turn_rate_ramp_time, 0.0, 1.0))
				var desired_angle: float = (_target_position - global_position).angle()
				var angle_diff: float = wrapf(desired_angle - _travel_direction.angle(), -PI, PI)
				var max_turn: float = turn_rate * delta
				_travel_direction = _travel_direction.rotated(clampf(angle_diff, -max_turn, max_turn))

				if global_position.distance_to(_target_position) <= ARRIVAL_DISTANCE:
					_reached_target = true

			_current_speed = minf(_current_speed + acceleration * delta, speed)
			global_position += _travel_direction * _current_speed * delta

	rotation = _travel_direction.angle()


## Lets weapon fire "shoot down" a missile in flight: any Projectile/Missile
## whose shooter is on the opposite side (not friendly fire) destroys it.
func _on_area_entered(area: Area2D) -> void:
	if not (area is Projectile):
		return
	var incoming: Projectile = area
	if incoming == self or incoming._shooter == null or _shooter == null:
		return
	if incoming._shooter.is_in_group("player_ship") == _shooter.is_in_group("player_ship"):
		return
	_destroy()

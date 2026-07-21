class_name Ship
extends CharacterBody2D

@export var thrust_force: float = 600.0
@export var reverse_thrust_force: float = 300.0
@export var max_speed: float = 400.0
@export var boost_multiplier: float = 1.8
@export var rotation_speed: float = 3.5
@export var drag: float = 0.6
@export var mass: float = 1.0

var _thrust_input: float = 0.0
var _turn_input: float = 0.0
var _boost_active: bool = false

@onready var _engine_particles: GPUParticles2D = $EngineParticles
@onready var _engine_particles_soft: GPUParticles2D = $EngineParticlesSoft


func set_thrust_input(thrust: float) -> void:
	_thrust_input = clampf(thrust, -1.0, 1.0)


func set_turn_input(turn: float) -> void:
	_turn_input = clampf(turn, -1.0, 1.0)


func set_boost_input(boosting: bool) -> void:
	_boost_active = boosting


func _physics_process(delta: float) -> void:
	rotation += _turn_input * rotation_speed * delta

	if _thrust_input != 0.0:
		var thrust: float = thrust_force if _thrust_input > 0.0 else reverse_thrust_force
		var current_max_speed: float = max_speed
		if _boost_active and _thrust_input > 0.0:
			thrust *= boost_multiplier
			current_max_speed *= boost_multiplier
		var acceleration: float = thrust / mass
		velocity += transform.x * _thrust_input * acceleration * delta
		velocity = velocity.limit_length(current_max_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, drag * max_speed * delta)

	move_and_slide()
	_update_engine_particles()


func _update_engine_particles() -> void:
	var thrusting_forward: bool = _thrust_input > 0.0
	var intensity: float = 1.0 if thrusting_forward and _boost_active else 0.6

	_engine_particles.emitting = thrusting_forward
	_engine_particles.amount_ratio = intensity

	_engine_particles_soft.emitting = thrusting_forward
	_engine_particles_soft.amount_ratio = intensity

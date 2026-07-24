class_name Ship
extends CharacterBody2D

@export var thrust_force: float = 600.0
@export var reverse_thrust_force: float = 120.0
@export var max_speed: float = 400.0
@export var reverse_max_speed: float = 140.0
@export var boost_multiplier: float = 1.8
@export var rotation_speed: float = 3.5
@export var drag: float = 0.6
@export var mass: float = 1.0
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var destruction_explosion_scale: float = 2.2
@export var drops_salvage: bool = true
@export var salvage_scene: PackedScene = preload("res://scenes/world/salvage.tscn")
@export var hit_flash_color: Color = Color(1, 1, 1, 1)
@export var hit_flash_duration: float = 0.12

var _thrust_input: float = 0.0
var _turn_input: float = 0.0
var _boost_active: bool = false
var _base_sprite_modulate: Color
var _flash_tween: Tween

@onready var _engine_particles: GPUParticles2D = $EngineParticles
@onready var _engine_particles_soft: GPUParticles2D = $EngineParticlesSoft
@onready var _engine_particles_normal: GPUParticles2D = $EngineParticlesNormal
@onready var _weapon: Weapon = $Weapon
@onready var _missile_launcher: MissileLauncher = $MissileLauncher
@onready var _health: Health = $Health
@onready var _ship_sprite: Sprite2D = $ShipSprite
@onready var _inventory: Inventory = $Inventory


func _ready() -> void:
	_health.destroyed.connect(_on_destroyed)
	_health.health_changed.connect(_on_health_changed)
	_base_sprite_modulate = _ship_sprite.modulate


func _on_health_changed(_current: float, _max: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_ship_sprite.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_ship_sprite, "modulate", _base_sprite_modulate, hit_flash_duration)


func fire_primary() -> void:
	_weapon.fire()


func fire_secondary() -> void:
	_missile_launcher.fire()


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


func add_salvage(amount: int) -> void:
	_inventory.add_salvage(amount)


func apply_impulse(impulse: Vector2) -> void:
	velocity += impulse / mass


func _on_destroyed() -> void:
	var explosion: Explosion = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	explosion.effect_scale = destruction_explosion_scale

	if drops_salvage:
		var salvage: Salvage = salvage_scene.instantiate()
		var rolled_rarity: Salvage.Rarity = _roll_salvage_rarity()
		salvage.rarity = rolled_rarity
		salvage.is_dangerous = randf() < _danger_chance_for_rarity(rolled_rarity)
		get_tree().current_scene.add_child(salvage)
		salvage.global_position = global_position

	queue_free()


func _danger_chance_for_rarity(rolled_rarity: Salvage.Rarity) -> float:
	match rolled_rarity:
		Salvage.Rarity.COMMON:
			return 0.05
		Salvage.Rarity.ELECTRONICS:
			return 0.1
		Salvage.Rarity.ENERGY:
			return 0.2
		Salvage.Rarity.EXPERIMENTAL:
			return 0.35
		Salvage.Rarity.ARTEFACT:
			return 0.5
		_:
			return 0.0


func _roll_salvage_rarity() -> Salvage.Rarity:
	var roll: float = randf()
	if roll < 0.55:
		return Salvage.Rarity.COMMON
	elif roll < 0.8:
		return Salvage.Rarity.ELECTRONICS
	elif roll < 0.93:
		return Salvage.Rarity.ENERGY
	elif roll < 0.99:
		return Salvage.Rarity.EXPERIMENTAL
	else:
		return Salvage.Rarity.ARTEFACT


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

		if _thrust_input > 0.0:
			velocity = velocity.limit_length(current_max_speed)
		else:
			var forward_speed: float = velocity.dot(transform.x)
			if forward_speed < -reverse_max_speed:
				velocity -= transform.x * (forward_speed + reverse_max_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, drag * max_speed * delta)

	move_and_slide()
	_update_engine_particles()


func _update_engine_particles() -> void:
	var thrusting_forward: bool = _thrust_input > 0.0
	var boosting: bool = thrusting_forward and _boost_active

	_engine_particles.emitting = boosting
	_engine_particles.amount_ratio = 1.0

	_engine_particles_soft.emitting = boosting
	_engine_particles_soft.amount_ratio = 1.0

	_engine_particles_normal.emitting = thrusting_forward and not boosting

class_name Ship
extends CharacterBody2D

signal layout_applied

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
@export var ship_layout: ShipLayout = preload("res://resources/ships/starter_ship_layout.tres")
@export var engine_thruster_scene: PackedScene = preload("res://scenes/player/engine_thruster.tscn")
@export var reverse_thrust_ratio: float = 0.2
@export var speed_per_acceleration: float = 1.0
@export var reverse_speed_ratio: float = 0.35

var _thrust_input: float = 0.0
var _turn_input: float = 0.0
var _boost_active: bool = false
var _base_hull_modulate: Color
var _flash_tween: Tween
var _thrusters: Array[Node2D] = []
var _collision_shapes: Array[CollisionPolygon2D] = []

@onready var _weapon: Weapon = $Weapon
@onready var _missile_launcher: MissileLauncher = $MissileLauncher
@onready var _health: Health = $Health
@onready var _hull_renderer: ShipLayoutRenderer = $HullRenderer
@onready var _inventory: Inventory = $Inventory


func _ready() -> void:
	_apply_ship_layout()
	_health.destroyed.connect(_on_destroyed)
	_health.health_changed.connect(_on_health_changed)
	_base_hull_modulate = _hull_renderer.modulate


func apply_layout(new_layout: ShipLayout) -> void:
	ship_layout = new_layout
	_apply_ship_layout()


func _apply_ship_layout() -> void:
	if ship_layout == null:
		return
	mass = ship_layout.total_mass()
	_health.configure(ship_layout.total_max_health())
	_hull_renderer.set_layout(ship_layout)
	_apply_layout_thrust()
	_spawn_thrusters()
	_spawn_collision_shapes()
	layout_applied.emit()


func get_layout_extent() -> float:
	if ship_layout == null:
		return 0.0

	var max_distance: float = 0.0
	for placement in ship_layout.placements:
		for cell in ship_layout.get_occupied_cells(placement):
			var local_pos: Vector2 = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
			max_distance = maxf(max_distance, local_pos.length() + _hull_renderer.cell_size)
	return max_distance


func _spawn_collision_shapes() -> void:
	for shape in _collision_shapes:
		shape.queue_free()
	_collision_shapes.clear()

	for placement in ship_layout.placements:
		for cell in ship_layout.get_occupied_cells(placement):
			var shape := CollisionPolygon2D.new()
			shape.polygon = HexUtils.hex_corners(Vector2.ZERO, _hull_renderer.cell_size)
			shape.position = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
			add_child(shape)
			_collision_shapes.append(shape)


func _apply_layout_thrust() -> void:
	thrust_force = ship_layout.total_thrust()
	reverse_thrust_force = thrust_force * reverse_thrust_ratio

	var acceleration_estimate: float = (thrust_force / mass) if mass > 0.0 else 0.0
	max_speed = acceleration_estimate * speed_per_acceleration
	reverse_max_speed = max_speed * reverse_speed_ratio


func _spawn_thrusters() -> void:
	for thruster in _thrusters:
		thruster.queue_free()
	_thrusters.clear()

	for placement in ship_layout.get_thruster_placements():
		var thruster: Node2D = engine_thruster_scene.instantiate()
		add_child(thruster)
		thruster.position = HexUtils.axial_to_pixel(placement.hex_coord, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
		_thrusters.append(thruster)


func _on_health_changed(_current: float, _max: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_hull_renderer.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_hull_renderer, "modulate", _base_hull_modulate, hit_flash_duration)


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

	# Generous absolute safety net (not a directional cap) so nothing — e.g.
	# weapon recoil stacking — can send velocity unbounded; normal flight,
	# including turning around while carrying momentum, never reaches it.
	velocity = velocity.limit_length(max_speed * boost_multiplier)

	move_and_slide()
	_update_engine_particles()


func _update_engine_particles() -> void:
	var thrusting_forward: bool = _thrust_input > 0.0
	var boosting: bool = thrusting_forward and _boost_active

	for thruster in _thrusters:
		var particles: GPUParticles2D = thruster.get_node("Particles")
		var particles_soft: GPUParticles2D = thruster.get_node("ParticlesSoft")
		var particles_normal: GPUParticles2D = thruster.get_node("ParticlesNormal")

		particles.emitting = boosting
		particles.amount_ratio = 1.0

		particles_soft.emitting = boosting
		particles_soft.amount_ratio = 1.0

		particles_normal.emitting = thrusting_forward and not boosting

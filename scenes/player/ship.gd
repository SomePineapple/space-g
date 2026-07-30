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
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and taking damage will play it automatically.
@export var hit_sound: AudioStream = null
@export var ship_layout: ShipLayout = preload("res://resources/ships/starter_ship_layout.tres")
## Defaults to USER (no AI behavior) since PlayerInput drives the player
## ship; enemy scenes override this to a Rammer/Sniper/etc. resource so
## ShipAI knows how to fly and fight.
@export var personality: ShipPersonality = preload("res://resources/ai/personality_user.tres")
@export var engine_thruster_scene: PackedScene = preload("res://scenes/player/engine_thruster.tscn")
@export var hardpoint_gun_scene: PackedScene = preload("res://scenes/player/hardpoint_gun.tscn")
@export var hardpoint_missile_launcher_scene: PackedScene = preload("res://scenes/player/hardpoint_missile_launcher.tscn")
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
var _hardpoint_guns: Array[HardpointGun] = []
var _missile_launchers: Array[HardpointMissileLauncher] = []
var _weapon_upgrade_modifiers: Dictionary = {}
var _missile_upgrade_modifiers: Dictionary = {}
var _aim_target: Vector2 = Vector2.ZERO
var _has_aim_target: bool = false
var _locked_target: Node2D = null
var _last_known_health: float = -1.0

@onready var _health: Health = $Health
@onready var _hull_renderer: ShipLayoutRenderer = $HullRenderer
@onready var _inventory: Inventory = $Inventory
@onready var _hit_sound_player: AudioStreamPlayer2D = $HitSound


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
	_spawn_hardpoint_guns()
	_spawn_missile_launchers()
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


func _spawn_hardpoint_guns() -> void:
	for gun in _hardpoint_guns:
		gun.queue_free()
	_hardpoint_guns.clear()

	for placement in ship_layout.get_weapon_hardpoint_placements():
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		var gun: HardpointGun = hardpoint_gun_scene.instantiate()
		add_child(gun)
		gun.position = _hardpoint_center(placement)
		gun.set_cell_size(_hull_renderer.cell_size, HardpointGun.tier_visual_scale(module_type.tier))
		gun.apply_tier(module_type.tier)
		gun.setup(self)
		for property_name in _weapon_upgrade_modifiers:
			gun.set(property_name, gun.get(property_name) + _weapon_upgrade_modifiers[property_name])
		_hardpoint_guns.append(gun)


func _spawn_missile_launchers() -> void:
	for launcher in _missile_launchers:
		launcher.queue_free()
	_missile_launchers.clear()

	for placement in ship_layout.get_missile_hardpoint_placements():
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		var launcher: HardpointMissileLauncher = hardpoint_missile_launcher_scene.instantiate()
		add_child(launcher)
		launcher.position = _hardpoint_center(placement)
		launcher.set_cell_size(_hull_renderer.cell_size, HardpointGun.tier_visual_scale(module_type.tier))
		launcher.apply_tier(module_type.tier)
		launcher.setup(self)
		for property_name in _missile_upgrade_modifiers:
			launcher.set(property_name, launcher.get(property_name) + _missile_upgrade_modifiers[property_name])
		_missile_launchers.append(launcher)


## Centroid of a hardpoint's occupied cells, so multi-hex (tier 2/3)
## hardpoints mount their gun/launcher in the middle of their footprint
## rather than at the anchor cell's corner.
func _hardpoint_center(placement: ModulePlacement) -> Vector2:
	var occupied_cells: Array[Vector2i] = ship_layout.get_occupied_cells(placement)
	var center_local: Vector2 = Vector2.ZERO
	for cell in occupied_cells:
		center_local += HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size)
	center_local /= occupied_cells.size()
	return center_local.rotated(_hull_renderer.rotation)


## Routes "Weapon" upgrade-tree modifiers to every mounted hardpoint gun
## instead of a single fixed node, and remembers them so a ship rebuild
## (e.g. from the builder) reapplies purchased upgrades to the new guns.
func apply_weapon_modifier(property_name: String, delta: float) -> void:
	_weapon_upgrade_modifiers[property_name] = _weapon_upgrade_modifiers.get(property_name, 0.0) + delta
	for gun in _hardpoint_guns:
		gun.set(property_name, gun.get(property_name) + delta)


## Same as apply_weapon_modifier(), for "MissileLauncher" upgrade-tree entries.
func apply_missile_modifier(property_name: String, delta: float) -> void:
	_missile_upgrade_modifiers[property_name] = _missile_upgrade_modifiers.get(property_name, 0.0) + delta
	for launcher in _missile_launchers:
		launcher.set(property_name, launcher.get(property_name) + delta)


func set_aim_target(target: Vector2) -> void:
	_aim_target = target
	_has_aim_target = true


func get_aim_target() -> Vector2:
	return _aim_target if _has_aim_target else global_position + transform.x * 1000.0


## The object homing missiles should steer toward: manually toggled by the
## player's lock-on (see ship_input.gd) or automatically set to whatever an
## AI ship is currently pursuing (see ship_ai.gd). Null means "no lock" —
## HardpointMissileLauncher then fires unguided, straight-outward missiles.
func set_locked_target(target: Node2D) -> void:
	_locked_target = target


func get_locked_target() -> Node2D:
	if _locked_target != null and not is_instance_valid(_locked_target):
		_locked_target = null
	return _locked_target


## Only current < last-known counts as damage — configure() (ship rebuilds
## in the builder) also emits health_changed, but resets to full health
## rather than lowering it, so it never falls through to the hit feedback.
func _on_health_changed(current: float, _max: float) -> void:
	var took_damage: bool = _last_known_health >= 0.0 and current < _last_known_health
	_last_known_health = current

	if took_damage and hit_sound != null:
		_hit_sound_player.stream = hit_sound
		_hit_sound_player.play()

	if _flash_tween:
		_flash_tween.kill()
	_hull_renderer.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_hull_renderer, "modulate", _base_hull_modulate, hit_flash_duration)


func fire_primary() -> void:
	for gun in _hardpoint_guns:
		gun.fire()


func fire_secondary() -> void:
	for launcher in _missile_launchers:
		launcher.fire()


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


func add_salvage(amount: int) -> void:
	_inventory.add_salvage(amount)


func apply_impulse(impulse: Vector2) -> void:
	velocity += impulse / mass


## Deferred as a whole: this fires from within the physics engine's
## collision query flush (via Projectile's body_entered signal), and both
## adding the Salvage Area2D to the tree and freeing this body would
## otherwise touch physics server shape state mid-flush.
func _on_destroyed() -> void:
	_finish_destruction.call_deferred()


func _finish_destruction() -> void:
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
	_update_hardpoint_aim()


func _update_hardpoint_aim() -> void:
	if _hardpoint_guns.is_empty() and _missile_launchers.is_empty():
		return
	var aim_target: Vector2 = get_aim_target()
	for gun in _hardpoint_guns:
		gun.aim_at(aim_target)
	for launcher in _missile_launchers:
		launcher.aim_at(aim_target)


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

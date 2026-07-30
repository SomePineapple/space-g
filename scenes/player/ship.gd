class_name Ship
extends CharacterBody2D

signal layout_applied
signal energy_changed(current: float, max_energy: float)

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
@export var ship_debris_scene: PackedScene = preload("res://scenes/world/ship_debris.tscn")
@export var seam_spark_scene: PackedScene = preload("res://scenes/world/seam_spark.tscn")
## Fraction of a hit's damage that also lands on the modules directly
## adjacent to the exact hex hit. Landing a hit on precisely the same hex
## repeatedly (needed to break a specific module) is hard against a moving,
## rotating target; without this, focused fire on a wing feels like it does
## nothing until one lucky hit lines up exactly right.
@export var module_splash_fraction: float = 0.35

## Outward speed/spin added on top of the ship's own velocity when a module
## detaches, so a severed wing visibly kicks away rather than just trailing
## along at the exact same velocity as the ship that lost it.
const DETACH_KICK_SPEED: float = 60.0
const DETACH_SPIN_RANGE: float = 2.0

## Energy pool available even with no Reactor/Battery modules installed, so
## existing ship layouts (pirates, the starter ship) keep working once
## weapons/thrusters/tractor beam start actually spending energy — reactor
## and battery modules add on top of this baseline.
@export var base_energy_generation: float = 10.0
@export var base_energy_capacity: float = 50.0
## Energy/sec spent thrusting at full non-boosted throttle. Deliberately at
## or below base_energy_generation so cruising is sustainable forever on
## base power alone — firing weapons or boosting is what actually draws the
## reserve down without a Reactor installed.
@export var thrust_energy_cost: float = 8.0

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

var current_energy: float = 0.0
var max_energy: float = 0.0
var energy_generation_rate: float = 0.0

## Per-placement runtime hit points (placement_id -> current condition),
## separate from the overall Health pool: a module can be individually
## knocked out mid-fight without that being a second way to destroy the
## ship. Rebuilt fresh whenever a layout is applied — never stored on the
## ShipLayout resource itself, since that resource is shared (not
## duplicated) across every instance of the same enemy scene.
var _module_conditions: Dictionary = {}

## placement_id -> true. A module ends up here when it's still intact but
## has lost its connection back to the core (see _check_for_detachment) —
## distinct from _module_conditions reaching zero, which means the module
## itself was destroyed outright. Either way counts as "gone" for gameplay
## purposes (see is_module_destroyed).
var _detached_placement_ids: Dictionary = {}

## placement_id -> Array[CollisionPolygon2D], so a detached module's hitbox
## can be removed from this ship's body along with its visual.
var _collision_shapes_by_placement: Dictionary = {}

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
	_init_module_conditions()
	_apply_layout_energy()
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
	_collision_shapes_by_placement.clear()

	for placement in ship_layout.placements:
		var shapes_for_placement: Array = []
		for cell in ship_layout.get_occupied_cells(placement):
			var shape := CollisionPolygon2D.new()
			shape.polygon = HexUtils.hex_corners(Vector2.ZERO, _hull_renderer.cell_size)
			shape.position = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
			add_child(shape)
			_collision_shapes.append(shape)
			shapes_for_placement.append(shape)
		_collision_shapes_by_placement[placement.placement_id] = shapes_for_placement


func _init_module_conditions() -> void:
	_module_conditions.clear()
	_detached_placement_ids.clear()
	for placement in ship_layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			_module_conditions[placement.placement_id] = module_type.health_contribution


func get_module_condition(placement_id: String) -> float:
	return _module_conditions.get(placement_id, 0.0)


## True if the module is either destroyed outright (condition at zero) or
## still intact but severed from the core's connectivity graph — both mean
## it no longer contributes to the ship (see _on_module_destroyed and
## _detach_module).
func is_module_destroyed(placement_id: String) -> bool:
	return get_module_condition(placement_id) <= 0.0 or _detached_placement_ids.has(placement_id)


## Resolves a world-space impact point to the specific module occupying that
## hex cell (if any) and damages it, plus a splash fraction to its immediate
## neighbors, independent of the ship's overall Health pool. Destroying an
## engine this way costs the ship real thrust; destroying a weapon/missile
## hardpoint stops it firing (see fire_primary/fire_secondary) — both react
## live, no rebuild needed.
func _damage_module_at_point(amount: float, impact_point: Vector2) -> void:
	if ship_layout == null:
		return

	var hull_local: Vector2 = to_local(impact_point).rotated(-_hull_renderer.rotation)
	var hex_coord: Vector2i = HexUtils.pixel_to_axial(hull_local, _hull_renderer.cell_size)
	var placement: ModulePlacement = ship_layout.get_placement_at(hex_coord)
	if placement != null:
		_apply_module_damage(placement, amount)

	for neighbor_coord in HexUtils.neighbors(hex_coord):
		var neighbor_placement: ModulePlacement = ship_layout.get_placement_at(neighbor_coord)
		# The Core is exempt from splash: it ends the ship outright if lost
		# (see _on_module_destroyed), so it shouldn't be catchable in
		# crossfire aimed at whatever else happens to be clustered around
		# it — only a hit landing squarely on it should count.
		if neighbor_placement != null and neighbor_placement != placement and neighbor_placement.placement_id != ship_layout.core_placement_id:
			_apply_module_damage(neighbor_placement, amount * module_splash_fraction)


func _apply_module_damage(placement: ModulePlacement, amount: float) -> void:
	if is_module_destroyed(placement.placement_id):
		return

	var remaining: float = maxf(get_module_condition(placement.placement_id) - amount, 0.0)
	_module_conditions[placement.placement_id] = remaining
	if remaining <= 0.0:
		_on_module_destroyed(placement)


func _on_module_destroyed(placement: ModulePlacement) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	_hull_renderer.set_module_destroyed(placement.placement_id)
	# A destroyed hex is a hole, not still-solid wreckage — without this, a
	# scorched module keeps blocking incoming shots aimed at whatever's
	# behind it (e.g. the connector further along a wing), which made
	# severing a wing much harder than intended.
	_free_collision_shapes_for(placement.placement_id)

	# Losing the Core ends the ship outright: without it there's no anchor
	# left to measure "still connected" against, so detachment checks would
	# otherwise go permanently inert and leftover modules would sit attached
	# to a dead, driverless hulk forever (see find_unreachable_from_core).
	if placement.placement_id == ship_layout.core_placement_id:
		_health.take_damage(_health.current_health)
		return

	if module_type.thrust_contribution > 0.0:
		thrust_force = maxf(thrust_force - module_type.thrust_contribution, 0.0)
		reverse_thrust_force = thrust_force * reverse_thrust_ratio

	_check_for_detachment()
	_check_all_modules_gone()


## The overall Health pool and per-module condition are deliberately separate
## (see _module_conditions), but splash damage (module_splash_fraction) lets
## modules collectively take more cumulative damage than Health ever
## registers, since a splash hit only affects modules, not Health. Without
## this, a ship can end up with every module destroyed/detached — visually a
## dead hulk — while Health still has some left and the ship keeps flying
## and fighting. Once nothing is left, finish the ship off for real.
func _check_all_modules_gone() -> void:
	if ship_layout == null or ship_layout.placements.is_empty():
		return
	for placement in ship_layout.placements:
		if not is_module_destroyed(placement.placement_id):
			return
	_health.take_damage(_health.current_health)


## After any module is destroyed outright, some other still-intact modules
## may no longer have a path back to the core through adjacent modules —
## a wing losing the one piece connecting it to the hull, for example. Any
## such module is severed for good: it stops contributing (is_module_destroyed
## now returns true for it) and flies off as its own debris piece.
func _check_for_detachment() -> void:
	if ship_layout == null:
		return

	var gone: Dictionary = {}
	for placement in ship_layout.placements:
		if is_module_destroyed(placement.placement_id):
			gone[placement.placement_id] = true

	var newly_unreachable: Array[String] = ship_layout.find_unreachable_from_core(gone)
	if not newly_unreachable.is_empty():
		_spawn_severance_sparks(newly_unreachable)

	for placement_id in newly_unreachable:
		_detach_module(ship_layout.get_placement_by_id(placement_id))


## Sparks trace the exact hex edge(s) where a severed wing tears away from
## the rest of the hull, one burst per boundary edge, rather than a single
## generic burst at the ship's center — reads as the connection itself
## breaking, especially for a multi-hex limb detaching all at once.
func _spawn_severance_sparks(detached_placement_ids: Array[String]) -> void:
	var detached_cells: Dictionary = {}
	for placement_id in detached_placement_ids:
		var placement: ModulePlacement = ship_layout.get_placement_by_id(placement_id)
		if placement == null:
			continue
		for cell in ship_layout.get_occupied_cells(placement):
			detached_cells[cell] = true

	for cell in detached_cells:
		for neighbor in HexUtils.neighbors(cell):
			# Only spark where another module (still attached, or the
			# destroyed connector that caused this severance) actually sits —
			# skip edges facing open space, which aren't a "seam" at all.
			if not detached_cells.has(neighbor) and ship_layout.is_occupied(neighbor):
				_spawn_seam_spark_at(cell, neighbor)


func _spawn_seam_spark_at(cell: Vector2i, neighbor: Vector2i) -> void:
	var cell_center: Vector2 = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size)
	var neighbor_center: Vector2 = HexUtils.axial_to_pixel(neighbor, _hull_renderer.cell_size)
	var edge_midpoint: Vector2 = (cell_center + neighbor_center) * 0.5
	var local_outward: Vector2 = (neighbor_center - cell_center).normalized()

	var spark: Node2D = seam_spark_scene.instantiate()
	get_tree().current_scene.add_child(spark)
	spark.global_position = _hull_renderer.global_transform * edge_midpoint
	spark.global_rotation = _hull_renderer.global_transform.basis_xform(local_outward).angle()


func _detach_module(placement: ModulePlacement) -> void:
	if placement == null or _detached_placement_ids.has(placement.placement_id):
		return
	_detached_placement_ids[placement.placement_id] = true

	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	# A module destroyed by a direct hit already lost its stat contribution in
	# _on_module_destroyed; only apply it here for a module that detaches
	# while still otherwise intact.
	if module_type.thrust_contribution > 0.0 and get_module_condition(placement.placement_id) > 0.0:
		thrust_force = maxf(thrust_force - module_type.thrust_contribution, 0.0)
		reverse_thrust_force = thrust_force * reverse_thrust_ratio

	_hull_renderer.set_module_detached(placement.placement_id)
	_free_collision_shapes_for(placement.placement_id)
	_spawn_debris_for(placement, module_type)


func _free_collision_shapes_for(placement_id: String) -> void:
	var shapes: Array = _collision_shapes_by_placement.get(placement_id, [])
	for shape in shapes:
		_collision_shapes.erase(shape)
		shape.queue_free()
	_collision_shapes_by_placement.erase(placement_id)


func _spawn_debris_for(placement: ModulePlacement, module_type: ModuleType) -> void:
	var cells: Array[Vector2i] = ship_layout.get_occupied_cells(placement)
	var colors: Array[Color] = []
	var textures: Array[Texture2D] = []
	var local_centroid: Vector2 = Vector2.ZERO
	for cell in cells:
		colors.append(module_type.color)
		textures.append(module_type.hex_texture)
		local_centroid += HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size)
	local_centroid /= cells.size()

	var debris: ShipDebris = ship_debris_scene.instantiate()
	get_tree().current_scene.add_child(debris)
	# Same transform as HullRenderer (ship center + its fixed rotation offset),
	# so the debris's cells render exactly where they were an instant ago,
	# before drifting away under their own velocity.
	debris.global_transform = _hull_renderer.global_transform

	var kick_direction: Vector2 = debris.global_transform.basis_xform(local_centroid)
	kick_direction = kick_direction.normalized() if kick_direction.length() > 0.001 else Vector2.RIGHT.rotated(debris.global_rotation)

	debris.setup(cells, colors, textures, _hull_renderer.cell_size,
		velocity + kick_direction * DETACH_KICK_SPEED, randf_range(-DETACH_SPIN_RANGE, DETACH_SPIN_RANGE))


## New max_energy keeps the same fraction full rather than resetting to full
## or to the old absolute amount, so refitting a ship (builder, upgrades)
## doesn't grant or destroy energy out of nowhere.
func _apply_layout_energy() -> void:
	var previous_fraction: float = (current_energy / max_energy) if max_energy > 0.0 else 1.0
	max_energy = base_energy_capacity + ship_layout.total_energy_capacity()
	energy_generation_rate = base_energy_generation + ship_layout.total_energy_generation()
	current_energy = max_energy * previous_fraction
	energy_changed.emit(current_energy, max_energy)


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
		gun.apply_core_distance_bonus(ship_layout.distance_from_core(placement))
		gun.setup(self)
		gun.source_placement_id = placement.placement_id
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
		launcher.apply_core_distance_bonus(ship_layout.distance_from_core(placement))
		launcher.setup(self)
		launcher.source_placement_id = placement.placement_id
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
		if not is_module_destroyed(gun.source_placement_id):
			gun.fire()


func fire_secondary() -> void:
	for launcher in _missile_launchers:
		if not is_module_destroyed(launcher.source_placement_id):
			launcher.fire()


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


## Same as take_damage(), but also attributes the hit to whichever module
## occupies the impact point, so individual engines/weapons can be knocked
## out mid-fight — the ship's overall Health pool takes the same damage
## either way; module condition is a separate, parallel effect.
func take_damage_at(amount: float, impact_point: Vector2) -> void:
	take_damage(amount)
	_damage_module_at_point(amount, impact_point)


func add_material(material_id: String, amount: int) -> void:
	_inventory.add_material(material_id, amount)


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
	_regenerate_energy(delta)
	rotation += _turn_input * rotation_speed * delta

	if _thrust_input != 0.0 and _try_spend_thrust_energy(delta):
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
		# No thrust input, or thrust requested but not enough energy for it —
		# either way the ship just coasts/drags rather than accelerating.
		velocity = velocity.move_toward(Vector2.ZERO, drag * max_speed * delta)

	# Generous absolute safety net (not a directional cap) so nothing — e.g.
	# weapon recoil stacking — can send velocity unbounded; normal flight,
	# including turning around while carrying momentum, never reaches it.
	velocity = velocity.limit_length(max_speed * boost_multiplier)

	move_and_slide()
	_update_engine_particles()
	_update_hardpoint_aim()


func has_energy(amount: float) -> bool:
	return current_energy >= amount


func spend_energy(amount: float) -> bool:
	if current_energy < amount:
		return false
	current_energy -= amount
	energy_changed.emit(current_energy, max_energy)
	return true


## Boosted thrust costs proportionally more, same multiplier as the extra
## speed/force it grants.
func _try_spend_thrust_energy(delta: float) -> bool:
	var boosting: bool = _boost_active and _thrust_input > 0.0
	var cost: float = thrust_energy_cost * absf(_thrust_input) * (boost_multiplier if boosting else 1.0) * delta
	return spend_energy(cost)


func _regenerate_energy(delta: float) -> void:
	if current_energy >= max_energy:
		return
	current_energy = minf(current_energy + energy_generation_rate * delta, max_energy)
	energy_changed.emit(current_energy, max_energy)


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

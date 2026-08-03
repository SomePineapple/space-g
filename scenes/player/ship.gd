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
@export var hardpoint_winch_scene: PackedScene = preload("res://scenes/player/hardpoint_winch.tscn")
@export var hardpoint_tractor_beam_scene: PackedScene = preload("res://scenes/player/hardpoint_tractor_beam.tscn")
@export var hardpoint_grinder_scene: PackedScene = preload("res://scenes/player/hardpoint_grinder.tscn")
@export var reverse_thrust_ratio: float = 0.2
@export var speed_per_acceleration: float = 1.0
@export var reverse_speed_ratio: float = 0.35
@export var ship_debris_scene: PackedScene = preload("res://scenes/world/ship_debris.tscn")
@export var captured_tech_part_scene: PackedScene = preload("res://scenes/world/captured_tech_part.tscn")
@export var seam_spark_scene: PackedScene = preload("res://scenes/world/seam_spark.tscn")
## Fraction of a hit's damage that also lands on the modules directly
## adjacent to the exact hex hit. Landing a hit on precisely the same hex
## repeatedly (needed to break a specific module) is hard against a moving,
## rotating target; without this, focused fire on a wing feels like it does
## nothing until one lucky hit lines up exactly right.
@export var module_splash_fraction: float = 0.35

## Seconds the ship must go without taking any damage before holed-out
## modules start regrowing. Prevents repair from meaningfully undoing damage
## mid-fight — it's a recovery mechanic for between engagements, not a heal
## button under fire.
@export var module_repair_delay: float = 6.0
## Condition/second restored to a regrowing module once it's eligible.
@export var module_repair_rate: float = 6.0
## Passive regrowth (above) only brings a holed-out module back to this
## fraction of its max condition — the rest requires a paid repair at a
## station (see repair_fully). Exported so it can be tuned now and raised
## later by an upgrade.
@export var passive_repair_cap_fraction: float = 0.4
## Credits charged per point of overall Health restored by repair_fully.
@export var repair_cost_per_health: float = 1.0

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
## Cargo capacity available even with no Storage modules installed, matching
## the same "baseline + layout total" shape as base_energy_capacity above.
@export var base_cargo_capacity: float = 100.0
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
## Parallel to _thrusters — which placement each thruster's flame belongs to,
## so a destroyed/detached engine's particles can be silenced individually
## even while other engines (or leftover momentum) keep the ship moving.
var _thruster_placement_ids: Array[String] = []
var _collision_shapes: Array[CollisionPolygon2D] = []
var _hardpoint_guns: Array[HardpointGun] = []
var _missile_launchers: Array[HardpointMissileLauncher] = []
var _winch_hardpoints: Array[HardpointWinch] = []
var _tractor_beam_hardpoints: Array[HardpointTractorBeam] = []
var _grinder_hardpoints: Array[HardpointGrinder] = []
## Toggled by Ship.toggle_grinder ("G" — see ship_input.gd), pulled every
## frame by each mounted HardpointGrinder, same pull-model as
## is_module_destroyed. Unlike the Tractor Beam, grinding needs deliberate
## activation since it deals continuous damage.
var _grinder_active: bool = false
var _weapon_upgrade_modifiers: Dictionary = {}
var _missile_upgrade_modifiers: Dictionary = {}
var _aim_target: Vector2 = Vector2.ZERO
var _has_aim_target: bool = false
var _locked_target: Node2D = null
var _last_known_health: float = -1.0
var _time_since_last_damage: float = 0.0

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

## placement_id -> true. A holed-out module regrowing (see _regenerate_modules)
## stays here — and counts as destroyed for every gameplay purpose, same as
## _detached_placement_ids — for its whole climb back to full condition, not
## just while condition is at zero. Without this, is_module_destroyed would
## flip back to false (restoring fire/thrust) the instant condition ticked
## above zero, and a multi-hex hole's neighbors would all unlock on top of
## each other in the same frame instead of visibly sweeping outward.
var _regrowing_placement_ids: Dictionary = {}

@onready var _health: Health = $Health
@onready var _hull_renderer: ShipLayoutRenderer = $HullRenderer
@onready var _inventory: Inventory = $Inventory
@onready var _hit_sound_player: AudioStreamPlayer2D = $HitSound
@onready var _scanner: Scanner = $Scanner


func _ready() -> void:
	_apply_ship_layout()
	_health.destroyed.connect(_on_destroyed)
	_health.health_changed.connect(_on_health_changed)
	_base_hull_modulate = _hull_renderer.modulate

	if is_in_group("player_ship"):
		GameState.apply(self)


func apply_layout(new_layout: ShipLayout) -> void:
	ship_layout = new_layout
	_apply_ship_layout()


func _apply_ship_layout() -> void:
	if ship_layout == null:
		return
	mass = ship_layout.total_mass()
	_health.configure(ship_layout.total_max_health() * personality.health_multiplier)
	_hull_renderer.faction_id = personality.faction_id
	_hull_renderer.set_layout(ship_layout)
	_init_module_conditions()
	_apply_layout_energy()
	_apply_layout_cargo_capacity()
	_apply_layout_thrust()
	_spawn_thrusters()
	_spawn_collision_shapes()
	_spawn_hardpoint_guns()
	_spawn_missile_launchers()
	_spawn_hardpoint_winches()
	_spawn_hardpoint_tractor_beams()
	_spawn_hardpoint_grinders()
	layout_applied.emit()


## Approximate "collision radius" for HardpointWinch's touch/arrival checks
## against another ship — see get_layout_extent(), which this just aliases
## under a name meaningful to the winch.
func get_winch_radius() -> float:
	return get_layout_extent()


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
		_spawn_collision_shape_for(placement)


## Split out from _spawn_collision_shapes() so a single repaired module (see
## _on_module_repaired) can get its shape back without rebuilding every other
## placement's shapes too.
func _spawn_collision_shape_for(placement: ModulePlacement) -> void:
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
	_regrowing_placement_ids.clear()
	for placement in ship_layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			_module_conditions[placement.placement_id] = module_type.health_contribution * personality.health_multiplier


func get_module_condition(placement_id: String) -> float:
	return _module_conditions.get(placement_id, 0.0)


## True if the module is either destroyed outright (condition at zero) or
## still intact but severed from the core's connectivity graph — both mean
## it no longer contributes to the ship (see _on_module_destroyed and
## _detach_module).
func is_module_destroyed(placement_id: String) -> bool:
	if _detached_placement_ids.has(placement_id) or _regrowing_placement_ids.has(placement_id):
		return true
	return get_module_condition(placement_id) <= 0.0


func get_missing_health() -> float:
	return _health.max_health - _health.current_health


func needs_repair() -> bool:
	return get_missing_health() > 0.01


func get_repair_cost() -> int:
	return ceili(get_missing_health() * repair_cost_per_health)


## Paid station repair: tops every attached module back to full condition
## (bypassing passive_repair_cap_fraction) and heals the overall Health pool
## to match. Detached (severed) modules are excluded — they're gone, not
## repairable in place.
func repair_fully() -> void:
	if ship_layout == null:
		return

	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var max_condition: float = module_type.health_contribution * personality.health_multiplier
		if get_module_condition(placement.placement_id) >= max_condition:
			continue

		var was_regrowing: bool = _regrowing_placement_ids.has(placement.placement_id)
		_module_conditions[placement.placement_id] = max_condition
		if was_regrowing:
			_regrowing_placement_ids.erase(placement.placement_id)
			_on_module_repaired(placement, module_type)

	_health.heal(get_missing_health())


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


## Public entry point for a hardpoint to damage its own mount (e.g. a Black
## Market Foundry weapon backfiring, see HardpointGun.malfunction_chance) —
## reuses the exact same per-module damage pathway a normal hit uses, so a
## bad enough malfunction streak can genuinely sever the weapon's own module.
func damage_own_module(placement_id: String, amount: float) -> void:
	var placement: ModulePlacement = ship_layout.get_placement_by_id(placement_id)
	if placement != null:
		_apply_module_damage(placement, amount)


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
	_set_hardpoint_visual_visible(placement.placement_id, false)

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


## Regrows holed-out (destroyed but still attached) modules over time, one
## ring at a time outward from whatever's still healthy — a module can only
## *start* regrowing once it has a neighbor that isn't itself destroyed (or
## already mid-regrow), and it stays non-functional for its whole climb back
## to full condition (see _regrowing_placement_ids), so a multi-hex hole
## visibly sweeps outward from the healthy edge inward rather than every hex
## in it popping back at once. Detached (severed) modules are excluded
## entirely — a piece that's already flown off as debris has nothing to grow
## back onto.
func _regenerate_modules(delta: float) -> void:
	if ship_layout == null or _time_since_last_damage < module_repair_delay:
		return

	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue
		var max_condition: float = module_type.health_contribution * personality.health_multiplier

		if not _regrowing_placement_ids.has(placement.placement_id):
			if get_module_condition(placement.placement_id) > 0.0:
				continue # undamaged, or only combat-damaged rather than holed out
			if not _has_healthy_neighbor(placement):
				continue # nothing healthy adjacent yet for this hex to grow back from
			_regrowing_placement_ids[placement.placement_id] = true

		_advance_module_repair(placement, module_type, max_condition, delta)


func _has_healthy_neighbor(placement: ModulePlacement) -> bool:
	for cell in ship_layout.get_occupied_cells(placement):
		for neighbor_coord in HexUtils.neighbors(cell):
			var neighbor_placement: ModulePlacement = ship_layout.get_placement_at(neighbor_coord)
			if neighbor_placement != null and not is_module_destroyed(neighbor_placement.placement_id):
				return true
	return false


func _advance_module_repair(placement: ModulePlacement, module_type: ModuleType, max_condition: float, delta: float) -> void:
	var passive_cap: float = max_condition * passive_repair_cap_fraction
	var current_condition: float = get_module_condition(placement.placement_id)
	if current_condition >= passive_cap:
		return # capped: needs a paid repair (see repair_fully) to go further

	var new_condition: float = minf(current_condition + module_repair_rate * delta, passive_cap)
	var healed_amount: float = new_condition - current_condition
	_module_conditions[placement.placement_id] = new_condition
	_health.heal(healed_amount)

	if new_condition >= passive_cap:
		_regrowing_placement_ids.erase(placement.placement_id)
		_on_module_repaired(placement, module_type)


## Reverses _on_module_destroyed's effects once a holed-out module finishes
## regrowing to its passive cap (or is topped off by a paid repair): restores
## its stat contribution, collision shape and normal hull appearance all at
## once (fire_primary/fire_secondary/thrust all gate on is_module_destroyed,
## which only reads false once this runs — see _regrowing_placement_ids).
func _on_module_repaired(placement: ModulePlacement, module_type: ModuleType) -> void:
	_hull_renderer.set_module_repaired(placement.placement_id)
	_spawn_collision_shape_for(placement)
	_set_hardpoint_visual_visible(placement.placement_id, true)

	if module_type.thrust_contribution > 0.0:
		thrust_force += module_type.thrust_contribution
		reverse_thrust_force = thrust_force * reverse_thrust_ratio


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
	_set_hardpoint_visual_visible(placement.placement_id, false)

	if _roll_capturable(placement, module_type):
		_spawn_capturable_part_for(placement, module_type)
	else:
		_spawn_debris_for(placement, module_type)


func _free_collision_shapes_for(placement_id: String) -> void:
	var shapes: Array = _collision_shapes_by_placement.get(placement_id, [])
	for shape in shapes:
		_collision_shapes.erase(shape)
		shape.queue_free()
	_collision_shapes_by_placement.erase(placement_id)


## Shared by _spawn_debris_for/_spawn_capturable_part_for: both spawn a node
## representing the same severed placement's hex(es), just as a different
## scene type, so the cell/color/texture/centroid gathering only lives once.
## Uses the same per-cell, faction-reskinned texture lookup as
## ShipLayoutRenderer (get_hex_texture_for_cell) so the severed piece keeps
## showing the exact art it had on the hull, not the type's generic fallback.
func _debris_visual_data(placement: ModulePlacement, module_type: ModuleType) -> Dictionary:
	var cells: Array[Vector2i] = ship_layout.get_occupied_cells(placement)
	var colors: Array[Color] = []
	var textures: Array[Texture2D] = []
	var local_centroid: Vector2 = Vector2.ZERO
	for i in cells.size():
		colors.append(module_type.color)
		textures.append(module_type.get_hex_texture_for_cell(personality.faction_id, i))
		local_centroid += HexUtils.axial_to_pixel(cells[i], _hull_renderer.cell_size)
	local_centroid /= cells.size()
	return {"cells": cells, "colors": colors, "textures": textures, "rotation_steps": placement.rotation_steps, "centroid": local_centroid}


func _spawn_debris_for(placement: ModulePlacement, module_type: ModuleType) -> void:
	var data: Dictionary = _debris_visual_data(placement, module_type)

	var debris: ShipDebris = ship_debris_scene.instantiate()
	get_tree().current_scene.add_child(debris)
	# Same transform as HullRenderer (ship center + its fixed rotation offset),
	# so the debris's cells render exactly where they were an instant ago,
	# before drifting away under their own velocity.
	debris.global_transform = _hull_renderer.global_transform

	var kick_direction: Vector2 = debris.global_transform.basis_xform(data["centroid"])
	kick_direction = kick_direction.normalized() if kick_direction.length() > 0.001 else Vector2.RIGHT.rotated(debris.global_rotation)

	debris.setup(data["cells"], data["colors"], data["textures"], data["rotation_steps"], _hull_renderer.cell_size,
		velocity + kick_direction * DETACH_KICK_SPEED, randf_range(-DETACH_SPIN_RANGE, DETACH_SPIN_RANGE))


## A severed module only stays intact enough to be worth recovering if it
## kept most of its own health right up to the moment it detached (rather
## than being chewed apart first via splash/direct hits) — and even then only
## sometimes, so capture is a notable outcome, not a guaranteed drop every
## time a wing carrying real tech comes off (see ModuleType.is_capturable_tech).
func _roll_capturable(placement: ModulePlacement, module_type: ModuleType) -> bool:
	if not module_type.is_capturable_tech:
		return false
	var max_condition: float = module_type.health_contribution * personality.health_multiplier
	if max_condition <= 0.0:
		return false
	var condition_fraction: float = get_module_condition(placement.placement_id) / max_condition
	if condition_fraction < module_type.capture_health_fraction:
		return false
	return randf() < module_type.capture_chance


func _spawn_capturable_part_for(placement: ModulePlacement, module_type: ModuleType) -> void:
	var data: Dictionary = _debris_visual_data(placement, module_type)

	var part: CapturedTechPart = captured_tech_part_scene.instantiate()
	get_tree().current_scene.add_child(part)
	part.global_transform = _hull_renderer.global_transform

	var kick_direction: Vector2 = part.global_transform.basis_xform(data["centroid"])
	kick_direction = kick_direction.normalized() if kick_direction.length() > 0.001 else Vector2.RIGHT.rotated(part.global_rotation)

	part.setup(data["cells"], data["colors"], data["textures"], data["rotation_steps"], _hull_renderer.cell_size,
		velocity + kick_direction * DETACH_KICK_SPEED, randf_range(-DETACH_SPIN_RANGE, DETACH_SPIN_RANGE),
		module_type.id, personality.faction_id, placement.manufacturer_id)


## New max_energy keeps the same fraction full rather than resetting to full
## or to the old absolute amount, so refitting a ship (builder, upgrades)
## doesn't grant or destroy energy out of nowhere.
func _apply_layout_energy() -> void:
	var previous_fraction: float = (current_energy / max_energy) if max_energy > 0.0 else 1.0
	max_energy = base_energy_capacity + ship_layout.total_energy_capacity()
	energy_generation_rate = base_energy_generation + ship_layout.total_energy_generation()
	current_energy = max_energy * previous_fraction
	energy_changed.emit(current_energy, max_energy)


func _apply_layout_cargo_capacity() -> void:
	_inventory.set_cargo_capacity(base_cargo_capacity + ship_layout.total_cargo_capacity())


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
	_thruster_placement_ids.clear()

	for placement in ship_layout.get_thruster_placements():
		var thruster: Node2D = engine_thruster_scene.instantiate()
		add_child(thruster)
		# Offset from the hex's center toward its trailing vertex, so the
		# flame visually bursts from the back tip of the hex instead of its
		# middle. This is in hex-grid-local space (same space as hex_center,
		# pre-_hull_renderer.rotation) — _hull_renderer.rotation is a fixed
		# +90° twist between the hex grid's own authored axes and the ship's
		# true movement-forward (+X) axis, so hex-grid-local "backward" is
		# +Y (a vertex per HexUtils.hex_corners), not -X. Only the *position*
		# needs that rotation applied (matching hex_center below) — the
		# thruster's own rotation stays default (0) so the particle's local
		# -X direction keeps pointing at the ship's real physics-backward,
		# not doubly twisted by the hex grid's separate authoring offset.
		var hex_center: Vector2 = HexUtils.axial_to_pixel(placement.hex_coord, _hull_renderer.cell_size)
		var back_vertex_offset: Vector2 = Vector2(0.0, _hull_renderer.cell_size)
		thruster.position = (hex_center + back_vertex_offset).rotated(_hull_renderer.rotation)
		_thrusters.append(thruster)
		_thruster_placement_ids.append(placement.placement_id)


func _spawn_hardpoint_guns() -> void:
	for gun in _hardpoint_guns:
		gun.queue_free()
	_hardpoint_guns.clear()

	for placement in ship_layout.get_weapon_hardpoint_placements():
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		var scene_to_spawn: PackedScene = module_type.hardpoint_scene if module_type.hardpoint_scene != null else hardpoint_gun_scene
		var gun: HardpointGun = scene_to_spawn.instantiate()
		add_child(gun)
		gun.position = _hardpoint_center(placement)
		gun.set_cell_size(_hull_renderer.cell_size, HardpointGun.tier_visual_scale(module_type.tier))
		gun.set_turret_texture(module_type.get_hex_overlay_texture(personality.faction_id))
		gun.apply_tier(module_type.tier)
		gun.apply_core_distance_bonus(ship_layout.distance_from_core(placement))
		gun.setup(self)
		gun.source_placement_id = placement.placement_id
		for property_name in _weapon_upgrade_modifiers:
			gun.set(property_name, gun.get(property_name) + _weapon_upgrade_modifiers[property_name])
		_apply_manufacturer_modifiers(gun, placement)
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
		_apply_manufacturer_modifiers(launcher, placement)
		_missile_launchers.append(launcher)


## Applies a placement's manufacturer stat_modifiers (additive deltas, same
## technique as the upgrade-tree modifiers above) to its spawned hardpoint
## node. Also passes through Black Market Foundry's malfunction risk, if any
## — see HardpointGun._apply_malfunction_damage.
func _apply_manufacturer_modifiers(node: Node, placement: ModulePlacement) -> void:
	var manufacturer: Manufacturer = ManufacturerCatalog.get_by_id(placement.manufacturer_id)
	if manufacturer == null:
		return
	for property_name in manufacturer.stat_modifiers:
		if property_name in node:
			node.set(property_name, node.get(property_name) + manufacturer.stat_modifiers[property_name])
	if "malfunction_chance" in node:
		node.set("malfunction_chance", manufacturer.malfunction_chance)
		node.set("malfunction_self_damage", manufacturer.malfunction_self_damage)


## Unlike guns/launchers, a winch hardpoint has a fixed facing rather than
## tracking the mouse (see HardpointWinch, Ship._update_hardpoint_aim) — its
## rotation is set once here from the placement's own rotation_steps (the
## same per-hex facing the ship builder's R hotkey already edits), plus the
## hull's fixed rendering offset, so "the direction the room is facing" is
## whatever the player pointed it at in the builder.
func _spawn_hardpoint_winches() -> void:
	for winch in _winch_hardpoints:
		winch.queue_free()
	_winch_hardpoints.clear()

	for placement in ship_layout.get_winch_hardpoint_placements():
		var winch: HardpointWinch = hardpoint_winch_scene.instantiate()
		add_child(winch)
		winch.position = _hardpoint_center(placement)
		winch.rotation = float(placement.rotation_steps) * (PI / 3.0) + _hull_renderer.rotation
		winch.setup(self)
		winch.source_placement_id = placement.placement_id
		_winch_hardpoints.append(winch)


## Tractor beam hardpoints aim nowhere in particular (the beam always targets
## whatever it finds, see HardpointTractorBeam) — spawned at the hardpoint's
## hex center only, no fixed facing needed.
func _spawn_hardpoint_tractor_beams() -> void:
	for tractor_beam in _tractor_beam_hardpoints:
		tractor_beam.queue_free()
	_tractor_beam_hardpoints.clear()

	for placement in ship_layout.get_tractor_hardpoint_placements():
		var tractor_beam: HardpointTractorBeam = hardpoint_tractor_beam_scene.instantiate()
		add_child(tractor_beam)
		tractor_beam.position = _hardpoint_center(placement)
		tractor_beam.setup(self)
		tractor_beam.source_placement_id = placement.placement_id
		_tractor_beam_hardpoints.append(tractor_beam)


## Same fixed-facing convention as _spawn_hardpoint_winches — the front cell
## (the actual contact point, see HardpointGrinder) is a specific direction
## out of the anchor cell, not aimed at anything, so it has to be set from
## the placement's own rotation_steps rather than left at the default.
func _spawn_hardpoint_grinders() -> void:
	for grinder in _grinder_hardpoints:
		grinder.queue_free()
	_grinder_hardpoints.clear()

	for placement in ship_layout.get_grinder_hardpoint_placements():
		var grinder: HardpointGrinder = hardpoint_grinder_scene.instantiate()
		add_child(grinder)
		grinder.position = _hardpoint_center(placement)
		grinder.rotation = float(placement.rotation_steps) * (PI / 3.0) + _hull_renderer.rotation
		grinder.set_cell_size(_hull_renderer.cell_size)
		grinder.setup(self)
		grinder.source_placement_id = placement.placement_id
		_grinder_hardpoints.append(grinder)


## Toggled by the toggle_grinder input action ("G" — see ship_input.gd).
## Every mounted, intact HardpointGrinder pulls this flag each physics frame
## (same pull-model as is_module_destroyed) rather than being pushed a
## one-shot command, so a grinder that mounts/repairs mid-toggle picks up
## the current state immediately instead of needing a fresh key press.
func toggle_grinder() -> void:
	_grinder_active = not _grinder_active


func is_grinder_active() -> bool:
	return _grinder_active


## A destroyed/detached module's hex goes dark (see _on_module_destroyed/
## _detach_module), but its HardpointGun/HardpointMissileLauncher is a
## separate node positioned on top of that hex — without this it kept
## floating there fully visible (turret and all) over a scorched or
## already-departed hole. Repairing a module (_on_module_repaired) reverses
## it. No-op for a placement that isn't a weapon/missile hardpoint.
func _set_hardpoint_visual_visible(placement_id: String, should_be_visible: bool) -> void:
	for gun in _hardpoint_guns:
		if gun.source_placement_id == placement_id:
			gun.visible = should_be_visible
			return
	for launcher in _missile_launchers:
		if launcher.source_placement_id == placement_id:
			launcher.visible = should_be_visible
			return
	for tractor_beam in _tractor_beam_hardpoints:
		if tractor_beam.source_placement_id == placement_id:
			tractor_beam.visible = should_be_visible
			return
	for grinder in _grinder_hardpoints:
		if grinder.source_placement_id == placement_id:
			grinder.visible = should_be_visible
			return


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


## Counter rather than a bool so overlapping nebula zones don't prematurely
## clear each other's effect when one is exited while still inside another.
var _nebula_depth: int = 0


func enter_nebula() -> void:
	_nebula_depth += 1


func exit_nebula() -> void:
	_nebula_depth = maxi(_nebula_depth - 1, 0)


func is_in_nebula() -> bool:
	return _nebula_depth > 0


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


## Called on fire_winch's just-pressed edge (see ship_input.gd) — starts a
## cast on every mounted, still-intact winch hardpoint (usually just one).
func fire_winch() -> void:
	for winch in _winch_hardpoints:
		if not is_module_destroyed(winch.source_placement_id):
			winch.fire()


## Called every physics frame with fire_winch's current held state — only
## has an effect on a winch that's already ATTACHED to a part (see
## HardpointWinch.set_reel_input).
func set_winch_reel_input(is_held: bool) -> void:
	for winch in _winch_hardpoints:
		if not is_module_destroyed(winch.source_placement_id):
			winch.set_reel_input(is_held)


## Toggled by the scan input action (see ship_input.gd) — starts scanning the
## nearest valid target if idle, cancels an in-progress scan otherwise.
func toggle_scan() -> void:
	_scanner.toggle_scan()


func get_scanner() -> Scanner:
	return _scanner


## Radar is a pure capability flag (see ModuleCatalog.RADAR_HARDPOINT_TYPE_ID)
## rather than a spawned hardpoint node — it has no fixed facing or world-space
## visual of its own, it just gates whether RadarDisplay (the HUD) runs at
## all. True if the layout has at least one radar hardpoint that isn't
## currently destroyed/detached.
func has_radar() -> bool:
	if ship_layout == null:
		return false
	for placement in ship_layout.get_radar_hardpoint_placements():
		if not is_module_destroyed(placement.placement_id):
			return true
	return false


## Same "pure capability flag" shape as has_radar() — see
## ModuleCatalog.SCANNER_HARDPOINT_TYPE_ID.
func has_scanner() -> bool:
	if ship_layout == null:
		return false
	for placement in ship_layout.get_scanner_hardpoint_placements():
		if not is_module_destroyed(placement.placement_id):
			return true
	return false


func take_damage(amount: float) -> void:
	_time_since_last_damage = 0.0
	_health.take_damage(amount)


## Same as take_damage(), but also attributes the hit to whichever module
## occupies the impact point, so individual engines/weapons can be knocked
## out mid-fight — the ship's overall Health pool takes the same damage
## either way; module condition is a separate, parallel effect.
func take_damage_at(amount: float, impact_point: Vector2) -> void:
	take_damage(amount)
	_damage_module_at_point(amount, impact_point)


## Fired by HardpointPhaseLance: unlike a normal hit (one hex + a splash
## fraction to its neighbors), a beam pierces straight through the hull,
## applying the full amount to every module hex it crosses from entry_point
## onward along aim_direction, up to max_travel_distance — including the
## Command Core, which splash damage deliberately never reaches (see
## module_splash_fraction). That's the point of this weapon: a well-aligned
## shot can punch through armor into whatever sits directly behind it.
## Overall Health only takes the hit once, same as a normal shot.
func take_beam_damage(amount: float, entry_point: Vector2, aim_direction: Vector2, max_travel_distance: float) -> void:
	take_damage(amount)
	if ship_layout == null or aim_direction.length() < 0.001:
		return

	var hull_local_origin: Vector2 = to_local(entry_point).rotated(-_hull_renderer.rotation)
	var hull_local_direction: Vector2 = aim_direction.rotated(-global_rotation - _hull_renderer.rotation).normalized()

	var step: float = _hull_renderer.cell_size * 0.5
	var traveled: float = 0.0
	var hit_placement_ids: Dictionary = {}

	while traveled <= max_travel_distance:
		var sample_point: Vector2 = hull_local_origin + hull_local_direction * traveled
		var hex_coord: Vector2i = HexUtils.pixel_to_axial(sample_point, _hull_renderer.cell_size)
		var placement: ModulePlacement = ship_layout.get_placement_at(hex_coord)
		if placement != null and not hit_placement_ids.has(placement.placement_id):
			hit_placement_ids[placement.placement_id] = true
			_apply_module_damage(placement, amount)
		traveled += step


func add_material(material_id: String, amount: int) -> void:
	_inventory.add_material(material_id, amount)


## Capacity-respecting version of add_material() — see Inventory.try_add_material.
## Used by Salvage pickup so a full cargo hold rejects the item instead of
## silently exceeding capacity.
func try_add_material(material_id: String, amount: int) -> bool:
	return _inventory.try_add_material(material_id, amount)


func discard_material(material_id: String, amount: int) -> int:
	return _inventory.discard_material(material_id, amount)


## Called by WinchBeam/HardpointTractorBeam once it finishes reeling in a
## CapturedTechPart. A non-empty manufacturer_id also discovers that
## manufacturer (see Inventory.discover_manufacturer) — separate from the
## per-module research unlock, since knowing "Atlas Heavy exists" is a
## different fact from "I can build a Weapon Hardpoint I."
func capture_tech_part(module_type_id: String, manufacturer_id: String = "") -> void:
	_inventory.add_captured_tech(module_type_id)
	if not manufacturer_id.is_empty():
		_inventory.discover_manufacturer(manufacturer_id)


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
	_time_since_last_damage += delta
	_regenerate_modules(delta)
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

	for i in _thrusters.size():
		var thruster: Node2D = _thrusters[i]
		# A destroyed/detached engine shouldn't keep showing its own flame,
		# even while other engines (or leftover momentum) keep the ship
		# actually moving forward.
		var alive: bool = not is_module_destroyed(_thruster_placement_ids[i])
		var particles: GPUParticles2D = thruster.get_node("Particles")
		var particles_soft: GPUParticles2D = thruster.get_node("ParticlesSoft")
		var particles_normal: GPUParticles2D = thruster.get_node("ParticlesNormal")

		particles.emitting = boosting and alive
		particles.amount_ratio = 1.0

		particles_soft.emitting = boosting and alive
		particles_soft.amount_ratio = 1.0

		particles_normal.emitting = thrusting_forward and not boosting and alive

class_name HullDamageModel
extends Node

## Per-module hull state for one ship: each placement's own condition, which
## placements are destroyed, severed or regrowing, and the collision shape each
## one contributes to the ship's body.
##
## Deliberately separate from the ship's overall Health pool — a module can be
## individually knocked out mid-fight without that being a second way to destroy
## the ship. This script owns that parallel model end to end (damage
## resolution, connectivity/detachment, passive regrowth, paid repair); ship.gd
## previously interleaved all of it with flight, energy and hardpoint code.
##
## Reports back to the ship through three signals rather than reaching for its
## Health node, so the ship stays the only thing that decides how its own health
## pool moves.

## Something changed that affects the ship's derived stats — a module was
## destroyed, severed or finished repairing. The ship re-sums thrust from
## whatever is still alive.
signal modules_changed
## A regrowing/repaired module restored this much condition; the ship's overall
## Health pool follows it up.
signal hull_healed(amount: float)
## Nothing functional is left (the Command Core is gone, or every module is).
## The ship finishes itself off.
signal hull_lost

## Fraction of a hit's damage that also lands on the modules directly adjacent
## to the exact hex hit. Landing a hit on precisely the same hex repeatedly
## (needed to break a specific module) is hard against a moving, rotating
## target; without this, focused fire on a wing feels like it does nothing until
## one lucky hit lines up exactly right.
@export var splash_fraction: float = 0.35

## Seconds the ship must go without taking any damage before holed-out modules
## start regrowing. Prevents repair from meaningfully undoing damage mid-fight —
## it's a recovery mechanic for between engagements, not a heal button under
## fire.
@export var repair_delay: float = 6.0
## Condition/second restored to a regrowing module once it's eligible.
@export var repair_rate: float = 6.0
## Passive regrowth only brings a holed-out module back to this fraction of its
## max condition — the rest requires a paid repair at a station (see
## repair_fully). Exported so it can be tuned now and raised later by an upgrade.
@export var passive_repair_cap_fraction: float = 0.4

var _ship: Ship
var _bank: HardpointBank
var _wreckage: WreckageSpawner
var _layout: ShipLayout
var _renderer: ShipLayoutRenderer
var _health_multiplier: float = 1.0

## placement_id -> current condition. Rebuilt fresh whenever a layout is applied
## — never stored on the ShipLayout resource itself, since that resource is
## shared (not duplicated) across every instance of the same enemy scene.
var _conditions: Dictionary = {}

## placement_id -> true. A module ends up here when it's still intact but has
## lost its connection back to the core (see _check_for_detachment) — distinct
## from its condition reaching zero, which means the module itself was destroyed
## outright. Either way counts as "gone" (see is_destroyed).
var _detached: Dictionary = {}

## placement_id -> true. A holed-out module regrowing stays here — and counts as
## destroyed for every gameplay purpose — for its whole climb back to full
## condition, not just while condition is at zero. Without this, is_destroyed
## would flip back to false (restoring fire/thrust) the instant condition ticked
## above zero, and a multi-hex hole's neighbors would all unlock on top of each
## other in the same frame instead of visibly sweeping outward.
var _regrowing: Dictionary = {}

## placement_id -> Array[CollisionPolygon2D], so a destroyed or detached
## module's hitbox can be removed from the ship's body along with its visual.
var _shapes_by_placement: Dictionary = {}
var _shapes: Array[CollisionPolygon2D] = []

var _time_since_last_damage: float = 0.0


func configure(ship: Ship, bank: HardpointBank, wreckage: WreckageSpawner) -> void:
	_ship = ship
	_bank = bank
	_wreckage = wreckage


## Full reset for a freshly applied layout: every module back to full condition,
## nothing destroyed/severed/regrowing, collision shapes respawned.
func rebuild(layout: ShipLayout, renderer: ShipLayoutRenderer, health_multiplier: float) -> void:
	_layout = layout
	_renderer = renderer
	_health_multiplier = health_multiplier

	_conditions.clear()
	_detached.clear()
	_regrowing.clear()
	for placement in layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type != null:
			_conditions[placement.placement_id] = module_type.health_contribution * health_multiplier

	for shape in _shapes:
		shape.queue_free()
	_shapes.clear()
	_shapes_by_placement.clear()
	for placement in layout.placements:
		_spawn_collision_shape_for(placement)


func get_condition(placement_id: String) -> float:
	return _conditions.get(placement_id, 0.0)


## True if the module is either destroyed outright (condition at zero), still
## intact but severed from the core's connectivity graph, or mid-regrowth — all
## three mean it no longer contributes to the ship.
func is_destroyed(placement_id: String) -> bool:
	if _detached.has(placement_id) or _regrowing.has(placement_id):
		return true
	return get_condition(placement_id) <= 0.0


## Restarts the repair delay. Called by the ship on every hit to its Health
## pool, including hits that never resolve to a specific module.
func note_damage_taken() -> void:
	_time_since_last_damage = 0.0


func process(delta: float) -> void:
	_time_since_last_damage += delta
	_regenerate_modules(delta)


func get_max_condition(placement_id: String) -> float:
	var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
	if placement == null:
		return 0.0
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	return module_type.health_contribution * _health_multiplier if module_type != null else 0.0


# --- Damage resolution -------------------------------------------------------

## Resolves a world-space impact point to the specific module occupying that hex
## cell (if any) and damages it, plus a splash fraction to its immediate
## neighbors. Destroying an engine this way costs the ship real thrust;
## destroying a weapon/missile hardpoint stops it firing — both react live, no
## rebuild needed.
func damage_at(amount: float, impact_point: Vector2) -> void:
	if _layout == null:
		return

	var hex_coord: Vector2i = _to_hex(_ship.to_local(impact_point))
	var placement: ModulePlacement = _layout.get_placement_at(hex_coord)
	if placement != null:
		_apply(placement, amount)

	for neighbor_coord in HexUtils.neighbors(hex_coord):
		var neighbor: ModulePlacement = _layout.get_placement_at(neighbor_coord)
		# The Core is exempt from splash: it ends the ship outright if lost, so
		# it shouldn't be catchable in crossfire aimed at whatever else happens
		# to be clustered around it — only a hit landing squarely on it counts.
		if neighbor != null and neighbor != placement and neighbor.placement_id != _layout.core_placement_id:
			_apply(neighbor, amount * splash_fraction)


## Fired by HardpointPhaseLance: unlike a normal hit (one hex + a splash
## fraction to its neighbors), a beam pierces straight through the hull, applying
## the full amount to every module hex it crosses from entry_point onward along
## aim_direction — including the Command Core, which splash damage deliberately
## never reaches. That's the point of this weapon: a well-aligned shot can punch
## through armor into whatever sits directly behind it.
func damage_beam(amount: float, entry_point: Vector2, aim_direction: Vector2, max_travel_distance: float) -> void:
	if _layout == null or aim_direction.length() < 0.001:
		return

	var origin: Vector2 = _ship.to_local(entry_point).rotated(-_renderer.rotation)
	var direction: Vector2 = aim_direction.rotated(-_ship.global_rotation - _renderer.rotation).normalized()

	# A zero cell_size would make the sampling loop below never advance.
	var step: float = _renderer.cell_size * 0.5
	if step <= 0.0:
		return

	var traveled: float = 0.0
	var already_hit: Dictionary = {}
	while traveled <= max_travel_distance:
		var hex_coord: Vector2i = HexUtils.pixel_to_axial(origin + direction * traveled, _renderer.cell_size)
		var placement: ModulePlacement = _layout.get_placement_at(hex_coord)
		if placement != null and not already_hit.has(placement.placement_id):
			already_hit[placement.placement_id] = true
			_apply(placement, amount)
		traveled += step


## Entry point for a hardpoint to damage its own mount (e.g. a Black Market
## Foundry weapon backfiring) — reuses the exact same pathway a normal hit uses,
## so a bad enough malfunction streak can genuinely sever the weapon's own module.
func damage_placement(placement_id: String, amount: float) -> void:
	var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
	if placement != null:
		_apply(placement, amount)


func _to_hex(ship_local_point: Vector2) -> Vector2i:
	return HexUtils.pixel_to_axial(ship_local_point.rotated(-_renderer.rotation), _renderer.cell_size)


func _apply(placement: ModulePlacement, amount: float) -> void:
	if is_destroyed(placement.placement_id):
		return
	var remaining: float = maxf(get_condition(placement.placement_id) - amount, 0.0)
	_conditions[placement.placement_id] = remaining
	if remaining <= 0.0:
		_on_module_destroyed(placement)


func _on_module_destroyed(placement: ModulePlacement) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	_renderer.set_module_destroyed(placement.placement_id)
	# A destroyed hex is a hole, not still-solid wreckage — without this, a
	# scorched module keeps blocking incoming shots aimed at whatever's behind
	# it (e.g. the connector further along a wing), which made severing a wing
	# much harder than intended.
	_free_collision_shapes_for(placement.placement_id)
	_bank.set_visual_visible(placement.placement_id, false)

	# Losing the Core ends the ship outright: without it there's no anchor left
	# to measure "still connected" against, so detachment checks would otherwise
	# go permanently inert and leftover modules would sit attached to a dead,
	# driverless hulk forever (see find_unreachable_from_core).
	if placement.placement_id == _layout.core_placement_id:
		hull_lost.emit()
		return

	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()

	_check_for_detachment()
	_check_all_modules_gone()


## The overall Health pool and per-module condition are deliberately separate,
## but splash damage lets modules collectively take more cumulative damage than
## Health ever registers, since a splash hit only affects modules. Without this,
## a ship can end up with every module destroyed/detached — visually a dead hulk
## — while Health still has some left and the ship keeps flying and fighting.
func _check_all_modules_gone() -> void:
	if _layout == null or _layout.placements.is_empty():
		return
	for placement in _layout.placements:
		if not is_destroyed(placement.placement_id):
			return
	hull_lost.emit()


## After any module is destroyed outright, some other still-intact modules may
## no longer have a path back to the core through adjacent modules — a wing
## losing the one piece connecting it to the hull, for example. Any such module
## is severed for good: it stops contributing and flies off as its own debris.
func _check_for_detachment() -> void:
	if _layout == null:
		return

	var gone: Dictionary = {}
	for placement in _layout.placements:
		if is_destroyed(placement.placement_id):
			gone[placement.placement_id] = true

	var newly_unreachable: Array[String] = _layout.find_unreachable_from_core(gone)
	if newly_unreachable.is_empty():
		return

	_wreckage.spawn_seam_sparks(newly_unreachable)
	for placement_id in newly_unreachable:
		_detach_module(_layout.get_placement_by_id(placement_id))


func _detach_module(placement: ModulePlacement) -> void:
	if placement == null or _detached.has(placement.placement_id):
		return
	_detached[placement.placement_id] = true

	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	# Re-summing every live module (rather than subtracting this one's share)
	# means it doesn't matter whether this module already lost its contribution
	# in _on_module_destroyed or is detaching while still intact.
	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()

	_renderer.set_module_detached(placement.placement_id)
	_free_collision_shapes_for(placement.placement_id)
	_bank.set_visual_visible(placement.placement_id, false)

	var max_condition: float = module_type.health_contribution * _health_multiplier
	var condition_fraction: float = (get_condition(placement.placement_id) / max_condition) if max_condition > 0.0 else 0.0
	_wreckage.spawn_severed_piece(placement, module_type, condition_fraction)


# --- Repair ------------------------------------------------------------------

## Regrows holed-out (destroyed but still attached) modules over time, one ring
## at a time outward from whatever's still healthy — a module can only *start*
## regrowing once it has a neighbor that isn't itself destroyed (or already
## mid-regrow), and it stays non-functional for its whole climb back to full
## condition, so a multi-hex hole visibly sweeps outward from the healthy edge
## inward rather than every hex in it popping back at once. Detached modules are
## excluded entirely — a piece that's already flown off has nothing to grow onto.
func _regenerate_modules(delta: float) -> void:
	if _layout == null or _time_since_last_damage < repair_delay:
		return

	for placement in _layout.placements:
		if _detached.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		if not _regrowing.has(placement.placement_id):
			if get_condition(placement.placement_id) > 0.0:
				continue # undamaged, or only combat-damaged rather than holed out
			if not _has_healthy_neighbor(placement):
				continue # nothing healthy adjacent yet to grow back from
			_regrowing[placement.placement_id] = true

		_advance_repair(placement, module_type, module_type.health_contribution * _health_multiplier, delta)


func _has_healthy_neighbor(placement: ModulePlacement) -> bool:
	for cell in _layout.get_occupied_cells(placement):
		for neighbor_coord in HexUtils.neighbors(cell):
			var neighbor: ModulePlacement = _layout.get_placement_at(neighbor_coord)
			if neighbor != null and not is_destroyed(neighbor.placement_id):
				return true
	return false


func _advance_repair(placement: ModulePlacement, module_type: ModuleType, max_condition: float, delta: float) -> void:
	var passive_cap: float = max_condition * passive_repair_cap_fraction
	var current_condition: float = get_condition(placement.placement_id)
	if current_condition >= passive_cap:
		return # capped: needs a paid repair (see repair_fully) to go further

	var new_condition: float = minf(current_condition + repair_rate * delta, passive_cap)
	_conditions[placement.placement_id] = new_condition
	hull_healed.emit(new_condition - current_condition)

	if new_condition >= passive_cap:
		_regrowing.erase(placement.placement_id)
		_on_module_repaired(placement, module_type)


## Paid station repair: tops every attached module back to full condition
## (bypassing passive_repair_cap_fraction). Detached (severed) modules are
## excluded — they're gone, not repairable in place. The caller heals the
## overall Health pool afterwards.
func repair_fully() -> void:
	if _layout == null:
		return

	for placement in _layout.placements:
		if _detached.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var max_condition: float = module_type.health_contribution * _health_multiplier
		if get_condition(placement.placement_id) >= max_condition:
			continue

		var was_regrowing: bool = _regrowing.has(placement.placement_id)
		_conditions[placement.placement_id] = max_condition
		if was_regrowing:
			_regrowing.erase(placement.placement_id)
			_on_module_repaired(placement, module_type)


## Reverses _on_module_destroyed's effects once a holed-out module finishes
## regrowing to its passive cap (or is topped off by a paid repair): restores its
## stat contribution, collision shape and normal hull appearance all at once
## (firing and thrust all gate on is_destroyed, which only reads false once this
## runs — see _regrowing).
func _on_module_repaired(placement: ModulePlacement, module_type: ModuleType) -> void:
	_renderer.set_module_repaired(placement.placement_id)
	_spawn_collision_shape_for(placement)
	_bank.set_visual_visible(placement.placement_id, true)

	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()


# --- Collision shapes --------------------------------------------------------
# Parented to the ship's CharacterBody2D itself, not to this node: the physics
# server only picks up shapes that are direct children of the body.

func _spawn_collision_shape_for(placement: ModulePlacement) -> void:
	var shapes_for_placement: Array = []
	for cell in _layout.get_occupied_cells(placement):
		var shape := CollisionPolygon2D.new()
		shape.polygon = HexUtils.hex_corners(Vector2.ZERO, _renderer.cell_size)
		shape.position = HexUtils.axial_to_pixel(cell, _renderer.cell_size).rotated(_renderer.rotation)
		_ship.add_child(shape)
		_shapes.append(shape)
		shapes_for_placement.append(shape)
	_shapes_by_placement[placement.placement_id] = shapes_for_placement


func _free_collision_shapes_for(placement_id: String) -> void:
	for shape in _shapes_by_placement.get(placement_id, []):
		_shapes.erase(shape)
		shape.queue_free()
	_shapes_by_placement.erase(placement_id)

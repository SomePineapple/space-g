class_name HardpointTractorBeam
extends Node2D

## Tractor beam hex module: always pulls the single nearest valid target
## (loose Salvage or a CapturedTechPart) within max_range and with a clear
## line of sight toward the ship, no player activation required — active
## whenever the module is mounted and intact. Only one target at a time by
## design (see the Phase 3.1 spec: "One active beam initially, more when
## upgraded") — a future upgrade could raise this to more simultaneous
## targets, but nothing here assumes exactly one beyond the single
## _active_target var and its one beam visual. The target leaving range,
## losing line of sight, or the ship running out of energy all end the pull
## safely; the beam visual only shows while a target is actually being pulled.
## Pulls all the way in to this hardpoint's own Muzzle and collects there
## (see _pull_target) — not to the ship's hull in general — so a beamed item
## is visibly drawn to the module doing the pulling, distinct from a loose
## item just drifting onto the hull (which instead has to reach the Command
## Core itself — see Salvage._is_near_core/Ship.get_core_global_position).

@export var max_range: float = 250.0
@export var pull_speed: float = 300.0
@export var beam_color: Color = Color(0.5, 0.8, 1.0, 0.8)
@export var beam_width: float = 4.0
@export var pulse_speed: float = 6.0
@export var pulse_strength: float = 0.4
## Outer glow line is this many times wider than the core, at reduced alpha
## — gives the beam a brighter, more "energetic" look than a single line.
@export var glow_width_multiplier: float = 3.0
@export var glow_alpha_multiplier: float = 0.35
@export var energy_cost_per_second: float = 5.0
## Pull speed for a CapturedTechPart — these have no rarity/pull_resistance
## concept like Salvage, so a single flat speed covers all of them.
@export var tech_part_pull_speed: float = 220.0
## How close a pulled CapturedTechPart needs to get to count as collected —
## it has no Area2D/collision of its own (unlike Salvage, which picks itself
## up via body_entered), so the beam has to do this check itself.
@export var tech_part_collect_radius: float = 20.0
## How close a pulled Salvage needs to get to the beam's own Muzzle to count
## as collected — items are drawn all the way in to the beam itself, not
## just to wherever the ship's hull happens to be (see _pull_target).
@export var salvage_collect_radius: float = 20.0

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## HardpointGun.source_placement_id.
var source_placement_id: String = ""

var _shooter: Ship
var _active_target: Node2D = null
var _time: float = 0.0

## Shared across every tractor beam hardpoint — a fresh CanvasItemMaterial per
## pickup used to force a new renderer material/pipeline setup on every single
## tractor grab, causing a real, reproducible hitch (see this module's prior
## always-on cockpit history). The blend mode is the only property set and
## never varies, so one cached instance is always correct to reuse.
static var _additive_material_cache: CanvasItemMaterial

@onready var _muzzle: Marker2D = $Muzzle
var _glow_line: Line2D
var _core_line: Line2D


func _ready() -> void:
	_glow_line = _create_beam_line(beam_width * glow_width_multiplier,
		Color(beam_color.r, beam_color.g, beam_color.b, beam_color.a * glow_alpha_multiplier))
	_core_line = _create_beam_line(beam_width, beam_color)
	_set_beam_visible(false)


func setup(shooter: Ship) -> void:
	_shooter = shooter


func _physics_process(delta: float) -> void:
	_time += delta

	if _shooter == null or (not source_placement_id.is_empty() and _shooter.is_module_destroyed(source_placement_id)):
		_release_target()
		return

	# is_instance_valid must run before _active_target is ever read/passed
	# again — a freed object stored in a typed variable throws as soon as
	# it's passed into another typed parameter, not just when its members
	# are accessed, so this check has to happen inline rather than inside a
	# helper that takes the target as an argument.
	if _active_target != null and not is_instance_valid(_active_target):
		_active_target = null

	if _active_target == null or not _in_range_and_sight(_active_target.global_position):
		_active_target = _find_nearest_valid_target()

	if _active_target == null:
		_set_beam_visible(false)
		return

	_pull_target(delta)


func _in_range_and_sight(target_position: Vector2) -> bool:
	if _muzzle.global_position.distance_to(target_position) > max_range:
		return false
	return _has_line_of_sight(target_position)


## Physics raycast from the muzzle to the candidate position — asteroids and
## ships are the only physics bodies that can occupy the gap (Salvage is an
## Area2D, CapturedTechPart has no collision at all), so any hit at all means
## something is in the way. The shooter's own body is excluded so the beam
## doesn't block on itself.
func _has_line_of_sight(target_position: Vector2) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_muzzle.global_position, target_position)
	query.exclude = [_shooter]
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()


## Closest valid target across both pullable groups, in range and with a
## clear line of sight — a target that's merely close but blocked or out of
## range is skipped rather than latched onto and immediately dropped.
func _find_nearest_valid_target() -> Node2D:
	var best: Node2D = null
	var best_distance: float = max_range

	for node in get_tree().get_nodes_in_group("salvage"):
		var candidate: Node2D = node
		var distance: float = _muzzle.global_position.distance_to(candidate.global_position)
		if distance <= best_distance and _has_line_of_sight(candidate.global_position):
			best = candidate
			best_distance = distance

	for node in get_tree().get_nodes_in_group("capturable_tech"):
		var candidate: Node2D = node
		var distance: float = _muzzle.global_position.distance_to(candidate.global_position)
		if distance <= best_distance and _has_line_of_sight(candidate.global_position):
			best = candidate
			best_distance = distance

	return best


## Pulls the active target all the way in to this hardpoint's own Muzzle —
## not just to wherever the ship's hull happens to be — and collects it once
## it actually arrives there. A collection failure (e.g. full cargo, see
## Salvage.collect_for) does not release the target: it stays held at the
## Muzzle and retries every frame until capacity frees up, out of range, or
## out of energy — same "hold and retry" shape as a real tractor beam.
func _pull_target(delta: float) -> void:
	if not _shooter.spend_energy(energy_cost_per_second * delta):
		# Out of energy just drops the target from the beam (same as being out
		# of range) rather than a hard block — the beam visibly cuts out.
		_release_target()
		return

	if _active_target is Salvage:
		var salvage: Salvage = _active_target
		# Heavier (rarer) salvage resists the beam and reels in slower, so it
		# physically feels heavier rather than just being worth more.
		salvage.pull_toward(_muzzle.global_position, pull_speed * salvage.pull_resistance, delta)
		if _muzzle.global_position.distance_to(salvage.global_position) <= salvage_collect_radius:
			if salvage.collect_for(_shooter):
				_active_target = null
				_set_beam_visible(false)
				return
	elif _active_target is CapturedTechPart:
		var part: CapturedTechPart = _active_target
		part.begin_reel_in()
		part.global_position = part.global_position.move_toward(_muzzle.global_position, tech_part_pull_speed * delta)
		if part.global_position.distance_to(_muzzle.global_position) <= tech_part_collect_radius:
			_shooter.capture_tech_part(part.module_type_id, part.manufacturer_id)
			part.collect()
			_active_target = null
			_set_beam_visible(false)
			return

	_update_beam_visual()


func _release_target() -> void:
	_active_target = null
	_set_beam_visible(false)


func _update_beam_visual() -> void:
	_set_beam_visible(true)
	var points: PackedVector2Array = [_muzzle.position, to_local(_active_target.global_position)]
	_glow_line.points = points
	_core_line.points = points

	var pulse: float = 1.0 - pulse_strength * (sin(_time * pulse_speed) * 0.5 + 0.5)
	_glow_line.modulate = Color(1.0, 1.0, 1.0, pulse)
	_core_line.modulate = Color(1.0, 1.0, 1.0, pulse)


func _set_beam_visible(should_be_visible: bool) -> void:
	_glow_line.visible = should_be_visible
	_core_line.visible = should_be_visible


func _create_beam_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.material = _additive_material()
	add_child(line)
	return line


func _additive_material() -> CanvasItemMaterial:
	if _additive_material_cache == null:
		_additive_material_cache = CanvasItemMaterial.new()
		_additive_material_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material_cache

class_name HardpointGrinder
extends Node2D

## Mining Grinder hex module: a short-range, contact-operation tool the
## player toggles on/off (see Ship.toggle_grinder, "G"), unlike the
## always-on Tractor Beam — grinding deals continuous damage, so it needs
## deliberate activation rather than running whenever mounted.
##
## While toggled on and a valid Asteroid sits within contact_range of the
## Muzzle (the front hex of this 2-cell module — see ModuleCatalog.
## GRINDER_HARDPOINT_TYPE_ID), it chips the asteroid's Health directly
## (Asteroid.take_damage, not take_damage_at — a held grind shouldn't also
## knock the target away every frame, unlike a one-off weapon hit) and, on a
## fixed interval, breaks off one physical ore fragment (a Salvage instance,
## same rarity odds as a normal kill-drop) at the contact point for the
## Tractor Beam or the ship's own hull to collect. Draws energy/sec from the
## shooter's pool the whole time it's actively touching a target, same
## "spend or stop" pattern as the Tractor Beam and Winch.

@export var contact_range: float = 55.0
@export var damage_per_second: float = 14.0
@export var energy_cost_per_second: float = 7.0
## How often (seconds) a held grind breaks off one collectible ore fragment.
@export var fragment_interval: float = 1.0
@export var salvage_scene: PackedScene = preload("res://scenes/world/salvage.tscn")
@export var beam_color: Color = Color(1.0, 0.65, 0.15, 0.85)
@export var beam_width: float = 3.0
@export var pulse_speed: float = 10.0
@export var pulse_strength: float = 0.5

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## every other hardpoint.
var source_placement_id: String = ""

var _shooter: Ship
var _active_target: Asteroid = null
var _fragment_timer: float = 0.0
var _time: float = 0.0

## Shared across every grinder hardpoint — see HardpointTractorBeam's
## identical cache for why a fresh CanvasItemMaterial per event is a real,
## reproducible hitch worth avoiding.
static var _additive_material_cache: CanvasItemMaterial

@onready var _muzzle: Marker2D = $Muzzle
var _beam_line: Line2D


func _ready() -> void:
	_beam_line = Line2D.new()
	_beam_line.width = beam_width
	_beam_line.default_color = beam_color
	_beam_line.material = _additive_material()
	add_child(_beam_line)
	_set_beam_visible(false)


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Front-cell reach, set once by Ship right after instancing (see
## HardpointGun.set_cell_size for the same idea applied to a weapon muzzle).
## The front hex's own centre sits ~0.87 cell-lengths out from this node's
## origin (the footprint's centroid); the extra distance reaches roughly to
## that hex's outer edge, where "contact" should actually start.
func set_cell_size(cell_size: float) -> void:
	_muzzle.position = Vector2(cell_size * 1.6, 0.0)


func _physics_process(delta: float) -> void:
	_time += delta

	if _shooter == null or (not source_placement_id.is_empty() and _shooter.is_module_destroyed(source_placement_id)):
		_stop_grinding()
		return

	if not _shooter.is_grinder_active():
		_stop_grinding()
		return

	# is_instance_valid must run before _active_target is read/passed again —
	# see HardpointTractorBeam._physics_process for why this has to happen
	# inline rather than inside a helper taking the target as an argument.
	if _active_target != null and not is_instance_valid(_active_target):
		_active_target = null

	if _active_target == null or not _in_contact_range(_active_target):
		_active_target = _find_nearest_asteroid_in_range()
		_fragment_timer = 0.0

	if _active_target == null:
		_stop_grinding()
		return

	if not _shooter.spend_energy(energy_cost_per_second * delta):
		_stop_grinding()
		return

	_grind(delta)


## Distance from the asteroid's own surface, not its center — a big asteroid
## should be reachable the moment its edge enters contact_range, not only
## once the ship is on top of its middle.
func _in_contact_range(asteroid: Asteroid) -> bool:
	var surface_distance: float = _muzzle.global_position.distance_to(asteroid.global_position) - asteroid.get_winch_radius()
	return surface_distance <= contact_range


func _find_nearest_asteroid_in_range() -> Asteroid:
	var best: Asteroid = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("asteroid"):
		var candidate: Asteroid = node
		if not _in_contact_range(candidate):
			continue
		var distance: float = _muzzle.global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _grind(delta: float) -> void:
	_active_target.take_damage(damage_per_second * delta)

	_fragment_timer += delta
	if _fragment_timer >= fragment_interval:
		_fragment_timer -= fragment_interval
		_spawn_fragment()

	_update_beam_visual()


## Breaks one ore fragment off the asteroid at the contact point — a real
## Salvage instance (same rarity odds Asteroid itself uses on a kill), not a
## direct cargo grant, so it has to be physically collected (Tractor Beam or
## drifting onto the hull) same as any other salvage. Guarded by
## is_instance_valid since the asteroid can be freed (health hit zero from
## this same grind tick) before this fires again next frame.
func _spawn_fragment() -> void:
	if not is_instance_valid(_active_target):
		return
	var fragment: Salvage = salvage_scene.instantiate()
	fragment.rarity = _active_target.roll_ore_rarity()
	get_tree().current_scene.add_child(fragment)
	fragment.global_position = _muzzle.global_position.move_toward(_active_target.global_position, contact_range * 0.5)


func _stop_grinding() -> void:
	_active_target = null
	_fragment_timer = 0.0
	_set_beam_visible(false)


func _update_beam_visual() -> void:
	_set_beam_visible(true)
	_beam_line.points = [_muzzle.position, to_local(_active_target.global_position)]
	var pulse: float = 1.0 - pulse_strength * (sin(_time * pulse_speed) * 0.5 + 0.5)
	_beam_line.modulate = Color(1.0, 1.0, 1.0, pulse)


func _set_beam_visible(should_be_visible: bool) -> void:
	_beam_line.visible = should_be_visible


func _additive_material() -> CanvasItemMaterial:
	if _additive_material_cache == null:
		_additive_material_cache = CanvasItemMaterial.new()
		_additive_material_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material_cache

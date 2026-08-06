class_name HardpointGrinder
extends Node2D

## Mining Grinder hex module: a short-range, contact-operation tool the
## player toggles on/off (the Grinder system's power switch, "G"), unlike the
## always-on Tractor Beam — grinding deals continuous damage, so it needs
## deliberate activation rather than running whenever mounted.
##
## While toggled on and a valid Asteroid sits within contact_range of the
## Muzzle (reaching out from this single-hex module's facing edge — see
## ModuleCatalog.GRINDER_HARDPOINT_TYPE_ID), it chips the asteroid's Health directly
## (Asteroid.take_damage, not take_damage_at — a held grind shouldn't also
## knock the target away every frame, unlike a one-off weapon hit) and, on a
## fixed interval, breaks off one small physical ore fragment (a Salvage
## instance, same material odds as a normal kill-drop but a smaller amount
## per fragment — see fragment_yield_multiplier below) at the contact point
## for the Tractor Beam or the ship's own hull to collect. Draws energy/sec
## from the shooter's pool the whole time it's actively touching a target,
## same "spend or stop" pattern as the Tractor Beam and Winch.

@export var contact_range: float = 55.0
@export var damage_per_second: float = 14.0
@export var energy_cost_per_second: float = 7.0
## How often (seconds) a held grind breaks off one collectible ore fragment.
@export var fragment_interval: float = 1.0
## Per-fragment yield (Salvage.amount_multiplier) relative to a plain weapon
## kill-drop's baseline amount. Deliberately well under 1.0 — a single chip
## should be much smaller than the chunk released when the whole rock finally
## breaks apart (still spawned separately by Asteroid._finish_destruction on
## death, at the full baseline amount, however the asteroid was killed).
## Mining still nets more material than a plain gun kill overall because the
## fragments accumulate throughout the grind on top of that same final
## kill-drop — the edge comes from the total across a full grind, not from
## any one fragment outsizing a kill-drop. Tuned down from an earlier 1.5
## (an individual fragment briefly outyielding a kill-drop) after live
## feedback that mining one Large asteroid filled cargo far too fast.
@export var fragment_yield_multiplier: float = 0.22
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

@onready var _muzzle: Marker2D = $Muzzle
## No glow layer, unlike the tractor beam's — a grinder is a hard cutting
## contact, not a soft field.
var _beam: BeamVisual


func _ready() -> void:
	_beam = BeamVisual.new()
	add_child(_beam)
	_beam.configure(beam_color, beam_width, pulse_speed, pulse_strength)


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Facing-vertex reach, set once by HardpointBank right after instancing (see
## HardpointGun.set_cell_size for the same idea applied to a weapon muzzle).
## This node's origin is the single occupied hex's own centre (see
## HardpointBank._hardpoint_center); this node's own rotation (set there too,
## `rotation_steps * PI/3 + _hull_renderer.rotation`) points at
## the hex's face — see docs/gotchas.md's "+90° fixed offset" entry — not at
## the direction the builder's placement-facing arrow shows for the same
## rotation_steps (hex_grid_control.gd's arrow is drawn without that
## hull-renderer offset, deliberately, for its own unrelated screen-up UX
## reason — see that file's comment). Converting the arrow's angle into this
## node's rotation convention lands it at grinder.rotation - 90°, exactly one
## hex vertex anticlockwise of the face grinder.rotation points at (cell_size
## from centre — see HexUtils.hex_corners) — that's the vertex used here so
## the beam visibly exits where the builder's arrow says "forward" is, per
## explicit request/live verification (a -90°/+30° mix-up here previously
## put the beam a full 120° off from the arrow).
func set_cell_size(cell_size: float) -> void:
	_muzzle.position = Vector2(cell_size * 1.15, 0.0).rotated(deg_to_rad(-90.0))


func _physics_process(delta: float) -> void:
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
## Salvage instance (same material odds Asteroid itself uses on a kill), not
## a direct cargo grant, so it has to be physically collected (Tractor Beam
## or drifting onto the hull) same as any other salvage. Guarded by
## is_instance_valid since the asteroid can be freed (health hit zero from
## this same grind tick) before this fires again next frame.
func _spawn_fragment() -> void:
	if not is_instance_valid(_active_target):
		return
	var fragment: Salvage = salvage_scene.instantiate()
	fragment.material_id = _active_target.roll_ore_material()
	fragment.amount_multiplier = fragment_yield_multiplier
	WorldSpawn.attach_at(fragment, _muzzle.global_position.move_toward(_active_target.global_position, contact_range * 0.5))


func _stop_grinding() -> void:
	_active_target = null
	_fragment_timer = 0.0
	_beam.hide_beam()


func _update_beam_visual() -> void:
	_beam.draw_beam(_muzzle.position, _active_target.global_position)

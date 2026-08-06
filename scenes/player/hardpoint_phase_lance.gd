class_name HardpointPhaseLance
extends HardpointGun

## Ancient Civilisation energy weapon: charges briefly, then instantly
## resolves a straight hitscan beam instead of a travelling projectile.
## Unlike a normal shot (one hex + a splash fraction to neighbors), the beam
## pierces the whole target and damages every module hex along its path in
## full (see Ship.take_beam_damage) — a well-aligned shot can punch through
## armor into whatever sits directly behind it. No barrel is drawn; the beam
## itself is the only visible weapon effect.

@export var charge_time: float = 0.7
@export var beam_max_range: float = 1200.0
@export var beam_scene: PackedScene = preload("res://scenes/world/phase_lance_beam.tscn")

var _charging: bool = false
var _charge_remaining: float = 0.0
var _pending_aim_direction: Vector2 = Vector2.RIGHT


## In _init() rather than _ready() so editor/scene overrides of these exports
## survive — see HardpointMissileLauncher._init().
func _init() -> void:
	fire_rate = 0.4
	recoil_force = 18.0
	projectile_color = Color(0.75, 0.55, 1.0, 1.0)
	projectile_damage = 24.0
	energy_cost = 45.0


func _ready() -> void:
	super._ready()
	_barrel.visible = false


func fire() -> Projectile:
	if _charging or _cooldown_remaining > 0.0 or _shooter == null:
		return null
	if not _shooter.has_energy(energy_cost):
		return null
	_cooldown_remaining = 1.0 / fire_rate
	_charging = true
	_charge_remaining = charge_time
	_pending_aim_direction = Vector2.RIGHT.rotated(global_rotation)
	return null


func _process(delta: float) -> void:
	super._process(delta)
	if not _charging:
		return
	_charge_remaining -= delta
	if _charge_remaining <= 0.0:
		_charging = false
		_resolve_beam()


func _resolve_beam() -> void:
	if _shooter == null or not _shooter.spend_energy(energy_cost):
		return

	var from_point: Vector2 = _muzzle.global_position
	var to_point: Vector2 = from_point + _pending_aim_direction * beam_max_range

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from_point, to_point)
	query.exclude = [_shooter.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)

	if not result.is_empty():
		to_point = result.position

	_spawn_beam_visual(from_point, to_point)

	if fire_sound != null:
		_fire_sound_player.stream = fire_sound
		_fire_sound_player.play()

	_apply_recoil()

	if result.is_empty():
		return
	var target: Object = result.collider
	if target == _shooter or not target.has_method("take_beam_damage"):
		return

	var travel_distance: float = beam_max_range
	if target.has_method("get_layout_extent"):
		travel_distance = target.get_layout_extent() * 2.5

	target.take_beam_damage(projectile_damage, result.position, _pending_aim_direction, travel_distance)


func _spawn_beam_visual(from_point: Vector2, to_point: Vector2) -> void:
	var beam: PhaseLanceBeam = beam_scene.instantiate()
	get_tree().current_scene.add_child(beam)
	beam.setup(from_point, to_point)

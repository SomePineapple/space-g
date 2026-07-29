class_name HardpointGun
extends Node2D

@export var projectile_scene: PackedScene = preload("res://scenes/world/projectile.tscn")
@export var fire_rate: float = 4.0
@export var projectile_speed: float = 700.0
@export var recoil_force: float = 20.0
@export var projectile_color: Color = Color(0.4, 0.9, 1.0, 1.0)
@export var projectile_damage: float = 8.0
@export var barrel_color: Color = Color(0.5, 0.85, 1.0, 1.0)
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and firing will play it automatically.
@export var fire_sound: AudioStream = null

## Tier scaling for bigger (multi-hex) hardpoints: bigger guns hit harder
## and kick more but cycle slower. Tier 1 (index 0) is a 1.0 no-op so
## existing single-hex hardpoints are unaffected.
const TIER_DAMAGE_MULTIPLIER: Array[float] = [1.0, 1.0, 1.8, 2.8]
const TIER_FIRE_RATE_MULTIPLIER: Array[float] = [1.0, 1.0, 0.8, 0.6]
const TIER_RECOIL_MULTIPLIER: Array[float] = [1.0, 1.0, 1.5, 2.2]
const TIER_VISUAL_SCALE: Array[float] = [1.0, 1.0, 1.4, 1.8]
const TIER_PROJECTILE_SCALE_MULTIPLIER: Array[float] = [1.0, 1.0, 1.4, 2.0]

## Scales the spawned projectile's whole node (visual and collision shape
## alike, since both are sized relative to this transform), so bigger-tier
## weapons visibly fire bigger shots.
@export var projectile_scale: float = 1.0

var _cooldown_remaining: float = 0.0
var _shooter: Ship

@onready var _barrel: Polygon2D = $Barrel
@onready var _muzzle: Marker2D = $Muzzle
@onready var _fire_sound_player: AudioStreamPlayer2D = $FireSound


func _ready() -> void:
	_barrel.color = barrel_color


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Scales this hardpoint's already-set base stats for its module tier (1-3).
## Called once, right after _ready(), before upgrade modifiers are applied.
func apply_tier(tier: int) -> void:
	projectile_damage *= TIER_DAMAGE_MULTIPLIER[tier]
	fire_rate *= TIER_FIRE_RATE_MULTIPLIER[tier]
	recoil_force *= TIER_RECOIL_MULTIPLIER[tier]
	projectile_scale *= TIER_PROJECTILE_SCALE_MULTIPLIER[tier]


static func tier_visual_scale(tier: int) -> float:
	return TIER_VISUAL_SCALE[tier]


## Sizes the barrel to two hex-lengths, pivoting at this node's own
## origin (the hardpoint's hex center) rather than the barrel's midpoint.
## tier_scale grows the barrel for bigger-tier hardpoints (see Ship's
## _spawn_hardpoint_guns()), which also occupy more hex cells.
func set_cell_size(cell_size: float, tier_scale: float = 1.0) -> void:
	var length: float = cell_size * 2.0 * tier_scale
	var half_width: float = cell_size * 0.18 * tier_scale
	_barrel.polygon = PackedVector2Array([
		Vector2(0, -half_width),
		Vector2(length, -half_width),
		Vector2(length, half_width),
		Vector2(0, half_width),
	])
	_muzzle.position = Vector2(length, 0)


func aim_at(global_target: Vector2) -> void:
	global_rotation = (global_target - global_position).angle()


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta


func fire() -> Projectile:
	if _cooldown_remaining > 0.0 or _shooter == null:
		return null
	_cooldown_remaining = 1.0 / fire_rate

	var projectile: Projectile = projectile_scene.instantiate()
	projectile.color = projectile_color
	projectile.damage = projectile_damage
	projectile.scale = Vector2.ONE * projectile_scale
	# Bigger-tier projectiles should leave a bigger impact burst, not just a
	# bigger travelling shot.
	projectile.explosion_scale *= projectile_scale
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = _muzzle.global_position
	projectile.global_rotation = _muzzle.global_rotation
	projectile.launch(projectile_speed, _shooter)

	if fire_sound != null:
		_fire_sound_player.stream = fire_sound
		_fire_sound_player.play()

	_shooter.apply_impulse(-_muzzle.global_transform.x * recoil_force)
	return projectile

class_name HardpointGun
extends Node2D

@export var projectile_scene: PackedScene = preload("res://scenes/world/projectile.tscn")
@export var fire_rate: float = 4.0
@export var projectile_speed: float = 700.0
@export var recoil_force: float = 20.0
@export var projectile_color: Color = Color(0.4, 0.9, 1.0, 1.0)
@export var projectile_damage: float = 8.0
@export var barrel_color: Color = Color(0.5, 0.85, 1.0, 1.0)

var _cooldown_remaining: float = 0.0
var _shooter: Ship

@onready var _barrel: Polygon2D = $Barrel
@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	_barrel.color = barrel_color


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Sizes the barrel to two hex-lengths, pivoting at this node's own
## origin (the hardpoint's hex center) rather than the barrel's midpoint.
func set_cell_size(cell_size: float) -> void:
	var length: float = cell_size * 2.0
	var half_width: float = cell_size * 0.18
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
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = _muzzle.global_position
	projectile.global_rotation = _muzzle.global_rotation
	projectile.launch(projectile_speed, _shooter)

	_shooter.apply_impulse(-_muzzle.global_transform.x * recoil_force)
	return projectile

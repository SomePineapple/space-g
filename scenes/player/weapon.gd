class_name Weapon
extends Node2D

@export var projectile_scene: PackedScene
@export var fire_rate: float = 4.0
@export var projectile_speed: float = 700.0
@export var recoil_force: float = 50.0
@export var projectile_color: Color = Color(1, 0.3, 0.3, 1)
@export var projectile_damage: float = 10.0

@onready var _muzzle: Marker2D = $Muzzle
@onready var _shooter: Ship = get_owner()

var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta


func fire() -> Projectile:
	if _cooldown_remaining > 0.0:
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

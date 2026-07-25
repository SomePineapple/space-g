class_name HardpointMissileLauncher
extends HardpointGun

@export var missile_scene: PackedScene = preload("res://scenes/world/missile.tscn")


func _ready() -> void:
	projectile_scene = missile_scene
	fire_rate = 1.0
	projectile_speed = 450.0
	recoil_force = 150.0
	projectile_color = Color(1, 0.6, 0.15, 1)
	projectile_damage = 40.0
	barrel_color = Color(0.35, 0.35, 0.4, 1)
	super._ready()


## Missile silos don't track the mouse like the laser gun — they stay
## rigidly fixed to the hull as a short tube (inherited "_barrel" node,
## reused here as the silo) and fire straight up; the missile itself
## arcs over to the target instead.
func set_cell_size(cell_size: float) -> void:
	var silo_width: float = cell_size * 0.55
	var silo_height: float = cell_size * 0.6
	_barrel.polygon = PackedVector2Array([
		Vector2(-silo_width * 0.5, 0),
		Vector2(silo_width * 0.5, 0),
		Vector2(silo_width * 0.5, -silo_height),
		Vector2(-silo_width * 0.5, -silo_height),
	])
	_muzzle.position = Vector2(0, -silo_height)


func aim_at(_global_target: Vector2) -> void:
	pass


func fire() -> Projectile:
	var projectile: Projectile = super.fire()
	if projectile is Missile and _shooter != null:
		projectile.set_target(_shooter.get_aim_target())
	return projectile

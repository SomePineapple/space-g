class_name MissileLauncher
extends Weapon


func fire() -> Projectile:
	var projectile: Projectile = super.fire()
	if projectile is Missile:
		projectile.set_target(get_global_mouse_position())
	return projectile

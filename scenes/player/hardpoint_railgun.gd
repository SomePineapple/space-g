class_name HardpointRailgun
extends ChargedHardpoint

## Corporate Alliance kinetic weapon: a brief charge-up before firing a very
## fast, high-damage slug. Recoil is stronger than a laser's but still just a
## tiny straight-back push (see HardpointGun._apply_recoil) — standardised,
## industrial and precise rather than a laser's instant-response spray.
##
## The charge state machine itself lives in ChargedHardpoint; this weapon adds
## nothing to it beyond its stats, since a completed charge just fires an
## ordinary projectile.


## In _init() rather than _ready() so editor/scene overrides of these exports
## survive — see HardpointMissileLauncher._init().
func _init() -> void:
	projectile_scene = preload("res://scenes/world/railgun_slug.tscn")
	charge_time = 0.5
	fire_rate = 0.5
	projectile_speed = 1400.0
	recoil_force = 48.0
	projectile_color = Color(0.85, 0.9, 1.0, 1.0)
	barrel_color = Color(0.78, 0.82, 0.9, 1.0)
	projectile_damage = 35.0
	energy_cost = 28.0

class_name HardpointRailgun
extends HardpointGun

## Corporate Alliance kinetic weapon: a brief charge-up before firing a very
## fast, high-damage slug. Recoil is stronger than a laser's but still just a
## tiny straight-back push (see HardpointGun._apply_recoil) — standardised,
## industrial and precise rather than a laser's instant-response spray.

@export var charge_time: float = 0.5

var _charging: bool = false
var _charge_remaining: float = 0.0


## In _init() rather than _ready() so editor/scene overrides of these exports
## survive — see HardpointMissileLauncher._init().
func _init() -> void:
	projectile_scene = preload("res://scenes/world/railgun_slug.tscn")
	fire_rate = 0.5
	projectile_speed = 1400.0
	recoil_force = 48.0
	projectile_color = Color(0.85, 0.9, 1.0, 1.0)
	barrel_color = Color(0.78, 0.82, 0.9, 1.0)
	projectile_damage = 35.0
	energy_cost = 28.0


## Reserves the cooldown slot and gates re-triggering for the whole
## charge+cycle up front, but doesn't spend energy until the slug actually
## fires (see _process) — so a charge that gets interrupted by running out
## of energy mid-charge simply fizzles rather than refunding a partial cost.
func fire() -> Projectile:
	if _charging or _cooldown_remaining > 0.0 or _shooter == null:
		return null
	if not _shooter.has_energy(energy_cost):
		return null
	_cooldown_remaining = 1.0 / fire_rate
	_charging = true
	_charge_remaining = charge_time
	return null


func _process(delta: float) -> void:
	super._process(delta)
	if not _charging:
		return
	_charge_remaining -= delta
	if _charge_remaining <= 0.0:
		_charging = false
		if _shooter != null and _shooter.spend_energy(energy_cost):
			_execute_fire()

class_name HardpointMissileLauncher
extends HardpointGun

@export var missile_scene: PackedScene = preload("res://scenes/world/missile.tscn")

## Passed onto each spawned Missile. Upgradeable through the "MissileLauncher"
## upgrade tree via Ship.apply_missile_modifier(), same as projectile_speed.
@export var missile_acceleration: float = 900.0
@export var ignition_delay: float = 1.2
@export var turn_rate_min: float = 0.35
@export var turn_rate_max: float = 1.5
@export var turn_rate_ramp_time: float = 0.6
@export var max_miss_offset_ratio: float = 0.2
@export var miss_chance: float = 0.3
## Each missile's actual lifetime is randomised within lifetime_variance below
## this max, so a salvo fired together doesn't all self-destruct in lockstep.
@export var missile_lifetime: float = 8.0
@export var lifetime_variance: float = 2.0

## Very low initial acceleration for the "spew out" creep before the missile
## commits to full power and starts homing.
@export var creep_acceleration: float = 69.0

func _ready() -> void:
	projectile_scene = missile_scene
	fire_rate = 1.0
	# Lowered by a third from the original 450 so missiles are dodgeable
	# rather than essentially guaranteed hits.
	projectile_speed = 300.0
	# Missiles spew straight up out of a fixed tube rather than being fired
	# like a gun, so there's no reaction kick into the ship.
	recoil_force = 0.0
	projectile_color = Color(1, 0.6, 0.15, 1)
	projectile_damage = 40.0
	energy_cost = 15.0
	super._ready()
	# The missile-silo hex art already shows the tube; the inherited barrel
	# shape would just draw a redundant grey rectangle on top of it.
	_barrel.visible = false


## Missiles now spawn from the hex's centre (matching the silo hole in the
## hex art) rather than a raised barrel tip. tier_scale is accepted for a
## consistent signature with HardpointGun, but the silo has no directional
## barrel to resize.
func set_cell_size(_unused_cell_size: float, _unused_tier_scale: float = 1.0) -> void:
	_muzzle.position = Vector2.ZERO


func aim_at(_global_target: Vector2) -> void:
	pass


func fire() -> Projectile:
	var projectile: Projectile = super.fire()
	if projectile is Missile and _shooter != null:
		var missile: Missile = projectile
		missile.acceleration = missile_acceleration
		missile.ignition_delay = ignition_delay
		missile.turn_rate_min = turn_rate_min
		missile.turn_rate_max = turn_rate_max
		missile.turn_rate_ramp_time = turn_rate_ramp_time
		missile.max_miss_offset_ratio = max_miss_offset_ratio
		missile.miss_chance = miss_chance
		missile.lifetime = randf_range(missile_lifetime - lifetime_variance, missile_lifetime)
		missile.creep_acceleration = creep_acceleration

		var locked_target: Node2D = _shooter.get_locked_target()
		if locked_target != null:
			missile.launch_toward(locked_target)
		else:
			missile.launch_outward()
	return projectile

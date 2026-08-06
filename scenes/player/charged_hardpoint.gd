class_name ChargedHardpoint
extends HardpointGun

## A weapon that spins up for charge_time before it actually shoots, instead
## of firing the instant the trigger is pulled. Shared by HardpointRailgun
## (which then fires an ordinary, very fast slug) and HardpointPhaseLance
## (which resolves a hitscan beam) — both previously carried an identical
## private copy of the charge state machine below.
##
## Deliberately reserves the cooldown slot up front but does NOT spend energy
## until the charge completes: a charge interrupted by the reserve running dry
## mid-spin fizzles rather than refunding a partial cost.

@export var charge_time: float = 0.5

var _charging: bool = false
var _charge_remaining: float = 0.0


func fire() -> Projectile:
	if _charging or _cooldown_remaining > 0.0 or _shooter == null:
		return null
	if not _shooter.has_energy(energy_cost):
		return null

	_cooldown_remaining = 1.0 / fire_rate
	_charging = true
	_charge_remaining = charge_time
	_on_charge_started()
	return null


## Hook for a subclass that has to latch something at trigger-pull time rather
## than at release — HardpointPhaseLance freezes its aim direction here, so a
## charged shot goes where the barrel was pointing when the player committed
## to it.
func _on_charge_started() -> void:
	pass


func _process(delta: float) -> void:
	super._process(delta)
	if not _charging:
		return

	_charge_remaining -= delta
	if _charge_remaining <= 0.0:
		_charging = false
		_release_charge()


## What the completed charge actually does. The default spends the energy and
## fires a normal projectile through HardpointGun's shared spawn/recoil path;
## HardpointPhaseLance overrides this to resolve a beam instead.
func _release_charge() -> void:
	if _shooter != null and _shooter.spend_energy(energy_cost):
		_execute_fire()


func is_charging() -> bool:
	return _charging

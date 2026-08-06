class_name ShipEnergy
extends Node

## The ship's energy pool: the capacity/regeneration derived from installed
## Reactor and Battery modules on top of a baseline, and the spend-or-refuse
## decision every consumer (thrust, weapons, tractor beam, grinder, winch)
## routes through.
##
## Split out of ship.gd, which owned the pool, its regeneration, its signal and
## the layout-derived totals inline. Ship keeps the public
## spend_energy()/has_energy() API and relays energy_changed, so nothing
## outside the ship reaches in here.

signal energy_changed(current: float, maximum: float)

## Available even with no Reactor/Battery modules installed, so existing ship
## layouts (pirates, the starter ship) keep working now that weapons/thrusters/
## tractor beam actually spend energy — reactor and battery modules add on top
## of these baselines.
@export var base_generation: float = 10.0
@export var base_capacity: float = 50.0

var current: float = 0.0
var maximum: float = 0.0
var generation_rate: float = 0.0


## A new maximum keeps the same fraction full rather than resetting to full or
## to the old absolute amount, so refitting a ship (builder, upgrades) doesn't
## grant or destroy energy out of nowhere.
func configure(layout_capacity: float, layout_generation: float) -> void:
	var previous_fraction: float = (current / maximum) if maximum > 0.0 else 1.0
	maximum = base_capacity + layout_capacity
	generation_rate = base_generation + layout_generation
	current = maximum * previous_fraction
	energy_changed.emit(current, maximum)


func has(amount: float) -> bool:
	return current >= amount


func spend(amount: float) -> bool:
	if current < amount:
		return false
	current -= amount
	energy_changed.emit(current, maximum)
	return true


## Regen used to emit every single physics frame while the pool was below full,
## which meant the HUD reformatted and rewrote its energy Label ~60 times a
## second for a readout that only displays whole numbers. Only emitting once the
## displayed value can actually have changed (or the pool tops out) keeps the
## readout identical while cutting the signal traffic.
func regenerate(delta: float) -> void:
	if current >= maximum:
		return
	var previous: float = current
	current = minf(current + generation_rate * delta, maximum)
	if current >= maximum or floorf(current) > floorf(previous):
		energy_changed.emit(current, maximum)

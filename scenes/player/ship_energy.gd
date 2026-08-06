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
## Smoothed energy/second currently being drawn, alongside the rate the ship
## regenerates at — the HUD's load bar reads "usage against what the reactor
## can sustain", so both halves travel together.
signal usage_changed(usage_per_second: float, generation_per_second: float)

## Available even with no Reactor/Battery modules installed, so existing ship
## layouts (pirates, the starter ship) keep working now that weapons/thrusters/
## tractor beam actually spend energy — reactor and battery modules add on top
## of these baselines.
@export var base_generation: float = 10.0
@export var base_capacity: float = 50.0
## How fast the displayed usage rate chases the instantaneous one. A raw
## per-frame rate is unreadable — a gun firing on one frame in twenty reads as
## a huge spike — so the HUD sees an exponentially smoothed value instead.
@export var usage_smoothing: float = 6.0

var current: float = 0.0
var maximum: float = 0.0
var generation_rate: float = 0.0
## Smoothed energy/second being drawn (see usage_changed).
var usage_rate: float = 0.0

## Energy spent since the last tick(), converted into usage_rate there.
var _spent_since_tick: float = 0.0
## Last usage_rate actually emitted, so the signal only fires on a change the
## HUD could draw differently.
var _emitted_usage: float = -1.0


## A new maximum keeps the same fraction full rather than resetting to full or
## to the old absolute amount, so refitting a ship (builder, upgrades) doesn't
## grant or destroy energy out of nowhere.
func configure(layout_capacity: float, layout_generation: float) -> void:
	var previous_fraction: float = (current / maximum) if maximum > 0.0 else 1.0
	maximum = base_capacity + layout_capacity
	generation_rate = base_generation + layout_generation
	current = maximum * previous_fraction
	energy_changed.emit(current, maximum)
	# A refit changes the sustainable limit the load bar is measured against,
	# so the HUD needs the new generation rate even if usage hasn't moved.
	_emitted_usage = usage_rate
	usage_changed.emit(usage_rate, generation_rate)


func has(amount: float) -> bool:
	return current >= amount


func spend(amount: float) -> bool:
	if current < amount:
		return false
	current -= amount
	_spent_since_tick += amount
	energy_changed.emit(current, maximum)
	return true


## Continuous background load (see ShipSystems): unlike spend(), this pays as
## much as the pool can afford instead of refusing outright, and returns the
## shortfall. A ship that can't cover its own idle draw browns out — the caller
## turns something off — rather than silently running its systems for free.
func drain(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var paid: float = minf(amount, current)
	if paid <= 0.0:
		return amount
	var previous: float = current
	current -= paid
	_spent_since_tick += paid
	# Same "only when the displayed whole number could have changed" guard as
	# regenerate() — this runs every physics frame.
	if current <= 0.0 or floorf(current) < floorf(previous):
		energy_changed.emit(current, maximum)
	return amount - paid


## Regen used to emit every single physics frame while the pool was below full,
## which meant the HUD reformatted and rewrote its energy Label ~60 times a
## second for a readout that only displays whole numbers. Only emitting once the
## displayed value can actually have changed (or the pool tops out) keeps the
## readout identical while cutting the signal traffic.
func tick(delta: float) -> void:
	_update_usage_rate(delta)

	if current >= maximum:
		return
	var previous: float = current
	current = minf(current + generation_rate * delta, maximum)
	if current >= maximum or floorf(current) > floorf(previous):
		energy_changed.emit(current, maximum)


## Turns everything spent since the previous tick into a smoothed per-second
## rate for the HUD's load bar. Spends made by the ship's children (hardpoints
## process after their parent) land in the following frame's window, which is
## invisible at these smoothing rates.
func _update_usage_rate(delta: float) -> void:
	if delta <= 0.0:
		return
	var instantaneous: float = _spent_since_tick / delta
	_spent_since_tick = 0.0
	usage_rate = lerpf(usage_rate, instantaneous, clampf(usage_smoothing * delta, 0.0, 1.0))
	if absf(usage_rate - _emitted_usage) < 0.05:
		return
	_emitted_usage = usage_rate
	usage_changed.emit(usage_rate, generation_rate)

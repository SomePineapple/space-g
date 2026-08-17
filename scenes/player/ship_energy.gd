class_name ShipEnergy
extends Node

## The ship's energy, held as one pool per circuit rather than one pool per ship.
##
## Every generating module (a reactor, or the Command Core) owns a circuit; every
## module that draws power belongs to exactly one, chosen by the player in the
## builder (see ShipLayout's circuit functions). A consumer spends against *its
## own* circuit and can only be refused by that circuit, which is the whole
## mechanic: run your guns dry and your engines still push.
##
## Circuits are keyed by their source's `placement_id`, so a reactor being shot
## off the hull removes exactly one pool and leaves the rest untouched.
##
## Ship keeps the public spend_energy()/has_energy() API and relays
## energy_changed, so nothing outside the ship reaches in here.

## Ship-wide totals, for readouts that want one number (the HUD's vitals bar).
## The per-circuit HUD is Phase 2; until then these keep the existing readout
## honest by summing what the circuits actually hold.
signal energy_changed(current: float, maximum: float)
## Smoothed energy/second currently being drawn, alongside the rate the ship
## regenerates at — the HUD's load bar reads "usage against what the reactor
## can sustain", so both halves travel together.
signal usage_changed(usage_per_second: float, generation_per_second: float)
## A circuit just hit empty. Carries the circuit's own id, not its position:
## positions shift when a reactor dies, and a readout that renumbers the surviving
## circuits mid-fight is worse than no readout. Callers resolve a name through
## ShipLayout.circuit_display_name, which is the only place circuits are named.
##
## Said out loud because everything on a dry circuit stops working, and hardware
## going quiet with no explanation is the exact confusion power management exists
## to avoid. Edge-triggered and rate-limited (see DEPLETION_NOTICE_INTERVAL) —
## a circuit sitting at zero under continuous load would otherwise re-announce
## itself every frame.
signal circuit_depleted(circuit_id: String)

## Minimum gap between one circuit's depletion notices, so a circuit held at
## empty says so once and then leaves the player alone to deal with it.
const DEPLETION_NOTICE_INTERVAL: float = 4.0
## How empty a circuit has to be before a refused spend counts as "this circuit
## is dry" rather than "that was too big a burst for the reserve you had". A full
## circuit refusing one railgun shot is the player overreaching; a near-empty one
## refusing everything is the thing they need told about.
const DEPLETION_NOTICE_FRACTION: float = 0.2

## How fast the displayed usage rate chases the instantaneous one. A raw
## per-frame rate is unreadable — a gun firing on one frame in twenty reads as
## a huge spike — so the HUD sees an exponentially smoothed value instead.
@export var usage_smoothing: float = 6.0

## A circuit with no battery on it still has to be able to spend what it makes,
## or a reactor with nothing attached would be worth nothing at all. Its working
## buffer is therefore at least this many seconds of its own generation: a
## continuous draw inside its rate is sustainable indefinitely, and a burst above
## it simply is not affordable. Adding a battery is what buys the burst.
const MINIMUM_BUFFER_SECONDS: float = 1.0


## One circuit's live state. Plain data on purpose — there is one of these per
## reactor and they are rebuilt on every refit, so they are not nodes.
class Circuit extends RefCounted:
	var id: String = ""
	var charge: float = 0.0
	var capacity: float = 0.0
	var generation: float = 0.0
	## Seconds until this circuit may announce being empty again.
	var notice_cooldown: float = 0.0

	## What this circuit can actually hold (see MINIMUM_BUFFER_SECONDS).
	func buffer() -> float:
		return maxf(capacity, generation * MINIMUM_BUFFER_SECONDS)

	func fill_fraction() -> float:
		var limit: float = buffer()
		return (charge / limit) if limit > 0.0 else 0.0


var _circuits: Dictionary = {}   # String (circuit_id) -> Circuit
var _order: Array[String] = []

## Energy spent since the last tick(), converted into usage_rate there.
var _spent_since_tick: float = 0.0
## Last values actually emitted, so the signals only fire on a change the HUD
## could draw differently.
var _emitted_usage: float = -1.0
var _emitted_charge: float = -1.0
var _usage_rate: float = 0.0


## Rebuilds the circuits from a layout. A circuit that survives the refit keeps
## the same *fraction* of its buffer rather than the same absolute charge or a
## free top-up, so changing a ship at the workbench neither grants nor destroys
## energy. A circuit that is new to this layout starts full — a reactor you just
## bolted on has been running.
func configure(layout: ShipLayout) -> void:
	var previous: Dictionary = _circuits
	_circuits = {}
	_order.clear()

	if layout != null:
		for circuit_id in layout.get_circuit_ids():
			var circuit := Circuit.new()
			circuit.id = circuit_id
			circuit.capacity = layout.circuit_capacity(circuit_id)
			circuit.generation = layout.circuit_generation(circuit_id)
			var carried: Circuit = previous.get(circuit_id)
			circuit.charge = circuit.buffer() * (carried.fill_fraction() if carried != null else 1.0)
			_circuits[circuit_id] = circuit
			_order.append(circuit_id)

	_emit_energy(true)
	# A refit changes the sustainable limit the load bar is measured against, so
	# the HUD needs the new generation rate even if usage hasn't moved.
	_emitted_usage = _usage_rate
	usage_changed.emit(_usage_rate, total_generation())


func get_circuit_ids() -> Array[String]:
	return _order.duplicate()


func get_circuit(circuit_id: String) -> Circuit:
	return _circuits.get(circuit_id)


func has(amount: float, circuit_id: String) -> bool:
	var circuit: Circuit = _circuits.get(circuit_id)
	return circuit != null and circuit.charge >= amount


## All of it or none of it. A weapon must never half-fire and a circuit must
## never go negative, so affordability is settled before anything is committed.
func spend(amount: float, circuit_id: String) -> bool:
	var circuit: Circuit = _circuits.get(circuit_id)
	if circuit == null:
		return false
	if circuit.charge < amount:
		_announce_depleted(circuit)
		return false
	circuit.charge -= amount
	_spent_since_tick += amount
	_emit_energy(true)
	return true


## Continuous load: unlike spend(), this pays as much as the circuit can afford
## instead of refusing outright, and returns the shortfall. Used by anything
## whose draw is a rate rather than an event, where partial delivery is
## meaningful — a thruster that can only be half fed pushes half as hard.
func drain(amount: float, circuit_id: String) -> float:
	if amount <= 0.0:
		return 0.0
	var circuit: Circuit = _circuits.get(circuit_id)
	if circuit == null:
		return amount
	var paid: float = minf(amount, circuit.charge)
	if paid <= 0.0:
		_announce_depleted(circuit)
		return amount
	circuit.charge -= paid
	_spent_since_tick += paid
	if paid < amount:
		_announce_depleted(circuit)
	_emit_energy(false)
	return amount - paid


func tick(delta: float) -> void:
	_update_usage_rate(delta)

	for circuit_id in _order:
		var circuit: Circuit = _circuits[circuit_id]
		circuit.notice_cooldown = maxf(circuit.notice_cooldown - delta, 0.0)
		var limit: float = circuit.buffer()
		if circuit.charge < limit:
			circuit.charge = minf(circuit.charge + circuit.generation * delta, limit)
	_emit_energy(false)


func _announce_depleted(circuit: Circuit) -> void:
	if circuit.notice_cooldown > 0.0:
		return
	var limit: float = circuit.buffer()
	if limit > 0.0 and circuit.charge > limit * DEPLETION_NOTICE_FRACTION:
		return
	circuit.notice_cooldown = DEPLETION_NOTICE_INTERVAL
	circuit_depleted.emit(circuit.id)


func total_charge() -> float:
	var total: float = 0.0
	for circuit_id in _order:
		total += _circuits[circuit_id].charge
	return total


func total_buffer() -> float:
	var total: float = 0.0
	for circuit_id in _order:
		total += _circuits[circuit_id].buffer()
	return total


func total_generation() -> float:
	var total: float = 0.0
	for circuit_id in _order:
		total += _circuits[circuit_id].generation
	return total


## `force` is for discrete spends, which the player caused and should see land.
## Everything continuous (regen, idle drain) goes through the whole-number guard:
## these run every physics frame for every circuit, and the readout only displays
## whole numbers, so emitting per frame would have the HUD reformat its label
## sixty times a second to draw the same characters.
func _emit_energy(force: bool) -> void:
	var current: float = total_charge()
	if not force and floorf(current) == floorf(_emitted_charge):
		return
	_emitted_charge = current
	energy_changed.emit(current, total_buffer())


## Turns everything spent since the previous tick into a smoothed per-second
## rate for the HUD's load bar. Spends made by the ship's children (hardpoints
## process after their parent) land in the following frame's window, which is
## invisible at these smoothing rates.
func _update_usage_rate(delta: float) -> void:
	if delta <= 0.0:
		return
	var instantaneous: float = _spent_since_tick / delta
	_spent_since_tick = 0.0
	_usage_rate = lerpf(_usage_rate, instantaneous, clampf(usage_smoothing * delta, 0.0, 1.0))
	if absf(_usage_rate - _emitted_usage) < 0.05:
		return
	_emitted_usage = _usage_rate
	usage_changed.emit(_usage_rate, total_generation())

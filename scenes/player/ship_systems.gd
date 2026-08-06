class_name ShipSystems
extends Node

## Which of the ship's systems are switched on, what each one draws from the
## reactor just by being ready, and what gets shut down first when the reactor
## can't keep up.
##
## Every system draws a small idle load whenever it's on, whether or not it's
## being used — a ship with everything running can't sustain full thrust on
## base power alone, so flying efficiently means switching off what you aren't
## using. Actually *using* a system (firing, grinding, pulling) still costs its
## own energy on top, through the same Ship.spend_energy every consumer already
## goes through.
##
## Idle draw is counted per live module: two weapon hardpoints idle at twice
## one's cost, and a destroyed or never-built module costs nothing. A system
## with no live module at all is "unavailable" — still listed on the HUD, but
## inert and free.
##
## Consumers pull their gate state each frame (Ship.is_system_enabled /
## has_radar / has_scanner / is_grinder_active), the same pull model as
## is_module_destroyed, so a module that mounts or repairs mid-flight picks up
## the current state without anything having to re-push it.

signal systems_changed
## A system was cut by the brownout handler rather than by the player — the HUD
## says so, since silently losing a system is exactly the confusing case the
## feature is meant to avoid.
signal system_auto_disabled(system_id: StringName)

const CONTROL: StringName = &"control"
const THRUSTERS: StringName = &"thrusters"
const WEAPONS: StringName = &"weapons"
const SENSORS: StringName = &"sensors"
const TRACTOR: StringName = &"tractor"
const GRINDER: StringName = &"grinder"

## Power priority, most essential first. Brownout shutdown walks it backwards,
## so utility goes before weapons and the helm is never cut.
const ORDER: Array[StringName] = [CONTROL, THRUSTERS, WEAPONS, SENSORS, TRACTOR, GRINDER]

## Everything else is essential and deliberately has no switch — losing the
## ability to fly or steer to a menu press isn't system management, it's a
## trap.
const TOGGLEABLE: Array[StringName] = [WEAPONS, SENSORS, TRACTOR, GRINDER]

const DISPLAY_NAMES: Dictionary = {
	CONTROL: "CONTROL",
	THRUSTERS: "THRUSTERS",
	WEAPONS: "WEAPONS",
	SENSORS: "SENSORS",
	TRACTOR: "TRACTOR",
	GRINDER: "GRINDER",
}

## Shown on the HUD next to each switchable system. Grinder keeps its
## established "G" rather than being renumbered.
const HOTKEY_HINTS: Dictionary = {
	WEAPONS: "1",
	SENSORS: "2",
	TRACTOR: "3",
	GRINDER: "G",
}

## Cockpit and control: a flat cost, since a layout has exactly one Core.
@export var control_idle_draw: float = 0.5
@export var thruster_idle_draw_per_module: float = 0.5
@export var weapon_idle_draw_per_module: float = 0.4
@export var sensor_idle_draw_per_module: float = 0.3
@export var tractor_idle_draw_per_module: float = 0.8
@export var grinder_idle_draw_per_module: float = 0.6
## Minimum gap between brownout shutdowns, so one flat pool doesn't strip every
## system in a single frame — the player gets one system back off at a time and
## can see each one go.
@export var auto_shutdown_interval: float = 1.5

## The grinder starts off because it deals continuous damage on contact; the
## rest start on so a fresh ship simply works.
var _switched_on: Dictionary = {
	CONTROL: true,
	THRUSTERS: true,
	WEAPONS: true,
	SENSORS: true,
	TRACTOR: true,
	GRINDER: false,
}

## system id -> number of live (mounted, not destroyed) modules backing it.
var _live_counts: Dictionary = {}
var _energy: ShipEnergy
var _shutdown_cooldown: float = 0.0


func configure(energy: ShipEnergy) -> void:
	_energy = energy


## Recounts the modules behind each system. Called on every layout apply and
## whenever the damage model reports modules destroyed or regrown, so a shot-off
## weapon hardpoint stops costing idle power immediately.
func refresh(ship: Ship, layout: ShipLayout) -> void:
	_live_counts.clear()
	if layout == null:
		systems_changed.emit()
		return

	_live_counts[CONTROL] = 1 if _is_core_alive(ship, layout) else 0
	_live_counts[THRUSTERS] = _count_live(ship, layout.get_thruster_placements())
	_live_counts[WEAPONS] = _count_live(ship, layout.get_weapon_hardpoint_placements()) \
		+ _count_live(ship, layout.get_missile_hardpoint_placements())
	_live_counts[SENSORS] = _count_live(ship, layout.get_radar_hardpoint_placements()) \
		+ _count_live(ship, layout.get_scanner_hardpoint_placements())
	_live_counts[TRACTOR] = _count_live(ship, layout.get_tractor_hardpoint_placements())
	_live_counts[GRINDER] = _count_live(ship, layout.get_grinder_hardpoint_placements())
	systems_changed.emit()


func _is_core_alive(ship: Ship, layout: ShipLayout) -> bool:
	if layout.core_placement_id.is_empty():
		return false
	return not ship.is_module_destroyed(layout.core_placement_id)


func _count_live(ship: Ship, placements: Array[ModulePlacement]) -> int:
	var count: int = 0
	for placement in placements:
		if not ship.is_module_destroyed(placement.placement_id):
			count += 1
	return count


func get_module_count(system_id: StringName) -> int:
	return _live_counts.get(system_id, 0)


func is_available(system_id: StringName) -> bool:
	return get_module_count(system_id) > 0


## The player's switch, regardless of whether the ship currently has the
## hardware for it — what the HUD's ON/OFF state shows.
func is_switched_on(system_id: StringName) -> bool:
	return _switched_on.get(system_id, false)


## Switched on *and* backed by at least one live module: the gate every
## consumer actually asks about.
func is_active(system_id: StringName) -> bool:
	return is_switched_on(system_id) and is_available(system_id)


func is_toggleable(system_id: StringName) -> bool:
	return TOGGLEABLE.has(system_id)


func set_switched_on(system_id: StringName, value: bool) -> void:
	if not is_toggleable(system_id) or _switched_on.get(system_id, false) == value:
		return
	_switched_on[system_id] = value
	systems_changed.emit()


func toggle(system_id: StringName) -> void:
	set_switched_on(system_id, not is_switched_on(system_id))


## Energy/second this system is costing right now — zero while it's off or has
## no live module behind it.
func get_idle_draw(system_id: StringName) -> float:
	if not is_active(system_id):
		return 0.0
	match system_id:
		CONTROL:
			return control_idle_draw
		THRUSTERS:
			return thruster_idle_draw_per_module * get_module_count(THRUSTERS)
		WEAPONS:
			return weapon_idle_draw_per_module * get_module_count(WEAPONS)
		SENSORS:
			return sensor_idle_draw_per_module * get_module_count(SENSORS)
		TRACTOR:
			return tractor_idle_draw_per_module * get_module_count(TRACTOR)
		GRINDER:
			return grinder_idle_draw_per_module * get_module_count(GRINDER)
	return 0.0


func total_idle_draw() -> float:
	var total: float = 0.0
	for system_id in ORDER:
		total += get_idle_draw(system_id)
	return total


## Called once per physics frame by Ship, after regeneration.
func process(delta: float) -> void:
	_shutdown_cooldown = maxf(_shutdown_cooldown - delta, 0.0)
	if _energy == null:
		return
	var unpaid: float = _energy.drain(total_idle_draw() * delta)
	if unpaid > 0.0:
		_handle_shortage()


## The pool ran dry with systems still drawing. Cut the least essential one
## that's actually running and let the player decide what to bring back —
## automatically re-enabling it the moment power recovered would just flap the
## same system on and off.
func _handle_shortage() -> void:
	if _shutdown_cooldown > 0.0:
		return
	for i in range(ORDER.size() - 1, -1, -1):
		var system_id: StringName = ORDER[i]
		if not is_toggleable(system_id) or not is_active(system_id):
			continue
		_switched_on[system_id] = false
		_shutdown_cooldown = auto_shutdown_interval
		system_auto_disabled.emit(system_id)
		systems_changed.emit()
		return


## Switch positions only — module counts are re-derived from the layout on the
## other side. Used to carry the player's choices across a warp (see GameState).
func get_switch_states() -> Dictionary:
	return _switched_on.duplicate()


func restore_switch_states(states: Dictionary) -> void:
	for system_id in states:
		if _switched_on.has(system_id):
			_switched_on[system_id] = bool(states[system_id])
	systems_changed.emit()

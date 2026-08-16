class_name ShipSystems
extends Node

## Which of the ship's systems are switched on, and the always-on load the
## modules behind them cost their circuits just by running.
##
## Switching a system off is how the player stops paying for hardware they aren't
## using. Actually *using* it (firing, cutting, pulling) costs its own energy on
## top, through the same Ship.spend_energy every consumer goes through.
##
## **The load itself lives on the modules, not here** (ModuleType.energy_idle_draw).
## This used to hold a per-system constant multiplied by a live module count,
## which meant a module's running cost was written in a table of categories
## somewhere else entirely; now a radar's 1/s is a property of radars. What this
## class still owns is the *switch*, which is a player-facing thing and belongs
## with the rest of the player-facing power management.
##
## There is deliberately no brownout auto-shutdown any more. It existed to stop
## one flat ship-wide pool from stripping every system at once; a circuit running
## dry now does that job, scoped to the modules the player actually put on it,
## and two systems shutting things down in competition is worse than either.
##
## Consumers pull their gate state each frame (Ship.is_system_enabled /
## has_radar / has_scanner / is_slicer_active), the same pull model as
## is_module_destroyed, so a module that mounts or repairs mid-flight picks up
## the current state without anything having to re-push it.

signal systems_changed

const CONTROL: StringName = &"control"
const THRUSTERS: StringName = &"thrusters"
const WEAPONS: StringName = &"weapons"
const SENSORS: StringName = &"sensors"
const TRACTOR: StringName = &"tractor"
const SALVAGER: StringName = &"salvager"

## Display order, most essential first — what the HUD lists top to bottom.
const ORDER: Array[StringName] = [CONTROL, THRUSTERS, WEAPONS, SENSORS, TRACTOR, SALVAGER]

## Everything else is essential and deliberately has no switch — losing the
## ability to fly or steer to a menu press isn't system management, it's a
## trap.
const TOGGLEABLE: Array[StringName] = [WEAPONS, SENSORS, TRACTOR, SALVAGER]

const DISPLAY_NAMES: Dictionary = {
	CONTROL: "CONTROL",
	THRUSTERS: "THRUSTERS",
	WEAPONS: "WEAPONS",
	SENSORS: "SENSORS",
	TRACTOR: "TRACTOR",
	SALVAGER: "SALVAGER",
}

## Shown on the HUD next to each switchable system. The Salvager keeps the "G"
## the Grinder established rather than being renumbered.
const HOTKEY_HINTS: Dictionary = {
	WEAPONS: "1",
	SENSORS: "2",
	TRACTOR: "3",
	SALVAGER: "G",
}

## The salvager starts off because its beam damages whatever it touches; the
## rest start on so a fresh ship simply works.
var _switched_on: Dictionary = {
	CONTROL: true,
	THRUSTERS: true,
	WEAPONS: true,
	SENSORS: true,
	TRACTOR: true,
	SALVAGER: false,
}

## system id -> number of live (mounted, not destroyed) modules backing it.
var _live_counts: Dictionary = {}


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
	_live_counts[SALVAGER] = _count_live(ship, layout.get_salvager_hardpoint_placements())
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


## Which system a module belongs to, or an empty name for plain structure.
##
## Derived from what the module *does* rather than from a list of ids, so a new
## weapon tier or a second radar type is picked up with no change here — the same
## reasoning as ShipLayout._get_hardpoint_placements matching on category.
static func system_for(module_type: ModuleType, is_core: bool) -> StringName:
	if module_type == null:
		return &""
	if is_core:
		return CONTROL
	if module_type.thrust_contribution > 0.0:
		return THRUSTERS
	match module_type.hardpoint_category:
		"weapon", "missile":
			return WEAPONS
		"radar", "scanner":
			return SENSORS
		"tractor":
			return TRACTOR
		"salvager":
			return SALVAGER
	return &""


## Energy/second the ship is paying just to have things switched on, summed
## across every live module. For the HUD only — the actual charging below is per
## module against per circuit, and never against this total.
func total_idle_draw(ship: Ship, layout: ShipLayout) -> float:
	var total: float = 0.0
	if layout == null:
		return total
	for placement in layout.placements:
		total += _idle_draw_of(ship, layout, placement)
	return total


## Called once per physics frame by Ship, after regeneration. Charges each
## always-on module's own draw to its own circuit.
##
## A circuit that cannot cover it simply runs dry, and everything on that circuit
## stops working until its reactor catches up. Nothing is switched off on the
## player's behalf: the shortage is now local to a circuit they built, and
## recovering from it is their decision to make.
func process(delta: float, ship: Ship, layout: ShipLayout) -> void:
	if layout == null:
		return
	for placement in layout.placements:
		var draw: float = _idle_draw_of(ship, layout, placement)
		if draw > 0.0:
			ship.drain_energy(draw * delta, placement.placement_id)


func _idle_draw_of(ship: Ship, layout: ShipLayout, placement: ModulePlacement) -> float:
	if ship.is_module_destroyed(placement.placement_id):
		return 0.0
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null or module_type.energy_idle_draw <= 0.0:
		return 0.0
	var system_id: StringName = system_for(
		module_type, placement.placement_id == layout.core_placement_id)
	if not system_id.is_empty() and not is_active(system_id):
		return 0.0
	return module_type.energy_idle_draw


## Switch positions only — module counts are re-derived from the layout on the
## other side. Used to carry the player's choices across a warp (see GameState).
func get_switch_states() -> Dictionary:
	return _switched_on.duplicate()


func restore_switch_states(states: Dictionary) -> void:
	for system_id in states:
		if _switched_on.has(system_id):
			_switched_on[system_id] = bool(states[system_id])
	systems_changed.emit()

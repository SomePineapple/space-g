extends Node

## Turns this machine's keyboard and mouse into a ShipIntent and submits it to
## the parent Ship each physics frame. It no longer calls the ship's individual
## input methods — everything commanding a ship goes through submit_intent(), so
## a remote peer's intent and this one are the same kind of thing arriving by a
## different route.
##
## Which parts of the intent are actually honoured is decided by the ship, from
## the roles passed alongside it (PlayerContext.local_roles). Solo play holds
## every role; a crew station later holds a subset, and the fields it isn't
## entitled to are discarded on arrival rather than never being filled here.

## Furthest a target (enemy ship or asteroid) can be from the mouse cursor
## to be lock-on-able.
const MAX_LOCK_RANGE: float = 1200.0
## Nebulae (see nebula.gd) scramble sensors — lock range is cut to this
## fraction of MAX_LOCK_RANGE while the ship is inside one.
const NEBULA_LOCK_RANGE_FRACTION: float = 0.35

const LOCK_INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/lock_on_indicator.tscn")

## Input action -> the ShipSystems id it switches. "toggle_grinder" keeps its
## established G binding rather than being renumbered alongside the new ones.
const SYSTEM_TOGGLE_ACTIONS: Dictionary = {
	"toggle_system_weapons": ShipSystems.WEAPONS,
	"toggle_system_sensors": ShipSystems.SENSORS,
	"toggle_system_tractor": ShipSystems.TRACTOR,
	"toggle_grinder": ShipSystems.GRINDER,
}

@onready var ship: Ship = get_parent()

## Reused rather than reallocated per frame; submit_intent() copies out of it.
var _intent: ShipIntent = ShipIntent.new()
var _lock_indicator: Node2D = null
## Which target _lock_indicator is currently attached to, so the sync below is a
## no-op on the vast majority of frames where the lock hasn't changed.
var _indicator_target: Node2D = null


func _ready() -> void:
	# Controllers must run before the ship consumes what they submit, otherwise
	# every input lands a frame late (children process after their parent by
	# default). Lower priority runs earlier.
	process_physics_priority = -1


func _physics_process(_delta: float) -> void:
	_intent.clear()

	if not _is_menu_open():
		_read_helm()
		_read_weapons()
		_read_operations()

	ship.submit_intent(_intent, PlayerContext.local_roles)
	_sync_lock_indicator()


func _read_helm() -> void:
	_intent.thrust = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	_intent.turn = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	_intent.boost = Input.is_action_pressed("boost")


func _read_weapons() -> void:
	_intent.aim_target = ship.get_global_mouse_position()
	_intent.has_aim_target = true
	_intent.fire_primary = Input.is_action_pressed("fire_primary")
	_intent.fire_secondary = Input.is_action_just_pressed("fire_secondary")

	if Input.is_action_just_pressed("lock_target"):
		_request_lock_toggle()


func _read_operations() -> void:
	_intent.fire_winch = Input.is_action_just_pressed("fire_winch")
	_intent.winch_reel = Input.is_action_pressed("fire_winch")
	_intent.toggle_scan = Input.is_action_just_pressed("scan")
	_read_system_toggles()


## Power switches for the ship's systems (see ShipSystems). One action per
## system rather than a cycle-and-confirm, so any system is one key away.
func _read_system_toggles() -> void:
	for action_name in SYSTEM_TOGGLE_ACTIONS:
		if Input.is_action_just_pressed(action_name):
			_intent.toggled_systems.append(SYSTEM_TOGGLE_ACTIONS[action_name])


## Any "menu_panel"-grouped CanvasLayer (ship builder, upgrade panel) being
## open suspends ship control entirely, so R/X/etc. can be reused as menu
## hotkeys without also firing weapons or turning the ship underneath it. The
## intent is still submitted, cleared — an open menu means "command nothing",
## not "keep doing whatever you were doing".
func _is_menu_open() -> bool:
	for panel in get_tree().get_nodes_in_group("menu_panel"):
		if panel.visible:
			return true
	return false


## Writes the lock change into this frame's intent. Nothing is locked here — the
## ship decides, and only if it accepts the WEAPONS role from this controller.
func _request_lock_toggle() -> void:
	_intent.set_lock = true
	_intent.locked_target = null if ship.get_locked_target() != null else _find_nearest_lockable_to_cursor()


## Nearest lockable object (enemy ship or asteroid) to the mouse cursor,
## within MAX_LOCK_RANGE, so locking works like clicking on a target rather
## than always picking the closest one to the player's own ship.
func _find_nearest_lockable_to_cursor() -> Node2D:
	var cursor: Vector2 = ship.get_global_mouse_position()
	var effective_range: float = MAX_LOCK_RANGE
	if ship.is_in_nebula():
		effective_range *= NEBULA_LOCK_RANGE_FRACTION
	var best: Node2D = null
	var best_distance: float = effective_range
	for target in get_tree().get_nodes_in_group("lockable"):
		var distance: float = target.global_position.distance_to(cursor)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


## Keeps the on-screen indicator matched to the lock the ship actually holds,
## rather than to what this controller asked for. Two reasons: a request only
## takes effect a frame later (the ship consumes intents after its controllers
## submit them) and may be refused outright if this station doesn't hold
## WEAPONS — and the locked target can be destroyed by something else entirely,
## which this picks up without needing a fresh toggle press.
func _sync_lock_indicator() -> void:
	var target: Node2D = ship.get_locked_target()
	if target == _indicator_target:
		return

	if _lock_indicator != null and is_instance_valid(_lock_indicator):
		_lock_indicator.queue_free()
	_lock_indicator = null
	_indicator_target = target

	if target != null:
		_lock_indicator = LOCK_INDICATOR_SCENE.instantiate()
		target.add_child(_lock_indicator)

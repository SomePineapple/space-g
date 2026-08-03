extends Node

## Furthest a target (enemy ship or asteroid) can be from the mouse cursor
## to be lock-on-able.
const MAX_LOCK_RANGE: float = 1200.0
## Nebulae (see nebula.gd) scramble sensors — lock range is cut to this
## fraction of MAX_LOCK_RANGE while the ship is inside one.
const NEBULA_LOCK_RANGE_FRACTION: float = 0.35

const LOCK_INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/lock_on_indicator.tscn")

@onready var ship: Ship = get_parent()

var _lock_indicator: Node2D = null


func _physics_process(_delta: float) -> void:
	if _is_menu_open():
		ship.set_thrust_input(0.0)
		ship.set_turn_input(0.0)
		return

	var thrust: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var turn: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")

	ship.set_thrust_input(thrust)
	ship.set_turn_input(turn)
	ship.set_boost_input(Input.is_action_pressed("boost"))
	ship.set_aim_target(ship.get_global_mouse_position())

	if Input.is_action_just_pressed("lock_target"):
		_toggle_lock()
	_clear_indicator_if_target_gone()

	if Input.is_action_pressed("fire_primary"):
		ship.fire_primary()

	if Input.is_action_just_pressed("fire_secondary"):
		ship.fire_secondary()

	if Input.is_action_just_pressed("fire_winch"):
		ship.fire_winch()
	ship.set_winch_reel_input(Input.is_action_pressed("fire_winch"))


## Any "menu_panel"-grouped CanvasLayer (ship builder, upgrade panel) being
## open suspends ship control entirely, so R/X/etc. can be reused as menu
## hotkeys without also firing weapons or turning the ship underneath it.
func _is_menu_open() -> bool:
	for panel in get_tree().get_nodes_in_group("menu_panel"):
		if panel.visible:
			return true
	return false


func _toggle_lock() -> void:
	if ship.get_locked_target() != null:
		_set_lock(null)
		return

	_set_lock(_find_nearest_lockable_to_cursor())


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


func _set_lock(target: Node2D) -> void:
	if _lock_indicator != null and is_instance_valid(_lock_indicator):
		_lock_indicator.queue_free()
	_lock_indicator = null

	ship.set_locked_target(target)
	if target != null:
		_lock_indicator = LOCK_INDICATOR_SCENE.instantiate()
		target.add_child(_lock_indicator)


## The locked target can be destroyed by something other than this ship
## (another weapon, a boundary push into an asteroid, etc.), so the
## indicator needs to clean itself up even without a fresh toggle press.
func _clear_indicator_if_target_gone() -> void:
	if ship.get_locked_target() == null and _lock_indicator != null:
		if is_instance_valid(_lock_indicator):
			_lock_indicator.queue_free()
		_lock_indicator = null

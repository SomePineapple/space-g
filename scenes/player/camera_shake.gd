extends Camera2D

@export var damage_shake_strength: float = 8.0
@export var destroyed_shake_strength: float = 20.0
@export var shake_decay_rate: float = 40.0

## Ship layout extent (see Ship.get_layout_extent()) at which zoom is
## max_zoom — tuned to the starter ship's size.
@export var reference_ship_extent: float = 66.0
## Widened 50% (divided by 1.5) versus the original ship-size-only range so
## the default view shows more of the surroundings.
@export var min_zoom: float = 0.35 / 1.5
@export var max_zoom: float = 0.6 / 1.5
@export var zoom_response: float = 3.0

## Scroll wheel zoom-in/out on top of the ship-size-driven base zoom.
@export var scroll_zoom_step: float = 0.05
## Closest the player can scroll in, regardless of ship size — the old
## max_zoom (0.6), i.e. roughly a 6-hex ship's default zoom.
@export var scroll_max_zoom: float = 0.6

var _shake_strength: float = 0.0
var _base_zoom: float = 1.0
var _manual_zoom_offset: float = 0.0
var _target_zoom: float = 1.0
var _last_known_health: float = -1.0

@onready var _ship: Ship = get_parent()
@onready var _health: Health = _ship.get_node("Health")


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)
	_health.destroyed.connect(_on_destroyed)
	_ship.layout_applied.connect(_on_layout_applied)


## Only current < last-known counts as damage — Health.heal() (module
## repair regrowing, see Ship._advance_module_repair) also emits
## health_changed, and configure() (ship rebuilds) resets to full, so
## neither should shake the camera the way taking a hit does.
func _on_health_changed(current: float, _max: float) -> void:
	var took_damage: bool = _last_known_health >= 0.0 and current < _last_known_health
	_last_known_health = current
	if took_damage:
		_shake_strength = maxf(_shake_strength, damage_shake_strength)


func _on_destroyed() -> void:
	_shake_strength = destroyed_shake_strength


## Public hook for one-off camera kicks from outside (e.g. WarpGate's speed
## lane jump) that aren't tied to taking damage or being destroyed.
func add_shake(amount: float) -> void:
	_shake_strength = maxf(_shake_strength, amount)


func _on_layout_applied() -> void:
	var extent: float = maxf(_ship.get_layout_extent(), 1.0)
	_base_zoom = clampf(reference_ship_extent / extent, min_zoom, max_zoom)
	_update_target_zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_manual_zoom_offset += scroll_zoom_step
			_update_target_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_manual_zoom_offset -= scroll_zoom_step
			_update_target_zoom()


## Scroll can zoom in up to scroll_max_zoom but never out past _base_zoom
## (the current ship's size-driven zoom) — so the ship's own size always
## sets the furthest-out view, and growing the ship pulls an under-cap
## zoom back up with it.
func _update_target_zoom() -> void:
	_target_zoom = clampf(_base_zoom + _manual_zoom_offset, _base_zoom, scroll_max_zoom)


func _process(delta: float) -> void:
	zoom = zoom.move_toward(Vector2(_target_zoom, _target_zoom), zoom_response * delta)

	if _shake_strength <= 0.0:
		offset = Vector2.ZERO
		return

	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	_shake_strength = maxf(_shake_strength - shake_decay_rate * delta, 0.0)

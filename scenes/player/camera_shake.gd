extends Camera2D

@export var damage_shake_strength: float = 8.0
@export var destroyed_shake_strength: float = 20.0
@export var shake_decay_rate: float = 40.0

## Ship layout extent (see Ship.get_layout_extent()) at which zoom is 1.0 —
## tuned to the starter ship's size, so default framing is unchanged.
@export var reference_ship_extent: float = 66.0
@export var min_zoom: float = 0.35
@export var max_zoom: float = 1.0
@export var zoom_response: float = 3.0

var _shake_strength: float = 0.0
var _target_zoom: float = 1.0

@onready var _ship: Ship = get_parent()
@onready var _health: Health = _ship.get_node("Health")


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)
	_health.destroyed.connect(_on_destroyed)
	_ship.layout_applied.connect(_on_layout_applied)


func _on_health_changed(_current: float, _max: float) -> void:
	_shake_strength = maxf(_shake_strength, damage_shake_strength)


func _on_destroyed() -> void:
	_shake_strength = destroyed_shake_strength


func _on_layout_applied() -> void:
	var extent: float = maxf(_ship.get_layout_extent(), 1.0)
	_target_zoom = clampf(reference_ship_extent / extent, min_zoom, max_zoom)


func _process(delta: float) -> void:
	zoom = zoom.move_toward(Vector2(_target_zoom, _target_zoom), zoom_response * delta)

	if _shake_strength <= 0.0:
		offset = Vector2.ZERO
		return

	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	_shake_strength = maxf(_shake_strength - shake_decay_rate * delta, 0.0)

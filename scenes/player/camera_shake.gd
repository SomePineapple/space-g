extends Camera2D

@export var damage_shake_strength: float = 8.0
@export var destroyed_shake_strength: float = 20.0
@export var shake_decay_rate: float = 40.0

var _shake_strength: float = 0.0

@onready var _health: Health = get_parent().get_node("Health")


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)
	_health.destroyed.connect(_on_destroyed)


func _on_health_changed(_current: float, _max: float) -> void:
	_shake_strength = maxf(_shake_strength, damage_shake_strength)


func _on_destroyed() -> void:
	_shake_strength = destroyed_shake_strength


func _process(delta: float) -> void:
	if _shake_strength <= 0.0:
		offset = Vector2.ZERO
		return

	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	_shake_strength = maxf(_shake_strength - shake_decay_rate * delta, 0.0)

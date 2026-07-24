class_name Health
extends Node

signal health_changed(current: float, max: float)
signal destroyed

@export var max_health: float = 100.0

var current_health: float


func _ready() -> void:
	current_health = max_health


func configure(max_health_value: float) -> void:
	max_health = max_health_value
	current_health = max_health_value


func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		destroyed.emit()

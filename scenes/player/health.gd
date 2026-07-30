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
	health_changed.emit(current_health, max_health)


func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		destroyed.emit()


## Mirrors module repair (see Ship._repair_module): a holed-out module
## regrowing restores the same amount to the overall Health pool, so a fully
## repaired ship doesn't still carry invisible splash-damage debt from
## before.
func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

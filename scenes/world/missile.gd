class_name Missile
extends Projectile

@export var turn_rate: float = 1.2

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false


func set_target(target_position: Vector2) -> void:
	_target_position = target_position
	_has_target = true


func _physics_process(delta: float) -> void:
	if _has_target:
		var to_target: Vector2 = _target_position - global_position
		if to_target.length() > 4.0:
			var desired_direction: Vector2 = to_target.normalized()
			var current_direction: Vector2 = _velocity.normalized()
			var new_direction: Vector2 = current_direction.slerp(desired_direction, turn_rate * delta)
			_velocity = new_direction * speed
			rotation = _velocity.angle()

	super._physics_process(delta)

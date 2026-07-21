extends Node

@onready var ship: Ship = get_parent()


func _physics_process(_delta: float) -> void:
	var thrust: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var turn: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")

	ship.set_thrust_input(thrust)
	ship.set_turn_input(turn)
	ship.set_boost_input(Input.is_action_pressed("boost"))

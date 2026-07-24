class_name EnemySpawner
extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_ship.tscn")
@export var spawn_position: Vector2 = Vector2(600, 300)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("spawn_enemy"):
		var enemy: Ship = enemy_scene.instantiate()
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_position

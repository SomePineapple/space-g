class_name EnemySpawner
extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_ship.tscn")
@export var missile_cruiser_scene: PackedScene = preload("res://scenes/enemies/missile_cruiser.tscn")
@export var spawn_position: Vector2 = Vector2(600, 300)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("spawn_enemy"):
		_spawn(enemy_scene)
	elif event.is_action_pressed("spawn_missile_cruiser"):
		_spawn(missile_cruiser_scene)


func _spawn(scene: PackedScene) -> void:
	var enemy: Ship = scene.instantiate()
	WorldSpawn.attach_at(enemy, spawn_position)

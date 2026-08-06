class_name RegionBoundary
extends Node2D

## Keeps the player within one coherent region instead of drifting into
## endless empty space. Push-back grows with how far past the radius the
## ship strays, so the edge feels like a gentle current rather than a wall.
@export var radius: float = 1600.0
@export var push_back_strength: float = 40.0


## Deliberately every player ship in the group, not PlayerContext's one: the
## boundary is a property of the region and has to hold whoever is in it. With
## one ship per player later, each of them needs pushing back, not just the one
## this machine happens to fly.
func _physics_process(delta: float) -> void:
	for player in get_tree().get_nodes_in_group("player_ship"):
		_push_back(player, delta)


func _push_back(player: Ship, delta: float) -> void:
	var offset: Vector2 = player.global_position - global_position
	var distance: float = offset.length()
	if distance <= radius:
		return

	var overshoot: float = distance - radius
	var inward_direction: Vector2 = -offset / distance
	player.apply_impulse(inward_direction * push_back_strength * overshoot * delta)

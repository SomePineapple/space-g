class_name RegionSpawner
extends Node2D

## Procedurally fills a rectangular area (centered on this node) with
## asteroids according to a RegionType's density/size-mix/spacing, instead
## of hand-placing every asteroid — see "1.3 Basic world regions". Spawns
## once using a seeded RNG, so a region's layout is identical every time
## its scene loads (stable when revisited). Spawning is deferred past
## _ready() since sibling nodes (including the scene root itself) may still
## be mid-setup when this node enters the tree, and current_scene.add_child()
## fails if called while the parent is busy adding its own children.

@export var region_type: RegionType
@export var region_size: Vector2 = Vector2(2000.0, 2000.0)
@export var random_seed: int = 1
## Local-space points (relative to this node) that must stay clear of
## asteroids — put an arrival gate/marker's local position here so nothing
## spawns on top of it or the ship that arrives there.
@export var keep_clear_points: Array[Vector2] = [Vector2.ZERO]
@export var keep_clear_radius: float = 350.0
@export var asteroid_scene: PackedScene = preload("res://scenes/world/asteroid.tscn")

const MAX_ATTEMPTS_PER_ASTEROID: int = 30


func _ready() -> void:
	_spawn_region.call_deferred()


func _spawn_region() -> void:
	if region_type == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var area: float = region_size.x * region_size.y
	var target_count: int = roundi(area / 1000000.0 * region_type.asteroid_density)

	var placed_points: Array[Vector2] = []
	for i in target_count:
		var point: Vector2 = _find_valid_point(rng, placed_points)
		if point == Vector2.INF:
			continue
		placed_points.append(point)
		_spawn_asteroid(rng, point)


func _find_valid_point(rng: RandomNumberGenerator, placed_points: Array[Vector2]) -> Vector2:
	for attempt in MAX_ATTEMPTS_PER_ASTEROID:
		var candidate := Vector2(
			rng.randf_range(-region_size.x * 0.5, region_size.x * 0.5),
			rng.randf_range(-region_size.y * 0.5, region_size.y * 0.5)
		)
		if _is_clear(candidate, placed_points):
			return candidate
	return Vector2.INF


func _is_clear(candidate: Vector2, placed_points: Array[Vector2]) -> bool:
	for clear_point in keep_clear_points:
		if candidate.distance_to(clear_point) < keep_clear_radius:
			return false
	for placed in placed_points:
		if candidate.distance_to(placed) < region_type.min_spacing:
			return false
	return true


func _spawn_asteroid(rng: RandomNumberGenerator, local_point: Vector2) -> void:
	var asteroid: Asteroid = asteroid_scene.instantiate()
	asteroid.size_tier = region_type.pick_size_tier(rng)
	asteroid.random_seed = rng.randi_range(1, 10000000)
	asteroid.self_modulate = region_type.asteroid_tint
	get_tree().current_scene.add_child(asteroid)
	asteroid.global_position = global_position + local_point

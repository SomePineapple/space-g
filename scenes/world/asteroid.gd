class_name Asteroid
extends StaticBody2D

@export var min_radius: float = 30.0
@export var max_radius: float = 60.0
@export var point_count: int = 9
@export var irregularity: float = 0.35
@export var random_seed: int = 1

@onready var _visual: Polygon2D = $Visual
@onready var _collision: CollisionPolygon2D = $Collision


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var base_radius: float = rng.randf_range(min_radius, max_radius)
	var points: PackedVector2Array = PackedVector2Array()
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count)
		var radius: float = base_radius * (1.0 - irregularity + rng.randf() * irregularity * 2.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	_visual.polygon = points
	_collision.polygon = points

	var shade: float = rng.randf_range(0.35, 0.55)
	_visual.color = Color(shade, shade * 0.95, shade * 0.9)

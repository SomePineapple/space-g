class_name Asteroid
extends StaticBody2D

@export var min_radius: float = 30.0
@export var max_radius: float = 60.0
@export var point_count: int = 9
@export var irregularity: float = 0.35
@export var random_seed: int = 1
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var salvage_scene: PackedScene = preload("res://scenes/world/salvage.tscn")
@export var destruction_explosion_scale: float = 1.2

@onready var _visual: Polygon2D = $Visual
@onready var _collision: CollisionPolygon2D = $Collision
@onready var _health: Health = $Health

var _radius: float = 0.0


func _ready() -> void:
	add_to_group("lockable")

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var base_radius: float = rng.randf_range(min_radius, max_radius)
	_radius = base_radius
	var points: PackedVector2Array = PackedVector2Array()
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count)
		var radius: float = base_radius * (1.0 - irregularity + rng.randf() * irregularity * 2.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	_visual.polygon = points
	_collision.polygon = points

	var shade: float = rng.randf_range(0.35, 0.55)
	_visual.color = Color(shade, shade * 0.95, shade * 0.9)

	_health.destroyed.connect(_on_destroyed)


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


## Used by HardpointWinch for touch/arrival checks. Deliberately has no
## apply_impulse (StaticBody2D — genuinely immovable), so a winch grappled to
## an asteroid always pulls the ship toward it, never the reverse.
func get_winch_radius() -> float:
	return _radius


## Deferred as a whole: this fires from within the physics engine's
## collision query flush (via Projectile's body_entered signal), and both
## adding the Salvage Area2D to the tree and freeing this body would
## otherwise touch physics server shape state mid-flush.
func _on_destroyed() -> void:
	_finish_destruction.call_deferred()


func _finish_destruction() -> void:
	var explosion: Explosion = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	explosion.effect_scale = destruction_explosion_scale

	var salvage: Salvage = salvage_scene.instantiate()
	salvage.rarity = _roll_ore_rarity()
	get_tree().current_scene.add_child(salvage)
	salvage.global_position = global_position

	queue_free()


func _roll_ore_rarity() -> Salvage.Rarity:
	var roll: float = randf()
	if roll < 0.7:
		return Salvage.Rarity.COMMON
	elif roll < 0.95:
		return Salvage.Rarity.ELECTRONICS
	else:
		return Salvage.Rarity.ENERGY

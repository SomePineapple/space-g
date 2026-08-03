class_name Asteroid
extends StaticBody2D

enum SizeTier { LARGE, MEDIUM, SMALL }
enum AsteroidVariant { ROCKY, ICY, RUSTY, CRYSTALLINE }

## Radius range, health and next-tier-down per SizeTier. Splitting a LARGE
## yields MEDIUM fragments, splitting a MEDIUM yields SMALL; SMALL has no
## entry in NEXT_TIER_DOWN, so it just breaks apart into salvage.
const RADIUS_RANGES := {
	SizeTier.LARGE: Vector2(70.0, 100.0),
	SizeTier.MEDIUM: Vector2(40.0, 65.0),
	SizeTier.SMALL: Vector2(18.0, 32.0),
}
const TIER_HEALTH := {
	SizeTier.LARGE: 90.0,
	SizeTier.MEDIUM: 45.0,
	SizeTier.SMALL: 20.0,
}
const NEXT_TIER_DOWN := {
	SizeTier.LARGE: SizeTier.MEDIUM,
	SizeTier.MEDIUM: SizeTier.SMALL,
}
## Per-variant shape (point count / silhouette irregularity) and colour tint,
## so "several visual variants" doesn't rely on shade alone.
const VARIANT_SHAPE := {
	AsteroidVariant.ROCKY: {"point_count": 9, "irregularity": 0.35},
	AsteroidVariant.ICY: {"point_count": 11, "irregularity": 0.2},
	AsteroidVariant.RUSTY: {"point_count": 7, "irregularity": 0.45},
	AsteroidVariant.CRYSTALLINE: {"point_count": 6, "irregularity": 0.15},
}
const VARIANT_TINT := {
	AsteroidVariant.ROCKY: Color(1.0, 0.95, 0.9),
	AsteroidVariant.ICY: Color(0.8, 0.9, 1.15),
	AsteroidVariant.RUSTY: Color(1.15, 0.75, 0.6),
	AsteroidVariant.CRYSTALLINE: Color(0.85, 1.05, 1.0),
}

@export var size_tier: SizeTier = SizeTier.MEDIUM
@export var random_seed: int = 1
## Constant, author-set drift for a slow-wandering asteroid. Zero (the
## default) means the asteroid just sits and slowly rotates in place.
@export var drift_velocity: Vector2 = Vector2.ZERO
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var salvage_scene: PackedScene = preload("res://scenes/world/salvage.tscn")
@export var asteroid_scene: PackedScene = preload("res://scenes/world/asteroid.tscn")
@export var destruction_explosion_scale: float = 1.2
## Cumulative ore-roll thresholds, matching _roll_ore_rarity's COMMON /
## ELECTRONICS / ENERGY bands — exported so denser, richer clusters (e.g. an
## asteroid field point of interest) can skew toward better ore without a
## second copy of this script.
@export_range(0.0, 1.0) var common_chance: float = 0.7
@export_range(0.0, 1.0) var electronics_chance: float = 0.95
@export var split_fragment_count: int = 2
@export var scatter_speed: float = 90.0
@export var scatter_decay: float = 120.0
## Small knockback nudge applied on a direct hit (reuses the split-fragment
## scatter/decay mechanics below rather than a second movement system).
@export var hit_knockback_speed: float = 25.0
@export var max_knockback_speed: float = 150.0

@onready var _visual: Polygon2D = $Visual
@onready var _collision: CollisionPolygon2D = $Collision
@onready var _health: Health = $Health

var _radius: float = 0.0
var _rotation_speed: float = 0.0
var _scatter_velocity: Vector2 = Vector2.ZERO
## Kept alive past _ready so split fragments get deterministic seeds — the
## sequence of calls made against it is fixed by code order, so the same
## random_seed always produces the same shape, tint, rotation and (later)
## the same child seeds/offsets.
var _rng: RandomNumberGenerator


func _ready() -> void:
	add_to_group("lockable")
	add_to_group("asteroid")

	_rng = RandomNumberGenerator.new()
	_rng.seed = random_seed

	var variant: int = _rng.randi_range(0, VARIANT_SHAPE.size() - 1)
	var shape: Dictionary = VARIANT_SHAPE[variant]
	var point_count: int = shape.point_count
	var irregularity: float = shape.irregularity

	var radius_range: Vector2 = RADIUS_RANGES[size_tier]
	var base_radius: float = _rng.randf_range(radius_range.x, radius_range.y)
	_radius = base_radius

	var points: PackedVector2Array = PackedVector2Array()
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count)
		var point_radius: float = base_radius * (1.0 - irregularity + _rng.randf() * irregularity * 2.0)
		points.append(Vector2(cos(angle), sin(angle)) * point_radius)

	_visual.polygon = points
	_collision.polygon = points

	var shade: float = _rng.randf_range(0.35, 0.55)
	var tint: Color = VARIANT_TINT[variant]
	_visual.color = Color(shade * tint.r, shade * tint.g, shade * tint.b)

	_rotation_speed = _rng.randf_range(0.05, 0.25) * (1.0 if _rng.randf() < 0.5 else -1.0)

	_health.configure(TIER_HEALTH[size_tier])
	_health.destroyed.connect(_on_destroyed)


func _physics_process(delta: float) -> void:
	rotation += _rotation_speed * delta
	if drift_velocity != Vector2.ZERO or _scatter_velocity != Vector2.ZERO:
		position += (drift_velocity + _scatter_velocity) * delta
		_scatter_velocity = _scatter_velocity.move_toward(Vector2.ZERO, scatter_decay * delta)


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


## Preferred by Projectile over take_damage when available, so a hit also
## nudges the asteroid back along the shot's travel direction. Reuses
## _scatter_velocity/scatter_decay (the same mechanic split fragments use)
## instead of a second movement system, clamped so rapid fire can't build up
## unbounded speed.
func take_damage_at(amount: float, hit_position: Vector2) -> void:
	_health.take_damage(amount)
	var direction: Vector2 = global_position - hit_position
	direction = direction.normalized() if direction.length() > 0.001 else Vector2.UP
	_scatter_velocity = (_scatter_velocity + direction * hit_knockback_speed).limit_length(max_knockback_speed)


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

	if NEXT_TIER_DOWN.has(size_tier):
		_spawn_fragments(NEXT_TIER_DOWN[size_tier])

	queue_free()


## Scatters `split_fragment_count` smaller asteroids evenly around a random
## base angle, offset outward from the parent's centre so fragments don't
## overlap each other or leave a ship sitting at the old centre suddenly
## boxed in. Each fragment gets a brief outward scatter_velocity that decays
## via _physics_process, then settles like any other static asteroid.
func _spawn_fragments(child_tier: SizeTier) -> void:
	var base_angle: float = _rng.randf_range(0.0, TAU)
	var offset_distance: float = _radius * 0.4
	for i in split_fragment_count:
		var angle: float = base_angle + TAU * float(i) / float(split_fragment_count)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))

		var fragment: Asteroid = asteroid_scene.instantiate()
		fragment.size_tier = child_tier
		fragment.random_seed = _rng.randi_range(1, 1000000)
		fragment.common_chance = common_chance
		fragment.electronics_chance = electronics_chance
		fragment.split_fragment_count = split_fragment_count
		fragment.scatter_speed = scatter_speed
		fragment.scatter_decay = scatter_decay

		get_tree().current_scene.add_child(fragment)
		fragment.global_position = global_position + direction * offset_distance
		fragment._scatter_velocity = direction * scatter_speed


func _roll_ore_rarity() -> Salvage.Rarity:
	var roll: float = randf()
	if roll < common_chance:
		return Salvage.Rarity.COMMON
	elif roll < electronics_chance:
		return Salvage.Rarity.ELECTRONICS
	else:
		return Salvage.Rarity.ENERGY

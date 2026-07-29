class_name Projectile
extends Area2D

@export var speed: float = 700.0
@export var lifetime: float = 2.0
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var explosion_scale: float = 0.35
@export var damage: float = 10.0

@export var color: Color = Color(1, 1, 1, 1):
	set(value):
		color = value
		if is_node_ready():
			_visual.color = value

var _velocity: Vector2 = Vector2.ZERO
var _time_alive: float = 0.0
var _shooter: Node = null

@onready var _visual: Polygon2D = $Visual


func launch(travel_speed: float, shooter: Node = null) -> void:
	speed = travel_speed
	_velocity = transform.x * speed
	_shooter = shooter


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual.color = color


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()


func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_destroy()


func _destroy() -> void:
	var explosion: Explosion = explosion_scene.instantiate()
	explosion.tint = color
	explosion.effect_scale = explosion_scale
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Deferred: this runs from within the physics engine's collision query
	# flush (_on_body_entered), where freeing a CollisionObject2D
	# synchronously triggers a physics server error.
	queue_free.call_deferred()

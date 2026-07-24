class_name Explosion
extends Node2D

@export var tint: Color = Color(1, 1, 1, 1)
@export var effect_scale: float = 1.0

@onready var _burst: GPUParticles2D = $Burst


func _ready() -> void:
	_burst.modulate = tint
	scale = Vector2.ONE * effect_scale
	_burst.emitting = true
	_burst.finished.connect(queue_free)

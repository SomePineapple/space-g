class_name Explosion
extends Node2D

@export var tint: Color = Color(1, 1, 1, 1)
@export var effect_scale: float = 1.0
## Left unassigned by default (no audio assets yet); assign a stream on this
## exported field once one exists and every explosion (ship, asteroid,
## projectile impact all reuse this scene) will play it automatically.
@export var explosion_sound: AudioStream = null

@onready var _burst: GPUParticles2D = $Burst
@onready var _sound: AudioStreamPlayer2D = $Sound


func _ready() -> void:
	_burst.modulate = tint
	scale = Vector2.ONE * effect_scale
	_burst.emitting = true
	_burst.finished.connect(queue_free)

	if explosion_sound != null:
		_sound.stream = explosion_sound
		_sound.play()

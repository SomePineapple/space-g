class_name SeamSpark
extends Node2D

## A quick, narrow shower of sparks fired outward along one hex edge of a
## module/wing that just tore free (see WreckageSpawner.spawn_seam_sparks).
## Spawned once per boundary edge, oriented along that edge's outward
## normal, so a whole limb detaching reads as the seam itself splitting
## apart rather than one generic burst at the ship's center.

@export var tint: Color = Color(1, 1, 1, 1)
@export var effect_scale: float = 1.0

@onready var _burst: GPUParticles2D = $Burst


func _ready() -> void:
	_burst.modulate = tint
	scale = Vector2.ONE * effect_scale
	_burst.emitting = true
	_burst.finished.connect(queue_free)

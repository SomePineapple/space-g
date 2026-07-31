class_name PhaseLanceBeam
extends Node2D

## Purely cosmetic — the actual damage resolution happens instantly in
## Ship.take_beam_damage() the moment the shot fires (see
## HardpointPhaseLance._resolve_beam). This just draws the line and fades it
## out quickly, left at the scene's default (identity) transform so its
## points can be set directly in world space.

@export var tint: Color = Color(0.75, 0.55, 1.0, 1.0)
@export var fade_duration: float = 0.18

@onready var _line: Line2D = $Line


func _ready() -> void:
	_line.default_color = tint


func setup(from_point: Vector2, to_point: Vector2) -> void:
	_line.points = PackedVector2Array([from_point, to_point])
	var tween: Tween = create_tween()
	tween.tween_property(_line, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)

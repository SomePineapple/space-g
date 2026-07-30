class_name LockOnIndicator
extends Node2D

@export var radius: float = 40.0
@export var rotation_speed: float = 3.0
@export var color: Color = Color(1.0, 0.15, 0.15, 1.0)
@export var arc_width: float = 3.0
@export var segment_count: int = 3
@export var segment_arc_deg: float = 50.0


func _process(delta: float) -> void:
	rotation += rotation_speed * delta
	queue_redraw()


func _draw() -> void:
	var segment_gap: float = TAU / segment_count
	for i in segment_count:
		var start_angle: float = i * segment_gap
		var end_angle: float = start_angle + deg_to_rad(segment_arc_deg)
		draw_arc(Vector2.ZERO, radius, start_angle, end_angle, 16, color, arc_width)

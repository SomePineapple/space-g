class_name UpgradeTreeLines
extends Control

const LINE_COLOR: Color = Color(0.6, 0.75, 0.9, 0.9)
const LINE_WIDTH: float = 2.0
const ARROW_SIZE: float = 8.0

var _lines: Array = []


func set_lines(new_lines: Array) -> void:
	_lines = new_lines
	queue_redraw()


func _draw() -> void:
	for line in _lines:
		_draw_arrow(line["from"], line["to"])


func _draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, LINE_COLOR, LINE_WIDTH)

	var direction: Vector2 = (to - from).normalized()
	var perpendicular: Vector2 = direction.orthogonal()
	var left: Vector2 = to - direction * ARROW_SIZE + perpendicular * ARROW_SIZE * 0.5
	var right: Vector2 = to - direction * ARROW_SIZE - perpendicular * ARROW_SIZE * 0.5
	draw_polygon(PackedVector2Array([to, left, right]), PackedColorArray([LINE_COLOR]))

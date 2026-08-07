class_name PriceGraph
extends Control

## Plots one material's price history, min/max normalised to fill the control.
##
## Serves both places the handoff asks for a line: the 56 x 20 sparkline in a
## list row (`fill_opacity` 0, thin stroke, last 14 samples) and the focus
## panel's full-width chart (filled area under a 2px line, all 26 samples).
## One control because the two differ only in numbers, not in shape.

## Fraction of the height the plot leaves empty at the top and bottom, so a
## peak or trough never sits flush against the edge.
const VERTICAL_INSET: float = 0.10

@export var line_width: float = 2.0
@export var fill_opacity: float = 0.10

var _samples: PackedFloat32Array = PackedFloat32Array()
var _color: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_series(samples: Array, color: Color) -> void:
	_samples = PackedFloat32Array(samples)
	_color = color
	queue_redraw()


func _draw() -> void:
	if _samples.size() < 2 or size.x <= 0.0 or size.y <= 0.0:
		return

	var points: PackedVector2Array = _plot_points()
	if fill_opacity > 0.0:
		var area: PackedVector2Array = points.duplicate()
		area.push_back(Vector2(size.x, size.y))
		area.push_back(Vector2(0.0, size.y))
		draw_colored_polygon(area, MarketTheme.with_alpha(_color, fill_opacity))
	# Antialiased: these are thin diagonal strokes over a dark panel, where
	# stair-stepping is the first thing that reads as unfinished.
	draw_polyline(points, _color, line_width, true)


func _plot_points() -> PackedVector2Array:
	var lowest: float = _samples[0]
	var highest: float = _samples[0]
	for value in _samples:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	var span: float = maxf(highest - lowest, 0.0001)

	var inset: float = size.y * VERTICAL_INSET
	var plot_height: float = size.y - inset * 2.0
	var step: float = size.x / float(_samples.size() - 1)

	var points: PackedVector2Array = PackedVector2Array()
	for index in _samples.size():
		var normalised: float = (_samples[index] - lowest) / span
		points.push_back(Vector2(index * step, inset + (1.0 - normalised) * plot_height))
	return points

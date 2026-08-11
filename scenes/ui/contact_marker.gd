class_name ContactMarker
extends Control

## Screen-edge pointer at something the player has been told about but cannot
## see yet — currently just the opening sequence's derelict.
##
## The contact is deliberately placed at a random bearing (see IntroDirector), so
## something has to answer "which way". A minimap would answer it too, but this
## keeps the player's eyes on the world rather than on a corner of the HUD, and
## it disappears the moment the thing is actually on screen — the point is to
## stop being needed.

## How far in from the screen edge the arrow rides.
@export var edge_inset: float = 64.0
@export var arrow_size: float = 13.0
@export var color: Color = Color(0.45, 0.85, 0.95, 0.85)
## Fades out over this distance as the target comes on screen, so it does not
## pop off at a hard threshold.
@export var fade_margin: float = 240.0

var _target: Node2D
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", color)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


func track(target: Node2D) -> void:
	_target = target
	visible = target != null


func clear_target() -> void:
	_target = null
	visible = false


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		clear_target()
		return
	queue_redraw()


func _draw() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var centre: Vector2 = viewport_size * 0.5
	# Where the target sits on screen, via the active camera's transform — this
	# works regardless of zoom, which the player controls with the scroll wheel.
	var screen_point: Vector2 = get_viewport().get_canvas_transform() * _target.global_position

	var to_target: Vector2 = screen_point - centre
	if to_target.length() < 1.0:
		return

	# Once the target is comfortably on screen the marker has done its job.
	var margin: float = edge_inset + arrow_size
	var on_screen: bool = screen_point.x > margin and screen_point.x < viewport_size.x - margin \
		and screen_point.y > margin and screen_point.y < viewport_size.y - margin
	if on_screen:
		_label.visible = false
		return

	var direction: Vector2 = to_target.normalized()
	# Clamped to the inset rectangle rather than to a circle, so the arrow slides
	# along the edge the target is actually past instead of orbiting a ring.
	var half: Vector2 = viewport_size * 0.5 - Vector2(edge_inset, edge_inset)
	var scale_x: float = half.x / maxf(absf(direction.x), 0.0001)
	var scale_y: float = half.y / maxf(absf(direction.y), 0.0001)
	var position_on_edge: Vector2 = centre + direction * minf(scale_x, scale_y)

	var distance: float = _target.global_position.distance_to(_player_position())
	var alpha: float = clampf(distance / fade_margin, 0.0, 1.0)
	var tint: Color = Color(color.r, color.g, color.b, color.a * alpha)

	var forward: Vector2 = direction * arrow_size
	var side: Vector2 = direction.orthogonal() * arrow_size * 0.55
	draw_colored_polygon(PackedVector2Array([
		position_on_edge + forward,
		position_on_edge - forward * 0.6 + side,
		position_on_edge - forward * 0.6 - side,
	]), tint)

	_label.visible = true
	_label.add_theme_color_override("font_color", tint)
	_label.text = "%d m" % roundi(distance)
	_label.position = position_on_edge - direction * (arrow_size * 2.6) - _label.size * 0.5


func _player_position() -> Vector2:
	var ship: Ship = PlayerContext.get_ship()
	return ship.global_position if ship != null else Vector2.ZERO

class_name Nebula
extends Area2D

## A big drifting gas cloud that scrambles sensors (see ship_input.gd's
## NEBULA_LOCK_RANGE_FRACTION) and tints the screen while the player is
## inside it — a "place of interest" reached without changing scenes, unlike
## the region-swapping WarpGate.GATE mode.
@export var zone_radius: float = 6000.0
@export var tint_color: Color = Color(0.55, 0.25, 0.75, 0.12)
@export var tint_fade_duration: float = 1.0

@onready var _collision: CollisionShape2D = $Zone

var _tint_layer: CanvasLayer
var _tint_rect: ColorRect
var _ships_inside: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CircleShape2D.new()
	shape.radius = zone_radius
	_collision.shape = shape


func _on_body_entered(body: Node) -> void:
	if not (body is Ship and body.is_in_group("player_ship")):
		return
	body.enter_nebula()
	_ships_inside += 1
	_show_tint()


func _on_body_exited(body: Node) -> void:
	if not (body is Ship and body.is_in_group("player_ship")):
		return
	body.exit_nebula()
	_ships_inside = maxi(_ships_inside - 1, 0)
	if _ships_inside == 0:
		_hide_tint()


func _show_tint() -> void:
	_ensure_tint_layer()
	var tween: Tween = create_tween()
	tween.tween_property(_tint_rect, "color:a", tint_color.a, tint_fade_duration)


func _hide_tint() -> void:
	if _tint_rect == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_tint_rect, "color:a", 0.0, tint_fade_duration)


func _ensure_tint_layer() -> void:
	if _tint_layer != null:
		return

	_tint_layer = CanvasLayer.new()
	_tint_rect = ColorRect.new()
	_tint_rect.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.0)
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint_layer.add_child(_tint_rect)
	get_tree().current_scene.add_child(_tint_layer)

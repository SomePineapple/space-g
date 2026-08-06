class_name StationPrompt
extends CanvasLayer

## Named so the ship builder's status line can show the same docking hint
## rather than keeping a second copy of the string.
const PROMPT_TEXT: String = "Near Corporate Station — U: Upgrades   B: Build   T: Trade"

@export var home_base_range: float = 300.0

var _ship: Ship
var _home_base: Node2D
var _label: Label


func _ready() -> void:
	_ship = PlayerContext.get_ship()

	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if not home_bases.is_empty():
		_home_base = home_bases[0]

	_build_ui()


func _build_ui() -> void:
	_label = Label.new()
	_label.text = PROMPT_TEXT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-260, -60)
	_label.size = Vector2(520, 24)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	if _ship == null or _home_base == null:
		return
	_label.visible = _ship.global_position.distance_to(_home_base.global_position) <= home_base_range

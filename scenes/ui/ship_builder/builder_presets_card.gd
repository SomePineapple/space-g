class_name BuilderPresetsCard
extends PanelContainer

## Collapsible "LOAD FROM PRESET" card on the ship-builder screen. The presets
## are the player's own saved ship layouts (user://ships) — ShipBuilderPanel
## supplies the names and does the loading.

signal preset_selected(preset_name: String)

const LIST_MAX_HEIGHT: float = 150.0
const CHEVRON_TWEEN_SECONDS: float = 0.15

var _body: VBoxContainer
var _chevron: Chevron
var _list: VBoxContainer
var _expanded: bool = false


## Small downward triangle. Drawn rather than typed as a glyph so it can't
## fall back to a missing-character box in whatever font the OS supplies.
class Chevron extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(8, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = Vector2(4, 2.5)

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 0), Vector2(8, 0), Vector2(4, 5),
		]), BuilderTheme.TEXT_LABEL)


func _ready() -> void:
	add_theme_stylebox_override("panel", BuilderTheme.card_style())
	clip_contents = true

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	column.add_child(_build_header())

	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 0)
	column.add_child(_body)

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.add_theme_stylebox_override("panel",
		BuilderTheme.flat_style(BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.15), Color.TRANSPARENT, 0))
	_body.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_MAX_HEIGHT)
	_body.add_child(scroll)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 6)
	padding.add_theme_constant_override("margin_right", 6)
	padding.add_theme_constant_override("margin_top", 6)
	padding.add_theme_constant_override("margin_bottom", 6)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(padding)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	padding.add_child(_list)


func _build_header() -> PanelContainer:
	var header := PanelContainer.new()
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.add_theme_stylebox_override("panel",
		BuilderTheme.padded(BuilderTheme.flat_style(Color.TRANSPARENT), 16.0, 12.0))
	header.gui_input.connect(_on_header_input)

	var row := HBoxContainer.new()
	header.add_child(row)

	var title: Label = BuilderTheme.mono_label("LOAD FROM PRESET", 12, BuilderTheme.TEXT_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_chevron = Chevron.new()
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chevron)
	return header


func set_presets(preset_names: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	for preset_name in preset_names:
		_list.add_child(_build_row(preset_name))


func _build_row(preset_name: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", _row_style(true)))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", _row_style(false)))
	row.gui_input.connect(_on_row_input.bind(preset_name))

	var line := HBoxContainer.new()
	row.add_child(line)

	var name_label: Label = BuilderTheme.mono_label(preset_name, 12, BuilderTheme.TEXT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	line.add_child(name_label)

	line.add_child(BuilderTheme.mono_label("LOAD", 11, BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.7)))
	return row


func _row_style(hovered: bool) -> StyleBoxFlat:
	var fill: Color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.1) if hovered else Color.TRANSPARENT
	return BuilderTheme.padded(BuilderTheme.flat_style(fill), 10.0, 8.0)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_expanded = not _expanded
		_body.visible = _expanded
		var tween: Tween = create_tween()
		tween.tween_property(_chevron, "rotation", PI if _expanded else 0.0, CHEVRON_TWEEN_SECONDS)


func _on_row_input(event: InputEvent, preset_name: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		preset_selected.emit(preset_name)

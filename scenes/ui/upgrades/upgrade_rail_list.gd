class_name UpgradeRailList
extends ScrollContainer

## The upgrade screen's left-rail category list
## (docs/design_handoff_upgrade_tree/README.md "Category list"). One row per
## ship system; picking one swaps the tree in the main column.

signal category_selected(category_index: int)

const ROW_PADDING_HORIZONTAL: float = 22.0
const ROW_PADDING_VERTICAL: float = 13.0
const ACTIVE_BORDER_WIDTH: int = 3
const LABEL_FONT_SIZE: int = 15
const PROGRESS_FONT_SIZE: int = 11

var _column: VBoxContainer
## Row index -> its PanelContainer.
var _rows: Dictionary = {}
var _categories: Array = []
var _selected: int = -1


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 0)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)


## categories: Array of {"label", "hue", "unlocked": int, "total": int}.
func set_categories(categories: Array) -> void:
	_categories = categories
	_rows.clear()
	for child in _column.get_children():
		child.queue_free()
	for index in categories.size():
		var row: PanelContainer = _build_row(index, categories[index])
		_rows[index] = row
		_column.add_child(row)
	for index in _rows:
		_paint(index, false)


func set_selected(index: int) -> void:
	_selected = index
	for row_index in _rows:
		_paint(row_index, false)


## In-place progress refresh after an unlock — avoids rebuilding every row
## just to change one "3/11".
func update_progress(index: int, unlocked: int) -> void:
	if not _rows.has(index):
		return
	_categories[index]["unlocked"] = unlocked
	_rows[index].get_meta("progress").text = "%d/%d" % [unlocked, _categories[index]["total"]]


func _build_row(index: int, category: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): _paint(index, true))
	row.mouse_exited.connect(func(): _paint(index, false))
	row.gui_input.connect(_on_row_input.bind(index))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)

	var label: Label = BuilderTheme.sans_label(category["label"], LABEL_FONT_SIZE, BuilderTheme.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)

	var progress: Label = BuilderTheme.mono_label(
		"%d/%d" % [category["unlocked"], category["total"]], PROGRESS_FONT_SIZE, BuilderTheme.TEXT_HINT)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(progress)

	row.set_meta("label", label)
	row.set_meta("progress", progress)
	return row


func _paint(index: int, hovered: bool) -> void:
	if not _rows.has(index):
		return
	var row: PanelContainer = _rows[index]
	var accent: Color = UpgradePalette.bright(_categories[index]["hue"])
	var active: bool = index == _selected

	var fill: Color = Color.TRANSPARENT
	if active:
		fill = BuilderTheme.with_alpha(accent, 0.14)
	elif hovered:
		fill = Color(1, 1, 1, 0.04)

	var style: StyleBoxFlat = BuilderTheme.padded(
		BuilderTheme.flat_style(fill, Color.TRANSPARENT, 0), ROW_PADDING_HORIZONTAL, ROW_PADDING_VERTICAL)
	# The inactive left border is transparent rather than absent so selecting a
	# row does not nudge its text sideways.
	style.border_width_left = ACTIVE_BORDER_WIDTH
	style.border_color = accent if active else Color.TRANSPARENT
	style.content_margin_left = ROW_PADDING_HORIZONTAL
	row.add_theme_stylebox_override("panel", style)

	row.get_meta("label").add_theme_color_override("font_color",
		BuilderTheme.TEXT_SELECTED if active else BuilderTheme.TEXT_MUTED)
	row.get_meta("progress").add_theme_color_override("font_color",
		accent if active else BuilderTheme.TEXT_HINT)


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		category_selected.emit(index)

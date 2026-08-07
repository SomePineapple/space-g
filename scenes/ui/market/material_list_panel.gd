class_name MaterialListPanel
extends PanelContainer

## The Exchange's left column: category tabs, a column header, a scrolling
## list of MaterialRows and a count footer
## (docs/design_handoff_trade_market/README.md "Left column").
##
## Category tabs are built from MaterialCatalog.categories(), never a
## hard-coded list, and filtering only hides rows — the selection persists
## even when the selected material is filtered out of view.

signal material_selected(material_id: String)

const ALL_CATEGORY: String = "All"
const TABS_PADDING: int = 12
const HEADER_COLUMNS: Array[String] = ["MATERIAL", "PRICE", "24H", "TREND"]

var _tab_strip: HFlowContainer
var _row_container: VBoxContainer
var _footer: Label
var _rows: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _category: String = ALL_CATEGORY
var _selected_id: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(MarketTheme.LIST_WIDTH, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel", MarketTheme.panel(MarketTheme.PANEL_ALPHA_LIST))
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	column.add_child(_build_tabs())
	column.add_child(_build_header())
	column.add_child(_build_scroll())
	column.add_child(_build_footer())


func _build_tabs() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", TABS_PADDING)
	margin.add_theme_constant_override("margin_right", TABS_PADDING)
	margin.add_theme_constant_override("margin_top", TABS_PADDING)
	margin.add_theme_constant_override("margin_bottom", 10)

	# HFlowContainer so a sixth category wraps to a second line instead of
	# squeezing the others — the handoff's tab strip wraps.
	_tab_strip = HFlowContainer.new()
	_tab_strip.add_theme_constant_override("h_separation", 6)
	_tab_strip.add_theme_constant_override("v_separation", 6)
	margin.add_child(_tab_strip)
	return margin


func _build_header() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MaterialRow.HORIZONTAL_PADDING)
	margin.add_theme_constant_override("margin_right", MaterialRow.HORIZONTAL_PADDING)
	margin.add_theme_constant_override("margin_bottom", 8)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for index in HEADER_COLUMNS.size():
		var label: Label = MarketTheme.mono_label(HEADER_COLUMNS[index],
			MarketTheme.SIZE_HEADER_CELL, MarketTheme.TEXT_FAINT, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = MaterialRow.COLUMN_RATIOS[index]
		if index == HEADER_COLUMNS.size() - 1:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	margin.add_child(row)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.add_child(margin)
	wrapper.add_child(_hairline(MarketTheme.BORDER))
	return wrapper


func _build_scroll() -> Control:
	var scroll: ScrollContainer = MarketTheme.make_scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_row_container = VBoxContainer.new()
	_row_container.add_theme_constant_override("separation", 0)
	_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_row_container)
	return scroll


func _build_footer() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.add_child(_hairline(MarketTheme.BORDER))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MaterialRow.HORIZONTAL_PADDING)
	margin.add_theme_constant_override("margin_right", MaterialRow.HORIZONTAL_PADDING)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_footer = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL)
	margin.add_child(_footer)
	wrapper.add_child(margin)
	return wrapper


func _hairline(color: Color) -> Panel:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_stylebox_override("panel", MarketTheme.flat_style(color))
	return line


# --- Population -------------------------------------------------------------

## Builds one row per material and one tab per category. Called once: the
## catalog is static within a session, so only the values inside rows change.
func populate(material_ids: Array) -> void:
	for material_id in material_ids:
		var row := MaterialRow.new(material_id)
		row.selected.connect(_on_row_selected)
		_row_container.add_child(row)
		_rows[material_id] = row
	_build_tab_buttons(material_ids)
	_apply_filter()


func _build_tab_buttons(material_ids: Array) -> void:
	var categories: Array = [ALL_CATEGORY]
	categories.append_array(MaterialCatalog.categories())
	for category in categories:
		var count: int = material_ids.size()
		if category != ALL_CATEGORY:
			count = 0
			for material_id in material_ids:
				if MaterialCatalog.category(material_id) == category:
					count += 1
		var button := Button.new()
		button.text = "%s (%d)" % [category, count]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_tab_pressed.bind(category))
		_tab_strip.add_child(button)
		_tab_buttons[category] = button
	_restyle_tabs()


func _restyle_tabs() -> void:
	for category in _tab_buttons:
		var selected: bool = category == _category
		MarketTheme.style_button(_tab_buttons[category],
			MarketTheme.CYAN if selected else Color(1, 1, 1, 0.04),
			Color.TRANSPARENT,
			MarketTheme.SCREEN_BG if selected else MarketTheme.TEXT_SUBTLE,
			MarketTheme.SIZE_LABEL, 11, 6)


func _on_tab_pressed(category: String) -> void:
	if _category == category:
		return
	_category = category
	_restyle_tabs()
	_apply_filter()


func _apply_filter() -> void:
	var shown: int = 0
	for material_id in _rows:
		var visible_row: bool = _category == ALL_CATEGORY \
			or MaterialCatalog.category(material_id) == _category
		_rows[material_id].visible = visible_row
		if visible_row:
			shown += 1
	_footer.text = "%d of %d commodities" % [shown, _rows.size()]


func _on_row_selected(material_id: String) -> void:
	material_selected.emit(material_id)


# --- Live state -------------------------------------------------------------

func set_selected(material_id: String) -> void:
	if _selected_id == material_id:
		return
	if _rows.has(_selected_id):
		_rows[_selected_id].set_selected(false)
	_selected_id = material_id
	if _rows.has(material_id):
		_rows[material_id].set_selected(true)


## `held_totals` is the player's cargo map, so the "50u" pills stay current
## between market ticks as well as on them.
func refresh(held_totals: Dictionary) -> void:
	for material_id in _rows:
		var history: Array = MarketService.get_history(material_id)
		var recent: Array = history.slice(maxi(0, history.size() - MarketService.SPARK_SAMPLES))
		_rows[material_id].refresh(held_totals.get(material_id, 0), recent)

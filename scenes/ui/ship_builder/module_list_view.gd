class_name ModuleListView
extends PanelContainer

## The ship builder's "PARTS" card: filter tabs, category-grouped rows, and the
## expansion strip under the selected row.
##
## One row is one *part*, not one module type. Nothing stacks and nothing shows
## a count — two Hull Spars are two rows, because they are two objects with
## different serials, different wear and different histories, and which one you
## bolt on is a real choice. Rows are grouped by category and sorted by type
## within it, so all the spars still sit together.
##
## Owns presentation only. It never reads Inventory or ModuleCatalog itself —
## ShipBuilderPanel supplies the hold via set_parts().

## Empty id means the selection was toggled off.
signal module_selected(instance_id: String)

const ROW_SEPARATION: int = 7
const GROUP_SEPARATION: int = 14
const ROW_PADDING_H: float = 12.0
const ROW_PADDING_V: float = 9.0

var faction_id: String = "corporate"

## instance_id -> {"instance": ModuleInstance, "module_type": ModuleType,
## "category": String}
var _entries: Dictionary = {}
## instance_id -> {"root","panel","icon","name","strip","detail","origin"}
var _rows: Dictionary = {}
var _tab_buttons: Dictionary = {}

var _active_tab: String = ModulePresentation.TAB_ALL
var _selected_key: String = ""

var _list: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", BuilderTheme.card_style())
	_build_chrome()


func _build_chrome() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 16)
	header.add_theme_constant_override("margin_right", 16)
	header.add_theme_constant_override("margin_top", 14)
	header.add_theme_constant_override("margin_bottom", 10)
	column.add_child(header)

	var header_column := VBoxContainer.new()
	header_column.add_theme_constant_override("separation", 10)
	header.add_child(header_column)

	var title: Label = BuilderTheme.mono_label("PARTS", 13, BuilderTheme.TEXT_BRIGHT)
	header_column.add_child(title)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	header_column.add_child(tabs)
	for tab_name in ModulePresentation.FILTER_TABS:
		var tab := Button.new()
		tab.text = tab_name
		tab.focus_mode = Control.FOCUS_NONE
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.pressed.connect(_on_tab_pressed.bind(tab_name))
		tabs.add_child(tab)
		_tab_buttons[tab_name] = tab

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.add_theme_stylebox_override("panel",
		BuilderTheme.flat_style(BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.15), Color.TRANSPARENT, 0))
	column.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 10)
	padding.add_theme_constant_override("margin_right", 10)
	padding.add_theme_constant_override("margin_top", 10)
	padding.add_theme_constant_override("margin_bottom", 10)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(padding)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", GROUP_SEPARATION)
	padding.add_child(_list)

	_refresh_tab_styles()


# --- Data -------------------------------------------------------------------

## parts: Array[ModuleInstance] — the whole hold. Rebuilds every row, since with
## no counts to update there is no cheaper partial refresh to make.
func set_parts(parts: Array) -> void:
	_entries.clear()
	_rows.clear()
	for child in _list.get_children():
		child.queue_free()

	var by_category: Dictionary = {}
	for part: ModuleInstance in parts:
		var module_type: ModuleType = ModuleCatalog.get_by_id(part.module_type_id)
		if module_type == null:
			continue
		var category: String = ModulePresentation.category(module_type)
		_entries[part.instance_id] = {
			"instance": part,
			"module_type": module_type,
			"category": category,
		}
		by_category.get_or_add(category, []).append(part.instance_id)

	for category in ModulePresentation.CATEGORY_ORDER:
		if not by_category.has(category):
			continue
		var ids: Array = by_category[category]
		ids.sort_custom(_compare_parts)
		_list.add_child(_build_group(category, ids))

	_apply_filter()


## Sorted by part type first so every Hull Spar sits with every other Hull Spar,
## then by serial so the order is stable and a given part stays where the player
## last saw it.
func _compare_parts(a_id: String, b_id: String) -> bool:
	var a: Dictionary = _entries[a_id]
	var b: Dictionary = _entries[b_id]
	if a["module_type"].display_name != b["module_type"].display_name:
		return a["module_type"].display_name < b["module_type"].display_name
	return a["instance"].serial < b["instance"].serial


func set_selected_key(key: String) -> void:
	if _selected_key == key:
		return
	var previous: String = _selected_key
	_selected_key = key
	if _rows.has(previous):
		_apply_selection(previous)
	if _rows.has(key):
		_apply_selection(key)


# --- Row construction -------------------------------------------------------

func _build_group(category: String, keys: Array) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", ROW_SEPARATION)

	var heading: Label = BuilderTheme.mono_label(category.to_upper(), 11, BuilderTheme.TEXT_HINT)
	group.add_child(heading)

	for key in keys:
		group.add_child(_build_row(key))
	return group


func _build_row(key: String) -> Control:
	var entry: Dictionary = _entries[key]
	var instance: ModuleInstance = entry["instance"]

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var panel := PanelContainer.new()
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_row_gui_input.bind(key))
	panel.mouse_entered.connect(_on_row_hover.bind(key, true))
	panel.mouse_exited.connect(_on_row_hover.bind(key, false))
	root.add_child(panel)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 11)
	panel.add_child(line)

	var icon := ModuleHexIcon.new()
	icon.configure(entry["module_type"], faction_id)
	line.add_child(icon)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 1)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text_column)

	var name_label: Label = BuilderTheme.sans_label(instance.display_name(), 13, BuilderTheme.TEXT_BODY)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(name_label)

	# Serial and condition sit on the collapsed row, not in the expansion strip:
	# they are how the player tells two otherwise identical parts apart, so
	# needing to click each one to find out would defeat the point.
	var detail_label: Label = BuilderTheme.mono_label(_detail_text(instance), 10, BuilderTheme.TEXT_MUTED_DIM)
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(detail_label)

	var strip := PanelContainer.new()
	strip.visible = false
	strip.add_theme_stylebox_override("panel", _strip_style())
	root.add_child(strip)

	var strip_column := VBoxContainer.new()
	strip_column.add_theme_constant_override("separation", 3)
	strip.add_child(strip_column)

	var origin_label: Label = BuilderTheme.mono_label(_origin_text(instance), 11, BuilderTheme.TEXT_MUTED_DIM)
	origin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strip_column.add_child(origin_label)

	_rows[key] = {
		"root": root, "panel": panel, "icon": icon, "name": name_label,
		"strip": strip, "detail": detail_label, "origin": origin_label, "hovered": false,
	}
	_apply_selection(key)
	return root


func _detail_text(instance: ModuleInstance) -> String:
	var text: String = "%s · %d%%" % [instance.serial, roundi(instance.condition_fraction * 100.0)]
	if instance.kill_count > 0:
		text += " · %d kills" % instance.kill_count
	return text


func _origin_text(instance: ModuleInstance) -> String:
	return instance.origin_description if instance.is_salvaged() else "Fabricated — no combat history"


func _strip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.06)
	style.border_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.2)
	style.set_border_width_all(1)
	style.border_width_top = 0
	style.corner_radius_bottom_left = BuilderTheme.RADIUS_MEDIUM
	style.corner_radius_bottom_right = BuilderTheme.RADIUS_MEDIUM
	return BuilderTheme.padded(style, 12.0, 8.0)


# --- State ------------------------------------------------------------------

func _apply_selection(key: String) -> void:
	var row: Dictionary = _rows[key]
	var is_selected: bool = key == _selected_key
	row["icon"].set_selected(is_selected)
	row["strip"].visible = is_selected
	row["name"].add_theme_color_override("font_color",
		BuilderTheme.TEXT_SELECTED if is_selected else BuilderTheme.TEXT_BODY)
	row["panel"].add_theme_stylebox_override("panel", _row_style(is_selected, row["hovered"]))


func _row_style(is_selected: bool, is_hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(BuilderTheme.RADIUS_MEDIUM)
	if is_selected:
		style.bg_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.16)
		style.border_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.85)
		style.set_border_width_all(2)
		style.shadow_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.18)
		style.shadow_size = 8
	else:
		style.bg_color = Color(1, 1, 1, 0.06 if is_hovered else 0.02)
		style.border_color = Color(1, 1, 1, 0.06)
		style.set_border_width_all(1)
	return BuilderTheme.padded(style, ROW_PADDING_H, ROW_PADDING_V)


# --- Filtering --------------------------------------------------------------

func _apply_filter() -> void:
	for key in _rows:
		_rows[key]["root"].visible = _passes_filter(key)

	# Hide a category heading whose rows are all filtered out.
	for group in _list.get_children():
		var any_visible: bool = false
		for child in group.get_children():
			if child is VBoxContainer and child.visible:
				any_visible = true
				break
		group.visible = any_visible


func _passes_filter(key: String) -> bool:
	if _active_tab == ModulePresentation.TAB_ALL:
		return true
	return _entries[key]["category"] == _active_tab


func _refresh_tab_styles() -> void:
	for tab_name in _tab_buttons:
		var tab: Button = _tab_buttons[tab_name]
		var is_active: bool = tab_name == _active_tab
		tab.add_theme_font_override("font", BuilderTheme.mono_font())
		# 10px rather than the handoff's 10.5: at 10.5 the five tabs wrap onto
		# a second row inside the 336px panel.
		tab.add_theme_font_size_override("font_size", 10)
		var fill: Color = BuilderTheme.CYAN if is_active else Color(1, 1, 1, 0.03)
		var border: Color = BuilderTheme.CYAN if is_active else Color(1, 1, 1, 0.08)
		var text_color: Color = BuilderTheme.BG_BASE if is_active else BuilderTheme.TEXT_MUTED_DIM
		for state_name in ["normal", "hover", "pressed", "focus"]:
			tab.add_theme_stylebox_override(state_name,
				BuilderTheme.padded(BuilderTheme.flat_style(fill, border, BuilderTheme.RADIUS_SMALL), 8.0, 5.0))
		tab.add_theme_color_override("font_color", text_color)
		tab.add_theme_color_override("font_hover_color",
			text_color if is_active else BuilderTheme.TEXT_BRIGHT)
		tab.add_theme_color_override("font_pressed_color", text_color)


# --- Input ------------------------------------------------------------------

func _on_tab_pressed(tab_name: String) -> void:
	_active_tab = tab_name
	_refresh_tab_styles()
	_apply_filter()


func _on_row_hover(key: String, hovered: bool) -> void:
	_rows[key]["hovered"] = hovered
	_apply_selection(key)


func _on_row_gui_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		module_selected.emit("" if key == _selected_key else key)

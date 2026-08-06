class_name ModuleListView
extends PanelContainer

## The ship builder's "MODULES" card: filter tabs, category-grouped module
## rows, and the expansion strip under the selected row.
##
## Owns presentation only. It never reads Inventory or ModuleCatalog itself —
## ShipBuilderPanel supplies the rows via set_entries() and their live
## owned/locked/affordable state via update_states(), so the same list can
## show manufacturer-flavoured variants without this file knowing what a
## manufacturer is.

## Empty key means the selection was toggled off.
signal module_selected(key: String)
signal craft_pressed(key: String)
signal research_pressed(module_type_id: String)
signal repair_pressed(module_type_id: String)

const ROW_SEPARATION: int = 7
const GROUP_SEPARATION: int = 14
const ROW_PADDING_H: float = 12.0
const ROW_PADDING_V: float = 9.0

var faction_id: String = "corporate"

## key -> {"module_type": ModuleType, "display_name": String, "category": String}
var _entries: Dictionary = {}
## key -> state Dictionary, as passed to update_states().
var _states: Dictionary = {}
## key -> {"root","panel","icon","name","craft","strip","cost","owned","research","repair"}
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

	var title: Label = BuilderTheme.mono_label("MODULES", 13, BuilderTheme.TEXT_BRIGHT)
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

## entries: Array of {"key", "module_type", "display_name"}. Rebuilds every
## row, so only call it when the set of modules itself changes.
func set_entries(entries: Array) -> void:
	_entries.clear()
	_rows.clear()
	for child in _list.get_children():
		child.queue_free()

	var by_category: Dictionary = {}
	for entry in entries:
		var module_type: ModuleType = entry["module_type"]
		var category: String = ModulePresentation.category(module_type)
		_entries[entry["key"]] = {
			"module_type": module_type,
			"display_name": entry["display_name"],
			"category": category,
		}
		by_category.get_or_add(category, []).append(entry["key"])

	for category in ModulePresentation.CATEGORY_ORDER:
		if not by_category.has(category):
			continue
		_list.add_child(_build_group(category, by_category[category]))

	_apply_filter()


## states: key -> {"owned": int, "locked": bool, "can_afford": bool,
## "cost_text": String, "research_text": String, "can_research": bool,
## "repair_text": String, "can_repair": bool}. Research/repair text being
## empty hides that button.
func update_states(states: Dictionary) -> void:
	_states = states
	for key in _rows:
		_apply_state(key)
	_apply_filter()


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
	icon.configure(entry["module_type"], faction_id, 0)
	line.add_child(icon)

	var name_label: Label = BuilderTheme.sans_label(entry["display_name"], 13, BuilderTheme.TEXT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	var craft := Button.new()
	craft.text = "CRAFT"
	craft.focus_mode = Control.FOCUS_NONE
	craft.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BuilderTheme.style_button(craft, BuilderTheme.CYAN, BuilderTheme.CYAN_BRIGHT,
		BuilderTheme.TEXT_BRIGHT, 11, 12.0, 6.0)
	craft.pressed.connect(_on_craft_pressed.bind(key))
	line.add_child(craft)

	var strip := PanelContainer.new()
	strip.visible = false
	strip.add_theme_stylebox_override("panel", _strip_style())
	root.add_child(strip)

	var strip_column := VBoxContainer.new()
	strip_column.add_theme_constant_override("separation", 3)
	strip.add_child(strip_column)

	var cost_label: Label = BuilderTheme.mono_label("COST · ", 11, BuilderTheme.TEXT_MUTED_DIM)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strip_column.add_child(cost_label)

	var owned_label: Label = BuilderTheme.mono_label("OWNED · 0", 11, BuilderTheme.TEXT_MUTED_DIM)
	strip_column.add_child(owned_label)

	# Research and Repair have no place in the visual reference; they live in
	# the expansion strip so the collapsed list stays as designed.
	var research := _make_strip_button(BuilderTheme.CYAN)
	research.pressed.connect(_on_research_pressed.bind(key))
	strip_column.add_child(research)

	var repair := _make_strip_button(BuilderTheme.AMBER)
	repair.pressed.connect(_on_repair_pressed.bind(key))
	strip_column.add_child(repair)

	_rows[key] = {
		"root": root, "panel": panel, "icon": icon, "name": name_label, "craft": craft,
		"strip": strip, "cost": cost_label, "owned": owned_label,
		"research": research, "repair": repair, "hovered": false,
	}
	_apply_selection(key)
	return root


func _make_strip_button(tint: Color) -> Button:
	var button := Button.new()
	button.visible = false
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BuilderTheme.style_button(button, tint, BuilderTheme.CYAN_BRIGHT, BuilderTheme.TEXT_BRIGHT,
		11, 10.0, 6.0)
	return button


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

func _apply_state(key: String) -> void:
	var row: Dictionary = _rows[key]
	var state: Dictionary = _states.get(key, {})
	var owned: int = state.get("owned", 0)
	var locked: bool = state.get("locked", false)

	row["icon"].configure(_entries[key]["module_type"], faction_id, owned)
	row["name"].text = ("%s [LOCKED]" % _entries[key]["display_name"]) if locked else _entries[key]["display_name"]
	row["craft"].disabled = locked or not state.get("can_afford", false)
	row["cost"].text = "COST · %s" % state.get("cost_text", "—")
	row["owned"].text = "OWNED · %d" % owned

	var research_text: String = state.get("research_text", "")
	row["research"].visible = not research_text.is_empty()
	row["research"].text = research_text
	row["research"].disabled = not state.get("can_research", false)

	var repair_text: String = state.get("repair_text", "")
	row["repair"].visible = not repair_text.is_empty()
	row["repair"].text = repair_text
	row["repair"].disabled = not state.get("can_repair", false)


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
	if _active_tab == ModulePresentation.TAB_OWNED:
		return _states.get(key, {}).get("owned", 0) > 0
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


func _on_craft_pressed(key: String) -> void:
	craft_pressed.emit(key)


func _on_research_pressed(key: String) -> void:
	research_pressed.emit(_entries[key]["module_type"].id)


func _on_repair_pressed(key: String) -> void:
	repair_pressed.emit(_entries[key]["module_type"].id)

extends Control

## Top-left power-management list: every ship system, its switch state and what
## it's costing per second. Sits directly under the vitals readout, which shows
## the total of this list as its load bar.
##
## Essential systems (control, thrusters) are listed too, without a key hint —
## seeing that simply being ready to fly costs power is the point of showing
## them, and they deliberately can't be switched off.
##
## Built in code like the other HUD widgets, and driven entirely by
## ShipSystems.systems_changed — nothing here polls per frame.

const PANEL_WIDTH: float = 214.0
const GAP_BELOW_VITALS: float = 74.0
const FONT_SIZE: int = 12
const KEY_COLUMN_WIDTH: float = 16.0
const STATE_COLUMN_WIDTH: float = 30.0
const DRAW_COLUMN_WIDTH: float = 46.0
const ROW_SEPARATION: int = 3

var _systems: ShipSystems
## system id -> [key label, name label, state label, draw label]
var _rows: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = HudPalette.CORNER_MARGIN
	offset_top = HudPalette.CORNER_MARGIN + GAP_BELOW_VITALS
	offset_right = HudPalette.CORNER_MARGIN + PANEL_WIDTH

	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return
	_systems = ship.get_systems()
	_build()
	_systems.systems_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_stylebox())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)

	rows.add_child(_make_heading())
	for system_id in ShipSystems.ORDER:
		rows.add_child(_make_row(system_id))


func _make_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HudPalette.with_alpha(HudPalette.PANEL_FILL, 0.55)
	style.border_color = HudPalette.with_alpha(HudPalette.CYAN, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _make_heading() -> Control:
	var label := _make_label("SYSTEMS", 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", HudPalette.CYAN)
	return label


func _make_row(system_id: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key_label: Label = _make_label(ShipSystems.HOTKEY_HINTS.get(system_id, ""), KEY_COLUMN_WIDTH)
	var name_label: Label = _make_label(ShipSystems.DISPLAY_NAMES[system_id], 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state_label: Label = _make_label("", STATE_COLUMN_WIDTH)
	var draw_label: Label = _make_label("", DRAW_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_RIGHT)

	row.add_child(key_label)
	row.add_child(name_label)
	row.add_child(state_label)
	row.add_child(draw_label)
	_rows[system_id] = [key_label, name_label, state_label, draw_label]
	return row


func _make_label(text: String, min_width: float,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0.0)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", HudPalette.LIST_NAME)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _refresh() -> void:
	for system_id in _rows:
		var labels: Array = _rows[system_id]
		var available: bool = _systems.is_available(system_id)
		var on: bool = _systems.is_switched_on(system_id)

		# A system the ship has no module for reads as absent rather than off:
		# "OFF" would imply a switch that would do something.
		var state_text: String = ("ON" if on else "OFF") if available else "--"
		labels[2].text = state_text
		labels[3].text = ("%.1f/s" % _systems.get_idle_draw(system_id)) if (available and on) else ""

		var color: Color = HudPalette.CYAN if (available and on) else HudPalette.TEXT_DIM
		if not available:
			color = HudPalette.with_alpha(HudPalette.TEXT_DIM, 0.5)
		for label in labels:
			label.add_theme_color_override("font_color", color)
		# Key hint stays dim even on an active system so the state column, not
		# the hint, is what reads as "on".
		labels[0].add_theme_color_override("font_color", HudPalette.with_alpha(color, 0.7))

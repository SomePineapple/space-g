extends Control

## Bottom-left cargo chip with a dropdown material list
## (docs/HUD-1d-Godot-spec.md §2).
##
## The chip is always visible and shows used/capacity; clicking it toggles a
## panel that grows *upward* from the chip's top edge. Built in code to match
## RadarDisplay/ScannerDisplay, and because the dropdown has to be re-measured
## and re-positioned every time its contents change.
##
## Backdrop is the spec's flat tinted-glass fallback: Godot has no CSS
## backdrop-filter, and a real blur needs a BackBufferCopy plus a shader.
## Deliberately not done — see the doc's note that blur is optional polish.

const DROPDOWN_WIDTH: float = 190.0
const DROPDOWN_GAP: float = 8.0
const ROW_GAP: int = 6
const ROW_DOT_SIZE: float = 8.0
const CHIP_ICON_SIZE: float = 11.0
const FONT_SIZE: int = 13
const CHEVRON_SIZE: Vector2 = Vector2(9.0, 6.0)
const CHEVRON_FLIP_DURATION: float = 0.12

var _inventory: Inventory
var _open: bool = false

var _chip: PanelContainer
var _chip_label: Label
var _chevron: Control
var _chevron_tween: Tween
var _dropdown: PanelContainer
var _rows: VBoxContainer
## material_id -> qty Label, so a refresh rewrites text instead of rebuilding
## the row nodes on every pickup.
var _quantity_labels: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_chip()
	_build_dropdown()
	_layout()

	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return
	_inventory = ship.get_inventory()
	_inventory.materials_changed.connect(_on_materials_changed)
	_inventory.cargo_capacity_changed.connect(_on_capacity_changed)
	_refresh()


func _build_chip() -> void:
	_chip = PanelContainer.new()
	_chip.add_theme_stylebox_override("panel", _make_stylebox(
		HudPalette.with_alpha(HudPalette.PANEL_FILL, 0.55),
		HudPalette.with_alpha(HudPalette.CYAN, 0.3),
		Vector2(10.0, 6.0)))
	_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_chip.gui_input.connect(_on_chip_gui_input)
	add_child(_chip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_chip.add_child(row)

	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(CHIP_ICON_SIZE, CHIP_ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_stylebox_override("panel", _make_stylebox(
		HudPalette.with_alpha(HudPalette.CYAN, 0.15),
		HudPalette.with_alpha(HudPalette.CYAN, 0.45),
		Vector2.ZERO))
	row.add_child(icon)

	_chip_label = _make_label("0/0", HudPalette.TEXT)
	row.add_child(_chip_label)

	_chevron = Control.new()
	_chevron.custom_minimum_size = CHEVRON_SIZE
	_chevron.pivot_offset = CHEVRON_SIZE * 0.5
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.draw.connect(_draw_chevron)
	row.add_child(_chevron)


func _build_dropdown() -> void:
	_dropdown = PanelContainer.new()
	_dropdown.add_theme_stylebox_override("panel", _make_stylebox(
		HudPalette.with_alpha(HudPalette.GLASS_FILL, 0.4),
		HudPalette.with_alpha(HudPalette.CYAN, 0.18),
		Vector2(10.0, 8.0)))
	_dropdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dropdown.visible = false
	add_child(_dropdown)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_dropdown.add_child(_rows)

	for material_id in MaterialCatalog.ALL_IDS:
		_rows.add_child(_make_material_row(material_id))


func _make_material_row(material_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var dot := Control.new()
	dot.custom_minimum_size = Vector2(ROW_DOT_SIZE, ROW_DOT_SIZE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.draw.connect(_draw_material_dot.bind(dot, material_id))
	row.add_child(dot)

	var name_label := _make_label(MaterialCatalog.display_name(material_id), HudPalette.LIST_NAME)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var quantity_label := _make_label("0", HudPalette.LIST_QTY)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(quantity_label)
	_quantity_labels[material_id] = quantity_label

	return row


## Anchor the whole widget to the bottom-left corner, sized to the chip. The
## dropdown then hangs off negative Y from there, which is how it "grows
## upward" without any anchor gymnastics.
func _layout() -> void:
	var chip_size: Vector2 = _chip.get_combined_minimum_size()
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = HudPalette.CORNER_MARGIN
	offset_right = HudPalette.CORNER_MARGIN + chip_size.x
	offset_bottom = -HudPalette.CORNER_MARGIN
	offset_top = -HudPalette.CORNER_MARGIN - chip_size.y

	_chip.position = Vector2.ZERO
	_chip.size = chip_size
	_position_dropdown()


func _position_dropdown() -> void:
	var height: float = _dropdown.get_combined_minimum_size().y
	_dropdown.size = Vector2(DROPDOWN_WIDTH, height)
	_dropdown.position = Vector2(0.0, -height - DROPDOWN_GAP)


func _on_chip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_set_open(not _open)
			accept_event()


func _set_open(open: bool) -> void:
	_open = open
	_dropdown.visible = open
	if _chevron_tween:
		_chevron_tween.kill()
	_chevron_tween = create_tween()
	_chevron_tween.tween_property(_chevron, "rotation", PI if open else 0.0, CHEVRON_FLIP_DURATION)


func _on_materials_changed(_totals: Dictionary) -> void:
	_refresh()


func _on_capacity_changed(_capacity: float) -> void:
	_refresh()


func _refresh() -> void:
	if _inventory == null:
		return
	_chip_label.text = "%s/%s" % [
		HudPalette.group_digits(_inventory.get_cargo_used()),
		HudPalette.group_digits(int(_inventory.get_cargo_capacity())),
	]
	for material_id in MaterialCatalog.ALL_IDS:
		var label: Label = _quantity_labels.get(material_id)
		if label != null:
			label.text = str(_inventory.get_material_amount(material_id))
	_layout()


func _draw_chevron() -> void:
	var points := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(CHEVRON_SIZE.x, 0.0),
		Vector2(CHEVRON_SIZE.x * 0.5, CHEVRON_SIZE.y),
	])
	_chevron.draw_colored_polygon(points, HudPalette.with_alpha(HudPalette.CYAN, 0.8))


func _draw_material_dot(dot: Control, material_id: String) -> void:
	var radius: float = ROW_DOT_SIZE * 0.5
	dot.draw_circle(Vector2(radius, radius), radius, MaterialCatalog.color(material_id))


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _make_stylebox(fill: Color, border: Color, padding: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = padding.x
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	return box

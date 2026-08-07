class_name MaterialRow
extends Control

## One 52px row of the Exchange's commodity list: colour chip, name over
## category, an optional "held" pill, price, 24h delta and a sparkline
## (docs/design_handoff_trade_market/README.md "Left column").
##
## Rows rather than cards is the whole point of the left column — cards stop
## working past about six commodities, rows never do — so this stays cheap:
## fixed height, no per-frame work, redrawn only when the market ticks.

signal selected(material_id: String)

## The handoff's `1.5fr 0.9fr 0.7fr 0.8fr` grid.
const COLUMN_RATIOS: Array[float] = [1.5, 0.9, 0.7, 0.8]
const HORIZONTAL_PADDING: int = 14
const CHIP_SIZE: float = 8.0
const SELECTED_EDGE_WIDTH: float = 2.0

var material_id: String = ""

var _color: Color = Color.WHITE
var _is_selected: bool = false
var _is_hovered: bool = false

var _chip: Panel
var _name_label: Label
var _held_pill: PanelContainer
var _held_label: Label
var _price_label: Label
var _delta_label: Label
var _spark: PriceGraph


func _init(id: String = "") -> void:
	material_id = id
	custom_minimum_size = Vector2(0, MarketTheme.ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_color = MaterialCatalog.color(material_id)
	_build()
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))


func _build() -> void:
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = HORIZONTAL_PADDING
	columns.offset_right = -HORIZONTAL_PADDING
	columns.add_theme_constant_override("separation", 0)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(columns)

	columns.add_child(_build_identity())
	_price_label = MarketTheme.mono_label("", MarketTheme.SIZE_ROW_NAME, MarketTheme.TEXT_PRICE)
	columns.add_child(_stretch(_price_label, COLUMN_RATIOS[1]))
	_delta_label = MarketTheme.mono_label("", MarketTheme.SIZE_SUB, MarketTheme.TEXT_MUTED)
	columns.add_child(_stretch(_delta_label, COLUMN_RATIOS[2]))
	columns.add_child(_build_spark())


func _build_identity() -> Control:
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_chip = MarketTheme.chip(_color, CHIP_SIZE)
	identity.add_child(_chip)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = MarketTheme.sans_label(MaterialCatalog.display_name(material_id),
		MarketTheme.SIZE_ROW_NAME, MarketTheme.TEXT_BODY)
	names.add_child(_name_label)
	names.add_child(MarketTheme.mono_label(MaterialCatalog.category(material_id),
		MarketTheme.SIZE_TINY, MarketTheme.TEXT_FAINT, true))
	identity.add_child(names)

	identity.add_child(_build_held_pill())
	return _stretch(identity, COLUMN_RATIOS[0])


func _build_held_pill() -> Control:
	_held_pill = PanelContainer.new()
	_held_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_held_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_pill.visible = false
	_held_pill.add_theme_stylebox_override("panel", MarketTheme.padded(
		MarketTheme.flat_style(Color.TRANSPARENT, MarketTheme.with_alpha(MarketTheme.CYAN, 0.3)),
		5, 1, 5, 1))
	_held_label = MarketTheme.mono_label("", MarketTheme.SIZE_TINY, MarketTheme.CYAN_BRIGHT)
	_held_pill.add_child(_held_label)
	return _held_pill


func _build_spark() -> Control:
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = COLUMN_RATIOS[3]
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_spark = PriceGraph.new()
	_spark.line_width = 1.3
	_spark.fill_opacity = 0.0
	_spark.size = MarketTheme.SPARK_SIZE
	# Pinned to the right edge of its column, vertically centred — the handoff
	# right-aligns the TREND column.
	_spark.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_spark.position = Vector2(-MarketTheme.SPARK_SIZE.x, -MarketTheme.SPARK_SIZE.y * 0.5)
	holder.add_child(_spark)
	return holder


func _stretch(control: Control, ratio: float) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.size_flags_stretch_ratio = ratio
	if control is Label:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


# --- State ------------------------------------------------------------------

func refresh(held: int, spark_samples: Array) -> void:
	var delta: int = MarketService.get_delta(material_id)
	_price_label.text = str(MarketService.get_price(material_id))
	_delta_label.text = ("▲ +%d" if delta >= 0 else "▼ %d") % delta
	_delta_label.add_theme_color_override("font_color", MarketTheme.direction_color(delta))
	_held_pill.visible = held > 0
	_held_label.text = "%du" % held
	_spark.set_series(spark_samples, _color)


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	_name_label.add_theme_color_override("font_color",
		MarketTheme.TEXT_PRIMARY if value else MarketTheme.TEXT_BODY)
	queue_redraw()


func _on_hover_changed(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(material_id)


func _draw() -> void:
	if _is_selected:
		draw_rect(Rect2(Vector2.ZERO, size), MarketTheme.with_alpha(MarketTheme.CYAN, 0.10), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(SELECTED_EDGE_WIDTH, size.y)), _color, true)
	elif _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), MarketTheme.HOVER, true)
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), MarketTheme.BORDER_FAINT, 1.0)

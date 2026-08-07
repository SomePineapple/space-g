class_name MarketFocusCard
extends VBoxContainer

## The Exchange's centre card: the selected material's name, live price, full
## 26-sample chart and the stats strip beneath it
## (docs/design_handoff_trade_market/README.md "Centre — focus panel").
##
## The 2px accent along the top is a separate strip above the card rather than
## a border width, because StyleBoxFlat carries one border colour for all four
## sides and the other three stay white-at-7%.

const ACCENT_HEIGHT: float = 2.0
const CARD_PADDING_HORIZONTAL: int = 24
const CARD_PADDING_VERTICAL: int = 20
const CHART_MARGIN_TOP: int = 14
const CHART_MARGIN_BOTTOM: int = 10
const STATS_SEPARATION: int = 26

## Supply readout thresholds, high means glut.
const GLUT_PERCENT: int = 66
const STEADY_PERCENT: int = 33
## A price never sits exactly on its anchor, so anything inside this band of
## it still reads as "steady" rather than flickering a pressure figure.
const STEADY_BAND: float = 0.01

var _material_id: String = ""

var _accent: Panel
var _name_label: Label
var _subtitle: Label
var _price_label: Label
var _delta_label: Label
var _chart: PriceGraph
var _supply_bar: Panel
var _supply_fill: Panel
var _supply_label: Label
var _range_label: Label
var _spread_label: Label
var _pressure_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_accent = Panel.new()
	_accent.custom_minimum_size = Vector2(0, ACCENT_HEIGHT)
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_accent)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = MarketTheme.padded(
		MarketTheme.panel(MarketTheme.PANEL_ALPHA_LIST),
		CARD_PADDING_HORIZONTAL, CARD_PADDING_VERTICAL,
		CARD_PADDING_HORIZONTAL, CARD_PADDING_VERTICAL)
	style.border_width_top = 0
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	column.add_child(_build_heading())
	column.add_child(_build_chart())
	column.add_child(_build_stats())


func _build_heading() -> Control:
	var row := HBoxContainer.new()

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label = MarketTheme.sans_label("", MarketTheme.SIZE_FOCUS_NAME, MarketTheme.TEXT_PRIMARY)
	titles.add_child(_name_label)
	_subtitle = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL, true)
	titles.add_child(_subtitle)
	row.add_child(titles)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 12)
	price_row.alignment = BoxContainer.ALIGNMENT_END
	price_row.size_flags_vertical = Control.SIZE_SHRINK_END
	_price_label = MarketTheme.mono_label("", MarketTheme.SIZE_FOCUS_PRICE, MarketTheme.TEXT_PRIMARY)
	price_row.add_child(_price_label)
	price_row.add_child(_baseline_aligned(
		MarketTheme.mono_label("cr/u", MarketTheme.SIZE_BODY, MarketTheme.TEXT_LABEL)))
	_delta_label = MarketTheme.mono_label("", MarketTheme.SIZE_FOCUS_DELTA, MarketTheme.TEXT_MUTED)
	price_row.add_child(_baseline_aligned(_delta_label))
	row.add_child(price_row)
	return row


## The handoff aligns `cr/u` and the delta on the big price's baseline; Godot
## has no baseline alignment, so they sit on the bottom of the tallest label
## instead, which is within a pixel of it for these sizes.
func _baseline_aligned(label: Label) -> Label:
	label.size_flags_vertical = Control.SIZE_SHRINK_END
	return label


func _build_chart() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", CHART_MARGIN_TOP)
	margin.add_theme_constant_override("margin_bottom", CHART_MARGIN_BOTTOM)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_chart = PriceGraph.new()
	_chart.line_width = 2.0
	_chart.fill_opacity = 0.10
	margin.add_child(_chart)
	return margin


func _build_stats() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", STATS_SEPARATION)

	var supply := HBoxContainer.new()
	supply.add_theme_constant_override("separation", 9)
	supply.add_child(MarketTheme.mono_label("SUPPLY", MarketTheme.SIZE_LABEL,
		MarketTheme.TEXT_LABEL, true))
	supply.add_child(_build_supply_bar())
	_supply_label = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_MUTED)
	supply.add_child(_supply_label)
	row.add_child(supply)

	_range_label = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL)
	row.add_child(_range_label)
	_spread_label = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL)
	row.add_child(_spread_label)

	_pressure_label = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL)
	_pressure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pressure_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_pressure_label)
	return row


func _build_supply_bar() -> Control:
	_supply_bar = Panel.new()
	_supply_bar.custom_minimum_size = MarketTheme.SUPPLY_BAR_SIZE
	_supply_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_supply_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_supply_bar.add_theme_stylebox_override("panel", MarketTheme.flat_style(MarketTheme.TRACK))

	_supply_fill = Panel.new()
	_supply_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_supply_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_supply_bar.add_child(_supply_fill)
	return _supply_bar


# --- State ------------------------------------------------------------------

## Not `set_material` — CanvasItem already owns that name.
func show_material(material_id: String) -> void:
	_material_id = material_id
	var color: Color = MaterialCatalog.color(material_id)
	_accent.add_theme_stylebox_override("panel", MarketTheme.flat_style(color))
	_name_label.text = MaterialCatalog.display_name(material_id)


func refresh() -> void:
	if _material_id.is_empty():
		return
	var price: int = MarketService.get_price(_material_id)
	var delta: int = MarketService.get_delta(_material_id)
	var history: Array = MarketService.get_history(_material_id)

	_subtitle.text = "%s · %du traded this shift" % [
		MaterialCatalog.category(_material_id).to_upper(),
		MarketService.get_shift_volume(_material_id),
	]
	_price_label.text = str(price)
	_delta_label.text = ("▲ +%d" if delta >= 0 else "▼ %d") % delta
	_delta_label.add_theme_color_override("font_color", MarketTheme.direction_color(delta))
	_chart.set_series(history, MaterialCatalog.color(_material_id))

	_refresh_supply()
	_refresh_range(history)
	_spread_label.text = "STATION PAYS %d cr sell" % MarketService.get_sell_price(_material_id)
	_refresh_pressure()


func _refresh_supply() -> void:
	var percent: int = MarketService.get_supply_percent(_material_id)
	var color: Color = MarketTheme.PRICE_DOWN
	var word: String = "SCARCE"
	if percent > GLUT_PERCENT:
		color = MarketTheme.PRICE_UP
		word = "GLUT"
	elif percent > STEADY_PERCENT:
		color = MarketTheme.AMBER
		word = "STEADY"
	_supply_fill.add_theme_stylebox_override("panel", MarketTheme.flat_style(color))
	# PRESET_LEFT_WIDE pins the fill to the track's left edge with a zero-width
	# right anchor, so offset_right *is* its width.
	_supply_fill.offset_right = MarketTheme.SUPPLY_BAR_SIZE.x * percent / 100.0
	_supply_label.text = word
	_supply_label.add_theme_color_override("font_color", color)


func _refresh_range(history: Array) -> void:
	if history.is_empty():
		_range_label.text = ""
		return
	var lowest: float = history[0]
	var highest: float = history[0]
	for value in history:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	_range_label.text = "RANGE %d–%d cr" % [roundi(lowest), roundi(highest)]


## The live "is anyone leaning on this market" line — how far the price sits
## from its anchor, counting both the stock shortfall a run of buying leaves
## behind and the short-lived pressure on top of it.
func _refresh_pressure() -> void:
	var deviation: float = MarketService.get_deviation(_material_id)
	if absf(deviation) < STEADY_BAND:
		_pressure_label.text = "Market steady"
		_pressure_label.add_theme_color_override("font_color", MarketTheme.TEXT_LABEL)
		return
	var upward: bool = deviation > 0.0
	_pressure_label.text = "%s %s%.1f%%" % [
		"Under upward pressure" if upward else "Under downward pressure",
		"+" if upward else "", deviation * 100.0,
	]
	_pressure_label.add_theme_color_override("font_color",
		MarketTheme.CYAN_BRIGHT if upward else MarketTheme.AMBER)

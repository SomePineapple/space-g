class_name MarketRail
extends VBoxContainer

## The Exchange's right rail: NEARBY MARKETS, MARKET FORCES and FLOOR ACTIVITY
## (docs/design_handoff_trade_market/README.md "Right rail").
##
## The sizing here is load-bearing. The rail is a fixed-height column, so the
## top two panels take explicit flex shares and the log is pinned to 176px,
## each clipping to its own scrolling list. Letting a panel size to its
## content collapses the flexible one and clips text mid-line.
##
## Rows are rebuilt on each market tick rather than pooled: there are at most
## a handful per panel, and the alternative is three parallel node caches to
## keep in step with three different-shaped data sources.

const PANEL_PAD_HORIZONTAL: int = 16
const PANEL_PAD_VERTICAL: int = 14
const NEARBY_SUBTITLE: String = "Prices react to your trades, strongest within 2 jumps."
const COMPARISON_BAR_HEIGHT: float = 4.0
const EVENT_CHIP_SIZE: float = 7.0
const SCROLLBAR_GUTTER: int = 12
## Oldest visible event keeps this much opacity — see the handoff's 1 → 0.45.
const EVENT_MIN_OPACITY: float = 0.45
const ACTIVITY_MIN_OPACITY: float = 0.35

var _nearby_title: Label
var _nearby_list: VBoxContainer
var _forces_summary: Label
var _forces_list: VBoxContainer
var _activity_list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(MarketTheme.RAIL_WIDTH, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	add_theme_constant_override("separation", MarketTheme.PANEL_GAP)

	_nearby_title = MarketTheme.caption("NEARBY MARKETS")
	_nearby_list = VBoxContainer.new()
	_nearby_list.add_theme_constant_override("separation", 0)
	add_child(_build_panel(_nearby_title, MarketTheme.sans_label(NEARBY_SUBTITLE,
		MarketTheme.SIZE_SUB, MarketTheme.TEXT_LABEL), _nearby_list, MarketTheme.NEARBY_STRETCH))

	_forces_summary = MarketTheme.sans_label("", MarketTheme.SIZE_SUB, MarketTheme.TEXT_LABEL)
	_forces_list = VBoxContainer.new()
	_forces_list.add_theme_constant_override("separation", 7)
	add_child(_build_panel(MarketTheme.caption("MARKET FORCES"), _forces_summary,
		_forces_list, MarketTheme.FORCES_STRETCH))

	_activity_list = VBoxContainer.new()
	_activity_list.add_theme_constant_override("separation", 9)
	var activity: Control = _build_panel(MarketTheme.caption("FLOOR ACTIVITY"), null,
		_activity_list, 0.0)
	activity.custom_minimum_size = Vector2(0, MarketTheme.ACTIVITY_PANEL_HEIGHT)
	add_child(activity)


## `stretch` of 0 means the panel is fixed-height and does not expand.
func _build_panel(title: Label, subtitle: Label, list: VBoxContainer, stretch: float) -> Control:
	var panel: PanelContainer = MarketTheme.make_panel(MarketTheme.PANEL_ALPHA_RAIL,
		PANEL_PAD_HORIZONTAL, PANEL_PAD_VERTICAL)
	panel.clip_contents = true
	if stretch > 0.0:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = stretch
	else:
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 3)
	heading.add_child(title)
	if subtitle != null:
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.add_child(subtitle)
	column.add_child(heading)

	var scroll: ScrollContainer = MarketTheme.make_scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The scrollbar is drawn over the content, and every list in this rail
	# ends in a right-aligned number, so the rows keep a gutter clear of it.
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", SCROLLBAR_GUTTER)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(list)
	scroll.add_child(gutter)
	column.add_child(scroll)
	return panel


# --- Nearby markets ---------------------------------------------------------

func refresh_nearby(material_id: String) -> void:
	_nearby_title.text = "NEARBY MARKETS · %s" % MaterialCatalog.display_name(material_id).to_upper()
	_clear(_nearby_list)
	for station in MarketService.get_neighbour_markets(material_id):
		_nearby_list.add_child(_build_nearby_row(station))


func _build_nearby_row(station: Dictionary) -> Control:
	var difference: int = station["difference_percent"]
	var tint: Color = MarketTheme.TEXT_SUBTLE
	if difference > MarketTheme.NEUTRAL_PERCENT:
		tint = MarketTheme.PRICE_UP
	elif difference < -MarketTheme.NEUTRAL_PERCENT:
		tint = MarketTheme.PRICE_DOWN

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var name_label: Label = MarketTheme.sans_label(station["name"],
		MarketTheme.SIZE_NEARBY_NAME, MarketTheme.TEXT_PRICE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(MarketTheme.mono_label("%d cr" % station["price"],
		MarketTheme.SIZE_BODY, MarketTheme.TEXT_BODY))
	var difference_label: Label = MarketTheme.mono_label(
		"%+d%%" % difference, MarketTheme.SIZE_SUB, tint)
	difference_label.custom_minimum_size = Vector2(46, 0)
	difference_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(difference_label)
	row.add_child(top)

	row.add_child(_build_nearby_meta(station, difference, tint))
	return _with_top_rule(row, 8)


func _build_nearby_meta(station: Dictionary, difference: int, tint: Color) -> Control:
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)

	var jumps: int = station["jumps"]
	meta.add_child(MarketTheme.mono_label("%d %s" % [jumps, "jump" if jumps == 1 else "jumps"],
		MarketTheme.SIZE_TINY, MarketTheme.TEXT_FAINT))
	meta.add_child(_comparison_bar(difference, tint))

	var flagged: bool = absi(difference) > MarketTheme.ARBITRAGE_PERCENT
	var note: String = "in line"
	if difference > MarketTheme.ARBITRAGE_PERCENT:
		note = "sell here"
	elif difference < -MarketTheme.ARBITRAGE_PERCENT:
		note = "buy here"
	meta.add_child(MarketTheme.mono_label(note, MarketTheme.SIZE_TINY,
		MarketTheme.AMBER if flagged else MarketTheme.TEXT_FAINT))

	if station["reacting"]:
		meta.add_child(MarketTheme.mono_label("reacting to you", MarketTheme.SIZE_TINY,
			MarketTheme.CYAN_BRIGHT))
	return meta


## A centred 0–100 bar: half-full means "same price as here", so the eye can
## read cheaper/dearer without comparing numbers.
func _comparison_bar(difference: int, tint: Color) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, COMPARISON_BAR_HEIGHT)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_theme_stylebox_override("panel", MarketTheme.flat_style(Color(1, 1, 1, 0.06)))

	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(50.0 + difference * 2.0, 0.0, 100.0) / 100.0
	fill.add_theme_stylebox_override("panel",
		MarketTheme.flat_style(MarketTheme.with_alpha(tint, 0.6)))
	track.add_child(fill)
	return track


# --- Market forces ----------------------------------------------------------

func refresh_forces() -> void:
	_clear(_forces_list)
	var events: Array = MarketService.get_events()
	_forces_summary.text = "No outside pressure right now" if events.is_empty() \
		else "%d active price drivers across %d markets" % [events.size(),
			MarketService.NEIGHBOURS.size()]
	for index in events.size():
		_forces_list.add_child(_build_force_row(events[index]))


func _build_force_row(event: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.modulate.a = maxf(EVENT_MIN_OPACITY, 1.0 - int(event["age"]) * 0.09)

	var chip: Panel = MarketTheme.chip(event["color"], EVENT_CHIP_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(chip)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 2)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sentence: Label = MarketTheme.sans_label(event["text"], MarketTheme.SIZE_TICKER,
		MarketTheme.TEXT_BODY)
	sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(sentence)
	var age: int = event["age"]
	text_column.add_child(MarketTheme.mono_label("%d %s out · %s" % [
			event["jumps"], "jump" if int(event["jumps"]) == 1 else "jumps",
			"just now" if age < 2 else "%d ticks ago" % age,
		], MarketTheme.SIZE_TINY, MarketTheme.TEXT_FAINT))
	row.add_child(text_column)

	var percent: float = event["percent"]
	row.add_child(MarketTheme.mono_label("%+.1f%%" % percent, MarketTheme.SIZE_SUB,
		MarketTheme.direction_color(percent)))
	return _with_top_rule(row, 7)


# --- Floor activity ---------------------------------------------------------

func refresh_activity() -> void:
	_clear(_activity_list)
	var lines: Array = MarketService.get_activity()
	for index in lines.size():
		var line: Dictionary = lines[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.modulate.a = maxf(ACTIVITY_MIN_OPACITY, 1.0 - index * 0.14)
		row.add_child(MarketTheme.mono_label(line["time"], MarketTheme.SIZE_LABEL,
			MarketTheme.TEXT_FAINT))
		var text: Label = MarketTheme.sans_label(line["text"], MarketTheme.SIZE_TICKER,
			_activity_color(line["kind"]))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_activity_list.add_child(row)


func _activity_color(kind: String) -> Color:
	match kind:
		"buy":
			return MarketTheme.CYAN_BRIGHT
		"sell":
			return MarketTheme.AMBER
		_:
			return MarketTheme.TEXT_MUTED


# --- Shared -----------------------------------------------------------------

## Wraps a row in its 1px separator plus the padding the handoff gives it.
func _with_top_rule(row: Control, top_padding: int) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override("panel", MarketTheme.flat_style(MarketTheme.DIVIDER))
	wrapper.add_child(rule)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", top_padding)
	margin.add_theme_constant_override("margin_bottom", top_padding)
	margin.add_child(row)
	wrapper.add_child(margin)
	return wrapper


func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

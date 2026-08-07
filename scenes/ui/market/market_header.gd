class_name MarketHeader
extends MarginContainer

## The Exchange's top band: station name, the trader count, the credit
## readout and the hold bar (docs/design_handoff_trade_market/README.md
## "Header").
##
## The trader count is flavour derived from occupied berths, but the handoff
## is explicit that it has to move — a static number here makes the whole
## station read as a mock-up.

const STATION_TITLE: String = "Corporate Station · Exchange"
const SECTOR_LABEL: String = "SECTOR 04"
## Gap between the two right-hand readouts, wider than the title's own gap.
const READOUT_SEPARATION: int = 26

var _traders_label: Label
var _credits_label: Label
var _hold_label: Label
var _hold_fill: Panel


func _ready() -> void:
	add_theme_constant_override("margin_left", MarketTheme.GUTTER)
	add_theme_constant_override("margin_right", MarketTheme.GUTTER)
	add_theme_constant_override("margin_top", MarketTheme.HEADER_TOP_PAD)
	add_theme_constant_override("margin_bottom", MarketTheme.HEADER_BOTTOM_PAD)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(MarketTheme.sans_label(STATION_TITLE, MarketTheme.SIZE_STATION,
		MarketTheme.TEXT_PRIMARY))

	_traders_label = MarketTheme.mono_label("", MarketTheme.SIZE_SUB, MarketTheme.TEXT_LABEL, true)
	_traders_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_traders_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_traders_label)

	var readouts := HBoxContainer.new()
	readouts.add_theme_constant_override("separation", READOUT_SEPARATION)
	_credits_label = MarketTheme.mono_label("", MarketTheme.SIZE_CREDITS, MarketTheme.AMBER)
	readouts.add_child(_build_readout("CREDITS", _credits_label, 2))
	_hold_label = MarketTheme.mono_label("", MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL, true)
	readouts.add_child(_build_readout("", _hold_label, 5, true))
	row.add_child(readouts)

	add_child(row)


## A right-aligned block: a caption over its value, or — for the hold — the
## caption itself over a bar.
func _build_readout(caption: String, value: Label, separation: int, is_bar: bool = false) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", separation)
	block.alignment = BoxContainer.ALIGNMENT_END
	if not caption.is_empty():
		var label: Label = MarketTheme.mono_label(caption, MarketTheme.SIZE_LABEL,
			MarketTheme.TEXT_LABEL, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		block.add_child(label)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	block.add_child(value)
	if is_bar:
		block.add_child(_build_hold_bar())
	return block


func _build_hold_bar() -> Control:
	var track := Panel.new()
	track.custom_minimum_size = MarketTheme.HOLD_BAR_SIZE
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = MarketTheme.flat_style(MarketTheme.TRACK)
	# The one rounded element on the screen, per the handoff.
	style.set_corner_radius_all(4)
	track.add_theme_stylebox_override("panel", style)

	_hold_fill = Panel.new()
	_hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	var fill_style: StyleBoxFlat = MarketTheme.flat_style(MarketTheme.CYAN)
	fill_style.set_corner_radius_all(4)
	_hold_fill.add_theme_stylebox_override("panel", fill_style)
	track.add_child(_hold_fill)
	return track


func refresh(credits: int, cargo_used: int, cargo_capacity: int) -> void:
	_traders_label.text = "%s · %d TRADERS ON DECK" % [SECTOR_LABEL,
		MarketService.get_trader_count()]
	_credits_label.text = "%s CR" % HudPalette.group_digits(credits)
	_hold_label.text = "HOLD %d / %d" % [cargo_used, cargo_capacity]

	var fraction: float = 0.0
	if cargo_capacity > 0:
		fraction = clampf(float(cargo_used) / cargo_capacity, 0.0, 1.0)
	# PRESET_LEFT_WIDE pins the fill to the track's left edge with a zero-width
	# right anchor, so offset_right *is* its width.
	_hold_fill.offset_right = MarketTheme.HOLD_BAR_SIZE.x * fraction

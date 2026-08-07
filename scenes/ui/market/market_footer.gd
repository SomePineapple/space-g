class_name MarketFooter
extends PanelContainer

## The Exchange's bottom hint bar: the key legend on the left, the station
## clock and the countdown to the next price tick on the right
## (docs/design_handoff_trade_market/README.md "Footer hint bar").

## `[M] NEARBY MARKETS` is a legend entry only — the rail is always on screen,
## so there is nothing for the key to toggle. It is kept because the handoff
## lists it and the panel it names is right there.
const HINTS: Array[String] = [
	"[↑/↓] SELECT MATERIAL", "[1-4] QUANTITY", "[B] BUY  [S] SELL", "[M] NEARBY MARKETS",
]

var _repair_label: Label
var _clock_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, MarketTheme.FOOTER_HEIGHT)
	var style: StyleBoxFlat = MarketTheme.padded(
		MarketTheme.flat_style(MarketTheme.with_alpha(MarketTheme.STRIP_RGB, 0.8)),
		MarketTheme.GUTTER, 0, MarketTheme.GUTTER, 0)
	style.border_width_top = 1
	style.border_color = MarketTheme.HAIRLINE
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	for hint in HINTS:
		row.add_child(_hint_label(hint, MarketTheme.TEXT_LABEL))

	# Not one of the handoff's hints: paid hull repair used to live on the old
	# trade panel, and the station exchange is the only screen it can reach.
	_repair_label = _hint_label("", MarketTheme.TEXT_LABEL)
	row.add_child(_repair_label)

	_clock_label = _hint_label("", MarketTheme.CYAN_BRIGHT)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_clock_label)
	add_child(row)


func _hint_label(text: String, color: Color) -> Label:
	var label: Label = MarketTheme.mono_label(text, MarketTheme.SIZE_SUB, color, true)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Called every frame the screen is open: the tick countdown is the one thing
## down here that has to move between market ticks.
func refresh(repair_cost: int) -> void:
	_clock_label.text = "%s · NEXT PRICE TICK %ds" % [MarketService.get_station_clock(),
		ceili(MarketService.seconds_to_next_tick())]
	var needs_repair: bool = repair_cost > 0
	_repair_label.text = "[R] REPAIR HULL · %d cr" % repair_cost if needs_repair \
		else "[R] HULL INTACT"
	_repair_label.add_theme_color_override("font_color",
		MarketTheme.AMBER if needs_repair else MarketTheme.TEXT_FAINT)

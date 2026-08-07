class_name MarketTicker
extends Control

## The LIVE FEED strip: an opaque fixed chip on the left and a right-to-left
## marquee of every material's price plus a few station headlines
## (docs/design_handoff_trade_market/README.md "Ticker").
##
## The strip is drawn rather than built from Labels because it is one long
## line of text scrolling under a mask — a container would need its own
## clipping, its own duplicate-for-seamless-loop copy, and a per-frame
## position write anyway.

const CHIP_WIDTH: float = 120.0
const CHIP_LABEL: String = "LIVE FEED"
## One full pass of the (duplicated) item list, in seconds.
const LOOP_SECONDS: float = 60.0
const ITEM_PADDING: float = 26.0

## Station headlines interleaved with the price quotes. Flavour today; the
## handoff expects real world-sim events to replace them, which is a change of
## source, not of shape.
const HEADLINES: Array[Dictionary] = [
	{"text": "CDF CONVOY INBOUND · TITANIUM DEMAND UP", "tone": "warm"},
	{"text": "BERTH B-06 CLEARED", "tone": "muted"},
	{"text": "PIRATE ACTIVITY REPORTED · SECTOR 07", "tone": "down"},
]

## Array of {"text": String, "color": Color, "width": float}.
var _items: Array = []
var _content_width: float = 0.0
var _scroll: float = 0.0
var _font: Font
var _baseline: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, MarketTheme.TICKER_HEIGHT)
	_font = MarketTheme.mono_font()
	_baseline = (MarketTheme.TICKER_HEIGHT + _font.get_ascent(MarketTheme.SIZE_TICKER)
		- _font.get_descent(MarketTheme.SIZE_TICKER)) * 0.5


## Rebuilt from the market on every tick — the quotes are the point of the
## strip, so they must not be a one-time snapshot.
func rebuild(material_ids: Array) -> void:
	_items.clear()
	_content_width = 0.0
	for material_id in material_ids:
		var delta: int = MarketService.get_delta(material_id)
		var prefix: String = "▲ +" if delta >= 0 else "▼ "
		_append("%s  %d cr  %s%d" % [
			MaterialCatalog.display_name(material_id).to_upper(),
			MarketService.get_price(material_id), prefix, delta,
		], MarketTheme.direction_color(delta))
	for headline in HEADLINES:
		_append(headline["text"], _headline_color(headline["tone"]))
	queue_redraw()


func _append(text: String, color: Color) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		MarketTheme.SIZE_TICKER).x + ITEM_PADDING * 2.0
	_items.append({"text": text, "color": color, "width": width})
	_content_width += width


func _headline_color(tone: String) -> Color:
	match tone:
		"warm":
			return MarketTheme.AMBER
		"down":
			return MarketTheme.PRICE_DOWN
		_:
			return MarketTheme.TEXT_LABEL


func _process(delta: float) -> void:
	if _content_width <= 0.0:
		return
	_scroll = fposmod(_scroll + _content_width / LOOP_SECONDS * delta, _content_width)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MarketTheme.with_alpha(MarketTheme.STRIP_RGB, 0.7), true)
	draw_line(Vector2.ZERO, Vector2(size.x, 0), MarketTheme.HAIRLINE, 1.0)
	draw_line(Vector2(0, size.y), size, MarketTheme.HAIRLINE, 1.0)

	_draw_items()
	_draw_chip()


## Items are laid out once and then drawn twice, offset by the full content
## width, so the loop has no visible seam or restart.
func _draw_items() -> void:
	if _items.is_empty():
		return
	var start: float = CHIP_WIDTH - _scroll
	for pass_index in 2:
		var x: float = start + pass_index * _content_width
		for item in _items:
			var width: float = item["width"]
			if x + width > CHIP_WIDTH and x < size.x:
				draw_string(_font, Vector2(x + ITEM_PADDING, _baseline), item["text"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, MarketTheme.SIZE_TICKER, item["color"])
			x += width


## Opaque, not translucent: items scrolling visibly under the chip was a bug
## in an earlier design pass, so it is drawn last and over an opaque fill.
func _draw_chip() -> void:
	var chip := Rect2(Vector2.ZERO, Vector2(CHIP_WIDTH, size.y))
	draw_rect(chip, MarketTheme.SCREEN_BG, true)
	draw_rect(chip, MarketTheme.with_alpha(MarketTheme.CYAN, 0.10), true)
	draw_line(Vector2(CHIP_WIDTH, 0), Vector2(CHIP_WIDTH, size.y),
		MarketTheme.with_alpha(MarketTheme.CYAN, 0.2), 1.0)

	var font: Font = MarketTheme.mono_tracked_font()
	var text_width: float = font.get_string_size(CHIP_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1,
		MarketTheme.SIZE_LABEL).x
	draw_string(font, Vector2((CHIP_WIDTH - text_width) * 0.5, _baseline), CHIP_LABEL,
		HORIZONTAL_ALIGNMENT_LEFT, -1, MarketTheme.SIZE_LABEL, MarketTheme.CYAN_BRIGHT)

class_name MarketTheme
extends RefCounted

## Colours, type sizes and StyleBox factories for the station Exchange screen
## (docs/design_handoff_trade_market/README.md "Design tokens" is the source
## of truth for every value here).
##
## Hex values are written out as floats because GDScript `const` can't fold
## Color("rrggbb") — the hex stays in the comment on each line. Several of
## these match BuilderTheme's Corporate palette; they are repeated rather than
## aliased so this screen can be retuned without dragging the builder with it.
##
## Type sizes are the handoff's px values rounded to the nearest integer,
## which is all Godot's font_size accepts.

# --- Surfaces ---------------------------------------------------------------
const SCREEN_BG: Color = Color(0.0392, 0.0510, 0.0706)  # 0a0d12
## rgba(16,20,26,*) — panels differ only in fill opacity.
const PANEL_RGB: Color = Color(0.0627, 0.0784, 0.1020)  # 101419
const PANEL_ALPHA_LIST: float = 0.6
const PANEL_ALPHA_RAIL: float = 0.7
const PANEL_ALPHA_TRADE: float = 0.75
## rgba(6,9,13,*) — ticker and footer strips.
const STRIP_RGB: Color = Color(0.0235, 0.0353, 0.0510)  # 060911

const BORDER: Color = Color(1, 1, 1, 0.07)
const BORDER_FAINT: Color = Color(1, 1, 1, 0.04)
const DIVIDER: Color = Color(1, 1, 1, 0.05)
const TRACK: Color = Color(1, 1, 1, 0.07)
const HOVER: Color = Color(1, 1, 1, 0.05)
## The cyan hairline above and below the ticker and above the footer.
const HAIRLINE: Color = Color(0.3333, 0.8392, 0.9098, 0.14)  # 55d6e8 @ 0.14

# --- Text -------------------------------------------------------------------
const TEXT_PRIMARY: Color = Color(0.9412, 0.9647, 0.9725)  # f0f6f8
const TEXT_PRICE: Color = Color(0.8588, 0.8902, 0.9176)  # dbe3ea
const TEXT_BODY: Color = Color(0.7843, 0.8275, 0.8588)  # c8d3db
const TEXT_MUTED: Color = Color(0.6588, 0.7059, 0.7412)  # a8b4bd
const TEXT_SUBTLE: Color = Color(0.5451, 0.5961, 0.6431)  # 8b98a4
const TEXT_LABEL: Color = Color(0.3725, 0.4275, 0.4706)  # 5f6d78
const TEXT_FAINT: Color = Color(0.3059, 0.3529, 0.3922)  # 4e5a64

# --- Accents ----------------------------------------------------------------
const CYAN: Color = Color(0.3333, 0.8392, 0.9098)  # 55d6e8
const CYAN_BRIGHT: Color = Color(0.5608, 0.9137, 0.9490)  # 8fe9f2
const AMBER: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e
const PRICE_UP: Color = Color(0.4353, 0.8902, 0.6275)  # 6fe3a0
const PRICE_DOWN: Color = Color(0.8784, 0.4784, 0.4157)  # e07a6a

# --- Type sizes -------------------------------------------------------------
const SIZE_FOCUS_PRICE: int = 44
const SIZE_FOCUS_NAME: int = 34
const SIZE_STATION: int = 23
const SIZE_CREDITS: int = 22
const SIZE_FOCUS_DELTA: int = 17
const SIZE_ROW_NAME: int = 14
const SIZE_NEARBY_NAME: int = 14
const SIZE_IMPACT: int = 14
const SIZE_BODY: int = 13
const SIZE_TICKER: int = 13
const SIZE_BUTTON: int = 13
const SIZE_SUB: int = 12
const SIZE_QUANTITY: int = 12
const SIZE_LABEL: int = 11
const SIZE_HEADER_CELL: int = 10
const SIZE_TINY: int = 10

# --- Layout metrics ---------------------------------------------------------
const GUTTER: int = 34
const HEADER_TOP_PAD: int = 22
const HEADER_BOTTOM_PAD: int = 16
const TICKER_HEIGHT: float = 38.0
const FOOTER_HEIGHT: float = 34.0
const BODY_PAD: int = 20
const COLUMN_GAP: int = 20
const PANEL_GAP: int = 14
const LIST_WIDTH: float = 440.0
const RAIL_WIDTH: float = 330.0
const ROW_HEIGHT: float = 52.0
const SPARK_SIZE: Vector2 = Vector2(56, 20)
const HOLD_BAR_SIZE: Vector2 = Vector2(180, 7)
const SUPPLY_BAR_SIZE: Vector2 = Vector2(150, 6)
const ACTIVITY_PANEL_HEIGHT: float = 176.0
const SCROLLBAR_WIDTH: float = 8.0
## The rail's three panels are given explicit flex shares on purpose — a
## content-sized panel here collapses the flexible one and clips text.
const NEARBY_STRETCH: float = 1.3
const FORCES_STRETCH: float = 1.0

## Beyond this the difference against a neighbour is called out in amber as a
## real arbitrage opportunity rather than noise.
const ARBITRAGE_PERCENT: int = 8
## Below this a difference is neither good nor bad, and prints grey.
const NEUTRAL_PERCENT: int = 4

static var _mono_font: SystemFont = null
static var _mono_tracked_font: FontVariation = null


## Godot ships no monospace font, so this resolves one from the OS. The
## sans/mono split carries most of this screen's character: every number,
## label and key hint is monospace, prose and names are not.
static func mono_font() -> Font:
	if _mono_font == null:
		_mono_font = _make_mono_font()
	return _mono_font


## The same face with the handoff's 0.06–0.14em tracking baked in, which
## Godot expresses as whole extra pixels between glyphs rather than an em
## fraction. Only uppercase monospace labels use it.
##
## A FontVariation wrapper, because glyph spacing lives there — SystemFont
## itself has no spacing of its own.
static func mono_tracked_font() -> Font:
	if _mono_tracked_font == null:
		_mono_tracked_font = FontVariation.new()
		_mono_tracked_font.base_font = mono_font()
		_mono_tracked_font.spacing_glyph = 1
	return _mono_tracked_font


static func _make_mono_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace",
	])
	font.allow_system_fallback = true
	return font


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func panel_fill(alpha: float) -> Color:
	return with_alpha(PANEL_RGB, alpha)


static func direction_color(value: float) -> Color:
	return PRICE_UP if value >= 0.0 else PRICE_DOWN


# --- Labels -----------------------------------------------------------------

static func mono_label(text: String, font_size: int, color: Color,
		tracked: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", mono_tracked_font() if tracked else mono_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func sans_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Uppercase monospace section label.
static func caption(text: String, color: Color = CYAN_BRIGHT) -> Label:
	return mono_label(text, SIZE_LABEL, color, true)


# --- Panels -----------------------------------------------------------------

static func flat_style(fill: Color, border: Color = Color.TRANSPARENT,
		border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	# Corners are square throughout this screen except the hold bar.
	style.set_corner_radius_all(0)
	if border.a > 0.0:
		style.set_border_width_all(border_width)
		style.border_color = border
	return style


static func padded(style: StyleBoxFlat, left: int, top: int, right: int, bottom: int) -> StyleBoxFlat:
	style.content_margin_left = left
	style.content_margin_top = top
	style.content_margin_right = right
	style.content_margin_bottom = bottom
	return style


static func panel(alpha: float) -> StyleBoxFlat:
	return flat_style(panel_fill(alpha), BORDER)


static func make_panel(alpha: float, pad_horizontal: int = 16, pad_vertical: int = 14) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel",
		padded(panel(alpha), pad_horizontal, pad_vertical, pad_horizontal, pad_vertical))
	return container


## Slim, translucent scrollbars (the handoff's 8px track with a cyan-at-25%
## thumb). Godot's default is a wide light bar that reads as a UI element in
## its own right and crowds the right-aligned numbers next to it.
static func make_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var bar: VScrollBar = scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)
	var grabber: StyleBoxFlat = flat_style(with_alpha(CYAN, 0.25))
	grabber.set_corner_radius_all(int(SCROLLBAR_WIDTH) / 2)
	bar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight",
		flat_style(with_alpha(CYAN, 0.45)))
	bar.add_theme_stylebox_override("grabber_pressed", flat_style(with_alpha(CYAN, 0.6)))
	return scroll


## Small solid square — the material colour chips and event dots.
static func chip(color: Color, extent: float) -> Panel:
	var square := Panel.new()
	square.custom_minimum_size = Vector2(extent, extent)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square.add_theme_stylebox_override("panel", flat_style(color))
	return square


static func set_chip_color(square: Panel, color: Color) -> void:
	square.add_theme_stylebox_override("panel", flat_style(color))


# --- Buttons ----------------------------------------------------------------

## Flat monospace button whose fill/border/text are set outright rather than
## derived, because the handoff specifies each state's three colours directly
## (selected tab, unselected tab, enabled BUY, disabled BUY, ...).
static func style_button(button: Button, fill: Color, border: Color, text: Color,
		font_size: int, pad_horizontal: int, pad_vertical: int) -> void:
	button.add_theme_font_override("font", mono_font())
	button.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)
	button.add_theme_color_override("font_disabled_color", text)

	var normal: StyleBoxFlat = padded(flat_style(fill, border),
		pad_horizontal, pad_vertical, pad_horizontal, pad_vertical)
	var hover: StyleBoxFlat = padded(flat_style(fill.lightened(0.06), border),
		pad_horizontal, pad_vertical, pad_horizontal, pad_vertical)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover if not button.disabled else normal)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

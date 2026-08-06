class_name BuilderTheme
extends RefCounted

## Colours, fonts and StyleBox factories for the ship-builder screen
## (docs/design_handoff_ship_builder/README.md is the source of truth for
## every value here).
##
## Hex values from the handoff are written out as floats because GDScript
## `const` can't fold Color("rrggbb") — the hex is kept in the comment on
## each line. Several of these deliberately match HudPalette (the gameplay
## HUD uses the same Corporate cyan/slate family); they are repeated rather
## than aliased so this screen can be retuned without touching the HUD.
##
## Known deviation: the handoff asks for `backdrop-filter: blur()` behind the
## cards. Godot has no cheap equivalent for a Control background, so the card
## fills are opaque-ish translucent instead of blurred.

# --- Surfaces ---------------------------------------------------------------
const BG_BASE: Color = Color(0.0392, 0.0510, 0.0706)  # 0a0d12
const PANEL_DARK: Color = Color(0.0510, 0.0667, 0.0902)  # 0d1117
const INPUT_DARK: Color = Color(0.0902, 0.1137, 0.1412)  # 171d24
const GLASS: Color = Color(0.0588, 0.0745, 0.0941)  # 0f1318

# --- Accents ----------------------------------------------------------------
const CYAN: Color = Color(0.3333, 0.8392, 0.9098)  # 55d6e8
const CYAN_BRIGHT: Color = Color(0.5608, 0.9137, 0.9490)  # 8fe9f2
const CYAN_DEEP: Color = Color(0.1647, 0.5608, 0.6392)  # 2a8fa3
const AMBER: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e
const AMBER_DEEP: Color = Color(0.6392, 0.5098, 0.1843)  # a3822f
const WARN: Color = Color(0.8863, 0.4078, 0.2902)  # e2684a
const WARN_TEXT: Color = Color(0.8510, 0.6039, 0.5255)  # d99a86
const WARN_TEXT_HOVER: Color = Color(0.9412, 0.8353, 0.8000)  # f0d5cc
const HEALTH_GOOD: Color = Color(0.4863, 0.9098, 0.7216)  # 7ce8b8

# --- Text -------------------------------------------------------------------
const TEXT_BRIGHT: Color = Color(0.9098, 0.9294, 0.9412)  # e8edf0
const TEXT_SELECTED: Color = Color(0.9412, 0.9647, 0.9725)  # f0f6f8
const TEXT_BODY: Color = Color(0.7804, 0.8157, 0.8471)  # c7d0d8
const TEXT_MUTED: Color = Color(0.6588, 0.7059, 0.7412)  # a8b4bd
const TEXT_MUTED_DIM: Color = Color(0.5608, 0.6275, 0.6706)  # 8fa0ab
const TEXT_LABEL: Color = Color(0.4863, 0.5451, 0.6000)  # 7c8b99
const TEXT_HINT: Color = Color(0.3725, 0.4275, 0.4706)  # 5f6d78

# --- Layout metrics ---------------------------------------------------------
const SCREEN_MARGIN: float = 32.0
const RIGHT_PANEL_WIDTH: float = 336.0
const RIGHT_PANEL_MARGIN: float = 24.0
const CARD_GAP: int = 12
const FIELD_TOP: float = 110.0
const FIELD_BOTTOM_INSET: float = 96.0
const BOTTOM_BAR_INSET: float = 60.0
const STATUS_LINE_INSET: float = 20.0

const RADIUS_SMALL: int = 3
const RADIUS_MEDIUM: int = 4
const RADIUS_CARD: int = 5
const RADIUS_FIELD: int = 6

## Hex silhouette ratio from STYLE_GUIDE.md (222 x 256).
const HEX_ASPECT: float = 222.0 / 256.0

static var _mono_font: SystemFont = null


## The handoff asks for "a monospace font available in the target engine".
## Godot ships no monospace font, so this resolves one from the OS rather
## than adding a font file to the project.
static func mono_font() -> Font:
	if _mono_font == null:
		_mono_font = SystemFont.new()
		_mono_font.font_names = PackedStringArray([
			"Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace",
		])
		_mono_font.allow_system_fallback = true
	return _mono_font


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


# --- StyleBoxes -------------------------------------------------------------

static func flat_style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = RADIUS_SMALL,
		border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	if border.a > 0.0:
		style.set_border_width_all(border_width)
		style.border_color = border
	return style


## Translucent bordered card ("rgba(15,19,24,0.72)" + cyan 0.25 border).
static func card_style(fill_alpha: float = 0.72, border_alpha: float = 0.25) -> StyleBoxFlat:
	return flat_style(with_alpha(GLASS, fill_alpha), with_alpha(CYAN, border_alpha), RADIUS_CARD)


## The hex field's container: near-black fill, 1px inset cyan hairline.
static func field_style() -> StyleBoxFlat:
	return flat_style(PANEL_DARK, with_alpha(CYAN, 0.14), RADIUS_FIELD)


static func padded(style: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


# --- Widgets ----------------------------------------------------------------

static func mono_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", mono_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func sans_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Outlined pill button. `tint` drives fill/border/text as a family, so the
## neutral cyan buttons and the destructive warm one share one call.
static func style_button(button: Button, tint: Color, text_color: Color, hover_text: Color,
		font_size: int = 12, horizontal_padding: float = 16.0, vertical_padding: float = 9.0) -> void:
	button.add_theme_font_override("font", mono_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", hover_text)
	button.add_theme_color_override("font_pressed_color", hover_text)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", with_alpha(text_color, 0.35))

	var normal: StyleBoxFlat = padded(
		flat_style(with_alpha(tint, 0.10), with_alpha(tint, 0.35), RADIUS_MEDIUM),
		horizontal_padding, vertical_padding)
	var hover: StyleBoxFlat = padded(
		flat_style(with_alpha(tint, 0.22), with_alpha(tint, 0.55), RADIUS_MEDIUM),
		horizontal_padding, vertical_padding)
	var pressed: StyleBoxFlat = padded(
		flat_style(with_alpha(tint, 0.32), with_alpha(tint, 0.7), RADIUS_MEDIUM),
		horizontal_padding, vertical_padding)
	var disabled: StyleBoxFlat = padded(
		flat_style(with_alpha(tint, 0.04), with_alpha(tint, 0.15), RADIUS_MEDIUM),
		horizontal_padding, vertical_padding)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Small 6px status dot with a soft glow, used by the top stat strip.
static func make_glow_dot(color: Color, diameter: float = 6.0) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(diameter, diameter)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_dot_color(dot, color)
	return dot


static func set_dot_color(dot: Panel, color: Color) -> void:
	var style: StyleBoxFlat = flat_style(color, Color.TRANSPARENT, 8)
	style.shadow_color = with_alpha(color, 0.55)
	style.shadow_size = 5
	dot.add_theme_stylebox_override("panel", style)


## 1px vertical hairline between stat-strip entries.
static func make_divider(height: float = 14.0) -> Panel:
	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(1, height)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_stylebox_override("panel", flat_style(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0))
	return divider

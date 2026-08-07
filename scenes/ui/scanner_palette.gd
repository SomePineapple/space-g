class_name ScannerPalette
extends RefCounted

## Design tokens for the A-scope scanner instrument
## (docs/design_handoff_scanner_radar/README.md, option 1D — the recommended
## one). Hex values are written out as floats because GDScript `const` can't
## fold Color("rrggbb"); the hex is kept in the comment on each line.
##
## Deliberately its own palette rather than an alias of HudPalette: 1D is a
## green instrument sitting inside an otherwise cyan HUD, and the handoff
## treats its colours as a set of their own. Only the two colours it genuinely
## shares with the HUD (amber, contact cyan) repeat values found there.

const ACCENT: Color = Color(0.4941, 0.8784, 0.6275)  # 7ee0a0
const ACCENT_BRIGHT: Color = Color(0.8784, 1.0, 0.9255)  # e0ffec
const AMBER: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e

const PANEL_FILL: Color = Color(0.0627, 0.0863, 0.0745, 0.60)  # rgba(16,22,19,0.6)
const HELP_FILL: Color = Color(0.0314, 0.0549, 0.0431, 0.94)  # rgba(8,14,11,0.94)
const CALLOUT_FILL: Color = Color(0.0392, 0.0627, 0.0510, 0.85)  # rgba(10,16,13,0.85)
const COOL_FILL: Color = Color(0.2980, 0.3529, 0.4000, 0.35)  # rgba(76,90,102,0.35)
const BACKDROP: Color = Color(0.0392, 0.0510, 0.0706)  # 0a0d12

const TEXT: Color = Color(0.7804, 0.8157, 0.8471)  # c7d0d8
const TEXT_DIM: Color = Color(0.4196, 0.4667, 0.5176)  # 6b7784
const TEXT_STATUS: Color = Color(0.2392, 0.2784, 0.3137)  # 3d4750
const HELP_TEXT: Color = Color(0.6235, 0.7020, 0.6588)  # 9fb3a8
const LIST_INDEX: Color = Color(0.2471, 0.5608, 0.4078)  # 3f8f68
const LIST_RANGE: Color = Color(0.3333, 0.8392, 0.9098)  # 55d6e8
const LIST_MUTED: Color = Color(0.2980, 0.3529, 0.4000)  # 4c5a66

## Trace signature -> marker/peak colour. rock/ice/wreck are the handoff's;
## "body" (planets) is this project's addition, see Scanner.signature_of().
const SIGNATURE_COLOR: Dictionary = {
	&"rock": Color(0.4941, 0.8784, 0.6275),  # 7ee0a0
	&"ice": Color(0.5608, 0.9137, 0.9490),  # 8fe9f2
	&"wreck": Color(0.9490, 0.7569, 0.3059),  # f2c14e
	&"body": Color(0.3333, 0.8392, 0.9098),  # 55d6e8
}

## Peak height multiplier per signature — wrecks read loudest, rock quietest.
const SIGNATURE_STRENGTH: Dictionary = {
	&"rock": 0.62,
	&"ice": 0.78,
	&"wreck": 1.0,
	&"body": 0.90,
}

# --- Geometry (all in the scope's own 360x360 space) ------------------------
const COLUMN_WIDTH: float = 360.0
const SCOPE_SIZE: float = 360.0
const PLOT_ORIGIN: Vector2 = Vector2(34.0, 84.0)
const PLOT_SIZE: Vector2 = Vector2(312.0, 246.0)
const BAR_Y: float = 34.0
const BAR_HEIGHT: float = 20.0
## The trace baseline sits this far above the plot floor.
const BASELINE_INSET: float = 14.0

const FONT_SIZE_CANVAS: int = 10
const FONT_SIZE_READOUT: int = 11
const FONT_SIZE_ROW: int = 12

static var _mono_font: SystemFont = null


## The handoff asks for a monospace face. Godot ships none, so this resolves
## one from the OS — same approach (and list) as BuilderTheme.mono_font().
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


static func signature_color(signature: StringName) -> Color:
	return SIGNATURE_COLOR.get(signature, ACCENT)


static func signature_strength(signature: StringName) -> float:
	return SIGNATURE_STRENGTH.get(signature, 0.62)


## "+40°" / "-30°" — every bearing readout in the instrument is signed.
static func format_bearing(degrees: float) -> String:
	var rounded: int = roundi(degrees)
	return ("%d°" % rounded) if rounded < 0 else ("+%d°" % rounded)


static func flat_style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	if border.a > 0.0:
		style.set_border_width_all(1)
		style.border_color = border
	return style


## Badge / help-card shell: a flat fill with even padding on all sides.
static func padded_style(fill: Color = ACCENT, border: Color = Color.TRANSPARENT,
		radius: int = 3, padding: float = 4.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = flat_style(fill, border, radius)
	style.content_margin_left = padding + 3.0
	style.content_margin_right = padding + 3.0
	style.content_margin_top = padding - 2.0
	style.content_margin_bottom = padding - 2.0
	return style


## The returns list's 1px rule: a top border only, with the handoff's 10px gap
## under it.
static func top_rule_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_top = 1
	style.border_color = with_alpha(ACCENT, 0.12)
	style.content_margin_top = 10.0
	return style


## PING and CLOSE share one look: solid accent fill, dark text. The cooldown
## state passes the muted fill and its own text colour rather than relying on
## Godot's disabled tint, which would wash the label out.
static func style_fire_button(button: Button, fill: Color, text_color: Color) -> void:
	button.add_theme_font_override("font", mono_font())
	button.add_theme_font_size_override("font_size", FONT_SIZE_READOUT)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_disabled_color"]:
		button.add_theme_color_override(state, text_color)

	button.add_theme_stylebox_override("normal", _button_box(fill))
	button.add_theme_stylebox_override("hover", _button_box(fill.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_box(fill.darkened(0.12)))
	button.add_theme_stylebox_override("disabled", _button_box(fill))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## The handoff's 7px x 14px button padding, shared by every button state so
## hovering never resizes the label.
static func _button_box(fill: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = flat_style(fill, Color.TRANSPARENT, 3)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func mono_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", mono_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

class_name DialogueStyle
extends RefCounted

## Design tokens and widget factories for the dialogue panel
## (docs/design_handoff_dialogue_box/README.md, option 1C).
##
## Split from DialogueBox so that script stays about playback — typing, advancing,
## replies — rather than half construction. Same division BuilderTheme makes for
## the ship builder.
##
## Shared hues come from HudPalette; only the values the handoff names that have
## no existing semantic entry there are defined here. Hex is kept in comments
## because GDScript const cannot fold Color("rrggbb").

const PANEL_FILL: Color = Color(0.0627, 0.0824, 0.1059, 0.9)  # 10151b @ 90%
const AFFILIATION: Color = Color(0.3608, 0.4196, 0.4706)  # 5c6b78
const BODY_TEXT: Color = Color(0.8745, 0.9059, 0.9255)  # dfe7ec
## Same value as HudPalette.HEALTH_WARNING, named for its role here.
const KEY_HINT: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e

const BORDER_ALPHA: float = 0.22
const DIVIDER_ALPHA: float = 0.14
const REPLY_FILL_ALPHA: float = 0.05
const REPLY_HOVER_FILL_ALPHA: float = 0.14
const REPLY_HOVER_BORDER_ALPHA: float = 0.4

const PANEL_RADIUS: int = 6
const REPLY_RADIUS: int = 4
const PANEL_PADDING_X: int = 18
const PANEL_PADDING_Y: int = 12
const REPLY_PADDING_X: int = 10
const REPLY_PADDING_Y: int = 6

const SPEAKER_SIZE: int = 12
const AFFILIATION_SIZE: int = 10
const HINT_SIZE: int = 10
const BODY_SIZE: int = 14
const REPLY_LABEL_SIZE: int = 13
const REPLY_KEY_SIZE: int = 10
const BODY_LINE_SPACING: int = 6  # 14px at line-height ~1.45

## Letter-spacing from the handoff, in em. Applied through FontVariation's glyph
## spacing — Label and RichTextLabel have no tracking property of their own, so
## this is the only way to get it without hand-kerning strings.
const SPEAKER_TRACKING: float = 0.16
const HINT_TRACKING: float = 0.14
const AFFILIATION_TRACKING: float = 0.12
const KEY_TRACKING: float = 0.1


## A monospace font with `tracking` em of extra glyph spacing. Reuses
## BuilderTheme's system-font resolution rather than repeating the list of font
## names, so the two panels cannot end up on different monospace faces.
static func mono(font_size: int, tracking: float = 0.0) -> Font:
	if is_zero_approx(tracking):
		return BuilderTheme.mono_font()
	var variation := FontVariation.new()
	variation.base_font = BuilderTheme.mono_font()
	variation.spacing_glyph = roundi(tracking * float(font_size))
	return variation


static func label(text: String, font_size: int, color: Color, tracking: float = 0.0) -> Label:
	var made := Label.new()
	made.text = text
	made.add_theme_font_override("font", mono(font_size, tracking))
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", color)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.set_border_width_all(1)
	style.border_color = HudPalette.with_alpha(HudPalette.CYAN, BORDER_ALPHA)
	style.set_corner_radius_all(PANEL_RADIUS)
	style.content_margin_left = PANEL_PADDING_X
	style.content_margin_right = PANEL_PADDING_X
	style.content_margin_top = PANEL_PADDING_Y
	style.content_margin_bottom = PANEL_PADDING_Y
	return style


static func reply_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HudPalette.with_alpha(HudPalette.CYAN,
		REPLY_HOVER_FILL_ALPHA if hovered else REPLY_FILL_ALPHA)
	style.set_border_width_all(1)
	style.border_color = HudPalette.with_alpha(HudPalette.CYAN,
		REPLY_HOVER_BORDER_ALPHA if hovered else DIVIDER_ALPHA)
	style.set_corner_radius_all(REPLY_RADIUS)
	style.content_margin_left = REPLY_PADDING_X
	style.content_margin_right = REPLY_PADDING_X
	style.content_margin_top = REPLY_PADDING_Y
	style.content_margin_bottom = REPLY_PADDING_Y
	return style


## The hairline above the reply list.
static func divider() -> Panel:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = HudPalette.with_alpha(HudPalette.CYAN, DIVIDER_ALPHA)
	line.add_theme_stylebox_override("panel", style)
	return line

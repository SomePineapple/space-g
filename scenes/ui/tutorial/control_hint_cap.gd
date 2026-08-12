class_name ControlHintCap
extends Control

## One key-cap inside a ControlHint panel: the glyph, the slow "press me" glow it
## wears until the player does, and the confirmed state it settles into
## afterwards (docs/design_handoff_controls_tutorial/README.md, "Key formation").
##
## Its own node rather than something the panel draws, because each cap flips to
## pressed independently while its neighbours carry on pulsing — a WASD hint is
## four of these in four different states.

## The handoff's 56px cap, scaled with the rest of the panel (see
## ControlHint's layout block).
const SIZE: Vector2 = Vector2(40.0, 40.0)
## Anything longer than a couple of glyphs ("SPACE", "SHIFT") gets the handoff's
## wide cap instead of a square one, so the label is never squeezed.
const WIDE_SIZE: Vector2 = Vector2(144.0, 40.0)
const WIDE_ABOVE_LENGTH: int = 2

const RADIUS: int = 6
const GLYPH_SIZE: int = 14
const WIDE_GLYPH_SIZE: int = 11
const WIDE_TRACKING: float = 0.1
const EMBOLDEN: float = 0.6

const UNPRESSED_TEXT: Color = Color(0.5608, 0.6275, 0.6706)  # 8fa0ab
const UNPRESSED_FILL_ALPHA: float = 0.06
const UNPRESSED_BORDER_ALPHA: float = 0.3
const PRESSED_FILL_ALPHA: float = 0.2

## The waiting glow, as the handoff's CSS keyframe expressed in StyleBox terms:
## a shadow that grows from nothing to PULSE_SPREAD while fading from
## PULSE_ALPHA to nothing, once every PULSE_SECONDS.
const PULSE_SECONDS: float = 1.8
const PULSE_SPREAD: float = 4.0
const PULSE_ALPHA: float = 0.35
## A pressed cap stops pulsing and keeps a constant halo instead — the animation
## is an invitation, and it has been accepted.
const PRESSED_SPREAD: float = 7.0
const PRESSED_ALPHA: float = 0.3

var _glyph_text: String = ""
var _confirmed: bool = false
var _elapsed: float = 0.0
var _panel: Panel
var _glyph: Label
var _badge: Label


## Built through a factory rather than instantiated and configured, so the cap
## knows its own text before _ready decides how wide it has to be.
static func create(glyph_text: String) -> ControlHintCap:
	var cap := ControlHintCap.new()
	cap._glyph_text = glyph_text
	return cap


func _ready() -> void:
	var wide: bool = _glyph_text.length() > WIDE_ABOVE_LENGTH
	custom_minimum_size = WIDE_SIZE if wide else SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_glyph = DialogueStyle.label(_glyph_text,
		WIDE_GLYPH_SIZE if wide else GLYPH_SIZE, UNPRESSED_TEXT,
		WIDE_TRACKING if wide else 0.0)
	_glyph.add_theme_font_override("font", _bold_mono(
		WIDE_GLYPH_SIZE if wide else GLYPH_SIZE, WIDE_TRACKING if wide else 0.0))
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glyph)

	# Hangs off the cap's top-right corner, outside it, so it reads as a stamp on
	# the key rather than as part of the label.
	_badge = DialogueStyle.label("✓", 10, HudPalette.CYAN_BRIGHT)
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.offset_left = -6.0
	_badge.offset_top = -10.0
	_badge.visible = false
	add_child(_badge)

	_refresh()


func confirm() -> void:
	if _confirmed:
		return
	_confirmed = true
	_badge.visible = true
	_glyph.add_theme_color_override("font_color", HudPalette.CYAN_BRIGHT)
	_refresh()


func is_confirmed() -> bool:
	return _confirmed


func _process(delta: float) -> void:
	if _confirmed:
		set_process(false)
		return
	_elapsed += delta
	_refresh()


## Rebuilds the StyleBox each frame while pulsing. Cheap — one cap, one box —
## and the alternative (tweening a stored box) hides the whole animation in
## setup code away from the constants that describe it.
func _refresh() -> void:
	if _panel == null:
		return
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS)
	style.set_border_width_all(1)
	if _confirmed:
		style.bg_color = HudPalette.with_alpha(HudPalette.CYAN, PRESSED_FILL_ALPHA)
		style.border_color = HudPalette.CYAN
		style.shadow_size = int(PRESSED_SPREAD)
		style.shadow_color = HudPalette.with_alpha(HudPalette.CYAN, PRESSED_ALPHA)
	else:
		style.bg_color = HudPalette.with_alpha(HudPalette.CYAN, UNPRESSED_FILL_ALPHA)
		style.border_color = HudPalette.with_alpha(HudPalette.CYAN, UNPRESSED_BORDER_ALPHA)
		var phase: float = fmod(_elapsed, PULSE_SECONDS) / PULSE_SECONDS
		style.shadow_size = int(PULSE_SPREAD * phase)
		style.shadow_color = HudPalette.with_alpha(HudPalette.CYAN,
			PULSE_ALPHA * (1.0 - phase))
	_panel.add_theme_stylebox_override("panel", style)


## The handoff asks for bold monospace. DialogueStyle.mono covers tracking but
## not weight, and the project's font is resolved from the OS rather than shipped
## (see BuilderTheme.mono_font), so the weight has to come from a variation.
func _bold_mono(font_size: int, tracking: float) -> Font:
	var variation := FontVariation.new()
	variation.base_font = BuilderTheme.mono_font()
	variation.variation_embolden = EMBOLDEN
	variation.spacing_glyph = roundi(tracking * float(font_size))
	return variation

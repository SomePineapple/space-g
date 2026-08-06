class_name HudPalette
extends RefCounted

## Single source for the gameplay HUD's colour scheme (docs/HUD-1d-Godot-spec.md).
## Hex values from the spec are written out as floats because GDScript `const`
## can't fold Color("rrggbb") — the hex is kept in the comment on each line.
##
## Material dot colours are deliberately NOT here: those come from
## MaterialCatalog.color() so the HUD can never drift from the cargo, trade
## and crafting panels, which already read the catalog.

const PANEL_FILL: Color = Color(0.0902, 0.1137, 0.1412)  # 171d24
const BAR_FILL: Color = Color(0.0706, 0.0863, 0.1098)  # 12161c
const GLASS_FILL: Color = Color(0.0588, 0.0745, 0.0941)  # 0f1318

const CYAN: Color = Color(0.3333, 0.8392, 0.9098)  # 55d6e8
const CYAN_BRIGHT: Color = Color(0.5608, 0.9137, 0.9490)  # 8fe9f2
const CYAN_DARK: Color = Color(0.1647, 0.5608, 0.6392)  # 2a8fa3

const HEALTH_GOOD: Color = Color(0.4863, 0.9098, 0.7216)  # 7ce8b8
const HEALTH_WARNING: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e
const HEALTH_CRITICAL: Color = Color(0.8863, 0.4078, 0.2902)  # e2684a

const TEXT: Color = Color(0.9098, 0.9294, 0.9412)  # e8edf0
const TEXT_DIM: Color = Color(0.4863, 0.5451, 0.6000)  # 7c8b99
const LIST_NAME: Color = Color(0.7804, 0.8157, 0.8471)  # c7d0d8
const LIST_QTY: Color = Color(0.9490, 0.9608, 0.9647)  # f2f5f6

## Every HUD widget hangs the same distance off its screen corner.
const CORNER_MARGIN: float = 24.0


## Health tint thresholds from the spec: >50% good, >20% warning, else critical.
static func health_color(fraction: float) -> Color:
	if fraction > 0.5:
		return HEALTH_GOOD
	if fraction > 0.2:
		return HEALTH_WARNING
	return HEALTH_CRITICAL


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


## "1240" -> "1,240". Used by the credits readout and cargo counts.
static func group_digits(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out

class_name UpgradePalette
extends RefCounted

## Hue-driven colour derivation for the upgrade-tree screen
## (docs/design_handoff_upgrade_tree/README.md is the source of truth).
##
## The handoff authors every category and branch colour as a single OKLCH hue
## angle and derives the whole family from it (`oklch(0.78 0.14 H)` bright,
## `oklch(0.4 0.06 H)` deep, and so on). Godot's Color has no OKLCH
## constructor, so the conversion is done here once and the hue numbers stay
## as data — adding a branch colour is still just a number.
##
## Surfaces, text and generic StyleBoxes come from BuilderTheme: this is the
## companion screen to the ship builder and deliberately shares its palette.

# --- OKLCH pairs from the handoff's "Design tokens" -------------------------
const BRIGHT_L: float = 0.78
const BRIGHT_C: float = 0.14
const DEEP_L: float = 0.40
const DEEP_C: float = 0.06

## Category key (as used by UpgradeMenu's grouping) -> OKLCH hue angle. These
## are the handoff's own seven systems and its own numbers; the rail's
## top-level rows are exactly this list. "Other" is a game-only fallback for a
## module type that matches none of them, so nothing can be silently dropped.
const CATEGORY_HUES: Dictionary = {
	"Hull": 210.0,
	"Propulsion": 95.0,
	"Weapons": 35.0,
	"Power": 190.0,
	"Storage": 150.0,
	"Sensors": 255.0,
	"Mining": 60.0,
	"Other": 220.0,
}

const DEFAULT_HUE: float = 190.0


static func hue_for_category(category: String) -> float:
	return CATEGORY_HUES.get(category, DEFAULT_HUE)


## `oklch(0.78 0.14 H)` — node fill top stop, borders, active rail accent.
static func bright(hue: float, alpha: float = 1.0) -> Color:
	return oklch(BRIGHT_L, BRIGHT_C, hue, alpha)


## `oklch(0.4 0.06 H)` — node fill bottom stop.
static func deep(hue: float, alpha: float = 1.0) -> Color:
	return oklch(DEEP_L, DEEP_C, hue, alpha)


## Connector from an unlocked parent to a still-locked child.
static func connector_half(hue: float) -> Color:
	return oklch(0.70, 0.07, hue, 0.4)


## Connector between two unlocked nodes.
static func connector_full(hue: float) -> Color:
	return oklch(0.80, 0.10, hue, 0.8)


## Dashed tier guide arc.
static func tier_arc(hue: float) -> Color:
	return oklch(0.45, 0.05, hue, 0.22)


## The soft radial wash behind the tree, tinted to the active category.
static func field_glow(hue: float) -> Color:
	return oklch(0.40, 0.08, hue, 0.22)


## OKLCH -> sRGB. Standard Björn Ottosson conversion (OKLab inverse matrices)
## followed by the sRGB transfer function; out-of-gamut results are clamped,
## which is fine for the moderate chroma values used here.
static func oklch(lightness: float, chroma: float, hue_degrees: float, alpha: float = 1.0) -> Color:
	var hue_radians: float = deg_to_rad(hue_degrees)
	var a: float = chroma * cos(hue_radians)
	var b: float = chroma * sin(hue_radians)

	var long_root: float = lightness + 0.3963377774 * a + 0.2158037573 * b
	var medium_root: float = lightness - 0.1055613458 * a - 0.0638541728 * b
	var short_root: float = lightness - 0.0894841775 * a - 1.2914855480 * b

	var l: float = long_root * long_root * long_root
	var m: float = medium_root * medium_root * medium_root
	var s: float = short_root * short_root * short_root

	return Color(
		_to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		_to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		_to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
		alpha)


static func _to_srgb(linear: float) -> float:
	var value: float = 12.92 * linear if linear <= 0.0031308 else 1.055 * pow(maxf(linear, 0.0), 1.0 / 2.4) - 0.055
	return clampf(value, 0.0, 1.0)

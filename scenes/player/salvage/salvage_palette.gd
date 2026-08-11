class_name SalvagePalette
extends RefCounted

## Colours, the slag cooling ramp and the shared additive material for the
## salvage beam (docs/design_salvage/salvage-beam-Godot-spec.md).
##
## Hex values from the spec are written out as floats because GDScript `const`
## cannot fold Color("rrggbb"); the hex is kept in the comment on each line, same
## convention as HudPalette.
##
## Several of these are deliberately pushed past 1.0. The project renders with
## `hdr_2d` on, so a colour above white is what the glow pass picks up — without
## it the additive core reads as a flat white line and the effect loses most of
## its punch (spec §Glow).

const BEAM_CORE: Color = Color(1.0, 0.9647, 0.8627)  # fff6dc
const BEAM_SHEATH: Color = Color(0.5608, 0.9137, 0.9490)  # 8fe9f2
const WARM_NODE: Color = Color(0.9490, 0.7569, 0.3059)  # f2c14e
const VENT: Color = Color(0.7255, 0.8039, 0.8471)  # b9cdd8

## HDR multipliers from the spec's colour table.
const CORE_GAIN: float = 2.5
const SHEATH_GAIN: float = 1.6

## The slag ramp, sampled with `age_seconds / SLAG_COOL_SECONDS` clamped to 0..1.
## Offsets below are that normalised position, with the spec's seconds alongside.
const SLAG_COOL_SECONDS: float = 3.0
const SLAG_STOPS: Array[float] = [0.0, 0.05, 0.20, 0.50, 1.0]
const SLAG_COLORS: Array[Color] = [
	Color(1.0, 0.9647, 0.8627),  # fff6dc   0.00s
	Color(1.0, 0.9647, 0.8627),  # fff6dc   0.15s
	Color(1.0, 0.8510, 0.6275),  # ffd9a0   0.60s
	Color(1.0, 0.5412, 0.2353),  # ff8a3c   1.50s
	Color(0.7882, 0.2902, 0.0706),  # c94a12  3.00s
]
## Past the ramp the metal is cold slag and simply stays there.
const SLAG_COLD: Color = Color(0.3686, 0.1686, 0.0784)  # 5e2b14

static var _slag_gradient: Gradient
## One material for every additive layer in the effect. Building a
## CanvasItemMaterial per line forces a fresh renderer pipeline setup each time,
## which is a measurable hitch — see BeamVisual, which cached one for the same
## reason.
static var _additive: CanvasItemMaterial


static func slag_gradient() -> Gradient:
	if _slag_gradient == null:
		_slag_gradient = Gradient.new()
		_slag_gradient.offsets = PackedFloat32Array(SLAG_STOPS)
		_slag_gradient.colors = PackedColorArray(SLAG_COLORS)
	return _slag_gradient


## Colour of a cut edge `age` seconds after the beam passed over it.
static func slag_color(age: float) -> Color:
	if age >= SLAG_COOL_SECONDS:
		return SLAG_COLD
	return slag_gradient().sample(clampf(age / SLAG_COOL_SECONDS, 0.0, 1.0))


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## A colour scaled past white for the glow pass to catch.
static func hdr(color: Color, gain: float, alpha: float = 1.0) -> Color:
	return Color(color.r * gain, color.g * gain, color.b * gain, alpha)

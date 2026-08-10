class_name LaserPalette
extends RefCounted

## What colour a given laser fires. Pure data and pure functions.
##
## Colour is a property of the *gun*, not of the ship carrying it: a pirate
## cannon cut off a raider keeps firing pirate red after it is bolted onto a
## corporate hull. That is the same rule the plating and turret art follow (see
## HullPaint.art_faction_for), and it is most of the point — a mongrel ship
## should visibly fire a mongrel spread of colours.
##
## Which entry of a faction's palette a particular gun uses is fixed for the life
## of that gun, derived from its instance id. Rolling per shot would make a
## single weapon strobe; rolling per faction would make every pirate identical.
## This way two pirate cannons on the same hull can fire different colours and
## each stays itself.

## Three per faction, chosen to stay distinguishable from each other at speed
## while still reading as one civilisation's equipment.
const FACTION_LASERS: Dictionary = {
	"corporate": [
		Color(0.45, 0.78, 1.00),  # light blue
		Color(0.16, 0.36, 1.00),  # deep blue
		Color(0.90, 0.97, 1.00),  # near-white
	],
	"pirate": [
		Color(1.00, 0.20, 0.12),  # red
		Color(1.00, 0.48, 0.08),  # orange
		Color(1.00, 0.82, 0.15),  # yellow
	],
	"ancient": [
		Color(0.72, 0.35, 1.00),  # violet
		Color(0.30, 1.00, 0.82),  # cyan-green
		Color(0.95, 0.42, 1.00),  # magenta
	],
}

## Used by anything with no faction palette of its own.
const DEFAULT_LASERS: Array = [
	Color(0.55, 0.90, 1.00),
	Color(0.80, 0.95, 1.00),
]

## How far past white a bolt is pushed so the glow pass actually catches it.
##
## Requires rendering/viewport/hdr_2d, without which canvas colour clamps at 1.0
## and only near-white pixels ever bloom — which is why lasers read as flat
## shapes rather than as light. Everything else in the game is authored at or
## below 1.0 and so is untouched by this; the bolts are deliberately the only
## thing bright enough to bloom hard.
const HDR_GAIN: float = 3.2
## The dimmer halo drawn under the core of a bolt, as a share of HDR_GAIN.
const HALO_GAIN_FRACTION: float = 0.35
const HALO_ALPHA: float = 0.5

## Salt for the stable per-gun pick, distinct from the ones HullPaint uses for
## jitter so a part's colour and its nudge are not correlated.
const PALETTE_SALT: int = 41


## The palette a faction fires in, falling back rather than returning empty.
static func palette_for(faction_id: String) -> Array:
	var palette: Variant = FACTION_LASERS.get(faction_id)
	return palette if palette != null else DEFAULT_LASERS


## The base (non-HDR) colour this specific gun fires — what the barrel and any
## UI should use, since neither wants a value above white.
static func base_color(instance: ModuleInstance, hull_faction_id: String) -> Color:
	var palette: Array = palette_for(HullPaint.art_faction_for(instance, hull_faction_id))
	return palette[HullPaint.stable_index(instance, PALETTE_SALT, palette.size())]


## The bolt colour itself, pushed past white so it blooms.
static func bolt_color(instance: ModuleInstance, hull_faction_id: String) -> Color:
	return _gained(base_color(instance, hull_faction_id), HDR_GAIN, 1.0)


## The soft halo drawn under the bolt.
static func halo_color(instance: ModuleInstance, hull_faction_id: String) -> Color:
	return _gained(base_color(instance, hull_faction_id),
		HDR_GAIN * HALO_GAIN_FRACTION, HALO_ALPHA)


## Multiplies the colour channels only — scaling a Color scales its alpha too,
## which would make a boosted bolt opaque-by-accident and a halo invisible.
static func _gained(color: Color, gain: float, alpha: float) -> Color:
	return Color(color.r * gain, color.g * gain, color.b * gain, alpha)

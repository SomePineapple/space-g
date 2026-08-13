class_name HullScarPattern
extends RefCounted

## Generates one module's battle damage as a list of atlas decals
## (`docs/scar_layer/SCAR_IMPLEMENTATION.md`).
##
## Pure data: it knows nothing about nodes, meshes or clipping — it is handed a
## seed, the module's tile centres and a scale, and returns where every mark
## goes. HullScarLayer turns that into geometry.
##
## **Append-only.** The whole feature list is always generated at the maximum
## tier and each feature tagged with the tier it first appears at; the layer
## draws everything at or below the current tier. That is what keeps a scar
## frozen: the RNG draw order is identical however damaged the part is, so
## tier 3 contains tier 1 and 2 exactly where the player last saw them. Nothing
## here may branch on the current tier.

## Atlas regions, in the 800x400 sheet's own pixels. Every mark was re-authored
## ~1.5x larger than the first pass so it reads at zoomed-out camera distances;
## the sizes below are the art's own, and the marks are drawn at them.
const CRATER_CORE: Rect2 = Rect2(0, 0, 144, 144)
const CRATER_RIM: Rect2 = Rect2(144, 0, 168, 168)
const HEAT_RIM: Rect2 = Rect2(312, 0, 192, 192)
const SOOT_BLOB: Rect2 = Rect2(504, 0, 288, 288)
const CRACK_SEGMENT: Rect2 = Rect2(0, 288, 192, 36)
const CRACK_BRANCH: Rect2 = Rect2(204, 288, 96, 72)
const WELD_PLATE: Rect2 = Rect2(312, 288, 96, 48)
const POCK: Rect2 = Rect2(408, 288, 48, 48)
const EMBER: Rect2 = Rect2(456, 288, 24, 24)

const ATLAS_SIZE: Vector2 = Vector2(800, 400)

## The atlas is authored against a 222x256 hex tile, so every pixel figure in
## the spec is scaled by this before it is used.
const TILE_HEIGHT: float = 256.0

enum Tier {NONE, SCUFFED, BREACHED, PATCHED, VETERAN}

## Every mark is drawn at the size the atlas authors it. Nothing here scales art
## up: the re-authored sheet carries its own weight, and an earlier pass that
## thickened cracks and drew a lit lip beside each one — needed when they were
## near-black hairlines on near-black plating — went out with the art it propped up.

## How far along its own length each crack segment advances before the next one
## starts. Slightly less than a full length, so a run reads as one crack rather
## than as a dotted line of them.
const CRACK_OVERLAP: float = 0.88

## One mark. `heat` marks are the additive fresh-hit layer and are drawn by a
## separate pass that fades them out; everything else is the cold scar and never
## changes once drawn.
class ScarDecal extends RefCounted:
	var region: Rect2
	var centre: Vector2
	var rotation: float
	## Full width/height in local pixels, before clipping.
	var size: Vector2
	var alpha: float
	var tier: int
	var heat: bool

	func _init(region_rect: Rect2, at: Vector2, angle: float, extent: Vector2,
			opacity: float, at_tier: int, is_heat: bool = false) -> void:
		region = region_rect
		centre = at
		rotation = angle
		size = extent
		alpha = opacity
		tier = at_tier
		heat = is_heat


## Same string in, same scar out, on every machine and every load.
static func fnv1a(text: String) -> int:
	var hash_value: int = 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = (hash_value ^ byte) * 16777619 & 0xFFFFFFFF
	return hash_value


## `tile_centres` are the module's hex centres in the hull's own space, and
## `cell_size` is the hull's hex radius — the spec's tile pixels are converted
## through it, so scars stay the same size relative to the plating at any zoom.
static func generate(seed_text: String, tile_centres: Array[Vector2],
		cell_size: float) -> Array:
	var decals: Array = []
	if tile_centres.is_empty():
		return decals

	var rng := RandomNumberGenerator.new()
	rng.seed = fnv1a(seed_text)
	# Atlas pixels -> hull pixels. A hex is 2 * cell_size tall and the atlas
	# tile is 256, so this is the only conversion needed anywhere below.
	var unit: float = cell_size * 2.0 / TILE_HEIGHT

	# Where the hull was hit, and from where. The angle comes from the upper
	# left because that is the hull's light direction — streaks lie along it.
	var impact_tile: int = rng.randi_range(0, tile_centres.size() - 1)
	var impact: Vector2 = tile_centres[impact_tile] + Vector2(
		rng.randf_range(-35.0, 35.0), rng.randf_range(-40.0, 40.0)) * unit
	var angle: float = -2.5 + rng.randf() * 0.5

	_add_soot(decals, rng, tile_centres, impact_tile, unit)
	_add_streaks(decals, rng, impact, angle, unit, 4, Tier.SCUFFED)
	_add_pocks(decals, rng, tile_centres, angle, unit, 2, Tier.SCUFFED)

	var severity: float = rng.randf_range(1.2, 1.8)
	var radius: float = (44.0 + 30.0 * severity) * unit
	_add_breach(decals, rng, tile_centres, impact_tile, impact, radius, unit, Tier.BREACHED)
	_add_streaks(decals, rng, impact, angle, unit, 3, Tier.BREACHED)
	_add_pocks(decals, rng, tile_centres, angle, unit, 1, Tier.BREACHED)
	_add_pocks(decals, rng, tile_centres, angle, unit, 2, Tier.PATCHED)

	# The second breach is somewhere else entirely — a veteran hull has been hit
	# more than once, and two craters in the same tile would read as one.
	var second_tile: int = (impact_tile + rng.randi_range(1, maxi(tile_centres.size() - 1, 1))) \
		% tile_centres.size()
	var second: Vector2 = tile_centres[second_tile] + Vector2(
		rng.randf_range(-35.0, 35.0), rng.randf_range(-40.0, 40.0)) * unit
	_add_breach(decals, rng, tile_centres, second_tile, second, radius * 0.7, unit, Tier.VETERAN)
	_add_streaks(decals, rng, second, angle, unit, 2, Tier.VETERAN)
	_add_pocks(decals, rng, tile_centres, angle, unit, 1, Tier.VETERAN)
	return decals


## Bloom over the whole footprint: full strength on the tile that was hit, half
## on the rest, so a multi-hex part darkens toward the impact.
static func _add_soot(decals: Array, rng: RandomNumberGenerator,
		tile_centres: Array[Vector2], impact_tile: int, unit: float) -> void:
	for i in tile_centres.size():
		var span: float = SOOT_BLOB.size.x * unit
		decals.append(ScarDecal.new(SOOT_BLOB, tile_centres[i], rng.randf() * TAU,
			Vector2(span, span), 1.0 if i == impact_tile else 0.5, Tier.SCUFFED))


## Scorch streaks. The atlas has no streak of its own — a pock stretched hard
## along the impact vector is what the spec's own placement rule (§6, "squashed
## 1.5-2.8x along the impact vector") produces, so streaks are the far end of
## that same squash rather than a second piece of art.
static func _add_streaks(decals: Array, rng: RandomNumberGenerator, from: Vector2,
		angle: float, unit: float, count: int, tier: int) -> void:
	for i in count:
		var reach: float = rng.randf_range(30.0, 110.0) * unit
		var length: float = rng.randf_range(45.0, 90.0) * unit
		var spread: float = rng.randf_range(-0.35, 0.35)
		var along: Vector2 = Vector2.RIGHT.rotated(angle + spread)
		decals.append(ScarDecal.new(POCK, from + along * reach, angle + spread,
			Vector2(length, rng.randf_range(5.0, 9.0) * unit),
			rng.randf_range(0.35, 0.6), tier))


static func _add_pocks(decals: Array, rng: RandomNumberGenerator,
		tile_centres: Array[Vector2], angle: float, unit: float, per_tile: int,
		tier: int) -> void:
	for centre in tile_centres:
		for i in per_tile:
			var offset: Vector2 = Vector2(rng.randf_range(-88.0, 88.0),
				rng.randf_range(-88.0, 88.0)) * unit
			var radius: float = rng.randf_range(5.0, 17.0) * unit
			var squash: float = rng.randf_range(1.5, 2.8)
			decals.append(ScarDecal.new(POCK, centre + offset, angle,
				Vector2(radius * 2.0 * squash, radius * 2.0),
				rng.randf_range(0.45, 0.8), tier))


## A breach and everything that spreads from it: the cooled ring, the crater,
## a crack run to every other tile of the footprint, the plate welded over each
## run, and — one tier later — the split through that plate.
static func _add_breach(decals: Array, rng: RandomNumberGenerator,
		tile_centres: Array[Vector2], impact_tile: int, impact: Vector2,
		radius: float, unit: float, tier: int) -> void:
	decals.append(ScarDecal.new(CRATER_RIM, impact, rng.randf() * TAU,
		Vector2.ONE * radius * 2.3, 0.85, tier))
	decals.append(ScarDecal.new(CRATER_CORE, impact, rng.randf() * TAU,
		Vector2.ONE * radius * 2.0, 1.0, tier))
	# The heat pass reuses this transform exactly, so the glow sits on the
	# crater rather than near it.
	decals.append(ScarDecal.new(HEAT_RIM, impact, rng.randf() * TAU,
		Vector2.ONE * radius * 2.6, 1.0, tier, true))
	for i in rng.randi_range(8, 12):
		var throw: float = radius * rng.randf_range(0.9, 2.8)
		var spark: float = rng.randf_range(4.0, 9.0) * unit
		decals.append(ScarDecal.new(EMBER, impact + Vector2.RIGHT.rotated(rng.randf() * TAU) * throw,
			0.0, Vector2.ONE * spark, 1.0, tier, true))

	for i in tile_centres.size():
		if i == impact_tile:
			continue
		_add_crack_run(decals, rng, impact, tile_centres[i], radius, unit, tier)


static func _add_crack_run(decals: Array, rng: RandomNumberGenerator, impact: Vector2,
		toward: Vector2, radius: float, unit: float, tier: int) -> void:
	var heading: float = (toward - impact).angle() + rng.randf_range(-0.15, 0.15)
	var run: float = impact.distance_to(toward) * rng.randf_range(0.75, 1.15)
	var step: float = CRACK_SEGMENT.size.x * unit
	var thickness: float = CRACK_SEGMENT.size.y * unit
	var walked: float = radius
	var at: Vector2 = impact + Vector2.RIGHT.rotated(heading) * radius
	while walked < run:
		heading += rng.randf_range(-0.1, 0.1)
		var along: Vector2 = Vector2.RIGHT.rotated(heading)
		var centre: Vector2 = at + along * step * 0.5
		decals.append(ScarDecal.new(CRACK_SEGMENT, centre, heading,
			Vector2(step, thickness), 1.0, tier))
		# Hairline forks come a tier later than the run they fork off.
		if rng.randf() < 0.35:
			decals.append(ScarDecal.new(CRACK_BRANCH, centre,
				heading + rng.randf_range(-1.2, 1.2), CRACK_BRANCH.size * unit, 0.95,
				mini(tier + 1, Tier.VETERAN)))
		at += along * step * CRACK_OVERLAP
		walked += step * CRACK_OVERLAP

	# The repair: a plate bolted over the run, stitched down either side, and
	# then — one tier on — split again. That progression is the whole point of
	# the patched/veteran pair.
	var patch_at: Vector2 = impact + Vector2.RIGHT.rotated(heading) * run * rng.randf_range(0.55, 0.75)
	var patch_tier: int = mini(tier + 1, Tier.VETERAN)
	decals.append(ScarDecal.new(WELD_PLATE, patch_at, heading,
		WELD_PLATE.size * unit, 0.95, patch_tier))
	# Stitches: short crack pieces laid across the plate, spaced by the spec's
	# 13px, scaled with the re-authored art like everything else.
	for i in 3:
		var across: Vector2 = Vector2.UP.rotated(heading) * (i - 1) * 13.0 * 1.5 * unit
		decals.append(ScarDecal.new(CRACK_SEGMENT, patch_at + across, heading + PI * 0.5,
			Vector2(27.0, 13.5) * unit, 0.9, patch_tier))
	# The split back through the patch: the mark that says the repair failed.
	decals.append(ScarDecal.new(CRACK_SEGMENT, patch_at,
		heading + rng.randf_range(-0.2, 0.2), Vector2(step * 0.8, thickness),
		1.0, Tier.VETERAN))

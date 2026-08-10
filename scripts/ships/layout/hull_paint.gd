class_name HullPaint
extends RefCounted

## How a hull built out of separate parts is shaded and jointed. Pure functions
## over layout and instance data — no drawing, no state.
##
## Extracted because two surfaces have to agree exactly: ShipLayoutRenderer
## draws the ship in the world, HexGridControl draws it in the builder, and a
## joint that welds in one and not the other would make the builder lie about
## what you are about to fly. The joint test was already duplicated across both
## before jitter and welds were added; four more copies was not worth it.
##
## None of this is authored into the art. A part can be joined on any of its six
## faces, so no drawn-in seam would ever line up — everything here is derived
## from the layout's own adjacency and from what each mounted part knows about
## itself.

# --- Provenance --------------------------------------------------------------

## Rough plate colour per faction, multiplied over the part's own art. These
## cannot lighten (a multiply never exceeds white), so they are picked as the
## warm/cool/violet cast each civilisation leaves on steel rather than as the
## literal colour of their plating.
const FACTION_TINTS: Dictionary = {
	"pirate": Color(1.0, 0.58, 0.34),
	"corporate": Color(0.78, 0.88, 1.0),
	# Deliberately the darkest of the three. At the lighter violet this started
	# at, ancient plating sat within 0.09 luminance of corporate slate, so the
	# boundary between them was the least legible on a mixed hull — and faction
	# has to read in a fraction of a second mid-fight, where hue alone doesn't
	# survive muzzle flash and thruster glare. Value carries it; hue confirms it.
	"ancient": Color(0.55, 0.34, 0.88),
}

## How far a part's tint is pulled toward its origin faction's colour. High
## enough that a foreign plate reads as foreign at a glance — at the 0.22 this
## started at, the shift was 4-7% per channel and effectively invisible.
const ORIGIN_TINT_STRENGTH: float = 0.5

## Brightness a part at zero condition is drawn at, relative to an intact one.
const WORN_SHADE: float = 0.55

## A part counts as healthy for the purpose of judging a joint above this much
## condition. Not 1.0: a graze shouldn't make every joint around it look bodged.
const HEALTHY_CONDITION: float = 0.85


## Whether two parts look like they were meant to go together: same provenance,
## and neither one beaten up. Anything else is a joint someone improvised.
##
## A part with no instance yet (a layout straight off disk, before rebuild()
## stamps one) counts as clean; the alternative is a brand new ship briefly
## rendering as a wreck.
static func is_clean_joint(a: ModulePlacement, b: ModulePlacement) -> bool:
	if a.instance == null or b.instance == null:
		return true
	if a.instance.origin_faction_id != b.instance.origin_faction_id:
		return false
	return a.instance.condition_fraction >= HEALTHY_CONDITION \
		and b.instance.condition_fraction >= HEALTHY_CONDITION


## The colour one part's art is multiplied by: darker the more beaten up it is,
## and cast toward its origin faction if it came off someone else's ship.
##
## Deliberately no random per-part variation. An intact factory part draws
## exactly as its art was authored, so a fresh hull looks manufactured and the
## contrast is still there to spend when the ship starts collecting salvage.
static func part_tint(placement: ModulePlacement, hull_faction_id: String) -> Color:
	var instance: ModuleInstance = placement.instance
	if instance == null:
		return Color.WHITE

	var tint: Color = Color.WHITE
	if instance.is_salvaged() and instance.origin_faction_id != hull_faction_id:
		var origin_tint: Variant = FACTION_TINTS.get(instance.origin_faction_id)
		if origin_tint != null:
			tint = tint.lerp(origin_tint, ORIGIN_TINT_STRENGTH)

	var shade: float = lerpf(WORN_SHADE, 1.0, clampf(instance.condition_fraction, 0.0, 1.0))
	return tint * Color(shade, shade, shade, 1.0)


# --- Hand-assembled alignment -------------------------------------------------

## Each part is nudged off its exact grid position by a fraction of a cell and a
## fraction of a degree. Machine-perfect alignment is most of what reads as
## stamped in one press; this is small enough to be invisible on any single part
## and is most of what makes a hull look bolted together by hand.
##
## It also opens the hairline gaps between parts that part_shadow_offset()'s
## shadow shows through — hexes tile exactly, so without this there is nowhere
## for a shadow between two parts to be seen.
##
## Expressed as a fraction of cell_size, since the builder draws the same ship
## at a much larger cell size than the world does and a fixed pixel nudge would
## vanish there.
##
## VISUAL ONLY. Collision shapes and impact resolution both run off the true
## grid coordinates (see HullDamageModel._spawn_collision_shape_for and
## damage_at), so a jittered part's drawn overhang is up to this far from where
## it can actually be shot. At this magnitude that is a sub-pixel band at the
## cell boundary; do not raise it far without moving collision with it.
const JITTER_OFFSET_FRACTION: float = 0.042
const JITTER_ROTATION_DEGREES: float = 1.0

## Where a part's shadow falls, as a fraction of cell_size. Down and right, in
## the hull's own space rather than the world's: this is the part sitting proud
## of the chassis, not scene lighting, so it must not swing around as the ship
## turns (and a world-space light would force a redraw every frame the ship
## rotates — the hull only redraws when its layout actually changes).
const SHADOW_OFFSET_FRACTION: float = 0.085
const SHADOW_COLOR: Color = Color(0.039, 0.055, 0.075, 0.55)


static func part_shadow_offset(cell_size: float) -> Vector2:
	return Vector2(SHADOW_OFFSET_FRACTION, SHADOW_OFFSET_FRACTION * 1.3) * cell_size


## Stable per-part nudge, derived from the instance id so a part sits exactly
## where it sat last time — a fresh roll per rebuild would make the whole ship
## shimmer every time a module was placed or destroyed. String.hash() is stable
## for a given string on every machine, and this is presentation anyway.
static func part_offset(instance: ModuleInstance, cell_size: float) -> Vector2:
	if instance == null:
		return Vector2.ZERO
	var seed_value: int = instance.instance_id.hash()
	return Vector2(_signed_unit(seed_value, 1), _signed_unit(seed_value, 2)) \
		* JITTER_OFFSET_FRACTION * cell_size


static func part_rotation(instance: ModuleInstance) -> float:
	if instance == null:
		return 0.0
	return deg_to_rad(_signed_unit(instance.instance_id.hash(), 3) * JITTER_ROTATION_DEGREES)


## A -1..1 value per (part, purpose). The avalanche step is not decoration:
## instance ids differ only in a trailing ordinal ("mi_4271_7" vs "mi_4271_8"),
## and String.hash() maps those to neighbouring values, so slicing its raw bits
## gave two consecutive parts offsets differing in the third decimal — a jitter
## nobody could see. Mixing first decorrelates them.
static func _signed_unit(seed_value: int, salt: int) -> float:
	var mixed: int = seed_value + salt * 0x9E3779B9
	mixed = (mixed ^ (mixed >> 16)) * 0x7FEB352D
	mixed = (mixed ^ (mixed >> 15)) * 0x846CA68B
	mixed = mixed ^ (mixed >> 16)
	return float(mixed & 0xFFFF) / 32767.5 - 1.0


## The part's own centre, which its rotation nudge turns about — rotating a
## multi-hex part about the origin instead would swing its far cells right off
## their neighbours.
static func part_centroid(layout: ShipLayout, placement: ModulePlacement, cell_size: float) -> Vector2:
	var cells: Array[Vector2i] = layout.get_occupied_cells(placement)
	if cells.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for cell in cells:
		total += HexUtils.axial_to_pixel(cell, cell_size)
	return total / cells.size()


static func jittered_corners(corners: PackedVector2Array, centroid: Vector2,
		offset: Vector2, rotation: float) -> PackedVector2Array:
	var moved := PackedVector2Array()
	moved.resize(corners.size())
	for i in corners.size():
		moved[i] = centroid + (corners[i] - centroid).rotated(rotation) + offset
	return moved


# --- Welds --------------------------------------------------------------------

## A joint between mismatched parts is not drawn as a line along the seam. A
## continuous, uniform-width stroke on every edge of a part traces a closed ring
## around it, which is selection-highlight language, not metal — and once most
## of a hull is salvage, every joint bodges and the whole ship ends up outlined.
##
## Instead: three short ticks with wide gaps, each with a bolt across it.
## Short, interrupted and repeated is what reads as something welded on.
##
## The coverage figure is the thing to tune, not the tick count. Two dashes
## covering 52% of the edge still left a long enough painted fraction that a run
## of adjacent welded seams — which is what a two-cell-wide limb of mismatched
## parts is — closed back up into a continuous stroke tracing the limb. At 36%
## across three ticks the gaps win and the run stays a row of marks. Raising this
## far will bring the stroke back.
const WELD_DASH_SPANS: Array[float] = [0.12, 0.24, 0.44, 0.56, 0.76, 0.88]
const WELD_BOLT_POSITIONS: Array[float] = [0.18, 0.82]
const WELD_BOLT_HALF_LENGTH: float = 0.09


## Appends this seam's weld dashes to `dashes` and its bolt marks to `bolts`,
## both as flat point pairs ready for draw_multiline().
static func append_weld(from: Vector2, to: Vector2, dashes: PackedVector2Array,
		bolts: PackedVector2Array) -> void:
	var span: Vector2 = to - from
	var across: Vector2 = span.orthogonal()

	for i in range(0, WELD_DASH_SPANS.size(), 2):
		dashes.append(from + span * WELD_DASH_SPANS[i])
		dashes.append(from + span * WELD_DASH_SPANS[i + 1])

	for position in WELD_BOLT_POSITIONS:
		var centre: Vector2 = from + span * position
		bolts.append(centre - across * WELD_BOLT_HALF_LENGTH)
		bolts.append(centre + across * WELD_BOLT_HALF_LENGTH)

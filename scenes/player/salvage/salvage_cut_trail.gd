class_name SalvageCutTrail
extends Node2D

## The glowing seam the beam leaves behind as its contact point walks the hex
## perimeter, cooling from white through orange to cold slag
## (docs/design_salvage/salvage-beam-Godot-spec.md §Cut line).
##
## Parented to the TARGET ship, in that ship's local space, for two reasons the
## spec calls out: the seam has to stay put on a hull that is moving and turning,
## and it must survive the tile being cut away so the socket rim on the parent
## ship keeps cooling afterwards. Freeing it with the beam would take the mark
## with it.
##
## Not additive. A cooling cut is hot metal, not light — additive slag stayed
## bright against the dark hull instead of going out.

## Point spacing along the perimeter, as a fraction of it. The spec asks for a
## point roughly every 1/150 of the perimeter.
const POINT_SPACING: float = 1.0 / 150.0
## Width while a point is still glowing, and after it has cooled past that.
const HOT_WIDTH: float = 3.4
const COOL_WIDTH: float = 2.6
const HOT_SECONDS: float = 0.6

## Colour along the seam is carried by a Gradient rather than per-point colours:
## Godot 4's Line2D has no set_point_color, it shades along its length from this.
## The same Gradient object is rewritten in place every frame — allocating a new
## one per frame is the render-resource construction docs/performance.md is about.
const GRADIENT_STOPS: int = 24

var _line: Line2D
var _gradient: Gradient
var _ages: PackedFloat32Array = PackedFloat32Array()
## Perimeter fraction already laid down, so re-entering the same cut appends
## rather than restarting.
var _laid: float = 0.0


func _ready() -> void:
	_line = Line2D.new()
	_line.width = HOT_WIDTH
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_gradient = Gradient.new()
	_line.gradient = _gradient
	add_child(_line)


## Lays the seam out to `progress` (0..1 around the hex). `corners` are the hex's
## six vertices in this node's own space.
func advance(corners: PackedVector2Array, progress: float) -> void:
	while _laid < progress:
		_laid = minf(_laid + POINT_SPACING, progress)
		_line.add_point(_perimeter_point(corners, _laid))
		_ages.append(0.0)
		# Stop if the spacing cannot advance (guards a zero-size hex).
		if POINT_SPACING <= 0.0:
			break


func _process(delta: float) -> void:
	if _line.get_point_count() == 0:
		return
	var any_hot: bool = false
	for i in _ages.size():
		_ages[i] += delta
		if _ages[i] < SalvagePalette.SLAG_COOL_SECONDS:
			any_hot = true

	# Sample the ages into a fixed number of gradient stops. Ages fall off
	# monotonically from the head backwards, so a gradient along the line is an
	# exact fit rather than an approximation.
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var last: int = _ages.size() - 1
	for stop in GRADIENT_STOPS:
		var u: float = float(stop) / float(GRADIENT_STOPS - 1)
		offsets.append(u)
		colors.append(SalvagePalette.slag_color(_ages[roundi(u * float(last))]))
	_gradient.offsets = offsets
	_gradient.colors = colors

	# The head is the only part still wide; once everything is cold the line stops
	# needing per-frame work and the whole node goes idle.
	_line.width = HOT_WIDTH if _ages[last] < HOT_SECONDS else COOL_WIDTH
	if not any_hot:
		set_process(false)


## Where `t` (0..1) falls along the hex perimeter, walking edge by edge.
static func _perimeter_point(corners: PackedVector2Array, t: float) -> Vector2:
	var edges: int = corners.size()
	var scaled: float = clampf(t, 0.0, 1.0) * float(edges)
	var index: int = mini(int(scaled), edges - 1)
	return corners[index].lerp(corners[(index + 1) % edges], scaled - float(index))


## Public because the beam's contact point has to land on the same place the
## seam is being drawn — if the two disagree, the beam visibly cuts somewhere
## other than where the mark appears.
static func perimeter_point(corners: PackedVector2Array, t: float) -> Vector2:
	return _perimeter_point(corners, t)

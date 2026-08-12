class_name GrappleChain
extends Node2D

## How the grapple line looks. GrappleRope decides where the points are; this
## draws them (docs/design_handoff_grapple/grapple-line-Godot-spec.md, "Node
## tree" and the paragraph under it).
##
## Four stacked passes over the same polyline — a dark outline that separates the
## chain from the hull behind it, the chain body, a bright highlight whose alpha
## rides the line's tension, and above 55% tension an additive cyan pass that is
## the whole "this line is loaded" read. That last pass only does anything with
## HDR glow on, which this project already runs (see SalvagePalette).
##
## The links are one MultiMesh, not one draw per link: a 64-node line is 63
## ellipses and docs/performance.md's rule is that the 2D renderer batches
## nothing across separate draw commands. Alternating each link between fat and
## flat is what makes it read as chain rather than as a rope — drop the link pass
## entirely and the three strokes alone give the cable variant.

const OUTLINE_COLOR: Color = Color(0.0627, 0.0784, 0.1020)  # 10141a
const BODY_COLOR: Color = Color(0.2314, 0.2784, 0.3255)  # 3b4753
const CORE_COLOR: Color = Color(0.5412, 0.6000, 0.6588)  # 8a99a8

const OUTLINE_WIDTH: float = 6.0
const BODY_WIDTH: float = 4.2
const CORE_WIDTH: float = 1.8
const STRAIN_WIDTH: float = 2.2

## Tension at which the loaded-line glow starts, and how fast it comes up past
## that point — spec: `alpha = (tension - 0.55) * 0.9`.
const STRAIN_THRESHOLD: float = 0.55
const STRAIN_ALPHA_GAIN: float = 0.9

## One ellipse per segment, at the segment midpoint, rotated to the segment
## angle: 6.2 x 3.4 alternating with 6.2 x 1.5.
const LINK_LENGTH: float = 6.2
const LINK_THICK: float = 3.4
const LINK_THIN: float = 1.5
## Sides of the unit ellipse the MultiMesh instances. Twelve is plenty at the
## three or four pixels these actually cover on screen.
const LINK_SIDES: int = 12

## Three-prong claw, drawn rather than sprited (this project has no hook art).
## Local +x points the way the hook is travelling, so the prongs splay back
## toward the line.
const HOOK_SHAFT: Vector2 = Vector2(-7.0, 0.0)
const HOOK_HUB: Vector2 = Vector2(1.0, 0.0)
const HOOK_PRONGS: Array[Vector2] = [Vector2(9.0, 0.0), Vector2(5.0, -5.0), Vector2(5.0, 5.0)]
const HOOK_OUTLINE_WIDTH: float = 4.0
const HOOK_BODY_WIDTH: float = 2.0

## Shared across every grapple in the scene — the link geometry never varies.
static var _link_mesh: ArrayMesh

var _outline: Line2D
var _body: Line2D
var _core: Line2D
var _strain: Line2D
var _links: MultiMeshInstance2D
var _hook: Node2D


func _ready() -> void:
	_outline = _make_line(OUTLINE_WIDTH, OUTLINE_COLOR, false)
	_body = _make_line(BODY_WIDTH, BODY_COLOR, false)
	_links = _make_links()
	_core = _make_line(CORE_WIDTH, CORE_COLOR, false)
	_strain = _make_line(STRAIN_WIDTH, SalvagePalette.hdr(
		SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN), true)
	_hook = Node2D.new()
	_hook.draw.connect(_draw_hook)
	add_child(_hook)
	_hook.queue_redraw()
	visible = false


## `points` are in this node's own space, hook first, drum last. `tension` is
## 0..1 (see GrappleRope.tension).
func update_chain(points: PackedVector2Array, tension: float) -> void:
	if points.size() < 2:
		visible = false
		return

	visible = true
	_outline.points = points
	_body.points = points
	_core.points = points
	_core.modulate.a = 0.75 + 0.25 * tension

	var glow: float = (tension - STRAIN_THRESHOLD) * STRAIN_ALPHA_GAIN
	_strain.visible = glow > 0.01
	if _strain.visible:
		_strain.points = points
		_strain.modulate.a = clampf(glow, 0.0, 1.0)

	_update_links(points)
	_update_hook(points)


func _update_links(points: PackedVector2Array) -> void:
	var count: int = points.size() - 1
	var multimesh: MultiMesh = _links.multimesh
	# Grown, never shrunk, and only when a longer line than any so far is cast:
	# resizing a MultiMesh reallocates its instance buffer.
	if multimesh.instance_count < count:
		multimesh.instance_count = count
	multimesh.visible_instance_count = count

	for i in count:
		var span: Vector2 = points[i + 1] - points[i]
		var flatten: float = LINK_THICK if i % 2 == 0 else LINK_THIN
		multimesh.set_instance_transform_2d(i, Transform2D(
			span.angle(), Vector2(LINK_LENGTH, flatten), 0.0, points[i] + span * 0.5))


func _update_hook(points: PackedVector2Array) -> void:
	_hook.position = points[0]
	# Angled off a point a little way down the line rather than off its immediate
	# neighbour, which at rest sits almost on top of the hook and gives a jittery
	# angle.
	var behind: Vector2 = points[mini(2, points.size() - 1)]
	var along: Vector2 = points[0] - behind
	if along.length() > 0.001:
		_hook.rotation = along.angle()


func _draw_hook() -> void:
	var segments := PackedVector2Array([HOOK_SHAFT, HOOK_HUB])
	for prong in HOOK_PRONGS:
		segments.append(HOOK_HUB)
		segments.append(prong)
	# Two commands rather than one per prong, same batching reason as the links.
	_hook.draw_multiline(segments, OUTLINE_COLOR, HOOK_OUTLINE_WIDTH)
	_hook.draw_multiline(segments, CORE_COLOR, HOOK_BODY_WIDTH)


func _make_line(width: float, color: Color, additive: bool) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	if additive:
		line.material = SalvagePalette.additive_material()
	add_child(line)
	return line


func _make_links() -> MultiMeshInstance2D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = _ellipse_mesh()
	multimesh.instance_count = 0

	var instance := MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.modulate = CORE_COLOR
	add_child(instance)
	return instance


## Unit ellipse (radius 0.5) as a triangle fan, scaled per instance into the
## link's length and flatten.
static func _ellipse_mesh() -> ArrayMesh:
	if _link_mesh != null:
		return _link_mesh

	var vertices := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	for i in LINK_SIDES + 1:
		var angle: float = TAU * float(i) / float(LINK_SIDES)
		vertices.append(Vector2(cos(angle), sin(angle)) * 0.5)
	for i in LINK_SIDES:
		indices.append_array([0, i + 1, i + 2])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_link_mesh = ArrayMesh.new()
	_link_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _link_mesh

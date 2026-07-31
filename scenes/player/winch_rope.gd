class_name WinchRope
extends Node2D

## Verlet-simulated rope trailing from a HardpointWinch to its tip — gives
## the winch a physical "cast a line" look with visible sag/bends rather
## than a rigid straight beam. The first point is pinned to the anchor
## (the hardpoint's muzzle) and the last to the tip (see update_rope());
## the points in between are free, constrained to a fixed segment length
## and nudged by a small persistent sideways undulation so the rope reads
## as slack/organic even at rest (there's no real "down" in a top-down space
## game to sag toward, so this stands in for gravity).
##
## Lives at the world origin with no transform of its own (spawned via
## get_tree().current_scene.add_child(), never reparented or moved) so the
## points it tracks — given in global space by HardpointWinch — can be drawn
## directly without a local/global conversion.

const ITERATIONS: int = 8
const DAMPING: float = 0.98
const UNDULATION_STRENGTH: float = 6.0
const UNDULATION_SPEED: float = 2.5

@export var segment_count: int = 14
@export var rope_color: Color = Color(0.75, 0.7, 0.55, 0.95)
@export var rope_width: float = 2.5

var _points: Array[Vector2] = []
var _prev_points: Array[Vector2] = []
var _segment_length: float = 12.0
var _time: float = 0.0
var _initialized: bool = false
var _last_anchor: Vector2 = Vector2.ZERO
var _last_tip: Vector2 = Vector2.ZERO


func _ready() -> void:
	_points.resize(segment_count)
	_prev_points.resize(segment_count)


## anchor/tip are global positions — always the winch's current muzzle
## position and current tip/target position, called every physics frame the
## rope is active, so the rope stays physically connected to the ship (and
## whatever the tip is attached to) at all times. paid_out_length is the
## rope's current "paid out" length budget — kept a little longer than the
## straight-line anchor-tip distance whenever possible so the rope visibly
## trails/sags instead of always being razor taut (see HardpointWinch, which
## grows this as its tip flies out and shrinks it while reeling in).
func update_rope(anchor: Vector2, tip: Vector2, paid_out_length: float) -> void:
	if not _initialized:
		_reset_points_along(anchor, tip)
		_initialized = true
		_last_anchor = anchor
		_last_tip = tip

	_segment_length = maxf(paid_out_length, 1.0) / float(segment_count - 1)

	var anchor_delta: Vector2 = anchor - _last_anchor
	var tip_delta: Vector2 = tip - _last_tip
	_last_anchor = anchor
	_last_tip = tip

	_points[0] = anchor
	_points[segment_count - 1] = tip
	_apply_endpoint_drag(anchor_delta, tip_delta)


func _physics_process(delta: float) -> void:
	_time += delta
	_verlet_integrate()
	_apply_undulation()
	for _i in ITERATIONS:
		_satisfy_constraints()
	queue_redraw()


## Injects the anchor/tip's own frame-to-frame motion into the nearby free
## points as real momentum — only their _points move here, not
## _prev_points, so the difference shows up as verlet-implied velocity next
## frame (see _verlet_integrate). Without this, the rope only follows a
## moving endpoint via the distance-constraint solver pulling it taut each
## frame, which reads as instantly rigid; with it, quickly moving the ship
## (or a grappled target) whips the rope along and it keeps swinging
## afterward under its own residual velocity instead of snapping straight
## and stopping the instant the ship does.
func _apply_endpoint_drag(anchor_delta: Vector2, tip_delta: Vector2) -> void:
	if anchor_delta.length() < 0.0001 and tip_delta.length() < 0.0001:
		return

	var free_count: int = segment_count - 2
	if free_count <= 0:
		return

	for i in range(1, segment_count - 1):
		var t: float = float(i - 1) / float(free_count - 1) if free_count > 1 else 0.5
		_points[i] += anchor_delta * (1.0 - t) + tip_delta * t


func _reset_points_along(anchor: Vector2, tip: Vector2) -> void:
	for i in segment_count:
		var fraction: float = float(i) / float(segment_count - 1)
		_points[i] = anchor.lerp(tip, fraction)
		_prev_points[i] = _points[i]


func _verlet_integrate() -> void:
	for i in range(1, segment_count - 1):
		var current: Vector2 = _points[i]
		var velocity: Vector2 = (current - _prev_points[i]) * DAMPING
		_prev_points[i] = current
		_points[i] = current + velocity


## A small perpetual sideways nudge (peaking at the rope's middle, zero at
## the pinned ends) — without it, pure distance-constraint solving with no
## external force settles into a perfectly straight line, which reads as a
## rigid beam rather than a rope.
func _apply_undulation() -> void:
	for i in range(1, segment_count - 1):
		var along: float = float(i) / float(segment_count - 1)
		var offset: float = sin(_time * UNDULATION_SPEED + along * TAU) * UNDULATION_STRENGTH * sin(along * PI)
		var span: Vector2 = _points[i + 1] - _points[i - 1]
		var normal: Vector2 = span.orthogonal().normalized() if span.length() > 0.001 else Vector2.UP
		_points[i] += normal * offset * 0.02


func _satisfy_constraints() -> void:
	for i in range(segment_count - 1):
		var span: Vector2 = _points[i + 1] - _points[i]
		var distance: float = span.length()
		if distance < 0.0001:
			continue
		var difference: float = (_segment_length - distance) / distance
		var correction: Vector2 = span * 0.5 * difference
		if i != 0:
			_points[i] -= correction
		if i + 1 != segment_count - 1:
			_points[i + 1] += correction


func _draw() -> void:
	if _points.size() < 2:
		return
	draw_polyline(PackedVector2Array(_points), rope_color, rope_width, true)

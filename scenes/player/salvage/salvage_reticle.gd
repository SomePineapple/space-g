class_name SalvageReticle
extends Node2D

## The lock-on marker drawn over the hex about to be cut: four brackets that fly
## in from 96px out to 6px out over 0.8s, and a dashed hex outline whose dashes
## scroll (docs/design_salvage/salvage-beam-Godot-spec.md, Lock phase).
##
## Lives in world space and is told which hex to sit on each frame, because the
## target ship moves and rotates while the cut is held — the reticle has to track
## it rather than being parented to it (parenting would also make it inherit the
## hull's own draw order and tint).

const FLY_IN_SECONDS: float = 0.8
const BRACKET_START_OFFSET: float = 96.0
const BRACKET_END_OFFSET: float = 6.0
const BRACKET_ARM: float = 9.0
const BRACKET_WIDTH: float = 2.0

const DASH_SCROLL_SPEED: float = 22.0
const DASH_LENGTH: float = 7.0
const DASH_GAP: float = 6.0
const OUTLINE_WIDTH: float = 1.6

var _elapsed: float = 0.0
var _radius: float = 24.0
var _hex_rotation: float = 0.0
var _active: bool = false


func _ready() -> void:
	visible = false


## Called every frame the beam is locked onto a cell. `center` and `rotation` are
## world-space; `radius` is the hex's own cell size.
func lock_on(center: Vector2, hex_rotation: float, radius: float) -> void:
	if not _active:
		_active = true
		_elapsed = 0.0
	global_position = center
	_hex_rotation = hex_rotation
	_radius = radius
	visible = true
	queue_redraw()


func release() -> void:
	_active = false
	_elapsed = 0.0
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var fly_in: float = clampf(_elapsed / FLY_IN_SECONDS, 0.0, 1.0)
	# Ease-out: fast approach that settles, rather than a linear slide.
	var eased: float = 1.0 - pow(1.0 - fly_in, 3.0)
	var offset: float = lerpf(BRACKET_START_OFFSET, BRACKET_END_OFFSET, eased)
	var color: Color = SalvagePalette.hdr(
		SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN, 0.55 + 0.35 * eased)

	_draw_brackets(offset, color)
	# The outline is the thing being cut, so it only appears once the brackets
	# have arrived — otherwise the lock reads as instant.
	if fly_in > 0.55:
		_draw_dashed_hex(color)


## Four corner brackets, at the diagonals so they frame the hex rather than
## sitting on its own vertices.
func _draw_brackets(offset: float, color: Color) -> void:
	var reach: float = _radius + offset
	for i in 4:
		var angle: float = PI * 0.25 + PI * 0.5 * float(i)
		var corner: Vector2 = Vector2.RIGHT.rotated(angle) * reach
		# Arms point back toward the hex along both axes.
		var inward_x: Vector2 = Vector2(-signf(corner.x) * BRACKET_ARM, 0.0)
		var inward_y: Vector2 = Vector2(0.0, -signf(corner.y) * BRACKET_ARM)
		draw_line(corner, corner + inward_x, color, BRACKET_WIDTH)
		draw_line(corner, corner + inward_y, color, BRACKET_WIDTH)


## The hex outline as scrolling dashes. Walked as one continuous perimeter so the
## dash pattern runs round the corners instead of restarting on every edge.
func _draw_dashed_hex(color: Color) -> void:
	var corners: PackedVector2Array = HexUtils.hex_corners(Vector2.ZERO, _radius)
	var period: float = DASH_LENGTH + DASH_GAP
	var scrolled: float = fmod(_elapsed * DASH_SCROLL_SPEED, period)
	var travelled: float = -scrolled
	for i in corners.size():
		var from: Vector2 = corners[i].rotated(_hex_rotation)
		var to: Vector2 = corners[(i + 1) % corners.size()].rotated(_hex_rotation)
		var edge: float = from.distance_to(to)
		var along: float = 0.0
		while along < edge:
			var phase: float = fmod(travelled + along, period)
			if phase < 0.0:
				phase += period
			var remaining: float = DASH_LENGTH - phase
			if remaining > 0.0:
				var dash_end: float = minf(along + remaining, edge)
				draw_line(from.lerp(to, along / edge), from.lerp(to, dash_end / edge),
					color, OUTLINE_WIDTH)
				along = dash_end
			along += maxf(period - maxf(phase, 0.0) - DASH_LENGTH, 0.5)
		travelled += edge

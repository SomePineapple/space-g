class_name SalvageBeam
extends Node2D

## The cutting beam itself: three stacked additive lines, the muzzle emitter
## (charge ring + core) and the contact flare
## (docs/design_salvage/salvage-beam-Godot-spec.md §Beam).
##
## Replaces the plain single-line BeamVisual for the Slicer. The tractor beam and
## winch still use BeamVisual — this is deliberately not a general beam widget,
## it is the salvage cutter's own look.
##
## Draws in the hardpoint's local space: `set_endpoints` takes the muzzle in local
## coordinates and the contact point in world coordinates, the same mixed-space
## convention BeamVisual established (and the same trap documented there — do not
## convert the endpoint before passing it).

## Widths from the spec's beam table.
const SHEATH_WIDTH: float = 16.0
const MID_WIDTH: float = 7.0
const CORE_WIDTH: float = 2.6
const SHEATH_ALPHA: float = 0.14
const MID_ALPHA: float = 0.42
const CORE_ALPHA: float = 0.95

## The pilot beam that precedes the cut: same geometry, thinner and dimmer.
const PILOT_WIDTH_SCALE: float = 0.32
const PILOT_ALPHA_SCALE: float = 0.55

const FLARE_RADIUS: float = 26.0
const FLARE_WOBBLE: float = 5.0
## The anamorphic streak that sells "hot" — a thin horizontal bar much wider than
## the flare itself.
const STREAK_WIDTH_SCALE: float = 3.4
const STREAK_HEIGHT: float = 2.0

const CHARGE_RING_RADIUS: float = 9.0
const CHARGE_RING_WIDTH: float = 2.0
const CHARGE_RING_SPIN: float = TAU  # ~1 rev/s
const MUZZLE_CORE_RADIUS: float = 4.0

var _sheath: Line2D
var _mid: Line2D
var _core: Line2D
var _flare: Node2D
var _emitter: Node2D

var _time: float = 0.0
## 0 while spooling, 1 once the cut beam is at full strength. The pilot beam is
## this at PILOT_*_SCALE rather than a separate set of nodes.
var _strength: float = 0.0
## 0..1 across the spool phase, driving the charge ring and muzzle brightness.
var _charge: float = 0.0
var _tint: Color = Color.WHITE
var _contact_local: Vector2 = Vector2.ZERO
var _showing: bool = false


func _ready() -> void:
	_sheath = _make_line(SHEATH_WIDTH, SalvagePalette.hdr(
		SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN, SHEATH_ALPHA))
	_mid = _make_line(MID_WIDTH, SalvagePalette.hdr(
		SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN, MID_ALPHA))
	_core = _make_line(CORE_WIDTH, SalvagePalette.hdr(
		SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, CORE_ALPHA))

	_flare = Node2D.new()
	_flare.material = SalvagePalette.additive_material()
	_flare.draw.connect(_draw_flare)
	add_child(_flare)

	_emitter = Node2D.new()
	_emitter.material = SalvagePalette.additive_material()
	_emitter.draw.connect(_draw_emitter)
	add_child(_emitter)

	hide_beam()


## `strength` 0..1 scales the beam between pilot and full cut; `charge` 0..1
## drives the muzzle spool. Both are set by the Slicer from its own phase state
## rather than being animated here, so an interrupted cut winds back down instead
## of finishing a canned timeline.
func set_state(strength: float, charge: float, tint: Color) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_charge = clampf(charge, 0.0, 1.0)
	_tint = tint


## `muzzle_local` is in the parent hardpoint's space; `contact_global` is world.
func set_endpoints(muzzle_local: Vector2, contact_global: Vector2) -> void:
	_showing = true
	visible = true
	_contact_local = to_local(contact_global)
	var points: PackedVector2Array = [muzzle_local, _contact_local]
	_sheath.points = points
	_mid.points = points
	_core.points = points
	_emitter.position = muzzle_local
	_flare.position = _contact_local


func hide_beam() -> void:
	_showing = false
	visible = false


func _process(delta: float) -> void:
	# Time runs while hidden too, so the flicker keeps a continuous phase across
	# brief target losses instead of restarting at full brightness.
	_time += delta
	if not _showing:
		return

	# Flicker is WIDTH ONLY. Position jitter reads as the targeting failing rather
	# than as a hot cutting beam — the spec is explicit about this.
	var flicker: float = 1.0 + 0.18 * sin(_time * 41.0) + 0.10 * sin(_time * 97.0)
	var scale: float = lerpf(PILOT_WIDTH_SCALE, 1.0, _strength) * flicker
	_sheath.width = SHEATH_WIDTH * scale
	_mid.width = MID_WIDTH * scale
	_core.width = CORE_WIDTH * scale

	var alpha: float = lerpf(PILOT_ALPHA_SCALE, 1.0, _strength)
	modulate = Color(_tint.r, _tint.g, _tint.b, _tint.a * alpha)

	_flare.queue_redraw()
	_emitter.queue_redraw()


func _draw_flare() -> void:
	if _strength <= 0.01:
		return
	var radius: float = (FLARE_RADIUS + FLARE_WOBBLE * sin(_time * 33.0)) * _strength
	_flare.draw_circle(Vector2.ZERO, radius,
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, 0.55))
	_flare.draw_circle(Vector2.ZERO, radius * 0.45,
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, 0.9))
	var streak: float = radius * STREAK_WIDTH_SCALE
	_flare.draw_rect(Rect2(-streak, -STREAK_HEIGHT * 0.5, streak * 2.0, STREAK_HEIGHT),
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, 0.35))


func _draw_emitter() -> void:
	if _charge <= 0.01:
		return
	# Ring spins and grows as it spools.
	var radius: float = CHARGE_RING_RADIUS * (0.4 + 0.6 * _charge)
	var start: float = _time * CHARGE_RING_SPIN
	_emitter.draw_arc(Vector2.ZERO, radius, start, start + TAU * 0.75, 24,
		SalvagePalette.hdr(SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN, _charge),
		CHARGE_RING_WIDTH, true)
	# Core brightens 0.4 -> 1.0 alpha across the spool.
	_emitter.draw_circle(Vector2.ZERO, MUZZLE_CORE_RADIUS,
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN,
			lerpf(0.4, 1.0, _charge)))


func _make_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.material = SalvagePalette.additive_material()
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(line)
	return line

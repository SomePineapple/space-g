class_name ScannerScope
extends Control

## The 360x360 A-scope face of the scanner instrument
## (docs/design_handoff_scanner_radar/README.md, option 1D). A direct port of
## the handoff's `drawScope()` canvas routine.
##
## Horizontal axis is RANGE, not position; vertical axis is signal strength.
## Bearing is set on the beam bar above the plot and is not on the plot itself.
##
## Owns only drawing and the beam-bar drag. Everything around it (buttons,
## readouts, returns list, help card) belongs to ScannerDisplay, which also
## supplies the Scanner this reads.

## Trace resolution. One polyline of this many segments is redrawn every frame;
## see docs/performance.md — the cost that matters is the draw-call count, not
## the sample count, so this stays a single polyline rather than per-segment
## lines.
const SEGMENTS: int = 260
## Noise amplitude in pixels, before the distance falloff.
const STATIC_AMPLITUDE: float = 5.0
const SINE_AMPLITUDE: float = 1.4
## Travelling-sine period, ~1.6s.
const SINE_PERIOD_MS: float = 260.0
## Peak height as a fraction of the plot, at full signature strength.
const PEAK_HEIGHT_FRACTION: float = 0.72
## Callout rows are this tall; overlapping labels stagger upward by one row.
const CALLOUT_ROW: float = 14.0

var _scanner: Scanner
## Fixed static pattern, generated once so the trace jitters in place rather
## than reshuffling every frame. Presentation-only randomness, so deliberately
## the global randf() and not a GameRng stream (see game_rng.gd).
var _noise: PackedFloat32Array = PackedFloat32Array()
var _font: Font
## Drag state: -1 = left edge, 1 = right edge, 0 = re-aim.
var _drag_edge: int = 0
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(ScannerPalette.SCOPE_SIZE, ScannerPalette.SCOPE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_font = ScannerPalette.mono_font()

	_noise.resize(SEGMENTS)
	for i in SEGMENTS:
		_noise[i] = randf()


func set_scanner(scanner: Scanner) -> void:
	_scanner = scanner


# --- Aiming ------------------------------------------------------------------

## Same interaction model as the handoff's 1C/1D: a press within 10° of a beam
## edge drags that edge, anything else re-aims the beam and keeps dragging it.
func _gui_input(event: InputEvent) -> void:
	if _scanner == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(_bearing_at(event.position.x))
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_continue_drag(_bearing_at(event.position.x))
		accept_event()


func _begin_drag(bearing: float) -> void:
	var half: float = _scanner.get_beam_width() * 0.5
	var to_left: float = absf(bearing - (_scanner.get_beam_bearing() - half))
	var to_right: float = absf(bearing - (_scanner.get_beam_bearing() + half))
	_dragging = true
	if minf(to_left, to_right) < 10.0:
		_drag_edge = -1 if to_left < to_right else 1
	else:
		_drag_edge = 0
		_scanner.set_beam(bearing, _scanner.get_beam_width())


func _continue_drag(bearing: float) -> void:
	if _drag_edge == 0:
		_scanner.set_beam(bearing, _scanner.get_beam_width())
	else:
		_scanner.set_beam(_scanner.get_beam_bearing(),
				_drag_edge * (bearing - _scanner.get_beam_bearing()) * 2.0)


## The bar is a linear -180..180 strip, so this is a plain remap of x with no
## angle wrapping — dragging off the left end clamps rather than jumping.
func _bearing_at(x: float) -> float:
	var plot: Rect2 = _plot()
	return clampf(((x - plot.position.x) / plot.size.x) * 360.0 - 180.0, -180.0, 180.0)


# --- Drawing -----------------------------------------------------------------

func _plot() -> Rect2:
	return Rect2(ScannerPalette.PLOT_ORIGIN, ScannerPalette.PLOT_SIZE)


func _draw() -> void:
	if _scanner == null:
		return

	var plot: Rect2 = _plot()
	_draw_beam_bar(plot)
	_draw_plot_frame(plot)
	_draw_trace(plot)
	if _scanner.is_scanning():
		_draw_transmit_line(plot)
	_draw_callouts(plot)


func _draw_beam_bar(plot: Rect2) -> void:
	var bar := Rect2(plot.position.x, ScannerPalette.BAR_Y, plot.size.x, ScannerPalette.BAR_HEIGHT)

	_text(Vector2(plot.position.x, 22.0), "BEAM BEARING — drag to aim",
			ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.7))
	draw_rect(bar, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.2), false, 1.0)

	for step in range(-180, 181, 45):
		var tick_x: float = _bar_x(plot, float(step))
		draw_line(Vector2(tick_x, bar.position.y), Vector2(tick_x, bar.position.y + 4.0),
				ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.25), 1.0)

	var half: float = _scanner.get_beam_width() * 0.5
	var left: float = _scanner.get_beam_bearing() - half
	var right: float = _scanner.get_beam_bearing() + half
	var left_x: float = _bar_x(plot, maxf(-180.0, left))
	var right_x: float = _bar_x(plot, minf(180.0, right))
	draw_rect(Rect2(left_x, bar.position.y + 1.0, right_x - left_x, bar.size.y - 2.0),
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.3))

	_draw_edge_arrow(_bar_x(plot, clampf(left, -180.0, 180.0)), bar, 1.0)
	_draw_edge_arrow(_bar_x(plot, clampf(right, -180.0, 180.0)), bar, -1.0)

	# Right-aligned to the bar's edge minus 28px, clearing the help toggle.
	var readout: String = ScannerPalette.format_bearing(_scanner.get_beam_bearing())
	var width: float = _font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ScannerPalette.FONT_SIZE_CANVAS).x
	_text(Vector2(plot.position.x + plot.size.x - 28.0 - width, bar.position.y - 6.0), readout,
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.85))


func _draw_edge_arrow(x: float, bar: Rect2, direction: float) -> void:
	var top: float = bar.position.y + bar.size.y + 2.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, top),
		Vector2(x + direction * 6.0, top + 7.0),
		Vector2(x - direction, top + 7.0),
	]), ScannerPalette.AMBER)


func _draw_plot_frame(plot: Rect2) -> void:
	var base: float = plot.position.y + plot.size.y
	draw_rect(plot, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.03))

	# The handoff labels every 1000u with a faint line every 500u. That only
	# stays readable while range is around its base 3000, so the step scales to
	# keep roughly six labels however far scanner upgrades push the range out.
	var max_range: float = _scanner.scan_range
	var major_step: float = maxf(1000.0, snappedf(max_range / 6.0, 500.0))
	var value: float = 0.0
	while value <= max_range:
		var x: float = _range_x(plot, value)
		var major: bool = is_zero_approx(fmod(value, major_step))
		draw_line(Vector2(x, plot.position.y), Vector2(x, base),
				ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.14 if major else 0.06), 1.0)
		if major:
			_text(Vector2(x - 12.0, base + 14.0), str(int(value)),
					ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.75))
		value += major_step * 0.5

	_text(Vector2(plot.position.x + plot.size.x - 92.0, base + 26.0), "RANGE (units) ->",
			ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.6))

	# The handoff rotates the signal caption; drawn as stacked glyphs instead,
	# because rotating a draw_string needs a canvas transform for two words.
	var caption: String = "SIGNAL"
	for i in caption.length():
		_text(Vector2(10.0, plot.position.y + plot.size.y * 0.5 - 24.0 + i * 11.0), caption[i],
				ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.6))

	for i in range(1, 4):
		var y: float = plot.position.y + (plot.size.y / 4.0) * i
		draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y),
				ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.05), 1.0)

	var floor_y: float = base - ScannerPalette.BASELINE_INSET
	draw_dashed_line(Vector2(plot.position.x, floor_y), Vector2(plot.position.x + plot.size.x, floor_y),
			ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.35), 1.0, 2.5)
	_text(Vector2(plot.position.x + 4.0, floor_y - 4.0), "noise floor",
			ScannerPalette.with_alpha(ScannerPalette.TEXT_DIM, 0.5))

	draw_rect(plot, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.25), false, 1.0)


## Per-sample static plus a slow travelling sine, both scaled up with range so
## distant contacts are genuinely harder to read, minus a Gaussian bump per
## resolved return.
func _draw_trace(plot: Rect2) -> void:
	var now_ms: float = float(Time.get_ticks_msec())
	var max_range: float = _scanner.scan_range
	var hits: Array[Dictionary] = _scanner.get_hits()
	var base: float = plot.position.y + plot.size.y - ScannerPalette.BASELINE_INSET
	var step: float = plot.size.x / float(SEGMENTS)

	var points := PackedVector2Array()
	points.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		var range_at: float = (float(i) / SEGMENTS) * max_range
		var far: float = 0.25 + 0.75 * (range_at / max_range)
		var amplitude: float = (_noise[i % SEGMENTS] - 0.5) * STATIC_AMPLITUDE * far \
				+ sin(now_ms / SINE_PERIOD_MS + i * 0.7) * SINE_AMPLITUDE * far
		for hit in hits:
			amplitude -= _peak_offset(plot, hit, range_at)
		points[i] = Vector2(plot.position.x + i * step,
				clampf(base + amplitude, plot.position.y + 4.0, plot.position.y + plot.size.y - 2.0))

	# Phosphor glow: a wide faint pass under the sharp one, standing in for the
	# canvas shadowBlur the handoff uses.
	draw_polyline(points, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.18), 5.0, true)
	draw_polyline(points, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.92), 1.4, true)


## How far a single return lifts the trace at `range_at`. Peaks smear wider the
## further out they sit, so distant contacts read as vague humps.
func _peak_offset(plot: Rect2, hit: Dictionary, range_at: float) -> float:
	var distance: float = hit["distance"]
	var offset: float = range_at - distance
	var sigma: float = 34.0 + distance * 0.012
	var falloff: float = exp(-(offset * offset) / (2.0 * sigma * sigma))
	return falloff * _peak_strength(hit) * plot.size.y * PEAK_HEIGHT_FRACTION


func _peak_strength(hit: Dictionary) -> float:
	var distance: float = hit["distance"]
	return ScannerPalette.signature_strength(hit["signature"]) \
			* (1.0 - distance / _scanner.scan_range * 0.45)


func _draw_transmit_line(plot: Rect2) -> void:
	var x: float = _range_x(plot, _scanner.get_reach())
	const TRAIL: float = 40.0
	const TRAIL_STEPS: int = 8
	for i in TRAIL_STEPS:
		var t: float = float(i) / TRAIL_STEPS
		var strip_x: float = x - TRAIL + TRAIL * t
		draw_rect(Rect2(strip_x, plot.position.y, TRAIL / TRAIL_STEPS, plot.size.y),
				ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.16 * t))
	draw_line(Vector2(x, plot.position.y), Vector2(x, plot.position.y + plot.size.y),
			ScannerPalette.with_alpha(ScannerPalette.ACCENT_BRIGHT, 0.85), 1.5)


## A dashed leader from each peak's apex to a label box. Boxes that would
## collide horizontally stagger upward a row at a time.
func _draw_callouts(plot: Rect2) -> void:
	var base: float = plot.position.y + plot.size.y - ScannerPalette.BASELINE_INSET
	var placed: Array[Rect2] = []

	for hit in _scanner.get_hits():
		var x: float = _range_x(plot, hit["distance"])
		var apex: float = maxf(plot.position.y + 30.0,
				base - _peak_strength(hit) * plot.size.y * PEAK_HEIGHT_FRACTION)
		var label: String = "%s · %du" % [String(hit["category"]).to_upper(), int(hit["distance"])]
		var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				ScannerPalette.FONT_SIZE_CANVAS).x
		var label_x: float = clampf(x - width * 0.5, plot.position.x + 2.0,
				plot.position.x + plot.size.x - width - 2.0)
		var label_y: float = apex - 26.0
		while _collides(placed, label_x, label_y, width) and label_y > plot.position.y + 2.0:
			label_y -= CALLOUT_ROW
		placed.append(Rect2(label_x, label_y, width, CALLOUT_ROW))

		var color: Color = ScannerPalette.signature_color(hit["signature"])
		draw_dashed_line(Vector2(x, apex - 4.0), Vector2(x, label_y + 13.0),
				ScannerPalette.with_alpha(ScannerPalette.TEXT, 0.4), 1.0, 2.5)
		draw_rect(Rect2(label_x - 3.0, label_y, width + 6.0, 13.0), ScannerPalette.CALLOUT_FILL)
		_text(Vector2(label_x, label_y + 10.0), label, color)
		draw_line(Vector2(x, base), Vector2(x, base + 8.0), color, 2.0)


func _collides(placed: Array[Rect2], x: float, y: float, width: float) -> bool:
	for box in placed:
		if x < box.position.x + box.size.x + 4.0 and box.position.x < x + width + 4.0 \
				and absf(box.position.y - y) < CALLOUT_ROW:
			return true
	return false


func _range_x(plot: Rect2, value: float) -> float:
	return plot.position.x + (value / _scanner.scan_range) * plot.size.x


func _bar_x(plot: Rect2, bearing: float) -> float:
	return plot.position.x + ((bearing + 180.0) / 360.0) * plot.size.x


func _text(baseline: Vector2, text: String, color: Color) -> void:
	draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ScannerPalette.FONT_SIZE_CANVAS, color)

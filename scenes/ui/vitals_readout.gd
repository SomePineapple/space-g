extends Control

## Top-left HP / EN / PWR readout (docs/HUD-1d-Godot-spec.md §1, plus a third
## load row the spec doesn't cover).
##
## The load row reads differently from the other two: its bar is not "how much
## is left" but "how much is being drawn against what the reactor can sustain",
## so a full bar means breaking even, not doing well. It deliberately overruns
## its trough when the ship draws more than it generates — the overrun is the
## whole point, since that's the state where the reserve is being eaten.
##
## The dots and bars are drawn rather than assembled from nested Controls:
## two glow dots and two 74x5 capsules are cheaper to draw directly than to
## keep six extra nodes' styleboxes and sizes in sync. Only the two numbers
## are real Labels, because Label already handles font metrics and outlines.
##
## Fed by HUD, which relays the Ship's health_changed / energy_changed —
## nothing here reaches into the ship.

const ROW_HEIGHT: float = 16.0
const ROW_GAP: float = 7.0
const DOT_RADIUS: float = 3.0
const DOT_CENTRE_X: float = 3.0
const BAR_X: float = 14.0
const BAR_SIZE: Vector2 = Vector2(74.0, 5.0)
## Pushed out from the spec's 96 to leave room for the load bar's overrun, so
## all three numbers stay aligned with each other.
const LABEL_X: float = 120.0
const LABEL_WIDTH: float = 80.0
const FONT_SIZE: int = 13
## How far past the trough (as a fraction of its width) an over-limit load bar
## is allowed to run before it stops growing — the number beside it keeps
## reporting the true figure past that point.
const MAX_LOAD_OVERRUN: float = 1.35
## Load fraction above which the bar warns before it actually overruns.
const LOAD_WARNING_FRACTION: float = 0.85

## Bar trough — the spec's rgba(255,255,255,0.15), not a palette colour.
const TROUGH: Color = Color(1.0, 1.0, 1.0, 0.15)

var _health_current: float = 0.0
var _health_max: float = 1.0
var _energy_current: float = 0.0
var _energy_max: float = 1.0
var _load_usage: float = 0.0
var _load_generation: float = 1.0

var _health_label: Label
var _energy_label: Label
var _load_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var total_height: float = ROW_HEIGHT * 3.0 + ROW_GAP * 2.0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = HudPalette.CORNER_MARGIN
	offset_top = HudPalette.CORNER_MARGIN
	offset_right = HudPalette.CORNER_MARGIN + LABEL_X + LABEL_WIDTH
	offset_bottom = HudPalette.CORNER_MARGIN + total_height

	_health_label = _make_number_label(0.0)
	_energy_label = _make_number_label(ROW_HEIGHT + ROW_GAP)
	_load_label = _make_number_label((ROW_HEIGHT + ROW_GAP) * 2.0)
	_refresh_load_label()


func _make_number_label(row_top: float) -> Label:
	var label := Label.new()
	label.position = Vector2(LABEL_X, row_top - 2.0)
	label.size = Vector2(LABEL_WIDTH, ROW_HEIGHT + 4.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", HudPalette.TEXT)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


func set_health(current: float, max_health: float) -> void:
	_health_current = current
	_health_max = maxf(max_health, 1.0)
	_health_label.text = str(int(roundf(current)))
	_health_label.add_theme_color_override("font_color", HudPalette.TEXT)
	queue_redraw()


func set_energy(current: float, max_energy: float) -> void:
	_energy_current = current
	_energy_max = maxf(max_energy, 1.0)
	_energy_label.text = str(int(roundf(current)))
	queue_redraw()


## Current draw against the rate the ship regenerates at (see
## ShipEnergy.usage_changed).
func set_power_load(usage: float, generation: float) -> void:
	_load_usage = maxf(usage, 0.0)
	_load_generation = maxf(generation, 0.01)
	_refresh_load_label()
	queue_redraw()


func _refresh_load_label() -> void:
	_load_label.text = "%.1f/%.0f" % [_load_usage, _load_generation]
	_load_label.add_theme_color_override("font_color",
		HudPalette.TEXT if _load_usage <= _load_generation else HudPalette.HEALTH_CRITICAL)


func _draw() -> void:
	var health_fraction: float = clampf(_health_current / _health_max, 0.0, 1.0)
	_draw_row(0.0, health_fraction, HudPalette.health_color(health_fraction))
	_draw_row(ROW_HEIGHT + ROW_GAP, clampf(_energy_current / _energy_max, 0.0, 1.0), HudPalette.CYAN)

	var load_fraction: float = _load_usage / _load_generation
	_draw_row((ROW_HEIGHT + ROW_GAP) * 2.0, minf(load_fraction, MAX_LOAD_OVERRUN), _load_color(load_fraction))


## Cyan while there's headroom, amber approaching the limit, red once the ship
## draws more than it makes — the same three-step reading as the health bar.
func _load_color(fraction: float) -> Color:
	if fraction > 1.0:
		return HudPalette.HEALTH_CRITICAL
	if fraction > LOAD_WARNING_FRACTION:
		return HudPalette.HEALTH_WARNING
	return HudPalette.CYAN


## `fraction` may exceed 1.0 (load row only), in which case the fill runs past
## the end of its trough rather than being clipped to it.
func _draw_row(row_top: float, fraction: float, color: Color) -> void:
	var centre_y: float = row_top + ROW_HEIGHT * 0.5
	_draw_glow_dot(Vector2(DOT_CENTRE_X, centre_y), color)

	var bar_top: float = centre_y - BAR_SIZE.y * 0.5
	_draw_capsule(Rect2(Vector2(BAR_X, bar_top), BAR_SIZE), TROUGH)
	if fraction > 0.0:
		_draw_capsule(Rect2(Vector2(BAR_X, bar_top), Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)), color)


## Two translucent haloes stand in for a real glow shader — the spec lists a
## plain solid dot as an acceptable fallback, this is a cheap step above it.
func _draw_glow_dot(centre: Vector2, color: Color) -> void:
	draw_circle(centre, DOT_RADIUS * 3.0, HudPalette.with_alpha(color, 0.16))
	draw_circle(centre, DOT_RADIUS * 1.9, HudPalette.with_alpha(color, 0.32))
	draw_circle(centre, DOT_RADIUS, color)


## Rounded bar ends: draw_rect has square corners and draw_line has no round
## cap, so the capsule is a rect plus a circle at each end.
func _draw_capsule(rect: Rect2, color: Color) -> void:
	var r: float = rect.size.y * 0.5
	if rect.size.x <= rect.size.y:
		draw_circle(rect.position + Vector2(r, r), rect.size.x * 0.5, color)
		return
	draw_rect(Rect2(rect.position + Vector2(r, 0.0), Vector2(rect.size.x - rect.size.y, rect.size.y)), color)
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, color)

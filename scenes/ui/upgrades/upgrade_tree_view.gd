class_name UpgradeTreeView
extends Control

## Draws the radial upgrade fan laid out by UpgradeTreeLayout
## (docs/design_handoff_upgrade_tree/README.md "Tree").
##
## Everything is drawn in one Control rather than assembled from Buttons: the
## whole composition is uniformly scaled to fit the panel, and dashed borders,
## two-tone merge fills and polar elbow connectors all need custom drawing
## anyway. Hit-testing against the laid-out circles is a few lines and avoids
## keeping a dozen scaled child controls in sync.
##
## The view is presentation only — it is handed nodes, a hue and a state per
## node, and knows nothing about ShipUpgradeService, costs or inventory.

signal node_hovered(node_id: String)
signal hover_exited()
signal node_clicked(node_id: String)

const STATE_UNLOCKED: String = "unlocked"
const STATE_AVAILABLE: String = "available"
const STATE_LOCKED: String = "locked"

const GLYPH_FRACTION: float = 0.26
const CONNECTOR_WIDTH_DIM: float = 2.2
const CONNECTOR_WIDTH_FULL: float = 3.0
const CONNECTOR_LOCKED: Color = Color(1, 1, 1, 0.1)
const ARC_DASH: float = 2.0
const ARC_GAP: float = 6.0

const FILL_AVAILABLE: Color = Color(0.0588, 0.0745, 0.0941, 0.85)  # rgba(15,19,24,0.85)
const FILL_LOCKED: Color = Color(0.0588, 0.0745, 0.0941, 0.6)  # rgba(15,19,24,0.6)
const BORDER_LOCKED: Color = Color(1, 1, 1, 0.14)

const PULSE_PERIOD: float = 2.2
const GRADIENT_ANGLE_DEGREES: float = 155.0
const MERGE_GRADIENT_ANGLE_DEGREES: float = 135.0
const CIRCLE_SEGMENTS: int = 32

var _base_hue: float = UpgradePalette.DEFAULT_HUE
var _states: Dictionary = {}
var _layout: UpgradeTreeLayout = UpgradeTreeLayout.new()

## When set, the scale is derived from this frame instead of the current
## tree's own, so every tree on the screen draws at one size.
var _reference_frame: Rect2 = Rect2()

var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _pulse: float = 0.0
var _hovered_id: String = ""

var _glow_texture: GradientTexture2D


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glow_texture = _make_radial_texture()
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	set_process(false)


func set_tree(nodes: Array, base_hue: float) -> void:
	_base_hue = base_hue
	_hovered_id = ""
	_layout.build(nodes, base_hue)
	_fit()
	queue_redraw()


## The frame every tree should be scaled against — the union of all of them,
## so switching modules never resizes the nodes.
func set_reference_frame(frame: Rect2) -> void:
	_reference_frame = frame
	_fit()
	queue_redraw()


## id -> STATE_*. Cheap: no re-layout, only appearance changes.
func set_states(states: Dictionary) -> void:
	_states = states
	set_process(_has_available())
	queue_redraw()


## The resolved branch hue of a node, for callers that need to match a node's
## colour outside the view (the detail panel's REQUIRES ALL dots).
func hue_of(node_id: String) -> float:
	return _layout.entries[node_id]["hue"] if _layout.entries.has(node_id) else _base_hue


func tier_of(node_id: String) -> int:
	return _layout.entries[node_id]["tier"] if _layout.entries.has(node_id) else 0


func _state_of(node_id: String) -> String:
	return _states.get(node_id, STATE_LOCKED)


func _has_available() -> bool:
	for state in _states.values():
		if state == STATE_AVAILABLE:
			return true
	return false


# --- Fitting ----------------------------------------------------------------

## Uniform scale-to-fit. Deliberately measured from a real extent rather than
## a fixed canvas: a wide fan in a narrower panel would otherwise let width
## bind and collapse the scale (LAYOUT_SPEC "Fitting"). The tree is centred on
## its *own* frame but scaled against the shared reference one.
func _fit() -> void:
	var target: Rect2 = _reference_frame if _reference_frame.size.x > 0.0 else _layout.frame
	if target.size.x <= 0.0 or target.size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	_scale = minf(size.x / target.size.x, size.y / target.size.y)
	_offset = size * 0.5 - _layout.frame.get_center() * _scale


func _to_screen(point: Vector2) -> Vector2:
	return _offset + point * _scale


func _on_resized() -> void:
	_fit()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta, PULSE_PERIOD)
	queue_redraw()


# --- Input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit: String = _node_at(event.position)
		if hit != _hovered_id:
			_hovered_id = hit
			queue_redraw()
			if hit.is_empty():
				hover_exited.emit()
			else:
				node_hovered.emit(hit)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: String = _node_at(event.position)
		if not hit.is_empty():
			node_clicked.emit(hit)


func _on_mouse_exited() -> void:
	if _hovered_id.is_empty():
		return
	_hovered_id = ""
	queue_redraw()
	hover_exited.emit()


func _node_at(point: Vector2) -> String:
	for node_id in _layout.entries:
		var entry: Dictionary = _layout.entries[node_id]
		if _to_screen(entry["position"]).distance_to(point) <= entry["diameter"] * 0.5 * _scale:
			return node_id
	return ""


# --- Drawing ----------------------------------------------------------------

## Everything here reads _layout.entries and nothing else, so the geometry
## being drawn is always the geometry that was laid out.
func _draw() -> void:
	if _layout.entries.is_empty():
		return
	_draw_field_glow()
	_draw_tier_arcs()
	_draw_connectors()
	for node_id in _layout.entries:
		_draw_node(node_id, _layout.entries[node_id])
	for node_id in _layout.entries:
		_draw_label(node_id, _layout.entries[node_id])


func _draw_field_glow() -> void:
	var rings: int = maxi(_layout.tier_radii.size(), 1)
	var extent: float = (UpgradeTreeLayout.BASE_R + rings * UpgradeTreeLayout.STEP) * 2.4 * _scale
	var centre: Vector2 = _to_screen(Vector2.ZERO)
	draw_texture_rect(_glow_texture, Rect2(centre - Vector2(extent, extent) * 0.5, Vector2(extent, extent)),
		false, UpgradePalette.field_glow(_base_hue))


func _draw_tier_arcs() -> void:
	var colour: Color = UpgradePalette.tier_arc(_base_hue)
	var centre: Vector2 = _to_screen(Vector2.ZERO)
	for radius in _layout.tier_radii:
		_draw_dashed_arc(centre, radius * _scale, -UpgradeTreeLayout.MAX_ANGLE, UpgradeTreeLayout.MAX_ANGLE, colour)


func _draw_connectors() -> void:
	for child_id in _layout.entries:
		for parent_id in _layout.entries[child_id]["parents"]:
			if not _layout.entries.has(parent_id):
				continue
			_draw_elbow(_layout.entries[parent_id], _layout.entries[child_id],
				_state_of(parent_id) == STATE_UNLOCKED, _state_of(child_id) == STATE_UNLOCKED)


## Polar elbow: an arc along the parent's ring across to the child's angle,
## then a straight radial spoke outward. Straight diagonals read as a scribble
## (LAYOUT_SPEC "Connectors").
func _draw_elbow(parent: Dictionary, child: Dictionary, parent_unlocked: bool, child_unlocked: bool) -> void:
	var hue: float = child["hue"]
	var colour: Color = CONNECTOR_LOCKED
	var width: float = CONNECTOR_WIDTH_DIM
	if parent_unlocked and child_unlocked:
		colour = UpgradePalette.connector_full(hue)
		width = CONNECTOR_WIDTH_FULL
	elif parent_unlocked:
		colour = UpgradePalette.connector_half(hue)

	var centre: Vector2 = _to_screen(Vector2.ZERO)
	var parent_radius: float = parent["radius"] * _scale
	var points := PackedVector2Array()

	if parent_radius > 0.0:
		var from_angle: float = parent["angle_degrees"]
		var to_angle: float = child["angle_degrees"]
		var steps: int = maxi(2, int(absf(to_angle - from_angle) / 3.0) + 2)
		for index in range(steps + 1):
			var angle: float = deg_to_rad(lerpf(from_angle, to_angle, float(index) / steps))
			points.append(centre + Vector2(sin(angle), -cos(angle)) * parent_radius)
	else:
		points.append(centre)

	points.append(_to_screen(child["position"]))
	draw_polyline(points, colour, width * _scale, true)


func _draw_node(node_id: String, entry: Dictionary) -> void:
	var state: String = _state_of(node_id)
	var centre: Vector2 = _to_screen(entry["position"])
	var radius: float = entry["diameter"] * 0.5 * _scale
	var hue: float = entry["hue"]
	var merge_hues: Array = entry["merge_hues"]
	var accent: Color = UpgradePalette.bright(hue)
	var glyph_colour: Color = BuilderTheme.TEXT_HINT

	match state:
		STATE_UNLOCKED:
			_draw_halo(centre, radius, UpgradePalette.bright(hue, 0.4), 14.0)
			if merge_hues.size() >= 2:
				_draw_merge_fill(centre, radius, merge_hues)
			else:
				_draw_gradient_fill(centre, radius, UpgradePalette.bright(hue),
					UpgradePalette.deep(hue), GRADIENT_ANGLE_DEGREES)
			draw_arc(centre, radius, 0.0, TAU, CIRCLE_SEGMENTS, accent, 1.0 * _scale, true)
			glyph_colour = BuilderTheme.BG_BASE
		STATE_AVAILABLE:
			# The dashed border of an available merge takes the second branch's
			# hue, so the two-tone requirement still reads before it is owned.
			if merge_hues.size() >= 2:
				accent = UpgradePalette.bright(merge_hues[1])
			var pulse: float = 0.5 - 0.5 * cos(_pulse / PULSE_PERIOD * TAU)
			_draw_halo(centre, radius, UpgradePalette.bright(hue, 0.25), lerpf(3.0, 11.0, pulse))
			draw_circle(centre, radius, FILL_AVAILABLE)
			_draw_dashed_circle(centre, radius, accent, 2.0 * _scale)
			glyph_colour = accent
		_:
			draw_circle(centre, radius, FILL_LOCKED)
			draw_arc(centre, radius, 0.0, TAU, CIRCLE_SEGMENTS, BORDER_LOCKED, 1.0 * _scale, true)

	if _hovered_id == node_id:
		draw_arc(centre, radius + 3.0 * _scale, 0.0, TAU, CIRCLE_SEGMENTS,
			BuilderTheme.with_alpha(accent, 0.6), 1.0 * _scale, true)

	_draw_glyph(entry["glyph"], centre, entry["diameter"], glyph_colour)


func _draw_glyph(glyph: String, centre: Vector2, diameter: float, colour: Color) -> void:
	if glyph.is_empty():
		return
	var font: Font = BuilderTheme.mono_font()
	var font_size: int = maxi(6, int(roundf(diameter * GLYPH_FRACTION * _scale)))
	var measured: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, centre + Vector2(-measured.x * 0.5, font.get_ascent(font_size) * 0.5 - 1.0),
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)


func _draw_label(node_id: String, entry: Dictionary) -> void:
	var state: String = _state_of(node_id)
	var colour: Color = BuilderTheme.TEXT_HINT
	if state == STATE_UNLOCKED:
		colour = BuilderTheme.TEXT_BODY
	elif state == STATE_AVAILABLE:
		colour = BuilderTheme.TEXT_BRIGHT

	var rect: Rect2 = entry["label_rect"]
	var font: Font = BuilderTheme.mono_font()
	var font_size: int = maxi(6, int(roundf(UpgradeTreeLayout.LABEL_FONT_SIZE * _scale)))
	draw_multiline_string(font, _to_screen(rect.position) + Vector2(0.0, font.get_ascent(font_size)),
		entry["label"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x * _scale, font_size, -1, colour)


## Stand-in for the handoff's CSS box-shadow / drop-shadow glow: a few
## expanding translucent rings. Godot has no shadow on a drawn circle.
func _draw_halo(centre: Vector2, radius: float, colour: Color, spread: float) -> void:
	var rings: int = 5
	for index in range(rings, 0, -1):
		var fraction: float = float(index) / rings
		draw_circle(centre, radius + spread * _scale * fraction,
			BuilderTheme.with_alpha(colour, colour.a * (1.0 - fraction) * 0.5))


func _draw_gradient_fill(centre: Vector2, radius: float, from: Color, to: Color, angle_degrees: float) -> void:
	var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	for index in CIRCLE_SEGMENTS:
		var point: Vector2 = Vector2.RIGHT.rotated(TAU * index / CIRCLE_SEGMENTS) * radius
		points.append(centre + point)
		colours.append(from.lerp(to, clampf(point.dot(axis) / (radius * 2.0) + 0.5, 0.0, 1.0)))
	draw_polygon(points, colours)


## A merge node is filled across the hues of *every* branch feeding it — the
## cue that more than one line of research is required.
func _draw_merge_fill(centre: Vector2, radius: float, hues: Array) -> void:
	var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(MERGE_GRADIENT_ANGLE_DEGREES))
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var last: int = hues.size() - 1
	for index in CIRCLE_SEGMENTS:
		var point: Vector2 = Vector2.RIGHT.rotated(TAU * index / CIRCLE_SEGMENTS) * radius
		points.append(centre + point)
		var stop: float = clampf(point.dot(axis) / (radius * 2.0) + 0.5, 0.0, 1.0) * last
		var lower: int = clampi(int(floor(stop)), 0, last)
		var upper: int = clampi(lower + 1, 0, last)
		colours.append(UpgradePalette.bright(hues[lower]).lerp(UpgradePalette.bright(hues[upper]), stop - lower))
	draw_polygon(points, colours)


func _draw_dashed_circle(centre: Vector2, radius: float, colour: Color, width: float) -> void:
	var dash_angle: float = 7.0 / maxf(radius, 1.0)
	var angle: float = 0.0
	while angle < TAU:
		var to: float = minf(angle + dash_angle, TAU)
		draw_arc(centre, radius, angle, to, 4, colour, width, true)
		angle = to + dash_angle * 0.7


func _draw_dashed_arc(centre: Vector2, radius: float, from_degrees: float, to_degrees: float, colour: Color) -> void:
	if radius <= 0.0:
		return
	var dash_angle: float = ARC_DASH * _scale / radius
	var gap_angle: float = ARC_GAP * _scale / radius
	var angle: float = deg_to_rad(from_degrees)
	var end_angle: float = deg_to_rad(to_degrees)
	# Angle 0 points up in tree space; draw_arc measures from +X.
	var rotation_offset: float = -PI * 0.5
	while angle < end_angle:
		var to: float = minf(angle + dash_angle, end_angle)
		draw_arc(centre, radius, angle + rotation_offset, to + rotation_offset, 3, colour, 1.0 * _scale, true)
		angle = to + gap_angle


func _make_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 0.7)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture

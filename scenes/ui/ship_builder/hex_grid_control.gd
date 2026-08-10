class_name HexGridControl
extends Control

## The ship builder's build field: the ship under construction, the cells it can
## currently grow into, and the placement preview.
##
## Styled to docs/design_handoff_ship_builder/README.md ("Hex grid field"), with
## one deliberate departure from it: the field no longer draws a full hex
## lattice. Only the empty cells directly against the hull are drawn, and those
## brighten when the selected module can actually reach them. A wall of 400
## identical cells said nothing about where a part could go; a thin ring of
## sockets around the ship says exactly that, and it is also far less to draw
## (docs/performance.md — this is a per-frame _draw while a preview pulses).
##
## The container's rounded frame is the parent PanelContainer's stylebox;
## everything inside it is drawn here.

signal hex_clicked(hex_coord: Vector2i)
signal hex_hovered(hex_coord: Vector2i)
signal hover_exited

@export var cell_size: float = 32.0
@export var grid_width: int = 20
@export var grid_height: int = 20

## Which faction's reskin the builder previews modules with — set by
## ShipBuilderPanel from the ship actually being edited (see ModuleType.
## faction_hex_textures).
var faction_id: String = "corporate"

var layout: ShipLayout
var selected_placement_id: String = ""

## The workbench frame: every cell in the field, drawn barely-there, so parts
## read as mounted onto a structure rather than floating. Below the sockets in
## both weight and meaning — this one says "the chassis extends here", not "you
## can attach here".
##
## Kept dim on purpose: at the alpha this started at, the empty field read at
## roughly the same weight as the ship on it and competed with the thing being
## edited. The lattice only needs to be present enough to say the workbench
## continues past the hull.
const FRAME_COLOR: Color = Color(0.11, 0.145, 0.188, 0.3)

## Attachment socket strokes: the dim state is "the hull could grow here", the
## bright state is "clicking here places the selected part".
const SOCKET_OPACITY: float = 0.18
const SOCKET_REACHABLE_OPACITY: float = 0.55
const SOCKET_FILL: Color = Color(1, 1, 1, 0.012)
const SOCKET_REACHABLE_FILL: Color = Color(0.1647, 0.3529, 0.4118, 0.18)

## Joins between parts, matching the in-game hull (see ShipLayoutRenderer and
## HullPaint): a fine line where two parts belong together, weld dashes and
## bolts where they don't. The point here is being able to see which joints are
## improvised *before* you commit the layout.
const SEAM_COLOR: Color = Color(0.05, 0.06, 0.08, 0.6)
const SEAM_WIDTH: float = 1.0
const WELD_COLOR: Color = Color(0.72, 0.42, 0.21, 0.8)
const WELD_WIDTH: float = 1.8
const WELD_BOLT_COLOR: Color = Color(0.54, 0.32, 0.15, 0.9)
const WELD_BOLT_WIDTH: float = 1.0

## Soft cyan wash behind the lattice, and the vignette over it.
const FIELD_GLOW: Color = Color(0.1647, 0.3529, 0.4118, 0.16)  # rgba(42,90,105,0.16)
const VIGNETTE_START: float = 0.4
const VIGNETTE_COLOR: Color = Color(0.0392, 0.0510, 0.0706, 0.85)  # 0a0d12 at 85%

## Placement-preview outline pulse (handoff: opacity 0.55 -> 1 over 2.4s).
const PULSE_PERIOD: float = 2.4
const PULSE_MIN_ALPHA: float = 0.55
const DASH_LENGTH: float = 5.0
const DASH_GAP: float = 4.0

## Fraction of the field's short side left as padding when fitting the grid.
const FIT_MARGIN: float = 0.04

var _center: Vector2
## Empty in-bounds cells directly against the hull, and the subset of those the
## currently selected module could actually be placed over. Both are recomputed
## by refresh()/set_build_target() rather than in _draw(): _draw runs every frame
## while a preview pulses, and sweeping placement legality there would be pure
## waste (docs/performance.md).
var _socket_cells: Array[Vector2i] = []
var _reachable_cells: Dictionary = {}
## The module type the palette currently has selected, and the rotation it would
## be placed at — what _reachable_cells is computed against. Empty means nothing
## is selected, so every socket draws in its dim state.
var _build_type_id: String = ""
var _build_rotation: int = 0
## The frame lattice, built once per size change — it only depends on the grid
## dimensions and the fitted cell size, never on the layout.
var _frame_points := PackedVector2Array()

var _preview_cells: Array[Vector2i] = []
var _preview_valid: bool = true
var _preview_module_type_id: String = ""
var _preview_rotation_steps: int = 0
var _pulse_time: float = 0.0

var _glow_texture: GradientTexture2D
var _vignette_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Hex art is authored at a much higher resolution than it renders at in
	# the builder preview, so mipmapped filtering is needed to avoid
	# minification aliasing.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glow_texture = _make_radial_texture(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
	_vignette_texture = _make_radial_texture(Color(1, 1, 1, 0), Color(1, 1, 1, 1), VIGNETTE_START)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	_center = size * 0.5
	fit_to_size()
	_frame_points.clear()
	queue_redraw()


## Scales the hex cells so the logical grid_width x grid_height grid fills the
## field, whatever resolution the screen is — the builder is a full-screen,
## responsive layout, so the cell size can't be a fixed constant.
func fit_to_size() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var usable: Vector2 = size * (1.0 - FIT_MARGIN * 2.0)
	var by_width: float = usable.x / (HexUtils.SQRT3 * (grid_width + 1.0))
	var by_height: float = usable.y / (1.5 * grid_height + 0.5)
	cell_size = maxf(minf(by_width, by_height), 4.0)


func _make_radial_texture(inner: Color, outer: Color, inner_offset: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, inner_offset)
	gradient.set_offset(1, 1.0)
	gradient.set_color(0, inner)
	gradient.set_color(1, outer)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


func _process(delta: float) -> void:
	_pulse_time = fposmod(_pulse_time + delta, PULSE_PERIOD)
	queue_redraw()


func _draw() -> void:
	_draw_field_glow()
	_draw_frame()
	_draw_sockets()
	_draw_placements()
	_draw_hardpoint_overlays()
	_draw_vignette()
	_draw_preview()


func _draw_field_glow() -> void:
	var extent: Vector2 = Vector2(size.x * 0.7, size.y * 0.6)
	var centre: Vector2 = Vector2(size.x * 0.48, size.y * 0.45)
	draw_texture_rect(_glow_texture, Rect2(centre - extent * 0.5, extent), false, FIELD_GLOW)


func _draw_vignette() -> void:
	var extent: Vector2 = Vector2(size.x * 1.2, size.y * 1.4)
	draw_texture_rect(_vignette_texture, Rect2(size * 0.5 - extent * 0.5, extent), false, VIGNETTE_COLOR)


## The workbench lattice under everything. Emitted as a single draw_multiline()
## rather than a stroked polygon per cell: the old full-field lattice cost seven
## canvas commands for each of ~400 cells, which is the exact batching problem
## docs/performance.md is about. Only three of each cell's six edges are pushed,
## since the other three belong to its neighbours — every edge lands in the list
## exactly once.
func _draw_frame() -> void:
	if _frame_points.is_empty():
		_build_frame_points()
	draw_multiline(_frame_points, FRAME_COLOR, 1.0)


func _build_frame_points() -> void:
	var r_min: int = -grid_height / 2
	for r in range(r_min, r_min + grid_height):
		var q_min: int = -grid_width / 2 - _row_q_offset(r)
		for q in range(q_min, q_min + grid_width):
			var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(Vector2i(q, r)))
			for edge in 3:
				_frame_points.append(corners[edge])
				_frame_points.append(corners[edge + 1])


## The ring of empty cells the hull can grow into. A socket the selected module
## can actually be placed over is drawn brighter and filled — that difference is
## the whole point of the ring, so "where can this part go" is answerable
## without hovering every cell in turn.
func _draw_sockets() -> void:
	for hex_coord in _socket_cells:
		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(hex_coord))
		var reachable: bool = _reachable_cells.has(hex_coord)
		draw_colored_polygon(corners, SOCKET_REACHABLE_FILL if reachable else SOCKET_FILL)
		_stroke_polygon(corners, BuilderTheme.with_alpha(BuilderTheme.CYAN,
			SOCKET_REACHABLE_OPACITY if reachable else SOCKET_OPACITY), 1.0)


## Which module the sockets should be measured against. Called by
## ShipBuilderPanel whenever the palette selection or the pending rotation
## changes; an empty id means nothing is selected.
func set_build_target(module_type_id: String, rotation_steps: int) -> void:
	if module_type_id == _build_type_id and rotation_steps == _build_rotation:
		return
	_build_type_id = module_type_id
	_build_rotation = rotation_steps
	_recompute_sockets()
	queue_redraw()


func _recompute_sockets() -> void:
	_socket_cells.clear()
	_reachable_cells.clear()
	if layout == null:
		return

	var seen: Dictionary = {}
	for placement in layout.placements:
		for cell in layout.get_occupied_cells(placement):
			for neighbor in HexUtils.neighbors(cell):
				if seen.has(neighbor) or layout.is_occupied(neighbor) or not is_in_bounds(neighbor):
					continue
				seen[neighbor] = true
				_socket_cells.append(neighbor)

	_recompute_reachable_cells()


## Which cells you can actually *click* to place the selected part — its legal
## anchor cells, not every cell it would end up covering. Clicking is anchored
## (see ShipBuilderPanel._on_hex_clicked), so lighting up covered cells was
## actively misleading: with a three-hex part it lit a band three cells deep,
## most of which reject the placement when clicked.
##
## A multi-hex module can legally anchor on a cell that isn't itself against the
## hull, as long as one of its other cells is. So rather than sweeping the whole
## field, this walks the socket ring and asks, for each cell, "what anchor would
## put some part of this module here?" — footprint size times ring size, instead
## of the whole 20x20 grid.
func _recompute_reachable_cells() -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(_build_type_id)
	if module_type == null:
		return

	for socket in _socket_cells:
		for offset in module_type.footprint_cells:
			var anchor: Vector2i = socket - HexUtils.rotate(offset, _build_rotation)
			if _reachable_cells.has(anchor):
				continue

			var cells: Array[Vector2i] = layout.get_candidate_cells(_build_type_id, anchor, _build_rotation)
			var in_bounds: bool = true
			for cell in cells:
				if not is_in_bounds(cell):
					in_bounds = false
					break
			if in_bounds and layout.can_place(_build_type_id, anchor, _build_rotation):
				_reachable_cells[anchor] = true


func _draw_placements() -> void:
	var occupant_by_cell: Dictionary = _build_occupant_lookup()
	# Same seam rule as the in-game hull (see ShipLayoutRenderer): edges inside
	# one part aren't drawn, edges between two parts are, so the builder shows
	# the ship as the pile of separate objects it is rather than a hex field.
	var seam_points := PackedVector2Array()
	var weld_points := PackedVector2Array()
	var weld_bolt_points := PackedVector2Array()
	var shadow_offset: Vector2 = HullPaint.part_shadow_offset(cell_size)

	for hex_coord in occupant_by_cell:
		var occupant: Array = occupant_by_cell[hex_coord]
		var placement: ModulePlacement = occupant[0]
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)

		# Same nudge the in-game hull applies (see HullPaint), so the ship you
		# are assembling is the ship you will fly rather than an idealised
		# schematic of it.
		var corners: PackedVector2Array = HullPaint.jittered_corners(
			_hex_corners(_axial_to_pixel(hex_coord)),
			_center + HullPaint.part_centroid(layout, placement, cell_size),
			HullPaint.part_offset(placement.instance, cell_size),
			HullPaint.part_rotation(placement.instance))

		draw_colored_polygon(_shifted(corners, shadow_offset), HullPaint.SHADOW_COLOR)
		_draw_module_glow(corners, placement)

		var tint: Color = HullPaint.part_tint(placement, faction_id)
		var hex_texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, occupant[1]) if module_type != null else null
		if hex_texture != null:
			var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(placement.rotation_steps)
			draw_colored_polygon(corners, tint, uvs, hex_texture)
		else:
			draw_colored_polygon(corners,
				(module_type.color * tint) if module_type != null else BuilderTheme.INPUT_DARK)

		_collect_joint_edges(hex_coord, corners, placement, occupant_by_cell,
			seam_points, weld_points, weld_bolt_points)

		if placement.placement_id == selected_placement_id:
			_stroke_polygon(corners, BuilderTheme.CYAN_BRIGHT, 2.0)

	if not seam_points.is_empty():
		draw_multiline(seam_points, SEAM_COLOR, SEAM_WIDTH)
	if not weld_points.is_empty():
		draw_multiline(weld_points, WELD_COLOR, WELD_WIDTH)
	if not weld_bolt_points.is_empty():
		draw_multiline(weld_bolt_points, WELD_BOLT_COLOR, WELD_BOLT_WIDTH)


func _shifted(corners: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	moved.resize(corners.size())
	for i in corners.size():
		moved[i] = corners[i] + offset
	return moved


## Each shared edge is found once from each side; the `>=` skip keeps a single
## copy so the joint isn't drawn twice over.
func _collect_joint_edges(cell: Vector2i, corners: PackedVector2Array, placement: ModulePlacement,
		occupant_by_cell: Dictionary, seam_points: PackedVector2Array,
		weld_points: PackedVector2Array, weld_bolt_points: PackedVector2Array) -> void:
	for edge in HexUtils.EDGE_DIRECTIONS.size():
		var occupant: Variant = occupant_by_cell.get(cell + HexUtils.EDGE_DIRECTIONS[edge])
		if occupant == null:
			continue
		var neighbour: ModulePlacement = occupant[0]
		if placement.placement_id >= neighbour.placement_id:
			continue

		var from: Vector2 = corners[edge]
		var to: Vector2 = corners[(edge + 1) % corners.size()]
		if HullPaint.is_clean_joint(placement, neighbour):
			seam_points.append(from)
			seam_points.append(to)
		else:
			HullPaint.append_weld(from, to, weld_points, weld_bolt_points)


## The handoff's per-tile drop shadow: a dark halo for ordinary modules, a
## noticeably stronger cyan one for the Command Core so the ship's single
## critical hex reads at a glance.
func _draw_module_glow(corners: PackedVector2Array, placement: ModulePlacement) -> void:
	var is_core: bool = placement.placement_id == (layout.core_placement_id if layout != null else "")
	var glow_color: Color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.35) if is_core else Color(0, 0, 0, 0.4)
	var rings: int = 3 if is_core else 2
	for ring in range(rings, 0, -1):
		var scale_factor: float = 1.0 + 0.09 * ring
		var expanded := PackedVector2Array()
		for corner in corners:
			expanded.append(_center + (corner - _center) * 1.0 + (corner - _polygon_centre(corners)) * (scale_factor - 1.0))
		draw_colored_polygon(expanded, BuilderTheme.with_alpha(glow_color, glow_color.a / float(rings + ring)))


func _polygon_centre(corners: PackedVector2Array) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for corner in corners:
		total += corner
	return total / corners.size()


## Weapon-hardpoint turret overlay art (turret_360/etc) is one whole icon
## meant to sit centered on a hardpoint's entire footprint — not per-cell art
## like the base plate — so it's drawn once per placement here rather than
## once per occupied hex (drawing it in the main per-cell loop left 2-3
## overlapping copies of the same icon crammed into individual hexes for any
## multi-hex tier). Sized/rotated the same way HardpointGun's live turret
## sprite is (see HardpointGun.set_turret_texture/_update_turret_transform),
## so the preview roughly matches what the gun looks like in-game.
func _draw_hardpoint_overlays() -> void:
	if layout == null:
		return
	for placement in layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue
		# Same rule as the mounted gun (see HardpointBank._mount_gun): the turret
		# is drawn in its own maker's art and tinted with its plate.
		var art_faction: String = HullPaint.art_faction_for(placement.instance, faction_id)
		var overlay_texture: Texture2D = module_type.get_hex_overlay_texture(art_faction)
		if overlay_texture == null:
			overlay_texture = module_type.get_hex_overlay_texture(faction_id)
		if overlay_texture == null:
			continue

		var occupied_cells: Array[Vector2i] = layout.get_occupied_cells(placement)
		var center_local: Vector2 = Vector2.ZERO
		for cell in occupied_cells:
			center_local += HexUtils.axial_to_pixel(cell, cell_size)
		center_local /= occupied_cells.size()
		var center: Vector2 = _center + center_local

		var length: float = cell_size * 2.0 * HardpointGun.tier_visual_scale(module_type.tier)
		var texture_size: Vector2 = overlay_texture.get_size()
		var scale_factor: float = length / (texture_size.y * 0.5)
		var half_size: Vector2 = texture_size * scale_factor * 0.5
		var angle: float = deg_to_rad(60.0 * placement.rotation_steps)
		var local_corners: Array[Vector2] = [
			Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y),
		]
		var corners := PackedVector2Array()
		for local_corner in local_corners:
			corners.append(center + local_corner.rotated(angle))
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		draw_colored_polygon(corners, HullPaint.part_tint(placement, faction_id), uvs, overlay_texture)


## The candidate cell(s) under the cursor: the module's own art at reduced
## opacity under a slowly pulsing dashed outline — cyan when the placement is
## legal, warm red when it is not.
func _draw_preview() -> void:
	if _preview_cells.is_empty():
		return

	var module_type: ModuleType = ModuleCatalog.get_by_id(_preview_module_type_id)
	var pulse: float = 0.5 - 0.5 * cos(TAU * _pulse_time / PULSE_PERIOD)
	var alpha: float = lerpf(PULSE_MIN_ALPHA, 1.0, pulse)
	var outline_color: Color = BuilderTheme.with_alpha(
		BuilderTheme.CYAN if _preview_valid else BuilderTheme.WARN, alpha)

	for i in _preview_cells.size():
		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(_preview_cells[i]))
		var hex_texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, i) if module_type != null else null
		if hex_texture != null:
			var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(_preview_rotation_steps)
			draw_colored_polygon(corners, Color(1, 1, 1, 0.45), uvs, hex_texture)
		elif module_type != null:
			draw_colored_polygon(corners, BuilderTheme.with_alpha(module_type.color, 0.45))
		if not _preview_valid:
			draw_colored_polygon(corners, BuilderTheme.with_alpha(BuilderTheme.WARN, 0.2))
		_draw_dashed_polygon(corners, outline_color, 1.5)


func _stroke_polygon(corners: PackedVector2Array, color: Color, width: float) -> void:
	for i in corners.size():
		draw_line(corners[i], corners[(i + 1) % corners.size()], color, width)


func _draw_dashed_polygon(corners: PackedVector2Array, color: Color, width: float) -> void:
	for i in corners.size():
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % corners.size()]
		var edge_length: float = from.distance_to(to)
		var direction: Vector2 = (to - from) / maxf(edge_length, 0.001)
		var travelled: float = 0.0
		while travelled < edge_length:
			var dash_end: float = minf(travelled + DASH_LENGTH, edge_length)
			draw_line(from + direction * travelled, from + direction * dash_end, color, width)
			travelled = dash_end + DASH_GAP


## hex_coord -> [ModulePlacement, cell_index], cell_index being this cell's
## position within the placement's footprint_cells order — needed to look up
## per-cell base art for multi-hex modules (see
## ModuleType.faction_hex_textures_per_cell).
func _build_occupant_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	if layout == null:
		return lookup
	for placement in layout.placements:
		var cells: Array[Vector2i] = layout.get_occupied_cells(placement)
		for i in cells.size():
			lookup[cells[i]] = [placement, i]
	return lookup


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex_coord: Vector2i = _pixel_to_axial(event.position)
		if is_in_bounds(hex_coord):
			hex_clicked.emit(hex_coord)
	elif event is InputEventMouseMotion:
		var hex_coord: Vector2i = _pixel_to_axial(event.position)
		if is_in_bounds(hex_coord):
			hex_hovered.emit(hex_coord)
		else:
			hover_exited.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_exited.emit()


func set_preview(cells: Array[Vector2i], valid: bool, module_type_id: String = "", rotation_steps: int = 0) -> void:
	_preview_cells = cells
	_preview_valid = valid
	_preview_module_type_id = module_type_id
	_preview_rotation_steps = rotation_steps
	# The pulse only animates while there is something to pulse.
	set_process(not cells.is_empty())
	queue_redraw()


func clear_preview() -> void:
	_preview_cells = []
	_preview_module_type_id = ""
	set_process(false)
	queue_redraw()


func refresh() -> void:
	_recompute_sockets()
	queue_redraw()


## Number of grid cells currently occupied by placed modules, for the bottom
## bar's used/max readout.
func used_cell_count() -> int:
	if layout == null:
		return 0
	var total: int = 0
	for placement in layout.placements:
		total += layout.get_occupied_cells(placement).size()
	return total


func total_cell_count() -> int:
	return grid_width * grid_height


func is_in_bounds(hex_coord: Vector2i) -> bool:
	var r_min: int = -grid_height / 2
	if hex_coord.y < r_min or hex_coord.y >= r_min + grid_height:
		return false
	var q_min: int = -grid_width / 2 - _row_q_offset(hex_coord.y)
	return hex_coord.x >= q_min and hex_coord.x < q_min + grid_width


## Each axial row is horizontally offset by half a cell per row in pixel
## space (see HexUtils.axial_to_pixel), so a plain fixed q-range per row
## draws as a parallelogram with diagonal left/right edges. Shifting q_min
## by this row offset instead produces a stepped, zig-zagging edge that
## reads as an overall rectangle.
func _row_q_offset(r: int) -> int:
	return floori(r / 2.0)


func _axial_to_pixel(hex_coord: Vector2i) -> Vector2:
	return _center + HexUtils.axial_to_pixel(hex_coord, cell_size)


func _pixel_to_axial(pixel: Vector2) -> Vector2i:
	return HexUtils.pixel_to_axial(pixel - _center, cell_size)


func _hex_corners(center: Vector2) -> PackedVector2Array:
	return HexUtils.hex_corners(center, cell_size)

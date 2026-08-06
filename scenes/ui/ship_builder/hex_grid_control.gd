class_name HexGridControl
extends Control

## The ship builder's build field: the faint hex lattice, the ship under
## construction, and the placement preview.
##
## Styled to docs/design_handoff_ship_builder/README.md ("Hex grid field").
## The lattice is deliberately not a rigid grid — per-hex stroke opacity fades
## from the centre outwards and a vignette darkens the border, so it reads as
## depth. The container's rounded frame is the parent PanelContainer's
## stylebox; everything inside it is drawn here.

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

## Lattice stroke opacity at the centre of the field and at its edge.
const LATTICE_OPACITY_CENTRE: float = 0.22
const LATTICE_OPACITY_EDGE: float = 0.05
const LATTICE_FILL: Color = Color(1, 1, 1, 0.012)

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
	_draw_lattice()
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


## Empty cells only — near-invisible fill with a stroke that fades towards the
## edges of the field.
func _draw_lattice() -> void:
	var falloff_radius: float = maxf(size.length() * 0.5, 1.0)
	for hex_coord in _all_coords_in_bounds():
		var centre: Vector2 = _axial_to_pixel(hex_coord)
		var corners: PackedVector2Array = _hex_corners(centre)
		draw_colored_polygon(corners, LATTICE_FILL)

		var distance_fraction: float = clampf(centre.distance_to(_center) / falloff_radius, 0.0, 1.0)
		var opacity: float = lerpf(LATTICE_OPACITY_CENTRE, LATTICE_OPACITY_EDGE, distance_fraction)
		_stroke_polygon(corners, BuilderTheme.with_alpha(BuilderTheme.CYAN, opacity), 1.0)


func _draw_placements() -> void:
	var occupant_by_cell: Dictionary = _build_occupant_lookup()
	for hex_coord in occupant_by_cell:
		var occupant: Array = occupant_by_cell[hex_coord]
		var placement: ModulePlacement = occupant[0]
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(hex_coord))

		_draw_module_glow(corners, placement)

		var hex_texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, occupant[1]) if module_type != null else null
		if hex_texture != null:
			var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(placement.rotation_steps)
			draw_colored_polygon(corners, Color.WHITE, uvs, hex_texture)
		else:
			draw_colored_polygon(corners, module_type.color if module_type != null else BuilderTheme.INPUT_DARK)

		if placement.placement_id == selected_placement_id:
			_stroke_polygon(corners, BuilderTheme.CYAN_BRIGHT, 2.0)


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
		var overlay_texture: Texture2D = module_type.get_hex_overlay_texture(faction_id)
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
		draw_colored_polygon(corners, Color.WHITE, uvs, overlay_texture)


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


func _all_coords_in_bounds() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var r_min: int = -grid_height / 2
	for r in range(r_min, r_min + grid_height):
		var q_min: int = -grid_width / 2 - _row_q_offset(r)
		for q in range(q_min, q_min + grid_width):
			coords.append(Vector2i(q, r))
	return coords


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

class_name HexGridControl
extends Control

signal hex_clicked(hex_coord: Vector2i)
signal hex_hovered(hex_coord: Vector2i)
signal hover_exited

@export var cell_size: float = 32.0
@export var grid_width: int = 20
@export var grid_height: int = 10

var layout: ShipLayout
var selected_placement_id: String = ""

var _center: Vector2
var _preview_cells: Array[Vector2i] = []
var _preview_valid: bool = true


func _ready() -> void:
	_center = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Hex art is authored at a much higher resolution than it renders at in
	# the builder preview, so mipmapped filtering is needed to avoid
	# minification aliasing.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var occupant_by_cell: Dictionary = _build_occupant_lookup()

	for hex_coord in _all_coords_in_bounds():
		var placement: ModulePlacement = occupant_by_cell.get(hex_coord)
		var fill_color: Color = Color(0.15, 0.16, 0.18, 1.0)
		var hex_texture: Texture2D = null
		if placement != null:
			var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
			if module_type != null:
				fill_color = module_type.color
				hex_texture = module_type.hex_texture

		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(hex_coord))
		if hex_texture != null:
			draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), hex_texture)
		else:
			draw_colored_polygon(corners, fill_color)

		var outline_color: Color = Color(0.9, 0.9, 0.9, 0.9) if placement != null and placement.placement_id == selected_placement_id else Color(0.4, 0.4, 0.45, 0.8)
		for i in corners.size():
			draw_line(corners[i], corners[(i + 1) % corners.size()], outline_color, 2.0)

		if placement != null and hex_coord == placement.hex_coord:
			var center: Vector2 = _axial_to_pixel(hex_coord)
			var angle: float = deg_to_rad(60.0 * placement.rotation_steps - 90.0)
			var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * cell_size * 0.8
			draw_line(center, tip, Color.WHITE, 3.0)

	_draw_preview()


func _draw_preview() -> void:
	if _preview_cells.is_empty():
		return

	var overlay_color: Color = Color(0.3, 1.0, 0.4, 0.45) if _preview_valid else Color(1.0, 0.3, 0.3, 0.45)
	for cell in _preview_cells:
		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(cell))
		draw_colored_polygon(corners, overlay_color)
		for i in corners.size():
			draw_line(corners[i], corners[(i + 1) % corners.size()], overlay_color.lightened(0.3), 2.0)


func _build_occupant_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	if layout == null:
		return lookup
	for placement in layout.placements:
		for cell in layout.get_occupied_cells(placement):
			lookup[cell] = placement
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


func set_preview(cells: Array[Vector2i], valid: bool) -> void:
	_preview_cells = cells
	_preview_valid = valid
	queue_redraw()


func clear_preview() -> void:
	_preview_cells = []
	queue_redraw()


func refresh() -> void:
	queue_redraw()


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
	var local: Vector2 = pixel - _center
	var qf: float = (HexUtils.SQRT3 / 3.0 * local.x - 1.0 / 3.0 * local.y) / cell_size
	var rf: float = (2.0 / 3.0 * local.y) / cell_size
	return _hex_round(qf, rf)


func _hex_round(qf: float, rf: float) -> Vector2i:
	var xf: float = qf
	var zf: float = rf
	var yf: float = -xf - zf

	var rx: float = roundf(xf)
	var ry: float = roundf(yf)
	var rz: float = roundf(zf)

	var x_diff: float = absf(rx - xf)
	var y_diff: float = absf(ry - yf)
	var z_diff: float = absf(rz - zf)

	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))


func _hex_corners(center: Vector2) -> PackedVector2Array:
	return HexUtils.hex_corners(center, cell_size)

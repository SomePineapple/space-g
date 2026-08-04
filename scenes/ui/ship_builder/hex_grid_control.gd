class_name HexGridControl
extends Control

signal hex_clicked(hex_coord: Vector2i)
signal hex_hovered(hex_coord: Vector2i)
signal hover_exited

@export var cell_size: float = 32.0
@export var grid_width: int = 20
@export var grid_height: int = 10

## Which faction's reskin the builder previews modules with — set by
## ShipBuilderPanel from the ship actually being edited (see ModuleType.
## faction_hex_textures).
var faction_id: String = "corporate"

var layout: ShipLayout
var selected_placement_id: String = ""

var _center: Vector2
var _preview_cells: Array[Vector2i] = []
var _preview_valid: bool = true
var _preview_module_type_id: String = ""
var _preview_rotation_steps: int = 0


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
		var occupant: Array = occupant_by_cell.get(hex_coord, [])
		var placement: ModulePlacement = occupant[0] if not occupant.is_empty() else null
		var fill_color: Color = Color(0.15, 0.16, 0.18, 1.0)
		var hex_texture: Texture2D = null
		if placement != null:
			var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
			if module_type != null:
				fill_color = module_type.color
				hex_texture = module_type.get_hex_texture_for_cell(faction_id, occupant[1])

		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(hex_coord))
		if hex_texture != null:
			var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(placement.rotation_steps)
			draw_colored_polygon(corners, Color.WHITE, uvs, hex_texture)
		else:
			draw_colored_polygon(corners, fill_color)

		var outline_color: Color = Color(0.9, 0.9, 0.9, 0.9) if placement != null and placement.placement_id == selected_placement_id else Color(0.4, 0.4, 0.45, 0.8)
		for i in corners.size():
			draw_line(corners[i], corners[(i + 1) % corners.size()], outline_color, 2.0)

		if placement != null and hex_coord == placement.hex_coord:
			var center: Vector2 = _axial_to_pixel(hex_coord)
			# This "- 90" is a DELIBERATE, KNOWN mismatch — do not "fix" it by
			# removing the offset. Without it, rotation_steps=0 points along
			# raw +X (screen-right); with it, rotation_steps=0 points screen-up,
			# which is what players expect an unrotated module to do and what
			# this arrow has always shown.
			#
			# It cannot be made to exactly track the real hex-neighbor
			# direction: HexUtils.rotate(Vector2i(1, 0), rotation_steps) only
			# ever lands on 60°*rotation_steps (0/60/120/180/240/300 — verified
			# live against a Railgun's actual second/front hex), and
			# none of those six angles is exactly "up" (-90°/270°). So this is
			# a smooth, UX-only preview arrow, not a literal pointer at the
			# real occupied front cell — for a multi-hex module (e.g. the
			# Railgun), the module's own second hex tile IS that real
			# direction; for a single-hex fixed-facing hardpoint (e.g. the
			# Mining Grinder, or any Weapon Hardpoint), the real
			# in-flight direction is 60°*rotation_steps + Ship._hull_renderer.
			# rotation (see docs/gotchas.md's "+90° fixed offset" entry) —
			# expect it to look diagonal in-flight even when this arrow points
			# straight up here. A previous session removed the "- 90" to make
			# this arrow match the real hex math exactly; it was reverted by
			# explicit request in favor of "still looks like it points up."
			var angle: float = deg_to_rad(60.0 * placement.rotation_steps - 90.0)
			var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * cell_size * 0.8
			draw_line(center, tip, Color.WHITE, 3.0)

	_draw_hardpoint_overlays()
	_draw_preview()


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


func _draw_preview() -> void:
	if _preview_cells.is_empty():
		return

	var module_type: ModuleType = ModuleCatalog.get_by_id(_preview_module_type_id)
	var tint_color: Color = Color(0.3, 1.0, 0.4, 0.35) if _preview_valid else Color(1.0, 0.3, 0.3, 0.35)
	var outline_color: Color = tint_color.lightened(0.3)
	outline_color.a = 0.9

	for i in _preview_cells.size():
		var cell: Vector2i = _preview_cells[i]
		var corners: PackedVector2Array = _hex_corners(_axial_to_pixel(cell))
		var hex_texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, i) if module_type != null else null
		if hex_texture != null:
			var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(_preview_rotation_steps)
			draw_colored_polygon(corners, Color.WHITE, uvs, hex_texture)
		elif module_type != null:
			draw_colored_polygon(corners, module_type.color)
		draw_colored_polygon(corners, tint_color)
		for j in corners.size():
			draw_line(corners[j], corners[(j + 1) % corners.size()], outline_color, 2.0)


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
	queue_redraw()


func clear_preview() -> void:
	_preview_cells = []
	_preview_module_type_id = ""
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
	return HexUtils.pixel_to_axial(pixel - _center, cell_size)


func _hex_corners(center: Vector2) -> PackedVector2Array:
	return HexUtils.hex_corners(center, cell_size)

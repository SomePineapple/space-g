class_name ModuleHexIcon
extends Control

## The icon shown next to a part in the builder's list.
##
## Draws the module's whole footprint, not a single hex — a Hull Spar is three
## hexes in a line and a Hull Wedge is three in a triangle, and the list is where
## you decide which of them to reach for, so the shape has to be visible before
## you pick it up. The footprint is scaled to fit the icon box, so a 1-hex part
## draws large and a 3-hex part draws smaller but keeps its silhouette.
##
## The handoff specifies a gradient-filled hex with a 2-letter glyph placeholder
## "to swap for real module icon art when available". This project already has
## that art (ModuleType.faction_hex_textures), so the real hex texture is drawn
## per cell when one exists and the gradient + glyph is the fallback for the
## module types that still have none (Railgun, Phase Lance, some weapon tiers).

## Reference sizes from the handoff: 38x44 normally, 48x55 when the row is
## selected. Both are the 222:256 hex ratio.
const SIZE_DEFAULT: Vector2 = Vector2(38, 44)
const SIZE_SELECTED: Vector2 = Vector2(48, 55)
const GLYPH_SIZE_DEFAULT: int = 10
const GLYPH_SIZE_SELECTED: int = 12

## Multi-hex footprints are drawn into a wider box than the handoff's single
## hex, so a three-in-a-line part doesn't shrink to nothing to fit a 38px slot.
const MULTI_CELL_WIDTH_SCALE: float = 1.5

## Direction of the handoff's `linear-gradient(155deg, ...)`, in the same
## screen space the hex is drawn in.
const GRADIENT_ANGLE_DEGREES: float = 155.0

var module_type: ModuleType
var faction_id: String = "corporate"
var selected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The hex art is authored far larger than this icon renders at; without a
	# mip chain it shimmers (see CLAUDE.md "Texture import settings").
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_apply_size()


func configure(new_module_type: ModuleType, new_faction_id: String) -> void:
	module_type = new_module_type
	faction_id = new_faction_id
	_apply_size()
	queue_redraw()


func set_selected(is_selected: bool) -> void:
	if selected == is_selected:
		return
	selected = is_selected
	_apply_size()
	queue_redraw()


func _apply_size() -> void:
	custom_minimum_size = _icon_box()


## Single-hex parts keep the handoff's exact box. Anything larger gets a wider
## one, since a three-hex footprint squeezed into a 38px slot reads as a smudge.
func _icon_box() -> Vector2:
	var box: Vector2 = SIZE_SELECTED if selected else SIZE_DEFAULT
	if module_type != null and module_type.footprint_cells.size() > 1:
		box.x *= MULTI_CELL_WIDTH_SCALE
	return box


func _draw() -> void:
	if module_type == null:
		return

	# custom_minimum_size drives the row's layout, but the control itself may be
	# stretched taller by the row — keep the footprint at its own aspect.
	var icon_size: Vector2 = _icon_box()
	var cell_size: float = _fitted_cell_size(icon_size)
	var origin: Vector2 = Vector2(icon_size.x * 0.5, size.y * 0.5) - _footprint_centre(cell_size)

	for i in module_type.footprint_cells.size():
		var centre: Vector2 = origin + HexUtils.axial_to_pixel(module_type.footprint_cells[i], cell_size)
		var corners: PackedVector2Array = HexUtils.hex_corners(centre, cell_size)
		var texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, i)
		if texture != null:
			draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), texture)
		else:
			_draw_gradient_hex(corners)

	# One glyph for the whole part rather than one per cell — it names the part,
	# it isn't a label on each hex.
	if module_type.get_hex_texture_for_cell(faction_id, 0) == null:
		_draw_glyph(Vector2(icon_size.x * 0.5, size.y * 0.5), icon_size)


## Largest cell size that fits the whole footprint inside the icon box.
func _fitted_cell_size(icon_size: Vector2) -> float:
	var extent: Rect2 = _footprint_extent(1.0)
	var by_width: float = icon_size.x / maxf(extent.size.x, 0.001)
	var by_height: float = icon_size.y / maxf(extent.size.y, 0.001)
	return minf(by_width, by_height)


func _footprint_centre(cell_size: float) -> Vector2:
	var extent: Rect2 = _footprint_extent(cell_size)
	return extent.position + extent.size * 0.5


## Bounding box of every hex in the footprint at the given cell size, corners
## included — a hex extends half a cell past its centre vertically and
## SQRT3/2 horizontally.
func _footprint_extent(cell_size: float) -> Rect2:
	var half: Vector2 = Vector2(HexUtils.SQRT3 * 0.5, 1.0) * cell_size
	var extent := Rect2()
	for i in module_type.footprint_cells.size():
		var centre: Vector2 = HexUtils.axial_to_pixel(module_type.footprint_cells[i], cell_size)
		var cell_box := Rect2(centre - half, half * 2.0)
		extent = cell_box if i == 0 else extent.merge(cell_box)
	return extent


func _draw_gradient_hex(corners: PackedVector2Array) -> void:
	var colors: Array = ModulePresentation.gradient(module_type)
	var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(GRADIENT_ANGLE_DEGREES))

	var projections: PackedFloat32Array = PackedFloat32Array()
	var lowest: float = INF
	var highest: float = -INF
	for corner in corners:
		var projection: float = corner.dot(axis)
		projections.append(projection)
		lowest = minf(lowest, projection)
		highest = maxf(highest, projection)

	var vertex_colors := PackedColorArray()
	var span: float = maxf(highest - lowest, 0.001)
	for projection in projections:
		vertex_colors.append(colors[0].lerp(colors[1], (projection - lowest) / span))
	draw_polygon(corners, vertex_colors)


func _draw_glyph(centre: Vector2, icon_size: Vector2) -> void:
	var font: Font = BuilderTheme.mono_font()
	var font_size: int = GLYPH_SIZE_SELECTED if selected else GLYPH_SIZE_DEFAULT
	var baseline: Vector2 = Vector2(0, centre.y + font_size * 0.36)
	font.draw_string(get_canvas_item(), baseline, ModulePresentation.glyph(module_type),
		HORIZONTAL_ALIGNMENT_CENTER, icon_size.x, font_size, ModulePresentation.glyph_color(module_type))



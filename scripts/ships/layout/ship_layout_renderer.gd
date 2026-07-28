class_name ShipLayoutRenderer
extends Node2D

## Draws a Ship's hull directly from its ShipLayout, so any ship's
## appearance always matches its actual module composition.

@export var ship_layout: ShipLayout
@export var cell_size: float = 24.0

const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)


func _ready() -> void:
	# Hex art is authored at a much higher resolution than it renders at in
	# game, so mipmapped filtering is needed to avoid minification aliasing.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_layout(new_layout: ShipLayout) -> void:
	ship_layout = new_layout
	queue_redraw()


func _draw() -> void:
	if ship_layout == null:
		return

	for placement in ship_layout.placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		for cell in ship_layout.get_occupied_cells(placement):
			var corners: PackedVector2Array = HexUtils.hex_corners(HexUtils.axial_to_pixel(cell, cell_size), cell_size)
			if module_type.hex_texture != null:
				draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), module_type.hex_texture)
			else:
				draw_colored_polygon(corners, module_type.color)
			for i in corners.size():
				draw_line(corners[i], corners[(i + 1) % corners.size()], OUTLINE_COLOR, 2.0)

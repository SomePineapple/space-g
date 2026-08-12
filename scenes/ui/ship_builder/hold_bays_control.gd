class_name HoldBaysControl
extends Control

## Draws the hold's bays as hex clusters and turns clicks into a (bay, cell)
## pair — the INVENTORY tab's grid
## (`docs/design_handoff_ship_builder_inv/README.md`).
##
## Presentation only: it is handed a ShipHold to read and never mutates it, the
## same division ModuleListView makes with the parts pool.
##
## Cells are drawn small on purpose. The handoff asks for ~34×39px so a bay never
## reads as big as the hull hexes on the build field — this is a manifest of what
## is in the hold, not a second ship to build.

signal cell_clicked(bay_index: int, cell: Vector2i)

const CELL_SIZE: float = 20.0
const BAY_LABEL_HEIGHT: float = 16.0
const BAY_GAP: float = 12.0
const OUTLINE_WIDTH: float = 1.0
## Fallback glyph size, for module types that still have no hex art.
const GLYPH_SIZE: int = 9

var hold: ShipHold = null
## instance_id -> ModuleInstance, for naming and drawing what is stowed.
var contents: Dictionary = {}
## The hull's faction, used only as the fallback for a part that isn't salvaged
## — a gun cut off a raider is drawn in the raider's plating (see HullPaint).
var faction_id: String = "corporate"
## bay index -> {cell -> which cell of the part's own footprint this is}, so a
## multi-hex part draws its real plates rather than its first one repeated.
var _cell_art_index: Dictionary = {}
## Cells a pending part would claim if stowed at the hovered cell, so the player
## can see a two-hex part's shape before committing to it.
var _preview: Array[Vector2i] = []
var _preview_bay: int = -1
var _hover_bay: int = -1
var _hover_cell: Vector2i = Vector2i.ZERO
## bay index -> the pixel offset its cluster is drawn at.
var _bay_origins: Dictionary = {}
## bay index -> the baseline its label sits on, kept apart from the cluster
## origin because a tall cluster's centre is nowhere near its heading.
var _bay_label_y: Dictionary = {}
## Set while a part is waiting to be stowed; open cells invite a click.
var pending_size: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Hex art is authored far larger than a hold cell; without a mip chain it
	# shimmers (see CLAUDE.md "Texture import settings").
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func refresh() -> void:
	_layout_bays()
	_map_cell_art()
	queue_redraw()


## Stacks the bays down the card, each one centred on its own width.
func _layout_bays() -> void:
	_bay_origins = {}
	if hold == null:
		custom_minimum_size = Vector2(0.0, 0.0)
		return
	_bay_label_y = {}
	var y: float = 0.0
	for index in hold.bay_count():
		_bay_label_y[index] = y + BAY_LABEL_HEIGHT * 0.75
		y += BAY_LABEL_HEIGHT
		var bounds: Rect2 = _cluster_bounds(hold.bay_cells(index))
		_bay_origins[index] = Vector2(size.x * 0.5 - bounds.get_center().x, y - bounds.position.y)
		y += bounds.size.y + BAY_GAP
	custom_minimum_size = Vector2(0.0, maxf(y, 40.0))


func _cluster_bounds(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var bounds: Rect2 = Rect2(HexUtils.axial_to_pixel(cells[0], CELL_SIZE), Vector2.ZERO)
	for cell in cells:
		bounds = bounds.expand(HexUtils.axial_to_pixel(cell, CELL_SIZE))
	# The points above are centres; grow by one cell so the outermost hexes fit.
	return bounds.grow_individual(CELL_SIZE, CELL_SIZE, CELL_SIZE, CELL_SIZE)


func _draw() -> void:
	if hold == null:
		return
	for index in hold.bay_count():
		_draw_bay(index)


func _draw_bay(index: int) -> void:
	var origin: Vector2 = _bay_origins.get(index, Vector2.ZERO)
	var label: String = "%s · %d/%d" % [hold.bay_label(index).to_upper(),
		hold.bay_used(index), hold.bay_cells(index).size()]
	draw_string(BuilderTheme.mono_font(), Vector2(2.0, _bay_label_y.get(index, 0.0)), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BuilderTheme.TEXT_LABEL)

	for cell in hold.bay_cells(index):
		var centre: Vector2 = origin + HexUtils.axial_to_pixel(cell, CELL_SIZE)
		var corners: PackedVector2Array = HexUtils.hex_corners(centre, CELL_SIZE)
		var occupant: String = hold.occupant(index, cell)
		if occupant.is_empty():
			draw_colored_polygon(corners, _fill_for(index, cell))
		else:
			_draw_part_cell(index, cell, centre, corners, occupant)
		draw_polyline(_closed(corners), _outline_for(index, cell, occupant), OUTLINE_WIDTH)


## The part as it actually looks — the same hex plate the builder and the hull
## draw, in the art of whoever built it. A stowed gun should be recognisable as
## the gun you cut off, not as a coloured dot standing in for one.
func _draw_part_cell(index: int, cell: Vector2i, centre: Vector2,
		corners: PackedVector2Array, instance_id: String) -> void:
	var instance: ModuleInstance = contents.get(instance_id, null)
	var module_type: ModuleType = null
	if instance != null:
		module_type = ModuleCatalog.get_by_id(instance.module_type_id)
	if module_type == null:
		draw_colored_polygon(corners, BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.14))
		return

	var art_faction: String = HullPaint.art_faction_for(instance, faction_id)
	var cell_index: int = _cell_art_index.get(index, {}).get(cell, 0)
	var texture: Texture2D = module_type.get_hex_texture_for_cell(art_faction, cell_index)
	if texture == null:
		_draw_fallback_cell(centre, corners, module_type)
		return

	draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), texture)
	# Lit parts on top, as on the hull and in the parts list.
	var glow: Texture2D = module_type.get_hex_glow_texture_for_cell(art_faction, cell_index)
	if glow != null:
		draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), glow)


## Module types with no hex art yet (Railgun, Phase Lance) keep the list's
## gradient-and-glyph treatment rather than vanishing into an empty cell.
func _draw_fallback_cell(centre: Vector2, corners: PackedVector2Array,
		module_type: ModuleType) -> void:
	draw_colored_polygon(corners, ModulePresentation.gradient(module_type)[0])
	draw_string(BuilderTheme.mono_font(), centre + Vector2(-CELL_SIZE, GLYPH_SIZE * 0.36),
		ModulePresentation.glyph(module_type), HORIZONTAL_ALIGNMENT_CENTER, CELL_SIZE * 2.0,
		GLYPH_SIZE, ModulePresentation.glyph_color(module_type))


## Which cell of its own footprint each stowed cell stands for. The hold claims
## cells by flood fill, so the shape a part takes in a bay is not its footprint
## — the cells are matched to footprint indices in a stable order instead, which
## keeps a three-hex part showing three different plates rather than one plate
## three times.
func _map_cell_art() -> void:
	_cell_art_index = {}
	if hold == null:
		return
	for index in hold.bay_count():
		var groups: Dictionary = {}
		for cell in hold.bay_cells(index):
			var occupant: String = hold.occupant(index, cell)
			if occupant.is_empty():
				continue
			groups.get_or_add(occupant, []).append(cell)
		var per_cell: Dictionary = {}
		for occupant in groups:
			var cells: Array = groups[occupant]
			cells.sort_custom(_compare_cells)
			for i in cells.size():
				per_cell[cells[i]] = i
		_cell_art_index[index] = per_cell


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Open cells only — an occupied one is covered by the part's own art.
func _fill_for(index: int, cell: Vector2i) -> Color:
	if index == _preview_bay and _preview.has(cell):
		return BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.22)
	if pending_size > 0:
		return BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.05)
	return BuilderTheme.with_alpha(Color.WHITE, 0.02)


func _outline_for(index: int, cell: Vector2i, occupant: String) -> Color:
	if index == _preview_bay and _preview.has(cell):
		return BuilderTheme.CYAN_BRIGHT
	if not occupant.is_empty():
		return BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.55)
	return BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.25)


func _closed(corners: PackedVector2Array) -> PackedVector2Array:
	var loop: PackedVector2Array = corners.duplicate()
	loop.append(corners[0])
	return loop


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover(event.position)
		if _hover_bay >= 0:
			cell_clicked.emit(_hover_bay, _hover_cell)


func _update_hover(at: Vector2) -> void:
	var bay: int = -1
	var cell: Vector2i = Vector2i.ZERO
	for index in _bay_origins:
		var local: Vector2 = at - _bay_origins[index]
		var candidate: Vector2i = HexUtils.pixel_to_axial(local, CELL_SIZE)
		if hold != null and hold.bay_cells(index).has(candidate):
			bay = index
			cell = candidate
			break
	if bay == _hover_bay and cell == _hover_cell:
		return
	_hover_bay = bay
	_hover_cell = cell
	_refresh_preview()
	queue_redraw()


## What the pending part would take from the hovered cell. Empty when it will not
## fit from there, which is the "won't fit" feedback happening before the click
## rather than after it.
func _refresh_preview() -> void:
	_preview = []
	_preview_bay = -1
	if hold == null or pending_size <= 0 or _hover_bay < 0:
		return
	var claimed: Array[Vector2i] = hold.claim_from(_hover_bay, _hover_cell, pending_size)
	if claimed.is_empty():
		return
	_preview = claimed
	_preview_bay = _hover_bay


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_bay = -1
		_refresh_preview()
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_layout_bays()
		queue_redraw()

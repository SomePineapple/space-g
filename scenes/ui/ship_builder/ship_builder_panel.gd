extends CanvasLayer

const GRID_COLS: int = 20
const GRID_ROWS: int = 20
const GRID_CELL_SIZE: float = 14.0
const GRID_PIXEL_WIDTH: float = 640.0
const GRID_PIXEL_HEIGHT: float = 470.0

const SAVE_DIRECTORY: String = "user://ships"

## Only lets the builder open near the region's home base marker, so
## building/spending happens at a fixed "home", not mid-flight anywhere.
@export var home_base_range: float = 300.0

var template_layout: ShipLayout
var working_layout: ShipLayout

var _inventory: Inventory

var _selected_type_id: String = ""
var _pending_rotation: int = 0
var _has_hover: bool = false
var _last_hover_hex: Vector2i = Vector2i.ZERO

var _status_label: Label
var _stats_label: Label
var _grid: HexGridControl
var _palette_buttons: Dictionary = {}
var _save_name_edit: LineEdit
var _saved_list: ItemList


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to this specific panel.
	add_to_group("menu_panel")

	template_layout = load("res://resources/ships/starter_ship_layout.tres")
	working_layout = template_layout.duplicate(true)

	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if not players.is_empty():
		_inventory = players[0].get_node("Inventory")

	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_builder"):
		if visible:
			visible = false
			_apply_to_player_ship()
		elif _is_near_home_base():
			visible = true
		return

	if not visible:
		return

	if event.is_action_pressed("builder_rotate"):
		_on_rotate_pressed()
	elif event.is_action_pressed("builder_delete"):
		_on_remove_pressed()


func _is_near_home_base() -> bool:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if players.is_empty() or home_bases.is_empty():
		return false
	return players[0].global_position.distance_to(home_bases[0].global_position) <= home_base_range


func _apply_to_player_ship() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	var issues: Array[String] = working_layout.validate_layout()
	if not issues.is_empty():
		_status_label.text = "Cannot apply to ship: %s" % "; ".join(issues)
		return

	players[0].apply_layout(working_layout.duplicate(true))
	_status_label.text = "Applied to ship."


func _build_ui() -> void:
	var panel := Control.new()
	panel.position = Vector2(20, 60)
	add_child(panel)

	_status_label = Label.new()
	_status_label.position = Vector2(0, 0)
	_status_label.size = Vector2(GRID_PIXEL_WIDTH, 24)
	_status_label.text = "Select a module type, then click an adjacent cell."
	panel.add_child(_status_label)

	_stats_label = Label.new()
	_stats_label.position = Vector2(0, 24)
	_stats_label.size = Vector2(GRID_PIXEL_WIDTH, 20)
	panel.add_child(_stats_label)

	var palette := HBoxContainer.new()
	palette.position = Vector2(0, 48)
	panel.add_child(palette)

	for module_type in ModuleCatalog.get_all():
		var button := Button.new()
		button.text = "%s\n%s" % [module_type.display_name, _format_costs(module_type.build_costs)]
		button.toggle_mode = true
		button.pressed.connect(_on_palette_pressed.bind(module_type.id))
		palette.add_child(button)
		_palette_buttons[module_type.id] = button

	_grid = HexGridControl.new()
	_grid.position = Vector2(0, 88)
	_grid.size = Vector2(GRID_PIXEL_WIDTH, GRID_PIXEL_HEIGHT)
	_grid.cell_size = GRID_CELL_SIZE
	_grid.grid_width = GRID_COLS
	_grid.grid_height = GRID_ROWS
	_grid.layout = working_layout
	_grid.hex_clicked.connect(_on_hex_clicked)
	_grid.hex_hovered.connect(_on_hex_hovered)
	_grid.hover_exited.connect(_on_hover_exited)
	panel.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.position = Vector2(0, 88 + GRID_PIXEL_HEIGHT + 10)
	panel.add_child(actions)

	var rotate_button := Button.new()
	rotate_button.text = "Rotate"
	rotate_button.pressed.connect(_on_rotate_pressed)
	actions.add_child(rotate_button)

	var remove_button := Button.new()
	remove_button.text = "Remove Selected"
	remove_button.pressed.connect(_on_remove_pressed)
	actions.add_child(remove_button)

	var validate_button := Button.new()
	validate_button.text = "Validate Layout"
	validate_button.pressed.connect(_on_validate_pressed)
	actions.add_child(validate_button)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "ship name"
	_save_name_edit.text = "my_ship"
	_save_name_edit.custom_minimum_size = Vector2(120, 0)
	actions.add_child(_save_name_edit)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	actions.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	actions.add_child(load_button)

	_saved_list = ItemList.new()
	_saved_list.position = Vector2(0, 88 + GRID_PIXEL_HEIGHT + 40)
	_saved_list.size = Vector2(GRID_PIXEL_WIDTH, 100)
	_saved_list.item_selected.connect(_on_saved_item_selected)
	panel.add_child(_saved_list)
	_refresh_saved_list()


func _on_palette_pressed(module_type_id: String) -> void:
	_selected_type_id = module_type_id
	_pending_rotation = 0
	_grid.selected_placement_id = ""
	for id in _palette_buttons:
		_palette_buttons[id].button_pressed = (id == module_type_id)
	_status_label.text = "Placing: %s (hover the grid, Rotate to orient, click to place)" % ModuleCatalog.get_by_id(module_type_id).display_name
	_update_preview()


func _on_hex_hovered(hex_coord: Vector2i) -> void:
	_has_hover = true
	_last_hover_hex = hex_coord
	_update_preview()


func _on_hover_exited() -> void:
	_has_hover = false
	_grid.clear_preview()


func _update_preview() -> void:
	if _selected_type_id.is_empty() or not _has_hover:
		_grid.clear_preview()
		return

	var candidate_cells: Array[Vector2i] = working_layout.get_candidate_cells(_selected_type_id, _last_hover_hex, _pending_rotation)
	var reason: String = "" if _fits_in_bounds(candidate_cells) else "Out of bounds"
	if reason == "":
		reason = working_layout.get_place_rejection_reason(_selected_type_id, _last_hover_hex, _pending_rotation)

	_grid.set_preview(candidate_cells, reason == "")

	var type_name: String = ModuleCatalog.get_by_id(_selected_type_id).display_name
	if reason == "":
		_status_label.text = "Ready to place %s here." % type_name
	else:
		_status_label.text = "Cannot place %s here: %s" % [type_name, reason]


func _on_hex_clicked(hex_coord: Vector2i) -> void:
	var existing: ModulePlacement = working_layout.get_placement_at(hex_coord)
	if existing != null:
		_selected_type_id = ""
		for id in _palette_buttons:
			_palette_buttons[id].button_pressed = false
		_grid.clear_preview()
		_grid.selected_placement_id = existing.placement_id
		var module_type: ModuleType = ModuleCatalog.get_by_id(existing.module_type_id)
		_status_label.text = "Selected: %s at (%d, %d)" % [module_type.display_name, hex_coord.x, hex_coord.y]
		_grid.refresh()
		return

	if _selected_type_id.is_empty():
		_status_label.text = "Pick a module type from the palette first."
		return

	if not _fits_in_bounds(working_layout.get_candidate_cells(_selected_type_id, hex_coord, _pending_rotation)):
		_status_label.text = "Cannot place: Out of bounds"
		return

	var reason: String = working_layout.get_place_rejection_reason(_selected_type_id, hex_coord, _pending_rotation)
	if reason != "":
		_status_label.text = "Cannot place: %s" % reason
		return

	var type_to_place: ModuleType = ModuleCatalog.get_by_id(_selected_type_id)
	if _inventory != null and not _inventory.has_materials(type_to_place.build_costs):
		_status_label.text = "Cannot place %s: need %s" % [type_to_place.display_name, _format_costs(type_to_place.build_costs)]
		return

	working_layout.place(_selected_type_id, hex_coord, _pending_rotation)
	if _inventory != null:
		_inventory.spend_materials(type_to_place.build_costs)
	_status_label.text = "Placed %s." % type_to_place.display_name
	_pending_rotation = 0
	_refresh()
	_grid.clear_preview()


func _on_rotate_pressed() -> void:
	if not _grid.selected_placement_id.is_empty():
		_rotate_selected_placement()
		return

	if not _selected_type_id.is_empty():
		_pending_rotation = posmod(_pending_rotation + 1, 6)
		_update_preview()
		return

	_status_label.text = "Select a module type or a placed module first."


func _rotate_selected_placement() -> void:
	var placement: ModulePlacement = working_layout.get_placement_by_id(_grid.selected_placement_id)
	var new_rotation: int = posmod(placement.rotation_steps + 1, 6)
	var candidate_cells: Array[Vector2i] = working_layout.get_candidate_cells(placement.module_type_id, placement.hex_coord, new_rotation)
	if not _fits_in_bounds(candidate_cells):
		_status_label.text = "Cannot rotate: Out of bounds"
		return

	var reason: String = working_layout.get_rotate_rejection_reason(_grid.selected_placement_id, 1)
	if reason != "":
		_status_label.text = "Cannot rotate: %s" % reason
		return

	working_layout.rotate(_grid.selected_placement_id, 1)
	_status_label.text = "Rotated."
	_refresh()


func _fits_in_bounds(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not _grid.is_in_bounds(cell):
			return false
	return true


func _on_remove_pressed() -> void:
	if _grid.selected_placement_id.is_empty():
		_status_label.text = "Select a placed module first."
		return

	var reason: String = working_layout.get_remove_rejection_reason(_grid.selected_placement_id)
	if reason != "":
		_status_label.text = "Cannot remove: %s" % reason
		return

	var removed_placement: ModulePlacement = working_layout.get_placement_by_id(_grid.selected_placement_id)
	var removed_type: ModuleType = ModuleCatalog.get_by_id(removed_placement.module_type_id)

	working_layout.remove(_grid.selected_placement_id)
	_grid.selected_placement_id = ""

	if _inventory != null:
		for material_id in removed_type.build_costs:
			_inventory.add_material(material_id, removed_type.build_costs[material_id])
		_status_label.text = "Removed. Refunded %s." % _format_costs(removed_type.build_costs)
	else:
		_status_label.text = "Removed."
	_refresh()


func _refresh() -> void:
	_grid.refresh()
	_stats_label.text = "Max Health: %d   Mass: %.2f" % [working_layout.total_max_health(), working_layout.total_mass()]


func _format_costs(costs: Dictionary) -> String:
	var parts: Array = []
	for material_id in costs:
		parts.append("%d %s" % [costs[material_id], Materials.display_name(material_id)])
	return ", ".join(parts)


func _on_validate_pressed() -> void:
	var issues: Array[String] = working_layout.validate_layout()
	if issues.is_empty():
		_status_label.text = "Layout OK."
	else:
		_status_label.text = "Issues: %s" % "; ".join(issues)


func _on_save_pressed() -> void:
	var save_path: String = _get_save_path()
	DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)

	var error: Error = ResourceSaver.save(working_layout, save_path)
	if error != OK:
		_status_label.text = "Save failed (error %d)." % error
		return
	_status_label.text = "Saved to %s." % save_path
	_refresh_saved_list()


func _on_load_pressed() -> void:
	var save_path: String = _get_save_path()
	if not FileAccess.file_exists(save_path):
		_status_label.text = "No saved ship named '%s'." % _save_name_edit.text
		return

	var loaded: ShipLayout = ResourceLoader.load(save_path, "ShipLayout", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded == null:
		_status_label.text = "Load failed."
		return

	working_layout = loaded.duplicate(true)
	_grid.layout = working_layout
	_grid.selected_placement_id = ""
	_selected_type_id = ""
	for id in _palette_buttons:
		_palette_buttons[id].button_pressed = false
	_status_label.text = "Loaded '%s'." % _save_name_edit.text
	_refresh()


func _on_saved_item_selected(index: int) -> void:
	_save_name_edit.text = _saved_list.get_item_text(index)
	_on_load_pressed()


func _refresh_saved_list() -> void:
	_saved_list.clear()
	var dir: DirAccess = DirAccess.open(SAVE_DIRECTORY)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			_saved_list.add_item(file_name.trim_suffix(".tres"))
		file_name = dir.get_next()
	dir.list_dir_end()


func _get_save_path() -> String:
	var sanitized: String = ""
	for character in _save_name_edit.text:
		if character.is_valid_identifier() or character == "-":
			sanitized += character
	if sanitized.is_empty():
		sanitized = "ship"
	return "%s/%s.tres" % [SAVE_DIRECTORY, sanitized]

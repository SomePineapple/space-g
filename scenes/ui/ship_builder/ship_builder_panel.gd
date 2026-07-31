extends CanvasLayer

const GRID_COLS: int = 20
const GRID_ROWS: int = 20
const GRID_CELL_SIZE: float = 14.0
const GRID_PIXEL_WIDTH: float = 640.0
const GRID_PIXEL_HEIGHT: float = 450.0

const SAVE_DIRECTORY: String = "user://ships"

const CONTENT_TOP: float = 108.0
const CONTENT_LEFT: float = 20.0
const INFO_BAR_HEIGHT: float = 40.0
const ACTIONS_HEIGHT: float = 34.0
const SECTION_GAP: float = 8.0

const SIDE_PANEL_GAP: float = 20.0
const SIDE_PANEL_WIDTH: float = 260.0
const SIDE_HEADER_HEIGHT: float = 22.0
const SIDE_SAVE_ROW_HEIGHT: float = 30.0
const SIDE_SAVED_LIST_HEIGHT: float = 120.0
const SIDE_MARGIN: float = 10.0
const PALETTE_BUTTON_HEIGHT: float = 66.0
const PALETTE_BUTTON_GAP: int = 6

## "Basic backgrounds for now" per the current UI tidy-up pass — a dark
## translucent bar behind the info/status text and a neon-blue translucent
## panel behind the module list, both easy to reskin later.
const INFO_BG_COLOR: Color = Color(0.05, 0.07, 0.1, 0.55)
const GRID_BG_COLOR: Color = Color(0.03, 0.04, 0.06, 0.5)
const PALETTE_BG_COLOR: Color = Color(0.1, 0.5, 1.0, 0.5)

## Only lets the builder open near the region's home base marker, so
## building/spending happens at a fixed "home", not mid-flight anywhere.
@export var home_base_range: float = 300.0

var template_layout: ShipLayout
var working_layout: ShipLayout

var _inventory: Inventory
## Only used to read base_energy_generation/base_energy_capacity so the
## builder's energy stat matches what the ship will actually have once
## applied — the working layout's own totals don't include that baseline.
var _player_ship: Ship

var _selected_type_id: String = ""
var _pending_rotation: int = 0
var _has_hover: bool = false
var _last_hover_hex: Vector2i = Vector2i.ZERO

var _status_label: Label
var _stats_label: Label
var _grid: HexGridControl
var _palette_buttons: Dictionary = {}
## module_type_id -> Button, only for ModuleType.requires_research entries.
var _research_buttons: Dictionary = {}
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
		_player_ship = players[0]

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
	panel.position = Vector2(CONTENT_LEFT, CONTENT_TOP)
	add_child(panel)

	_build_left_column(panel)
	_build_side_panel(panel)
	_refresh_saved_list()


func _build_left_column(panel: Control) -> void:
	var info_bg := ColorRect.new()
	info_bg.position = Vector2(0, 0)
	info_bg.size = Vector2(GRID_PIXEL_WIDTH, INFO_BAR_HEIGHT)
	info_bg.color = INFO_BG_COLOR
	panel.add_child(info_bg)

	_status_label = Label.new()
	_status_label.position = Vector2(8, 2)
	_status_label.size = Vector2(GRID_PIXEL_WIDTH - 16, 18)
	_status_label.clip_text = true
	_status_label.text = "Select a module type, then click an adjacent cell."
	panel.add_child(_status_label)

	_stats_label = Label.new()
	_stats_label.position = Vector2(8, 20)
	_stats_label.size = Vector2(GRID_PIXEL_WIDTH - 16, 18)
	panel.add_child(_stats_label)

	var grid_top: float = INFO_BAR_HEIGHT + SECTION_GAP

	var grid_bg := ColorRect.new()
	grid_bg.position = Vector2(0, grid_top)
	grid_bg.size = Vector2(GRID_PIXEL_WIDTH, GRID_PIXEL_HEIGHT)
	grid_bg.color = GRID_BG_COLOR
	panel.add_child(grid_bg)

	_grid = HexGridControl.new()
	_grid.position = Vector2(0, grid_top)
	_grid.size = Vector2(GRID_PIXEL_WIDTH, GRID_PIXEL_HEIGHT)
	_grid.cell_size = GRID_CELL_SIZE
	_grid.grid_width = GRID_COLS
	_grid.grid_height = GRID_ROWS
	_grid.layout = working_layout
	if _player_ship != null:
		_grid.faction_id = _player_ship.personality.faction_id
	_grid.hex_clicked.connect(_on_hex_clicked)
	_grid.hex_hovered.connect(_on_hex_hovered)
	_grid.hover_exited.connect(_on_hover_exited)
	panel.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.position = Vector2(0, grid_top + GRID_PIXEL_HEIGHT + SECTION_GAP)
	actions.add_theme_constant_override("separation", 8)
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


## Right-hand column: the placeable-module list (scrollable, neon-blue
## backdrop) on top, ship save/load underneath, matching the same overall
## height as the grid + actions row on the left.
func _build_side_panel(panel: Control) -> void:
	var side_x: float = GRID_PIXEL_WIDTH + SIDE_PANEL_GAP
	var side_height: float = INFO_BAR_HEIGHT + SECTION_GAP + GRID_PIXEL_HEIGHT + SECTION_GAP + ACTIONS_HEIGHT

	var side_bg := ColorRect.new()
	side_bg.position = Vector2(side_x, 0)
	side_bg.size = Vector2(SIDE_PANEL_WIDTH, side_height)
	side_bg.color = PALETTE_BG_COLOR
	panel.add_child(side_bg)

	var header := Label.new()
	header.position = Vector2(side_x + SIDE_MARGIN, 4)
	header.size = Vector2(SIDE_PANEL_WIDTH - SIDE_MARGIN * 2, SIDE_HEADER_HEIGHT - 4)
	header.text = "Modules"
	header.add_theme_font_size_override("font_size", 18)
	panel.add_child(header)

	var save_row_top: float = side_height - SIDE_SAVE_ROW_HEIGHT - SECTION_GAP - SIDE_SAVED_LIST_HEIGHT
	var palette_top: float = SIDE_HEADER_HEIGHT
	var palette_height: float = save_row_top - SECTION_GAP - palette_top

	var palette_scroll := ScrollContainer.new()
	palette_scroll.position = Vector2(side_x + SIDE_MARGIN, palette_top)
	palette_scroll.size = Vector2(SIDE_PANEL_WIDTH - SIDE_MARGIN * 2, palette_height)
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(palette_scroll)

	var palette := VBoxContainer.new()
	palette.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - SIDE_MARGIN * 2, 0)
	palette.add_theme_constant_override("separation", PALETTE_BUTTON_GAP)
	palette_scroll.add_child(palette)

	for module_type in ModuleCatalog.get_all():
		var button := Button.new()
		button.toggle_mode = true
		# clip_text excludes the (sometimes long) cost string from the
		# button's minimum-size calculation; without it a long enough cost
		# string forces the ScrollContainer wider than SIDE_PANEL_WIDTH
		# (ScrollContainer expands to fit content when horizontal scrolling
		# is disabled), pushing the list and its scrollbar out past the
		# neon-blue background on the right.
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, PALETTE_BUTTON_HEIGHT)
		button.pressed.connect(_on_palette_pressed.bind(module_type.id))
		palette.add_child(button)
		_palette_buttons[module_type.id] = button

		if module_type.requires_research:
			var research_button := Button.new()
			research_button.pressed.connect(_on_research_pressed.bind(module_type.id))
			palette.add_child(research_button)
			_research_buttons[module_type.id] = research_button

	if _inventory != null:
		_inventory.captured_tech_changed.connect(func(_totals): _refresh_lock_state())
	_refresh_lock_state()

	var save_row := HBoxContainer.new()
	save_row.position = Vector2(side_x + SIDE_MARGIN, save_row_top)
	save_row.size = Vector2(SIDE_PANEL_WIDTH - SIDE_MARGIN * 2, SIDE_SAVE_ROW_HEIGHT)
	save_row.add_theme_constant_override("separation", 6)
	panel.add_child(save_row)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "ship name"
	_save_name_edit.text = "my_ship"
	_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_save_name_edit)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	save_row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	save_row.add_child(load_button)

	_saved_list = ItemList.new()
	_saved_list.position = Vector2(side_x + SIDE_MARGIN, save_row_top + SIDE_SAVE_ROW_HEIGHT + SECTION_GAP)
	_saved_list.size = Vector2(SIDE_PANEL_WIDTH - SIDE_MARGIN * 2, SIDE_SAVED_LIST_HEIGHT)
	_saved_list.item_selected.connect(_on_saved_item_selected)
	panel.add_child(_saved_list)


## Shows each palette entry's current lock/researched state — call whenever
## captured-tech counts change (see _build_side_panel) since that's what
## Inventory.can_research depends on.
func _refresh_lock_state() -> void:
	for module_type in ModuleCatalog.get_all():
		var locked: bool = module_type.requires_research and (_inventory == null or not _inventory.is_researched(module_type.id))
		var button: Button = _palette_buttons[module_type.id]
		button.disabled = locked
		button.text = "%s%s\n%s" % [
			"[LOCKED] " if locked else "",
			module_type.display_name,
			_format_costs(module_type.build_costs),
		]

		if not _research_buttons.has(module_type.id):
			continue
		var research_button: Button = _research_buttons[module_type.id]
		research_button.visible = locked
		if locked and _inventory != null:
			var captured: int = _inventory.get_captured_tech_count(module_type.id)
			research_button.disabled = not _inventory.can_research(module_type.id)
			research_button.text = "Research (%d captured)" % captured


func _on_research_pressed(module_type_id: String) -> void:
	if _inventory == null:
		return

	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	if _inventory.research(module_type_id):
		_status_label.text = "Researched %s. It can now be built." % module_type.display_name
	else:
		_status_label.text = "Cannot research %s yet: capture one first." % module_type.display_name
	_refresh_lock_state()


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

	var base_generation: float = _player_ship.base_energy_generation if _player_ship != null else 0.0
	var base_capacity: float = _player_ship.base_energy_capacity if _player_ship != null else 0.0
	var energy_generation: float = base_generation + working_layout.total_energy_generation()
	var energy_capacity: float = base_capacity + working_layout.total_energy_capacity()

	_stats_label.text = "Max Health: %d   Mass: %.2f   Energy: +%.0f/s (cap %.0f)" % [
		working_layout.total_max_health(), working_layout.total_mass(), energy_generation, energy_capacity]


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

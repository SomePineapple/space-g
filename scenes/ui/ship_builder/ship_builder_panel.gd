extends GamePanel

## Full-screen ship-builder screen, rebuilt to
## docs/design_handoff_ship_builder/README.md. That handoff (plus
## ship_builder_reference.html for structure) is the source of truth for this
## screen's appearance — check it before restyling anything here.
##
## This file owns the screen's state and gameplay actions; the look lives in
## BuilderTheme, and the three heavier widgets are their own components
## (ModuleListView, BuilderStatStrip, BuilderPresetsCard, BuilderBackdrop).

const GRID_COLS: int = 20
const GRID_ROWS: int = 20

const SAVE_DIRECTORY: String = "user://ships"

## Only weapon/missile hardpoints and the two energy modules currently have
## Manufacturer stat_modifiers wired up (see Ship._apply_manufacturer_modifiers/
## ShipLayout._manufacturer_stat_delta) — matches the "Weapons + Reactor/Battery"
## scope decision, not every module type.
const MANUFACTURER_ELIGIBLE_TYPE_IDS: Array[String] = ["reactor_mk1", "battery_mk1"]

var template_layout: ShipLayout
var working_layout: ShipLayout

var _selected_type_id: String = ""
## Empty means "generic/no manufacturer" — see Manufacturer/ManufacturerCatalog.
var _selected_manufacturer_id: String = ""
var _pending_rotation: int = 0
var _has_hover: bool = false
var _last_hover_hex: Vector2i = Vector2i.ZERO

## Composite keys ("module_type_id", or "module_type_id::manufacturer_id" for
## a manufacturer-flavoured row) currently shown in the module list, in list
## order — see Inventory.owned_module_key.
var _entry_keys: Array[String] = []

var _instruction_label: Label
var _status_label: Label
var _stat_strip: BuilderStatStrip
var _grid: HexGridControl
var _module_list: ModuleListView
var _presets_card: BuilderPresetsCard
var _save_name_edit: LineEdit
var _cell_count_label: Label


func _init() -> void:
	# Opening is handled below rather than by GamePanel's toggle_action, because
	# this panel's own key also has to reach its in-panel hotkeys, and closing
	# it applies the built layout.
	requires_home_base = true
	# The builder is a full-screen takeover with its own background and its own
	# HP/MASS/EN/CARGO strip, so it has to sit above the gameplay HUD and the
	# station prompt (both CanvasLayer 1) rather than letting them show through.
	layer = 10


func _setup() -> void:
	template_layout = load("res://resources/ships/starter_ship_layout.tres")
	working_layout = template_layout.duplicate(true)

	_build_ui()
	_rebuild_module_list()
	_connect_inventory()
	_refresh_saved_list()
	_refresh()


## Closing the builder is what commits the working layout to the live ship.
func _on_closed() -> void:
	_apply_toship()


func _on_ship_bound() -> void:
	if _grid == null:
		return
	if ship != null:
		_grid.faction_id = ship.personality.faction_id
	_rebuild_module_list()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_builder"):
		if visible:
			close()
		else:
			open()
		return

	if not visible:
		return

	if event.is_action_pressed("builder_rotate"):
		_on_rotate_pressed()
	elif event.is_action_pressed("builder_delete"):
		_on_remove_pressed()


func _apply_toship() -> void:
	if ship == null:
		return

	var issues: Array[String] = working_layout.validate_layout()
	if not issues.is_empty():
		_report("Cannot apply to ship: %s" % "; ".join(issues))
		return

	ship.apply_layout(working_layout.duplicate(true))
	_report("Applied to ship.")


# --- Screen construction ----------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	# ...and_offsets_preset throughout: set_anchors_preset() alone keeps the
	# control's current rect by writing compensating offsets, which on a
	# freshly created Control means it stays zero-sized.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(BuilderBackdrop.new())
	_build_top_hud(root)
	_build_field(root)
	_build_right_column(root)
	_build_bottom_bar(root)


func _build_top_hud(root: Control) -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(BuilderTheme.SCREEN_MARGIN, 24.0)
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	_instruction_label = BuilderTheme.mono_label(
		"Select a module type, then click an adjacent cell.", 13, BuilderTheme.TEXT_BODY)
	column.add_child(_instruction_label)

	_stat_strip = BuilderStatStrip.new()
	_stat_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_stat_strip)


func _build_field(root: Control) -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = BuilderTheme.SCREEN_MARGIN
	frame.offset_top = BuilderTheme.FIELD_TOP
	frame.offset_right = -(BuilderTheme.RIGHT_PANEL_MARGIN + BuilderTheme.RIGHT_PANEL_WIDTH + 16.0)
	frame.offset_bottom = -BuilderTheme.FIELD_BOTTOM_INSET
	frame.add_theme_stylebox_override("panel", BuilderTheme.field_style())
	# So the lattice and the vignette stop at the rounded frame.
	frame.clip_contents = true
	root.add_child(frame)

	_grid = HexGridControl.new()
	_grid.grid_width = GRID_COLS
	_grid.grid_height = GRID_ROWS
	_grid.layout = working_layout
	if ship != null:
		_grid.faction_id = ship.personality.faction_id
	_grid.hex_clicked.connect(_on_hex_clicked)
	_grid.hex_hovered.connect(_on_hex_hovered)
	_grid.hover_exited.connect(_on_hover_exited)
	frame.add_child(_grid)


func _build_right_column(root: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	column.offset_left = -(BuilderTheme.RIGHT_PANEL_MARGIN + BuilderTheme.RIGHT_PANEL_WIDTH)
	column.offset_right = -BuilderTheme.RIGHT_PANEL_MARGIN
	column.offset_top = BuilderTheme.RIGHT_PANEL_MARGIN
	column.offset_bottom = -BuilderTheme.RIGHT_PANEL_MARGIN
	column.add_theme_constant_override("separation", BuilderTheme.CARD_GAP)
	root.add_child(column)

	_module_list = ModuleListView.new()
	_module_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ship != null:
		_module_list.faction_id = ship.personality.faction_id
	_module_list.module_selected.connect(_on_module_selected)
	_module_list.craft_pressed.connect(_on_craft_pressed)
	_module_list.research_pressed.connect(_on_research_pressed)
	_module_list.repair_pressed.connect(_on_repair_pressed)
	column.add_child(_module_list)

	column.add_child(_build_save_card())

	_presets_card = BuilderPresetsCard.new()
	_presets_card.preset_selected.connect(_on_preset_selected)
	column.add_child(_presets_card)


func _build_save_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BuilderTheme.padded(BuilderTheme.card_style(), 12.0, 12.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "ship name"
	_save_name_edit.text = "my_ship"
	_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name_edit.add_theme_font_override("font", BuilderTheme.mono_font())
	_save_name_edit.add_theme_font_size_override("font_size", 12)
	_save_name_edit.add_theme_color_override("font_color", BuilderTheme.TEXT_BRIGHT)
	_save_name_edit.add_theme_color_override("font_placeholder_color", BuilderTheme.TEXT_HINT)
	_save_name_edit.add_theme_color_override("caret_color", BuilderTheme.CYAN)
	_save_name_edit.add_theme_stylebox_override("normal", BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.BG_BASE,
			BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.3), BuilderTheme.RADIUS_SMALL), 10.0, 8.0))
	_save_name_edit.add_theme_stylebox_override("focus", BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.BG_BASE,
			BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.6), BuilderTheme.RADIUS_SMALL), 10.0, 8.0))
	row.add_child(_save_name_edit)

	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.focus_mode = Control.FOCUS_NONE
	BuilderTheme.style_button(save_button, BuilderTheme.CYAN, BuilderTheme.CYAN_BRIGHT,
		BuilderTheme.TEXT_BRIGHT, 11, 12.0, 8.0)
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)
	return card


func _build_bottom_bar(root: Control) -> void:
	# Spans the full width but left-aligned, so the buttons keep their own
	# widths instead of being stretched.
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = BuilderTheme.SCREEN_MARGIN
	bar.offset_right = -BuilderTheme.SCREEN_MARGIN
	bar.offset_top = -(BuilderTheme.BOTTOM_BAR_INSET + 36.0)
	bar.offset_bottom = -BuilderTheme.BOTTOM_BAR_INSET
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)

	bar.add_child(_build_cell_count_pill())
	bar.add_child(_make_action_button("ROTATE", BuilderTheme.CYAN, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT, _on_rotate_pressed))
	bar.add_child(_make_action_button("REMOVE SELECTED", BuilderTheme.WARN, BuilderTheme.WARN_TEXT,
		BuilderTheme.WARN_TEXT_HOVER, _on_remove_pressed))
	bar.add_child(_make_action_button("VALIDATE LAYOUT", BuilderTheme.CYAN, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT, _on_validate_pressed))

	_status_label = BuilderTheme.mono_label(StationPrompt.PROMPT_TEXT, 12, BuilderTheme.TEXT_HINT)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_top = -(BuilderTheme.STATUS_LINE_INSET + 18.0)
	_status_label.offset_bottom = -BuilderTheme.STATUS_LINE_INSET
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)


## The handoff shows a dropdown chevron here for an intended build-size
## selector; there is no such system in the game, so this is a plain readout.
func _build_cell_count_pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel", BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.with_alpha(BuilderTheme.GLASS, 0.6),
			BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.28), BuilderTheme.RADIUS_MEDIUM),
		12.0, 8.0))

	_cell_count_label = BuilderTheme.mono_label("0/0", 12, BuilderTheme.TEXT_BRIGHT)
	pill.add_child(_cell_count_label)
	return pill


func _make_action_button(text: String, tint: Color, text_color: Color, hover_color: Color,
		handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BuilderTheme.style_button(button, tint, text_color, hover_color)
	button.pressed.connect(handler)
	return button


# --- Module list ------------------------------------------------------------

func _connect_inventory() -> void:
	if inventory == null:
		return
	inventory.captured_tech_changed.connect(func(_totals): _refresh_module_states())
	inventory.materials_changed.connect(func(_totals): _refresh_module_states())
	inventory.components_changed.connect(func(_totals): _refresh_module_states())
	inventory.owned_modules_changed.connect(func(_totals): _refresh_module_states())
	# A newly discovered manufacturer adds whole new rows (not just a state
	# change on existing ones), so it needs a full rebuild.
	inventory.manufacturer_discovered.connect(func(_id): _rebuild_module_list())


func _module_type_takes_manufacturers(module_type: ModuleType) -> bool:
	return module_type.hardpoint_category in ["weapon", "missile"] \
		or module_type.id in MANUFACTURER_ELIGIBLE_TYPE_IDS


## Composite key for a manufacturer-flavored row, distinct from the generic
## row's plain module_type_id key. Delegates to Inventory so the same key
## format is shared with owned-module tracking.
func _palette_key(module_type_id: String, manufacturer_id: String) -> String:
	return Inventory.owned_module_key(module_type_id, manufacturer_id)


func _split_key(key: String) -> Array:
	var parts: PackedStringArray = key.split("::")
	return [parts[0], parts[1] if parts.size() > 1 else ""]


func _rebuild_module_list() -> void:
	var entries: Array = []
	_entry_keys.clear()

	for module_type in ModuleCatalog.get_all():
		entries.append(_make_entry(module_type, null))

		# A manufacturer row only makes sense once the base type itself is
		# actually buildable — an "Atlas Railgun" row before Railgun itself is
		# researched would be confusing (and un-placeable anyway).
		var base_type_unlocked: bool = not module_type.requires_research \
			or (inventory != null and inventory.is_researched(module_type.id))
		if inventory == null or not base_type_unlocked or not _module_type_takes_manufacturers(module_type):
			continue
		for manufacturer_id in inventory.get_known_manufacturer_ids():
			var manufacturer: Manufacturer = ManufacturerCatalog.get_by_id(manufacturer_id)
			if manufacturer == null:
				continue
			entries.append(_make_entry(module_type, manufacturer))

	_module_list.set_entries(entries)
	_refresh_module_states()


func _make_entry(module_type: ModuleType, manufacturer: Manufacturer) -> Dictionary:
	var manufacturer_id: String = manufacturer.id if manufacturer != null else ""
	var key: String = _palette_key(module_type.id, manufacturer_id)
	_entry_keys.append(key)
	return {
		"key": key,
		"module_type": module_type,
		"display_name": "%s (%s)" % [module_type.display_name, manufacturer.display_name] \
			if manufacturer != null else module_type.display_name,
	}


## Pushes each row's current lock/owned/affordable state into the list — call
## whenever captured-tech counts, owned-module counts, or material/component
## totals change.
func _refresh_module_states() -> void:
	var states: Dictionary = {}
	for key in _entry_keys:
		var split: Array = _split_key(key)
		var module_type: ModuleType = ModuleCatalog.get_by_id(split[0])
		var is_generic_row: bool = split[1] == ""

		var locked: bool = module_type.requires_research \
			and (inventory == null or not inventory.is_researched(module_type.id))
		var state: Dictionary = {
			"owned": inventory.get_owned_module_count(key) if inventory != null else 0,
			"locked": locked,
			"can_afford": inventory != null and inventory.has_items(module_type.build_costs),
			"cost_text": _format_costs(module_type.build_costs),
			"research_text": "", "can_research": false,
			"repair_text": "", "can_repair": false,
		}

		# Research permanently unlocks a locked type; Repair converts one
		# damaged/captured part into a placeable owned instance. They are
		# orthogonal, and neither applies to a manufacturer-flavoured row —
		# those only ever appear once the base type is already known.
		if is_generic_row and locked and inventory != null:
			state["research_text"] = "RESEARCH (%d captured)" % inventory.get_captured_tech_count(module_type.id)
			state["can_research"] = inventory.can_research(module_type.id)

		if is_generic_row and module_type.is_capturable_tech and inventory != null:
			var captured: int = inventory.get_captured_tech_count(module_type.id)
			if captured > 0:
				state["repair_text"] = "REPAIR (%d damaged) · %s" % [
					captured, _format_costs(inventory.get_repair_cost(module_type.id))]
				state["can_repair"] = inventory.can_repair(module_type.id)

		states[key] = state
	_module_list.update_states(states)


# --- Module actions ---------------------------------------------------------

func _on_module_selected(key: String) -> void:
	_module_list.set_selected_key(key)
	_grid.selected_placement_id = ""
	_pending_rotation = 0

	if key.is_empty():
		_selected_type_id = ""
		_selected_manufacturer_id = ""
		_grid.clear_preview()
		_report("Select a module type, then click an adjacent cell.")
		_grid.refresh()
		return

	var split: Array = _split_key(key)
	_selected_type_id = split[0]
	_selected_manufacturer_id = split[1]

	var module_type: ModuleType = ModuleCatalog.get_by_id(_selected_type_id)
	if inventory != null and inventory.get_owned_module_count(key) <= 0:
		_report("Selected: %s — you don't own one yet, CRAFT it first." % module_type.display_name)
	else:
		_report("Selected: %s — click an adjacent cell to place it." % module_type.display_name)
	_grid.refresh()
	_update_preview()


## Spends ModuleType.build_costs (materials and/or crafted components — see
## Inventory.has_items/spend_items) to craft one owned-but-unplaced instance.
## Never places anything itself — placement is a separate, free action once
## owned (see _on_hex_clicked).
func _on_craft_pressed(key: String) -> void:
	if inventory == null:
		return

	var split: Array = _split_key(key)
	var module_type: ModuleType = ModuleCatalog.get_by_id(split[0])
	if module_type.requires_research and not inventory.is_researched(module_type.id):
		_report("Cannot craft %s: research it first." % module_type.display_name)
		_refresh_module_states()
		return

	if not inventory.spend_items(module_type.build_costs):
		_report("Cannot craft %s: need %s." % [module_type.display_name, _format_costs(module_type.build_costs)])
		return

	inventory.add_owned_module(key)
	_report("Crafted %s." % module_type.display_name)
	_refresh_module_states()


func _on_research_pressed(module_type_id: String) -> void:
	if inventory == null:
		return

	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	if inventory.research(module_type_id):
		_report("Researched %s. It can now be crafted." % module_type.display_name)
		# Researching a type can add manufacturer rows beneath it.
		_rebuild_module_list()
		return
	_report("Cannot research %s yet: capture one first." % module_type.display_name)
	_refresh_module_states()


func _on_repair_pressed(module_type_id: String) -> void:
	if inventory == null:
		return

	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	if inventory.repair_module(module_type_id):
		_report("Repaired %s. Added to owned inventory." % module_type.display_name)
	else:
		_report("Cannot repair %s: need a damaged part and %s." % [
			module_type.display_name, _format_costs(inventory.get_repair_cost(module_type_id))])
	_refresh_module_states()


# --- Grid interaction -------------------------------------------------------

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

	var candidate_cells: Array[Vector2i] = working_layout.get_candidate_cells(
		_selected_type_id, _last_hover_hex, _pending_rotation)
	var reason: String = "" if _fits_in_bounds(candidate_cells) else "Out of bounds"
	if reason == "":
		reason = working_layout.get_place_rejection_reason(_selected_type_id, _last_hover_hex, _pending_rotation)

	_grid.set_preview(candidate_cells, reason == "", _selected_type_id, _pending_rotation)

	var type_name: String = ModuleCatalog.get_by_id(_selected_type_id).display_name
	if reason == "":
		_report("Ready to place %s here." % type_name)
	else:
		_report("Cannot place %s here: %s" % [type_name, reason])


func _on_hex_clicked(hex_coord: Vector2i) -> void:
	var existing: ModulePlacement = working_layout.get_placement_at(hex_coord)
	if existing != null:
		_selected_type_id = ""
		_selected_manufacturer_id = ""
		_module_list.set_selected_key("")
		_grid.clear_preview()
		_grid.selected_placement_id = existing.placement_id
		var module_type: ModuleType = ModuleCatalog.get_by_id(existing.module_type_id)
		_report("Selected: %s at (%d, %d)" % [module_type.display_name, hex_coord.x, hex_coord.y])
		_grid.refresh()
		return

	if _selected_type_id.is_empty():
		_report("Pick a module type from the list first.")
		return

	if not _fits_in_bounds(working_layout.get_candidate_cells(_selected_type_id, hex_coord, _pending_rotation)):
		_report("Cannot place: Out of bounds")
		return

	var reason: String = working_layout.get_place_rejection_reason(_selected_type_id, hex_coord, _pending_rotation)
	if reason != "":
		_report("Cannot place: %s" % reason)
		return

	var type_to_place: ModuleType = ModuleCatalog.get_by_id(_selected_type_id)
	var owned_key: String = _palette_key(_selected_type_id, _selected_manufacturer_id)
	if inventory != null and inventory.get_owned_module_count(owned_key) <= 0:
		_report("Cannot place %s: you don't own one. Craft it first." % type_to_place.display_name)
		return

	var placed: ModulePlacement = working_layout.place(
		_selected_type_id, hex_coord, _pending_rotation, _selected_manufacturer_id)
	if inventory != null and placed != null:
		placed.instance = inventory.take_owned_module(owned_key)
	_report("Placed %s." % type_to_place.display_name)
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

	_report("Select a module type or a placed module first.")


func _rotate_selected_placement() -> void:
	var placement: ModulePlacement = working_layout.get_placement_by_id(_grid.selected_placement_id)
	var new_rotation: int = posmod(placement.rotation_steps + 1, 6)
	var candidate_cells: Array[Vector2i] = working_layout.get_candidate_cells(
		placement.module_type_id, placement.hex_coord, new_rotation)
	if not _fits_in_bounds(candidate_cells):
		_report("Cannot rotate: Out of bounds")
		return

	var reason: String = working_layout.get_rotate_rejection_reason(_grid.selected_placement_id, 1)
	if reason != "":
		_report("Cannot rotate: %s" % reason)
		return

	working_layout.rotate(_grid.selected_placement_id, 1)
	_report("Rotated.")
	_refresh()


func _fits_in_bounds(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not _grid.is_in_bounds(cell):
			return false
	return true


func _on_remove_pressed() -> void:
	if _grid.selected_placement_id.is_empty():
		_report("Select a placed module first.")
		return

	var reason: String = working_layout.get_remove_rejection_reason(_grid.selected_placement_id)
	if reason != "":
		_report("Cannot remove: %s" % reason)
		return

	var removed_placement: ModulePlacement = working_layout.get_placement_by_id(_grid.selected_placement_id)
	var removed_type: ModuleType = ModuleCatalog.get_by_id(removed_placement.module_type_id)

	# Prevent removing a Storage module while it would leave currently-held
	# cargo over the new capacity — cargo is never deleted to make it fit, so
	# the player has to discard cargo first (see CargoPanel) instead.
	if inventory != null and removed_type.cargo_capacity_contribution > 0.0:
		var capacity_after_removal: float = _current_cargo_capacity() - removed_type.cargo_capacity_contribution
		if inventory.get_cargo_used() > capacity_after_removal:
			_report("Cannot remove %s: discard cargo first, current cargo exceeds the reduced capacity."
				% removed_type.display_name)
			return

	working_layout.remove(_grid.selected_placement_id)
	_grid.selected_placement_id = ""

	# Removal returns the built instance itself to owned stock, not raw
	# materials/components — it was already a finished module, not something to
	# be melted back down. It is the *same* instance, so anything tracked
	# against it survives the round trip.
	if inventory != null:
		var key: String = _palette_key(removed_placement.module_type_id, removed_placement.manufacturer_id)
		inventory.return_owned_module(key, removed_placement.ensure_instance())
		_report("Removed %s. Returned to inventory." % removed_type.display_name)
	else:
		_report("Removed.")
	_refresh_module_states()
	_refresh()


func _on_validate_pressed() -> void:
	var issues: Array[String] = working_layout.validate_layout()
	if issues.is_empty():
		_report("Layout OK.")
	else:
		_report("Issues: %s" % "; ".join(issues))


# --- Stats ------------------------------------------------------------------

## Only used to read base_energy_generation/base_energy_capacity/
## base_cargo_capacity so the builder's stats match what the ship will
## actually have once applied — the working layout's own totals don't
## include that baseline.
func _current_cargo_capacity() -> float:
	var base_capacity: float = ship.base_cargo_capacity if ship != null else 0.0
	return base_capacity + working_layout.total_cargo_capacity()


func _refresh() -> void:
	_grid.refresh()

	var base_generation: float = ship.get_base_energy_generation() if ship != null else 0.0
	var base_capacity: float = ship.get_base_energy_capacity() if ship != null else 0.0
	var max_health: float = working_layout.total_max_health()
	var health_fraction: float = ship.get_health_fraction() if ship != null else 1.0

	_stat_strip.set_stats(max_health, health_fraction, working_layout.total_mass(),
		base_generation + working_layout.total_energy_generation(),
		base_capacity + working_layout.total_energy_capacity(),
		inventory.get_cargo_used() if inventory != null else 0,
		_current_cargo_capacity())

	_cell_count_label.text = "%d/%d" % [_grid.used_cell_count(), _grid.total_cell_count()]


## Costs can mix material_id and component_id keys (see Phase 5.2 module
## construction costs, e.g. Hull) — resolve each id's display name from
## whichever catalog actually owns it.
func _format_costs(costs: Dictionary) -> String:
	var parts: Array = []
	for id in costs:
		var item_name: String = ComponentCatalog.display_name(id) \
			if ComponentCatalog.get_by_id(id) != null else MaterialCatalog.display_name(id)
		parts.append("%d %s" % [costs[id], item_name])
	return ", ".join(parts) if not parts.is_empty() else "free"


## All transient feedback goes to the top instruction line, which the handoff
## defines as the screen's dynamic text. The bottom line stays the docking
## hint.
func _report(message: String) -> void:
	_instruction_label.text = message


# --- Save / load ------------------------------------------------------------

func _on_save_pressed() -> void:
	var save_path: String = _get_save_path()
	DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)

	var error: Error = ResourceSaver.save(working_layout, save_path)
	if error != OK:
		_report("Save failed (error %d)." % error)
		return
	_report("Saved to %s." % save_path)
	_refresh_saved_list()


func _on_preset_selected(preset_name: String) -> void:
	_save_name_edit.text = preset_name
	_load_current_name()


func _load_current_name() -> void:
	var save_path: String = _get_save_path()
	if not FileAccess.file_exists(save_path):
		_report("No saved ship named '%s'." % _save_name_edit.text)
		return

	var loaded: ShipLayout = ResourceLoader.load(save_path, "ShipLayout", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded == null:
		_report("Load failed.")
		return

	working_layout = loaded.duplicate(true)
	_grid.layout = working_layout
	_grid.selected_placement_id = ""
	_selected_type_id = ""
	_selected_manufacturer_id = ""
	_module_list.set_selected_key("")
	_report("Loaded '%s'." % _save_name_edit.text)
	_refresh()


func _refresh_saved_list() -> void:
	var names: Array = []
	var dir: DirAccess = DirAccess.open(SAVE_DIRECTORY)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				names.append(file_name.trim_suffix(".tres"))
			file_name = dir.get_next()
		dir.list_dir_end()
	_presets_card.set_presets(names)


func _get_save_path() -> String:
	var sanitized: String = ""
	for character in _save_name_edit.text:
		if character.is_valid_identifier() or character == "-":
			sanitized += character
	if sanitized.is_empty():
		sanitized = "ship"
	return "%s/%s.tres" % [SAVE_DIRECTORY, sanitized]

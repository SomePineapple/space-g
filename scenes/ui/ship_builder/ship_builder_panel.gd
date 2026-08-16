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

## The two refits. Quoted as a percentage rather than as a name for the penalty,
## because the number is the decision: a part on the hull at half output can
## still be better than the same part in the hold doing nothing.
##
## Templates rather than finished strings — a `%` against another script's const
## is not a constant expression, and the percentage is ModuleInstance's to state
## (see _field_percent()), not this screen's to keep a second copy of.
const DOCKED_PILL_TEXT: String = "DOCKED REFIT · FULL MOUNTS"
const FIELD_PILL_FORMAT: String = "FIELD REFIT · %d%% NOW · %d%% CEILING"
const FIELD_STATUS_FORMAT: String = \
	"No dock in range — anything bolted on out here runs at %d%%, and a station can only ever bring it back to %d%%."

## There is no manufacturing on this screen. The list is the hold: every row is
## a part the player physically has, and building is putting those parts onto
## the hull. Parts come from combat, not from a button — see docs/direction.md
## §1. Inventory.research()/ModuleType.build_costs still exist and are simply
## unreached; nothing is deleted.

## Forces this refit to count as a docked one wherever the ship happens to be.
## Set by IntroDirector: the opening hands the player their first parts to bolt
## on while adrift in a derelict, and starting the game with every module at half
## output would teach the field penalty at the worst possible moment.
@export var always_docked: bool = false

var template_layout: ShipLayout
var working_layout: ShipLayout

## The specific part being placed, taken out of the hold on placement. Empty
## means nothing is selected. The type id is derived from it rather than stored
## alongside, so the two can never disagree about what is being placed.
var _selected_instance_id: String = ""
var _pending_rotation: int = 0
var _has_hover: bool = false
var _last_hover_hex: Vector2i = Vector2i.ZERO

## Whether this refit counts as being done at a dock, and so whether parts bolted
## on during it get a proper mount or a jury-rigged one.
##
## Snapshotted when the screen opens rather than tested per placement: the ship
## keeps drifting while the builder is up, so a live check could silently flip
## mid-refit and leave the player with two different classes of mount from one
## session of clicking. One refit, one answer, stated on screen the whole time.
var _docked: bool = false

var _instruction_label: Label
var _status_label: Label
var _stat_strip: BuilderStatStrip
var _grid: HexGridControl
var _module_list: ModuleListView
var _part_card: BuilderPartCard
var _presets_card: BuilderPresetsCard
var _save_name_edit: LineEdit
var _cell_count_label: Label
var _mount_pill: PanelContainer
var _mount_label: Label
var _power_button: Button


func _init() -> void:
	# Opening is handled below rather than by GamePanel's toggle_action, because
	# this panel's own key also has to reach its in-panel hotkeys, and closing
	# it applies the built layout.
	#
	# No home-base gate: refitting out in the field is always allowed, because a
	# part cut off a wreck is worth something *there*, not only after the trip
	# home. Being near a dock no longer decides whether you can build — it decides
	# how good the mount is (see _docked / ModuleInstance.field_attached).
	requires_home_base = false
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


## Opening loads the ship's *live* layout rather than the stored template.
## Mounted ModuleInstances — and with them every module's accumulated damage and
## origin — are part of that layout now, so editing a stale copy and committing
## it on close would wipe the ship's record of every fight it has been in, every
## time the player opened this screen.
func _on_opened() -> void:
	_docked = always_docked or is_near_home_base()
	_refresh_mount_mode()
	if ship == null or ship.ship_layout == null:
		return
	working_layout = ship.ship_layout.duplicate(true)
	_grid.layout = working_layout
	_grid.selected_placement_id = ""
	_sync_build_target()
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


## Gap between the build field's frame and the part card floating inside it.
const FIELD_CARD_INSET: float = 14.0


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

	# Floated over the field's top-left corner rather than parented into it: the
	# frame is a PanelContainer, which stretches every child to fill its content
	# rect, so a card added there would cover the whole build area. Wrapped in a
	# positioned container for the same reason _build_top_hud is — a container
	# placed by `position` sizes itself to its contents, while a bare Control
	# would need its rect setting by hand.
	var card_holder := VBoxContainer.new()
	card_holder.position = Vector2(
		BuilderTheme.SCREEN_MARGIN + FIELD_CARD_INSET,
		BuilderTheme.FIELD_TOP + FIELD_CARD_INSET)
	root.add_child(card_holder)

	_part_card = BuilderPartCard.new()
	card_holder.add_child(_part_card)


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
	column.add_child(_module_list)
	# After add_child, not before: the card builds its own children in _ready, so
	# the hold half does not exist until it is in the tree.
	_module_list.hold_view().stow_requested.connect(_on_stow_requested)
	_module_list.hold_view().jettison_requested.connect(_on_jettison_requested)

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

	bar.add_child(_build_mount_pill())
	bar.add_child(_build_cell_count_pill())
	bar.add_child(_make_action_button("ROTATE", BuilderTheme.CYAN, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT, _on_rotate_pressed))
	bar.add_child(_make_action_button("REMOVE SELECTED", BuilderTheme.WARN, BuilderTheme.WARN_TEXT,
		BuilderTheme.WARN_TEXT_HOVER, _on_remove_pressed))
	bar.add_child(_make_action_button("VALIDATE LAYOUT", BuilderTheme.CYAN, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT, _on_validate_pressed))
	bar.add_child(_build_power_button())

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


## Says which kind of refit this is, for as long as the screen is up. Sits at the
## head of the bottom bar rather than in a transient message because the penalty
## applies to every placement made this session, not to one of them — the player
## should not have to remember a line that scrolled away three parts ago.
func _build_mount_pill() -> PanelContainer:
	_mount_pill = PanelContainer.new()
	_mount_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mount_label = BuilderTheme.mono_label("", 12, BuilderTheme.TEXT_BRIGHT)
	_mount_pill.add_child(_mount_label)
	_refresh_mount_mode()
	return _mount_pill


func _refresh_mount_mode() -> void:
	if _mount_pill == null or _mount_label == null:
		return

	var tint: Color = BuilderTheme.CYAN if _docked else BuilderTheme.WARN
	_mount_label.text = DOCKED_PILL_TEXT if _docked \
		else FIELD_PILL_FORMAT % [_field_percent(), _refitted_percent()]
	_mount_label.add_theme_color_override("font_color",
		BuilderTheme.TEXT_BRIGHT if _docked else BuilderTheme.WARN_TEXT)
	_mount_pill.add_theme_stylebox_override("panel", BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.with_alpha(tint, 0.14),
			BuilderTheme.with_alpha(tint, 0.55), BuilderTheme.RADIUS_MEDIUM), 12.0, 8.0))

	if _status_label != null:
		_status_label.text = StationPrompt.PROMPT_TEXT if _docked \
			else FIELD_STATUS_FORMAT % [_field_percent(), _refitted_percent()]
		_status_label.add_theme_color_override("font_color",
			BuilderTheme.TEXT_HINT if _docked else BuilderTheme.WARN_TEXT)


static func _field_percent() -> int:
	return roundi(ModuleInstance.FIELD_MOUNT_EFFICIENCY * 100.0)


static func _refitted_percent() -> int:
	return roundi(ModuleInstance.REFITTED_MOUNT_EFFICIENCY * 100.0)


## Toggles the supply-line overlay on the hull (see HexGridControl.show_power_paths).
##
## A toggle rather than a hold, and a separate button rather than a mode the
## screen sits in: §5 of the Phase 4 spec asks for an overlay *inside* the build
## screen, not a second destination, and the player needs both hands free to keep
## placing parts while it is up.
func _build_power_button() -> Button:
	_power_button = Button.new()
	_power_button.text = "POWER PATHS"
	_power_button.toggle_mode = true
	_power_button.focus_mode = Control.FOCUS_NONE
	_power_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_power_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BuilderTheme.style_button(_power_button, BuilderTheme.CYAN, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT)
	_power_button.toggled.connect(_on_power_toggled)
	return _power_button


func _on_power_toggled(pressed: bool) -> void:
	_grid.show_power_paths = pressed
	if not pressed:
		_report("Power paths hidden.")
		return
	var solution: Dictionary = PowerGrid.solve(working_layout)
	var cold: int = solution["unpowered_ids"].size()
	if cold == 0:
		_report("Power paths: every part is fed.")
	else:
		_report("Power paths: %d %s with no route to a reactor (outlined red)."
			% [cold, "part" if cold == 1 else "parts"])


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


# --- Parts list -------------------------------------------------------------

func _connect_inventory() -> void:
	if inventory == null:
		return
	# Every change to the hold changes which rows exist, because rows are parts
	# rather than counts — there is no cheaper state-only refresh to fall back on.
	inventory.owned_modules_changed.connect(func(_totals): _rebuild_module_list())
	inventory.hold_changed.connect(_refresh_hold)


func _rebuild_module_list() -> void:
	var parts: Array = inventory.get_owned_instances() if inventory != null else []
	_module_list.set_parts(parts)
	# A part that was in the hold when the list was last built may have been
	# placed since; don't leave the panel pointing at something it can't place.
	if not _selected_instance_id.is_empty() and _selected_part() == null:
		_clear_selection()


## The part currently selected in the list, or null if none is (or if it has
## left the hold since).
func _selected_part() -> ModuleInstance:
	if inventory == null or _selected_instance_id.is_empty():
		return null
	return inventory.get_owned_instance(_selected_instance_id)


func _selected_type_id() -> String:
	var part: ModuleInstance = _selected_part()
	return part.module_type_id if part != null else ""


func _clear_selection() -> void:
	_selected_instance_id = ""
	_module_list.set_selected_key("")
	if _part_card != null:
		_part_card.clear()
	_grid.clear_preview()
	_sync_build_target()
	_grid.refresh()


# --- Part actions -----------------------------------------------------------

func _on_module_selected(instance_id: String) -> void:
	_module_list.set_selected_key(instance_id)
	_grid.selected_placement_id = ""
	_pending_rotation = 0
	_selected_instance_id = instance_id

	var part: ModuleInstance = _selected_part()
	if part == null:
		_clear_selection()
		_report("Select a part from the hold, then click a socket on the hull.")
		return

	_part_card.show_instance(part)
	_report("Click a socket on the hull to bolt it on.")
	_grid.refresh()
	_update_preview()


# --- Grid interaction -------------------------------------------------------

func _on_hex_hovered(hex_coord: Vector2i) -> void:
	_has_hover = true
	_last_hover_hex = hex_coord
	_update_preview()


func _on_hover_exited() -> void:
	_has_hover = false
	_grid.clear_preview()


## Tells the grid which module its attachment sockets should be measured
## against, so the ring highlights where the current selection actually fits.
func _sync_build_target() -> void:
	_grid.set_build_target(_selected_type_id(), _pending_rotation)


func _update_preview() -> void:
	_sync_build_target()
	var type_id: String = _selected_type_id()
	if type_id.is_empty() or not _has_hover:
		_grid.clear_preview()
		return

	var candidate_cells: Array[Vector2i] = working_layout.get_candidate_cells(
		type_id, _last_hover_hex, _pending_rotation)
	var reason: String = "" if _fits_in_bounds(candidate_cells) else "Out of bounds"
	if reason == "":
		reason = working_layout.get_place_rejection_reason(type_id, _last_hover_hex, _pending_rotation)

	_grid.set_preview(candidate_cells, reason == "", type_id, _pending_rotation)

	var part: ModuleInstance = _selected_part()
	if reason != "":
		_report("Cannot place %s here: %s" % [part.display_name(), reason])
		return
	# Quoted before the click rather than after it: the whole point of the field
	# penalty is that it is a choice — and the ceiling half of it is irreversible,
	# so a number that only appears once the part is on the hull is no use at all.
	var wear: float = part.wear_efficiency()
	if _docked:
		if part.ever_field_attached:
			_report("Ready to bolt %s on here — %d%%, its mounts capped at %d%% by an old field rig."
				% [part.display_name(),
					roundi(wear * ModuleInstance.REFITTED_MOUNT_EFFICIENCY * 100.0),
					roundi(ModuleInstance.REFITTED_MOUNT_EFFICIENCY * 100.0)])
		else:
			_report("Ready to bolt %s on here — %d%%, mounted properly."
				% [part.display_name(), roundi(wear * 100.0)])
		return

	var field_output: int = roundi(wear * ModuleInstance.FIELD_MOUNT_EFFICIENCY * 100.0)
	if part.ever_field_attached:
		_report("Ready to field-rig %s here — %d%% now, %d%% if you re-seat it at a dock."
			% [part.display_name(), field_output,
				roundi(wear * ModuleInstance.REFITTED_MOUNT_EFFICIENCY * 100.0)])
		return
	_report("Ready to field-rig %s here — %d%% now, and never above %d%% again, dock refit or not."
		% [part.display_name(), field_output,
			roundi(ModuleInstance.REFITTED_MOUNT_EFFICIENCY * 100.0)])


func _on_hex_clicked(hex_coord: Vector2i) -> void:
	var existing: ModulePlacement = working_layout.get_placement_at(hex_coord)
	if existing != null:
		_selected_instance_id = ""
		_module_list.set_selected_key("")
		_grid.clear_preview()
		_sync_build_target()
		_grid.selected_placement_id = existing.placement_id
		_part_card.show_instance(existing.instance, existing.module_type_id)
		# Identity lives on the part card now; the status line stays on what to do
		# next, which is the one thing the card does not say.
		_report("R to rotate, or Remove Selected to take it off.")
		_grid.refresh()
		return

	var part: ModuleInstance = _selected_part()
	if part == null:
		_report("Pick a part from the hold first.")
		return

	if not _fits_in_bounds(working_layout.get_candidate_cells(part.module_type_id, hex_coord, _pending_rotation)):
		_report("Cannot place: Out of bounds")
		return

	var reason: String = working_layout.get_place_rejection_reason(part.module_type_id, hex_coord, _pending_rotation)
	if reason != "":
		_report("Cannot place: %s" % reason)
		return

	var placed: ModulePlacement = working_layout.place(
		part.module_type_id, hex_coord, _pending_rotation, part.manufacturer_id)
	if placed == null:
		_report("Cannot place %s here." % part.display_name())
		return

	# The placement takes the exact object out of the hold — same serial, same
	# wear, same history — rather than a fresh one of its type.
	placed.instance = inventory.take_owned_instance(part.instance_id)
	# Written on every attach, not only on field ones, so bolting a jury-rigged
	# part back on at a dock is what clears it. The permanent half is only ever
	# set — a part that has been field-rigged once stays a field-rigged part.
	placed.instance.field_attached = not _docked
	if not _docked:
		placed.instance.ever_field_attached = true
	if _docked:
		_report("Bolted on %s (%s) — %d%% of rated output."
			% [part.display_name(), part.serial, roundi(placed.instance.efficiency() * 100.0)])
	else:
		_report("Field-rigged %s (%s) — running at %d%%, and never better than %d%% again."
			% [part.display_name(), part.serial,
				roundi(placed.instance.efficiency() * 100.0),
				roundi(placed.instance.mount_efficiency_ceiling() * 100.0)])
	_pending_rotation = 0
	_clear_selection()
	_refresh()


func _on_rotate_pressed() -> void:
	if not _grid.selected_placement_id.is_empty():
		_rotate_selected_placement()
		return

	if not _selected_type_id().is_empty():
		_pending_rotation = posmod(_pending_rotation + 1, 6)
		_update_preview()
		return

	_report("Select a part, or a module already on the hull, first.")


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

	# Same rule as the cargo check above, for the hold: a container is where its
	# parts physically are, so unbolting one with parts in it would have to
	# destroy them. Empty it first.
	if inventory != null and removed_type.hold_cells > 0:
		var bay_used: int = _bay_usage(removed_placement.placement_id)
		if bay_used > 0:
			_report("Cannot remove %s: %d %s still stowed in it."
				% [removed_type.display_name, bay_used,
					"part" if bay_used == 1 else "parts"])
			return

	working_layout.remove(_grid.selected_placement_id)
	_grid.selected_placement_id = ""

	# Unbolting puts the part itself back in the hold, not raw materials — it was
	# never melted down, it was just taken off. It is the *same* object, so its
	# serial, wear and history survive the round trip.
	if inventory != null:
		var instance: ModuleInstance = removed_placement.ensure_instance()
		inventory.return_owned_module(
			Inventory.owned_module_key(removed_placement.module_type_id, removed_placement.manufacturer_id),
			instance)
		_report("Unbolted %s (%s). Back in the hold." % [instance.display_name(), instance.serial])
	else:
		_report("Removed %s." % removed_type.display_name)
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
	_refresh_hold()


# --- The hold (INVENTORY tab) ------------------------------------------------

## The bays and whatever is waiting on the end of the grapple. Read from the
## *ship's* inventory rather than the working layout, because the hold is
## physical state that exists whether or not the builder is open — an edit here
## is not applied to it until the layout is (see _apply_to_ship).
func _refresh_hold() -> void:
	if inventory == null:
		return
	var contents: Dictionary = {}
	for part: ModuleInstance in inventory.get_owned_instances():
		contents[part.instance_id] = part
	var view: HoldView = _module_list.hold_view()
	if ship != null:
		view.faction_id = ship.personality.faction_id
	view.refresh(inventory.get_hold(), contents, _towed_instance(),
		inventory.get_unstowed_instances())


func _towed_instance() -> ModuleInstance:
	if ship == null:
		return null
	var part: Node2D = ship.get_towed_part()
	if part == null or not part.has_method("peek_instance"):
		return null
	return part.call("peek_instance")


func _on_stow_requested(bay_index: int, cell: Vector2i) -> void:
	if ship == null or _towed_instance() == null:
		return
	var instance: ModuleInstance = _towed_instance()
	if ship.stow_towed_part(bay_index, cell):
		_report("Stowed %s (%s)." % [instance.display_name(), instance.serial])
	else:
		_report("Won't fit there — needs %d adjacent open cells."
			% Inventory.part_size(instance))
	_refresh_hold()


func _on_jettison_requested() -> void:
	if ship == null:
		return
	var instance: ModuleInstance = _towed_instance()
	ship.jettison_towed_part()
	if instance != null:
		_report("Released %s. It is adrift, not gone." % instance.display_name())
	_refresh_hold()


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

	# KNOWN HOLE: a saved layout carries its own ModuleInstances, so loading one
	# mounts parts that are not in the hold — with no crafting left, this is the
	# only way to get parts without cutting them off something. Whether a preset
	# is a blueprint (shape only, needs the parts) or a saved ship is an open
	# design question; see docs/direction.md §6.
	working_layout = loaded.duplicate(true)
	_grid.layout = working_layout
	_grid.selected_placement_id = ""
	_selected_instance_id = ""
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


## How many cells of one bay are in use, found by placement id — the hold keys
## its bays the same way the layout keys its placements.
func _bay_usage(placement_id: String) -> int:
	var hold: ShipHold = inventory.get_hold()
	for index in hold.bay_count():
		if hold.bay_id(index) == placement_id:
			return hold.bay_used(index)
	return 0

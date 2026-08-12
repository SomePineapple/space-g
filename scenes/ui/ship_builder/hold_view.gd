class_name HoldView
extends VBoxContainer

## The INVENTORY tab's contents: the part currently in tow waiting to be stowed,
## the hold's bays, and what stowing it does
## (`docs/design_handoff_ship_builder_inv/README.md`, "Ship Builder — Inventory
## tab"). That section is explicitly a direction rather than a pixel spec, so
## this follows its rules — one cluster per container, click an open cell to
## stow, jettison to let go — and not its exact chrome.
##
## Presentation and intent only: it reports a clicked cell and a jettison press
## and does nothing itself, leaving ShipBuilderPanel to move the actual part.

signal stow_requested(bay_index: int, cell: Vector2i)
signal jettison_requested

const NO_BAYS_TEXT: String = "No hold. Fit a Cargo Container."
const EMPTY_TEXT: String = "Hold empty."
const PICK_UP_TEXT: String = "Click it to pick it up."
const PROMPT_TEXT: String = "Click an open cell to stow it."
const WONT_FIT_TEXT: String = "Won't fit anywhere — jettison it, or fit a bigger hold."

## The hull's faction, forwarded to the bays and the pending part's icon so a
## salvaged part is drawn in its own maker's plating.
var faction_id: String = "corporate":
	set(value):
		faction_id = value
		if _bays != null:
			_bays.faction_id = value

var _pending_card: PanelContainer
var _pending_icon: ModuleHexIcon
var _pending_name: Label
var _pending_detail: Label
var _status: Label
var _bays: HoldBaysControl
var _unstowed: Label
## Whether the towed part has been picked up. Stowing is deliberately two steps,
## the same as building: pick the part up, then choose where it goes — so the
## click that commits a part to a cell is always the second one.
var _carrying: bool = false
var _towed: ModuleInstance = null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_pending_card()

	_bays = HoldBaysControl.new()
	_bays.faction_id = faction_id
	_bays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bays.cell_clicked.connect(_on_cell_clicked)
	add_child(_bays)

	# Parts that are owned but have no cell — the starter kit at the very
	# beginning, mostly. Listed rather than hidden: they are placeable from the
	# PARTS tab, and a part that exists but appears nowhere reads as a bug.
	_unstowed = BuilderTheme.mono_label("", 10, BuilderTheme.TEXT_MUTED_DIM)
	_unstowed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_unstowed)

	_status = BuilderTheme.mono_label("", 10, BuilderTheme.TEXT_HINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _build_pending_card() -> void:
	_pending_card = PanelContainer.new()
	_pending_card.visible = false
	# The card is the part: clicking it is how you take hold of it.
	_pending_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pending_card.gui_input.connect(_on_card_gui_input)
	add_child(_pending_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_pending_card.add_child(column)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# The real part, in its own art — so what is on the end of the grapple is
	# recognisable as the thing that was just cut free.
	_pending_icon = ModuleHexIcon.new()
	line.add_child(_pending_icon)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 3)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text_column)

	_pending_name = BuilderTheme.mono_label("", 12, BuilderTheme.TEXT_BRIGHT)
	_pending_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_pending_name)
	_pending_detail = BuilderTheme.mono_label("", 10, BuilderTheme.TEXT_MUTED_DIM)
	_pending_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_pending_detail)

	var jettison := Button.new()
	jettison.text = "JETTISON"
	jettison.focus_mode = Control.FOCUS_NONE
	BuilderTheme.style_button(jettison, BuilderTheme.WARN, BuilderTheme.WARN_TEXT,
		BuilderTheme.WARN_TEXT_HOVER, 10, 10.0, 6.0)
	jettison.pressed.connect(func() -> void: jettison_requested.emit())
	column.add_child(jettison)


## `towed` is the part on the end of the grapple, or null. `contents` maps
## instance_id to the part in that cell, so the bays can name and colour what
## they are holding.
func refresh(hold: ShipHold, contents: Dictionary, towed: ModuleInstance,
		unstowed: Array = []) -> void:
	# A part that has gone (stowed, jettisoned, or a different one arriving) is
	# no longer the one in hand.
	if towed == null or _towed == null or towed.instance_id != _towed.instance_id:
		_carrying = false
	_towed = towed

	_bays.hold = hold
	_bays.contents = contents
	_bays.pending_size = Inventory.part_size(towed) if _carrying and towed != null else 0
	_bays.refresh()

	_pending_card.visible = towed != null
	if towed != null:
		_refresh_pending(hold, towed)

	_refresh_unstowed(unstowed)
	_status.text = _status_text(hold, towed)


func _refresh_pending(hold: ShipHold, towed: ModuleInstance) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(towed.module_type_id)
	if module_type != null:
		_pending_icon.configure(module_type, HullPaint.art_faction_for(towed, faction_id))
	_pending_icon.set_selected(_carrying)

	var cells: int = Inventory.part_size(towed)
	var fits: bool = hold != null and hold.has_room_for(cells)
	_pending_name.text = "%s · %s" % [towed.display_name(), towed.serial]
	var action: String = PROMPT_TEXT if _carrying else PICK_UP_TEXT
	_pending_detail.text = "%s · %d %s · %s" % [
		"In hand" if _carrying else "In tow",
		cells, "cell" if cells == 1 else "cells",
		action if fits else WONT_FIT_TEXT]
	_pending_card.add_theme_stylebox_override("panel", _pending_style())


## Amber while it is only being towed, cyan once it is in hand — the same
## colour the build field uses for a part waiting to be placed.
func _pending_style() -> StyleBoxFlat:
	var tint: Color = BuilderTheme.CYAN if _carrying else BuilderTheme.AMBER
	return BuilderTheme.padded(BuilderTheme.flat_style(
		BuilderTheme.with_alpha(tint, 0.16 if _carrying else 0.08),
		BuilderTheme.with_alpha(tint, 0.85 if _carrying else 0.35),
		BuilderTheme.RADIUS_MEDIUM), 12.0, 10.0)


func _on_card_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _towed == null:
		return
	_carrying = not _carrying
	_bays.pending_size = Inventory.part_size(_towed) if _carrying else 0
	_pending_icon.set_selected(_carrying)
	_pending_card.add_theme_stylebox_override("panel", _pending_style())
	_refresh_pending(_bays.hold, _towed)
	_bays.refresh()


## Cells only accept a click while a part is actually in hand, so clicking
## around the hold never moves anything by accident.
func _on_cell_clicked(bay_index: int, cell: Vector2i) -> void:
	if not _carrying:
		return
	stow_requested.emit(bay_index, cell)


func _refresh_unstowed(unstowed: Array) -> void:
	_unstowed.visible = not unstowed.is_empty()
	if unstowed.is_empty():
		return
	var names: Array[String] = []
	for part: ModuleInstance in unstowed:
		names.append(part.display_name())
	_unstowed.text = "NO CELL · %s" % ", ".join(names)


func _status_text(hold: ShipHold, _towed_part: ModuleInstance) -> String:
	if hold == null or hold.bay_count() == 0:
		return NO_BAYS_TEXT
	if hold.used_cells() == 0:
		return EMPTY_TEXT
	return "%d/%d cells used." % [hold.used_cells(), hold.total_cells()]

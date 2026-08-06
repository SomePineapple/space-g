extends GamePanel

## The Module Upgrades screen, built against docs/design_handoff_upgrade_tree/
## (README.md + LAYOUT_SPEC.md are the source of truth for its appearance,
## geometry and rules; upgrade_data.json is its content, copied into
## res://resources/upgrades/ — see ShipUpgradeCatalog).
##
## A left rail lists the seven ship systems; the main column shows that
## system's tree as a radial fan. Unlocks are ship-wide and stored by id in
## GameState, per the handoff's state model — they are not attached to a
## particular mounted module.
##
## Known gap, accepted deliberately: the handoff authors no stat modifiers, so
## unlocking spends resources and records the id but does not yet change ship
## behaviour. ShipUpgradeService is where that hook belongs when the effects
## pass happens; HardpointBank.apply_modifiers is how a modifier reaches an
## already-spawned hardpoint without rebuilding it.

const RAIL_WIDTH: float = 250.0
const RAIL_PADDING_VERTICAL: int = 26
const RAIL_PADDING_HORIZONTAL: int = 22
const DETAIL_MARGIN: int = 16
const TITLE_FONT_SIZE: int = 19
const HEADER_TITLE_FONT_SIZE: int = 22
const HEADER_SUBTITLE_FONT_SIZE: int = 13
const LEGEND_FONT_SIZE: int = 11
const LEGEND_DOT_SIZE: float = 8.0
## Where the screen opens when nothing has been viewed yet (handoff default).
const DEFAULT_CATEGORY: String = "power"

var _rail_list: UpgradeRailList
var _detail: UpgradeDetailPanel
var _tree_view: UpgradeTreeView
var _header_title: Label
var _header_progress: Label
var _legend: HBoxContainer

## Array of {"key", "label", "hue", "unlocked", "total"} — the rail's rows.
var _categories: Array = []
var _selected_index: int = -1

var _hovered_node_id: String = ""
var _selected_node_id: String = ""


func _init() -> void:
	toggle_action = "toggle_upgrades"
	requires_home_base = true
	# Full-screen takeover with its own background: it has to sit above the
	# gameplay HUD and the station prompt, which share CanvasLayer 1.
	layer = 10


func _setup() -> void:
	_build_ui()
	_build_categories()


func _on_opened() -> void:
	_refresh_progress()
	_select_category(_remembered_index())


# --- Construction -----------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	# ...and_offsets_preset, not set_anchors_preset: the latter preserves the
	# control's current (zero) rect by writing compensating offsets.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(BuilderBackdrop.new())

	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 0)
	root.add_child(columns)

	columns.add_child(_build_rail())
	columns.add_child(_build_main_column())


func _build_rail() -> PanelContainer:
	var rail := PanelContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	var style: StyleBoxFlat = BuilderTheme.flat_style(
		BuilderTheme.with_alpha(BuilderTheme.GLASS, 0.55), Color.TRANSPARENT, 0)
	style.border_width_right = 1
	style.border_color = BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.18)
	style.content_margin_top = RAIL_PADDING_VERTICAL
	style.content_margin_bottom = RAIL_PADDING_VERTICAL
	rail.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	rail.add_child(column)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", RAIL_PADDING_HORIZONTAL)
	title_margin.add_theme_constant_override("margin_right", RAIL_PADDING_HORIZONTAL)
	title_margin.add_theme_constant_override("margin_bottom", 20)
	title_margin.add_child(BuilderTheme.sans_label("Module Upgrades", TITLE_FONT_SIZE, BuilderTheme.TEXT_BRIGHT))
	column.add_child(title_margin)

	_rail_list = UpgradeRailList.new()
	_rail_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail_list.category_selected.connect(_select_category)
	column.add_child(_rail_list)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", DETAIL_MARGIN)
	detail_margin.add_theme_constant_override("margin_right", DETAIL_MARGIN)
	detail_margin.add_theme_constant_override("margin_top", DETAIL_MARGIN)
	column.add_child(detail_margin)

	_detail = UpgradeDetailPanel.new()
	_detail.unlock_pressed.connect(_on_unlock_pressed)
	detail_margin.add_child(_detail)
	return rail


func _build_main_column() -> VBoxContainer:
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 40)
	header_margin.add_theme_constant_override("margin_right", 40)
	header_margin.add_theme_constant_override("margin_top", 16)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	main.add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)

	_header_title = BuilderTheme.sans_label("", HEADER_TITLE_FONT_SIZE, BuilderTheme.TEXT_SELECTED)
	_header_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_header_title)

	var subtitle: Label = BuilderTheme.mono_label("Upgrade Tree", HEADER_SUBTITLE_FONT_SIZE, BuilderTheme.TEXT_HINT)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(subtitle)

	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 14)
	_legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_legend)

	_header_progress = BuilderTheme.mono_label("", HEADER_SUBTITLE_FONT_SIZE, BuilderTheme.TEXT_HINT)
	_header_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_header_progress)

	_tree_view = UpgradeTreeView.new()
	_tree_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_view.node_hovered.connect(_on_node_hovered)
	_tree_view.hover_exited.connect(_on_tree_hover_exited)
	_tree_view.node_clicked.connect(_on_node_clicked)
	main.add_child(_tree_view)
	return main


# --- Categories -------------------------------------------------------------

func _build_categories() -> void:
	_categories.clear()
	for category in ShipUpgradeCatalog.get_categories():
		var progress: Vector2i = ShipUpgradeService.progress(category["key"])
		_categories.append({
			"key": category["key"],
			"label": category["label"],
			"hue": float(category["hue"]),
			"unlocked": progress.x,
			"total": progress.y,
		})
	_rail_list.set_categories(_categories)
	_tree_view.set_reference_frame(_shared_frame())


func _refresh_progress() -> void:
	for index in _categories.size():
		var progress: Vector2i = ShipUpgradeService.progress(_categories[index]["key"])
		_rail_list.update_progress(index, progress.x)


## The union of every tree's extent. Feeding this to the view as its fit
## target keeps one node size across the whole screen — otherwise a narrow
## tree would scale up to fill the panel and the nodes would visibly change
## size every time the player picked a different system.
func _shared_frame() -> Rect2:
	var frame: Rect2 = Rect2()
	var first: bool = true
	for category in _categories:
		var layout := UpgradeTreeLayout.new()
		layout.build(_tree_nodes(category["key"]), category["hue"])
		frame = layout.frame if first else frame.merge(layout.frame)
		first = false
	return frame


func _remembered_index() -> int:
	var wanted: String = GameState.last_upgrade_category
	if wanted.is_empty():
		wanted = DEFAULT_CATEGORY
	for index in _categories.size():
		if _categories[index]["key"] == wanted:
			return index
	return 0 if not _categories.is_empty() else -1


func _select_category(index: int) -> void:
	_selected_index = index
	_rail_list.set_selected(index)
	_selected_node_id = ""
	_hovered_node_id = ""
	if index < 0:
		return

	var category: Dictionary = _categories[index]
	GameState.last_upgrade_category = category["key"]
	_header_title.text = category["label"]
	_tree_view.set_tree(_tree_nodes(category["key"]), category["hue"])
	_rebuild_legend(category["key"])
	_refresh_states()
	_detail.show_message("Hover a node for details.")


# --- Tree -------------------------------------------------------------------

## Adapts the catalog's rows into the shape UpgradeTreeView expects. `hue` is
## optional in the data and marks the start of a coloured branch.
func _tree_nodes(category_key: String) -> Array:
	var result: Array = []
	for node in ShipUpgradeCatalog.get_tree(category_key):
		result.append({
			"id": node["id"],
			"parents": node["parents"].duplicate(),
			"tier": node["tier"],
			"label": node["label"],
			"glyph": node["glyph"],
			"branch_hue": float(node["hue"]) if node.has("hue") else -1.0,
		})
	return result


func _refresh_states() -> void:
	if _selected_index < 0:
		return
	var category_key: String = _categories[_selected_index]["key"]
	var states: Dictionary = {}
	for node in ShipUpgradeCatalog.get_tree(category_key):
		if ShipUpgradeService.is_unlocked(category_key, node["id"]):
			states[node["id"]] = UpgradeTreeView.STATE_UNLOCKED
		elif ShipUpgradeService.is_available(category_key, node):
			states[node["id"]] = UpgradeTreeView.STATE_AVAILABLE
		else:
			states[node["id"]] = UpgradeTreeView.STATE_LOCKED
	_tree_view.set_states(states)

	var progress: Vector2i = ShipUpgradeService.progress(category_key)
	_header_progress.text = "%d/%d unlocked" % [progress.x, progress.y]
	_header_progress.add_theme_color_override("font_color",
		UpgradePalette.bright(_categories[_selected_index]["hue"]))
	_rail_list.update_progress(_selected_index, progress.x)


## Only shown for trees that declare branch hues — currently Weapons, whose
## laser / missile / rail mounts each start their own colour.
func _rebuild_legend(category_key: String) -> void:
	_clear_legend()
	for node in ShipUpgradeCatalog.get_tree(category_key):
		if not node.has("hue"):
			continue
		var unlocked: bool = ShipUpgradeService.is_unlocked(category_key, node["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(BuilderTheme.make_glow_dot(UpgradePalette.bright(float(node["hue"])), LEGEND_DOT_SIZE))
		row.add_child(BuilderTheme.mono_label(node["label"], LEGEND_FONT_SIZE,
			BuilderTheme.TEXT_BODY if unlocked else BuilderTheme.TEXT_LABEL))
		_legend.add_child(row)


func _clear_legend() -> void:
	for child in _legend.get_children():
		child.queue_free()


# --- Detail panel -----------------------------------------------------------

func _on_node_hovered(node_id: String) -> void:
	_hovered_node_id = node_id
	_show_detail(node_id)


## Hover takes precedence over the last click, falling back to it on mouse-out
## so the panel never flickers empty (handoff "Interactions").
func _on_tree_hover_exited() -> void:
	_hovered_node_id = ""
	if _selected_node_id.is_empty():
		_detail.show_message("Hover a node for details.")
	else:
		_show_detail(_selected_node_id)


## Clicking an available node unlocks it; anything else just selects, so a
## locked node can still be inspected.
func _on_node_clicked(node_id: String) -> void:
	_selected_node_id = node_id
	if _can_unlock(node_id):
		_unlock(node_id)
	else:
		_show_detail(node_id)


func _show_detail(node_id: String) -> void:
	if _selected_index < 0:
		return
	var category_key: String = _categories[_selected_index]["key"]
	var node: Dictionary = ShipUpgradeCatalog.get_node(category_key, node_id)
	if node.is_empty():
		return

	var unlocked: bool = ShipUpgradeService.is_unlocked(category_key, node_id)
	var state: String = UpgradeTreeView.STATE_UNLOCKED
	if not unlocked:
		state = UpgradeTreeView.STATE_AVAILABLE if ShipUpgradeService.is_available(category_key, node) \
			else UpgradeTreeView.STATE_LOCKED
	var reason: String = "" if unlocked else ShipUpgradeService.get_rejection_reason(
		inventory, category_key, node_id)
	var is_root: bool = node_id == ShipUpgradeCatalog.ROOT_ID

	_detail.show_node({
		"id": node_id,
		"label": node["label"],
		"tier": node["tier"],
		"is_base": is_root,
		"description": node["desc"],
		"cost_text": "" if is_root else node["cost"],
		"effect_text": "",
		"state": state,
		"hue": _tree_view.hue_of(node_id),
		"can_unlock": reason.is_empty() and not unlocked,
		"reason": "" if state != UpgradeTreeView.STATE_AVAILABLE else reason,
		"requirements": _requirements_for(category_key, node),
	})


## The handoff's REQUIRES ALL block, shown for merge nodes — those needing two
## or more branches to converge.
func _requirements_for(category_key: String, node: Dictionary) -> Array:
	if node["parents"].size() < 2:
		return []
	var rows: Array = []
	for parent_id in node["parents"]:
		var parent: Dictionary = ShipUpgradeCatalog.get_node(category_key, parent_id)
		rows.append({
			"label": parent.get("label", parent_id),
			"met": ShipUpgradeService.is_unlocked(category_key, parent_id),
			"hue": _tree_view.hue_of(parent_id),
		})
	return rows


# --- Unlocking --------------------------------------------------------------

func _can_unlock(node_id: String) -> bool:
	if _selected_index < 0:
		return false
	return ShipUpgradeService.can_unlock(inventory, _categories[_selected_index]["key"], node_id)


func _on_unlock_pressed(node_id: String) -> void:
	if not node_id.is_empty() and _can_unlock(node_id):
		_unlock(node_id)


## Re-deriving availability afterwards is what makes newly unlockable children
## start their dashed pulse and the connector to the parent brighten — there
## is no animation to author, it falls out of the state change.
func _unlock(node_id: String) -> void:
	var category_key: String = _categories[_selected_index]["key"]
	if not ShipUpgradeService.unlock(inventory, category_key, node_id):
		return
	_refresh_states()
	_rebuild_legend(category_key)
	_show_detail(node_id)

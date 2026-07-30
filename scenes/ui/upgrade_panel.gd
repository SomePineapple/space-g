extends CanvasLayer

const BOX_WIDTH: float = 220.0
const BOX_HEIGHT: float = 50.0
const COLUMN_SPACING: float = 30.0
const ROW_SPACING: float = 50.0
const HEADER_HEIGHT: float = 30.0

## Only lets the upgrade panel open near the region's home base marker,
## matching the ship builder's gating.
@export var home_base_range: float = 300.0

var _ship: Ship
var _manager: UpgradeManager
var _buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to this specific panel.
	add_to_group("menu_panel")

	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_ship = players[0]
	_manager = _ship.get_node("UpgradeManager")
	_manager.upgrade_purchased.connect(_on_state_changed)
	_ship.get_node("Inventory").materials_changed.connect(_on_state_changed)

	_build_ui()
	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_upgrades"):
		return

	if visible:
		visible = false
		return

	if _is_near_home_base():
		visible = true


func _is_near_home_base() -> bool:
	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if _ship == null or home_bases.is_empty():
		return false
	return _ship.global_position.distance_to(home_bases[0].global_position) <= home_base_range


func _build_ui() -> void:
	var panel := Control.new()
	panel.position = Vector2(20, 60)
	add_child(panel)

	var lines_layer := UpgradeTreeLines.new()
	panel.add_child(lines_layer)

	var all_nodes: Array = UpgradeCatalog.get_all()
	var depths: Dictionary = _compute_depths(all_nodes)

	var trees: Array = []
	for node in all_nodes:
		if not trees.has(node.tree_id):
			trees.append(node.tree_id)

	var tree_column: Dictionary = {}
	for i in trees.size():
		tree_column[trees[i]] = i

	for tree_id in trees:
		var header := Label.new()
		header.text = String(tree_id).capitalize()
		header.position = Vector2(tree_column[tree_id] * (BOX_WIDTH + COLUMN_SPACING), 0)
		header.size = Vector2(BOX_WIDTH, HEADER_HEIGHT)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(header)

	var box_rects: Dictionary = {}
	var max_depth: int = 0

	for node in all_nodes:
		var col: int = tree_column[node.tree_id]
		var row: int = depths[node.id]
		max_depth = maxi(max_depth, row)
		var pos := Vector2(col * (BOX_WIDTH + COLUMN_SPACING), HEADER_HEIGHT + row * (BOX_HEIGHT + ROW_SPACING))
		box_rects[node.id] = Rect2(pos, Vector2(BOX_WIDTH, BOX_HEIGHT))

		var button := Button.new()
		button.position = pos
		button.size = Vector2(BOX_WIDTH, BOX_HEIGHT)
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_button_pressed.bind(node.id))
		panel.add_child(button)
		_buttons[node.id] = button

	var connections: Array = []
	for node in all_nodes:
		var to_rect: Rect2 = box_rects[node.id]
		var to_point: Vector2 = to_rect.position + Vector2(to_rect.size.x * 0.5, 0.0)
		for req_id in node.requires:
			var from_rect: Rect2 = box_rects[req_id]
			var from_point: Vector2 = from_rect.position + Vector2(from_rect.size.x * 0.5, from_rect.size.y)
			connections.append({"from": from_point, "to": to_point})

	lines_layer.position = Vector2.ZERO
	lines_layer.size = Vector2(
		trees.size() * (BOX_WIDTH + COLUMN_SPACING),
		HEADER_HEIGHT + (max_depth + 1) * (BOX_HEIGHT + ROW_SPACING)
	)
	lines_layer.set_lines(connections)


func _compute_depths(all_nodes: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for node in all_nodes:
		by_id[node.id] = node

	var depths: Dictionary = {}
	for node in all_nodes:
		_get_depth(node.id, by_id, depths)

	return depths


func _get_depth(id: String, by_id: Dictionary, depths: Dictionary) -> int:
	if depths.has(id):
		return depths[id]

	var node: UpgradeNode = by_id[id]
	var max_parent_depth: int = -1
	for req_id in node.requires:
		max_parent_depth = maxi(max_parent_depth, _get_depth(req_id, by_id, depths))

	var d: int = max_parent_depth + 1
	depths[id] = d
	return d


func _on_button_pressed(id: String) -> void:
	_manager.purchase(id)


func _on_state_changed(_value) -> void:
	_refresh_all()


func _refresh_all() -> void:
	for node in UpgradeCatalog.get_all():
		var button: Button = _buttons[node.id]
		if _manager.is_unlocked(node.id):
			button.text = "%s\nOwned" % node.display_name
			button.disabled = true
		else:
			button.text = "%s\n%s" % [node.display_name, _format_costs(node.costs)]
			button.disabled = not _manager.can_purchase(node.id)


func _format_costs(costs: Dictionary) -> String:
	var parts: Array = []
	for material_id in costs:
		parts.append("%d %s" % [costs[material_id], Materials.display_name(material_id)])
	return ", ".join(parts)

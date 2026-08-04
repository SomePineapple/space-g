class_name ModuleUpgradeTree
extends Control

## The per-module-instance radial upgrade tree overlay (Phase 8.1), opened
## from the ship builder's "Upgrade" button for whichever placement is
## currently selected. Node positions are computed purely from each
## ModuleUpgradeNode's own `requires` chain (see _layout_tree()) — nothing
## about the fan shape is hand-authored per tree, so a brand new tree in
## ModuleUpgradeCatalog draws correctly with zero UI changes.
##
## Visual language (per explicit reference/request):
## - Unlocked nodes: bright, filled, a checkmark glyph.
## - Ready to unlock (prereqs + cross-module requirements met, affordable):
##   full brightness plus a pulsing glow halo.
## - Reachable but blocked (missing resources/cross-module requirement):
##   dulled, non-interactive, tooltip explains why.
## - Not yet reachable (same-tree prerequisite missing): almost hidden.
## Hovering any node shows its name/description/cost/effect via the engine's
## own tooltip (Control.tooltip_text) rather than a custom popup.

signal closed()
signal upgrade_unlocked(upgrade_id: String)

const PANEL_SIZE: Vector2 = Vector2(780.0, 580.0)
const TITLE_HEIGHT: float = 40.0
const STATUS_HEIGHT: float = 26.0
const NODE_DIAMETER: float = 52.0
const RING_BASE: float = 60.0
const RING_SPACING: float = 100.0
const ARC_HALF_DEGREES: float = 78.0
const GLOW_DIAMETER: float = 78.0

const COLOR_DIM_BACKDROP: Color = Color(0.0, 0.0, 0.0, 0.55)
const COLOR_PANEL_BG: Color = Color(0.05, 0.06, 0.09, 0.92)
const COLOR_LINE_BRIGHT: Color = Color(0.8, 0.85, 0.95, 0.9)
const COLOR_LINE_DIM: Color = Color(0.4, 0.45, 0.55, 0.25)
const COLOR_UNLOCKED: Color = Color(0.95, 0.8, 0.35)
const COLOR_READY: Color = Color(0.45, 0.85, 1.0)
const COLOR_LOCKED_NEAR: Color = Color(0.55, 0.58, 0.65)
const COLOR_LOCKED_FAR: Color = Color(0.4, 0.42, 0.48)
const COLOR_GLOW: Color = Color(0.5, 0.9, 1.0)

var _ship_layout: ShipLayout
var _inventory: Inventory
var _placement: ModulePlacement

var _tree_area: _TreeArea
var _title_label: Label
var _status_label: Label
var _center_label: Label

## upgrade_id -> Button
var _node_buttons: Dictionary = {}
## upgrade_id -> Panel (glow halo, only created for nodes in the "ready" state).
var _node_glow_panels: Dictionary = {}
## upgrade_id -> StyleBoxFlat, that Panel's own style resource — animated
## directly by _set_glow_alpha, since mutating a StyleBoxFlat's color is
## enough for Godot to redraw the Panel using it.
var _node_glow_styles: Dictionary = {}
var _glow_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = COLOR_DIM_BACKDROP
	add_child(backdrop)

	var panel := Panel.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)

	_title_label = Label.new()
	_title_label.position = Vector2(16, 8)
	_title_label.size = Vector2(PANEL_SIZE.x - 90, TITLE_HEIGHT - 8)
	_title_label.add_theme_font_size_override("font_size", 20)
	panel.add_child(_title_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.position = Vector2(PANEL_SIZE.x - 76, 8)
	close_button.size = Vector2(60, 26)
	close_button.pressed.connect(func(): closed.emit())
	panel.add_child(close_button)

	_status_label = Label.new()
	_status_label.position = Vector2(16, PANEL_SIZE.y - STATUS_HEIGHT - 6)
	_status_label.size = Vector2(PANEL_SIZE.x - 32, STATUS_HEIGHT)
	_status_label.clip_text = true
	panel.add_child(_status_label)

	_tree_area = _TreeArea.new()
	_tree_area.position = Vector2(0, TITLE_HEIGHT)
	_tree_area.size = Vector2(PANEL_SIZE.x, PANEL_SIZE.y - TITLE_HEIGHT - STATUS_HEIGHT)
	panel.add_child(_tree_area)

	_center_label = Label.new()
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 14)
	_tree_area.add_child(_center_label)

	_glow_tween = create_tween()
	_glow_tween.set_loops()
	_glow_tween.tween_method(_set_glow_alpha, 0.15, 0.55, 1.1)
	_glow_tween.tween_method(_set_glow_alpha, 0.55, 0.15, 1.1)

	# Centers the panel on the viewport. Deliberately NOT using
	# set_anchors_preset(PRESET_CENTER) here — with its default
	# keep_offsets=false it recomputes offsets to preserve the control's
	# *current* on-screen rect under the new anchor, i.e. it does not
	# recenter a control already sitting at the top-left corner (which is
	# where a freshly-added, default-anchored Panel starts). Also
	# deliberately reads the viewport directly rather than this control's
	# own `size` — despite the PRESET_FULL_RECT anchors set above, `size`
	# still reads back (0, 0) synchronously inside the same _ready() (Control
	# layout recomputation is deferred), which silently reproduced the same
	# off-screen bug through different math.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	panel.position = (viewport_size - PANEL_SIZE) * 0.5


## Opens (or refreshes, if already open) the tree for `placement`. Safe to
## call repeatedly — e.g. the ship builder calls this again if the player
## presses Upgrade a second time without closing the overlay first.
func open(ship_layout: ShipLayout, inventory: Inventory, placement: ModulePlacement) -> void:
	_ship_layout = ship_layout
	_inventory = inventory
	_placement = placement
	_rebuild()


func _rebuild() -> void:
	for child in _node_buttons.values():
		child.queue_free()
	_node_buttons.clear()
	for child in _node_glow_panels.values():
		child.queue_free()
	_node_glow_panels.clear()
	_node_glow_styles.clear()

	var module_type: ModuleType = ModuleCatalog.get_by_id(_placement.module_type_id)
	var instance: ModuleInstance = _placement.ensure_instance()
	_title_label.text = "%s — Upgrade Tree (Level %d)" % [module_type.display_name, instance.get_level()]
	_status_label.text = "Hover a node for details. Click a glowing node to unlock it."

	var nodes: Array[ModuleUpgradeNode] = ModuleUpgradeService.get_tree_for_placement(_placement)
	if nodes.is_empty():
		_center_label.text = "%s has no upgrades yet." % module_type.display_name
		_center_label.position = _tree_area.size * 0.5 - Vector2(80, 0)
		_center_label.size = Vector2(160, 20)
		_tree_area.set_segments([])
		return

	var origin: Vector2 = Vector2(_tree_area.size.x * 0.5, _tree_area.size.y - 30.0)
	_center_label.text = module_type.display_name
	_center_label.position = origin - Vector2(60, 34)
	_center_label.size = Vector2(120, 20)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var positions: Dictionary = _layout_tree(nodes, origin)
	var segments: Array = []

	for node in nodes:
		var state: String = _state_for(instance, node)
		var pos: Vector2 = positions[node.id]

		for req_id in node.requires:
			if positions.has(req_id):
				segments.append({
					"from": positions[req_id], "to": pos,
					"color": COLOR_LINE_BRIGHT if state == "unlocked" else COLOR_LINE_DIM,
				})
		if node.requires.is_empty():
			segments.append({"from": origin, "to": pos, "color": COLOR_LINE_BRIGHT if state == "unlocked" else COLOR_LINE_DIM})

		if state == "ready":
			var glow := Panel.new()
			glow.size = Vector2(GLOW_DIAMETER, GLOW_DIAMETER)
			glow.position = pos - Vector2(GLOW_DIAMETER, GLOW_DIAMETER) * 0.5
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var glow_style := StyleBoxFlat.new()
			glow_style.bg_color = Color(COLOR_GLOW, 0.35)
			var glow_radius: int = int(GLOW_DIAMETER * 0.5)
			glow_style.corner_radius_top_left = glow_radius
			glow_style.corner_radius_top_right = glow_radius
			glow_style.corner_radius_bottom_left = glow_radius
			glow_style.corner_radius_bottom_right = glow_radius
			glow.add_theme_stylebox_override("panel", glow_style)
			_tree_area.add_child(glow)
			_tree_area.move_child(glow, 0)
			_node_glow_panels[node.id] = glow
			_node_glow_styles[node.id] = glow_style

		var button := Button.new()
		button.size = Vector2(NODE_DIAMETER, NODE_DIAMETER)
		button.position = pos - Vector2(NODE_DIAMETER, NODE_DIAMETER) * 0.5
		button.text = node.glyph if state != "unlocked" else "OK"
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = _tooltip_for(instance, node, state)
		button.disabled = state != "ready"
		button.modulate = _color_for_state(state)
		_make_circle_button(button, NODE_DIAMETER * 0.5)
		button.pressed.connect(_on_node_pressed.bind(node.id))
		_tree_area.add_child(button)
		_node_buttons[node.id] = button

	_tree_area.set_segments(segments)


func _set_glow_alpha(alpha: float) -> void:
	for style in _node_glow_styles.values():
		style.bg_color.a = alpha


func _color_for_state(state: String) -> Color:
	match state:
		"unlocked":
			return COLOR_UNLOCKED
		"ready":
			return COLOR_READY
		"locked_near":
			return Color(COLOR_LOCKED_NEAR, 0.75)
		_:
			return Color(COLOR_LOCKED_FAR, 0.22)


## "unlocked" (already owned), "ready" (unlockable right now), "locked_near"
## (same-tree prerequisites met but blocked on cost/cross-module modules —
## dulled, visible, tooltip explains why) or "locked_far" (same-tree
## prerequisite still missing — almost hidden, per the reference design).
func _state_for(instance: ModuleInstance, node: ModuleUpgradeNode) -> String:
	if instance.is_upgrade_unlocked(node.id):
		return "unlocked"
	if not ModuleUpgradeService.prerequisites_met(instance, node):
		return "locked_far"
	var reason: String = ModuleUpgradeService.get_rejection_reason(_ship_layout, _inventory, _placement, node.id)
	return "ready" if reason == "" else "locked_near"


func _tooltip_for(instance: ModuleInstance, node: ModuleUpgradeNode, state: String) -> String:
	var lines: Array = [node.display_name, node.description, ""]

	if not node.modifiers.is_empty():
		lines.append("Effect:")
		for stat_name in node.modifiers:
			var before: float = instance.get_stat_modifier(stat_name)
			var after: float = before + node.modifiers[stat_name]
			lines.append("  %s: %+.2f -> %+.2f" % [stat_name.capitalize(), before, after])
		lines.append("")

	lines.append("Cost: %s" % _format_costs(node.costs))
	if not node.requires_ship_modules.is_empty():
		var names: Array = []
		for required_type_id in node.requires_ship_modules:
			var required_type: ModuleType = ModuleCatalog.get_by_id(required_type_id)
			names.append(required_type.display_name if required_type != null else required_type_id)
		lines.append("Requires installed: %s" % ", ".join(names))

	if state == "unlocked":
		lines.append("")
		lines.append("Unlocked.")
	elif state != "ready":
		var reason: String = ModuleUpgradeService.get_rejection_reason(_ship_layout, _inventory, _placement, node.id)
		lines.append("")
		lines.append("Locked: %s" % reason)

	return "\n".join(lines)


func _format_costs(costs: Dictionary) -> String:
	if costs.is_empty():
		return "Free"
	var parts: Array = []
	for id in costs:
		var item_name: String = ComponentCatalog.display_name(id) if ComponentCatalog.get_by_id(id) != null else MaterialCatalog.display_name(id)
		parts.append("%d %s" % [costs[id], item_name])
	return ", ".join(parts)


func _on_node_pressed(upgrade_id: String) -> void:
	var node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(upgrade_id)
	if ModuleUpgradeService.unlock(_ship_layout, _inventory, _placement, upgrade_id):
		_status_label.text = "Unlocked %s." % node.display_name
		upgrade_unlocked.emit(upgrade_id)
		_rebuild()
	else:
		_status_label.text = "Cannot unlock %s: %s" % [
			node.display_name, ModuleUpgradeService.get_rejection_reason(_ship_layout, _inventory, _placement, upgrade_id)]


## Rounds every corner of a Button to its own half-size, turning a square
## button into a circle — same trick used for the glow Panels above.
func _make_circle_button(button: Button, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)


## Radial layout: each node's ring comes from its depth in the `requires`
## chain (longest path from any root, so a node converging two branches sits
## beyond both — see engine_lvl_3 in ModuleUpgradeCatalog), and its angle is
## the average of its children's angles, with leaves evenly spread across a
## fixed arc. Purely structural — no per-node position is ever authored.
func _layout_tree(nodes: Array[ModuleUpgradeNode], origin: Vector2) -> Dictionary:
	var by_id: Dictionary = {}
	for node in nodes:
		by_id[node.id] = node

	# "Primary parent" (first listed requirement, or "" for a root) decides
	# tree structure/slot allocation; a second+ requirement (convergence,
	# e.g. engine_lvl_3) still gets its own connecting line drawn in _rebuild,
	# it just doesn't affect layout math.
	var primary_children: Dictionary = {"": []}
	for node in nodes:
		var parent_id: String = node.requires[0] if not node.requires.is_empty() else ""
		if not primary_children.has(parent_id):
			primary_children[parent_id] = []
		primary_children[parent_id].append(node.id)

	var depths: Dictionary = {}
	for node in nodes:
		_compute_depth(node.id, by_id, depths)

	var leaf_count: int = _count_leaves("", primary_children)
	var next_slot: Array = [0]
	var angles: Dictionary = {}
	_assign_angles("", primary_children, leaf_count, next_slot, angles)

	var positions: Dictionary = {}
	for node in nodes:
		var radius: float = RING_BASE + (depths[node.id] + 1) * RING_SPACING
		var angle_rad: float = deg_to_rad(angles.get(node.id, 0.0))
		positions[node.id] = origin + Vector2(sin(angle_rad), -cos(angle_rad)) * radius
	return positions


func _compute_depth(id: String, by_id: Dictionary, depths: Dictionary) -> int:
	if depths.has(id):
		return depths[id]
	var node: ModuleUpgradeNode = by_id[id]
	var max_parent_depth: int = -1
	for req_id in node.requires:
		if by_id.has(req_id):
			max_parent_depth = maxi(max_parent_depth, _compute_depth(req_id, by_id, depths))
	var depth: int = max_parent_depth + 1
	depths[id] = depth
	return depth


func _count_leaves(id: String, primary_children: Dictionary) -> int:
	var kids: Array = primary_children.get(id, [])
	if kids.is_empty():
		return 1
	var total: int = 0
	for kid in kids:
		total += _count_leaves(kid, primary_children)
	return total


func _assign_angles(id: String, primary_children: Dictionary, leaf_count: int, next_slot: Array, angles: Dictionary) -> float:
	var kids: Array = primary_children.get(id, [])
	if kids.is_empty():
		var t: float = (next_slot[0] + 0.5) / float(leaf_count)
		next_slot[0] += 1
		var angle: float = lerp(-ARC_HALF_DEGREES, ARC_HALF_DEGREES, t) if leaf_count > 1 else 0.0
		angles[id] = angle
		return angle
	var sum: float = 0.0
	for kid in kids:
		sum += _assign_angles(kid, primary_children, leaf_count, next_slot, angles)
	var avg: float = sum / kids.size()
	angles[id] = avg
	return avg


## Small nested Control that just draws straight connecting lines behind
## whatever node buttons its parent adds as children — kept minimal (no
## state of its own beyond the segment list) rather than a whole separate file.
class _TreeArea:
	extends Control

	var _segments: Array = []

	func set_segments(segments: Array) -> void:
		_segments = segments
		queue_redraw()

	func _draw() -> void:
		for segment in _segments:
			draw_line(segment["from"], segment["to"], segment["color"], 2.0, true)

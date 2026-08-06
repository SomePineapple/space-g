class_name UpgradeTreeLayout
extends RefCounted

## The polar layout for one upgrade tree
## (docs/design_handoff_upgrade_tree/LAYOUT_SPEC.md §3): tier maps to radius,
## angle is allocated by recursive subdivision of the root's arc.
##
## Split out of UpgradeTreeView so a tree can be measured without being the
## one on screen — the upgrade screen fits every tree to one shared scale, so
## it needs the frame of trees it is not currently drawing (see
## UpgradeTreeView.set_reference_frame).
##
## Node dictionaries expected:
##   id: String, parents: Array[String], label: String, glyph: String,
##   branch_hue: float (< 0 inherits from parents[0], else starts a branch)

const BASE_R: float = 78.0
const STEP: float = 104.0
const MAX_ANGLE: float = 72.0
const MERGE_RADIUS_OFFSET: float = 0.4 * STEP

const DIAMETER_ROOT: float = 60.0
const DIAMETER_MERGE: float = 54.0
const DIAMETER_NORMAL: float = 48.0

const LABEL_WIDTH: float = 104.0
const LABEL_FONT_SIZE: int = 13
const LABEL_GAP: float = 9.0
## Beyond this angle the radius is near-horizontal, so a label offset outward
## would reach into the neighbouring ring — those labels hang below instead.
const LABEL_TANGENTIAL_ANGLE: float = 50.0

## Padding around the measured frame so glows and the availability pulse are
## not clipped at the panel edge.
const FRAME_PADDING: float = 18.0

## id -> {"position", "radius", "angle_degrees", "diameter", "tier", "hue",
##        "merge_hues", "label_rect"} in unscaled tree space.
var entries: Dictionary = {}
## Radius of each tier's dashed guide arc, outermost last.
var tier_radii: Array = []
## The real extent of nodes *and* labels — what fit-to-panel scales.
var frame: Rect2 = Rect2()
var root_id: String = ""

var _nodes: Array = []
var _by_id: Dictionary = {}
var _base_hue: float = 0.0


## `nodes` must contain exactly one node with no parents.
func build(nodes: Array, base_hue: float) -> void:
	_nodes = nodes
	_base_hue = base_hue
	_by_id.clear()
	entries.clear()
	tier_radii.clear()
	frame = Rect2()
	root_id = ""
	for node in nodes:
		_by_id[node["id"]] = node

	var children: Dictionary = {}
	for node in nodes:
		var parents: Array = node["parents"]
		if parents.is_empty():
			root_id = node["id"]
		elif parents.size() == 1:
			# Only single-parent nodes claim angular span; merges are placed
			# afterwards from their parents' angles so they never steal room
			# from a branch (§3.1).
			if not children.has(parents[0]):
				children[parents[0]] = []
			children[parents[0]].append(node["id"])
	if root_id.is_empty():
		return

	var tiers: Dictionary = {}
	for node in nodes:
		_tier_of(node["id"], tiers)

	var angles: Dictionary = {}
	_allocate_span(root_id, -MAX_ANGLE, MAX_ANGLE, children, angles)
	for node in nodes:
		if node["parents"].size() >= 2:
			var sum: float = 0.0
			for parent_id in node["parents"]:
				sum += angles.get(parent_id, 0.0)
			angles[node["id"]] = sum / node["parents"].size()

	var max_tier: int = 0
	for node in nodes:
		var node_id: String = node["id"]
		# The data may author `tier` (the handoff's trees do); otherwise fall
		# back to the longest path, which is what an authored tier encodes.
		var tier: int = int(node["tier"]) if node.has("tier") else tiers[node_id]
		max_tier = maxi(max_tier, tier)
		var is_merge: bool = node["parents"].size() >= 2
		var radius: float = 0.0 if tier == 0 else BASE_R + tier * STEP + (MERGE_RADIUS_OFFSET if is_merge else 0.0)
		var angle: float = deg_to_rad(angles.get(node_id, 0.0))
		var diameter: float = DIAMETER_ROOT if node_id == root_id else (DIAMETER_MERGE if is_merge else DIAMETER_NORMAL)

		var entry: Dictionary = {
			"position": Vector2(sin(angle), -cos(angle)) * radius,
			"radius": radius,
			"angle_degrees": angles.get(node_id, 0.0),
			"diameter": diameter,
			"tier": tier,
			"hue": _hue_of(node_id),
			"merge_hues": _merge_hues_of(node) if is_merge else [],
			# Carried so the renderer can work purely from `entries` and never
			# hold its own copy of the node list that could fall out of step.
			"label": node["label"],
			"glyph": node["glyph"],
			"parents": node["parents"].duplicate(),
		}
		entry["label_rect"] = _label_rect(entry, node["label"])
		entries[node_id] = entry

	for tier in range(1, max_tier + 1):
		tier_radii.append(BASE_R + tier * STEP)

	frame = _measure_frame()


## Longest path from the root, so a merge sits beyond both of its parents.
func _tier_of(node_id: String, tiers: Dictionary) -> int:
	if tiers.has(node_id):
		return tiers[node_id]
	var deepest_parent: int = -1
	for parent_id in _by_id[node_id]["parents"]:
		if _by_id.has(parent_id):
			deepest_parent = maxi(deepest_parent, _tier_of(parent_id, tiers))
	tiers[node_id] = deepest_parent + 1
	return tiers[node_id]


## Walks up parents[0] until a node declares its own branch hue, else the
## category hue ("Colour marks the branch").
func _hue_of(node_id: String) -> float:
	var node: Dictionary = _by_id[node_id]
	if node.get("branch_hue", -1.0) >= 0.0:
		return node["branch_hue"]
	var parents: Array = node["parents"]
	if parents.is_empty() or not _by_id.has(parents[0]):
		return _base_hue
	return _hue_of(parents[0])


func _merge_hues_of(node: Dictionary) -> Array:
	var hues: Array = []
	for parent_id in node["parents"]:
		if not _by_id.has(parent_id):
			continue
		var hue: float = _hue_of(parent_id)
		if not hues.has(hue):
			hues.append(hue)
	return hues


func _allocate_span(node_id: String, span_min: float, span_max: float,
		children: Dictionary, angles: Dictionary) -> void:
	var midpoint: float = (span_min + span_max) * 0.5
	angles[node_id] = midpoint

	var kids: Array = children.get(node_id, [])
	if kids.is_empty():
		return
	if midpoint > 0.0:
		# Mirroring: without this, "first child" is outermost on the left and
		# innermost on the right and the fan comes out crooked (§3.2).
		kids = kids.duplicate()
		kids.reverse()

	var width: float = (span_max - span_min) / kids.size()
	for index in kids.size():
		_allocate_span(kids[index], span_min + index * width, span_min + (index + 1) * width, children, angles)


## Where the label sits, in tree space. Placement and the frame reservation
## below share this one function precisely so a capstone's label — which sits
## *above* its node — is never clipped ("Labels").
func _label_rect(entry: Dictionary, text: String) -> Rect2:
	var font: Font = BuilderTheme.mono_font()
	var measured: Vector2 = font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_FONT_SIZE)
	var box := Vector2(LABEL_WIDTH, maxf(measured.y, LABEL_FONT_SIZE))
	var centre: Vector2 = entry["position"]
	var half: float = entry["diameter"] * 0.5

	if absf(entry["angle_degrees"]) <= LABEL_TANGENTIAL_ANGLE and entry["radius"] > 0.0:
		# Near the hub "down" points inward, so grow outward along the node's
		# own radius, anchored by the label's bottom edge.
		var direction: Vector2 = centre.normalized()
		var anchor: Vector2 = centre + direction * (half + LABEL_GAP)
		return Rect2(Vector2(anchor.x - box.x * 0.5, anchor.y - box.y), box)

	return Rect2(Vector2(centre.x - box.x * 0.5, centre.y + half + LABEL_GAP), box)


func _measure_frame() -> Rect2:
	var measured: Rect2 = Rect2()
	var first: bool = true
	for entry in entries.values():
		var half: float = entry["diameter"] * 0.5
		var circle := Rect2(entry["position"] - Vector2(half, half), Vector2(half, half) * 2.0)
		measured = circle if first else measured.merge(circle)
		first = false
		measured = measured.merge(entry["label_rect"])
	return measured.grow(FRAME_PADDING)

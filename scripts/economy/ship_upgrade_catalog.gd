class_name ShipUpgradeCatalog
extends RefCounted

## The ship-wide upgrade trees: seven systems, 89 nodes, loaded from
## res://resources/upgrades/upgrade_tree_data.json.
##
## That file is the design handoff's own `upgrade_data.json`
## (docs/design_handoff_upgrade_tree/) copied into resources/ verbatim apart
## from dropping its `_schema` block. It stays JSON rather than becoming a
## pile of .tres Resources because the handoff treats the whole tree as
## content — "adding an upgrade is a data edit" — and one table keeps that
## true. LAYOUT_SPEC.md §1 documents every field.
##
## Costs are authored as display strings ("8 Copper, 3 Wiring"); parse_costs()
## resolves them against MaterialCatalog/ComponentCatalog by display name, so
## they are spent from the real inventory. Every name currently used in the
## data resolves — see _item_ids().

const DATA_PATH: String = "res://resources/upgrades/upgrade_tree_data.json"
## Reserved id of the tier-0 node, owned from the start and never stored.
const ROOT_ID: String = "root"
## Cost string used by root nodes to mean "already installed".
const NO_COST: String = "—"

static var _categories: Array = []
## category key -> Array of node Dictionaries, in file order.
static var _trees: Dictionary = {}
## category key -> {node id -> node Dictionary}.
static var _by_id: Dictionary = {}
## Lower-cased display name -> material/component id.
static var _item_ids_by_name: Dictionary = {}


## Array of {"key", "label", "hue"} in the order the rail should show them.
static func get_categories() -> Array:
	_load()
	return _categories


static func get_tree(category_key: String) -> Array:
	_load()
	return _trees.get(category_key, [])


static func get_node(category_key: String, node_id: String) -> Dictionary:
	_load()
	return _by_id.get(category_key, {}).get(node_id, {})


static func category_label(category_key: String) -> String:
	for category in get_categories():
		if category["key"] == category_key:
			return category["label"]
	return category_key


static func category_hue(category_key: String) -> float:
	for category in get_categories():
		if category["key"] == category_key:
			return float(category["hue"])
	return UpgradePalette.DEFAULT_HUE


## "8 Copper, 3 Wiring" -> {"copper": 8, "wiring": 3}. An empty dictionary
## means free — either the root's placeholder or an unrecognised name, which
## is reported rather than silently costing nothing.
static func parse_costs(cost_text: String) -> Dictionary:
	_load()
	var costs: Dictionary = {}
	if cost_text.is_empty() or cost_text == NO_COST:
		return costs
	for part in cost_text.split(",", false):
		var piece: String = part.strip_edges()
		var split: int = piece.find(" ")
		if split < 0:
			continue
		var amount: int = piece.substr(0, split).to_int()
		var item_name: String = piece.substr(split + 1).strip_edges().to_lower()
		if not _item_ids_by_name.has(item_name):
			push_warning("ShipUpgradeCatalog: unknown cost item '%s' in '%s'" % [item_name, cost_text])
			continue
		costs[_item_ids_by_name[item_name]] = amount
	return costs


static func _load() -> void:
	if not _categories.is_empty():
		return

	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("ShipUpgradeCatalog: cannot open %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ShipUpgradeCatalog: %s is not a JSON object" % DATA_PATH)
		return

	_categories = parsed.get("categories", [])
	var trees: Dictionary = parsed.get("trees", {})
	for key in trees:
		var nodes: Array = trees[key]
		_trees[key] = nodes
		var lookup: Dictionary = {}
		for node in nodes:
			lookup[node["id"]] = node
		_by_id[key] = lookup

	_item_ids()


static func _item_ids() -> void:
	for material in MaterialCatalog.get_all():
		_item_ids_by_name[material.display_name.to_lower()] = material.id
	for component in ComponentCatalog.get_all():
		_item_ids_by_name[component.display_name.to_lower()] = component.id

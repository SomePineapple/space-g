class_name ShipUpgradeService
extends RefCounted

## The two predicates that are the whole gameplay rule for the ship-wide
## upgrade trees (docs/design_handoff_upgrade_tree/LAYOUT_SPEC.md §1):
##
##   is_unlocked(cat, id)  = id == "root" or saved[cat].has(id)
##   is_available(cat, n)  = not is_unlocked(cat, n.id)
##                           and every parent is unlocked
##
## `parents` is an AND list; arity 2+ *is* the merge mechanic — there is no
## separate flag. Everything else on the screen is presentation.
##
## Stateless: the unlock set lives in GameState (it is player progression, not
## ship-layout data, so it survives rebuilding or losing the ship) and the
## costs come out of the passed Inventory.
##
## Known gap: unlocking spends resources and records the id, but the handoff's
## data authors no stat modifiers, so no node changes ship behaviour yet. The
## effect hook is deliberately absent rather than faked — see
## docs/design_handoff_upgrade_tree/README.md "Fidelity".


static func is_unlocked(category_key: String, node_id: String) -> bool:
	if node_id == ShipUpgradeCatalog.ROOT_ID:
		return true
	return GameState.is_upgrade_unlocked(category_key, node_id)


static func is_available(category_key: String, node: Dictionary) -> bool:
	if is_unlocked(category_key, node["id"]):
		return false
	for parent_id in node["parents"]:
		if not is_unlocked(category_key, parent_id):
			return false
	return true


## Empty string means the node is purchasable right now. Any other string is
## the specific reason it isn't, shown directly in the UI (project convention
## — never a silent no-op).
static func get_rejection_reason(inventory: Inventory, category_key: String, node_id: String) -> String:
	var node: Dictionary = ShipUpgradeCatalog.get_node(category_key, node_id)
	if node.is_empty():
		return "Unknown upgrade"
	if is_unlocked(category_key, node_id):
		return "Already unlocked"

	for parent_id in node["parents"]:
		if not is_unlocked(category_key, parent_id):
			var parent: Dictionary = ShipUpgradeCatalog.get_node(category_key, parent_id)
			return "Requires %s first" % parent.get("label", parent_id)

	var costs: Dictionary = ShipUpgradeCatalog.parse_costs(node["cost"])
	if inventory != null and not costs.is_empty() and not inventory.has_items(costs):
		return "Insufficient resources"
	return ""


static func can_unlock(inventory: Inventory, category_key: String, node_id: String) -> bool:
	return get_rejection_reason(inventory, category_key, node_id) == ""


## Spends the cost (once, atomically — Inventory.spend_items checks
## affordability before touching anything) and records the unlock. Returns
## false without effect if can_unlock() would be false.
static func unlock(inventory: Inventory, category_key: String, node_id: String) -> bool:
	if not can_unlock(inventory, category_key, node_id):
		return false
	var costs: Dictionary = ShipUpgradeCatalog.parse_costs(
		ShipUpgradeCatalog.get_node(category_key, node_id)["cost"])
	if not costs.is_empty():
		inventory.spend_items(costs)
	GameState.unlock_upgrade(category_key, node_id)
	return true


## How many of a category's non-root nodes are unlocked, and how many there
## are — the rail's and the header's "{unlocked}/{total}".
static func progress(category_key: String) -> Vector2i:
	var unlocked: int = 0
	var total: int = 0
	for node in ShipUpgradeCatalog.get_tree(category_key):
		if node["id"] == ShipUpgradeCatalog.ROOT_ID:
			continue
		total += 1
		if is_unlocked(category_key, node["id"]):
			unlocked += 1
	return Vector2i(unlocked, total)

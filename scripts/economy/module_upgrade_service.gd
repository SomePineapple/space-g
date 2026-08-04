class_name ModuleUpgradeService
extends RefCounted

## Stateless per-instance upgrade rules (Phase 8.1). Deliberately not a Node
## (no "UpgradeManager" autoload/child needed) — every call takes the
## ShipLayout/Inventory/ModulePlacement it should act on, so it works
## identically against the ship builder's in-progress working_layout (before
## Apply) and the live player ship's own layout, with no ambiguity about
## which one "the" manager would be attached to.

## Which upgrade tree a module type draws from — its hardpoint_category if it
## has one (so every tier of weapon/missile hardpoint shares one tree), else
## its own module type id (e.g. "engine").
static func tree_key_for(module_type_id: String) -> String:
	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	if module_type == null:
		return module_type_id
	return module_type.hardpoint_category if not module_type.hardpoint_category.is_empty() else module_type_id


static func get_tree_for_placement(placement: ModulePlacement) -> Array[ModuleUpgradeNode]:
	return ModuleUpgradeCatalog.get_for_tree_key(tree_key_for(placement.module_type_id))


## Empty string means unlock_id is currently purchasable on this placement's
## instance. Any other string is the specific reason it isn't, shown directly
## in the UI (project convention — never a silent no-op).
static func get_rejection_reason(layout: ShipLayout, inventory: Inventory, placement: ModulePlacement, upgrade_id: String) -> String:
	var node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(upgrade_id)
	if node == null:
		return "Unknown upgrade"
	if node.tree_key != tree_key_for(placement.module_type_id):
		return "Does not apply to this module"

	var instance: ModuleInstance = placement.ensure_instance()
	if instance.is_upgrade_unlocked(upgrade_id):
		return "Already unlocked"

	for req_id in node.requires:
		if not instance.is_upgrade_unlocked(req_id):
			var req_node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(req_id)
			return "Requires %s first" % (req_node.display_name if req_node != null else req_id)

	for required_type_id in node.requires_ship_modules:
		if not _layout_has_module_type(layout, required_type_id):
			var required_type: ModuleType = ModuleCatalog.get_by_id(required_type_id)
			return "Requires a %s installed on the ship" % (required_type.display_name if required_type != null else required_type_id)

	if inventory != null and not inventory.has_items(node.costs):
		return "Insufficient resources"

	return ""


static func can_unlock(layout: ShipLayout, inventory: Inventory, placement: ModulePlacement, upgrade_id: String) -> bool:
	return get_rejection_reason(layout, inventory, placement, upgrade_id) == ""


## Whether every same-tree prerequisite is met, ignoring cost/cross-module
## gates — used by the UI to tell "next up, just can't afford it yet" apart
## from "not even reachable yet", the "dulled vs. almost hidden" distinction.
static func prerequisites_met(instance: ModuleInstance, node: ModuleUpgradeNode) -> bool:
	for req_id in node.requires:
		if not instance.is_upgrade_unlocked(req_id):
			return false
	return true


## Spends costs (once, atomically — Inventory.spend_items already checks
## affordability before touching anything) and unlocks upgrade_id on the
## placement's own instance. Returns false without effect if can_unlock()
## would be false.
static func unlock(layout: ShipLayout, inventory: Inventory, placement: ModulePlacement, upgrade_id: String) -> bool:
	if not can_unlock(layout, inventory, placement, upgrade_id):
		return false
	var node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(upgrade_id)
	inventory.spend_items(node.costs)
	placement.ensure_instance().unlock_upgrade(upgrade_id)
	return true


static func _layout_has_module_type(layout: ShipLayout, module_type_id: String) -> bool:
	for placement in layout.placements:
		if placement.module_type_id == module_type_id:
			return true
	return false

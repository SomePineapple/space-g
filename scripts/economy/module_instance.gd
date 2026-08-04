class_name ModuleInstance
extends Resource

## One specific built module (Phase 8.1) — distinct from a bare owned-count.
## Lives either in Inventory's owned-but-unplaced pool (see
## Inventory._owned_module_pool) or attached directly to the ModulePlacement
## it's mounted on (see ModulePlacement.instance). Carries its own upgrade
## state so building, placing, removing and re-placing the *same* instance
## never loses what's been unlocked on it — a fresh Build always starts a
## brand new ModuleInstance with nothing unlocked.

@export var instance_id: String = ""
@export var module_type_id: String = ""
## Empty means "generic/no manufacturer" — matches ModulePlacement.manufacturer_id.
@export var manufacturer_id: String = ""
## Set of ModuleUpgradeNode ids unlocked on this specific instance.
@export var unlocked_upgrade_ids: Array[String] = []


func is_upgrade_unlocked(upgrade_id: String) -> bool:
	return unlocked_upgrade_ids.has(upgrade_id)


func unlock_upgrade(upgrade_id: String) -> void:
	if not is_upgrade_unlocked(upgrade_id):
		unlocked_upgrade_ids.append(upgrade_id)


## How many upgrade nodes this instance has unlocked — used by the UI as a
## simple "level" readout, not a separate tracked field.
func get_level() -> int:
	return unlocked_upgrade_ids.size()


## Sum of every unlocked node's modifier for stat_name — additive stacking,
## same convention the old ship-wide upgrade tree and Manufacturer stat
## modifiers both already use.
func get_stat_modifier(stat_name: String) -> float:
	var total: float = 0.0
	for upgrade_id in unlocked_upgrade_ids:
		var node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(upgrade_id)
		if node != null:
			total += node.modifiers.get(stat_name, 0.0)
	return total

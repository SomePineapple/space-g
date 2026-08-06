class_name ModuleUpgradeCatalog
extends RefCounted

## Prototype-only stand-in for loading ModuleUpgradeNode resources from disk —
## same "documented shortcut" shape as ModuleCatalog/MaterialCatalog. Replaces
## the old ship-wide UpgradeCatalog (Phase 8.1: upgrades now attach to one
## specific ModuleInstance, not the whole ship at once).
##
## Deliberately minimal content per the spec's own framing ("implement one
## reusable upgrade system before adding individual upgrade trees") — small
## trees mainly exist to exercise the framework end to end: Engine (with a
## branching pair of nodes converging on a capstone that also needs a
## Reactor installed elsewhere on the ship — see requires_ship_modules), the
## Weapon/Missile linear chains ported over from the old ship-wide system
## with their modifier keys retargeted to per-instance stats, and one-node
## Tractor/Grinder trees proving those two hardpoints are wired the same way.
##
## Which categories are actually wired to *do* something when unlocked
## (see HardpointBank._apply_instance_upgrade_modifiers/get_node_for and
## ShipLayout._instance_stat_delta) — check before adding a new tree_key:
##   - engine, hull, heavy_hull, strut, command_core, reactor_mk1,
##     battery_mk1, storage_mk1: any of ModuleType's own aggregate fields
##     (thrust_contribution, health_contribution, mass_contribution,
##     energy_generation, energy_capacity_contribution,
##     cargo_capacity_contribution) — summed generically by ShipLayout,
##     works automatically, nothing else to wire.
##   - weapon, missile, tractor, grinder: any property that exists on the
##     live spawned node (HardpointGun/HardpointMissileLauncher/
##     HardpointTractorBeam/HardpointGrinder) — applied directly to that one
##     node at spawn time and by Ship.apply_instance_upgrade_effect() on
##     unlock.
##   - radar, scanner: NOT wired yet. Both are "pure capability flag"
##     modules with no per-placement spawned node (see Ship.has_radar/
##     has_scanner) — a modifiers key here would parse fine, cost resources,
##     unlock fine, and then silently do nothing. Needs Scanner/RadarDisplay
##     to pull their own backing placement's instance modifiers live, a
##     different mechanism than the pull-model above, not yet built.

static var _cached_nodes: Array[ModuleUpgradeNode] = []
static var _cached_by_id: Dictionary = {}


static func get_all() -> Array[ModuleUpgradeNode] :
	if not _cached_nodes.is_empty():
		return _cached_nodes

	var nodes: Array[ModuleUpgradeNode] = []

	# --- Engine tree (tree_key = ModuleType id "engine") ---
	nodes.append(_make("engine_lvl_1", "Reinforced Thrusters", "Denser coil windings push more thrust from the same housing.",
		"engine", {MaterialCatalog.IRON: 15, MaterialCatalog.COPPER: 5}, [], [],
		{"thrust_contribution": 100.0}, "I"))
	nodes.append(_make("engine_speed_branch", "Overdrive Coils", "Sacrifices smooth handling for raw acceleration.",
		"engine", {MaterialCatalog.IRON: 25, MaterialCatalog.COPPER: 15, MaterialCatalog.NICKEL: 5}, ["engine_lvl_1"], [],
		{"thrust_contribution": 120.0}, "II-A"))
	nodes.append(_make("engine_mass_branch", "Lightweight Housing", "Shaves mass off the engine casing without weakening the mount.",
		"engine", {MaterialCatalog.TITANIUM: 15, MaterialCatalog.COPPER: 10}, ["engine_lvl_1"], [],
		{"mass_contribution": -0.08}, "II-B"))
	nodes.append(_make("engine_lvl_3", "Overcharged Drive", "The fully tuned drive — needs a Reactor nearby to keep it fed.",
		"engine", {MaterialCatalog.IRON: 40, MaterialCatalog.TITANIUM: 25, MaterialCatalog.NICKEL: 15},
		["engine_speed_branch", "engine_mass_branch"], ["reactor_mk1"],
		{"thrust_contribution": 180.0}, "III"))

	# --- Weapon tree (tree_key = hardpoint_category "weapon", shared by every tier) ---
	nodes.append(_make("weapon_lvl_1", "Focused Emitters", "Tightens the beam for a modest damage bump.",
		"weapon", {MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 10}, [], [],
		{"projectile_damage": 5.0, "fire_rate": 1.0}, "I"))
	nodes.append(_make("weapon_lvl_2", "Overcharged Capacitor", "Faster projectiles, at the cost of a heavier charge cycle.",
		"weapon", {MaterialCatalog.IRON: 20, MaterialCatalog.COPPER: 25, MaterialCatalog.TITANIUM: 5},
		["weapon_lvl_1"], [], {"projectile_damage": 8.0, "projectile_speed": 150.0}, "II"))
	nodes.append(_make("weapon_lvl_3", "Resonance Chamber", "The top tier — needs a Battery installed to sustain the draw.",
		"weapon", {MaterialCatalog.IRON: 30, MaterialCatalog.COPPER: 40, MaterialCatalog.TITANIUM: 30},
		["weapon_lvl_2"], ["battery_mk1"], {"projectile_damage": 12.0, "fire_rate": 1.5}, "III"))

	# --- Missile tree (tree_key = hardpoint_category "missile") ---
	nodes.append(_make("missile_lvl_1", "Guidance Tuning", "Sharper lock-on, slightly quicker ignition.",
		"missile", {MaterialCatalog.IRON: 15, MaterialCatalog.COPPER: 15}, [], [],
		{"projectile_damage": 15.0, "ignition_delay": -0.15}, "I"))
	nodes.append(_make("missile_lvl_2", "Booster Stage", "A hotter second-stage burn.",
		"missile", {MaterialCatalog.IRON: 25, MaterialCatalog.COPPER: 30, MaterialCatalog.NICKEL: 15},
		["missile_lvl_1"], [], {"projectile_damage": 20.0, "projectile_speed": 100.0, "ignition_delay": -0.2}, "II"))
	nodes.append(_make("missile_lvl_3", "Warhead Overcharge", "Maximum yield, fastest possible creep-acceleration.",
		"missile", {MaterialCatalog.IRON: 40, MaterialCatalog.COPPER: 50, MaterialCatalog.NICKEL: 40},
		["missile_lvl_2"], [], {"projectile_damage": 25.0, "creep_acceleration": 30.0, "ignition_delay": -0.25}, "III"))

	# --- Tractor tree (tree_key = hardpoint_category "tractor") — a single
	# node proving HardpointTractorBeam is wired the same way weapons are
	# (see the module-level comment above), not a full tier ladder yet.
	nodes.append(_make("tractor_lvl_1", "Wide-Aperture Coils", "Extends the beam's effective reach.",
		"tractor", {MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 15}, [], [],
		{"max_range": 60.0}, "I"))

	# --- Grinder tree (tree_key = hardpoint_category "grinder") — same
	# one-node proof for HardpointGrinder.
	nodes.append(_make("grinder_lvl_1", "Diamond-Tipped Bit", "Chews through ore noticeably faster.",
		"grinder", {MaterialCatalog.IRON: 12, MaterialCatalog.NICKEL: 8}, [], [],
		{"damage_per_second": 6.0}, "I"))

	_cached_nodes = nodes
	for node in nodes:
		_cached_by_id[node.id] = node
	return _cached_nodes


static func get_by_id(id: String) -> ModuleUpgradeNode:
	get_all()
	return _cached_by_id.get(id)


## Every node belonging to one tree, in catalog order (callers derive
## depth/branching from each node's own `requires`, see ModuleUpgradeService).
static func get_for_tree_key(tree_key: String) -> Array[ModuleUpgradeNode]:
	var result: Array[ModuleUpgradeNode] = []
	for node in get_all():
		if node.tree_key == tree_key:
			result.append(node)
	return result


static func _make(id: String, display_name: String, description: String, tree_key: String, costs: Dictionary,
		requires: Array[String], requires_ship_modules: Array[String], modifiers: Dictionary, glyph: String) -> ModuleUpgradeNode:
	var node := ModuleUpgradeNode.new()
	node.id = id
	node.display_name = display_name
	node.description = description
	node.tree_key = tree_key
	node.costs = costs
	node.requires = requires
	node.requires_ship_modules = requires_ship_modules
	node.modifiers = modifiers
	node.glyph = glyph
	return node

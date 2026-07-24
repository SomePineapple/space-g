class_name UpgradeCatalog
extends RefCounted

static func get_all() -> Array[UpgradeNode]:
	var nodes: Array[UpgradeNode] = []

	nodes.append(_make("thruster_lvl_1", "Reinforced Thrusters I", "thrusters", 20, [], "",
		{"thrust_force": 100.0, "boost_multiplier": 0.1}))
	nodes.append(_make("thruster_lvl_2", "Reinforced Thrusters II", "thrusters", 50, ["thruster_lvl_1"], "",
		{"thrust_force": 150.0, "max_speed": 50.0}))
	nodes.append(_make("thruster_lvl_3", "Reinforced Thrusters III", "thrusters", 100, ["thruster_lvl_2"], "",
		{"thrust_force": 200.0, "boost_multiplier": 0.2, "max_speed": 75.0}))

	nodes.append(_make("laser_lvl_1", "Laser Cannon I", "laser", 20, [], "Weapon",
		{"projectile_damage": 5.0, "fire_rate": 1.0}))
	nodes.append(_make("laser_lvl_2", "Laser Cannon II", "laser", 50, ["laser_lvl_1"], "Weapon",
		{"projectile_damage": 8.0, "projectile_speed": 150.0}))
	nodes.append(_make("laser_lvl_3", "Laser Cannon III", "laser", 100, ["laser_lvl_2"], "Weapon",
		{"projectile_damage": 12.0, "fire_rate": 1.5}))

	nodes.append(_make("missile_lvl_1", "Missile Rack I", "missiles", 30, [], "MissileLauncher",
		{"projectile_damage": 15.0, "fire_rate": 0.3}))
	nodes.append(_make("missile_lvl_2", "Missile Rack II", "missiles", 70, ["missile_lvl_1"], "MissileLauncher",
		{"projectile_damage": 20.0, "projectile_speed": 100.0}))
	nodes.append(_make("missile_lvl_3", "Missile Rack III", "missiles", 130, ["missile_lvl_2"], "MissileLauncher",
		{"projectile_damage": 25.0, "recoil_force": -30.0}))

	return nodes


static func _make(id: String, display_name: String, tree_id: String, cost: int, requires: Array[String],
		target_node_path: String, modifiers: Dictionary) -> UpgradeNode:
	var node := UpgradeNode.new()
	node.id = id
	node.display_name = display_name
	node.tree_id = tree_id
	node.cost = cost
	node.requires = requires
	node.target_node_path = target_node_path
	node.modifiers = modifiers
	return node

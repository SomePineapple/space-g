class_name UpgradeCatalog
extends RefCounted

static func get_all() -> Array[UpgradeNode]:
	var nodes: Array[UpgradeNode] = []

	nodes.append(_make("thruster_lvl_1", "Reinforced Thrusters I", "thrusters",
		{Materials.STEEL_ALLOY: 15, Materials.ELECTRONICS: 5}, [], "",
		{"thrust_force": 100.0, "boost_multiplier": 0.1}))
	nodes.append(_make("thruster_lvl_2", "Reinforced Thrusters II", "thrusters",
		{Materials.STEEL_ALLOY: 35, Materials.ELECTRONICS: 15}, ["thruster_lvl_1"], "",
		{"thrust_force": 150.0, "max_speed": 50.0}))
	nodes.append(_make("thruster_lvl_3", "Reinforced Thrusters III", "thrusters",
		{Materials.STEEL_ALLOY: 60, Materials.ELECTRONICS: 30, Materials.REACTOR_COMPONENTS: 10},
		["thruster_lvl_2"], "", {"thrust_force": 200.0, "boost_multiplier": 0.2, "max_speed": 75.0}))

	nodes.append(_make("laser_lvl_1", "Laser Cannon I", "laser",
		{Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 10}, [], "Weapon",
		{"projectile_damage": 5.0, "fire_rate": 1.0}))
	nodes.append(_make("laser_lvl_2", "Laser Cannon II", "laser",
		{Materials.STEEL_ALLOY: 20, Materials.ELECTRONICS: 25, Materials.REACTOR_COMPONENTS: 5},
		["laser_lvl_1"], "Weapon", {"projectile_damage": 8.0, "projectile_speed": 150.0}))
	nodes.append(_make("laser_lvl_3", "Laser Cannon III", "laser",
		{Materials.STEEL_ALLOY: 30, Materials.ELECTRONICS: 40, Materials.REACTOR_COMPONENTS: 30},
		["laser_lvl_2"], "Weapon", {"projectile_damage": 12.0, "fire_rate": 1.5}))

	nodes.append(_make("missile_lvl_1", "Missile Rack I", "missiles",
		{Materials.STEEL_ALLOY: 15, Materials.ELECTRONICS: 15}, [], "MissileLauncher",
		{"projectile_damage": 15.0, "fire_rate": 0.3, "ignition_delay": -0.15}))
	nodes.append(_make("missile_lvl_2", "Missile Rack II", "missiles",
		{Materials.STEEL_ALLOY: 25, Materials.ELECTRONICS: 30, Materials.REACTOR_COMPONENTS: 15},
		["missile_lvl_1"], "MissileLauncher",
		{"projectile_damage": 20.0, "projectile_speed": 100.0, "ignition_delay": -0.2}))
	nodes.append(_make("missile_lvl_3", "Missile Rack III", "missiles",
		{Materials.STEEL_ALLOY: 40, Materials.ELECTRONICS: 50, Materials.REACTOR_COMPONENTS: 40},
		["missile_lvl_2"], "MissileLauncher",
		{"projectile_damage": 25.0, "creep_acceleration": 30.0, "ignition_delay": -0.25}))

	return nodes


static func _make(id: String, display_name: String, tree_id: String, costs: Dictionary, requires: Array[String],
		target_node_path: String, modifiers: Dictionary) -> UpgradeNode:
	var node := UpgradeNode.new()
	node.id = id
	node.display_name = display_name
	node.tree_id = tree_id
	node.costs = costs
	node.requires = requires
	node.target_node_path = target_node_path
	node.modifiers = modifiers
	return node

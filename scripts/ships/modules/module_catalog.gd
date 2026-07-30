class_name ModuleCatalog
extends RefCounted

## Prototype-only stand-in for loading ModuleType resources from
## res://resources/modules/. Do not let wider systems assume a
## hard-coded catalog once real module content grows.

const CORE_TYPE_ID: String = "command_core"
const WEAPON_HARDPOINT_TYPE_ID: String = "weapon_hardpoint"
const MISSILE_HARDPOINT_TYPE_ID: String = "missile_hardpoint"

const SINGLE_CELL: Array[Vector2i] = [Vector2i.ZERO]
const LINE_2_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const LINE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
## Three mutually-adjacent hexes forming a compact triangle, rather than a
## straight line, for a bulkier-looking tier-3 mount.
const TRIANGLE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]

const HULL_TEXTURE: Texture2D = preload("res://art/ships/hull_v1.png")
const MISSILE_HARDPOINT_TEXTURE: Texture2D = preload("res://art/ships/missile_silo_v1.png")
const COCKPIT_TEXTURE: Texture2D = preload("res://art/ships/cockpit_v1.png")


static func get_all() -> Array[ModuleType]:
	var types: Array[ModuleType] = []
	types.append(_make(CORE_TYPE_ID, "Command Core", Color(0.9, 0.85, 0.2), SINGLE_CELL, 0.4, 40.0, 0.0, COCKPIT_TEXTURE,
		"", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 20}))
	types.append(_make("hull", "Hull", Color(0.5, 0.55, 0.6), SINGLE_CELL, 0.3, 60.0, 0.0, HULL_TEXTURE,
		"", 1, {Materials.STEEL_ALLOY: 5}))
	types.append(_make("engine", "Engine", Color(0.3, 0.7, 1.0), SINGLE_CELL, 0.25, 20.0, 500.0, null,
		"", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 5}))
	types.append(_make("heavy_hull", "Heavy Hull", Color(0.45, 0.3, 0.55), LINE_3_CELLS, 0.9, 150.0, 0.0, null,
		"", 1, {Materials.STEEL_ALLOY: 20}))

	types.append(_make(WEAPON_HARDPOINT_TYPE_ID, "Weapon Hardpoint I", Color(0.9, 0.35, 0.3), SINGLE_CELL,
		0.2, 15.0, 0.0, null, "weapon", 1, {Materials.STEEL_ALLOY: 8, Materials.ELECTRONICS: 4}))
	types.append(_make("weapon_hardpoint_t2", "Weapon Hardpoint II", Color(0.8, 0.25, 0.2), LINE_2_CELLS,
		0.5, 35.0, 0.0, null, "weapon", 2, {Materials.STEEL_ALLOY: 18, Materials.ELECTRONICS: 10}))
	types.append(_make("weapon_hardpoint_t3", "Weapon Hardpoint III", Color(0.65, 0.15, 0.1), TRIANGLE_3_CELLS,
		0.9, 60.0, 0.0, null, "weapon", 3,
		{Materials.STEEL_ALLOY: 32, Materials.ELECTRONICS: 20, Materials.REACTOR_COMPONENTS: 5}))

	types.append(_make(MISSILE_HARDPOINT_TYPE_ID, "Missile Rack I", Color(1.0, 0.6, 0.15), SINGLE_CELL,
		0.3, 20.0, 0.0, MISSILE_HARDPOINT_TEXTURE, "missile", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 8}))
	types.append(_make("missile_hardpoint_t2", "Missile Rack II", Color(0.9, 0.5, 0.1), LINE_2_CELLS,
		0.7, 45.0, 0.0, null, "missile", 2, {Materials.STEEL_ALLOY: 22, Materials.ELECTRONICS: 16}))
	types.append(_make("missile_hardpoint_t3", "Missile Rack III", Color(0.75, 0.4, 0.05), LINE_3_CELLS,
		1.2, 75.0, 0.0, null, "missile", 3,
		{Materials.STEEL_ALLOY: 38, Materials.ELECTRONICS: 26, Materials.REACTOR_COMPONENTS: 10}))

	types.append(_make("reactor_mk1", "Reactor Mk1", Color(1.0, 0.75, 0.2), SINGLE_CELL,
		0.35, 25.0, 0.0, null, "", 1,
		{Materials.STEEL_ALLOY: 15, Materials.ELECTRONICS: 15, Materials.REACTOR_COMPONENTS: 10},
		15.0, 0.0))
	types.append(_make("battery_mk1", "Battery Mk1", Color(0.85, 0.75, 0.95), SINGLE_CELL,
		0.3, 20.0, 0.0, null, "", 1,
		{Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 20},
		0.0, 80.0))

	return types


static func get_by_id(id: String) -> ModuleType:
	for type in get_all():
		if type.id == id:
			return type
	return null


static func _make(id: String, display_name: String, color: Color, footprint_cells: Array[Vector2i],
		mass_contribution: float = 0.0, health_contribution: float = 0.0, thrust_contribution: float = 0.0,
		hex_texture: Texture2D = null, hardpoint_category: String = "", tier: int = 1,
		build_costs: Dictionary = {}, energy_generation: float = 0.0,
		energy_capacity_contribution: float = 0.0) -> ModuleType:
	var type := ModuleType.new()
	type.id = id
	type.display_name = display_name
	type.color = color
	type.footprint_cells = footprint_cells
	type.mass_contribution = mass_contribution
	type.health_contribution = health_contribution
	type.thrust_contribution = thrust_contribution
	type.hex_texture = hex_texture
	type.hardpoint_category = hardpoint_category
	type.tier = tier
	type.build_costs = build_costs
	type.energy_generation = energy_generation
	type.energy_capacity_contribution = energy_capacity_contribution
	return type

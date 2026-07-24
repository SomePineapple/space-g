class_name ModuleCatalog
extends RefCounted

## Prototype-only stand-in for loading ModuleType resources from
## res://resources/modules/. Do not let wider systems assume a
## hard-coded catalog once real module content grows.

const CORE_TYPE_ID: String = "command_core"

const SINGLE_CELL: Array[Vector2i] = [Vector2i.ZERO]


static func get_all() -> Array[ModuleType]:
	var types: Array[ModuleType] = []
	types.append(_make(CORE_TYPE_ID, "Command Core", Color(0.9, 0.85, 0.2), SINGLE_CELL, 0.4, 40.0, 0.0))
	types.append(_make("hull", "Hull", Color(0.5, 0.55, 0.6), SINGLE_CELL, 0.3, 60.0, 0.0))
	types.append(_make("engine", "Engine", Color(0.3, 0.7, 1.0), SINGLE_CELL, 0.25, 20.0, 500.0))
	types.append(_make("weapon_hardpoint", "Weapon Hardpoint", Color(0.9, 0.35, 0.3), SINGLE_CELL, 0.2, 15.0, 0.0))
	types.append(_make("heavy_hull", "Heavy Hull", Color(0.45, 0.3, 0.55),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 0.9, 150.0, 0.0))
	return types


static func get_by_id(id: String) -> ModuleType:
	for type in get_all():
		if type.id == id:
			return type
	return null


static func _make(id: String, display_name: String, color: Color, footprint_cells: Array[Vector2i],
		mass_contribution: float = 0.0, health_contribution: float = 0.0, thrust_contribution: float = 0.0) -> ModuleType:
	var type := ModuleType.new()
	type.id = id
	type.display_name = display_name
	type.color = color
	type.footprint_cells = footprint_cells
	type.mass_contribution = mass_contribution
	type.health_contribution = health_contribution
	type.thrust_contribution = thrust_contribution
	return type
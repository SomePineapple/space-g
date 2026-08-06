class_name ComponentCatalog
extends RefCounted

## Prototype-only stand-in for loading ComponentType resources from
## res://resources/components/ — same documented shortcut as MaterialCatalog/
## ModuleCatalog. Phase 5.1 crafting: six intermediate components, each
## produced by exactly one CraftingCatalog recipe from raw materials.
##
## Adding a new component is a two-line change here plus one new recipe in
## CraftingCatalog — nothing else hardcodes the component list, callers key
## off plain component_id Strings or iterate ALL_IDS/get_all().

const METAL_SHEETS: String = "metal_sheets"
const WIRING: String = "wiring"
const CIRCUIT_BOARD: String = "circuit_board"
const REINFORCED_STEEL: String = "reinforced_steel"
const MOTOR: String = "motor"
const CANISTER: String = "canister"

const ALL_IDS: Array[String] = [METAL_SHEETS, WIRING, CIRCUIT_BOARD, REINFORCED_STEEL, MOTOR, CANISTER]

## Phase 5.3 combat/wreck salvage split — "rare" components (require two raw
## materials to craft, see CraftingCatalog) drop less often than "common"
## ones (single raw material) when a kill/wreck rolls a component instead of
## plain material. Purely a drop-table grouping, not a new data field on
## ComponentType — nothing about a component's own definition marks it rare.
const COMMON_IDS: Array[String] = [METAL_SHEETS, WIRING, CANISTER]
const RARE_IDS: Array[String] = [CIRCUIT_BOARD, REINFORCED_STEEL, MOTOR]

static var _cached_types: Array[ComponentType] = []
## id -> ComponentType — see MaterialCatalog._index.
static var _index: Dictionary = {}


static func get_all() -> Array[ComponentType]:
	if not _cached_types.is_empty():
		return _cached_types

	var types: Array[ComponentType] = []
	types.append(_make(METAL_SHEETS, "Metal Sheets", Color(0.75, 0.76, 0.78)))
	types.append(_make(WIRING, "Wiring", Color(0.9, 0.55, 0.15)))
	types.append(_make(CIRCUIT_BOARD, "Circuit Board", Color(0.2, 0.75, 0.35)))
	types.append(_make(REINFORCED_STEEL, "Reinforced Steel", Color(0.4, 0.42, 0.48)))
	types.append(_make(MOTOR, "Motor", Color(0.8, 0.65, 0.2)))
	types.append(_make(CANISTER, "Canister", Color(0.6, 0.7, 0.65)))

	_cached_types = types
	for type in types:
		_index[type.id] = type
	return types


static func get_by_id(component_id: String) -> ComponentType:
	get_all()
	return _index.get(component_id)


static func display_name(component_id: String) -> String:
	var type: ComponentType = get_by_id(component_id)
	return type.display_name if type != null else component_id


static func color(component_id: String) -> Color:
	var type: ComponentType = get_by_id(component_id)
	return type.color if type != null else Color.WHITE


static func _make(id: String, type_display_name: String, type_color: Color, type_icon: Texture2D = null) -> ComponentType:
	var type := ComponentType.new()
	type.id = id
	type.display_name = type_display_name
	type.color = type_color
	type.icon = type_icon
	return type

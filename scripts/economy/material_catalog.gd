class_name MaterialCatalog
extends RefCounted

## Prototype-only stand-in for loading MaterialType resources from
## res://resources/materials/ — same documented shortcut as ModuleCatalog.
## Phase 4.2 raw materials: Iron/Copper/Nickel/Titanium. Phase 5.1 added
## Glass (Circuit Board crafting needs a transparent input) — do not add
## Silver/Gold or anything else until a system actually needs it.
##
## Adding a fifth material is a two-line change: one id const + one entry in
## ALL_IDS + one _make() call in get_all() below. Nothing else in the game
## (Inventory, Salvage, ship-builder costs, Trade/Cargo/HUD panels) hardcodes
## the material list — they all key off plain material_id Strings or iterate
## ALL_IDS/get_all().

const IRON: String = "iron"
const COPPER: String = "copper"
const NICKEL: String = "nickel"
const TITANIUM: String = "titanium"
## No asteroid variant claims Glass as a primary_material (see Asteroid.
## VARIANT_PRIMARY_MATERIAL) — it's deliberately only ever the uniform-random
## "otherwise" pick every variant already rolls among ALL_IDS, so it stays a
## rarer, non-guaranteed find without touching asteroid.gd at all.
const GLASS: String = "glass"

## Ordered id list — Trade/Cargo/HUD panels and combat salvage's uniform
## material roll (see Ship._roll_combat_material) iterate this instead of a
## separate hardcoded array.
const ALL_IDS: Array[String] = [IRON, COPPER, NICKEL, TITANIUM, GLASS]

static var _cached_types: Array[MaterialType] = []


static func get_all() -> Array[MaterialType]:
	if not _cached_types.is_empty():
		return _cached_types

	var types: Array[MaterialType] = []
	# yield_multiplier scales down per-drop amount as sell/buy price climbs, so
	# rarer materials feel scarcer to collect, not just more valuable to sell.
	types.append(_make(IRON, "Iron", Color(0.72, 0.7, 0.68), 2, 4, 1.0))
	types.append(_make(COPPER, "Copper", Color(0.85, 0.45, 0.2), 4, 8, 0.85))
	types.append(_make(NICKEL, "Nickel", Color(0.75, 0.8, 0.78), 5, 10, 0.65))
	types.append(_make(TITANIUM, "Titanium", Color(0.65, 0.6, 0.8), 9, 18, 0.45))
	types.append(_make(GLASS, "Glass", Color(0.75, 0.9, 0.95), 6, 12, 0.6))

	_cached_types = types
	return types


static func get_by_id(material_id: String) -> MaterialType:
	for type in get_all():
		if type.id == material_id:
			return type
	return null


static func display_name(material_id: String) -> String:
	var type: MaterialType = get_by_id(material_id)
	return type.display_name if type != null else material_id


static func color(material_id: String) -> Color:
	var type: MaterialType = get_by_id(material_id)
	return type.color if type != null else Color.WHITE


static func icon(material_id: String) -> Texture2D:
	var type: MaterialType = get_by_id(material_id)
	return type.icon if type != null else null


static func sell_price(material_id: String) -> int:
	var type: MaterialType = get_by_id(material_id)
	return type.sell_price if type != null else 0


static func buy_price(material_id: String) -> int:
	var type: MaterialType = get_by_id(material_id)
	return type.buy_price if type != null else 0


static func yield_multiplier(material_id: String) -> float:
	var type: MaterialType = get_by_id(material_id)
	return type.yield_multiplier if type != null else 1.0


static func _make(id: String, type_display_name: String, type_color: Color, type_sell_price: int, type_buy_price: int,
		type_yield_multiplier: float = 1.0, type_icon: Texture2D = null) -> MaterialType:
	var type := MaterialType.new()
	type.id = id
	type.display_name = type_display_name
	type.color = type_color
	type.sell_price = type_sell_price
	type.buy_price = type_buy_price
	type.yield_multiplier = type_yield_multiplier
	type.icon = type_icon
	return type

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
## id -> MaterialType. Same reason as ModuleCatalog._index: every
## display_name/color/price/yield helper below funnels through get_by_id(),
## and the UI panels call those once per material per refresh.
static var _index: Dictionary = {}


static func get_all() -> Array[MaterialType]:
	if not _cached_types.is_empty():
		return _cached_types

	var types: Array[MaterialType] = []
	# Prices, volatilities, categories and colours are the trade-market
	# handoff's own numbers for these five materials
	# (docs/design_handoff_trade_market/README.md "Per-material data" and
	# "Design tokens").
	#
	# yield_multiplier scales down per-drop amount as price climbs, so rarer,
	# pricier materials feel scarcer to collect, not just better to sell.
	types.append(_make(IRON, "Iron", Color(0.6235, 0.6902, 0.7412), 40, 3.0, "Ore", 1.0))
	types.append(_make(COPPER, "Copper", Color(0.8784, 0.5451, 0.2980), 80, 6.0, "Ore", 0.85))
	types.append(_make(NICKEL, "Nickel", Color(0.6588, 0.7529, 0.7843), 100, 7.0, "Ore", 0.65))
	types.append(_make(TITANIUM, "Titanium", Color(0.7961, 0.8392, 0.8784), 180, 13.0, "Ore", 0.45))
	types.append(_make(GLASS, "Glass", Color(0.5608, 0.9137, 0.9490), 120, 9.0, "Refined", 0.6))

	_cached_types = types
	for type in types:
		_index[type.id] = type
	return types


static func get_by_id(material_id: String) -> MaterialType:
	get_all()
	return _index.get(material_id)


static func display_name(material_id: String) -> String:
	var type: MaterialType = get_by_id(material_id)
	return type.display_name if type != null else material_id


static func color(material_id: String) -> Color:
	var type: MaterialType = get_by_id(material_id)
	return type.color if type != null else Color.WHITE


static func icon(material_id: String) -> Texture2D:
	var type: MaterialType = get_by_id(material_id)
	return type.icon if type != null else null


## The market's anchor price. The live price the player actually pays comes
## from MarketService, which drifts around this — nothing should quote this
## number to the player directly.
static func base_price(material_id: String) -> int:
	var type: MaterialType = get_by_id(material_id)
	return type.base_price if type != null else 0


static func volatility(material_id: String) -> float:
	var type: MaterialType = get_by_id(material_id)
	return type.volatility if type != null else 0.0


static func category(material_id: String) -> String:
	var type: MaterialType = get_by_id(material_id)
	return type.category if type != null else ""


## Distinct categories in catalog order — the market's tab strip is built from
## this, so adding a category is a _make() call and nothing else.
static func categories() -> Array[String]:
	var result: Array[String] = []
	for type in get_all():
		if not type.category.is_empty() and not result.has(type.category):
			result.append(type.category)
	return result


static func yield_multiplier(material_id: String) -> float:
	var type: MaterialType = get_by_id(material_id)
	return type.yield_multiplier if type != null else 1.0


static func _make(id: String, type_display_name: String, type_color: Color, type_base_price: int,
		type_volatility: float, type_category: String, type_yield_multiplier: float = 1.0,
		type_icon: Texture2D = null) -> MaterialType:
	var type := MaterialType.new()
	type.id = id
	type.display_name = type_display_name
	type.color = type_color
	type.base_price = type_base_price
	type.volatility = type_volatility
	type.category = type_category
	type.yield_multiplier = type_yield_multiplier
	type.icon = type_icon
	return type

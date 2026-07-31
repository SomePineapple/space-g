class_name Materials
extends RefCounted

## Material ids are plain Strings so Inventory/Salvage/UpgradeNode can key
## Dictionaries by them without depending on this class beyond display
## metadata. Prototype-only: only the three materials Version 0.2 calls for
## exist so far.

const STEEL_ALLOY: String = "steel_alloy"
const ELECTRONICS: String = "electronics"
const REACTOR_COMPONENTS: String = "reactor_components"

## sell_price/buy_price are Version 0.6's trading numbers (Credits per unit).
## buy_price > sell_price on every material so round-tripping (sell then buy
## back) always loses Credits, matching a normal trader spread.
const DISPLAY_DATA: Dictionary = {
	STEEL_ALLOY: {"display_name": "Steel Alloy", "color": Color(0.75, 0.78, 0.8), "sell_price": 2, "buy_price": 4},
	ELECTRONICS: {"display_name": "Electronics", "color": Color(0.3, 0.6, 1.0), "sell_price": 4, "buy_price": 8},
	REACTOR_COMPONENTS: {"display_name": "Reactor Components", "color": Color(0.3, 1.0, 0.5), "sell_price": 8, "buy_price": 16},
}


static func display_name(material_id: String) -> String:
	return DISPLAY_DATA.get(material_id, {}).get("display_name", material_id)


static func color(material_id: String) -> Color:
	return DISPLAY_DATA.get(material_id, {}).get("color", Color.WHITE)


static func sell_price(material_id: String) -> int:
	return DISPLAY_DATA.get(material_id, {}).get("sell_price", 0)


static func buy_price(material_id: String) -> int:
	return DISPLAY_DATA.get(material_id, {}).get("buy_price", 0)

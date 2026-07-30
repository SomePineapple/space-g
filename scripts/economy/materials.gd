class_name Materials
extends RefCounted

## Material ids are plain Strings so Inventory/Salvage/UpgradeNode can key
## Dictionaries by them without depending on this class beyond display
## metadata. Prototype-only: only the three materials Version 0.2 calls for
## exist so far.

const STEEL_ALLOY: String = "steel_alloy"
const ELECTRONICS: String = "electronics"
const REACTOR_COMPONENTS: String = "reactor_components"

const DISPLAY_DATA: Dictionary = {
	STEEL_ALLOY: {"display_name": "Steel Alloy", "color": Color(0.75, 0.78, 0.8)},
	ELECTRONICS: {"display_name": "Electronics", "color": Color(0.3, 0.6, 1.0)},
	REACTOR_COMPONENTS: {"display_name": "Reactor Components", "color": Color(0.3, 1.0, 0.5)},
}


static func display_name(material_id: String) -> String:
	return DISPLAY_DATA.get(material_id, {}).get("display_name", material_id)


static func color(material_id: String) -> Color:
	return DISPLAY_DATA.get(material_id, {}).get("color", Color.WHITE)

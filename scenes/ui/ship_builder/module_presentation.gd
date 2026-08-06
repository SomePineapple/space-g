class_name ModulePresentation
extends RefCounted

## How a ModuleType is presented in the ship-builder module list: which
## category heading it groups under, its icon gradient, and the 2-letter
## glyph used when no hex art exists for it.
##
## The categories are derived from the ModuleType's own fields rather than
## stored on it — the builder UI is the only thing that needs this grouping,
## so it isn't worth adding a field every ModuleType has to fill in. If a
## second system ever needs categories, promote it to ModuleType then.

const CORE: String = "Core"
const STRUCTURE: String = "Structure"
const PROPULSION: String = "Propulsion"
const WEAPONS: String = "Weapons"
const UTILITY: String = "Utility"
const STORAGE: String = "Storage"

## Display order of the category headings (handoff README "List grouped by
## category, in order").
const CATEGORY_ORDER: Array[String] = [CORE, STRUCTURE, PROPULSION, WEAPONS, UTILITY, STORAGE]

## Filter tabs above the list. "All"/"Owned" are not categories.
const TAB_ALL: String = "All"
const TAB_OWNED: String = "Owned"
const FILTER_TABS: Array[String] = [TAB_ALL, STRUCTURE, WEAPONS, UTILITY, TAB_OWNED]

const STRUCTURE_TYPE_IDS: Array[String] = ["hull", "heavy_hull", "strut"]

## Icon gradient (top, bottom) and glyph colour per category, taken from the
## handoff's per-module gradients — which follow the category, not the
## individual module.
const CATEGORY_GRADIENTS: Dictionary = {
	CORE: [Color(0.1647, 0.3725, 0.4196), Color(0.0902, 0.1961, 0.2196)],  # 2a5f6b -> 173238
	STRUCTURE: [Color(0.2902, 0.3412, 0.3882), Color(0.1686, 0.2078, 0.2588)],  # 4a5763 -> 2b3542
	PROPULSION: [Color(0.6392, 0.5098, 0.1843), Color(0.3608, 0.2784, 0.0941)],  # a3822f -> 5c4718
	WEAPONS: [Color(0.6392, 0.3529, 0.2275), Color(0.3608, 0.1804, 0.0941)],  # a35a3a -> 5c2e18
	UTILITY: [Color(0.2275, 0.4196, 0.4784), Color(0.1098, 0.2157, 0.2588)],  # 3a6b7a -> 1c3742
	STORAGE: [Color(0.1647, 0.5608, 0.6392), Color(0.0902, 0.2275, 0.2588)],  # 2a8fa3 -> 173a42
}

const CATEGORY_GLYPH_COLORS: Dictionary = {
	CORE: Color(0.5608, 0.9137, 0.9490),  # 8fe9f2
	STRUCTURE: Color(0.7804, 0.8157, 0.8471),  # c7d0d8
	PROPULSION: Color(1.0, 0.9020, 0.6588),  # ffe6a8
	WEAPONS: Color(1.0, 0.7961, 0.6902),  # ffcbb0
	UTILITY: Color(0.6588, 0.8510, 0.9098),  # a8d9e8
	STORAGE: Color(0.5608, 0.9137, 0.9490),  # 8fe9f2
}

## Hand-picked where initials would collide or read badly ("Mining Grinder"
## and "Missile Rack" both start "MI"). Anything not listed falls back to
## _derive_glyph().
const GLYPH_OVERRIDES: Dictionary = {
	"command_core": "CC",
	"hull": "HL",
	"heavy_hull": "HH",
	"strut": "ST",
	"engine": "EN",
	"storage_mk1": "CB",
	"reactor_mk1": "RC",
	"battery_mk1": "BT",
	"mining_grinder_hardpoint": "GR",
	"missile_hardpoint": "M1",
	"missile_hardpoint_t2": "M2",
	"missile_hardpoint_t3": "M3",
	"weapon_hardpoint": "W1",
	"weapon_hardpoint_t2": "W2",
	"weapon_hardpoint_t3": "W3",
	"railgun_hardpoint": "RG",
	"phase_lance_hardpoint": "PL",
	"tractor_beam_hardpoint": "TB",
	"radar_hardpoint": "RD",
	"scanner_hardpoint": "SC",
}


static func category(module_type: ModuleType) -> String:
	if module_type.id == ModuleCatalog.CORE_TYPE_ID:
		return CORE
	if module_type.id in STRUCTURE_TYPE_IDS:
		return STRUCTURE
	if module_type.thrust_contribution > 0.0:
		return PROPULSION
	if module_type.hardpoint_category in ["weapon", "missile"]:
		return WEAPONS
	if module_type.cargo_capacity_contribution > 0.0:
		return STORAGE
	return UTILITY


static func gradient(module_type: ModuleType) -> Array:
	return CATEGORY_GRADIENTS[category(module_type)]


static func glyph_color(module_type: ModuleType) -> Color:
	return CATEGORY_GLYPH_COLORS[category(module_type)]


static func glyph(module_type: ModuleType) -> String:
	if GLYPH_OVERRIDES.has(module_type.id):
		return GLYPH_OVERRIDES[module_type.id]
	return _derive_glyph(module_type.display_name)


## Initials of the first two words, or the first two letters of a one-word
## name.
static func _derive_glyph(display_name: String) -> String:
	var words: PackedStringArray = display_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	if display_name.length() >= 2:
		return display_name.substr(0, 2).to_upper()
	return display_name.to_upper()

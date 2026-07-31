class_name ManufacturerCatalog
extends RefCounted

## Prototype-only stand-in for loading Manufacturer resources from
## res://resources/manufacturers/, same shortcut ModuleCatalog documents for
## module types. Three manufacturers exist per Roadmap v.2-v.9 Version 0.5:
## Atlas Heavy Industries (powerful/heavy/high recoil), Nova Precision
## (accurate/efficient/lightweight), Black Market Foundry
## (unstable/experimental/dangerous).

const ATLAS_HEAVY_ID: String = "atlas_heavy"
const NOVA_PRECISION_ID: String = "nova_precision"
const BLACK_MARKET_FOUNDRY_ID: String = "black_market_foundry"

static var _cached: Array[Manufacturer] = []


static func get_all() -> Array[Manufacturer]:
	if not _cached.is_empty():
		return _cached

	var atlas := Manufacturer.new()
	atlas.id = ATLAS_HEAVY_ID
	atlas.display_name = "Atlas Heavy Industries"
	atlas.flavor_text = "Brute-force engineering: more power, more weight, more kick."
	atlas.stat_modifiers = {
		"projectile_damage": 6.0,
		"recoil_force": 14.0,
		"energy_cost": 2.0,
		"mass_contribution": 0.15,
		"energy_generation": 5.0,
		"energy_capacity_contribution": 15.0,
	}
	_cached.append(atlas)

	var nova := Manufacturer.new()
	nova.id = NOVA_PRECISION_ID
	nova.display_name = "Nova Precision"
	nova.flavor_text = "Refined engineering: lighter, more efficient, easier to land a hit with."
	nova.stat_modifiers = {
		"projectile_damage": -2.0,
		"energy_cost": -1.5,
		"projectile_speed": 150.0,
		"mass_contribution": -0.1,
		"energy_generation": 2.0,
	}
	_cached.append(nova)

	var black_market := Manufacturer.new()
	black_market.id = BLACK_MARKET_FOUNDRY_ID
	black_market.display_name = "Black Market Foundry"
	black_market.flavor_text = "Backstreet engineering: cheap and powerful, but it can turn on you."
	black_market.stat_modifiers = {
		"projectile_damage": 9.0,
		"energy_cost": -2.0,
		"energy_generation": 6.0,
		"energy_capacity_contribution": 10.0,
	}
	black_market.malfunction_chance = 0.06
	black_market.malfunction_self_damage = 8.0
	_cached.append(black_market)

	return _cached


static func get_by_id(id: String) -> Manufacturer:
	if id.is_empty():
		return null
	for manufacturer in get_all():
		if manufacturer.id == id:
			return manufacturer
	return null

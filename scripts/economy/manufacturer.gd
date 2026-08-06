class_name Manufacturer
extends Resource

## A manufacturer is an engineering philosophy that can flavor a specific
## module instance, independent of faction — a Corporate ship and a Pirate
## ship can both mount an Atlas Heavy reactor. Distinct from
## ModuleType.faction_hex_textures (which is purely visual/faction-owned).

@export var id: String = ""
@export var display_name: String = ""
@export var flavor_text: String = ""

## property_name -> additive delta (see HardpointBank.apply_modifiers): the
## target node's existing value for that property is read and the delta added
## to it, once, at spawn time. Keys are HardpointGun/HardpointMissileLauncher
## property names (applied when the placement is a weapon/missile hardpoint)
## or ModuleType field names (applied to Reactor/Battery totals inside
## ShipLayout, which have no live node to mutate directly).
@export var stat_modifiers: Dictionary = {}

## Black Market Foundry only, for now: chance per shot the weapon backfires
## instead of firing, damaging its own hull module (see
## HardpointGun._apply_malfunction_damage). Zero means "never" — most
## manufacturers have no malfunction risk at all.
@export var malfunction_chance: float = 0.0
@export var malfunction_self_damage: float = 0.0

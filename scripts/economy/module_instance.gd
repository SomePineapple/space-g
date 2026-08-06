class_name ModuleInstance
extends Resource

## One specific built module — distinct from a bare owned-count. Lives either
## in Inventory's owned-but-unplaced pool (see Inventory._owned_module_pool) or
## attached directly to the ModulePlacement it's mounted on (see
## ModulePlacement.instance), so building, placing, removing and re-placing
## keeps identifying the *same* physical module rather than an interchangeable
## one of its type.
##
## This used to carry per-instance upgrade state as well. Upgrades are now
## ship-wide and stored by id in GameState (see ShipUpgradeService), so the
## instance is identity and provenance only.

@export var instance_id: String = ""
@export var module_type_id: String = ""
## Empty means "generic/no manufacturer" — matches ModulePlacement.manufacturer_id.
@export var manufacturer_id: String = ""

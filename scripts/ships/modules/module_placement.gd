class_name ModulePlacement
extends Resource

@export var placement_id: String = ""
@export var module_type_id: String = ""
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var rotation_steps: int = 0
## Empty means "generic/no manufacturer" — see Manufacturer/ManufacturerCatalog.
## Only meaningful for weapon/missile hardpoints and Reactor/Battery; other
## module types simply never get one set.
@export var manufacturer_id: String = ""
## Which reactor powers this module: the `placement_id` of the circuit source it
## belongs to. Empty means unassigned, which for anything that draws power means
## dead.
##
## **A circuit is a logical grouping, not a physical one.** There is deliberately
## no relationship between this and where the module sits on the hull — no
## adjacency, no routing, no path back to anything. The player picks it in the
## builder, and the ship's power topology is therefore something they authored
## rather than something the hull's shape decided for them.
##
## A circuit source (a reactor, or the Command Core) carries its own
## `placement_id` here. The set of circuits that exist is derived from those
## placements and membership is derived from this field, so there is no separate
## circuit list that can fall out of sync with the layout.
@export var circuit_id: String = ""
## The specific built ModuleInstance mounted here — identifies this exact
## module, distinct from every other instance of the same module_type_id, so
## removing and re-placing it returns the same physical module to the pool.
## Null for a placement that has never needed one (e.g. the starter ship layout
## loaded straight from a .tres) — see ensure_instance().
@export var instance: ModuleInstance = null


## Lazily creates an instance if this placement doesn't have one yet, so a
## layout authored without instances still round-trips through the owned-module
## pool without every call site null-checking first.
func ensure_instance() -> ModuleInstance:
	if instance == null:
		instance = ModuleInstance.create(module_type_id, manufacturer_id)
	return instance
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
		instance = ModuleInstance.new()
		instance.instance_id = GameRng.next_id("mi")
		instance.module_type_id = module_type_id
		instance.manufacturer_id = manufacturer_id
	return instance
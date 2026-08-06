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
## The specific built ModuleInstance mounted here (Phase 8.1) — carries this
## exact module's upgrade state, distinct from every other instance of the
## same module_type_id. Null for a placement that predates Phase 8.1 (e.g.
## the starter ship layout loaded straight from a .tres) or that's never had
## its upgrade tree opened yet — see ensure_instance().
@export var instance: ModuleInstance = null


## Lazily creates a blank (no upgrades unlocked) instance if this placement
## doesn't have one yet, so a pre-Phase-8.1 or freshly-placed module is always
## upgrade-capable without needing every call site to null-check first.
func ensure_instance() -> ModuleInstance:
	if instance == null:
		instance = ModuleInstance.new()
		instance.instance_id = GameRng.next_id("mi")
		instance.module_type_id = module_type_id
		instance.manufacturer_id = manufacturer_id
	return instance
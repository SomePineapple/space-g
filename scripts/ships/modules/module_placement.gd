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
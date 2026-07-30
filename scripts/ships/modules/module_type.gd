class_name ModuleType
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var hex_texture: Texture2D = null
@export var footprint_cells: Array[Vector2i] = [Vector2i.ZERO]
@export var mass_contribution: float = 0.0
@export var health_contribution: float = 0.0
@export var thrust_contribution: float = 0.0

## "weapon" or "missile" for hardpoint modules (any tier), "" otherwise.
## Lets ShipLayout find all hardpoints of a kind without hard-coding every
## tier's module id.
@export var hardpoint_category: String = ""
## Hardpoint size tier (1-3). Scales the spawned gun/launcher's stats and
## visual size; ignored for non-hardpoint modules.
@export var tier: int = 1
## Material id -> amount required to place this module in the ship builder.
@export var build_costs: Dictionary = {}

## Energy/second this module adds to the ship's regeneration rate (reactors).
@export var energy_generation: float = 0.0
## Energy capacity this module adds to the ship's energy pool (batteries).
@export var energy_capacity_contribution: float = 0.0

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

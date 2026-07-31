class_name CapturedTechPart
extends Node2D

## A severed module that stayed intact enough to be worth recovering (see
## Ship._roll_capturable). Drifts like ordinary ShipDebris at first, but
## persists far longer and can be reeled in by WinchBeam instead of just
## fading away — see begin_reel_in(). Stores which module/faction it came
## from for a future reverse-engineering/research system to consume.

signal captured

@export var lifetime: float = 45.0
@export var fade_duration: float = 2.0

const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)

var module_type_id: String = ""
var faction_id: String = ""

var _cells: Array[Vector2i] = []
var _colors: Array[Color] = []
var _textures: Array[Texture2D] = []
var _cell_size: float = 24.0
var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _age: float = 0.0
var _being_reeled_in: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_to_group("capturable_tech")


func setup(cells: Array[Vector2i], colors: Array[Color], textures: Array[Texture2D],
		cell_size: float, drift_velocity: Vector2, spin: float,
		source_module_type_id: String, source_faction_id: String) -> void:
	_cells = cells
	_colors = colors
	_textures = textures
	_cell_size = cell_size
	_velocity = drift_velocity
	_spin = spin
	module_type_id = source_module_type_id
	faction_id = source_faction_id
	queue_redraw()


## Called by WinchBeam once it locks on. Stops the part drifting/spinning
## and stops its own lifetime countdown so the winch has full control of its
## motion until _complete_reel_in() collects it.
func begin_reel_in() -> void:
	_being_reeled_in = true
	_velocity = Vector2.ZERO
	_spin = 0.0


func collect() -> void:
	captured.emit()
	queue_free()


func _process(delta: float) -> void:
	if _being_reeled_in:
		return

	_age += delta
	position += _velocity * delta
	rotation += _spin * delta

	if _age >= lifetime - fade_duration:
		modulate.a = clampf((lifetime - _age) / fade_duration, 0.0, 1.0)
	if _age >= lifetime:
		queue_free()


func _draw() -> void:
	for i in _cells.size():
		var corners: PackedVector2Array = HexUtils.hex_corners(HexUtils.axial_to_pixel(_cells[i], _cell_size), _cell_size)
		var texture: Texture2D = _textures[i] if i < _textures.size() else null
		if texture != null:
			draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), texture)
		else:
			draw_colored_polygon(corners, _colors[i])
		for j in corners.size():
			draw_line(corners[j], corners[(j + 1) % corners.size()], OUTLINE_COLOR, 2.0)

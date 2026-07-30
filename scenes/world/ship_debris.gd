class_name ShipDebris
extends Node2D

## Cosmetic-only wreckage: a hex module severed from its parent ship's
## connectivity graph (see Ship._detach_module). Drifts under its own
## momentum, has no collision, and fades out before freeing itself.

@export var lifetime: float = 8.0
@export var fade_duration: float = 1.5

const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)

var _cells: Array[Vector2i] = []
var _colors: Array[Color] = []
var _textures: Array[Texture2D] = []
var _cell_size: float = 24.0
var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func setup(cells: Array[Vector2i], colors: Array[Color], textures: Array[Texture2D],
		cell_size: float, drift_velocity: Vector2, spin: float) -> void:
	_cells = cells
	_colors = colors
	_textures = textures
	_cell_size = cell_size
	_velocity = drift_velocity
	_spin = spin
	queue_redraw()


func _process(delta: float) -> void:
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

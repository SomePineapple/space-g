class_name DriftingHexPiece
extends Node2D

## Shared base for the two kinds of hex module that come off a ship when a
## limb is severed (see HullDamageModel._detach_module): plain cosmetic ShipDebris, and
## the recoverable CapturedTechPart. Both render the same per-cell hex art the
## hull was showing an instant earlier, drift and spin under their own
## momentum, and fade out at the end of their life — previously two separate
## files carrying identical copies of all three.
##
## Subclasses vary this by overriding is_drifting() (a part held by a winch or
## tractor beam stops moving and stops ageing) and by tuning lifetime/
## fade_duration in the editor.

@export var lifetime: float = 8.0
@export var fade_duration: float = 1.5

const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)
const OUTLINE_WIDTH: float = 2.0

var _cells: Array[Vector2i] = []
var _colors: Array[Color] = []
var _textures: Array[Texture2D] = []
var _rotation_steps: int = 0
var _cell_size: float = 24.0
var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func setup(cells: Array[Vector2i], colors: Array[Color], textures: Array[Texture2D], rotation_steps: int,
		cell_size: float, drift_velocity: Vector2, spin: float) -> void:
	_cells = cells
	_colors = colors
	_textures = textures
	_rotation_steps = rotation_steps
	_cell_size = cell_size
	_velocity = drift_velocity
	_spin = spin
	queue_redraw()


## Whether this piece should keep moving and ageing this frame. Overridden by
## CapturedTechPart, which freezes once something takes hold of it.
func is_drifting() -> bool:
	return true


func _process(delta: float) -> void:
	if not is_drifting():
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
			draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners_for_rotation(_rotation_steps), texture)
		else:
			draw_colored_polygon(corners, _colors[i])
		for j in corners.size():
			draw_line(corners[j], corners[(j + 1) % corners.size()], OUTLINE_COLOR, OUTLINE_WIDTH)

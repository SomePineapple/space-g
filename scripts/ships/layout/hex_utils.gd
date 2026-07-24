class_name HexUtils
extends RefCounted

const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

const SQRT3: float = 1.7320508


static func axial_to_pixel(hex_coord: Vector2i, cell_size: float) -> Vector2:
	var x: float = cell_size * (SQRT3 * hex_coord.x + SQRT3 * 0.5 * hex_coord.y)
	var y: float = cell_size * (1.5 * hex_coord.y)
	return Vector2(x, y)


static func hex_corners(center: Vector2, cell_size: float) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		corners.append(center + Vector2(cos(angle), sin(angle)) * cell_size)
	return corners


static func rotate(coord: Vector2i, steps: int) -> Vector2i:
	var x: int = coord.x
	var z: int = coord.y
	var y: int = -x - z

	for i in posmod(steps, 6):
		var new_x: int = -z
		var new_y: int = -x
		var new_z: int = -y
		x = new_x
		y = new_y
		z = new_z

	return Vector2i(x, z)


static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in HEX_DIRECTIONS:
		result.append(coord + direction)
	return result

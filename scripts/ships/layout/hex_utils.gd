class_name HexUtils
extends RefCounted

const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


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

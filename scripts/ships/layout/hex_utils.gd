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


## Normalised (0-1) UV coordinates matching hex_corners' vertex order, for
## sampling a square hex-tile texture generated with a small margin around
## the hex silhouette (as produced by art/reference/hex_module.png).
static func hex_uv_corners(uv_radius: float = 0.49) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		uvs.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * uv_radius)
	return uvs


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


## Hex grid distance (number of steps) between two axial coordinates.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in HEX_DIRECTIONS:
		result.append(coord + direction)
	return result


## Inverse of axial_to_pixel: which hex cell a local-space point falls in.
## Shared by the ship builder's click-to-place grid and Ship's impact-point
## hit detection, so both use the same rounding math.
static func pixel_to_axial(pixel: Vector2, cell_size: float) -> Vector2i:
	var qf: float = (SQRT3 / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / cell_size
	var rf: float = (2.0 / 3.0 * pixel.y) / cell_size
	return _hex_round(qf, rf)


static func _hex_round(qf: float, rf: float) -> Vector2i:
	var xf: float = qf
	var zf: float = rf
	var yf: float = -xf - zf

	var rx: float = roundf(xf)
	var ry: float = roundf(yf)
	var rz: float = roundf(zf)

	var x_diff: float = absf(rx - xf)
	var y_diff: float = absf(ry - yf)
	var z_diff: float = absf(rz - zf)

	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))

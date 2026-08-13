class_name HullScarLayer
extends Node2D

## Draws battle damage over a hull's plating and under its lights
## (`docs/scar_layer/SCAR_IMPLEMENTATION.md`, "Layer order").
##
## Its own node for the same reason HullGlowLayer is: ShipLayoutRenderer draws
## plating, seams and welds in one _draw and cannot interleave a second pass
## between them, and the fresh-hit glow needs an additive blend the hull item
## cannot switch to mid-draw. So the stack is renderer -> this -> HullGlowLayer,
## and each is one canvas item.
##
## **Every mark is clipped to the module's own hexes**, so damage never bleeds
## onto the part next to it. The spec suggests a SubViewport and a mask; this
## clips the geometry instead — each decal quad is intersected with the hexes it
## lands on and triangulated. Both hexes and quads are convex, so the result is
## convex and fans trivially, it costs nothing per frame (only when the tier
## changes), and it avoids a viewport and a backbuffer copy per ship.
##
## Everything batches: the whole hull's cold scars are one mesh and one draw
## call, because they all share the one atlas (see docs/performance.md — the
## canvas renderer will not merge separate draw commands however identical).

## Loaded on first use rather than preloaded: a preload of a texture that has
## not been imported yet is a *parse* error, which would take every hull in the
## game down with it rather than merely leaving scars unpainted.
const ATLAS_PATH: String = "res://art/scars/scar_decals.png"
static var _atlas: Texture2D = null

## Seconds a fresh hit stays lit. The spec's 1.5s.
const HEAT_SECONDS: float = 1.5


var _cold_mesh: ArrayMesh = null
## Kept alive because draw_mesh() records only the mesh RID — dropping it frees
## the mesh out from under the canvas item (same trap as ShipLayoutRenderer).
var _heat: HullScarHeat = null
## Per-part scar data from the last set_parts(), keyed by placement id.
var _parts: Dictionary = {}
## seed text + cell size -> Array[HullScarPattern.ScarDecal]. A pattern is expensive
## to generate and never changes, so a redraw reuses it.
var _patterns: Dictionary = {}


static func atlas() -> Texture2D:
	if _atlas == null and ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH)
	return _atlas


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## `parts` is one entry per scarred module:
## {"id": String, "seed": String, "tier": int, "tiles": Array[Vector2],
##  "polys": Array[PackedVector2Array]} — tile centres and the drawn (jittered)
## hex outlines, both in the hull's own space.
func set_parts(parts: Array, cell_size: float) -> void:
	_parts = {}
	var cold: Array = []
	for part: Dictionary in parts:
		_parts[part["id"]] = part
		var decals: Array = _pattern_for(part, cell_size)
		for decal: HullScarPattern.ScarDecal in decals:
			if not decal.heat and decal.tier <= part["tier"]:
				cold.append([decal, part["polys"]])
	_cold_mesh = _build_mesh(cold)
	queue_redraw()
	_heat_layer().set_parts(_parts, _patterns_by_part(cell_size))


## Lights this module's fresh-hit glow. Called on every hit that lands on it, so
## sustained fire keeps the crater hot rather than flickering.
func flash(placement_id: String) -> void:
	_heat_layer().flash(placement_id)


func _draw() -> void:
	# A null atlas would draw every decal as a flat white quad, which is worse
	# than drawing nothing at all.
	if _cold_mesh != null and atlas() != null:
		draw_mesh(_cold_mesh, atlas())


func _pattern_for(part: Dictionary, cell_size: float) -> Array:
	var key: String = "%s@%0.2f" % [part["seed"], cell_size]
	if not _patterns.has(key):
		_patterns[key] = HullScarPattern.generate(part["seed"], part["tiles"], cell_size)
	return _patterns[key]


func _patterns_by_part(cell_size: float) -> Dictionary:
	var by_part: Dictionary = {}
	for id in _parts:
		by_part[id] = _pattern_for(_parts[id], cell_size)
	return by_part


func _heat_layer() -> HullScarHeat:
	if _heat == null or not is_instance_valid(_heat):
		_heat = HullScarHeat.new()
		add_child(_heat)
	return _heat


## Turns [decal, hex polygons] pairs into one triangle mesh, clipped to those
## hexes. Returns null when nothing survives the clip, which is the common case
## for an undamaged hull.
static func _build_mesh(entries: Array) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for entry: Array in entries:
		var decal: HullScarPattern.ScarDecal = entry[0]
		var quad: PackedVector2Array = _decal_quad(decal)
		for poly: PackedVector2Array in entry[1]:
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(quad, poly):
				if piece.size() < 3:
					continue
				var base: int = vertices.size()
				for point in piece:
					vertices.append(point)
					uvs.append(_decal_uv(decal, point))
					colors.append(Color(1.0, 1.0, 1.0, decal.alpha))
				# Convex piece, so a fan from its first vertex is always valid.
				for i in range(1, piece.size() - 1):
					indices.append(base)
					indices.append(base + i)
					indices.append(base + i + 1)

	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _decal_quad(decal: HullScarPattern.ScarDecal) -> PackedVector2Array:
	var half: Vector2 = decal.size * 0.5
	var quad := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		quad.append(decal.centre + corner.rotated(decal.rotation))
	return quad


## Where a clipped vertex falls inside the decal's own region of the atlas —
## the inverse of the transform _decal_quad applies.
static func _decal_uv(decal: HullScarPattern.ScarDecal, point: Vector2) -> Vector2:
	var local: Vector2 = (point - decal.centre).rotated(-decal.rotation)
	var unit := Vector2(
		clampf(local.x / maxf(decal.size.x, 0.001) + 0.5, 0.0, 1.0),
		clampf(local.y / maxf(decal.size.y, 0.001) + 0.5, 0.0, 1.0))
	return (decal.region.position + unit * decal.region.size) / HullScarPattern.ATLAS_SIZE


## The fresh-hit pass: the same crater transform, additively blended, fading out
## over HEAT_SECONDS. A separate node because blend mode is a property of the
## canvas item, so the cold scar and the glow cannot share one.
class HullScarHeat extends Node2D:
	## placement_id -> heat, 1 at the moment of the hit and 0 when cool.
	var _heat: Dictionary = {}
	var _parts: Dictionary = {}
	var _patterns: Dictionary = {}
	var _mesh: ArrayMesh = null

	func _init() -> void:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		set_process(false)

	func set_parts(parts: Dictionary, patterns: Dictionary) -> void:
		_parts = parts
		_patterns = patterns
		# A part that lost its scars (repaired, or removed) must not stay lit.
		for id in _heat.keys():
			if not _parts.has(id):
				_heat.erase(id)
		queue_redraw()

	func flash(placement_id: String) -> void:
		_heat[placement_id] = 1.0
		set_process(true)

	func _process(delta: float) -> void:
		for id in _heat.keys():
			_heat[id] -= delta / HullScarLayer.HEAT_SECONDS
			if _heat[id] <= 0.0:
				_heat.erase(id)
		if _heat.is_empty():
			set_process(false)
		queue_redraw()

	## Rebuilt per frame, but only while something is actually hot, and only from
	## the handful of decals a breach contributes.
	func _draw() -> void:
		_mesh = null
		if _heat.is_empty():
			return
		var entries: Array = []
		for id in _heat:
			var part: Dictionary = _parts.get(id, {})
			if part.is_empty():
				continue
			var heat: float = clampf(_heat[id], 0.0, 1.0)
			for decal: HullScarPattern.ScarDecal in _patterns.get(id, []):
				if not decal.heat or decal.tier > part["tier"]:
					continue
				# Squared: the glow drops away fast and the rim is the last thing
				# to cool, which is what reads as metal cooling rather than a
				# light being switched off.
				var lit := HullScarPattern.ScarDecal.new(decal.region, decal.centre,
					decal.rotation, decal.size, decal.alpha * heat * heat, decal.tier, true)
				entries.append([lit, part["polys"]])
		_mesh = HullScarLayer._build_mesh(entries)
		if _mesh != null and HullScarLayer.atlas() != null:
			draw_mesh(_mesh, HullScarLayer.atlas())

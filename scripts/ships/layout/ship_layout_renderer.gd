class_name ShipLayoutRenderer
extends Node2D

## Draws a Ship's hull directly from its ShipLayout, so any ship's
## appearance always matches its actual module composition.

@export var ship_layout: ShipLayout
@export var cell_size: float = 24.0
## Which faction's reskin (see ModuleType.faction_hex_textures) this ship's
## hull draws with — set by Ship from its ShipPersonality.faction_id.
@export var faction_id: String = "pirate"

const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)
## Flat scorched-hull look for a destroyed module — deliberately ignores its
## hex_texture/color entirely so "this module is dead" reads at a glance.
const DESTROYED_COLOR: Color = Color(0.12, 0.1, 0.1, 1.0)

## placement_id -> true. Owned by whoever calls set_module_destroyed() (Ship,
## once a module's per-placement condition hits zero — see
## Ship._on_module_destroyed); this renderer just reflects it visually.
var _destroyed_placement_ids: Dictionary = {}

## placement_id -> true. A detached module (severed from the core's
## connectivity graph — see HullDamageModel._detach_module) is no longer drawn here at
## all, since a separate ShipDebris node now renders it drifting away.
var _detached_placement_ids: Dictionary = {}

## Batched hull meshes built by the last _draw() (see _build_hex_mesh).
## draw_mesh() records only the mesh's RID in the canvas item, so these have to
## outlive _draw() — dropping them frees the mesh out from under the renderer
## and it spams "Parameter mesh is null" every frame.
var _hull_meshes: Array[ArrayMesh] = []


func _ready() -> void:
	# Hex art is authored at a much higher resolution than it renders at in
	# game, so mipmapped filtering is needed to avoid minification aliasing.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_layout(new_layout: ShipLayout) -> void:
	ship_layout = new_layout
	# A fresh layout (ship rebuild, new instance) starts with no destroyed
	# modules, same as Health resetting to full — stale visuals shouldn't
	# survive a rebuild.
	_destroyed_placement_ids.clear()
	_detached_placement_ids.clear()
	queue_redraw()


func set_module_destroyed(placement_id: String) -> void:
	_destroyed_placement_ids[placement_id] = true
	queue_redraw()


func set_module_detached(placement_id: String) -> void:
	_detached_placement_ids[placement_id] = true
	queue_redraw()


func set_module_repaired(placement_id: String) -> void:
	_destroyed_placement_ids.erase(placement_id)
	queue_redraw()


func _draw() -> void:
	_hull_meshes.clear()
	if ship_layout == null:
		return

	# Every cell's six outline edges are accumulated here and emitted as one
	# draw_multiline() at the end. Interleaving six draw_line()s with each
	# textured fill cost seven canvas commands per hex and stopped the renderer
	# batching any of them, which is the dominant per-frame cost on a large
	# hull — this makes the outlines a single command for the whole ship.
	var outline_points := PackedVector2Array()

	# Textured hex fills are accumulated per texture and emitted as one mesh
	# each. The canvas renderer issues a draw call per draw_colored_polygon()
	# and will not merge them even when they share a texture, so a 42-cell hull
	# cost 42 calls; it only has ~7 distinct textures, so one mesh per texture
	# cuts that to ~7. Cells never overlap, so the reordering is not observable.
	var fills_by_texture: Dictionary = {}
	var flat_fills: Array[Array] = []

	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var destroyed: bool = _destroyed_placement_ids.has(placement.placement_id)
		var occupied_cells: Array[Vector2i] = ship_layout.get_occupied_cells(placement)
		for i in occupied_cells.size():
			var cell: Vector2i = occupied_cells[i]
			var corners: PackedVector2Array = HexUtils.hex_corners(HexUtils.axial_to_pixel(cell, cell_size), cell_size)
			if destroyed:
				flat_fills.append([corners, DESTROYED_COLOR])
			else:
				var texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, i)
				if texture != null:
					var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(placement.rotation_steps)
					if not fills_by_texture.has(texture):
						fills_by_texture[texture] = []
					fills_by_texture[texture].append([corners, uvs])
				else:
					flat_fills.append([corners, module_type.color])
				# Weapon-hardpoint overlay art (turret_360/etc) is drawn by the
				# rotating HardpointGun itself during gameplay (see
				# HardpointGun.set_turret_texture), not here — drawing it a
				# second time on this static, non-rotating hull layer would
				# leave a ghost turret showing through whenever the gun aims
				# away from its neutral orientation.
			for corner_index in corners.size():
				outline_points.append(corners[corner_index])
				outline_points.append(corners[(corner_index + 1) % corners.size()])

	for fill in flat_fills:
		draw_colored_polygon(fill[0], fill[1])

	for texture: Texture2D in fills_by_texture:
		var mesh: ArrayMesh = _build_hex_mesh(fills_by_texture[texture])
		_hull_meshes.append(mesh)
		draw_mesh(mesh, texture)

	if not outline_points.is_empty():
		draw_multiline(outline_points, OUTLINE_COLOR, 2.0)


## Merges every [corners, uvs] hex sharing one texture into a single triangle
## mesh, so the whole group costs one draw call. Each hex is fanned from its
## first corner into four triangles.
func _build_hex_mesh(fills: Array) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for fill: Array in fills:
		var base: int = vertices.size()
		vertices.append_array(fill[0])
		uvs.append_array(fill[1])
		for corner_index in range(1, 5):
			indices.append(base)
			indices.append(base + corner_index)
			indices.append(base + corner_index + 1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

class_name ShipLayoutRenderer
extends Node2D

## Draws a Ship's hull directly from its ShipLayout, so any ship's
## appearance always matches its actual module composition.
##
## A ship here is a pile of separate parts bolted together, and it is drawn to
## look like one. Three things do that work, none of which live in the art (a
## part can be joined on any of its six faces, so no authored seam would ever
## line up):
##
##   * edges *inside* a part are not drawn at all, so a three-hex spar reads as
##     one object rather than three tiles;
##   * edges *between* two different parts are drawn as a heavy seam;
##   * each part is tinted by its own wear and origin, so a hull of scavenged
##     parts is visibly mismatched plating rather than one uniform shell.

@export var ship_layout: ShipLayout
@export var cell_size: float = 24.0
## Which faction's reskin (see ModuleType.faction_hex_textures) this ship's
## hull draws with — set by Ship from its ShipPersonality.faction_id.
@export var faction_id: String = "pirate"

## The ship's outer edge against space, and the join between two parts. The seam
## is lighter and thinner than the silhouette so it reads as a panel line rather
## than a hole.
const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)
const SEAM_COLOR: Color = Color(0.05, 0.06, 0.08, 0.55)
const OUTLINE_WIDTH: float = 2.0
const SEAM_WIDTH: float = 1.0

## Flat scorched-hull look for a destroyed module — deliberately ignores its
## hex_texture/color entirely so "this module is dead" reads at a glance.
const DESTROYED_COLOR: Color = Color(0.12, 0.1, 0.1, 1.0)

## How far a part's tint is pulled toward its origin faction's colour. Enough to
## see that a plate came off someone else's ship, not enough to lose the
## faction reskin the art already carries.
const ORIGIN_TINT_STRENGTH: float = 0.22
## Brightness a part at zero condition is drawn at, relative to an intact one.
const WORN_SHADE: float = 0.55
## Per-part brightness jitter, so two intact parts of the same type aren't
## pixel-identical. Derived from the instance id, so a given part always looks
## the same and every machine agrees.
const PART_VARIATION: float = 0.07

## Rough plate colour per faction, for the origin tint above. Presentation only
## — nothing simulation-side reads these.
const FACTION_TINTS: Dictionary = {
	"pirate": Color(1.0, 0.82, 0.68),
	"corporate": Color(0.82, 0.90, 1.0),
	"ancient": Color(0.88, 0.78, 1.0),
}

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

	# Silhouette and seam edges are accumulated here and emitted as one
	# draw_multiline() each at the end. Interleaving draw_line()s with each
	# textured fill cost seven canvas commands per hex and stopped the renderer
	# batching any of them, which is the dominant per-frame cost on a large
	# hull — this makes all the line work two commands for the whole ship.
	var outline_points := PackedVector2Array()
	var seam_points := PackedVector2Array()

	# Textured hex fills are accumulated per texture and emitted as one mesh
	# each. The canvas renderer issues a draw call per draw_colored_polygon()
	# and will not merge them even when they share a texture, so a 42-cell hull
	# cost 42 calls; it only has ~7 distinct textures, so one mesh per texture
	# cuts that to ~7. Cells never overlap, so the reordering is not observable.
	# Per-part tint rides along as vertex colours rather than as its own draw
	# call, so mismatched plating costs nothing extra.
	var fills_by_texture: Dictionary = {}
	var flat_fills: Array[Array] = []

	# Which part owns each drawn cell, so an edge can tell "inside one part"
	# from "between two parts" from "open space".
	var owner_by_cell: Dictionary = _build_owner_lookup()

	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var destroyed: bool = _destroyed_placement_ids.has(placement.placement_id)
		var tint: Color = _part_tint(placement)
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
					fills_by_texture[texture].append([corners, uvs, tint])
				else:
					flat_fills.append([corners, module_type.color * tint])
				# Weapon-hardpoint overlay art (turret_360/etc) is drawn by the
				# rotating HardpointGun itself during gameplay (see
				# HardpointGun.set_turret_texture), not here — drawing it a
				# second time on this static, non-rotating hull layer would
				# leave a ghost turret showing through whenever the gun aims
				# away from its neutral orientation.
			_collect_edges(cell, corners, placement.placement_id, owner_by_cell,
				outline_points, seam_points)

	for fill in flat_fills:
		draw_colored_polygon(fill[0], fill[1])

	for texture: Texture2D in fills_by_texture:
		var mesh: ArrayMesh = _build_hex_mesh(fills_by_texture[texture])
		_hull_meshes.append(mesh)
		draw_mesh(mesh, texture)

	# Seams under the silhouette: where a part meets open space, the heavier
	# outline should win.
	if not seam_points.is_empty():
		draw_multiline(seam_points, SEAM_COLOR, SEAM_WIDTH)
	if not outline_points.is_empty():
		draw_multiline(outline_points, OUTLINE_COLOR, OUTLINE_WIDTH)


## cell -> placement_id, for every cell actually being drawn. Detached parts are
## excluded, so the hole a severed wing leaves behind is outlined as the ship's
## new edge rather than seamed against something that isn't there.
func _build_owner_lookup() -> Dictionary:
	var owner_by_cell: Dictionary = {}
	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue
		for cell in ship_layout.get_occupied_cells(placement):
			owner_by_cell[cell] = placement.placement_id
	return owner_by_cell


## Sorts one cell's six edges into silhouette, seam, or nothing at all. An edge
## shared by two cells of the same part is deliberately dropped — that is what
## makes a multi-hex part read as one object.
##
## Edges between two different parts are found twice, once from each side; the
## `<` comparison keeps only one copy so the seam isn't drawn double-width.
func _collect_edges(cell: Vector2i, corners: PackedVector2Array, placement_id: String,
		owner_by_cell: Dictionary, outline_points: PackedVector2Array,
		seam_points: PackedVector2Array) -> void:
	for edge in HexUtils.EDGE_DIRECTIONS.size():
		var neighbour: Vector2i = cell + HexUtils.EDGE_DIRECTIONS[edge]
		var neighbour_owner: Variant = owner_by_cell.get(neighbour)

		var target: PackedVector2Array
		if neighbour_owner == null:
			target = outline_points
		elif neighbour_owner == placement_id:
			continue
		elif placement_id < neighbour_owner:
			target = seam_points
		else:
			continue

		target.append(corners[edge])
		target.append(corners[(edge + 1) % corners.size()])


## How this specific part is shaded: darker the more beaten up it is, pulled
## toward its origin faction's plate colour if it was cut off someone else's
## ship, and nudged a little either way per part so a hull of identical types
## still looks assembled rather than stamped.
func _part_tint(placement: ModulePlacement) -> Color:
	var instance: ModuleInstance = placement.instance
	if instance == null:
		return Color.WHITE

	var tint: Color = Color.WHITE
	if instance.is_salvaged() and instance.origin_faction_id != faction_id:
		var origin_tint: Variant = FACTION_TINTS.get(instance.origin_faction_id)
		if origin_tint != null:
			tint = tint.lerp(origin_tint, ORIGIN_TINT_STRENGTH)

	# String.hash() is stable for a given string everywhere, so this is the same
	# on every machine. It is presentation anyway, and deliberately not drawn
	# from a GameRng stream — see docs/multiplayer.md on cosmetic randomness.
	var jitter: float = (float(instance.instance_id.hash() % 1000) / 999.0 - 0.5) * 2.0 * PART_VARIATION
	# Capped at 1.0: a vertex colour above white would brighten the art past what
	# it was drawn at, which reads as a lighting bug rather than a fresh plate.
	var shade: float = clampf(
		lerpf(WORN_SHADE, 1.0, clampf(instance.condition_fraction, 0.0, 1.0)) + jitter, 0.0, 1.0)
	return tint * Color(shade, shade, shade, 1.0)


## Merges every [corners, uvs, tint] hex sharing one texture into a single
## triangle mesh, so the whole group costs one draw call. Each hex is fanned
## from its first corner into four triangles. The per-part tint travels as a
## vertex colour, which is what lets parts shade differently without splitting
## the batch.
func _build_hex_mesh(fills: Array) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for fill: Array in fills:
		var base: int = vertices.size()
		vertices.append_array(fill[0])
		uvs.append_array(fill[1])
		for corner_index in fill[0].size():
			colors.append(fill[2])
		for corner_index in range(1, 5):
			indices.append(base)
			indices.append(base + corner_index)
			indices.append(base + corner_index + 1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

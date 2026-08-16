class_name ShipLayoutRenderer
extends Node2D

## Draws a Ship's hull directly from its ShipLayout, so any ship's
## appearance always matches its actual module composition.
##
## A ship here is a pile of separate parts bolted together, and it is drawn to
## look like one. None of that lives in the art: a part can be joined on any of
## its six faces, so no authored seam would ever line up. It is all derived from
## the layout's own adjacency and from what each mounted part knows about itself
## (see HullPaint, which ShipBuilderPanel's grid shares so both surfaces agree):
##
##   * edges *inside* a part are not drawn at all, so a three-hex spar reads as
##     one object rather than three tiles;
##   * edges *between* two matched parts get a fine panel line;
##   * a joint between parts that don't belong together — different origin, or
##     either one damaged — gets short weld dashes and bolts instead;
##   * every part is nudged a fraction off its grid cell and casts a shadow into
##     the hairline gap that opens, so parts sit on the hull rather than in it.
##
## The weld rule is the whole visual arc. A fresh hull of matched, undamaged
## parts has only clean seams and looks manufactured; scrappiness appears by
## itself, exactly where scrap actually is, as foreign and beaten-up parts
## accumulate. Nothing here fakes wear on a ship that hasn't earned it.

@export var ship_layout: ShipLayout
@export var cell_size: float = 24.0
## Which faction's reskin (see ModuleType.faction_hex_textures) this ship's
## hull draws with — set by Ship from its ShipPersonality.faction_id.
@export var faction_id: String = "pirate"

## The ship's outer edge against space. Heavier than any seam, so a joint never
## reads as a hole.
const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.07, 0.9)
const OUTLINE_WIDTH: float = 2.0

## A joint between two parts that belong together: a fine panel line.
const SEAM_COLOR: Color = Color(0.05, 0.06, 0.08, 0.55)
const SEAM_WIDTH: float = 1.0

## A joint between parts that don't. Dashes are the weld bead itself; bolts are
## the fixings across it, thinner and darker so they read as hardware rather
## than more weld (see HullPaint.append_weld for why this isn't a line).
const WELD_COLOR: Color = Color(0.72, 0.42, 0.21, 0.8)
const WELD_WIDTH: float = 1.8
const WELD_BOLT_COLOR: Color = Color(0.54, 0.32, 0.15, 0.9)
const WELD_BOLT_WIDTH: float = 1.0

## Flat scorched-hull look for a destroyed module — deliberately ignores its
## hex_texture/color entirely so "this module is dead" reads at a glance.
const DESTROYED_COLOR: Color = Color(0.12, 0.1, 0.1, 1.0)

## Emissive layers are drawn white here and pushed past the glow threshold by
## HullGlowLayer's shader instead. They cannot be brightened at this point: a
## mesh's vertex colour is 8-bit, so a Color above 1.0 clamps back to white on
## the way in — which is what the gain that used to live here was quietly doing.
const GLOW_TINT: Color = Color.WHITE

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
## The child that draws this hull's lit layers (see _glow_layer).
var _glow: HullGlowLayer = null
## The child that draws battle damage, between the plating and the lights (see
## _scar_layer).
var _scars: HullScarLayer = null


func _ready() -> void:
	# Hex art is authored at a much higher resolution than it renders at in
	# game, so mipmapped filtering is needed to avoid minification aliasing.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Created on first use rather than in _ready, because _draw can run before
## _ready on a hull built during a layout apply.
func _glow_layer() -> HullGlowLayer:
	if _glow == null or not is_instance_valid(_glow):
		_glow = HullGlowLayer.new()
		add_child(_glow)
	return _glow


## Scars sit above the plating and below the lights, so a lamp on a battered
## part still reads as lit. Created before the glow layer for exactly that
## reason — children draw in tree order — and moved under it if the glow layer
## happened to exist first.
func _scar_layer() -> HullScarLayer:
	if _scars == null or not is_instance_valid(_scars):
		_scars = HullScarLayer.new()
		add_child(_scars)
		if _glow != null and is_instance_valid(_glow):
			move_child(_scars, _glow.get_index())
	return _scars


## Deliberately no wiring layer on the hull. Circuit runs are drawn on the ship
## *builder*'s grid only (HexGridControl._draw_conduit_wires) — at flight zoom
## the cables were finer than the hull's own seams and read as speckle across the
## plating rather than as wiring, so they cost legibility on the one screen where
## legibility matters most. The builder is where a hull is inspected; that is
## where its loom is worth showing.


## Lights the fresh-hit glow on one module. Called by HullDamageModel as damage
## lands, since that is the only thing that knows a hit happened as opposed to
## seeing the condition it left behind.
func flash_module_damage(placement_id: String) -> void:
	_scar_layer().flash(placement_id)


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

	# All the line work is accumulated here and emitted as one draw_multiline()
	# per style at the end. Interleaving draw_line()s with each textured fill
	# cost seven canvas commands per hex and stopped the renderer batching any of
	# them, which is the dominant per-frame cost on a large hull — this way the
	# whole ship's edges are five commands however big it gets.
	var outline_points := PackedVector2Array()
	var seam_points := PackedVector2Array()
	var weld_points := PackedVector2Array()
	var weld_bolt_points := PackedVector2Array()
	# The perimeter of every part damaged enough for the Slicer to cut free.
	var cut_ready_points := PackedVector2Array()

	# Textured hex fills are accumulated per texture and emitted as one mesh
	# each. The canvas renderer issues a draw call per draw_colored_polygon()
	# and will not merge them even when they share a texture, so a 42-cell hull
	# cost 42 calls; it only has ~7 distinct textures, so one mesh per texture
	# cuts that to ~7. Cells never overlap, so the reordering is not observable.
	# Per-part tint rides along as vertex colours rather than as its own draw
	# call, so mismatched plating costs nothing extra. Shadows batch the same
	# way, into one untextured mesh drawn under everything.
	var fills_by_texture: Dictionary = {}
	# The emissive layer, batched exactly like the base fills and drawn straight
	# after them (see ModuleType.faction_hex_glow_textures).
	var glow_fills_by_texture: Dictionary = {}
	var flat_fills: Array[Array] = []
	var shadow_fills: Array[Array] = []
	# Battle damage, handed to the scar child once the hull's own geometry is
	# known — the scars are clipped to these same jittered hexes, so they have to
	# be the drawn outlines rather than the grid cells underneath.
	var scar_parts: Array = []
	var shadow_offset: Vector2 = HullPaint.part_shadow_offset(cell_size)

	# Which part owns each drawn cell, so an edge can tell "inside one part" from
	# "between two parts" from "open space" — and, for a joint, judge whether the
	# two parts belong together.
	var owner_by_cell: Dictionary = _build_owner_lookup()

	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var destroyed: bool = _destroyed_placement_ids.has(placement.placement_id)
		var tint: Color = HullPaint.part_tint(placement, faction_id)
		# The part's nudge off its exact grid cell, computed once and applied to
		# every cell it occupies, so a multi-hex part moves as one rigid object.
		var centroid: Vector2 = HullPaint.part_centroid(ship_layout, placement, cell_size)
		var offset: Vector2 = HullPaint.part_offset(placement.instance, cell_size)
		var rotation: float = HullPaint.part_rotation(placement.instance)

		# A destroyed module is already drawn as scorched wreckage, so scarring it
		# further would only muddy the one state that has to read instantly.
		var scar_tier: int = 0 if destroyed else HullPaint.scar_tier(placement.instance)
		var scar_polys: Array[PackedVector2Array] = []
		var scar_tiles: Array[Vector2] = []

		var occupied_cells: Array[Vector2i] = ship_layout.get_occupied_cells(placement)
		for i in occupied_cells.size():
			var cell: Vector2i = occupied_cells[i]
			var corners: PackedVector2Array = HullPaint.jittered_corners(
				HexUtils.hex_corners(HexUtils.axial_to_pixel(cell, cell_size), cell_size),
				centroid, offset, rotation)

			shadow_fills.append([_translated(corners, shadow_offset),
				HexUtils.hex_uv_corners(), HullPaint.SHADOW_COLOR])

			if destroyed:
				flat_fills.append([corners, DESTROYED_COLOR])
			else:
				var uvs: PackedVector2Array = HexUtils.hex_uv_corners_for_rotation(placement.rotation_steps)
				# The flight plate, not the builder's: a module whose tile art is a
				# cutaway (the Conduit's open junction box) shows its cover out here.
				# See ModuleType.faction_hex_cover_textures.
				var texture: Texture2D = module_type.get_flight_hex_texture_for_cell(faction_id, i)
				if texture != null:
					if not fills_by_texture.has(texture):
						fills_by_texture[texture] = []
					fills_by_texture[texture].append([corners, uvs, tint])
				else:
					flat_fills.append([corners, module_type.color * tint])
				# Deliberately not tinted with the part: a scavenged module's
				# plating takes the colour of wherever it came from, but its
				# indicator lamps are the same lamps whoever is flying it.
				var glow: Texture2D = module_type.get_hex_glow_texture_for_cell(faction_id, i)
				if glow != null:
					if not glow_fills_by_texture.has(glow):
						glow_fills_by_texture[glow] = []
					glow_fills_by_texture[glow].append([corners, uvs, GLOW_TINT])
				# Weapon-hardpoint overlay art (turret_360/etc) is drawn by the
				# rotating HardpointGun itself during gameplay (see
				# HardpointGun.set_turret_texture), not here — drawing it a
				# second time on this static, non-rotating hull layer would
				# leave a ghost turret showing through whenever the gun aims
				# away from its neutral orientation.
			if scar_tier > 0:
				scar_polys.append(corners)
				scar_tiles.append(_polygon_centre(corners))

			_collect_edges(cell, corners, placement, owner_by_cell,
				outline_points, seam_points, weld_points, weld_bolt_points,
				cut_ready_points)

		if scar_tier > 0:
			scar_parts.append({
				"id": placement.placement_id,
				"seed": _scar_seed(placement),
				"tier": scar_tier,
				"tiles": scar_tiles,
				"polys": scar_polys,
			})

	# Shadows first, under every fill: a part's shadow falls across its
	# neighbour's cells, and only the slivers that land in the gaps the jitter
	# opened — or outside the hull entirely — should survive.
	if not shadow_fills.is_empty():
		var shadow_mesh: ArrayMesh = _build_hex_mesh(shadow_fills)
		_hull_meshes.append(shadow_mesh)
		draw_mesh(shadow_mesh, null)

	for fill in flat_fills:
		draw_colored_polygon(fill[0], fill[1])

	for texture: Texture2D in fills_by_texture:
		var mesh: ArrayMesh = _build_hex_mesh(fills_by_texture[texture])
		_hull_meshes.append(mesh)
		draw_mesh(mesh, texture)

	# Lights are handed to the child glow layer rather than drawn here, because
	# they need a shader this item cannot switch to mid-draw (see HullGlowLayer).
	# Not kept in _hull_meshes: these are drawn by the child, so it is the child
	# that has to hold them alive.
	var glow_meshes: Dictionary = {}
	for glow_texture: Texture2D in glow_fills_by_texture:
		glow_meshes[glow_texture] = _build_hex_mesh(glow_fills_by_texture[glow_texture])
	_scar_layer().set_parts(scar_parts, cell_size)
	_glow_layer().set_glow_meshes(glow_meshes)

	# Bolts over their own weld dashes, and the silhouette over everything, so a
	# joint reaching the hull's edge never looks like a hole.
	if not seam_points.is_empty():
		draw_multiline(seam_points, SEAM_COLOR, SEAM_WIDTH)
	if not weld_points.is_empty():
		draw_multiline(weld_points, WELD_COLOR, WELD_WIDTH)
	if not weld_bolt_points.is_empty():
		draw_multiline(weld_bolt_points, WELD_BOLT_COLOR, WELD_BOLT_WIDTH)
	if not outline_points.is_empty():
		draw_multiline(outline_points, OUTLINE_COLOR, OUTLINE_WIDTH)
	# Over the silhouette: this has to be readable against space at the edge of a
	# hull, which is exactly where a severable limb usually is.
	if not cut_ready_points.is_empty():
		draw_multiline(cut_ready_points, HullPaint.CUT_READY_COLOR, HullPaint.CUT_READY_WIDTH)


## The scar seed. Keyed to the mounted part, not to where it is bolted: a gun
## cut off a wreck arrives wearing the damage it took there, and unbolting it
## and putting it back must not re-roll the marks.
func _scar_seed(placement: ModulePlacement) -> String:
	if placement.instance != null and not placement.instance.instance_id.is_empty():
		return placement.instance.instance_id
	return placement.placement_id


func _polygon_centre(corners: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for corner in corners:
		total += corner
	return total / maxf(float(corners.size()), 1.0)


func _translated(corners: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	moved.resize(corners.size())
	for i in corners.size():
		moved[i] = corners[i] + offset
	return moved


## cell -> ModulePlacement, for every cell actually being drawn. Detached parts
## are excluded, so the hole a severed wing leaves behind is outlined as the
## ship's new edge rather than seamed against something that isn't there.
func _build_owner_lookup() -> Dictionary:
	var owner_by_cell: Dictionary = {}
	for placement in ship_layout.placements:
		if _detached_placement_ids.has(placement.placement_id):
			continue
		for cell in ship_layout.get_occupied_cells(placement):
			owner_by_cell[cell] = placement
	return owner_by_cell


## Sorts one cell's six edges into silhouette, one of the two seam styles, or
## nothing at all. An edge shared by two cells of the same part is deliberately
## dropped — that is what makes a multi-hex part read as one object.
##
## Edges between two different parts are found twice, once from each side; the
## `<` comparison keeps only one copy so the seam isn't drawn double-width.
## The corners passed in are already jittered, so a weld follows the edge of the
## part as drawn rather than the grid cell underneath it. The two sides of a
## joint therefore no longer agree exactly on where the edge is — which is the
## point: that hairline mismatch is what a hand-fitted joint looks like.
func _collect_edges(cell: Vector2i, corners: PackedVector2Array, placement: ModulePlacement,
		owner_by_cell: Dictionary, outline_points: PackedVector2Array,
		seam_points: PackedVector2Array, weld_points: PackedVector2Array,
		weld_bolt_points: PackedVector2Array, cut_ready_points: PackedVector2Array) -> void:
	# A destroyed module is a hole, not something still to be cut: its condition
	# is zero, so is_cuttable() is trivially true and the marker would sit on the
	# scorched remains forever. The part that was severed has already left.
	var cuttable: bool = not _destroyed_placement_ids.has(placement.placement_id) \
		and HullPaint.is_cuttable(placement.instance)
	for edge in HexUtils.EDGE_DIRECTIONS.size():
		var neighbour: Variant = owner_by_cell.get(cell + HexUtils.EDGE_DIRECTIONS[edge])
		var from: Vector2 = corners[edge]
		var to: Vector2 = corners[(edge + 1) % corners.size()]

		# Marked around the part's own outline — every edge that isn't internal to
		# it — so the marker traces the object you would actually cut free rather
		# than the individual hexes it happens to occupy.
		if cuttable and neighbour != placement:
			HullPaint.append_cut_marker(from, to, cut_ready_points)

		if neighbour == null:
			outline_points.append(from)
			outline_points.append(to)
			continue
		if placement.placement_id >= neighbour.placement_id:
			continue

		if HullPaint.is_clean_joint(placement, neighbour):
			seam_points.append(from)
			seam_points.append(to)
		else:
			HullPaint.append_weld(from, to, weld_points, weld_bolt_points)




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

class_name FactionArtImporter
extends RefCounted

## Generic loader for per-faction hex art. Given a module's base art name
## (e.g. "hull_mk1"), scans res://resources/exports/ for faction subfolders
## and returns a {faction_id: Texture2D} dictionary built from whichever
## "<folder>/<faction_id>_<base_name>.png" files actually exist. Adding a new
## faction (a new folder of correctly-named PNGs) or a new per-faction sprite
## needs no code changes here — see ModuleCatalog for which base_name each
## module type asks for.
##
## apply_hex_art() is the entry point ModuleCatalog uses: one call claims every
## layer a module could have, and each layer is simply whatever files happen to
## be on disk. Dropping a new light map into an exports folder lights that module
## up with no code change at all.

const EXPORTS_ROOT: String = "res://resources/exports/"

## What a light map is called: the base art name with this on the end, after the
## cell coordinates for per-cell art. "corporate_grapple_mk1_lights.png",
## "corporate_grapple_mk3_1_0_lights.png".
##
## These are the emissive layers the world's glow catches (see
## ModuleType.faction_hex_glow_textures and ShipLayoutRenderer's glow pass) —
## lit windows, indicator strips, emitter rings, authored over transparency and
## drawn additively over the plate so they can be blown past white.
const LIGHTS_SUFFIX: String = "_lights"

## What a closed-up plate is called: the base art name with this on the end.
## "corporate_conduit_cover.png".
##
## Only a module whose ordinary plate is a *cutaway* needs one. The conduit's
## tile shows its junction hub and every hole in it, which is what the ship
## builder is for — but on a flying hull that is an open inspection panel with the
## wiring hanging out. The cover is the same hex with the panel bolted shut, and
## it is what the world draws (see ModuleType.get_flight_hex_texture_for_cell).
##
## Optional and automatic, exactly like the light maps: a module with no cover
## file simply draws the same plate on both screens, which is every module but one.
const COVER_SUFFIX: String = "_cover"


## Claims every art layer for one module type, in one call.
##
## Each layer is optional and independent: whichever files exist get used, and
## the ones that do not simply leave their dictionary empty, which every consumer
## already treats as "draw nothing extra". For `base_name` "grapple_mk3" on a
## three-cell module this looks for, per faction:
##
##   <faction>_grapple_mk3.png                 whole-footprint plate (fallback)
##   <faction>_grapple_mk3_<q>_<r>.png         one plate per cell
##   <faction>_grapple_mk3_lights.png          whole-footprint light map
##   <faction>_grapple_mk3_<q>_<r>_lights.png  one light map per cell
##   <faction>_grapple_mk3_cover.png           closed-up plate for flight
##
## The per-cell footprint is read off the module type rather than passed in.
## Call sites used to repeat the footprint constant they had just built the
## module with, which is a second place for it to be wrong.
##
## `overlay_name` is the separate sprite some modules draw over their plate (a
## weapon tier's turret — see ModuleType.faction_hex_overlay_textures). It is a
## different image, not a layer of the base one, so it is named independently.
## Overlays have no light map: nothing has needed one, and adding the field
## before there is art for it would be guessing at the shape.
static func apply_hex_art(module_type: ModuleType, base_name: String,
		overlay_name: String = "") -> void:
	var cells: Array[Vector2i] = module_type.footprint_cells
	module_type.faction_hex_textures = load_faction_textures(base_name)
	module_type.faction_hex_textures_per_cell = load_faction_textures_per_cell(base_name, cells)
	module_type.faction_hex_cover_textures = load_faction_textures(base_name + COVER_SUFFIX)
	module_type.faction_hex_glow_textures = load_faction_textures(base_name + LIGHTS_SUFFIX)
	module_type.faction_hex_glow_textures_per_cell = load_faction_textures_per_cell(
		base_name, cells, LIGHTS_SUFFIX)
	if not overlay_name.is_empty():
		module_type.faction_hex_overlay_textures = load_faction_textures(overlay_name)

## folder_name -> faction_id. Kept separate because they diverge for
## "pirates": the folder is plural, but its files are prefixed "pirate_"
## (singular, matching ShipPersonality.faction_id values elsewhere). Every
## other faction folder name already matches its file prefix exactly.
static var _folder_to_faction_id: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func load_faction_textures(base_name: String) -> Dictionary:
	if _texture_cache.has(base_name):
		return _texture_cache[base_name]

	var result: Dictionary = {}
	for folder_name in _discover_faction_folders():
		var faction_id: String = _folder_to_faction_id[folder_name]
		var path: String = "%s%s/%s_%s.png" % [EXPORTS_ROOT, folder_name, faction_id, base_name]
		if ResourceLoader.exists(path):
			result[faction_id] = load(path)

	_texture_cache[base_name] = result
	return result


## Same as load_faction_textures(), but for a module exported as one image
## per hex it occupies rather than a single image spanning the whole
## footprint. Looks for "<base_name>_<q>_<r>" for each offset in
## footprint_cells (the exported piece's column/row matching that cell's own
## axial offset, e.g. "laser_cannon_mk3_1_0" for Vector2i(1, 0)) and returns
## one {faction_id: Texture2D} dictionary per cell, same order as
## footprint_cells (see ModuleType.faction_hex_textures_per_cell). A faction
## missing a given piece simply has no entry for that cell, same graceful
## fallback as the single-image loader.
## `suffix` is appended after the cell coordinates, for a module exported as
## more than one layer per hex — "grapple_mk2" + "_lights" resolves to
## "corporate_grapple_mk2_0_0_lights.png". Empty (the default) is the plain base
## layer every existing caller wants.
static func load_faction_textures_per_cell(base_name: String, footprint_cells: Array[Vector2i],
		suffix: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offset in footprint_cells:
		result.append(load_faction_textures("%s_%d_%d%s" % [base_name, offset.x, offset.y, suffix]))
	return result


## Faction ids are just the exports folder's subdirectory names, mapped
## through _folder_name_to_faction_id() for the one folder/prefix mismatch —
## so a new faction folder is picked up automatically with no code changes.
static func _discover_faction_folders() -> Array[String]:
	if not _folder_to_faction_id.is_empty():
		return _folder_to_faction_id.keys()

	var dir: DirAccess = DirAccess.open(EXPORTS_ROOT)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				_folder_to_faction_id[entry] = _folder_name_to_faction_id(entry)
			entry = dir.get_next()
		dir.list_dir_end()

	return _folder_to_faction_id.keys()


static func _folder_name_to_faction_id(folder_name: String) -> String:
	if folder_name == "pirates":
		return "pirate"
	return folder_name

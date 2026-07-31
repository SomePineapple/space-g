class_name FactionArtImporter
extends RefCounted

## Generic loader for per-faction hex art. Given a module's base art name
## (e.g. "hull_mk1"), scans res://resources/exports/ for faction subfolders
## and returns a {faction_id: Texture2D} dictionary built from whichever
## "<folder>/<faction_id>_<base_name>.png" files actually exist. Adding a new
## faction (a new folder of correctly-named PNGs) or a new per-faction sprite
## needs no code changes here — see ModuleCatalog for which base_name each
## module type asks for.

const EXPORTS_ROOT: String = "res://resources/exports/"

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
static func load_faction_textures_per_cell(base_name: String, footprint_cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offset in footprint_cells:
		result.append(load_faction_textures("%s_%d_%d" % [base_name, offset.x, offset.y]))
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

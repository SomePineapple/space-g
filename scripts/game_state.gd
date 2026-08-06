extends Node

## Carries player ship state across a warp gate's scene change (see
## WarpGate.gd), since each region is a separate scene and change_scene_to_file
## discards the old scene tree entirely — the player's Ship, Inventory, etc.
## get rebuilt from scratch in the destination scene and need this to catch up
## to where they left off. Session-only, like the rest of this prototype's
## economy state; not a save system.
##
## Parameters are untyped Node/Resource (not Ship/ShipLayout) deliberately:
## as an autoload, this script compiles before the project's other global
## classes are guaranteed registered, and a static Ship/ShipLayout type hint
## here corrupts type resolution for those classes project-wide.

## Scene paths already handed to ResourceLoader's threaded loader (path ->
## true), so a gate re-requesting its own destination (e.g. re-entering its
## trigger area) doesn't double-request the same path.
var _threaded_requests: Dictionary = {}
## Fully-loaded PackedScenes, cached once retrieved so repeated warps to an
## already-visited region don't re-touch ResourceLoader at all.
var _loaded_scene_cache: Dictionary = {}

var _has_snapshot: bool = false
var _credits: int = 0
var _material_totals: Dictionary = {}
var _component_totals: Dictionary = {}
## key -> Array[ModuleInstance] — the real owned-module pool (Phase 8.1), not
## just counts, so upgrade state on an owned-but-unplaced instance survives a
## warp the same way a placed one already does via _ship_layout below.
var _owned_module_pool: Dictionary = {}
var _captured_tech_totals: Dictionary = {}
var _researched_ids: Array = []
var _known_manufacturer_ids: Array = []
var _ship_layout: Resource
var _health_fraction: float = 1.0

## Name of a node in the *destination* scene to arrive at — set by WarpGate
## just before a GATE-mode change_scene_to_file, normally naming the paired
## gate on the other side, so arriving always lands you on a gate rather
## than wherever that scene's Ship happens to be parked.
var pending_arrival_node_name: String = ""


## Starts a background load of a region scene ahead of an actual warp, so the
## expensive disk-read/parse/import cost happens while the player is still
## flying normally instead of stalling the main thread the instant they cross
## a gate. Safe to call repeatedly for the same path (e.g. a gate's _ready()
## firing again after a scene reload) — already-requested/loaded paths are
## no-ops.
func request_scene_preload(path: String) -> void:
	if path.is_empty() or _threaded_requests.has(path):
		return
	_threaded_requests[path] = true
	ResourceLoader.load_threaded_request(path)


## Returns the PackedScene if its threaded load has finished, null otherwise
## (never blocks). Callers should fall back to a direct ResourceLoader.load()
## if this returns null, for the rare case a warp happens before the
## background load completes.
func get_preloaded_scene(path: String) -> PackedScene:
	if _loaded_scene_cache.has(path):
		return _loaded_scene_cache[path]
	if not _threaded_requests.has(path):
		return null
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	var loaded: PackedScene = ResourceLoader.load_threaded_get(path)
	_loaded_scene_cache[path] = loaded
	return loaded


func has_snapshot() -> bool:
	return _has_snapshot


func capture(ship: Node) -> void:
	var inventory: Node = ship.get_node("Inventory")
	_credits = inventory.get_credits()
	_material_totals = inventory.get_all_materials().duplicate()
	_component_totals = inventory.get_all_components().duplicate()
	_owned_module_pool = inventory.get_all_owned_module_instances().duplicate()
	_captured_tech_totals = inventory.get_all_captured_tech().duplicate()
	_researched_ids = inventory.get_researched_ids()
	_known_manufacturer_ids = inventory.get_known_manufacturer_ids()
	_ship_layout = ship.ship_layout.duplicate(true)
	_health_fraction = ship.get_health_fraction()

	_has_snapshot = true


## Called from a freshly-spawned player Ship's _ready() in the destination
## scene. No-op on the very first region a session ever loads into, since
## there's nothing to restore yet.
func apply(ship: Node) -> void:
	if not _has_snapshot:
		return

	ship.apply_layout(_ship_layout.duplicate(true))

	var inventory: Node = ship.get_node("Inventory")
	inventory.add_credits(_credits)
	for material_id in _material_totals:
		inventory.add_material(material_id, _material_totals[material_id])
	for component_id in _component_totals:
		inventory.add_component(component_id, _component_totals[component_id])
	inventory.restore_owned_module_pool(_owned_module_pool.duplicate())
	for module_type_id in _captured_tech_totals:
		for i in _captured_tech_totals[module_type_id]:
			inventory.add_captured_tech(module_type_id)
	for module_type_id in _researched_ids:
		inventory.set_researched(module_type_id)
	for manufacturer_id in _known_manufacturer_ids:
		inventory.discover_manufacturer(manufacturer_id)

	ship.set_health_fraction(_health_fraction)

	if not pending_arrival_node_name.is_empty():
		var arrival: Node2D = ship.get_tree().current_scene.get_node_or_null(pending_arrival_node_name)
		if arrival != null:
			ship.global_position = arrival.global_position
		pending_arrival_node_name = ""

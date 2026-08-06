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
## key -> Array[ModuleInstance] — the real owned-module pool, not just counts,
## so an owned-but-unplaced module keeps its identity across a warp the same
## way a placed one already does via _ship_layout below.
var _owned_module_pool: Dictionary = {}
var _captured_tech_totals: Dictionary = {}
var _researched_ids: Array = []
var _known_manufacturer_ids: Array = []
var _ship_layout: Resource
var _health_fraction: float = 1.0

## Ship-wide upgrade unlocks: category key -> Array[String] of node ids
## (docs/design_handoff_upgrade_tree/README.md "State management"). Ids only,
## so adding upgrades to the catalog later never invalidates this. Deliberately
## NOT part of capture()/apply() below: those mirror one ship's state across a
## warp, whereas these are player progression that outlives any given hull, and
## this autoload already persists for the session.
var _upgrade_unlocks: Dictionary = {}
## Category the upgrade screen was last showing, restored when it reopens.
var last_upgrade_category: String = ""

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


# --- Ship-wide upgrade unlocks ----------------------------------------------
# Read and written through ShipUpgradeService; nothing else should touch
# _upgrade_unlocks directly.

func is_upgrade_unlocked(category_key: String, node_id: String) -> bool:
	return _upgrade_unlocks.get(category_key, []).has(node_id)


func unlock_upgrade(category_key: String, node_id: String) -> void:
	if not _upgrade_unlocks.has(category_key):
		_upgrade_unlocks[category_key] = []
	if not _upgrade_unlocks[category_key].has(node_id):
		_upgrade_unlocks[category_key].append(node_id)


func get_unlocked_upgrades(category_key: String) -> Array:
	return _upgrade_unlocks.get(category_key, []).duplicate()


func capture(ship: Node) -> void:
	var inventory: Node = ship.get_inventory()
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

	var inventory: Node = ship.get_inventory()
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

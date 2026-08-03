class_name Scanner
extends Node2D

## Long-range sensor pulse, distinct from RadarDisplay (broad live position
## blips, never identity). A single deliberate press channels briefly, then
## reveals category + distance for the closest handful of things around the
## ship in one shot — not a continuously updating display.
##
## Deliberately limited to "off the grid" objects — derelicts and natural
## phenomena, not active/living infrastructure (a home station is already
## known, not something to identify).
##
## Two kinds of result: individual objects (Planet, Wreck — anything in the
## "scannable" group, duck-typed against is_identified/scan_category/
## mark_identified, see scannable.gd) stay identified once scanned, flagged
## "already known" on a later pulse. Asteroids (the "asteroid" group) are
## instead reported as clusters — naming is purely a function of how many are
## grouped together (e.g. "Asteroid Cluster (6)"), not per-rock identity,
## since a dense field would otherwise fill every result slot with the same
## handful of nearby rocks.
signal scan_started
signal scan_progress_updated(fraction: float)
signal scan_completed(results: Array[Dictionary])
signal scan_cancelled

## Tripled from the original 1200 — off-screen asteroids/wrecks/planets were
## going undetected.
@export var scan_range: float = 3600.0
@export var channel_duration: float = 1.5
@export var max_results: int = 5

## Asteroids within this world-distance of any existing cluster member join
## that cluster (simple single-link chaining — same approximation RadarDisplay
## uses for its own, separate asteroid clustering).
const ASTEROID_CLUSTER_MERGE_DISTANCE: float = 300.0

@onready var _ship: Node2D = get_owner()

var _is_scanning: bool = false
var _elapsed: float = 0.0


func _physics_process(delta: float) -> void:
	if not _is_scanning:
		return

	_elapsed += delta
	scan_progress_updated.emit(clampf(_elapsed / channel_duration, 0.0, 1.0))

	if _elapsed >= channel_duration:
		_finish_scan()


## Bound to the "scan" input action: starts a new pulse if idle, cancels the
## current one if already channeling — one key doubles as start/cancel so
## there's no separate binding to remember.
func toggle_scan() -> void:
	if _is_scanning:
		_cancel()
		return

	_is_scanning = true
	_elapsed = 0.0
	scan_started.emit()
	scan_progress_updated.emit(0.0)


func is_scanning() -> bool:
	return _is_scanning


func _finish_scan() -> void:
	_is_scanning = false

	var candidates: Array[Dictionary] = []
	candidates.append_array(_gather_individual_candidates())
	candidates.append_array(_gather_asteroid_clusters())

	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var results: Array[Dictionary] = []
	for i in mini(max_results, candidates.size()):
		results.append(candidates[i])

	scan_completed.emit(results)


func _gather_individual_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("scannable"):
		if not (node is Node2D):
			continue
		var distance: float = _ship.global_position.distance_to((node as Node2D).global_position)
		if distance > scan_range:
			continue
		var already_known: bool = node.get("is_identified") == true
		if node.has_method("mark_identified"):
			node.mark_identified()
		candidates.append({
			"category": _category_of(node),
			"distance": distance,
			"already_known": already_known,
		})
	return candidates


func _gather_asteroid_clusters() -> Array[Dictionary]:
	var offsets: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("asteroid"):
		if not (node is Node2D):
			continue
		var offset: Vector2 = (node as Node2D).global_position - _ship.global_position
		if offset.length() <= scan_range:
			offsets.append(offset)

	var clusters: Array = []
	for offset in offsets:
		var joined_cluster: Array = []
		for cluster in clusters:
			for member in cluster:
				if (member as Vector2).distance_to(offset) <= ASTEROID_CLUSTER_MERGE_DISTANCE:
					joined_cluster = cluster
					break
			if not joined_cluster.is_empty():
				break
		if joined_cluster.is_empty():
			clusters.append([offset])
		else:
			joined_cluster.append(offset)

	var results: Array[Dictionary] = []
	for cluster in clusters:
		var centroid: Vector2 = Vector2.ZERO
		for member in cluster:
			centroid += member
		centroid /= cluster.size()
		results.append({
			"category": _cluster_category_name(cluster.size()),
			"distance": centroid.length(),
			"already_known": false,
		})
	return results


func _cluster_category_name(count: int) -> String:
	return "Asteroid" if count == 1 else "Asteroid Cluster (%d)" % count


func _category_of(target: Node2D) -> String:
	var category = target.get("scan_category")
	return category if category != null else "Unknown"


func _cancel() -> void:
	_is_scanning = false
	scan_cancelled.emit()

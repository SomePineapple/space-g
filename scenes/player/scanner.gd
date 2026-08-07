class_name Scanner
extends Node2D

## Directional time-of-flight sensor pulse, distinct from RadarDisplay (broad
## live position blips, never identity). The player aims a beam, fires once,
## and returns arrive progressively as the wavefront reaches each object
## (WAVEFRONT_SPEED units/sec, so a 2500u wreck resolves 2.5s after the ping).
## See docs/design_handoff_scanner_radar/README.md — this is the scan model
## behind option 1D, the A-scope the HUD draws.
##
## Contacts are sampled once, at the moment the ping fires, and never tracked
## afterwards: the display represents a snapshot of one pulse, so letting
## markers follow moving objects would break the fiction.
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
##
## Requires a Scanner hardpoint (see ModuleCatalog.SCANNER_HARDPOINT_TYPE_ID)
## — fire_ping() refuses to start a new pulse without one, and a pulse already
## in flight cancels itself if the module is lost mid-scan (destroyed in
## combat, removed in the builder, sensors powered down), same "destroyed
## hardpoint stops working" convention every other hardpoint follows.
signal scan_started
signal beam_changed(bearing_degrees: float, width_degrees: float)
## One contact's return reaching the ship — the display appends a row and a
## trace peak per emission rather than waiting for the whole pulse.
signal contact_resolved(contact: Dictionary)
signal scan_completed(results: Array[Dictionary])
signal scan_cancelled

## How fast the wavefront travels outward. Fixed by the design; range is the
## upgradeable stat, not speed.
const WAVEFRONT_SPEED: float = 1000.0
const MIN_BEAM_WIDTH: float = 6.0
const MAX_BEAM_WIDTH: float = 120.0

## Asteroids within this world-distance of any existing cluster member join
## that cluster (simple single-link chaining — same approximation RadarDisplay
## uses for its own, separate asteroid clustering).
const ASTEROID_CLUSTER_MERGE_DISTANCE: float = 300.0

## MAXR in the handoff. This is the stat scanner upgrades are meant to raise.
@export var scan_range: float = 3000.0
## Dead time after the wavefront completes before the emitter can fire again;
## a full cycle is scan_range / WAVEFRONT_SPEED + cooldown.
@export var cooldown: float = 6.0
## The "first n" cap — only the nearest this many contacts inside the beam are
## ever reported, however crowded the arc is.
@export var max_results: int = 5

@onready var _ship: Ship = get_owner()

## World-space bearing in degrees, 0 = +X, wrapped to -180..180. World rather
## than ship-relative so a snapshot stays put on the display while the ship
## turns underneath it.
var _beam_bearing: float = 0.0
var _beam_width: float = 40.0

var _is_scanning: bool = false
var _elapsed: float = 0.0
var _cooldown_remaining: float = 0.0
## Snapshot contacts still in flight, kept sorted nearest-first so arrivals
## always come off the front.
var _pending: Array[Dictionary] = []
var _hits: Array[Dictionary] = []


func _physics_process(delta: float) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	if not _is_scanning:
		return

	if not _ship.has_scanner():
		_cancel()
		return

	_elapsed += delta
	_resolve_arrivals()

	if get_reach() >= scan_range:
		_is_scanning = false
		scan_completed.emit(_hits)


## Bound to the "scan" input action via ShipIntent. Returns false (silently, as
## the design asks — the cooling-down button is the only feedback) when the
## emitter isn't ready or the ship has no working scanner.
func fire_ping() -> bool:
	if not _ship.has_scanner() or _cooldown_remaining > 0.0:
		return false

	_pending = _snapshot_contacts()
	_hits.clear()
	_elapsed = 0.0
	_is_scanning = true
	_cooldown_remaining = scan_range / WAVEFRONT_SPEED + cooldown
	scan_started.emit()
	return true


## Set by the HUD's beam bar. Width is clamped to the design's 6°–120°.
func set_beam(bearing_degrees: float, width_degrees: float) -> void:
	_beam_bearing = wrapf(bearing_degrees, -180.0, 180.0)
	_beam_width = clampf(width_degrees, MIN_BEAM_WIDTH, MAX_BEAM_WIDTH)
	beam_changed.emit(_beam_bearing, _beam_width)


func get_beam_bearing() -> float:
	return _beam_bearing


func get_beam_width() -> float:
	return _beam_width


func is_scanning() -> bool:
	return _is_scanning


## How far out the wavefront currently is, clamped to range.
func get_reach() -> float:
	return minf(_elapsed * WAVEFRONT_SPEED, scan_range)


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


func is_ready() -> bool:
	return _cooldown_remaining <= 0.0


## Contacts resolved so far by the current (or most recent) pulse. They persist
## until the next ping clears them — no fade-out, no timeout.
func get_hits() -> Array[Dictionary]:
	return _hits


## Which trace signature a scan category reads as. The handoff's placeholder
## set is rock/ice/wreck; "body" is this project's addition for planets, which
## the README explicitly invites ("extend TCOL and the strength table as real
## types are added"). Unrecognised categories fall back to ice.
static func signature_of(category: String) -> StringName:
	var lower: String = category.to_lower()
	if lower.contains("asteroid"):
		return &"rock"
	if lower.contains("wreck") or lower.contains("derelict"):
		return &"wreck"
	if lower.contains("planet"):
		return &"body"
	return &"ice"


## Everything inside the beam and inside range at fire time, nearest first,
## truncated to max_results.
func _snapshot_contacts() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	candidates.append_array(_gather_individual_candidates())
	candidates.append_array(_gather_asteroid_clusters())

	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var selected: Array[Dictionary] = []
	for i in mini(max_results, candidates.size()):
		selected.append(candidates[i])
	return selected


func _resolve_arrivals() -> void:
	var reach: float = get_reach()
	while not _pending.is_empty() and float(_pending[0]["distance"]) <= reach:
		var contact: Dictionary = _pending.pop_front()
		_hits.append(contact)
		contact_resolved.emit(contact)


func _gather_individual_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("scannable"):
		if not (node is Node2D):
			continue
		var offset: Vector2 = (node as Node2D).global_position - _ship.global_position
		if not _is_in_beam(offset):
			continue
		var already_known: bool = node.get("is_identified") == true
		# Identity is recorded when the pulse leaves, not when the return
		# arrives, so a scan cancelled mid-flight still can't un-know things
		# it had already lit up. Same point the previous scanner marked them.
		if node.has_method("mark_identified"):
			node.mark_identified()
		candidates.append(_make_contact(_category_of(node), offset, already_known))
	return candidates


func _gather_asteroid_clusters() -> Array[Dictionary]:
	var offsets: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("asteroid"):
		if not (node is Node2D):
			continue
		var offset: Vector2 = (node as Node2D).global_position - _ship.global_position
		if _is_in_beam(offset):
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
		results.append(_make_contact(_cluster_category_name(cluster.size()), centroid, false))
	return results


func _make_contact(category: String, offset: Vector2, already_known: bool) -> Dictionary:
	return {
		"category": category,
		"distance": offset.length(),
		"bearing": rad_to_deg(offset.angle()),
		"signature": signature_of(category),
		"already_known": already_known,
	}


## In range and inside the beam arc. Clusters are tested on their centroid,
## which is close enough at these arc widths.
func _is_in_beam(offset: Vector2) -> bool:
	if offset.length() > scan_range:
		return false
	var delta: float = wrapf(rad_to_deg(offset.angle()) - _beam_bearing, -180.0, 180.0)
	return absf(delta) <= _beam_width * 0.5


func _cluster_category_name(count: int) -> String:
	return "Asteroid" if count == 1 else "Asteroid Cluster (%d)" % count


func _category_of(target: Node2D) -> String:
	var category = target.get("scan_category")
	return category if category != null else "Unknown"


func _cancel() -> void:
	_is_scanning = false
	_pending.clear()
	scan_cancelled.emit()

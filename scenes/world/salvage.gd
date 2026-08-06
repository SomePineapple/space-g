class_name Salvage
extends Area2D

signal collected(item_id: String, amount: int)

enum Rarity { COMMON, UNCOMMON, RARE, EXPERIMENTAL, ARTEFACT }
## Phase 5.3: a drop carries either a raw material (existing behavior,
## material_id/material_amount) or a crafted component (component_id/
## component_amount) — never both. Lets combat/wreck salvage hand out
## already-crafted components directly, distinct from mining (Asteroid/
## HardpointGrinder never set this, so it stays MATERIAL for them).
enum Kind { MATERIAL, COMPONENT }

## Rarity is now purely a yield-size/visual tier — it no longer implies a
## material (see Phase 4.2). What material this salvage actually carries is
## set on material_id directly by whoever spawns it (Asteroid.roll_ore_material,
## HardpointGrinder, Ship's combat drop), independently of rarity.
## "visual_scale" and "spike_count" give higher rarities a bigger, spikier
## silhouette (0 spikes = plain glow, no overlay) so rarity reads at a
## glance without text — "pull_resistance" makes rarer salvage feel heavier
## on the tractor beam (see HardpointTractorBeam._pull_target). Color comes
## from the material itself (MaterialCatalog.color), not from rarity.
const RARITY_DATA: Dictionary = {
	Rarity.COMMON: {"amount": 10, "visual_scale": 1.0, "spike_count": 0, "pull_resistance": 1.0},
	Rarity.UNCOMMON: {"amount": 8, "visual_scale": 1.1, "spike_count": 4, "pull_resistance": 0.9},
	Rarity.RARE: {"amount": 5, "visual_scale": 1.2, "spike_count": 5, "pull_resistance": 0.8},
	Rarity.EXPERIMENTAL: {"amount": 12, "visual_scale": 1.35, "spike_count": 6, "pull_resistance": 0.65},
	Rarity.ARTEFACT: {"amount": 25, "visual_scale": 1.5, "spike_count": 8, "pull_resistance": 0.5},
}

const DANGER_COLOR: Color = Color(1.0, 0.15, 0.15)
const DANGER_PULSE_SPEED: float = 6.0
const DANGER_PULSE_STRENGTH: float = 0.7

const STAR_OUTER_RADIUS: float = 22.0
const STAR_INNER_RATIO: float = 0.5
const STAR_OUTLINE_WIDTH: float = 2.0
## Radians/sec per spike point — rarer (more spikes) items shimmer faster.
const SPIKE_ROTATION_SPEED: float = 0.6

@export var rarity: Rarity = Rarity.COMMON
@export var kind: Kind = Kind.MATERIAL
## Extra multiplier on top of rarity's base amount and the material's own
## yield_multiplier — set by the spawner before add_child (same convention as
## rarity/material_id) so e.g. HardpointGrinder can hand out more material per
## drop than a plain weapon kill without touching rarity or material data.
@export var amount_multiplier: float = 1.0
@export var drift_speed: float = 20.0
@export var is_dangerous: bool = false
@export var danger_damage: float = 15.0
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and collecting salvage will play it automatically.
@export var pickup_sound: AudioStream = null

var material_id: String = MaterialCatalog.IRON
var material_amount: int = 10
## Only meaningful when kind == COMPONENT — set by the spawner alongside kind
## (same convention as material_id), left empty/0 for ordinary material drops.
var component_id: String = ""
var component_amount: int = 0
var pull_resistance: float = 1.0
var _visual_scale: float = 1.0
var _spike_count: int = 0
var _drift_direction: Vector2 = Vector2.ZERO
var _base_color: Color
var _display_color: Color
var _time: float = 0.0
## Set when a pickup attempt is rejected for lack of cargo space, so
## _process() can keep retrying while the ship sits overlapped instead of
## the collection only ever getting one shot at body_entered — otherwise
## discarding cargo to make room wouldn't free a salvage node already
## touching the hull until it drifted away and back.
var _pending_pickup_body: Node = null

@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	add_to_group("salvage")
	body_entered.connect(_on_body_entered)
	var rng: RandomNumberGenerator = GameRng.stream("salvage")
	_drift_direction = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()

	var data: Dictionary = RARITY_DATA[rarity]
	if kind == Kind.COMPONENT:
		_base_color = ComponentCatalog.color(component_id)
		# Components have no MaterialType.yield_multiplier of their own —
		# amount_multiplier alone lets a spawner tune how generous its
		# component drops are relative to its material ones.
		component_amount = maxi(1, roundi(data["amount"] * amount_multiplier))
	else:
		_base_color = MaterialCatalog.color(material_id)
		# Rarer materials (see MaterialCatalog.yield_multiplier) yield less per
		# drop regardless of rarity tier; amount_multiplier layers a source-driven
		# boost on top (e.g. grinder fragments yield more than a weapon kill).
		var raw_amount: float = data["amount"] * MaterialCatalog.yield_multiplier(material_id) * amount_multiplier
		material_amount = maxi(1, roundi(raw_amount))
	_display_color = _base_color
	_visual.modulate = _base_color
	pull_resistance = data["pull_resistance"]
	_visual_scale = data["visual_scale"]
	_spike_count = data["spike_count"]
	_visual.scale *= _visual_scale

	set_process(is_dangerous or _spike_count > 0)


func _process(delta: float) -> void:
	_time += delta
	if is_dangerous:
		var pulse: float = (sin(_time * DANGER_PULSE_SPEED) + 1.0) * 0.5
		_display_color = _base_color.lerp(DANGER_COLOR, pulse * DANGER_PULSE_STRENGTH)
		_visual.modulate = _display_color

	if _spike_count > 0:
		rotation += SPIKE_ROTATION_SPEED * _spike_count * delta
		queue_redraw()

	if _pending_pickup_body != null:
		if is_instance_valid(_pending_pickup_body) and overlaps_body(_pending_pickup_body):
			if _is_near_core(_pending_pickup_body) and _try_collect(_pending_pickup_body):
				_pending_pickup_body = null
		else:
			_pending_pickup_body = null
		if _pending_pickup_body == null and not (is_dangerous or _spike_count > 0):
			set_process(false)


## Higher rarities get a spikier star silhouette layered over the glow
## sprite, so rarity reads from shape alone, not just color.
func _draw() -> void:
	if _spike_count <= 0:
		return

	var outer_radius: float = STAR_OUTER_RADIUS * _visual_scale
	var inner_radius: float = outer_radius * STAR_INNER_RATIO
	var point_count: int = _spike_count * 2
	var points := PackedVector2Array()
	for i in point_count:
		var point_radius: float = outer_radius if i % 2 == 0 else inner_radius
		var angle: float = TAU * i / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * point_radius)
	points.append(points[0])

	draw_polyline(points, _display_color, STAR_OUTLINE_WIDTH)


func _physics_process(delta: float) -> void:
	position += _drift_direction * drift_speed * delta


func pull_toward(target_position: Vector2, speed: float, delta: float) -> void:
	global_position = global_position.move_toward(target_position, speed * delta)


## Touching the hull alone is not enough — plain drift-in contact (no
## Tractor Beam) only collects once the item actually reaches the Command
## Core specifically (see _is_near_core), so a piece that merely grazes an
## outer hex keeps drifting instead of vanishing on first touch. Always
## defers to the _process() retry loop rather than collecting immediately,
## so the core-distance check re-runs every frame the item stays overlapped
## (it may still be drifting closer when this first fires).
func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player_ship"):
		return
	_pending_pickup_body = body
	set_process(true)


## True once body is close enough to its own Command Core to count as a real
## hull pickup, not just a graze on an outer module — see
## Ship.get_core_global_position/get_core_collect_radius. Ships without the
## concept (shouldn't happen — every Ship has one) just collect on touch.
func _is_near_core(body: Node) -> bool:
	if not body.has_method("get_core_global_position"):
		return true
	var core_position: Vector2 = body.get_core_global_position()
	var collect_radius: float = body.get_core_collect_radius() if body.has_method("get_core_collect_radius") else 0.0
	return global_position.distance_to(core_position) <= collect_radius


## Force-attempts collection against body regardless of physical Area2D
## overlap or Core proximity — used by HardpointTractorBeam once a pulled
## item reaches the beam's own position, which isn't guaranteed to sit
## inside the ship's hull collision shapes or near the Core hex.
func collect_for(body: Node) -> bool:
	return _try_collect(body)


## Attempts to hand this salvage's material to body. Returns false without
## freeing the node if cargo is full (see try_add_material) — the node is
## left in place, overlapping the ship, and _process() retries every frame
## until capacity frees up or the ship moves away.
func _try_collect(body: Node) -> bool:
	if kind == Kind.COMPONENT:
		if body.has_method("try_add_component"):
			if not body.try_add_component(component_id, component_amount):
				_pending_pickup_body = body
				set_process(true)
				return false
		elif body.has_method("add_component"):
			body.add_component(component_id, component_amount)
	else:
		if body.has_method("try_add_material"):
			if not body.try_add_material(material_id, material_amount):
				_pending_pickup_body = body
				set_process(true)
				return false
		elif body.has_method("add_material"):
			body.add_material(material_id, material_amount)

	if is_dangerous and body.has_method("take_damage"):
		body.take_damage(danger_damage)
	if kind == Kind.COMPONENT:
		collected.emit(component_id, component_amount)
	else:
		collected.emit(material_id, material_amount)
	_play_pickup_sound()
	# Deferred: this runs from within the physics engine's collision query
	# flush (body_entered), where freeing a CollisionObject2D synchronously
	# triggers a physics server error.
	queue_free.call_deferred()
	return true


## Spawned detached (rather than as a child) so the sound survives this
## node's own queue_free() and can finish playing before it frees itself.
func _play_pickup_sound() -> void:
	if pickup_sound == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = pickup_sound
	player.global_position = global_position
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

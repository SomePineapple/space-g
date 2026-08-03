class_name Salvage
extends Area2D

signal collected(material_id: String, amount: int)

enum Rarity { COMMON, ELECTRONICS, ENERGY, EXPERIMENTAL, ARTEFACT }

## Experimental/Artefact tiers reuse the existing three material types at
## larger amounts until dedicated rarer materials (Alien Biomatter, Rare
## Crystals, ...) are added in a later increment.
## "visual_scale" and "spike_count" give higher rarities a bigger, spikier
## silhouette (0 spikes = plain glow, no overlay) so rarity reads at a
## glance without text — "pull_resistance" makes rarer salvage feel heavier
## on the tractor beam (see HardpointTractorBeam._pull_target).
const RARITY_DATA: Dictionary = {
	Rarity.COMMON: {"color": Color(0.75, 0.78, 0.8), "material": Materials.STEEL_ALLOY, "amount": 10,
		"visual_scale": 1.0, "spike_count": 0, "pull_resistance": 1.0},
	Rarity.ELECTRONICS: {"color": Color(0.3, 0.6, 1.0), "material": Materials.ELECTRONICS, "amount": 8,
		"visual_scale": 1.1, "spike_count": 4, "pull_resistance": 0.9},
	Rarity.ENERGY: {"color": Color(0.3, 1.0, 0.5), "material": Materials.REACTOR_COMPONENTS, "amount": 5,
		"visual_scale": 1.2, "spike_count": 5, "pull_resistance": 0.8},
	Rarity.EXPERIMENTAL: {"color": Color(0.7, 0.3, 1.0), "material": Materials.REACTOR_COMPONENTS, "amount": 12,
		"visual_scale": 1.35, "spike_count": 6, "pull_resistance": 0.65},
	Rarity.ARTEFACT: {"color": Color(1.0, 0.85, 0.3), "material": Materials.ELECTRONICS, "amount": 25,
		"visual_scale": 1.5, "spike_count": 8, "pull_resistance": 0.5},
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
@export var drift_speed: float = 20.0
@export var is_dangerous: bool = false
@export var danger_damage: float = 15.0
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and collecting salvage will play it automatically.
@export var pickup_sound: AudioStream = null

var material_id: String = Materials.STEEL_ALLOY
var material_amount: int = 10
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
	_drift_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

	var data: Dictionary = RARITY_DATA[rarity]
	_base_color = data["color"]
	_display_color = _base_color
	_visual.modulate = _base_color
	material_id = data["material"]
	material_amount = data["amount"]
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
			if _try_collect(_pending_pickup_body):
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


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player_ship"):
		return
	_try_collect(body)


## Attempts to hand this salvage's material to body. Returns false without
## freeing the node if cargo is full (see try_add_material) — the node is
## left in place, overlapping the ship, and _process() retries every frame
## until capacity frees up or the ship moves away.
func _try_collect(body: Node) -> bool:
	if body.has_method("try_add_material"):
		if not body.try_add_material(material_id, material_amount):
			_pending_pickup_body = body
			set_process(true)
			return false
	elif body.has_method("add_material"):
		body.add_material(material_id, material_amount)

	if is_dangerous and body.has_method("take_damage"):
		body.take_damage(danger_damage)
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

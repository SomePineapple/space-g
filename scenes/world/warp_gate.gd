class_name WarpGate
extends Area2D

## GATE: instant scene change to another region (see GameState) — used for
## destinations you can't reach any other way, like a distant galaxy. Always
## built in a pair: the destination scene has its own GATE-mode WarpGate
## naming this one (by node name) as ITS destination_arrival_node_name, so
## arriving always lands you on a gate, not wherever that scene's Ship
## happens to sit.
## SPEED_LANE: a dramatic high-speed dash to a marker within the *same*
## scene — a shortcut across a region you could otherwise fly to normally.
## Always built in a pair too (see map_tester.tscn), so a lane can be ridden
## both ways.
enum WarpMode { GATE, SPEED_LANE }

@export var mode: WarpMode = WarpMode.GATE
@export var ring_radius: float = 60.0
@export var ring_color: Color = Color(0.3, 0.9, 1.0, 1.0)

## GATE mode only. destination_arrival_node_name is looked up (by name, in
## the destination scene's root) once loaded, and the ship is placed there —
## normally the paired WarpGate on the other side.
@export var destination_scene: String = ""
@export var destination_arrival_node_name: String = ""

## SPEED_LANE mode only: a Node2D elsewhere in the same scene the ship dashes
## to — normally the paired gate.
@export var destination_marker_path: NodePath = NodePath()
## Seconds the ship is held in place (screen shake ramping up) before the
## fling — the "charging up" beat.
@export var speed_lane_hold_duration: float = 2.5
## Shake magnitude reached by the end of the hold.
@export var speed_lane_hold_max_shake: float = 26.0
## Dash speed in px/sec — roughly 40% of a punchier ~4000 px/s "full" warp
## speed, per design: slow enough that the streaking is actually visible
## rather than an instant teleport.
@export var speed_lane_dash_speed: float = 1600.0

@onready var _ring: Line2D = $Ring
@onready var _collision: CollisionShape2D = $Collision
@onready var _prompt: Label = $Prompt

var _ship: Ship
var _jumping: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CircleShape2D.new()
	shape.radius = ring_radius
	_collision.shape = shape

	var points: PackedVector2Array = PackedVector2Array()
	const SEGMENTS: int = 32
	for i in SEGMENTS + 1:
		var angle: float = TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle), sin(angle)) * ring_radius)
	_ring.points = points
	_ring.default_color = ring_color
	_ring.width = 4.0
	_ring.self_modulate = Color(1.4, 1.4, 1.4, 1.0)

	_prompt.text = "E: Warp" if mode == WarpMode.GATE else "E: Speed Jump"
	_prompt.visible = false

	# Kick off the destination's load the instant this gate exists, not when
	# the player reaches it — hides the change_scene_to_file stall behind
	# normal flight time instead of causing it mid-warp. See GameState.
	if mode == WarpMode.GATE and not destination_scene.is_empty():
		GameState.request_scene_preload(destination_scene)


func _on_body_entered(body: Node) -> void:
	if body is Ship and body.is_in_group("player_ship"):
		_ship = body
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body == _ship:
		_ship = null
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _ship == null or _jumping:
		return
	if not event.is_action_pressed("interact"):
		return

	if mode == WarpMode.GATE:
		if destination_scene.is_empty():
			return
		GameState.capture(_ship)
		GameState.pending_arrival_node_name = destination_arrival_node_name

		# Use the background-loaded PackedScene if it's ready (the common
		# case — it's been loading since this gate's _ready()); otherwise
		# fall back to the old blocking load rather than fail the warp.
		var preloaded: PackedScene = GameState.get_preloaded_scene(destination_scene)
		if preloaded != null:
			get_tree().change_scene_to_packed(preloaded)
		else:
			get_tree().change_scene_to_file(destination_scene)
	else:
		_do_speed_jump()


## Holds the ship in place with ramping camera shake, then dashes it to
## destination_marker_path at a fixed speed (so duration scales with
## distance rather than always taking the same time regardless of how far
## the pair is apart). Suspends normal ship control for the whole sequence
## the same way an open menu panel does (see ship_input.gd's _is_menu_open),
## via a throwaway node in the "menu_panel" group, so the player can't fight
## the hold or the dash.
func _do_speed_jump() -> void:
	var marker: Node2D = get_node_or_null(destination_marker_path)
	if marker == null:
		return

	var ship_ref: Ship = _ship
	_jumping = true

	var control_lock := Node2D.new()
	control_lock.add_to_group("menu_panel")
	control_lock.visible = true
	get_tree().current_scene.add_child(control_lock)

	var camera: Camera2D = ship_ref.get_node("ShipCamera")
	ship_ref.velocity = Vector2.ZERO

	if camera.has_method("add_shake"):
		var hold_tween: Tween = create_tween()
		hold_tween.tween_method(camera.add_shake, 0.0, speed_lane_hold_max_shake, speed_lane_hold_duration)
		await hold_tween.finished
	else:
		await get_tree().create_timer(speed_lane_hold_duration).timeout

	# The dash itself needs the camera pinned exactly to the ship every
	# frame — Camera2D's own position smoothing can't keep up with a fast
	# tweened position jump and visibly lags behind ("loses" the ship).
	var was_smoothing: bool = camera.position_smoothing_enabled
	camera.position_smoothing_enabled = false

	var travel_direction: Vector2 = (marker.global_position - ship_ref.global_position)
	var distance: float = travel_direction.length()
	var speed_lines: GPUParticles2D = _spawn_speed_lines(ship_ref, travel_direction)

	var travel_time: float = maxf(distance / speed_lane_dash_speed, 0.05)
	var dash_tween: Tween = create_tween()
	dash_tween.set_ease(Tween.EASE_IN)
	dash_tween.set_trans(Tween.TRANS_CUBIC)
	dash_tween.tween_property(ship_ref, "global_position", marker.global_position, travel_time)
	await dash_tween.finished

	ship_ref.velocity = Vector2.ZERO
	camera.position_smoothing_enabled = was_smoothing
	_stop_speed_lines(speed_lines)
	control_lock.queue_free()
	_jumping = false


## White streak lines shooting backward past the ship (additive-blend,
## trailed particles) — reads as speed even though the ship itself is
## silhouette-simple. Parented to the ship and in global coordinate space
## (local_coords = false) so they line up with the actual travel direction
## regardless of the ship's own rotation.
## Cached rather than built fresh per jump (see _canvas_material_cache) — the
## only thing that ever changes between jumps is direction, updated in place
## below.
static var _process_material_cache: ParticleProcessMaterial
static var _canvas_material_cache: CanvasItemMaterial


func _speed_lines_process_material(backward: Vector2) -> ParticleProcessMaterial:
	if _process_material_cache == null:
		var process_material := ParticleProcessMaterial.new()
		process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process_material.emission_sphere_radius = 50.0
		process_material.spread = 3.0
		process_material.initial_velocity_min = 1400.0
		process_material.initial_velocity_max = 2200.0
		process_material.gravity = Vector3.ZERO
		process_material.scale_min = 0.5
		process_material.scale_max = 0.9

		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var gradient_texture := GradientTexture1D.new()
		gradient_texture.gradient = gradient
		process_material.color_ramp = gradient_texture

		_process_material_cache = process_material

	_process_material_cache.direction = Vector3(backward.x, backward.y, 0.0)
	return _process_material_cache


func _speed_lines_canvas_material() -> CanvasItemMaterial:
	if _canvas_material_cache == null:
		_canvas_material_cache = CanvasItemMaterial.new()
		_canvas_material_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _canvas_material_cache


## White streak lines shooting backward past the ship (additive-blend,
## trailed particles) — reads as speed even though the ship itself is
## silhouette-simple. Parented to the ship and in global coordinate space
## (local_coords = false) so they line up with the actual travel direction
## regardless of the ship's own rotation.
func _spawn_speed_lines(ship_ref: Ship, travel_direction: Vector2) -> GPUParticles2D:
	var backward: Vector2 = -travel_direction.normalized()

	var particles := GPUParticles2D.new()
	particles.local_coords = false
	particles.amount = 40
	particles.lifetime = 0.4
	particles.trail_enabled = true
	particles.trail_lifetime = 0.5
	particles.texture = preload("res://scenes/player/engine_particle_glow.tres")
	particles.process_material = _speed_lines_process_material(backward)
	particles.material = _speed_lines_canvas_material()
	particles.emitting = true

	ship_ref.add_child(particles)
	return particles


func _stop_speed_lines(particles: GPUParticles2D) -> void:
	if particles == null:
		return
	particles.emitting = false
	get_tree().create_timer(particles.lifetime + particles.trail_lifetime).timeout.connect(
		func(): if is_instance_valid(particles): particles.queue_free()
	)

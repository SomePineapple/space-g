extends ParallaxLayer

@export var star_count: int = 120
@export var field_size: Vector2 = Vector2(1024, 1024)
@export var min_star_size: float = 1.0
@export var max_star_size: float = 2.0
@export var min_brightness: float = 0.4
@export var max_brightness: float = 1.0
@export var tint_saturation: float = 0.25
@export var random_seed: int = 1

@export var flicker_chance: float = 0.0
@export var flicker_strength: float = 0.45
@export var flicker_speed_min: float = 0.4
@export var flicker_speed_max: float = 1.0

## Non-flickering stars are drawn once into this child and never redrawn —
## flickering stars are the only ones that need a per-frame queue_redraw(),
## and they're usually a small fraction of star_count.
var _static_canvas: Node2D
var _flicker_stars: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	motion_mirroring = field_size

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var static_stars: Array[Dictionary] = []
	_flicker_stars.clear()

	for i in star_count:
		var hue: float = rng.randf()
		var color: Color = Color.from_hsv(hue, tint_saturation, 1.0)
		var flickers: bool = rng.randf() < flicker_chance
		var radius: float = rng.randf_range(min_star_size, max_star_size)
		var brightness: float = max_brightness if flickers else rng.randf_range(min_brightness, max_brightness)
		if flickers:
			radius = max_star_size
		var star: Dictionary = {
			"position": Vector2(rng.randf_range(0.0, field_size.x), rng.randf_range(0.0, field_size.y)),
			"radius": radius,
			"brightness": brightness,
			"color": color,
			"flicker_phase": rng.randf() * TAU,
			"flicker_speed": rng.randf_range(flicker_speed_min, flicker_speed_max),
		}
		if flickers:
			_flicker_stars.append(star)
		else:
			static_stars.append(star)

	_static_canvas = Node2D.new()
	add_child(_static_canvas)
	_static_canvas.draw.connect(_draw_static_stars.bind(_static_canvas, static_stars))
	_static_canvas.queue_redraw()

	set_process(not _flicker_stars.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw_static_stars(canvas: CanvasItem, stars: Array[Dictionary]) -> void:
	for star in stars:
		var color: Color = star["color"]
		var brightness: float = star["brightness"]
		canvas.draw_circle(star["position"], star["radius"], Color(color.r * brightness, color.g * brightness, color.b * brightness, 1.0))


func _draw() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return

	var half_view_size: Vector2 = get_viewport().get_visible_rect().size / camera.zoom * 0.5
	var view_margin: float = max_star_size * 4.0
	half_view_size += Vector2(view_margin, view_margin)
	var view_center_local: Vector2 = to_local(camera.get_screen_center_position())

	for star in _flicker_stars:
		if not _is_star_in_view(star["position"], view_center_local, half_view_size):
			continue

		var color: Color = star["color"]
		var brightness: float = star["brightness"]
		var radius: float = star["radius"]
		var pulse: float = (sin(_time * star["flicker_speed"] + star["flicker_phase"]) + 1.0) * 0.5
		var dip: float = 1.0 - flicker_strength * pulse
		brightness *= dip
		radius *= lerp(0.6, 1.0, dip)
		draw_circle(star["position"], radius, Color(color.r * brightness, color.g * brightness, color.b * brightness, 1.0))


func _is_star_in_view(star_local_pos: Vector2, view_center_local: Vector2, half_view_size: Vector2) -> bool:
	# Stars tile every field_size (motion_mirroring); wrap the delta to the
	# nearest mirrored copy so visibility is correct regardless of which
	# tile repetition the camera currently sits in.
	var delta: Vector2 = star_local_pos - view_center_local
	delta.x = wrapf(delta.x, -field_size.x * 0.5, field_size.x * 0.5)
	delta.y = wrapf(delta.y, -field_size.y * 0.5, field_size.y * 0.5)
	return absf(delta.x) <= half_view_size.x and absf(delta.y) <= half_view_size.y

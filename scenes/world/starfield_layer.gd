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

var _stars: Array[Dictionary] = []
var _has_flickering_stars: bool = false
var _time: float = 0.0


func _ready() -> void:
	motion_mirroring = field_size

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	_stars.clear()
	for i in star_count:
		var hue: float = rng.randf()
		var color: Color = Color.from_hsv(hue, tint_saturation, 1.0)
		var flickers: bool = rng.randf() < flicker_chance
		_has_flickering_stars = _has_flickering_stars or flickers
		var radius: float = rng.randf_range(min_star_size, max_star_size)
		var brightness: float = max_brightness if flickers else rng.randf_range(min_brightness, max_brightness)
		if flickers:
			radius = max_star_size
		_stars.append({
			"position": Vector2(rng.randf_range(0.0, field_size.x), rng.randf_range(0.0, field_size.y)),
			"radius": radius,
			"brightness": brightness,
			"color": color,
			"flickers": flickers,
			"flicker_phase": rng.randf() * TAU,
			"flicker_speed": rng.randf_range(flicker_speed_min, flicker_speed_max),
		})

	set_process(_has_flickering_stars)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for star in _stars:
		var color: Color = star["color"]
		var brightness: float = star["brightness"]
		var radius: float = star["radius"]
		if star["flickers"]:
			var pulse: float = (sin(_time * star["flicker_speed"] + star["flicker_phase"]) + 1.0) * 0.5
			var dip: float = 1.0 - flicker_strength * pulse
			brightness *= dip
			radius *= lerp(0.6, 1.0, dip)
		draw_circle(star["position"], radius, Color(color.r * brightness, color.g * brightness, color.b * brightness, 1.0))

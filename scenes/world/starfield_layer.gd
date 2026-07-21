extends ParallaxLayer

@export var star_count: int = 120
@export var field_size: Vector2 = Vector2(1024, 1024)
@export var min_star_size: float = 1.0
@export var max_star_size: float = 2.0
@export var min_brightness: float = 0.4
@export var max_brightness: float = 1.0
@export var tint_saturation: float = 0.25
@export var random_seed: int = 1

var _stars: Array[Dictionary] = []


func _ready() -> void:
	motion_mirroring = field_size

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	_stars.clear()
	for i in star_count:
		var hue: float = rng.randf()
		var color: Color = Color.from_hsv(hue, tint_saturation, 1.0)
		_stars.append({
			"position": Vector2(rng.randf_range(0.0, field_size.x), rng.randf_range(0.0, field_size.y)),
			"radius": rng.randf_range(min_star_size, max_star_size),
			"brightness": rng.randf_range(min_brightness, max_brightness),
			"color": color,
		})

	queue_redraw()


func _draw() -> void:
	for star in _stars:
		var color: Color = star["color"]
		draw_circle(star["position"], star["radius"], Color(color.r, color.g, color.b, star["brightness"]))

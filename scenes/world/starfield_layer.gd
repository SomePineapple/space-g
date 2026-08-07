extends ParallaxLayer

@export var star_count: int = 120
@export var field_size: Vector2 = Vector2(1024, 1024)
## Kept above ~1px so stars don't alias to on/off between frames on
## smaller/lower-res screens as the parallax layer scrolls sub-pixel amounts.
@export var min_star_size: float = 1.2
@export var max_star_size: float = 2.0
@export var min_brightness: float = 0.4
@export var max_brightness: float = 1.0
@export var tint_saturation: float = 0.25
@export var random_seed: int = 1

@export var flicker_chance: float = 0.0
@export var flicker_strength: float = 0.45
@export var flicker_speed_min: float = 0.4
@export var flicker_speed_max: float = 1.0

const STAR_SHADER: Shader = preload("res://scenes/world/starfield_star.gdshader")

## The entire layer is one MultiMesh, so a 2000-star field is a single draw call
## rather than 2000 — and motion_mirroring re-renders this item's whole tree per
## visible tile, so the old per-star draw_circle() cost was multiplied again by
## up to four. Flicker lives in starfield_star.gdshader (fed by per-instance
## custom data), so steady and flickering stars share the one batch and nothing
## here runs per frame.
var _multimesh: MultiMesh


func _ready() -> void:
	motion_mirroring = field_size

	var star_material := ShaderMaterial.new()
	star_material.shader = STAR_SHADER
	material = star_material

	_build_stars()


func _build_stars() -> void:
	if star_count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	# Unit quad: the per-instance transform scales it to the star's diameter,
	# and the shader shades it into a disc.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = star_count

	for i in star_count:
		var hue: float = rng.randf()
		var color: Color = Color.from_hsv(hue, tint_saturation, 1.0)
		var flickers: bool = rng.randf() < flicker_chance
		var radius: float = rng.randf_range(min_star_size, max_star_size)
		var brightness: float = max_brightness if flickers else rng.randf_range(min_brightness, max_brightness)
		if flickers:
			radius = max_star_size
		var star_position := Vector2(rng.randf_range(0.0, field_size.x), rng.randf_range(0.0, field_size.y))
		var flicker_phase: float = rng.randf() * TAU
		var flicker_speed: float = rng.randf_range(flicker_speed_min, flicker_speed_max)

		_multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ONE * radius * 2.0, 0.0, star_position))
		_multimesh.set_instance_color(i, Color(color.r * brightness, color.g * brightness, color.b * brightness, 1.0))
		_multimesh.set_instance_custom_data(i, Color(flicker_speed, flicker_phase, flicker_strength if flickers else 0.0, 0.0))

	queue_redraw()


func _draw() -> void:
	if _multimesh == null:
		return
	draw_multimesh(_multimesh, null)

class_name BuilderBackdrop
extends Control

## Full-bleed background for the ship builder: near-black base, two soft
## radial glows, and a handful of slowly drifting star dots (handoff README
## "Background").
##
## Drawn rather than assembled from TextureRects because it is three
## stretched gradients and five dots — nodes would be more state to keep in
## sync with the screen size for no gain.

const GLOW_WARM: Color = Color(0.1647, 0.2353, 0.2941, 0.35)  # rgba(42,60,75,0.35)
const GLOW_COOL: Color = Color(0.1647, 0.3529, 0.3922, 0.18)  # rgba(42,90,100,0.18)

## Star field: fraction-of-screen position, brightness, and the size of the
## tile it wraps within (all from the handoff's five radial-gradient dots).
const STARS: Array[Dictionary] = [
	{"at": Vector2(0.20, 0.30), "alpha": 0.50, "tile": Vector2(600, 600)},
	{"at": Vector2(0.70, 0.60), "alpha": 0.35, "tile": Vector2(500, 500)},
	{"at": Vector2(0.40, 0.80), "alpha": 0.40, "tile": Vector2(700, 700)},
	{"at": Vector2(0.85, 0.25), "alpha": 0.30, "tile": Vector2(400, 400)},
	{"at": Vector2(0.55, 0.15), "alpha": 0.40, "tile": Vector2(550, 550)},
]

## One full drift cycle takes 90s, matching the reference animation.
const DRIFT_PERIOD: float = 90.0
const DRIFT_TRAVEL: Vector2 = Vector2(-600, 300)

var _glow_texture: GradientTexture2D
var _elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ...and_offsets_preset, not set_anchors_preset: the latter keeps the
	# control's current (zero) rect by writing compensating offsets.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_texture = _make_radial_texture()


## A white-to-transparent radial ramp, tinted per use via draw_texture_rect's
## modulate — one texture serves both glows.
func _make_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 1.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


func _process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta, DRIFT_PERIOD)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BuilderTheme.BG_BASE, true)
	_draw_glow(Vector2(0.30, 0.80), Vector2(900, 700), GLOW_WARM)
	_draw_glow(Vector2(0.90, 0.10), Vector2(700, 500), GLOW_COOL)
	_draw_stars()


func _draw_glow(centre_fraction: Vector2, extent: Vector2, color: Color) -> void:
	var centre: Vector2 = size * centre_fraction
	draw_texture_rect(_glow_texture, Rect2(centre - extent * 0.5, extent), false, color)


func _draw_stars() -> void:
	var drift: Vector2 = DRIFT_TRAVEL * (_elapsed / DRIFT_PERIOD)
	for star in STARS:
		var tile: Vector2 = star["tile"]
		var origin: Vector2 = size * (star["at"] as Vector2) + drift
		# Wrap within the star's own tile so a dot leaving one edge reappears
		# rather than the field emptying over the 90s cycle.
		var wrapped := Vector2(fposmod(origin.x, tile.x), fposmod(origin.y, tile.y))
		while wrapped.x < size.x:
			var y: float = wrapped.y
			while y < size.y:
				draw_circle(Vector2(wrapped.x, y), 1.0, Color(1, 1, 1, star["alpha"]))
				y += tile.y
			wrapped.x += tile.x

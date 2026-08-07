class_name MarketBackdrop
extends Control

## The Exchange screen's two full-bleed background layers: a pair of soft
## corner glows over near-black, and a 96px cyan grid at half opacity
## (docs/design_handoff_trade_market/README.md "Layout").
##
## Drawn rather than assembled from nodes — it is two stretched gradients and
## a line grid, so nodes would only add state to keep in sync with the screen
## size. It is also static: the handoff is explicit that all movement on this
## screen should come from data changing, not from decoration.

## rgba(42,90,100,0.20) at 12% / 100%, extent 1100 x 700.
const GLOW_LOW: Color = Color(0.1647, 0.3529, 0.3922, 0.20)
const GLOW_LOW_AT: Vector2 = Vector2(0.12, 1.00)
const GLOW_LOW_EXTENT: Vector2 = Vector2(2200, 1400)

## rgba(60,72,88,0.24) at 92% / 0%, extent 900 x 600.
const GLOW_HIGH: Color = Color(0.2353, 0.2824, 0.3451, 0.24)
const GLOW_HIGH_AT: Vector2 = Vector2(0.92, 0.00)
const GLOW_HIGH_EXTENT: Vector2 = Vector2(1800, 1200)

const GRID_SPACING: float = 96.0
## The handoff's 0.05/0.04 cyan, already multiplied by the layer's 0.5 opacity.
const GRID_VERTICAL: Color = Color(0.3333, 0.8392, 0.9098, 0.025)
const GRID_HORIZONTAL: Color = Color(0.3333, 0.8392, 0.9098, 0.020)

var _glow_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ...and_offsets_preset, not set_anchors_preset: the latter preserves the
	# control's current (zero) rect by writing compensating offsets.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_texture = _make_radial_texture()
	resized.connect(queue_redraw)


## White-to-transparent radial ramp, tinted per use via draw_texture_rect's
## modulate — one texture serves both glows.
func _make_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MarketTheme.SCREEN_BG, true)
	_draw_glow(GLOW_LOW_AT, GLOW_LOW_EXTENT, GLOW_LOW)
	_draw_glow(GLOW_HIGH_AT, GLOW_HIGH_EXTENT, GLOW_HIGH)
	_draw_grid()


func _draw_glow(centre_fraction: Vector2, extent: Vector2, color: Color) -> void:
	var centre: Vector2 = size * centre_fraction
	draw_texture_rect(_glow_texture, Rect2(centre - extent * 0.5, extent), false, color)


func _draw_grid() -> void:
	var x: float = 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_VERTICAL, 1.0)
		x += GRID_SPACING
	var y: float = 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_HORIZONTAL, 1.0)
		y += GRID_SPACING

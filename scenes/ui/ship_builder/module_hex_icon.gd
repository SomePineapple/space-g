class_name ModuleHexIcon
extends Control

## The small hex icon shown next to a module in the builder's module list.
##
## The handoff specifies a gradient-filled hex with a 2-letter glyph
## placeholder "to swap for real module icon art when available". This project
## already has that art (ModuleType.faction_hex_textures), so the real hex
## texture is drawn when one exists and the gradient + glyph is the fallback
## for the module types that still have none (Railgun, Phase Lance, the
## higher weapon tiers on some factions).

## Reference sizes from the handoff: 38x44 normally, 48x55 when the row is
## selected. Both are the 222:256 hex ratio.
const SIZE_DEFAULT: Vector2 = Vector2(38, 44)
const SIZE_SELECTED: Vector2 = Vector2(48, 55)
const GLYPH_SIZE_DEFAULT: int = 10
const GLYPH_SIZE_SELECTED: int = 12

const BADGE_BG: Color = Color(0.0392, 0.0510, 0.0706)  # 0a0d12
const BADGE_FONT_SIZE: int = 9

## Direction of the handoff's `linear-gradient(155deg, ...)`, in the same
## screen space the hex is drawn in.
const GRADIENT_ANGLE_DEGREES: float = 155.0

var module_type: ModuleType
var faction_id: String = "corporate"
var owned_count: int = 0
var selected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The hex art is authored far larger than this icon renders at; without a
	# mip chain it shimmers (see CLAUDE.md "Texture import settings").
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_apply_size()


func configure(new_module_type: ModuleType, new_faction_id: String, new_owned_count: int) -> void:
	module_type = new_module_type
	faction_id = new_faction_id
	owned_count = new_owned_count
	queue_redraw()


func set_selected(is_selected: bool) -> void:
	if selected == is_selected:
		return
	selected = is_selected
	_apply_size()
	queue_redraw()


func _apply_size() -> void:
	custom_minimum_size = SIZE_SELECTED if selected else SIZE_DEFAULT


func _draw() -> void:
	if module_type == null:
		return

	# custom_minimum_size drives the row's layout, but the control itself may
	# be stretched taller by the row — keep the hex at its own aspect.
	var icon_size: Vector2 = SIZE_SELECTED if selected else SIZE_DEFAULT
	var centre: Vector2 = Vector2(icon_size.x * 0.5, size.y * 0.5)
	var corners: PackedVector2Array = HexUtils.hex_corners(centre, icon_size.y * 0.5)

	var texture: Texture2D = module_type.get_hex_texture_for_cell(faction_id, 0)
	if texture != null:
		draw_colored_polygon(corners, Color.WHITE, HexUtils.hex_uv_corners(), texture)
	else:
		_draw_gradient_hex(corners)
		_draw_glyph(centre, icon_size)

	if owned_count > 0:
		_draw_owned_badge(icon_size)


func _draw_gradient_hex(corners: PackedVector2Array) -> void:
	var colors: Array = ModulePresentation.gradient(module_type)
	var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(GRADIENT_ANGLE_DEGREES))

	var projections: PackedFloat32Array = PackedFloat32Array()
	var lowest: float = INF
	var highest: float = -INF
	for corner in corners:
		var projection: float = corner.dot(axis)
		projections.append(projection)
		lowest = minf(lowest, projection)
		highest = maxf(highest, projection)

	var vertex_colors := PackedColorArray()
	var span: float = maxf(highest - lowest, 0.001)
	for projection in projections:
		vertex_colors.append(colors[0].lerp(colors[1], (projection - lowest) / span))
	draw_polygon(corners, vertex_colors)


func _draw_glyph(centre: Vector2, icon_size: Vector2) -> void:
	var font: Font = BuilderTheme.mono_font()
	var font_size: int = GLYPH_SIZE_SELECTED if selected else GLYPH_SIZE_DEFAULT
	var baseline: Vector2 = Vector2(0, centre.y + font_size * 0.36)
	font.draw_string(get_canvas_item(), baseline, ModulePresentation.glyph(module_type),
		HORIZONTAL_ALIGNMENT_CENTER, icon_size.x, font_size, ModulePresentation.glyph_color(module_type))


## Owned count, bottom-right of the icon and deliberately overhanging it by a
## few pixels as in the handoff.
func _draw_owned_badge(icon_size: Vector2) -> void:
	var font: Font = BuilderTheme.mono_font()
	var text: String = str(owned_count)
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE).x
	var badge_size: Vector2 = Vector2(text_width + 6.0, BADGE_FONT_SIZE + 4.0)
	var badge_position: Vector2 = Vector2(
		icon_size.x - badge_size.x + 4.0,
		(size.y + icon_size.y) * 0.5 - badge_size.y + 4.0)
	var badge := Rect2(badge_position, badge_size)

	draw_rect(badge, BADGE_BG, true)
	draw_rect(badge, BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.4), false, 1.0)
	font.draw_string(get_canvas_item(), badge_position + Vector2(0, badge_size.y - 3.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, badge_size.x, BADGE_FONT_SIZE, BuilderTheme.CYAN_BRIGHT)

class_name BeamVisual
extends Node2D

## The pulsing additive line a continuous-effect hardpoint draws from its
## muzzle to whatever it is currently acting on. Shared by
## HardpointTractorBeam (which wants a wider, dimmer glow layer under the core
## line) and HardpointGrinder (core line only) — both previously carried their
## own copy of the Line2D construction, the additive-material cache, the pulse
## formula and the show/hide helpers.
##
## Added as a child of the hardpoint at its origin, so points are given in the
## hardpoint's own local space (the muzzle) and world space (the target).

## Shared across every beam in the game. Building a fresh CanvasItemMaterial
## per beam forced a new renderer material/pipeline setup on each one, which
## was a real, reproducible hitch on every tractor grab. The blend mode is the
## only property set and never varies, so one cached instance is always
## correct to reuse.
static var _additive_material_cache: CanvasItemMaterial

var _lines: Array[Line2D] = []
var _pulse_speed: float = 6.0
var _pulse_strength: float = 0.4
var _time: float = 0.0


## Builds the beam's layers. A glow_width_multiplier of 0 (the default) means
## a single core line with no glow layer under it.
func configure(color: Color, width: float, pulse_speed: float, pulse_strength: float,
		glow_width_multiplier: float = 0.0, glow_alpha_multiplier: float = 0.0) -> void:
	_pulse_speed = pulse_speed
	_pulse_strength = pulse_strength

	for line in _lines:
		line.queue_free()
	_lines.clear()

	# Glow first so it renders beneath the core line.
	if glow_width_multiplier > 0.0:
		_lines.append(_create_line(width * glow_width_multiplier,
			Color(color.r, color.g, color.b, color.a * glow_alpha_multiplier)))
	_lines.append(_create_line(width, color))

	hide_beam()


## from_local is in the parent hardpoint's local space (its Muzzle position);
## target_global is the target's world position.
func draw_beam(from_local: Vector2, target_global: Vector2) -> void:
	visible = true
	var points: PackedVector2Array = [from_local, to_local(target_global)]
	for line in _lines:
		line.points = points


func hide_beam() -> void:
	visible = false


func _process(delta: float) -> void:
	# Time advances even while hidden so the pulse keeps a continuous phase
	# across brief target losses rather than restarting from full brightness.
	_time += delta
	if not visible:
		return

	var pulse: float = 1.0 - _pulse_strength * (sin(_time * _pulse_speed) * 0.5 + 0.5)
	var pulse_modulate := Color(1.0, 1.0, 1.0, pulse)
	for line in _lines:
		line.modulate = pulse_modulate


func _create_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.material = _additive_material()
	add_child(line)
	return line


func _additive_material() -> CanvasItemMaterial:
	if _additive_material_cache == null:
		_additive_material_cache = CanvasItemMaterial.new()
		_additive_material_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material_cache

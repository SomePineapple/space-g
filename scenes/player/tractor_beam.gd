class_name TractorBeam
extends Node2D

@export var tractor_range: float = 250.0
@export var pull_speed: float = 300.0
@export var beam_color: Color = Color(0.5, 0.8, 1.0, 0.8)
@export var beam_width: float = 3.0
@export var pulse_speed: float = 6.0
@export var pulse_strength: float = 0.4

@onready var _ship: Ship = get_owner()

var _beam_lines: Dictionary = {}
var _time: float = 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	var active_salvage: Array = []

	for node in get_tree().get_nodes_in_group("salvage"):
		var salvage: Salvage = node
		var distance: float = _ship.global_position.distance_to(salvage.global_position)
		if distance <= tractor_range:
			salvage.pull_toward(_ship.global_position, pull_speed, delta)
			active_salvage.append(salvage)
			_update_beam(salvage)

	_cleanup_beams(active_salvage)


func _update_beam(salvage: Salvage) -> void:
	var line: Line2D = _beam_lines.get(salvage)
	if line == null:
		line = Line2D.new()
		line.width = beam_width
		line.default_color = beam_color
		var line_material := CanvasItemMaterial.new()
		line_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		line.material = line_material
		add_child(line)
		_beam_lines[salvage] = line

	line.points = [Vector2.ZERO, to_local(salvage.global_position)]

	var pulse: float = 1.0 - pulse_strength * (sin(_time * pulse_speed) * 0.5 + 0.5)
	line.modulate = Color(1.0, 1.0, 1.0, pulse)


func _cleanup_beams(active_salvage: Array) -> void:
	for salvage in _beam_lines.keys().duplicate():
		if not active_salvage.has(salvage) or not is_instance_valid(salvage):
			var line: Line2D = _beam_lines[salvage]
			if is_instance_valid(line):
				line.queue_free()
			_beam_lines.erase(salvage)

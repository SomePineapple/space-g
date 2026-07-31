class_name TractorBeam
extends Node2D

@export var tractor_range: float = 250.0
@export var pull_speed: float = 300.0
@export var beam_color: Color = Color(0.5, 0.8, 1.0, 0.8)
@export var beam_width: float = 4.0
@export var pulse_speed: float = 6.0
@export var pulse_strength: float = 0.4
## Outer glow line is this many times wider than the core, at reduced alpha
## — gives the beam a brighter, more "energetic" look than a single line.
@export var glow_width_multiplier: float = 3.0
@export var glow_alpha_multiplier: float = 0.35
## Energy/sec per salvage item (or capturable tech part) actively being
## pulled — beaming in several pieces at once costs proportionally more.
@export var energy_cost_per_second: float = 5.0
## Pull speed for a CapturedTechPart — these have no rarity/pull_resistance
## concept like Salvage, so a single flat speed covers all of them.
@export var tech_part_pull_speed: float = 220.0
## How close a pulled CapturedTechPart needs to get to count as collected —
## it has no Area2D/collision of its own (unlike Salvage, which picks itself
## up via body_entered), so the beam has to do this check itself.
@export var tech_part_collect_radius: float = 20.0

@onready var _ship: Ship = get_owner()

var _beam_visuals: Dictionary = {}
var _time: float = 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	var active_pulled: Array = []

	for node in get_tree().get_nodes_in_group("salvage"):
		var salvage: Salvage = node
		var distance: float = _ship.global_position.distance_to(salvage.global_position)
		# Out of energy just drops this item from the beam (same as being out
		# of range) rather than a hard block — the beam visibly cuts out.
		if distance <= tractor_range and _ship.spend_energy(energy_cost_per_second * delta):
			# Heavier (rarer) salvage resists the beam and reels in slower,
			# so it physically feels heavier rather than just being worth more.
			salvage.pull_toward(_ship.global_position, pull_speed * salvage.pull_resistance, delta)
			active_pulled.append(salvage)
			_update_beam(salvage)

	for node in get_tree().get_nodes_in_group("capturable_tech"):
		var part: CapturedTechPart = node
		var distance: float = _ship.global_position.distance_to(part.global_position)
		if distance <= tractor_range and _ship.spend_energy(energy_cost_per_second * delta):
			# Stops it drifting/spinning and expiring under its own lifetime
			# countdown once the beam has it — same as HardpointWinch used to
			# do on attach (see CapturedTechPart.begin_reel_in).
			part.begin_reel_in()
			part.global_position = part.global_position.move_toward(_ship.global_position, tech_part_pull_speed * delta)
			active_pulled.append(part)
			_update_beam(part)

			if part.global_position.distance_to(_ship.global_position) <= tech_part_collect_radius:
				_ship.capture_tech_part(part.module_type_id)
				part.collect()

	_cleanup_beams(active_pulled)


## Salvage and CapturedTechPart share the same beam-visual treatment, so
## this takes either as a plain Node2D rather than duplicating the visuals
## code per type.
func _update_beam(pulled: Node2D) -> void:
	if not _beam_visuals.has(pulled):
		_beam_visuals[pulled] = _create_beam_visuals()
	var visuals: Dictionary = _beam_visuals[pulled]

	var points: PackedVector2Array = [Vector2.ZERO, to_local(pulled.global_position)]
	visuals["glow"].points = points
	visuals["core"].points = points

	var pulse: float = 1.0 - pulse_strength * (sin(_time * pulse_speed) * 0.5 + 0.5)
	visuals["glow"].modulate = Color(1.0, 1.0, 1.0, pulse)
	visuals["core"].modulate = Color(1.0, 1.0, 1.0, pulse)


func _create_beam_visuals() -> Dictionary:
	var glow := Line2D.new()
	glow.width = beam_width * glow_width_multiplier
	glow.default_color = Color(beam_color.r, beam_color.g, beam_color.b, beam_color.a * glow_alpha_multiplier)
	glow.material = _additive_material()
	add_child(glow)

	var core := Line2D.new()
	core.width = beam_width
	core.default_color = beam_color
	core.material = _additive_material()
	add_child(core)

	return {"glow": glow, "core": core}


func _additive_material() -> CanvasItemMaterial:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive


func _cleanup_beams(active_salvage: Array) -> void:
	for salvage in _beam_visuals.keys().duplicate():
		if not active_salvage.has(salvage) or not is_instance_valid(salvage):
			var visuals: Dictionary = _beam_visuals[salvage]
			for line in visuals.values():
				if is_instance_valid(line):
					line.queue_free()
			_beam_visuals.erase(salvage)

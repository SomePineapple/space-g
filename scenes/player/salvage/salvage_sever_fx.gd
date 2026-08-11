class_name SalvageSeverFx
extends Node2D

## The one-shot burst at the moment a part comes free: flash, radial spark blast,
## atmosphere venting outward from all six edges, and a scatter of hull debris
## (docs/design_salvage/salvage-beam-Godot-spec.md §Sever and structure).
##
## Spawned into the world at the severed cell and frees itself when the longest
## emitter has finished. Deliberately not parented to the tile that just came
## loose: the vent is the *hole* letting go, and it stays with the hull.
##
## Particle materials are built once and shared. Constructing a
## ParticleProcessMaterial per burst is exactly the per-frame render-resource
## construction docs/performance.md is about, and a sever happens mid-fight.

const LIFETIME: float = 1.6
const FLASH_SECONDS: float = 0.18
const FLASH_RADIUS: float = 44.0

static var _spark_material: ParticleProcessMaterial
static var _vent_material: ParticleProcessMaterial
static var _debris_material: ParticleProcessMaterial

var _elapsed: float = 0.0
var _flash: Node2D


## `radius` is the cell size, used to place the vents on the hex edges.
func burst(radius: float) -> void:
	_flash = Node2D.new()
	_flash.material = SalvagePalette.additive_material()
	_flash.draw.connect(_draw_flash)
	add_child(_flash)

	_add_particles(_sparks(), 130)
	_add_particles(_debris(), 16)
	# Six vents, one per edge, each firing along that edge's outward normal.
	for i in 6:
		var vent: GPUParticles2D = _add_particles(_vents(), 14)
		var angle: float = TAU * (float(i) + 0.5) / 6.0
		vent.position = Vector2.RIGHT.rotated(angle) * radius * 0.8
		vent.rotation = angle


func _process(delta: float) -> void:
	_elapsed += delta
	_flash.queue_redraw()
	if _elapsed >= LIFETIME:
		queue_free()


func _draw_flash() -> void:
	if _elapsed >= FLASH_SECONDS:
		return
	var fade: float = 1.0 - _elapsed / FLASH_SECONDS
	_flash.draw_circle(Vector2.ZERO, FLASH_RADIUS * (0.4 + 0.6 * fade),
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, fade * 0.85))


func _add_particles(process_material: ParticleProcessMaterial, amount: int) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 1.1
	particles.process_material = process_material
	particles.emitting = true
	add_child(particles)
	return particles


func _sparks() -> ParticleProcessMaterial:
	if _spark_material == null:
		_spark_material = _base_material(60.0, 300.0, 1.0)
		_spark_material.scale_min = 1.0
		_spark_material.scale_max = 2.4
		_spark_material.color_ramp = _spark_ramp()
	return _spark_material


func _vents() -> ParticleProcessMaterial:
	if _vent_material == null:
		# A narrow cone rather than a sphere: venting atmosphere leaves along the
		# edge it escaped through.
		_vent_material = _base_material(30.0, 90.0, 0.35)
		_vent_material.scale_min = 1.0
		_vent_material.scale_max = 3.2
		_vent_material.color = Color(SalvagePalette.VENT.r, SalvagePalette.VENT.g,
			SalvagePalette.VENT.b, 0.32)
	return _vent_material


func _debris() -> ParticleProcessMaterial:
	if _debris_material == null:
		_debris_material = _base_material(40.0, 150.0, 1.0)
		_debris_material.scale_min = 0.6
		_debris_material.scale_max = 1.4
		_debris_material.color = Color(0.2902, 0.3412, 0.3882)  # 4a5763 rivet grey
	return _debris_material


func _base_material(min_speed: float, max_speed: float, spread: float) -> ParticleProcessMaterial:
	var made := ParticleProcessMaterial.new()
	made.particle_flag_disable_z = true
	made.direction = Vector3(1.0, 0.0, 0.0)
	made.spread = 180.0 * spread
	made.initial_velocity_min = min_speed
	made.initial_velocity_max = max_speed
	made.gravity = Vector3.ZERO
	made.damping_min = 30.0
	made.damping_max = 90.0
	return made


func _spark_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, 1.0),
		Color(1.0, 0.8510, 0.6275, 1.0),  # ffd9a0
		Color(1.0, 0.5412, 0.2353, 0.8),  # ff8a3c
		Color(1.0, 0.5412, 0.2353, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

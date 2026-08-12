class_name GrappleFx
extends RefCounted

## The grapple line's two one-shot particle bursts: the spark blast when the hook
## bites (docs/design_handoff_grapple/grapple-line-Godot-spec.md, "Bite") and the
## smaller puff each time a slack line snaps taut ("Tension").
##
## Factories rather than scenes, and the ParticleProcessMaterials are built once
## and shared across every emitter — constructing a process material per burst is
## exactly the per-frame render-resource construction docs/performance.md warns
## about, and a grapple bites and jolts repeatedly during one haul. Same shape as
## SalvageSeverFx, which shares its materials for the same reason.
##
## Every emitter comes back stopped. Call burst() to fire it.

static var _spark_material: ParticleProcessMaterial
static var _grit_material: ParticleProcessMaterial
static var _strain_material: ParticleProcessMaterial


## The hot half of the bite: 46 sparks in the beam's own core colour, cooling
## through the salvage ramp.
static func sparks(amount: int) -> GPUParticles2D:
	if _spark_material == null:
		_spark_material = _base_material(80.0, 340.0)
		_spark_material.scale_min = 1.0
		_spark_material.scale_max = 2.2
		_spark_material.color_ramp = _spark_ramp()
	return _emitter(_spark_material, amount, 0.9)


## The cold half: 16 chips of plating knocked off the hunk.
static func grit(amount: int) -> GPUParticles2D:
	if _grit_material == null:
		_grit_material = _base_material(30.0, 130.0)
		_grit_material.scale_min = 0.6
		_grit_material.scale_max = 1.3
		_grit_material.color = Color(0.2314, 0.2784, 0.3255)  # 3b4753 chain body
	return _emitter(_grit_material, amount, 1.1)


## The jolt when the line comes taut — a short cyan flick in the line's own
## highlight colour, so the burst reads as the chain straining rather than as
## something breaking.
static func strain(amount: int) -> GPUParticles2D:
	if _strain_material == null:
		_strain_material = _base_material(40.0, 150.0)
		_strain_material.scale_min = 0.8
		_strain_material.scale_max = 1.6
		_strain_material.color = SalvagePalette.hdr(
			SalvagePalette.BEAM_SHEATH, SalvagePalette.SHEATH_GAIN, 0.8)
	return _emitter(_strain_material, amount, 0.45)


## Fires an emitter built above at a world position. `emitting` is set as well as
## restart() because a one-shot emitter that has already finished its cycle stays
## switched off otherwise.
static func burst(particles: GPUParticles2D, at_global: Vector2) -> void:
	if particles == null or not is_instance_valid(particles):
		return
	particles.global_position = at_global
	particles.emitting = true
	particles.restart()


static func _emitter(process_material: ParticleProcessMaterial, amount: int,
		lifetime: float) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = maxi(amount, 1)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = lifetime
	particles.process_material = process_material
	particles.emitting = false
	return particles


static func _base_material(min_speed: float, max_speed: float) -> ParticleProcessMaterial:
	var made := ParticleProcessMaterial.new()
	made.particle_flag_disable_z = true
	made.direction = Vector3(1.0, 0.0, 0.0)
	made.spread = 180.0
	made.initial_velocity_min = min_speed
	made.initial_velocity_max = max_speed
	made.gravity = Vector3.ZERO
	made.damping_min = 40.0
	made.damping_max = 110.0
	return made


static func _spark_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		SalvagePalette.hdr(SalvagePalette.BEAM_CORE, SalvagePalette.CORE_GAIN, 1.0),
		Color(1.0, 0.8510, 0.6275, 1.0),  # ffd9a0
		Color(1.0, 0.5412, 0.2353, 0.8),  # ff8a3c
		Color(1.0, 0.5412, 0.2353, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

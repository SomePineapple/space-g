class_name HullGlowLayer
extends Node2D

## Draws a hull's emissive layers (see ModuleType.faction_hex_glow_textures)
## brightly enough for the region's glow to catch them, breathing slowly.
##
## A separate node purely because a CanvasItem has ONE material, and the gain has
## to come from a shader — see hull_glow.gdshader for why it cannot be a vertex
## colour. ShipLayoutRenderer draws plating, lights and panel lines in one _draw,
## so it cannot switch material part-way through; the lights move out here
## instead, onto a child that draws over its parent.
##
## The one visible consequence is ordering: lights now sit above the panel lines
## and hull silhouette rather than under them. Lamps are small and live inside a
## hex while seams run along hex borders, so in practice they barely meet.

## How far past white a lamp is pushed at the top of its cycle. The glow
## threshold is 1.0 and the art's lit pixels top out around 0.95, so anything at
## or below 1.0 leaves them just under the line and they read as pale paint
## rather than as light.
const GLOW_GAIN: float = 3.4
## How far it falls at the bottom, as a fraction of GLOW_GAIN.
##
## The trough has to cross BELOW the glow threshold of 1.0, which is the
## opposite of what it looks like it should do. A lamp's lit pixels are already
## near white, so at any level above about 1.05 they display as pure white no
## matter how much higher the level goes — the whole cycle sat between 1.53 and
## 3.4 at first, every lamp core stayed white end to end, and the only thing that
## actually moved was the width of the bloom halo. That is invisible on the small
## lamps, which have barely any halo: measured against what the eye sees, the
## Battery swung 0.8% and the Thruster 1.2% while the Command Core managed 24%.
##
## At 0.75 the trough is 0.85 and the lamps themselves darken rather than just
## their halos — the amber strips drop to a dull orange, the teal indicators
## fade, the reactor rings shed their glow. They still read as lit, because the
## art is coloured rather than white, so this does not look like a failure.
const PULSE_DEPTH: float = 0.75
## Seconds per breath. Slow enough to read as idling machinery rather than as a
## blinking indicator.
const PULSE_PERIOD: float = 5.0

const GLOW_SHADER: Shader = preload("res://scripts/ships/layout/hull_glow.gdshader")

## Every hull gets its own material, but they all share the one Shader above and
## therefore its compiled pipeline — the per-hull cost is a uniform buffer. They
## cannot share one material because each needs its own pulse phase.
var _material: ShaderMaterial

## texture -> ArrayMesh for the current layout. Held rather than rebuilt in
## _draw because draw_mesh only records the mesh's RID, so dropping these frees
## the mesh out from under the renderer (same trap as ShipLayoutRenderer's
## _hull_meshes).
var _meshes: Dictionary = {}


func _ready() -> void:
	# Matches the parent hull: the art is authored far larger than it draws.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material = ShaderMaterial.new()
	_material.shader = GLOW_SHADER
	_material.set_shader_parameter("gain", GLOW_GAIN)
	_material.set_shader_parameter("pulse_depth", PULSE_DEPTH)
	_material.set_shader_parameter("pulse_period", PULSE_PERIOD)
	# Drawn from the session RNG rather than the clock or the instance id, so two
	# machines running the same session light their ships identically
	# (docs/multiplayer.md). Cosmetic either way, but the rule is the rule.
	_material.set_shader_parameter("phase", GameRng.stream("hull_glow").randf() * TAU)
	material = _material


## Handed the finished meshes by ShipLayoutRenderer, which already batches one
## per glow texture while walking its cells.
func set_glow_meshes(meshes_by_texture: Dictionary) -> void:
	_meshes = meshes_by_texture
	queue_redraw()


func _draw() -> void:
	for texture: Texture2D in _meshes:
		draw_mesh(_meshes[texture], texture)

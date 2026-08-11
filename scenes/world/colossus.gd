class_name Colossus
extends Node2D

## The derelict capital ship the opening sequence points the player at.
##
## Two layers, both the same authored image size and origin so they line up
## without any offset maths: an unlit base hull, and a lights layer drawn
## additively over it. The lights flicker and bloom; the base does not, which is
## what sells the thing as powerless and drifting rather than as a lit ship.
##
## Pure presentation, and deliberately at the very back (z_index in the scene):
## it is a backdrop the size of a region, so anything with gameplay in it — the
## player, the graveyard, projectiles — has to draw in front. It has no collision
## body either; something this large behaving as an obstacle would read as an
## invisible wall long before the art explained itself.
##
## The part the player can actually take is a separate wreck in the field around
## it (see Battleground) — this script deliberately knows nothing about salvage,
## so the wreck's art and the salvage mechanics can change independently.

## Both layers are authored at 3440x2580. This is the dial that decides how big
## "large" reads as, and it is set for awe rather than for legibility: at 2.5 the
## hull is about 8600 units across, so it fills the view long before the player
## reaches it and cannot be seen whole at normal zoom. That is the intent.
@export var visual_scale: float = 2.5

## The band the lights layer is allowed to move in, as a fraction of the authored
## artwork. It never leaves this range in either direction: never brighter than
## the art, never darker than the floor. Failing power that still swings a long
## way is what reads as dying, so the whole effect lives between these two.
@export var light_level_min: float = 0.2
@export var light_level_max: float = 0.4

## Flicker is the sum of two out-of-phase waves plus occasional brownouts.
## Two waves rather than one because a single sine reads as a pulse — a
## deliberate, powered rhythm — where dying electrics should feel unsteady.
@export var flicker_speed_a: float = 1.7
@export var flicker_speed_b: float = 4.3

## How often the lights sag to the bottom of the band, and for how long.
## Irregular on purpose: a timer reads as machinery working correctly.
@export var brownout_chance_per_second: float = 0.35
@export var brownout_seconds: Vector2 = Vector2(0.06, 0.28)

@onready var _base: Sprite2D = $Base
@onready var _lights: Sprite2D = $Lights

var _time: float = 0.0
var _brownout_remaining: float = 0.0


func _ready() -> void:
	_base.scale = Vector2.ONE * visual_scale
	_lights.scale = Vector2.ONE * visual_scale
	# Phase offset per instance so two colossi in one scene never flicker in
	# lockstep. Global randf, not a GameRng stream: this is local decoration and
	# drawing from a shared stream would desync every simulation roll downstream
	# (see docs/direction.md §2).
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta

	if _brownout_remaining > 0.0:
		_brownout_remaining -= delta
		_apply_light_level(0.0)
		return

	if randf() < brownout_chance_per_second * delta:
		_brownout_remaining = randf_range(brownout_seconds.x, brownout_seconds.y)
		return

	# Two waves summed land in -1..1; remapped to 0..1 so the lights ride the
	# whole band rather than hovering around its middle.
	var wobble: float = (sin(_time * flicker_speed_a) + sin(_time * flicker_speed_b)) * 0.25 + 0.5
	_apply_light_level(wobble)


## `position_in_band` is 0..1 across light_level_min..light_level_max. Clamped
## rather than trusted, so no amount of retuning the waves can push the layer
## past the authored artwork or below the floor.
##
## Set through modulate rather than by touching the material or the texture:
## anything that rebuilds a render resource per frame is the cost
## docs/performance.md is about.
func _apply_light_level(position_in_band: float) -> void:
	var value: float = lerpf(light_level_min, light_level_max,
		clampf(position_in_band, 0.0, 1.0))
	_lights.modulate = Color(value, value, value, 1.0)


## World-space radius the hull occupies, for anything that needs to keep its
## distance (spawn placement, the intro's approach cue). Derived from the
## texture rather than hard-coded so rescaling the art cannot leave a stale
## number behind.
func get_visual_radius() -> float:
	var texture: Texture2D = _base.texture
	if texture == null:
		return 0.0
	return maxf(texture.get_width(), texture.get_height()) * 0.5 * visual_scale

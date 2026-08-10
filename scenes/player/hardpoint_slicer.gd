class_name HardpointSlicer
extends Node2D

## Hull Slicer hex module: a long, thick cutting beam the player toggles on/off
## (the same system switch the Mining Grinder used, "G") and holds on a target
## ship to cut through its hull.
##
## Aimed with the mouse, out to beam_range and no further. The mount itself does
## not rotate — the beam simply leaves its muzzle toward the cursor — so the
## reach is a circle around the module rather than a cone.
##
## This replaces the Mining Grinder, which reduced a specific object to bulk
## material — a smelter, and the mechanic the design thesis is built against.
## The Slicer does the opposite: it takes a ship apart into the specific parts it
## was assembled from, intact enough to bolt onto your own hull.
##
## **It is not a weapon.** It damages exactly one part — the one under the point
## where the beam makes contact — with no splash onto neighbours, nothing behind
## it, and no effect on the target's overall Health pool. So it cannot kill a
## ship, only dismantle one, and it cannot reach a part it isn't touching.
##
## The severing itself is not implemented here. Destroying a cell is all this
## does; whether that actually frees anything is decided by the target's own
## connectivity graph (HullDamageModel._check_for_detachment ->
## ShipLayout.find_unreachable_from_core), which already severs any part left
## with no path back to the core. That is the whole mechanic: you are not aiming
## at the part you want, you are aiming at what holds it on. A gun mounted at the
## end of a long thin spar is one cut away from floating free; the same gun in
## the middle of a solid hull cannot be taken at all.
##
## Anything cut loose this way is always recoverable (see
## Ship.take_slicer_cut -> WreckageSpawner.spawn_severed_piece's `clean_cut`) —
## no capture roll. Reel it in with the Winch.

## How far the beam reaches, in world units — a hard cap on length regardless of
## where the cursor is. Authored as 10 hexes: a hex is HexUtils.SQRT3 * cell_size
## across and hulls render at cell_size 24, so 10 * 1.732 * 24 ~= 420. Long
## enough to reach past a ship's outer plating to the spar behind it without
## having to fly into the wreckage you are creating.
@export var beam_range: float = 420.0
## Damage per second dealt to every part the beam crosses.
##
## Tuned against a real enemy part. Condition is stored per part, not per cell,
## so the Hull Spar this is meant to cut is one 150-condition object however many
## hexes it spans. Pirates run health_multiplier 1.0 (it is the *player* that
## carries 3.0, on personality_user), so that 150 is the number in the field —
## about 2.7s of held beam here.
##
## Long enough that holding the cut on one specific connector, on a moving
## target, is a real commitment; short enough not to be a chore. Both bounds are
## measured: 30 dps took 15s against a 3x hull, and 150 dps cut a real 1.0x
## pirate spar in a single second, which made the topology decision irrelevant
## because everything fell off immediately.
@export var damage_per_second: float = 55.0
@export var energy_cost_per_second: float = 9.0
## Thick and near-white, deliberately unlike every weapon in the game — this is
## industrial cutting equipment, not ordnance, and it should never be mistaken
## for a gun that happens to have long range.
@export var beam_color: Color = Color(0.94, 0.97, 1.0, 0.95)
@export var beam_width: float = 6.0
@export var pulse_speed: float = 14.0
@export var pulse_strength: float = 0.25

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## every other hardpoint.
var source_placement_id: String = ""

var _shooter: Ship
var _beam: BeamVisual

@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	_beam = BeamVisual.new()
	add_child(_beam)
	_beam.configure(beam_color, beam_width, pulse_speed, pulse_strength)


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Facing-vertex reach, set once by HardpointBank right after instancing. See the
## "+90° fixed offset" entry in docs/gotchas.md: this node's rotation points at
## the hex's *face*, and the builder's placement arrow is drawn 90° off that for
## its own UX reasons, so the muzzle is pushed out along the vertex the arrow
## points at. Inherited unchanged from the Grinder this replaced, where it was
## established by live verification — don't "simplify" the rotation away.
func set_cell_size(cell_size: float) -> void:
	_muzzle.position = Vector2(cell_size * 1.15, 0.0).rotated(deg_to_rad(-90.0))


## Where the cut is aimed: the cursor. Picking out one specific connector on a
## moving hull is fiddly enough with a mouse; making the whole ship the aiming
## device on top of that made it a wrestling match rather than a decision.
##
## Falls back to the mount's own facing only while there is no aim target at all
## (an AI ship carrying a Slicer, which never sets one) — a zero vector would
## make the raycast fail silently.
func _beam_direction() -> Vector2:
	var muzzle_position: Vector2 = _muzzle.global_position
	var aim_target: Vector2 = _shooter.get_aim_target()
	var to_target: Vector2 = aim_target - muzzle_position
	if to_target.length() > 0.001:
		return to_target.normalized()
	if _muzzle.position.is_zero_approx():
		return Vector2.RIGHT.rotated(global_rotation - PI * 0.5)
	return _muzzle.position.normalized().rotated(global_rotation)


## How far the beam reaches this frame: to the cursor, but never past
## beam_range. The clamp is what makes the reach readable — drift away from a
## target and the beam stops at 10 hexes and visibly falls short, rather than
## stretching to wherever the mouse happens to be.
func _beam_length() -> float:
	return minf(_muzzle.global_position.distance_to(_shooter.get_aim_target()), beam_range)


func _physics_process(delta: float) -> void:
	if _shooter == null or (not source_placement_id.is_empty() and _shooter.is_module_destroyed(source_placement_id)):
		_stop_cutting()
		return

	if not _shooter.is_slicer_active():
		_stop_cutting()
		return

	if not _shooter.spend_energy(energy_cost_per_second * delta):
		_stop_cutting()
		return

	_cut(delta)


func _cut(delta: float) -> void:
	var from_point: Vector2 = _muzzle.global_position
	var direction: Vector2 = _beam_direction()
	var to_point: Vector2 = from_point + direction * _beam_length()

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from_point, to_point)
	query.exclude = [_shooter.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)

	# The beam is drawn to whatever it actually reaches, so its length reads as
	# the tool's reach rather than as a fixed decorative bar.
	if not result.is_empty():
		to_point = result.position
	# Mixed spaces on purpose — draw_beam() takes its start in this hardpoint's
	# local space and its end in WORLD space, applying to_local() to the end
	# itself. Converting the end first transforms it twice, which leaves the far
	# tip wandering somewhere near the ship instead of tracking the cursor.
	_beam.draw_beam(_muzzle.position, to_point)

	if result.is_empty():
		return
	var target: Object = result.collider
	if target == _shooter or not target.has_method("take_slicer_cut"):
		return

	# Just the contact point. The cut lands on the one part the beam is touching
	# and stops there — see Ship.take_slicer_cut.
	target.take_slicer_cut(damage_per_second * delta, result.position)


func _stop_cutting() -> void:
	_beam.hide_beam()

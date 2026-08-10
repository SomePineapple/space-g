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
## Seconds of held beam to cut through a part, once it is damaged enough to be
## cuttable at all (below HullPaint.CUTTABLE_CONDITION).
##
## A duration rather than a damage rate, so every part takes the same time. Under
## a flat rate a 40-condition gun came free three times quicker than a
## 150-condition spar, which made the tool's timing a property of whatever it was
## pointed at instead of something the player could learn and plan around.
##
## Ten seconds is a long commitment on purpose: it has to be held on one specific
## connector, on a moving target, while that ship is still fighting back.
@export var cut_duration: float = 10.0
@export var energy_cost_per_second: float = 9.0
## Thick and near-white, deliberately unlike every weapon in the game — this is
## industrial cutting equipment, not ordnance, and it should never be mistaken
## for a gun that happens to have long range.
@export var beam_color: Color = Color(0.94, 0.97, 1.0, 0.95)
@export var beam_width: float = 6.0
@export var pulse_speed: float = 14.0
@export var pulse_strength: float = 0.25
## How fast the beam extends and retracts, in world units per second. The beam
## does not appear and vanish: it reaches out when switched on, draws back in
## when switched off, and slides in and out as the cursor moves nearer and
## further. Roughly a quarter-second to cover its full 10-hex reach.
@export var extend_speed: float = 1600.0
## What the beam is modulated toward as a cut progresses, from cold white at the
## first touch to a hot working colour as the part comes apart — so how far
## through a ten-second cut you are is legible on the beam itself, not only on
## the target.
@export var cut_progress_color: Color = Color(1.0, 0.62, 0.28)
## What the beam is modulated by while touching a part too healthy to cut.
const INTACT_BEAM_FADE: Color = Color(0.5, 0.55, 0.62, 0.45)

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## every other hardpoint.
var source_placement_id: String = ""

var _shooter: Ship
var _beam: BeamVisual
## What the last cut attempt did: "cut", "intact" or "miss" (see
## Ship.take_slicer_cut), and how far through the band that part is. Together
## these drive the beam's own feedback.
var _last_result: String = "miss"
var _last_progress: float = 0.0
## How far the beam is currently reaching. Animated toward its target rather than
## set outright, which is what makes it extend and retract instead of blinking.
var _current_length: float = 0.0
## The direction the beam last pointed, so a retracting beam keeps drawing along
## its own line rather than snapping to wherever the cursor has since moved.
var _last_direction: Vector2 = Vector2.RIGHT
## Set on the frame a part comes apart, cleared once the beam is fully home. The
## beam draws itself back in before it will cut anything else, so finishing a cut
## is a visible completed action rather than the beam carrying straight on
## through the hole into whatever was behind the part.
var _finishing_cut: bool = false

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
	# Every "stop" case retracts rather than killing the beam outright, so
	# switching off, running out of power, losing the mount and having nothing in
	# range all look like one piece of equipment drawing itself back in.
	if _shooter == null or (not source_placement_id.is_empty() and _shooter.is_module_destroyed(source_placement_id)):
		_retract(delta)
		return

	# A finished cut retracts before anything else is considered, so it completes
	# even with the beam still switched on and the cursor still on the target.
	if _finishing_cut:
		_retract(delta)
		return

	if not _shooter.is_slicer_active():
		_retract(delta)
		return

	if not _shooter.spend_energy(energy_cost_per_second * delta):
		_retract(delta)
		return

	_cut(delta)


func _cut(delta: float) -> void:
	var from_point: Vector2 = _muzzle.global_position
	var direction: Vector2 = _beam_direction()
	_last_direction = direction

	# Grow toward the length the cursor is asking for. Because the raycast below
	# only reaches as far as the beam has actually extended, a beam still on its
	# way out cannot cut something it has not visibly reached yet.
	_current_length = move_toward(_current_length, _beam_length(), extend_speed * delta)
	var to_point: Vector2 = from_point + direction * _current_length

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
	# Dimmed while the beam is landing on something it cannot open, so "nothing is
	# happening" is visible on the tool as well as on the target (which carries
	# the cut-ready marker — see HullPaint.CUT_READY_COLOR). Set as modulate
	# rather than by reconfiguring the beam: configure() rebuilds its Line2D
	# children, and doing that every frame is the per-frame resource construction
	# docs/performance.md is about.
	_apply_beam_tint()
	_beam.draw_beam(_muzzle.position, to_point)

	if result.is_empty():
		_last_result = "miss"
		_last_progress = 0.0
		return
	var target: Object = result.collider
	if target == _shooter or not target.has_method("take_slicer_cut"):
		_last_result = "miss"
		_last_progress = 0.0
		return

	# Just the contact point. The cut lands on the one part the beam is touching
	# and stops there — see Ship.take_slicer_cut. The direction is passed so the
	# hull can sample just inside the surface the ray stopped on.
	# The share of the cut spent this frame is simply the share of cut_duration
	# this frame represents.
	var outcome: Dictionary = target.take_slicer_cut(
		delta / maxf(cut_duration, 0.001), result.position, direction)
	_last_result = outcome["result"]
	_last_progress = outcome["progress"]
	if _last_result == "severed":
		_finishing_cut = true


## Draws the beam back in rather than switching it off. Once it is fully home the
## visual is hidden, which is also what stops it being drawn at a stale angle.
func _retract(delta: float) -> void:
	# A beam drawing back in from a completed cut keeps the hot colour it finished
	# on all the way home, so the last thing seen is the cut succeeding. Every
	# other retraction goes cold immediately.
	if not _finishing_cut:
		_last_result = "miss"
		_last_progress = 0.0
	_current_length = move_toward(_current_length, 0.0, extend_speed * delta)
	if _current_length <= 0.01:
		_finishing_cut = false
		_last_result = "miss"
		_last_progress = 0.0
		_beam.hide_beam()
		return
	_apply_beam_tint()
	_beam.draw_beam(_muzzle.position,
		_muzzle.global_position + _last_direction * _current_length)


## Colour is set through modulate rather than by reconfiguring the beam:
## configure() rebuilds its Line2D children, and doing that every frame is the
## per-frame resource construction docs/performance.md is about.
func _apply_beam_tint() -> void:
	if _last_result == "intact":
		_beam.modulate = INTACT_BEAM_FADE
		return
	_beam.modulate = Color.WHITE.lerp(cut_progress_color, _last_progress)

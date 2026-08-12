class_name HardpointSlicer
extends Node2D

## Hull Slicer hex module: a long, thick cutting beam the player toggles on/off
## (the Salvager system switch, "G") and holds on a target
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
## Per the spec's phase table this is the CUT phase alone — the upgradeable stat
## a faster cutter shortens. The lock/spool/pilot ramp in front of it
## (LOCK_SECONDS) is fixed, so a whole cut is that ramp plus this.
##
## Was 10.0 for the hold-the-beam-forever version of this tool. The spec's
## timeline is the contract now, and it puts the cut at 3.6s after a 2.4s ramp:
## roughly six seconds end to end rather than ten.
@export var cut_duration: float = 3.6
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
## How fast the beam draws back in once a cut has actually completed, as opposed
## to the snap-back of switching off or losing the target. Deliberately slower
## than extend_speed: finishing a cut is the tool's one moment of success and it
## should be watchable, not a single frame of blur.
@export var cut_retract_speed: float = 700.0
## How long the beam stays stowed after a completed cut before it will reach out
## again.
##
## Without this the collapse was technically happening and effectively invisible:
## measured, the beam went from 243 units to home in 0.13s and was back at full
## extension 0.07s later, because the Salvager is still switched on and the cursor
## is still on the wreck. The pause is what turns that into a completed action —
## the part comes off, the tool draws in, and only then does it look for more.
@export var post_cut_hold: float = 0.8
## What the beam is modulated toward as a cut progresses, from cold white at the
## first touch to a hot working colour as the part comes apart — so how far
## through a ten-second cut you are is legible on the beam itself, not only on
## the target.
@export var cut_progress_color: Color = Color(1.0, 0.62, 0.28)
## What the beam is modulated by while touching a part too healthy to cut.
const INTACT_BEAM_FADE: Color = Color(0.5, 0.55, 0.62, 0.45)

# --- Phase timings (docs/design_salvage/salvage-beam-Godot-spec.md) -----------
# Seconds from acquiring a cuttable cell. The spec drives these from one
# AnimationPlayer over a fixed 10s; here they are driven from live state instead,
# because this cut is something the player holds on a moving target and can break
# off at any moment — a canned timeline cannot be interrupted halfway and
# resumed, which is most of what actually happens in play.
const SPOOL_START: float = 1.1
const PILOT_START: float = 1.55
const CUT_START: float = 2.4
## Camera shake while cutting, from the spec's ±1.3px.
@export var shake_strength: float = 1.3

## Every hull in the game draws at the default z_index, so among themselves ships
## sort by scene-tree order — and an enemy added to the world after the player
## therefore draws *over* anything parented under the player's ship, including
## this beam. The cutting effect has to be above the hull it is cutting, so it is
## pulled out of that ordering entirely (z_as_relative = false).
const EFFECT_Z_INDEX: int = 20

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## every other hardpoint.
var source_placement_id: String = ""

var _shooter: Ship
var _beam: SalvageBeam
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
## Seconds the beam has been locked on the current cell, driving the lock/spool/
## pilot ramp. Reset whenever the lock is lost.
var _lock_elapsed: float = 0.0
## Counts down post_cut_hold once a finished cut has fully drawn in.
var _hold_remaining: float = 0.0
## The cell currently being cut, as reported by Ship.get_cut_cell.
var _cell: Dictionary = {}
## The ship and hex the beam has committed to for this cut.
var _locked_ship: Object = null
var _locked_coord: Vector2i = Vector2i.ZERO
var _reticle: SalvageReticle
## The seam being burned into the target, parented to that ship so it stays with
## the hull. Dropped (not freed) when the cut ends — it carries on cooling.
var _trail: SalvageCutTrail

@onready var _muzzle: Marker2D = $Muzzle


func _ready() -> void:
	_beam = SalvageBeam.new()
	_beam.z_index = EFFECT_Z_INDEX
	_beam.z_as_relative = false
	add_child(_beam)
	_reticle = SalvageReticle.new()
	_reticle.z_index = EFFECT_Z_INDEX + 1
	_reticle.z_as_relative = false
	# In the world rather than under the muzzle: it has to sit on the target hex
	# while this node swings around with its own ship.
	WorldSpawn.attach(_reticle)


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

	# ...and then stays in for a beat, for the same reason.
	if _hold_remaining > 0.0:
		_hold_remaining -= delta
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

	if result.is_empty():
		_lose_lock()
		_beam.set_state(0.0, 0.0, Color.WHITE)
		_beam.set_endpoints(_muzzle.position, to_point)
		_last_result = "miss"
		_last_progress = 0.0
		return

	var target: Object = result.collider
	if target == _shooter or not target.has_method("take_slicer_cut"):
		_lose_lock()
		_beam.set_state(0.0, 0.0, Color.WHITE)
		_beam.set_endpoints(_muzzle.position, result.position)
		_last_result = "miss"
		_last_progress = 0.0
		return

	# A cell the beam is not allowed to open never gets a lock at all, so the
	# reticle and spool are a promise the tool can keep: if it locks on, it will
	# cut. Feedback is the dimmed beam and the target's own missing cut-ready
	# marker, same as before.
	if not _track_lock(target, result.position, direction, delta):
		_beam.set_state(0.0, 0.0, INTACT_BEAM_FADE)
		_beam.set_endpoints(_muzzle.position, result.position)
		_last_result = "intact"
		_last_progress = 0.0
		return

	# Lock and spool happen before anything is actually being cut: the tool has to
	# settle on the cell first. Only past CUT_START does the beam bite.
	if _lock_elapsed < CUT_START:
		_show_ramp(result.position)
		_last_result = "cut"
		return

	# Aimed at the locked cell's own centre rather than the raw contact point, so
	# the part being damaged is always the part the reticle is drawn around.
	var cut_at: Vector2 = _cell["center"] if not _cell.is_empty() else result.position
	var outcome: Dictionary = target.take_slicer_cut(
		delta / maxf(cut_duration, 0.001), cut_at, direction)
	_last_result = outcome["result"]
	_last_progress = outcome["progress"]

	_show_cut(target, result.position)
	if _last_result == "severed":
		_on_severed(target)
		_finishing_cut = true


## Keeps the reticle and seam pointed at the cell under the beam. Losing the cell
## — the cursor slipping onto a different hex — restarts the ramp, so you cannot
## spool up on one part and cash it in on another.
##
## False when there is nothing here the beam may lock onto: no cell, or a cell
## still in good enough condition that the Slicer cannot open it. The lock used to
## be granted on any occupied cell and cuttability only checked once damage was
## being applied, so the tool would fly its reticle in and spool all the way up on
## an intact part before quietly doing nothing.
func _track_lock(target: Object, contact: Vector2, direction: Vector2, delta: float) -> bool:
	if not target.has_method("get_cut_cell"):
		_lose_lock()
		return false

	# Once locked, the cell is held by coordinate rather than re-resolved from the
	# contact point. Re-resolving every frame made the lock flicker between
	# neighbouring hexes as the two hulls drifted against each other, which reset
	# the ramp continuously and meant a cut could never start at all.
	var cell: Dictionary = {}
	if _locked_ship == target and _lock_elapsed > 0.0:
		cell = target.get_cell_geometry(_locked_coord)
	if cell.is_empty():
		cell = target.get_cut_cell(contact, direction)
		if cell.is_empty():
			_lose_lock()
			return false
		# A genuinely different cell — the player has moved the beam onto another
		# part — starts its own lock rather than inheriting this one's progress.
		if _locked_ship != target or _locked_coord != cell["coord"]:
			_lose_lock()
		_locked_ship = target
		_locked_coord = cell["coord"]

	if not cell.get("cuttable", false):
		_lose_lock()
		return false

	_cell = cell
	_lock_elapsed += delta
	_reticle.lock_on(cell["center"], cell["rotation"], cell["radius"])
	return true


func _lose_lock() -> void:
	_lock_elapsed = 0.0
	_cell = {}
	_locked_ship = null
	_trail = null
	_reticle.release()


## Lock, spool and pilot: the beam is present but not yet cutting.
func _show_ramp(contact: Vector2) -> void:
	var charge: float = clampf((_lock_elapsed - SPOOL_START) / (CUT_START - SPOOL_START), 0.0, 1.0)
	var strength: float = 0.0 if _lock_elapsed < PILOT_START else 0.0
	_beam.set_state(strength, charge, Color.WHITE)
	# Nothing is drawn at all until the pilot beam: the lock phase is the reticle's.
	if _lock_elapsed < PILOT_START:
		_beam.hide_beam()
		return
	_beam.set_endpoints(_muzzle.position, contact)


## Full cut: the contact point walks the hex perimeter and burns a seam as it
## goes, rather than sitting wherever the raycast happened to land.
func _show_cut(target: Object, fallback_contact: Vector2) -> void:
	_beam.set_state(1.0, 1.0, _cut_tint())
	if _cell.is_empty():
		_beam.set_endpoints(_muzzle.position, fallback_contact)
		return

	# Both outlines come from the target itself (HullDamageModel._describe_cell)
	# rather than being rebuilt from centre and radius here: the hull renderer
	# carries its own rotation and jitters every part off its grid cell, so a
	# hexagon reconstructed out here landed somewhere the hull was not.
	_beam.set_endpoints(_muzzle.position,
		SalvageCutTrail.perimeter_point(_cell["corners"], _last_progress))

	_ensure_trail(target)
	if _trail != null and is_instance_valid(_trail):
		_trail.advance(_cell["corners_hull"], _last_progress)

	_shake()


## The seam belongs to the hull being cut, so it is parented there and simply
## left behind when the cut ends.
func _ensure_trail(target: Object) -> void:
	if _trail != null and is_instance_valid(_trail):
		return
	if not target.has_method("get_hull_renderer_node"):
		return
	_trail = SalvageCutTrail.new()
	target.get_hull_renderer_node().add_child(_trail)


func _cut_tint() -> Color:
	return Color.WHITE.lerp(cut_progress_color, _last_progress)


func _shake() -> void:
	if shake_strength <= 0.0 or _shooter == null:
		return
	var camera: Node = _shooter.get_node_or_null("ShipCamera")
	if camera != null and camera.has_method("add_shake"):
		camera.add_shake(shake_strength)


func _on_severed(target: Object) -> void:
	if _cell.is_empty():
		return
	var burst := SalvageSeverFx.new()
	burst.z_index = EFFECT_Z_INDEX
	burst.z_as_relative = false
	WorldSpawn.attach_at(burst, _cell["center"])
	burst.burst(_cell["radius"])
	_reticle.release()
	# The seam is deliberately NOT freed: it is the socket rim on the hull the
	# part came off, and it carries on cooling there.
	_trail = null
	_power_down()


## A finished cut switches the Salvager off. post_cut_hold alone was not enough:
## the beam drew in, waited its beat and then reached straight back out, because
## the switch was still on and the cursor was still on the wreck — so one cut ran
## into the next and the tool never looked like it had finished anything.
##
## Switching the system off rather than latching this hardpoint is what makes that
## legible: SALVAGER goes dark on the systems panel, which says why the beam is
## stowed and what to press to cut again.
func _power_down() -> void:
	if _shooter == null:
		return
	var systems: ShipSystems = _shooter.get_systems()
	if systems != null:
		systems.set_switched_on(ShipSystems.SALVAGER, false)


## Draws the beam back in rather than switching it off. Once it is fully home the
## visual is hidden, which is also what stops it being drawn at a stale angle.
func _retract(delta: float) -> void:
	# A beam drawing back in from a completed cut keeps the hot colour it finished
	# on all the way home, so the last thing seen is the cut succeeding. Every
	# other retraction goes cold immediately.
	if not _finishing_cut:
		_last_result = "miss"
		_last_progress = 0.0
		_lose_lock()
	var speed: float = cut_retract_speed if _finishing_cut else extend_speed
	_current_length = move_toward(_current_length, 0.0, speed * delta)
	if _current_length <= 0.01:
		if _finishing_cut:
			_hold_remaining = post_cut_hold
		_finishing_cut = false
		_last_result = "miss"
		_last_progress = 0.0
		_lose_lock()
		_beam.hide_beam()
		return
	_beam.set_state(1.0 if _finishing_cut else 0.0, 0.0, _beam_tint())
	_beam.set_endpoints(_muzzle.position,
		_muzzle.global_position + _last_direction * _current_length)


## Dimmed while the beam is landing on something it cannot open, so "nothing is
## happening" is visible on the tool as well as on the target (which carries the
## cut-ready marker — see HullPaint.CUT_READY_COLOR).
func _beam_tint() -> Color:
	if _last_result == "intact":
		return INTACT_BEAM_FADE
	return _cut_tint()


func _exit_tree() -> void:
	# The reticle lives in the world rather than under this node, so it has to be
	# taken down by hand when the hardpoint goes (a refit, or the module being
	# shot off).
	if _reticle != null and is_instance_valid(_reticle):
		_reticle.queue_free()

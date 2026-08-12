class_name GrappleRope
extends Node2D

## The grapple line: a verlet chain that is cast, bites a severed part, wraps it
## and winches it home (docs/design_handoff_grapple/grapple-line-Godot-spec.md).
##
## **Nothing here is animated.** The unfurl, the whip, the slack bloom when the
## ship stops and the jolt as the line comes taut again all fall out of the
## simulation — HardpointWinch only calls fire/reel_to/release in order. The
## overshoot when thrust is cut is the beat the whole tool is built around: the
## rope carries momentum the ship does not, so do not "fix" it.
##
## Node 0 is the hook; every node from the drum index up is pinned to the muzzle
## each substep, so the line follows the ship for free.
##
## Lives in the world (WorldSpawn.attach) with no transform of its own, so the
## global positions it simulates need no conversion to draw. It is NOT parented
## to the hardpoint: the tip has to stay where it is in space while the ship
## flies off, which a parented node cannot do.
##
## Replaces WinchRope, which was a purely cosmetic sag drawn between two points
## the hardpoint had already decided on. Here the simulation owns the hook, so
## reach, bite and haul are consequences of it rather than of a state machine.

## Emitted the instant the hook enters a part's radius; the listener takes hold
## of the body (see CapturedTechPart.begin_reel_in).
signal hooked(body: Node2D)
## Emitted when a hooked body reaches the muzzle. The listener owns what happens
## to it — this only reports the arrival, and drops the body first so the sim
## never touches something being freed.
signal secured(body: Node2D)
## Slack -> taut. Carries the point on the line that jolted, for camera shake.
signal snapped_taut(at_global: Vector2)
## The line is fully wound in with nothing on it: safe to free.
signal stowed

## Simulation constants, tuned in the handoff's mock — see its table. The
## substep is fixed at 1/120 so the rope behaves identically regardless of frame
## rate; delta is accumulated into whole substeps instead of being fed in raw.
const SUBSTEP: float = 1.0 / 120.0
const MAX_SUBSTEPS_PER_FRAME: int = 8
## A link leaving the drum inherits this much of the line's current velocity.
## Spawning new links at rest turns the spool into a brake and the hook stalls at
## half range — per the spec this is the single most important number here.
const PAYOUT_INHERIT: float = 0.98
const TAUT_THRESHOLD: float = 0.35

@export var nodes: int = 64
@export var rest_length: float = 13.0
@export var iterations: int = 12
## Zero gravity: this is the only energy loss in the system.
@export var damping: float = 0.997
@export var cast_speed: float = 820.0
## The line spools to stay this much longer than the hook is far, so it trails
## rather than dragging the hook back.
@export var payout_slack: float = 60.0
## Slack taken up after a bite, until the line is taut. Stops there.
@export var take_up_rate: float = 300.0
@export var wrap_links: int = 10
@export var wrap_time: float = 0.9
## Only the outermost wrapped link hauls the body. If every wrapped link pushed,
## ten links would pull at once and a hull section would come in like paper.
@export var load_transfer: float = 0.055
## Mass stand-in, paired with load_transfer: the line pulls a few tonnes, it
## never flings them.
@export var body_speed_cap: float = 52.0
@export var body_speed_cap_reeling: float = 105.0
## How much shorter than the span it has to cross a loaded line is wound — the
## stretch the chain carries while hauling, and so what sets its tension during a
## haul (see _load_limited_length). Roughly a link and a quarter, which lands
## tension just above the loaded-line glow threshold and leaves headroom for the
## jolts on top.
@export var load_stretch: float = 16.0
## Tension normaliser: the total constraint correction on the first solver
## iteration is divided by this and clamped to 0..1.
##
## The spec's 22 is the one number here that did not carry over. Measured on this
## project's line, a free cast sums 5-7 and a loaded haul 50-60, so 22 pinned
## tension at 1.0 for every haul from end to end — which left the loaded-line
## glow permanently maxed and fired the taut jolt fourteen times per pull instead
## of once. 70 puts a haul around 0.8 with headroom for the jolts on top.
@export var tension_scale: float = 70.0
## Slack around a part's own extent (DriftingHexPiece.get_winch_radius) that
## still counts as a bite.
@export var bite_margin: float = 6.0
## Surface gap at which the winch stops relying on the chain and simply hauls the
## part in against the drum (see _draw_in).
@export var dock_distance: float = 55.0
## How close a hauled part's own *surface* has to get to the muzzle to count as
## delivered — measured off the surface because a two-hex part is some 80 units
## across, and asking its centre to reach the maw would mean driving its middle
## into the hull first.
@export var secure_radius: float = 8.0

var tension: float = 0.0

var _anchor: Node2D
var _chain: GrappleChain
var _impact_sparks: GPUParticles2D
var _impact_grit: GPUParticles2D
var _strain_fx: GPUParticles2D

var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _deployed: int = 3
var _line_length: float = 0.0
var _max_length: float = 0.0
var _cast_out: bool = false
var _hooked_body: Node2D = null
## Where on the body the hook bit, in the body's own frame, so the wrap spiral
## starts where the chain actually landed.
var _hook_angle: float = 0.0
var _wrap_elapsed: float = 0.0
var _wrapped: int = 0
var _taut: bool = false
var _took_up: bool = false
var _reeling: bool = false
## True only while the hook is still flying out unhindered. Cleared by the first
## bite and by the first touch of the winch — see _advance_payout.
var _casting: bool = false
var _stowed_emitted: bool = false
var _reel_from: float = 0.0
var _reel_target: float = 0.0
var _reel_duration: float = 1.0
var _reel_elapsed: float = 0.0
var _accumulated: float = 0.0
## Set once the hooked body has been handed over, so its speed cap starts fresh
## on the next haul rather than from a stale frame.
var _body_previous: Vector2 = Vector2.ZERO


func _ready() -> void:
	_chain = GrappleChain.new()
	add_child(_chain)
	_impact_sparks = GrappleFx.sparks(46)
	_impact_grit = GrappleFx.grit(16)
	_strain_fx = GrappleFx.strain(10)
	add_child(_impact_sparks)
	add_child(_impact_grit)
	add_child(_strain_fx)
	_reset()


## `anchor` is the muzzle the line pays out of — its global position is read
## every substep, so the drum end tracks the ship without this node moving.
## `max_length` caps how much chain there is; 0 means the full 64 x 13 capacity.
func setup(anchor: Node2D, max_length: float = 0.0) -> void:
	_anchor = anchor
	_max_length = max_length if max_length > 0.0 else float(nodes) * rest_length


func fire(direction: Vector2) -> void:
	_reset()
	_cast_out = true
	_casting = true
	# The hook is given its speed as verlet history rather than as a velocity
	# field: there is no velocity field, position and previous position are all
	# the integrator has.
	_prev[0] = _pos[0] - direction.normalized() * cast_speed * SUBSTEP


func is_hooked() -> bool:
	return _hooked_body != null and is_instance_valid(_hooked_body)


func line_length() -> float:
	return _line_length


func is_reeling() -> bool:
	return _reeling


## The length to wind a loaded line down to: the full wrap plus the shortest run
## of free chain the solver can still pull with.
##
## Winding in further does not bring the part any closer. _advance_wrap caps the
## turns at `deployed - 3`, so past this point every extra link wound in comes
## straight back off the wrap and the free run stays exactly three segments long
## either way. Zero with nothing on the hook — an empty line comes all the way
## home and the rope stows itself.
func secured_line_length() -> float:
	if not is_hooked():
		return 0.0
	return rest_length * float(wrap_links + 1)


## Winch: close to `target_length` over `seconds`, eased in and out. Restarting
## one mid-reel is fine — it re-bases on the current length.
func reel_to(target_length: float, seconds: float) -> void:
	_reel_from = _line_length
	_reel_target = maxf(target_length, 0.0)
	_reel_duration = maxf(seconds, 0.01)
	_reel_elapsed = 0.0
	_reeling = true
	_casting = false


## Stops winding without retracting — the line simply holds whatever length it
## has reached (the player letting go of the reel).
func stop_reel() -> void:
	_reeling = false


## Drops whatever is on the hook and winds the line all the way home. The spec
## leaves 40px of chain out here; this project despawns the rope between casts
## instead, so it comes fully in and reports `stowed`.
func release() -> void:
	_hooked_body = null
	_wrapped = 0
	reel_to(0.0, 0.8)


func _physics_process(delta: float) -> void:
	_accumulated += delta
	var steps: int = 0
	while _accumulated >= SUBSTEP and steps < MAX_SUBSTEPS_PER_FRAME:
		_step(SUBSTEP)
		_accumulated -= SUBSTEP
		steps += 1
	# A frame long enough to exhaust the substep budget would otherwise build up
	# a backlog it can never clear, and the rope would run in slow motion.
	if steps >= MAX_SUBSTEPS_PER_FRAME:
		_accumulated = 0.0
	_update_visuals()


func _reset() -> void:
	_pos.resize(nodes)
	_prev.resize(nodes)
	var muzzle: Vector2 = _muzzle_position()
	for i in nodes:
		_pos[i] = muzzle
		_prev[i] = muzzle
	_deployed = 3
	_line_length = 0.0
	_cast_out = false
	_hooked_body = null
	_wrapped = 0
	_wrap_elapsed = 0.0
	tension = 0.0
	_taut = false
	_took_up = false
	_reeling = false
	_casting = false
	_stowed_emitted = false


func _muzzle_position() -> Vector2:
	if _anchor != null and is_instance_valid(_anchor):
		return _anchor.global_position
	return global_position


func _step(step: float) -> void:
	var muzzle: Vector2 = _muzzle_position()
	if not _cast_out:
		for i in nodes:
			_pos[i] = muzzle
			_prev[i] = muzzle
		return

	# A hauled part can be taken out from under the line — a region change, or
	# anything else that clears the scene. Winding home rather than just dropping
	# the reference, so a reel that was aimed at a length that only made sense
	# with a load on it re-targets and the rope still stows itself.
	if _hooked_body != null and not is_instance_valid(_hooked_body):
		release()

	_advance_payout(step, muzzle)
	_integrate(muzzle)
	_advance_wrap(step)
	_solve(step)
	_check_bite()
	_check_secured(muzzle)
	_check_stowed()


## How much chain is out.
##
## The drum only ever feeds line out while the cast is still in flight. Once the
## hook has bitten, or the player has touched the winch, the line is never paid
## out again — it is taken up, wound in, or held. Letting the payout branch run
## after a reel meant the drum immediately fed the line back out to follow the
## hook it had just pulled in, and the haul went nowhere.
func _advance_payout(step: float, muzzle: Vector2) -> void:
	var hook_distance: float = _pos[0].distance_to(muzzle)

	if _reeling:
		_reel_elapsed = minf(_reel_duration, _reel_elapsed + step)
		var u: float = _reel_elapsed / _reel_duration
		_line_length = lerpf(_reel_from, _reel_target, u * u * (3.0 - 2.0 * u))
		_line_length = maxf(_line_length, _load_limited_length())
		# A finished wind holds its length rather than clearing _reeling: the
		# body is still being dragged up the taut line long after the drum has
		# stopped turning, and that is the whole haul.
	elif is_hooked() and not _took_up:
		_line_length = maxf(hook_distance + 8.0, _line_length - take_up_rate * step)
		if _line_length <= hook_distance + 9.0:
			_took_up = true
	elif _casting:
		_line_length = maxf(_line_length, hook_distance + payout_slack)

	# Running out of chain is what enforces the grapple's reach: the hook simply
	# stops being able to pay out and the constraint solver reels it up short.
	_line_length = minf(_line_length, _max_length)

	var deployed: int = int(clampf(_line_length / rest_length + 2.0, 3.0, float(nodes)))
	if deployed > _deployed:
		var hook_velocity: Vector2 = _pos[0] - _prev[0]
		for i in range(maxi(0, _deployed - 1), deployed - 1):
			_pos[i] = muzzle
			_prev[i] = muzzle - hook_velocity * PAYOUT_INHERIT
	_deployed = deployed


## The shortest the drum can actually have wound to, given how far behind the
## load is: everything the wrap has consumed, plus the span still to cross, less
## the stretch the line is carrying.
##
## A winch under load stalls — it cannot wind in line the hunk has not travelled.
## Without this the drum kept turning while the hunk lagged, the line ended up
## wound far shorter than the distance it had to span, and it sat pinned at
## maximum tension for the entire haul. That reads as a taut cable rather than a
## working chain, and it makes `tension` useless as a signal, since the one thing
## it is for is telling a loaded line from a slack one.
func _load_limited_length() -> float:
	if not is_hooked():
		return 0.0
	var span: float = _muzzle_position().distance_to(_hooked_body.global_position) \
		- _body_radius(_hooked_body)
	return maxf(span, 0.0) + rest_length * float(_wrapped) - load_stretch


func _integrate(muzzle: Vector2) -> void:
	for i in nodes:
		if i >= _deployed - 1:
			_pos[i] = muzzle
			_prev[i] = muzzle
			continue
		var velocity: Vector2 = (_pos[i] - _prev[i]) * damping
		_prev[i] = _pos[i]
		_pos[i] += velocity


## Lays links onto a closing spiral around the hooked body. Pinned outright
## rather than constrained: these are wound on, not hanging.
func _advance_wrap(step: float) -> void:
	if not is_hooked():
		return
	_wrap_elapsed = minf(1.0, _wrap_elapsed + step / wrap_time)
	var eased: float = _wrap_elapsed * _wrap_elapsed * (3.0 - 2.0 * _wrap_elapsed)
	# Never more turns than there is deployed chain to make them with: a bite at
	# point-blank range has only a few links out, and wrapping all of them leaves
	# the solver with nothing free to haul on.
	_wrapped = mini(int(round(lerpf(1.0, float(wrap_links), eased))), maxi(1, _deployed - 3))

	var body_radius: float = _body_radius(_hooked_body)
	for i in _wrapped:
		var along: float = float(i) / float(wrap_links)
		var angle: float = _hooked_body.global_rotation + _hook_angle + along * 5.4
		var radius: float = lerpf(body_radius + 3.0, body_radius - 9.0, eased) - along * 2.4
		_pos[i] = _hooked_body.global_position + Vector2(cos(angle), sin(angle)) * radius
		_prev[i] = _pos[i]


## Distance constraints, plus the one place the line does work on the world.
func _solve(step: float) -> void:
	var correction_total: float = 0.0

	for iteration in iterations:
		for i in range(0, _deployed - 1):
			var span: Vector2 = _pos[i + 1] - _pos[i]
			var distance: float = maxf(span.length(), 0.0001)
			# One-sided: chain resists being stretched, never being bunched up.
			if distance <= rest_length:
				continue
			var excess: float = (distance - rest_length) / distance
			var a_pinned: bool = i < _wrapped
			var b_pinned: bool = (i + 1 >= _deployed - 1) or (i + 1 < _wrapped)
			if a_pinned and b_pinned:
				continue
			var a_share: float = 0.0 if a_pinned else (1.0 if b_pinned else 0.5)
			var b_share: float = 0.0 if b_pinned else (1.0 if a_pinned else 0.5)
			if iteration == 0:
				correction_total += distance - rest_length
			_pos[i] += span * excess * a_share
			_pos[i + 1] -= span * excess * b_share
			if a_pinned and i == _wrapped - 1 and is_hooked():
				_hooked_body.global_position += span * excess * load_transfer

	if is_hooked():
		_draw_in(step)
		_cap_body_speed(step)

	var was_taut: bool = _taut
	tension = clampf(correction_total / maxf(tension_scale, 0.001), 0.0, 1.0)
	_taut = tension > TAUT_THRESHOLD
	if _taut and not was_taut:
		var at: int = clampi(mini(_deployed - 2, _wrapped + 4), 0, _pos.size() - 1)
		GrappleFx.burst(_strain_fx, _pos[at])
		snapped_taut.emit(_pos[at])


## The last stretch onto the collector.
##
## The solver on its own cannot bring a part any closer than about three free
## links plus the part's own radius. _advance_wrap caps the turns at
## `deployed - 3`, so there is always some un-pinned chain left between the wrap
## and the drum — and that leftover chain is exactly what the haul pulls on, so it
## cannot be wound away. On a one-hex part that left it hanging some 60 units off
## the hull at the moment it was collected, visibly short of the maw.
##
## Inside dock_distance the winch stops pulling through the chain and hauls the
## part in against the drum directly, which is what a winch does once its load
## reaches the fairlead. Still speed-capped like any other haul, and still only
## while the player is actually winching.
func _draw_in(step: float) -> void:
	if not _reeling:
		return
	var to_muzzle: Vector2 = _muzzle_position() - _hooked_body.global_position
	var gap: float = to_muzzle.length() - _body_radius(_hooked_body)
	if gap > dock_distance or gap <= 0.0:
		return
	_hooked_body.global_position += to_muzzle.normalized() 		* minf(body_speed_cap_reeling * step, gap)


func _cap_body_speed(step: float) -> void:
	var moved: Vector2 = _hooked_body.global_position - _body_previous
	var cap: float = body_speed_cap_reeling if _reeling else body_speed_cap
	if moved.length() > cap * step:
		_hooked_body.global_position = _body_previous + moved.normalized() * cap * step
	_body_previous = _hooked_body.global_position


func _check_bite() -> void:
	if is_hooked():
		return
	var body: Node2D = _overlapping_part(_pos[0])
	if body == null:
		return
	_hooked_body = body
	_body_previous = body.global_position
	_hook_angle = (_pos[0] - body.global_position).angle() - body.global_rotation
	_wrap_elapsed = 0.0
	_took_up = false
	_casting = false
	GrappleFx.burst(_impact_sparks, _pos[0])
	GrappleFx.burst(_impact_grit, _pos[0])
	hooked.emit(body)


## The drum is home and carrying nothing, however it got there — a wind that ran
## to completion, a reel the player stopped a hair short, or a load that vanished
## mid-haul. Tested as a state rather than announced at the end of a particular
## reel, because every way of ending up here that was not that one reel left the
## rope alive with no way to stow, and the hardpoint reads a live rope as "a line
## is already out" and refuses to cast again.
func _check_stowed() -> void:
	if _stowed_emitted or _casting or not _cast_out:
		return
	if is_hooked() or _line_length > 1.0:
		return
	_stowed_emitted = true
	stowed.emit()


func _check_secured(muzzle: Vector2) -> void:
	if not is_hooked():
		return
	var reach: float = _body_radius(_hooked_body) + secure_radius
	if _hooked_body.global_position.distance_to(muzzle) > reach:
		return
	var body: Node2D = _hooked_body
	# Dropped before the signal so a listener that frees the part cannot leave
	# the sim wrapping a dead node for the rest of this frame's substeps.
	_hooked_body = null
	_wrapped = 0
	secured.emit(body)


func _overlapping_part(point: Vector2) -> Node2D:
	for node in get_tree().get_nodes_in_group("capturable_tech"):
		var part: Node2D = node
		if point.distance_to(part.global_position) <= _body_radius(part) + bite_margin:
			return part
	return null


func _body_radius(body: Node2D) -> float:
	if body.has_method("get_winch_radius"):
		return body.get_winch_radius()
	return rest_length * 2.0


func _update_visuals() -> void:
	if not _cast_out:
		_chain.update_chain(PackedVector2Array(), 0.0)
		return
	var points := PackedVector2Array()
	for i in maxi(3, _deployed):
		points.append(to_local(_pos[i]))
	_chain.update_chain(points, tension)

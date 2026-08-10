class_name HardpointWinch
extends Node2D

## A hardpoint that casts a physical rope (see WinchRope) instead of firing
## a projectile: press fire_winch (see Ship.fire_winch) to shoot the rope
## out in this hardpoint's own facing direction (its placement's
## rotation_steps — see HardpointBank._mount_winch — not aimed at the
## mouse like a gun).
##
## The rope always stays paid out until the player reels it back in by
## holding fire_winch — it does NOT auto-retract on a miss, only on a
## completed tech-part capture (nothing left to interact with there).
##
## It catches severed parts and nothing else (see _reel_in_tech_part: always
## pulled to the ship, captured on arrival).
##
## It used to also grapple ships and asteroids, hauling the two ends together
## with equal-and-opposite impulses — a genuinely interesting toy, but one that
## made the winch fire off in unpredictable directions in ordinary combat and
## turned the salvage tool into a movement tool. This is the recovery half of the
## cut-and-take loop, so it now only ever grabs what the Slicer freed. Nothing of
## the grapple remains: reinstating it means writing it again deliberately, with
## its own button, rather than having it fall out of the salvage winch by
## accident.

enum State { IDLE, FIRING, ATTACHED, EXTENDED, RETRACTING }

## Fallback touch radius for a part that somehow reports no extent of its own
## (see DriftingHexPiece.get_winch_radius).
const DEFAULT_TARGET_RADIUS: float = 24.0

@export var winch_rope_scene: PackedScene = preload("res://scenes/player/winch_rope.tscn")
@export var max_range: float = 320.0
@export var fire_speed: float = 900.0
## Reel speed for a CapturedTechPart (direct position pull) and for
## retrieving an empty rope after a miss — deliberately slow, a hand-cranked
## winch rather than an instant snap.
@export var reel_speed: float = 140.0
## Only used for the automatic snap-back after a completed tech-part
## capture — see State.RETRACTING.
@export var retract_speed: float = 700.0
## How close the rope tip must get to a target to attach/arrive.
@export var attach_radius: float = 20.0
@export var energy_cost_per_second: float = 6.0

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## HardpointGun.source_placement_id.
var source_placement_id: String = ""

var _state: State = State.IDLE
var _shooter: Ship
var _rope: WinchRope = null
var _tip_position: Vector2 = Vector2.ZERO
var _paid_out_length: float = 0.0
var _attached_target: Node2D = null
var _reel_input_held: bool = false

@onready var _muzzle: Marker2D = $Muzzle


func setup(shooter: Ship) -> void:
	_shooter = shooter


## The rope is parented to the current scene (not to this hardpoint) so it can
## span from the muzzle to a world-space tip. That means it does NOT get freed
## along with this node — a ship destroyed, or a module severed, mid-cast used
## to leave its rope in the scene forever.
func _exit_tree() -> void:
	if _rope != null and is_instance_valid(_rope):
		_rope.queue_free()
	_rope = null


## Called once on the fire_winch action's just-pressed edge (see
## Ship.fire_winch) — starts casting if idle, otherwise does nothing (an
## attached/firing/extended rope has to resolve on its own first).
func fire() -> void:
	if _state == State.IDLE:
		_start_firing()


## Called every physics frame with the fire_winch action's current held
## state (see ShipIntent.winch_reel) — matters while ATTACHED (reels the
## target in) or EXTENDED (reels an empty rope back home).
func set_reel_input(is_held: bool) -> void:
	_reel_input_held = is_held


func _physics_process(delta: float) -> void:
	match _state:
		State.FIRING:
			_advance_firing(delta)
		State.ATTACHED:
			_advance_attached(delta)
		State.EXTENDED:
			_advance_extended(delta)
		State.RETRACTING:
			_advance_retracting(delta)
		State.IDLE:
			pass


func _start_firing() -> void:
	if _shooter == null:
		return
	_state = State.FIRING
	_tip_position = _muzzle.global_position
	_paid_out_length = 0.0
	_rope = winch_rope_scene.instantiate()
	WorldSpawn.attach(_rope)


func _advance_firing(delta: float) -> void:
	var direction: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	_tip_position += direction * fire_speed * delta
	_paid_out_length += fire_speed * delta
	_rope.update_rope(_muzzle.global_position, _tip_position, _paid_out_length)

	var hit: Node2D = _find_touching_target(_tip_position)
	if hit != null:
		_attach_to(hit)
		return

	# Fully extended without hitting anything: stop paying out rope, but stay
	# out — see State.EXTENDED — rather than auto-retracting.
	if _paid_out_length >= max_range:
		_paid_out_length = max_range
		_tip_position = _muzzle.global_position + direction * max_range
		_state = State.EXTENDED


func _find_touching_target(point: Vector2) -> Node2D:
	return _find_capturable_part_at(point)


## Catches on the part's actual extent, the same way a ship or asteroid is
## caught. Testing against attach_radius alone meant a 20-unit window on
## something ~80 units across, with a rope tip covering 15 units per frame — so
## the rope routinely passed straight through a part it visibly hit.
func _find_capturable_part_at(point: Vector2) -> Node2D:
	for node in get_tree().get_nodes_in_group("capturable_tech"):
		var part: CapturedTechPart = node
		if point.distance_to(part.global_position) <= attach_radius + _effective_radius(part):
			return part
	return null


func _effective_radius(node: Node2D) -> float:
	if node.has_method("get_winch_radius"):
		return node.get_winch_radius()
	return DEFAULT_TARGET_RADIUS


func _attach_to(target: Node2D) -> void:
	_state = State.ATTACHED
	_attached_target = target
	if target.has_method("begin_reel_in"):
		target.call("begin_reel_in")


func _advance_attached(delta: float) -> void:
	if not is_instance_valid(_attached_target):
		_release()
		return

	if _reel_input_held:
		_reel_in(delta)
	else:
		# Not reeling: the rope just holds its current length. A caught part has
		# already stopped drifting under its own momentum (see
		# CapturedTechPart.begin_reel_in), so it simply hangs there.
		_hold_rope_to_target()


## Keeps the tracked tip on the target as well as drawing the rope there.
##
## _tip_position is otherwise only written while the rope is paying out, so an
## attached rope's tracked tip stayed frozen at wherever it first caught. Any
## retract then started from that stale point — the rope visibly flung itself
## back out to the original attach distance before reeling in.
func _hold_rope_to_target() -> void:
	_tip_position = _attached_target.global_position
	_paid_out_length = _muzzle.global_position.distance_to(_tip_position) + 1.0
	_rope.update_rope(_muzzle.global_position, _tip_position, _paid_out_length)


## Only one kind of thing can ever be attached now, so this forwards straight to
## the part reel instead of branching on the target's type.
func _reel_in(delta: float) -> void:
	_reel_in_tech_part(delta)


func _reel_in_tech_part(delta: float) -> void:
	if _shooter == null or not _shooter.spend_energy(energy_cost_per_second * delta):
		_hold_rope_to_target()
		return

	var to_muzzle: Vector2 = _muzzle.global_position - _attached_target.global_position
	var distance: float = to_muzzle.length()
	var travel: float = minf(reel_speed * delta, distance)
	if distance > 0.001:
		_attached_target.global_position += to_muzzle.normalized() * travel

	if distance - travel <= attach_radius:
		_complete_capture()
		return

	# Tracked as well as drawn, for the same reason as _hold_rope_to_target.
	_tip_position = _attached_target.global_position
	_paid_out_length = distance - travel + 1.0
	_rope.update_rope(_muzzle.global_position, _tip_position, _paid_out_length)


func _complete_capture() -> void:
	_shooter.capture_tech_part(_attached_target.release_instance())
	_attached_target.collect()
	_attached_target = null
	# The part arrived at the muzzle, so the rope is already home — there is no
	# length left to wind in. Saying so explicitly means RETRACTING finishes on
	# its next tick instead of playing a retract of whatever length the rope
	# happened to be cast at.
	_tip_position = _muzzle.global_position
	_paid_out_length = 0.0
	_state = State.RETRACTING


## Lets go without capturing anything, leaving the rope paid out for a manual
## reel (see State.EXTENDED). Only reachable now when the attached part is freed
## from under the winch — it drifted out its lifetime, or something else took
## it — since a part that arrives is captured instead.
##
## Previously this was also the normal end of a grapple, firing once a ship or
## asteroid had been hauled close enough.
func _release() -> void:
	_attached_target = null
	_state = State.EXTENDED


func _advance_extended(delta: float) -> void:
	if _reel_input_held:
		_paid_out_length = maxf(_paid_out_length - reel_speed * delta, 0.0)

	# Unattached, the tip isn't holding onto anything in the world — it just
	# rides along with the ship at whatever length it stopped paying out at
	# (shrinking while reeling), rigidly in the hardpoint's fixed facing
	# direction, rather than being left behind as a dead point in space.
	var direction: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	_tip_position = _muzzle.global_position + direction * _paid_out_length
	_rope.update_rope(_muzzle.global_position, _tip_position, maxf(_paid_out_length, 1.0))

	if _paid_out_length <= 0.0:
		_finish_retract()


func _advance_retracting(delta: float) -> void:
	_paid_out_length = maxf(_paid_out_length - retract_speed * delta, 0.0)
	_tip_position = _tip_position.move_toward(_muzzle.global_position, retract_speed * delta)
	if _rope != null:
		_rope.update_rope(_muzzle.global_position, _tip_position, maxf(_paid_out_length, 1.0))

	if _paid_out_length <= 0.0:
		_finish_retract()


func _finish_retract() -> void:
	if _rope != null:
		_rope.queue_free()
		_rope = null
	_state = State.IDLE

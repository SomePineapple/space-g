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
## It can catch a CapturedTechPart (see _reel_in_tech_part — unchanged
## behavior: always pulled to the ship, captured on arrival) or grapple onto
## anything in the player_ship/enemy_ship/lockable groups (other ships,
## asteroids — see _reel_in_physics_target). Grappling reuses Ship's
## existing apply_impulse (the same mechanism as weapon recoil): pulling
## impulses are applied equal-and-opposite to both ends, so
## `velocity += impulse / mass` naturally makes the lighter side accelerate
## more — no separate "weight" comparison needed. An Asteroid has no
## apply_impulse at all (StaticBody2D, genuinely immovable), so grappling one
## always pulls the ship toward it instead — the "use the winch as a
## thruster substitute" case.

enum State { IDLE, FIRING, ATTACHED, EXTENDED, RETRACTING }

## Groups (besides "capturable_tech") scanned for a generic grapple target —
## covers enemy ships, the player's own ship (if some other shooter ever
## fires at it), and asteroids (also "lockable").
const GENERIC_TARGET_GROUPS: Array[String] = ["player_ship", "enemy_ship", "lockable"]
## Fallback touch radius for a generic target with no get_winch_radius().
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
## Acceleration fed into apply_impulse/sec while grappling a ship/asteroid —
## see _reel_in_physics_target.
@export var ship_pull_force: float = 400.0
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
## state (see Ship.set_winch_reel_input) — matters while ATTACHED (reels the
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
	get_tree().current_scene.add_child(_rope)


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
	var tech_part: Node2D = _find_capturable_part_at(point)
	if tech_part != null:
		return tech_part
	return _find_generic_target_at(point)


func _find_capturable_part_at(point: Vector2) -> Node2D:
	for node in get_tree().get_nodes_in_group("capturable_tech"):
		var part: CapturedTechPart = node
		if point.distance_to(part.global_position) <= attach_radius:
			return part
	return null


func _find_generic_target_at(point: Vector2) -> Node2D:
	var seen: Dictionary = {}
	for group_name in GENERIC_TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == _shooter or seen.has(node):
				continue
			seen[node] = true
			var candidate: Node2D = node
			if point.distance_to(candidate.global_position) <= attach_radius + _effective_radius(candidate):
				return candidate
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
		# Not reeling: the rope just holds its current length, following
		# wherever the attached target currently is (a grappled ship keeps
		# moving under its own steam; a caught tech part doesn't drift away
		# under its own momentum once caught — see CapturedTechPart.begin_reel_in).
		_hold_rope_to_target()

	# A tech part is always pulled fully to the ship (see _reel_in_tech_part)
	# — the tether cap only matters for a grapple onto something that isn't
	# just going to be reeled all the way in, i.e. a ship/asteroid.
	if not (_attached_target is CapturedTechPart):
		_enforce_tether_limit()


func _hold_rope_to_target() -> void:
	_rope.update_rope(_muzzle.global_position, _attached_target.global_position,
		_muzzle.global_position.distance_to(_attached_target.global_position) + 1.0)


## The rope's paid-out length (however far it had traveled when it caught
## the target — see _attach_to/_paid_out_length, which never grows again
## once attached) is a hard cap on how far the shooter can be from the
## target, not just something that matters while actively reeling — a real
## taut rope stops you, it doesn't just sit there while your thrusters keep
## fighting it. Only pulls the shooter back (not the target); killing the
## outward-radial velocity component stops the ship fighting the tether
## every frame instead of coming to a firm stop against it.
func _enforce_tether_limit() -> void:
	var to_target: Vector2 = _attached_target.global_position - _shooter.global_position
	var distance: float = to_target.length()
	if distance <= _paid_out_length or distance < 0.0001:
		return

	var direction_to_target: Vector2 = to_target / distance
	var excess: float = distance - _paid_out_length
	_shooter.global_position += direction_to_target * excess

	var outward_speed: float = _shooter.velocity.dot(-direction_to_target)
	if outward_speed > 0.0:
		_shooter.velocity += direction_to_target * outward_speed


func _reel_in(delta: float) -> void:
	if _attached_target is CapturedTechPart:
		_reel_in_tech_part(delta)
	else:
		_reel_in_physics_target(delta)


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

	_rope.update_rope(_muzzle.global_position, _attached_target.global_position, distance - travel + 1.0)


## Pulls a physics-capable target (Ship, or anything else exposing
## apply_impulse) toward the shooter and vice versa via equal-and-opposite
## impulses — see class comment for why this needs no explicit weight
## comparison: apply_impulse already divides by each side's own mass.
func _reel_in_physics_target(delta: float) -> void:
	if _shooter == null or not _shooter.spend_energy(energy_cost_per_second * delta):
		_hold_rope_to_target()
		return

	var to_target: Vector2 = _attached_target.global_position - _shooter.global_position
	var distance: float = to_target.length()
	if distance <= attach_radius + _effective_radius(_attached_target):
		_release()
		return

	var direction_to_target: Vector2 = to_target / distance
	var pull_impulse: float = ship_pull_force * delta
	_shooter.apply_impulse(direction_to_target * pull_impulse)
	if _attached_target.has_method("apply_impulse"):
		_attached_target.call("apply_impulse", -direction_to_target * pull_impulse)

	_hold_rope_to_target()


func _complete_capture() -> void:
	_shooter.capture_tech_part(_attached_target.module_type_id)
	_attached_target.collect()
	_attached_target = null
	_state = State.RETRACTING


## A grapple attachment (ship/asteroid) just lets go once close enough —
## unlike a tech-part capture, there's nothing to collect, and the rope
## still needs a manual reel to come all the way home (see State.EXTENDED).
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

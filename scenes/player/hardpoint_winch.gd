class_name HardpointWinch
extends Node2D

## The Grapple hardpoint (Mk1/Mk2/Mk3 — see ModuleCatalog._grapple_types): the
## recovery half of the salvage loop. The Slicer frees a part, this drags it
## home.
##
## One key runs the whole tool, a press at a time: cast, wind in, stop (see
## press()). The line is cast along this hardpoint's own facing, not at the
## mouse — a grapple is bolted to the hull pointing one way, and which way that
## is, is the placement decision the builder screen is for.
##
## It catches severed parts and nothing else. A caught part is hauled to the ship
## and then *stays on the line* — see _on_secured.
##
## **All the motion belongs to GrappleRope.** This script owns intent and
## consequences — when to cast, when to wind in, what energy that costs, what
## happens to a part that arrives — and nothing else. It used to own a tip
## position it advanced by hand along a straight line, with WinchRope drawn
## between that tip and the muzzle as decoration; the states that needed
## (FIRING/ATTACHED/EXTENDED/RETRACTING) were all restatements of things the
## simulation now knows for itself. Casting, biting, wrapping, hauling and
## running out of chain are all consequences of the rope sim
## (docs/design_handoff_grapple/grapple-line-Godot-spec.md), which is why the
## line overshoots the bow when the ship stops instead of snapping rigid.
##
## It used to also grapple ships and asteroids, hauling the two ends together
## with equal-and-opposite impulses — a genuinely interesting toy, but one that
## made the tool fire off in unpredictable directions in ordinary combat and
## turned the salvage tool into a movement tool. Nothing of that remains:
## reinstating it means writing it again deliberately, with its own button.

## Chain capacity, in world units. The spec's line is 64 nodes at 13px rest
## length, so 832 is the whole drum — reeling this in is the tool's reach, and
## the knob to turn if the grapple should out-range or under-range the Slicer's
## 420.
@export var max_range: float = 832.0
## How fast the winch closes the line, in world units per second. The spec's
## secured beat winds ~700px down to ~178px over 2.1s; that rate is this. Each
## pull is issued as a GrappleRope.reel_to over a duration derived from it, so
## the ease-in-out of the spec's winch is kept while the player still controls
## the reel by holding the button.
@export var reel_speed: float = 250.0
@export var energy_cost_per_second: float = 6.0
## Camera kick when a slack line comes taut, from the spec's ±2.4px jolt.
@export var jolt_shake: float = 2.4

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, same convention as
## HardpointGun.source_placement_id.
var source_placement_id: String = ""

var _shooter: Ship
var _rope: GrappleRope = null
## Whether the player has the winch switched on. Latched by press(), not held —
## a brownout pauses the drum without clearing this, so the haul resumes on its
## own once the reactor catches up rather than needing another press.
var _winching: bool = false

@onready var _muzzle: Marker2D = $Muzzle


## Moves the point the rope leaves from to wherever this module's art draws its
## aperture (see ModuleType.muzzle_offset_cells) — a hardpoint sits at its
## footprint's centroid, which on the Grapple marks is not where the hole is.
## `offset` is already in pixels, in this node's own local space.
func set_muzzle_offset(offset: Vector2) -> void:
	_muzzle.position = offset


## Which way the chain pays out: straight out of the aperture, along this
## hardpoint's own facing.
##
## Local -y rather than +x, because that is the direction the module art calls
## "forward". A hardpoint is mounted with the hull renderer's fixed 90° built
## into its rotation (HardpointBank._fixed_facing), so local -y is the ship's
## nose at rotation_steps 0 — the same convention muzzle_offset_cells is measured
## in and the Slicer's muzzle uses. Firing along +x sent the chain out of the
## ship's right flank while the aperture pointed forward.
func _fire_direction() -> Vector2:
	return Vector2.UP.rotated(global_rotation)


func setup(shooter: Ship) -> void:
	_shooter = shooter


## The rope is parented to the world (not to this hardpoint) so it can hold its
## tip in space while the ship flies away from it. That means it does NOT get
## freed along with this node — a ship destroyed, or a module severed, mid-cast
## used to leave its rope in the scene forever.
func _exit_tree() -> void:
	if _rope != null and is_instance_valid(_rope):
		_rope.queue_free()
	_rope = null


## One press of the grapple key, and the whole of its control (see
## Ship.press_winch). What it does depends on what the grapple is doing:
##
##   drum empty      cast the line
##   line out, idle  start the winch
##   winching        stop the winch, leaving the line where it is
##
## Deliberately not hold-to-reel. Held reeling meant a press and a hold were the
## same gesture, so anything but a flick of the key cast the line and immediately
## began winding it back in — you could not throw the grapple and leave it out.
## Casting and hauling are two decisions, so they are two presses.
func press() -> void:
	if _shooter == null:
		return
	_forget_dead_rope()
	# A press while something is on the hook and already home lets it go. That is
	# the only way to get rid of a part you have decided not to keep without
	# opening a screen, and it is the same key that caught it.
	if is_towing():
		drop_tow()
		return
	if _rope == null:
		_cast()
		return
	_winching = not _winching


## Whether this grapple is the one currently holding the ship's towed part.
func is_towing() -> bool:
	if _shooter == null or _rope == null or not is_instance_valid(_rope):
		return false
	return _shooter.get_towed_part() != null and _rope.is_hooked()


## Lets the towed part go, drifting from where it was. The chain draws itself
## back in on its own once nothing is on the end of it.
func drop_tow() -> void:
	if _shooter == null:
		return
	var part: Node2D = _shooter.get_towed_part()
	if part != null and part.has_method("end_reel_in"):
		part.call("end_reel_in")
	_shooter.clear_tow()
	if _rope != null and is_instance_valid(_rope):
		_rope.release()
	_winching = false


func _cast() -> void:
	_rope = GrappleRope.new()
	_rope.hooked.connect(_on_hooked)
	_rope.secured.connect(_on_secured)
	_rope.snapped_taut.connect(_on_snapped_taut)
	_rope.stowed.connect(_on_stowed)
	WorldSpawn.attach(_rope)
	_rope.setup(_muzzle, max_range)
	_rope.fire(_fire_direction())
	_winching = false


## A rope can be taken out from under this hardpoint without _on_stowed ever
## running — it lives in the world, so a region change or anything else that
## clears the scene frees it. The reference left behind is non-null but dead, and
## treating that as "a line is still out" wedged the grapple permanently: every
## later press was read as a winch toggle for a rope that no longer existed, and
## the key appeared to stop working.
func _forget_dead_rope() -> void:
	if _rope != null and not is_instance_valid(_rope):
		_rope = null
		_winching = false


func _physics_process(delta: float) -> void:
	_forget_dead_rope()
	if _rope == null:
		return

	if not _winching:
		if _rope.is_reeling():
			_rope.stop_reel()
		return

	# Hauling costs power; drawing an empty line back in does not. Losing power
	# mid-haul stops the winch where it is rather than dropping the part, so the
	# line stays on it and the pull resumes as soon as the reactor catches up.
	if _rope.is_hooked() and not _shooter.spend_energy(energy_cost_per_second * delta, source_placement_id):
		_rope.stop_reel()
		return

	if not _rope.is_reeling():
		_start_reel()


func _start_reel() -> void:
	var target: float = _rope.secured_line_length()
	var distance: float = _rope.line_length() - target
	if distance <= 1.0:
		return
	_rope.reel_to(target, maxf(distance / maxf(reel_speed, 1.0), 0.15))


## Freezes the part's drift and lifetime the instant the hook lands, so the rope
## has sole control of where it goes from here (see
## CapturedTechPart.begin_reel_in) and a long haul cannot expire halfway home.
func _on_hooked(body: Node2D) -> void:
	if body.has_method("begin_reel_in"):
		body.call("begin_reel_in")


## The part reached the maw — and stays there, on the end of the line. It is
## **not** absorbed: the hold is a set of hex bays now (see ShipHold), and which
## bay a part goes in is a decision the player makes on the builder screen. Until
## they do, they are towing it, which is a thing you can keep flying with, drop
## with another press, or lose to whatever shoots it.
##
## What this replaces: the part handing over its ModuleInstance here and deleting
## itself, so a haul ended with a number changing somewhere off screen.
func _on_secured(body: Node2D) -> void:
	if _shooter != null:
		_shooter.take_in_tow(body)
	_winching = false


func _on_snapped_taut(_at_global: Vector2) -> void:
	if jolt_shake <= 0.0 or _shooter == null:
		return
	var camera: Node = _shooter.get_node_or_null("ShipCamera")
	if camera != null and camera.has_method("add_shake"):
		camera.add_shake(jolt_shake)


func _on_stowed() -> void:
	if _rope != null and is_instance_valid(_rope):
		_rope.queue_free()
	_rope = null
	_winching = false

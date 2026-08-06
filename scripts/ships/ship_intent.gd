class_name ShipIntent
extends RefCounted

## One frame's worth of commands for a ship: what its controller *wants* it to
## do, as plain data, separate from who decided it and how it arrived.
##
## Every controller — the local player's keyboard (ship_input.gd), an AI
## personality (ship_ai.gd), and eventually a remote peer — fills one of these
## and hands it to Ship.submit_intent(). The ship applies the merged result in
## its own _physics_process. Nothing calls Ship's individual input setters from
## outside any more.
##
## This exists to serve both planned multiplayer shapes without either one
## needing the other's plumbing:
##
##   * one ship per player — each ship gets exactly one intent per frame,
##     authored locally or arriving from that ship's owning peer.
##   * several players crewing one ship — each crew member submits an intent
##     covering only the Role bits their station holds, and the ship merges
##     them. A gunner's WEAPONS fields land; their HELM fields are discarded by
##     the merge, so a station cannot command something it doesn't crew.
##
## Because the ship merges by role rather than trusting the sender, the same
## code is the authority check a server needs later: submit_intent() is the one
## place a peer's claimed roles are enforced.

## Which station owns each group of fields below. Powers of two so a controller
## can hold several at once — a solo player holds ALL_ROLES.
enum Role {
	HELM = 1,
	WEAPONS = 2,
	OPERATIONS = 4,
}

const ALL_ROLES: int = Role.HELM | Role.WEAPONS | Role.OPERATIONS

# --- HELM ---
var thrust: float = 0.0
var turn: float = 0.0
var boost: bool = false

# --- WEAPONS ---
var aim_target: Vector2 = Vector2.ZERO
## False means "this controller isn't aiming", which is different from aiming at
## the origin — the ship then falls back to its own facing (see Ship.get_aim_target).
var has_aim_target: bool = false
var fire_primary: bool = false
var fire_secondary: bool = false
## Lock is edge-driven: set_lock says "I am changing the lock this frame",
## locked_target carries the new value (null clears it). Without the separate
## flag there'd be no way to express "leave the current lock alone".
var set_lock: bool = false
var locked_target: Node2D = null

# --- OPERATIONS ---
var fire_winch: bool = false
var winch_reel: bool = false
var toggle_scan: bool = false
var toggle_grinder: bool = false


## Copies only the fields the given roles are entitled to. Roles the caller
## doesn't hold are left at whatever this intent already carried — which is how
## several partial crew intents combine into one complete command set.
func merge_from(other: ShipIntent, roles: int) -> void:
	if roles & Role.HELM:
		thrust = other.thrust
		turn = other.turn
		boost = other.boost

	if roles & Role.WEAPONS:
		aim_target = other.aim_target
		has_aim_target = other.has_aim_target
		fire_primary = other.fire_primary
		fire_secondary = other.fire_secondary
		set_lock = other.set_lock
		locked_target = other.locked_target

	if roles & Role.OPERATIONS:
		fire_winch = other.fire_winch
		winch_reel = other.winch_reel
		toggle_scan = other.toggle_scan
		toggle_grinder = other.toggle_grinder


## Returns the given roles' fields to "commanding nothing", leaving the rest
## alone. The ship calls this every frame for whichever roles nobody submitted
## for, so a station going quiet — a crew member disconnecting, a ship losing
## its controller entirely — releases the controls instead of leaving the ship
## latched at whatever it was last told. Without it, a helmsman dropping out
## mid-burn would pin the throttle open indefinitely.
func clear_roles(roles: int) -> void:
	if roles & Role.HELM:
		thrust = 0.0
		turn = 0.0
		boost = false

	if roles & Role.WEAPONS:
		has_aim_target = false
		fire_primary = false
		fire_secondary = false
		set_lock = false
		locked_target = null

	if roles & Role.OPERATIONS:
		fire_winch = false
		winch_reel = false
		toggle_scan = false
		toggle_grinder = false


func clear() -> void:
	clear_roles(ALL_ROLES)


## The edge-triggered commands only, cleared by the ship after it consumes them
## so a single key press doesn't repeat every frame until the next submission.
## Held states (thrust, turn, boost, winch_reel) deliberately survive.
func clear_one_shots() -> void:
	fire_primary = false
	fire_secondary = false
	fire_winch = false
	toggle_scan = false
	toggle_grinder = false
	set_lock = false
	locked_target = null

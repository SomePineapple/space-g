extends Node

## Who the local player is: which Ship this machine's HUD, panels and input
## belong to, and which crew roles it may command on that ship.
##
## Replaces the `get_tree().get_nodes_in_group("player_ship")[0]` lookup that
## ten UI and world scripts each carried a copy of. That lookup silently assumed
## exactly one player ship exists, which is wrong for both planned multiplayer
## shapes:
##
##   * one ship per player — several ships carry the "player_ship" group and
##     [0] is an arbitrary one, not necessarily this peer's.
##   * several players crewing one ship — every peer resolves to the same ship,
##     which is correct, but each needs its own role set on it.
##
## The "player_ship" group stays, and stays the right tool for questions about
## *any* player ship (AI target selection, salvage pickup, nebula entry). This
## autoload answers the different question of *which one is mine*.
##
## Parameters and fields are untyped Node (not Ship) deliberately: as an
## autoload this script compiles before the project's other global classes are
## guaranteed registered, and a static Ship type hint here corrupts type
## resolution for those classes project-wide. GameState has the same constraint
## for the same reason.

## Fires when the local player's ship changes — a warp to a new region, or
## later, being assigned to a different ship or respawning. UI that must survive
## that should rebind here rather than caching the ship from _ready() alone.
signal ship_changed(ship: Node)

## Which ShipIntent.Role bits the local player commands on that ship. Solo play
## holds all of them; a crew station later holds a subset, assigned wherever the
## lobby decides. Written as a literal rather than ShipIntent.ALL_ROLES for the
## autoload compile-order reason above — keep the two in step.
var local_roles: int = 7

var _ship: Node = null


## Called by Ship itself as it enters the tree, before any _ready() runs
## anywhere, so a UI script reading get_ship() in its own _ready() always finds
## it — the same ordering guarantee the old group lookup relied on.
func set_ship(ship: Node) -> void:
	if ship == _ship:
		return
	_ship = ship
	ship_changed.emit(ship)


func clear_ship(ship: Node) -> void:
	if _ship == ship:
		_ship = null
		ship_changed.emit(null)


## Null before the local ship enters the tree, and after it is destroyed —
## callers that run outside that window must handle it.
func get_ship() -> Node:
	if _ship != null and not is_instance_valid(_ship):
		_ship = null
	return _ship


func has_ship() -> bool:
	return get_ship() != null

class_name ModuleInstance
extends Resource

## One specific physical module — *this* railgun, not "a railgun". Lives either
## in Inventory's owned-but-unplaced pool (see Inventory._owned_module_pool) or
## attached directly to the ModulePlacement it's mounted on (see
## ModulePlacement.instance), so building, placing, removing, being cut off a
## wreck and being re-placed all keep identifying the same object rather than an
## interchangeable one of its type.
##
## Deliberately pure data: every field is an exported primitive, no node
## references, no Object fields, no back-pointer to the ship holding it. That is
## what lets an instance be duplicated across a scene change, written to a save,
## or replicated to a peer (docs/direction.md §2). Anything that needs a live
## object should look it up from the id, not store it here.
##
## Per-instance upgrade state used to live here too. Upgrades are now ship-wide
## and stored by id in GameState (see ShipUpgradeService); what remains is
## identity, provenance and condition.

@export var instance_id: String = ""
@export var module_type_id: String = ""
## Empty means "generic/no manufacturer" — matches ModulePlacement.manufacturer_id.
@export var manufacturer_id: String = ""

## Wear, as a fraction of full condition. Stored as a fraction rather than
## absolute condition points so it stays meaningful when the part moves to a
## hull with a different health_multiplier — a part carries how beaten up it is,
## not how many hit points some particular ship gave it. HullDamageModel is the
## only thing that writes this while a module is mounted; it converts to and
## from absolute points at the boundary.
##
## This is the authoritative record of a module's damage. It used to be a
## dictionary on HullDamageModel that was wiped on every rebuild(), which meant
## opening the ship builder erased the ship's memory of every fight.
@export var condition_fraction: float = 1.0

## Which faction's hull this part was cut off (see ShipPersonality.faction_id).
## Empty for a part that was fabricated rather than salvaged.
@export var origin_faction_id: String = ""
## Human-readable provenance, e.g. "Cut from Pirate Raider in AsteroidField".
## Stamped once, the first time the part is severed and recovered — a part that
## changes hands later keeps naming where it originally came from. Empty means
## fabricated, never salvaged.
@export var origin_description: String = ""
## How many ships this specific part has helped destroy. Nothing increments this
## yet: kills are not attributed to a firing module anywhere in the project (a
## Projectile knows its shooter Ship, not the hardpoint that launched it), and
## building that attribution is its own change.
@export var kill_count: int = 0


## Records the hull this part was cut off, if it doesn't already know. First
## origin wins: a railgun taken off a corvette and later severed from the
## player's own ship should still say it came from the corvette.
func stamp_origin(faction_id: String, description: String) -> void:
	if not origin_description.is_empty():
		return
	origin_faction_id = faction_id
	origin_description = description


## True if this part was recovered from a wreck rather than fabricated.
func is_salvaged() -> bool:
	return not origin_description.is_empty()


func record_kill() -> void:
	kill_count += 1

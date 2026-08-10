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

## Call-signs a part can be issued. Deliberately short, plain and a bit
## industrial — a part is a named object you can argue about ("put the Vane on
## the left"), not a magic item with a title.
## Call-signs a part can be issued, handed out in order rather than drawn at
## random — see create(). Two parts sharing a name is the one thing a name is
## supposed to prevent, and independent draws from a pool this size collide
## almost immediately (five starter parts already collide about a third of the
## time).
##
## Typed Array rather than PackedStringArray: a PackedStringArray() call is not
## a constant expression, so it cannot initialise a const (see docs/gotchas.md).
const NICKNAMES: Array[String] = [
	"Tern", "Vane", "Ash", "Grit", "Cinder", "Harrow", "Mote", "Kestrel",
	"Slate", "Brace", "Ember", "Drift", "Halyard", "Quill", "Ridge", "Salt",
	"Tally", "Vesper", "Wick", "Yoke", "Anvil", "Bramble", "Cobalt", "Dray",
	"Flint", "Gable", "Hoist", "Iron", "Jetty", "Kiln", "Lathe", "Marrow",
	"Nettle", "Oakum", "Pitch", "Rasp", "Sable", "Tinder", "Umber", "Wren",
]

@export var instance_id: String = ""
@export var module_type_id: String = ""
## Empty means "generic/no manufacturer" — matches ModulePlacement.manufacturer_id.
@export var manufacturer_id: String = ""

## What this part is called and how it's stamped — the two things that make one
## railgun tellable from another at a glance. The nickname is what a crew would
## actually say; the serial is what disambiguates two parts that drew the same
## call-sign. Both are cosmetic labels: instance_id is still the identity every
## system keys on.
@export var nickname: String = ""
@export var serial: String = ""

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


## The one place a part comes into existence. Every field that identifies it is
## drawn from GameRng, so two machines building the same part in the same order
## produce the same object — wall-clock values or instance ids would not
## (docs/multiplayer.md).
static func create(module_type_id_value: String, manufacturer_id_value: String = "") -> ModuleInstance:
	var instance := ModuleInstance.new()
	instance.instance_id = GameRng.next_id("mi")
	instance.module_type_id = module_type_id_value
	instance.manufacturer_id = manufacturer_id_value

	# The call-sign comes off the same monotonic counter that made the id unique,
	# so no two parts share a name until the pool wraps. Deriving it from a
	# registry of taken names would be the other way to guarantee that, and
	# docs/direction.md §2 rules that out — a global part registry is exactly the
	# shape not to build. The serial stays a roll, as the tiebreaker after a wrap.
	instance.nickname = NICKNAMES[GameRng.last_id_ordinal() % NICKNAMES.size()]
	instance.serial = "%s-%04d" % [
		_serial_prefix(module_type_id_value), GameRng.stream("parts").randi() % 10000]
	return instance


## Two letters off the module type id — "hull_spar" becomes HS, "gun_mk1" GM.
## Purely a label, so a collision between two types is cosmetic, not a bug.
static func _serial_prefix(type_id: String) -> String:
	var words: PackedStringArray = type_id.split("_", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return type_id.substr(0, 2).to_upper()


## What the builder calls this part: the type it is, plus which one it is.
func display_name() -> String:
	var type_name: String = ModuleCatalog.get_by_id(module_type_id).display_name \
		if ModuleCatalog.get_by_id(module_type_id) != null else module_type_id
	return "%s \"%s\"" % [type_name, nickname] if not nickname.is_empty() else type_name


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

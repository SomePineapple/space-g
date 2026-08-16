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

## The ceiling `condition_fraction` can be repaired back to — how much of its
## original life the part has permanently left. Every hit takes a little of this
## with it, and nothing gives it back: a part that has been through five fights
## is worn out even when fully patched up, and eventually has to be replaced with
## one cut off somebody else.
##
## This is what stops passive repair making damage free. Condition is the wound;
## integrity is the scar.
@export var integrity: float = 1.0

## The worst this part's condition has ever been. Only ever falls, and nothing —
## repair, regrowth, being unbolted and refitted — puts it back.
##
## This is what the hull's visible damage is drawn from (HullPaint.scar_tier), so
## a breach stays a breach. Keyed off condition rather than integrity because the
## question a scar answers is "how badly was this hit", not "how much life has it
## lost": integrity moves a fraction as fast and bottoms out at MINIMUM_INTEGRITY,
## so a part shot to the brink and patched up would otherwise look barely marked.
@export var worst_condition_fraction: float = 1.0

## How far integrity is allowed to fall. Deliberately above
## HullPaint.CUTTABLE_CONDITION (0.30): a part worn past that point would sit
## permanently under the cut-ready threshold and wear the white slicer marker
## forever on its owner's own hull, which reads as a bug rather than as age.
const MINIMUM_INTEGRITY: float = 0.35

## Above this much condition a part performs exactly as designed (see
## efficiency()). The deadband is deliberate: chip damage is constant in any
## fight, and without it every graze would shave a little off the ship's output,
## leaving the player managing a slow leak rather than reacting to real damage.
const FULL_PERFORMANCE_CONDITION: float = 0.8

## What a part on the very brink still manages. Not zero, for two reasons: a part
## that does nothing is indistinguishable from a destroyed one, and the case this
## whole mechanic exists for — shooting a gun off a wreck and bolting it on —
## would otherwise hand the player something useless as its reward. Note that
## HullPaint.CUTTABLE_CONDITION is 0.3, so *every* freshly cut part lands in the
## degraded band by construction: you cannot cut a part free without first
## hurting it, which is the trade.
const MINIMUM_EFFICIENCY: float = 0.4

## True when this part was bolted on away from a dock. A field refit is always
## possible — that is the point, a part cut off a wreck should be usable there
## and then — but it is always worse: no jig, no alignment, no proper power
## coupling, so the mount itself costs FIELD_MOUNT_EFFICIENCY on top of whatever
## the part's wear already costs (see efficiency()).
##
## A property of the current *mount*, not of the part: it is written on every
## attach (ShipBuilderPanel) and cleared the moment the part comes off the hull
## and re-enters the hold (Inventory.return_owned_module), so re-seating a
## jury-rigged part at a station is what lifts it — as far as it goes, which is
## not all the way back (see ever_field_attached).
@export var field_attached: bool = false

## Whether this part has *ever* been bolted on outside a dock. Only ever set,
## never cleared: cutting a mount by hand deforms the mounting points, and no
## amount of later work in a proper cradle makes them true again.
##
## This is what stops a field refit being a free option that a trip home undoes.
## Bolting a part on out here is a real decision with a real price — the part is
## permanently a REFITTED_MOUNT_EFFICIENCY part — weighed against carrying it
## home instead, which costs hold space the whole way and leaves the slot on the
## hull empty for the fight in between.
@export var ever_field_attached: bool = false

## What a field mount alone leaves the part delivering, and what the best
## possible re-seat afterwards can get it back to. Deliberately hard round
## numbers rather than curves: this is a decision the player makes at the moment
## of attaching ("bolt it on now, or carry it home"), so both halves of it have
## to be quotable before they commit.
const FIELD_MOUNT_EFFICIENCY: float = 0.5
const REFITTED_MOUNT_EFFICIENCY: float = 0.7

## Which faction's hull this part was cut off (see ShipPersonality.faction_id).
## Empty for a part that was fabricated rather than salvaged.
@export var origin_faction_id: String = ""
## Human-readable provenance, e.g. "Cut from Pirate Raider in AsteroidField".
## Stamped once, the first time the part is severed and recovered — a part that
## changes hands later keeps naming where it originally came from. Empty means
## fabricated, never salvaged.
@export var origin_description: String = ""
## How many ships this specific part has killed. Credited to the gun that fired
## the fatal shot — see Ship.record_hardpoint_kill.
@export var kill_count: int = 0

## Whether this part is currently drawing power. Read by HullPaint.is_cuttable(),
## which lets an unpowered part be cut at any condition.
##
## **Nothing writes this yet, deliberately.** Reactor circuits (see
## docs/rejected/power-conduits.md for what this seam used to serve) could drive
## it directly — a module whose circuit is dark would become harvestable — and
## that is a genuinely good tactic: knock out their reactor and their guns become
## salvage rather than targets. It is held back because it is a *salvage-economy*
## change wearing a power change's clothes, and it wants playtesting on its own
## terms rather than arriving as a side effect of the energy rework.
@export var powered: bool = true

## Nothing the player does can hurt this part: no weapon fire, no splash, and no
## Slicer cut. Set on scenery that exists to be *taken* rather than fought over —
## the opening's derelict arm, which would otherwise be destroyable by a stray
## shot before the player ever learned what it was for.
##
## Lives on the instance rather than on ModuleType because it is a property of
## this particular object in this particular scene, not of Hull Spars in general.
## Cleared the moment the part is cut free (see WreckageSpawner) — it protects
## scenery waiting to be taken, and a salvaged part is neither.
@export var damage_immune: bool = false


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


## How well a part still does its job, 0..1. The one place the curve lives —
## weapons, thrusters, reactors and batteries all read this and then apply it to
## whatever "output" means for them.
##
## Two independent things are multiplied together here, and deliberately so: how
## beaten up the part is, and how well it is bolted on. A pristine part in a
## jury-rigged mount and a worn part in a proper one are different problems with
## different fixes (a dock visit; a new part), and stacking them means neither
## hides the other.
##
## Deliberately derived rather than stored: condition is already the
## authoritative record of a part's damage, and a second field would be one more
## thing to keep in step with it across salvage, refit and repair.
func efficiency() -> float:
	return wear_efficiency() * mount_efficiency()


## The wear half of efficiency() — what this part's condition alone costs it.
func wear_efficiency() -> float:
	if condition_fraction >= FULL_PERFORMANCE_CONDITION:
		return 1.0
	return lerpf(MINIMUM_EFFICIENCY, 1.0,
		clampf(condition_fraction / FULL_PERFORMANCE_CONDITION, 0.0, 1.0))


## The mount half of efficiency() — what the way it is bolted on costs it, and
## what having once been bolted on badly still costs it.
func mount_efficiency() -> float:
	if field_attached:
		return FIELD_MOUNT_EFFICIENCY
	if ever_field_attached:
		return REFITTED_MOUNT_EFFICIENCY
	return 1.0


## The best this part's mount can ever be again — 100% for one that has only been
## fitted properly, REFITTED_MOUNT_EFFICIENCY for one that has been jury-rigged
## at any point in its life. Quoted to the player *before* a field refit, since
## that is the moment the ceiling drops.
func mount_efficiency_ceiling() -> float:
	return REFITTED_MOUNT_EFFICIENCY if ever_field_attached else 1.0


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

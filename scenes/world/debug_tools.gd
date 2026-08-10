class_name DebugTools
extends Node

## Testing aid, not a real gameplay feature: grants materials so builder
## costs/upgrades can be tried out without grinding salvage first.
@export var debug_material_amount: int = 1000

const TEST_DUMMY_SCENE: PackedScene = preload("res://scenes/enemies/test_dummy.tscn")
const DUMMY_SPAWN_DISTANCE: float = 400.0

## Parts handed out by debug_add_salvaged_parts, as
## [module_type_id, origin_faction_id, condition_fraction, origin_description].
##
## Chosen to put every visual state next to each other in one hull: foreign
## plating from two different factions, same-faction salvage (which tints like
## your own work but still joints badly once it's chewed up), and a spread of
## condition either side of ShipLayoutRenderer.HEALTHY_CONDITION. Fixed values
## rather than rolls, so what you're looking at is the same every run and worth
## judging.
##
## Normally these only exist by severing a module off a live enemy and reeling
## the piece in before it drifts (see WreckageSpawner.spawn_severed_piece),
## which is far too slow a way to look at how a mongrel hull renders.
const SALVAGED_PARTS: Array[Array] = [
	["hull_spar", "pirate", 1.0, "Cut from Raider in AsteroidField"],
	["hull_spar", "pirate", 0.55, "Cut from Bruiser in AsteroidField"],
	["hull_wedge", "ancient", 0.8, "Cut from Sentinel in FrontierSystem"],
	["hull_wedge", "pirate", 0.35, "Cut from Bruiser in AsteroidField"],
	["gun_mk1", "corporate", 0.45, "Cut from Enforcer in MapTester"],
	["gun_mk1", "ancient", 0.95, "Cut from Sentinel in FrontierSystem"],
	["reactor_pair", "pirate", 0.7, "Cut from Raider in AsteroidField"],
	["thruster_block", "pirate", 0.9, "Cut from Raider in AsteroidField"],
]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_add_resources"):
		_add_resources_to_player()
	elif event.is_action_pressed("debug_add_salvaged_parts"):
		_add_salvaged_parts_to_player()
	elif event.is_action_pressed("debug_spawn_test_dummy"):
		_spawn_test_dummy()


func _add_resources_to_player() -> void:
	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return

	var inventory: Inventory = ship.get_inventory()
	for material_id in MaterialCatalog.ALL_IDS:
		inventory.add_material(material_id, debug_material_amount)


## Drops a spread of foreign, worn parts straight into the hold so a mongrel
## hull can be assembled and looked at immediately. Goes through the same
## add_captured_instance() path a real capture uses, so what appears in the
## builder is exactly what a recovered part looks like.
func _add_salvaged_parts_to_player() -> void:
	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return

	var inventory: Inventory = ship.get_inventory()
	for entry in SALVAGED_PARTS:
		var instance: ModuleInstance = ModuleInstance.create(entry[0])
		instance.condition_fraction = entry[2]
		instance.stamp_origin(entry[1], entry[3])
		inventory.add_captured_instance(instance)
	print("[debug] granted %d salvaged parts" % SALVAGED_PARTS.size())


## Drops an inert pirate in front of the player so the Slicer can be tried
## without also being shot at. It is a real enemy ship — same scene, same
## HullDamageModel, same wreckage path — with a personality that never detects,
## never fires and never turns (see personality_test_dummy.tres), so what you
## learn about cutting it is true of a live one.
##
## Its layout is built to be taken apart: a gun on the end of a long spar, a
## thruster on a shorter one, and a reactor tucked against the core that cannot
## be severed at all because it has no connector to cut.
func _spawn_test_dummy() -> void:
	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return

	var dummy: Ship = TEST_DUMMY_SCENE.instantiate()
	# Far enough ahead to have to fly at it, well inside the Slicer's 10-hex
	# reach once you arrive.
	WorldSpawn.attach_at(dummy, ship.global_position + ship.transform.x * DUMMY_SPAWN_DISTANCE)
	print("[debug] spawned an inert pirate %.0f units ahead" % DUMMY_SPAWN_DISTANCE)

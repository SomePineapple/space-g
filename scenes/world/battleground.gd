class_name Battleground
extends Node2D

## A dead engagement: the Colossus adrift at the centre of a field of corporate
## and pirate hulls that stopped fighting a long time ago.
##
## Every wreck is a real Ship built from a real ShipLayout (resources/ships/),
## with an inert personality and no AI — so the graveyard is made of the same
## objects the player flies and fights, not of scenery that only looks like them.
## That is what lets one of them be cut apart with no special case.
##
## Wrecks are scattered on a ring around the Colossus, scaled to fake distance
## and rotated freely, with a share of their modules blown out so the field reads
## as a battle rather than as a parking lot.
##
## Placement uses a named GameRng stream: where the world's content sits is a
## simulation outcome, not decoration (docs/direction.md §2).

signal salvage_target_ready(ship: Ship)

const CORPORATE_DESIGNS: Array[String] = [
	"res://resources/ships/corporate/lancer.tres",
	"res://resources/ships/corporate/bastion.tres",
	"res://resources/ships/corporate/custodian.tres",
	"res://resources/ships/corporate/vanguard.tres",
]
const PIRATE_DESIGNS: Array[String] = [
	"res://resources/ships/pirates/fang.tres",
	"res://resources/ships/pirates/wrecker.tres",
	"res://resources/ships/pirates/serpent.tres",
	"res://resources/ships/pirates/warlord.tres",
]

## The wreck the player is meant to cut. Deliberately a corporate hull: the
## opening's own faction, so the first part the player ever takes is one they can
## read at a glance.
##
## Deliberately a *small* one. This is the first salvage the player ever sees, so
## the hull has to be readable at a glance as "a gun, on an arm, on a hulk" —
## a full cruiser buried the one cuttable hex among a dozen identical-looking
## plates and the lesson did not land.
@export var salvage_design: String = "res://resources/ships/corporate/derelict_gunboat.tres"

@export var ship_scene: PackedScene = preload("res://scenes/player/ship.tscn")
@export var corporate_personality: ShipPersonality = preload("res://resources/ai/personality_derelict.tres")
@export var pirate_personality: ShipPersonality = preload("res://resources/ai/personality_test_dummy.tres")

@export var wreck_count: int = 22
## Ring the field occupies, as a fraction of the Colossus's own radius. Kept
## inside 1.0 so the wrecks lie *over* the Colossus rather than in a halo around
## it: they read as the battle that happened on top of the hulk, and silhouetted
## against its plating they are far more legible than they were against a
## starfield.
@export var field_radius: Vector2 = Vector2(0.12, 0.9)
## Wrecks are drawn at a spread of sizes to sell depth in a game with no depth.
@export var wreck_scale: Vector2 = Vector2(0.55, 2.4)
## Share of each wreck's modules blown away.
@export var wreck_damage: Vector2 = Vector2(0.15, 0.55)

## Dead hulls, tinted down so the field recedes behind the Colossus and the one
## wreck that matters can be lit differently.
@export var wreck_tint: Color = Color(0.38, 0.42, 0.5)
## The salvage target wears the region's own colour rather than the graveyard's,
## so the thing the player is meant to approach is the one thing that looks alive.
@export var salvage_tint: Color = Color(0.78, 0.84, 0.95)

## Condition left on the one cuttable connector — under
## HullPaint.CUTTABLE_CONDITION, so it wears the white cut-ready marker.
##
## It stays there because derelicts do not regenerate (see Ship.regenerates_hull);
## with regrowth on, this healed past the cuttable threshold within seconds of
## spawning and the marker disappeared before the player ever arrived.
@export var connector_condition: float = 0.18

## Where the dead hulls sit relative to everything that matters. The graveyard is
## scenery: the player's ship, its projectiles and the one wreck they are here to
## cut all have to read in front of it, so the field is pushed behind the play
## plane outright rather than left to tree order.
@export var wreck_z_index: int = -60
## The salvage target is real, so it sits in the play plane — just behind the
## player, so flying over it reads as flying over it.
@export var salvage_z_index: int = -1

## Where the target hull sits, as a multiple of the Colossus's radius — on the
## far side from the player, so reaching it means crossing the whole length of
## the hulk. The approach is the point: the first salvage in the game is at the
## end of a flight down something enormous, and a target on the near side would
## be reached before the Colossus had a chance to register as big.
@export var salvage_standoff: float = 1.05

var _radius: float = 3000.0
var _approach_bearing: float = 0.0
var _salvage_ship: Ship
## The weapon this whole field exists to hand over, so anything watching for the
## lesson to be finished can ask about that one part rather than guess.
var _prize_placement_id: String = ""
## Identity of the part itself, which outlives the placement it was cut from —
## it travels hull -> drifting piece -> hold -> the player's own hull, and
## instance_id is the same string the whole way (docs/direction.md §1).
var _prize_instance_id: String = ""


## `radius` is the Colossus's own visual radius, so the field scales with it.
## `approach_bearing` points from the Colossus back toward the player, so the one
## hull that matters can be put at the opposite end from them.
func build(radius: float, approach_bearing: float = 0.0) -> void:
	_radius = radius
	_approach_bearing = approach_bearing
	var rng: RandomNumberGenerator = GameRng.stream("battleground")

	_salvage_ship = _spawn_wreck(salvage_design, corporate_personality, rng, true)
	_prepare_salvage_target(_salvage_ship)
	salvage_target_ready.emit(_salvage_ship)

	for i in wreck_count:
		var corporate: bool = rng.randf() < 0.5
		var designs: Array[String] = CORPORATE_DESIGNS if corporate else PIRATE_DESIGNS
		var personality: ShipPersonality = corporate_personality if corporate else pirate_personality
		_spawn_wreck(designs[rng.randi() % designs.size()], personality, rng, false)


func _spawn_wreck(design_path: String, personality: ShipPersonality,
		rng: RandomNumberGenerator, is_target: bool) -> Ship:
	var layout: ShipLayout = load(design_path)
	var ship: Ship = ship_scene.instantiate()
	# duplicate(true) because a .tres is shared across every instance that loads
	# it — without this, damaging one wreck damages every wreck of that design.
	ship.ship_layout = layout.duplicate(true)
	ship.personality = personality
	ship.drops_salvage = false
	# Nothing in this field repairs itself. For the target that is load-bearing:
	# its cuttable connector has to still be cuttable when the player arrives.
	ship.regenerates_hull = false
	ship.modulate = salvage_tint if is_target else wreck_tint

	if not is_target:
		# Background hulls are scenery, not obstacles: the player flies through
		# them and shots pass through them. Clearing both layer and mask takes
		# them out of the physics world entirely rather than half-way.
		ship.collision_layer = 0
		ship.collision_mask = 0

	var holder := Node2D.new()
	add_child(holder)
	holder.add_child(ship)
	# Absolute, not inherited: this node hangs off the Colossus, which is itself
	# pushed far back, and the field must not be pushed back again with it.
	holder.z_as_relative = false
	holder.z_index = salvage_z_index if is_target else wreck_z_index

	var bearing: float = rng.randf() * TAU
	var distance: float = _radius * rng.randf_range(field_radius.x, field_radius.y)
	# The target sits at the far end of the Colossus, opposite the player's
	# approach — clear of the field so it is not lost among two dozen others, and
	# far enough that getting to it is a flight the length of the wreck.
	if is_target:
		bearing = _approach_bearing + PI
		distance = _radius * salvage_standoff
	holder.position = Vector2.RIGHT.rotated(bearing) * distance
	holder.rotation = rng.randf() * TAU
	holder.scale = Vector2.ONE * (1.0 if is_target else rng.randf_range(wreck_scale.x, wreck_scale.y))

	if not is_target:
		_wreck(ship, rng)
	return ship


## Blows out a share of a hull's modules so it reads as a casualty. The core is
## spared — destroying it takes the whole ship with it (see Ship._on_hull_lost).
func _wreck(ship: Ship, rng: RandomNumberGenerator) -> void:
	var layout: ShipLayout = ship.ship_layout
	var fraction: float = rng.randf_range(wreck_damage.x, wreck_damage.y)
	for placement in layout.placements:
		if placement.placement_id == layout.core_placement_id:
			continue
		if rng.randf() < fraction:
			ship.damage_own_module(placement.placement_id, 99999.0)


## Turns one hull into the salvage lesson: the weapon furthest out is the prize,
## the module holding it on is the only thing that can be cut, and everything
## else is immune.
##
## Derived from the layout rather than hard-coded to one design, so changing
## `salvage_design` does not silently break the tutorial.
func _prepare_salvage_target(ship: Ship) -> void:
	var layout: ShipLayout = ship.ship_layout
	var prize: ModulePlacement = _furthest_weapon(layout)
	if prize == null:
		return
	_prize_placement_id = prize.placement_id
	# Recorded now, while the part is still mounted: detaching hands the instance
	# over to the wreckage and clears the placement's reference to it, so after the
	# cut there is nothing left here to ask for its id.
	prize.ensure_instance()
	_prize_instance_id = prize.instance.instance_id
	var connector: ModulePlacement = _neighbour_toward_core(layout, prize)

	for placement in layout.placements:
		placement.ensure_instance()
		if connector != null and placement.placement_id == connector.placement_id:
			placement.instance.condition_fraction = connector_condition
			placement.instance.damage_immune = false
		else:
			# Nothing else on this hull can be hurt or cut — the player cannot
			# destroy the first weapon they are ever shown how to take.
			placement.instance.damage_immune = true


func _furthest_weapon(layout: ShipLayout) -> ModulePlacement:
	var best: ModulePlacement = null
	var best_distance: int = -1
	for placement in layout.get_weapon_hardpoint_placements():
		var distance: int = layout.distance_from_core(placement)
		if distance > best_distance:
			best_distance = distance
			best = placement
	return best


## The placement adjacent to `placement` that is one step nearer the core — the
## thing actually holding it on.
func _neighbour_toward_core(layout: ShipLayout, placement: ModulePlacement) -> ModulePlacement:
	var target_distance: int = layout.distance_from_core(placement)
	for cell in layout.get_occupied_cells(placement):
		for direction in HexUtils.EDGE_DIRECTIONS:
			var neighbour: ModulePlacement = layout.get_placement_at(cell + direction)
			if neighbour == null or neighbour.placement_id == placement.placement_id:
				continue
			if neighbour.placement_id == layout.core_placement_id:
				continue
			if layout.distance_from_core(neighbour) < target_distance:
				return neighbour
	return null


func get_salvage_ship() -> Ship:
	return _salvage_ship


## True once the weapon has actually come off the hull — HullDamageModel clears a
## placement's instance the moment the part detaches, so an empty mount is the
## authoritative "this has been salvaged", not a guess from condition or from
## anything the wreck still looks like.
## The part the lesson is about, by identity rather than by location.
func get_prize_instance_id() -> String:
	return _prize_instance_id


func is_salvage_taken() -> bool:
	if _salvage_ship == null or not is_instance_valid(_salvage_ship):
		return true
	if _prize_placement_id.is_empty():
		return false
	var placement: ModulePlacement = _salvage_ship.ship_layout.get_placement_by_id(_prize_placement_id)
	return placement == null or placement.instance == null

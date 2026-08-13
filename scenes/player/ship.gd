class_name Ship
extends CharacterBody2D

## One flying ship — player or AI, since both drive the same body through the
## same input setters (see ship_input.gd / ship_ai.gd).
##
## This script owns the ship's body and identity: flight, its layout-derived
## aggregate stats, engine flames, damage/destruction feedback, and the small
## public API everything outside the ship talks to. The heavier subsystems live
## in child components it delegates to and relays for:
##
##   ShipEnergy        the energy pool, its regeneration and its signal
##   ShipSystems       which systems are switched on and what they idle at
##   HardpointBank     every mounted hardpoint, spawning them, firing and aiming
##   HullDamageModel   per-module condition, severance and regrowth
##   WreckageSpawner   the debris and sparks a severed module throws off
##
## External systems keep talking to Ship, never to those children — see the
## delegating methods below and the relayed signals.

signal layout_applied
signal energy_changed(current: float, max_energy: float)
## Relayed from ShipEnergy — how much the ship is drawing per second against
## how much it can sustain (see the HUD's load bar).
signal energy_usage_changed(usage: float, generation: float)
## Relayed from the internal Health component (see its own signals of the same
## name) so external systems — ShipAI, the HUD, the trade panel — can react to
## this ship being hurt without reaching into its node hierarchy for $Health,
## which is exactly the coupling the project's scene ownership rules forbid.
signal health_changed(current: float, max_health: float)
signal damaged(amount: float, current: float)
signal destroyed

@export var thrust_force: float = 600.0
@export var reverse_thrust_force: float = 120.0
@export var max_speed: float = 400.0
@export var reverse_max_speed: float = 140.0
@export var boost_multiplier: float = 1.8
## Top turn rate at `handling_reference_mass`. Actual rate is scaled by
## _mass_handling_factor() — see there for why this is no longer a flat rate.
## Reaching it is not instant; see angular_acceleration.
@export var rotation_speed: float = 3.5
## How fast the ship builds up to `rotation_speed`, in rad/s^2. Rotation used to
## be applied straight from input, so a hull snapped to full turn rate and back
## to zero in a single frame however heavy it was — the one part of flight with
## no momentum at all. This is the angular counterpart of thrust_force.
@export var angular_acceleration: float = 14.0
## How fast an unattended spin bleeds off, as a fraction of the current top turn
## rate per second — the angular counterpart of `drag`, and read the same way.
##
## Deliberately much higher than linear `drag`. Linear coasting is the point of
## flying in space and takes ~1.7s to stop; rotation at that timing overshoots
## every time you line up a shot, because aim is a position you stop *at* rather
## than a direction you drift along.
@export var angular_drag: float = 2.6
## The hull mass `rotation_speed` is quoted at. Set to the starter ship's real
## total (measured, not guessed) so the default loadout turns at exactly the
## rate it always did and only ships that deviate from it feel the change.
@export var handling_reference_mass: float = 3.85
## How far mass is allowed to move the turn rate. Without a floor, a large hull
## becomes unplayable rather than merely ponderous; without a ceiling, a nearly
## stripped hull spins fast enough to make aiming trivial.
@export var handling_factor_min: float = 0.38
@export var handling_factor_max: float = 1.6
## How sharply the turn rate falls away once a hull is heavier than
## `handling_reference_mass`. 1.0 is the plain inverse; above it, each extra
## tonne costs more than the last, so a big hull is worse than proportionally
## slow to come round.
##
## Applied only above the reference mass. A light hull's bonus stays a plain
## inverse, because this exists to price up bulk, not to pay out for flying a
## stripped frame.
@export var handling_mass_falloff: float = 1.3
@export var drag: float = 0.6
@export var mass: float = 1.0
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var destruction_explosion_scale: float = 2.2
@export var drops_salvage: bool = true
## Off for a derelict, which stays exactly as damaged as it spawned. See
## HullDamageModel.regenerates for why this matters to salvage specifically.
@export var regenerates_hull: bool = true
## Takes no weapon damage at all — not to its modules, and not to its Health
## pool. Deliberately does NOT block the Slicer (take_slicer_cut), which is a
## dismantling tool rather than a weapon.
##
## Exists for the opening's salvage target: a hull the lesson depends on must not
## be destructible by anything the player or a raider can shoot at it. Per-module
## damage_immune was not enough on its own, because Health is a separate pool and
## a wreck shot to zero takes every part on it — including the one the player was
## sent there to cut off (see Battleground._prepare_salvage_target).
@export var invulnerable: bool = false
@export var salvage_scene: PackedScene = preload("res://scenes/world/salvage.tscn")
## Combat kills drop a handful of raw-material salvage pieces rather than
## just one (Phase 4.2) — each drop rolls its own rarity/material separately.
@export var salvage_drop_count_min: int = 2
@export var salvage_drop_count_max: int = 3
## Phase 5.3: chance each combat kill-drop is an already-crafted component
## instead of a raw material — lets destroyed ships/wrecks progress the
## player through crafted components without mining+CraftingPanel, distinct
## per source since these are per-instance exports (a plain pirate can be
## tuned lower than a rare capital wreck). 0 on Asteroid/HardpointGrinder's
## drops on purpose — mining stays raw-material-only, salvage is the
## alternative route to components, not a duplicate of it.
@export_range(0.0, 1.0) var component_drop_chance: float = 0.3
## Of the drops that do roll a component, the fraction pulled from
## ComponentCatalog.RARE_IDS instead of COMMON_IDS.
@export_range(0.0, 1.0) var rare_component_chance: float = 0.25
@export var hit_flash_color: Color = Color(1, 1, 1, 1)
@export var hit_flash_duration: float = 0.12
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and taking damage will play it automatically.
@export var hit_sound: AudioStream = null
@export var ship_layout: ShipLayout = preload("res://resources/ships/starter_ship_layout.tres")
## Defaults to USER (no AI behavior) since PlayerInput drives the player
## ship; enemy scenes override this to a Rammer/Sniper/etc. resource so
## ShipAI knows how to fly and fight.
@export var personality: ShipPersonality = preload("res://resources/ai/personality_user.tres")
@export var engine_thruster_scene: PackedScene = preload("res://scenes/player/engine_thruster.tscn")
@export var reverse_thrust_ratio: float = 0.2
@export var speed_per_acceleration: float = 1.0
## Hard ceiling on the derived `max_speed`, before boost. Without it, max_speed
## is thrust/mass unbounded, so a stripped hull carrying one thruster block
## reaches 500 (900 boosted) and outruns its own projectiles, which travel at
## HardpointGun.projectile_speed = 700. Set so even a boosted ship stays under
## that: a shot must always visibly leave the ship that fired it.
@export var max_speed_ceiling: float = 360.0
@export var reverse_speed_ratio: float = 0.35

## Cargo capacity available even with no Storage modules installed, matching the
## same "baseline + layout total" shape as ShipEnergy's base_capacity.
@export var base_cargo_capacity: float = 100.0
## Cells in the hull's own parts bay, before any Cargo Container adds its own
## (see ShipHold). Non-zero for the same reason base_cargo_capacity is: a hull
## with no storage module still has to be able to carry the first part it cuts
## free, which is the opening of the game.
##
## Deliberately the same 4 cells a basic Cargo Container gives, so fitting one is
## a doubling rather than a rounding error. The seven starter parts need 15 cells
## between them and therefore do NOT all fit at the start — they are a crate of
## parts waiting to be bolted on, not cargo, and the builder lists them whether
## or not they have a cell (see Inventory.get_unstowed_instances). By the time
## the ship is built the hold is empty and the first salvaged part has room.
@export var base_hold_cells: int = 4
## Energy/sec spent thrusting at full non-boosted throttle. Deliberately at
## or below ShipEnergy.base_generation so cruising is sustainable forever on
## base power alone — firing weapons or boosting is what actually draws the
## reserve down without a Reactor installed.
@export var thrust_energy_cost: float = 8.0
## Credits charged per point of overall Health restored by repair_fully.
@export var repair_cost_per_health: float = 1.0

## Commands accumulated since the last physics frame (see submit_intent), and
## which ShipIntent.Role bits were actually submitted for. Roles missing from
## that mask are released on consume rather than left holding their last order.
var _pending_intent: ShipIntent = ShipIntent.new()
var _submitted_roles: int = 0

var _thrust_input: float = 0.0
var _turn_input: float = 0.0
var _boost_active: bool = false
var _base_hull_modulate: Color
var _flash_tween: Tween
var _thrusters: Array[Node2D] = []
## The three GPUParticles2D children of each entry in _thrusters, resolved
## once at spawn — _update_engine_particles() runs every physics frame and was
## doing three get_node() string lookups per thruster per frame.
var _thruster_particles_boost: Array[GPUParticles2D] = []
var _thruster_particles_boost_soft: Array[GPUParticles2D] = []
var _thruster_particles_normal: Array[GPUParticles2D] = []
## Parallel to _thrusters — which placement each thruster's flame belongs to,
## so a destroyed/detached engine's particles can be silenced individually
## even while other engines (or leftover momentum) keep the ship moving.
var _thruster_placement_ids: Array[String] = []
## Current spin, in rad/s. Owned here rather than by the physics server: this is
## a CharacterBody2D, so `rotation` is ours to integrate (see _apply_turn).
var _angular_velocity: float = 0.0
## Attitude-jet emitters, one pair per thruster. Index-parallel to _thrusters,
## same as the main flame arrays above.
var _thruster_particles_turn_left: Array[GPUParticles2D] = []
var _thruster_particles_turn_right: Array[GPUParticles2D] = []
## The engine loop, one voice per faction of thruster mounted (see EngineAudio).
## Created in code rather than in ship.tscn because it has no authored state and
## every ship — player and AI alike — wants exactly one.
var _engine_audio: EngineAudio
var _aim_target: Vector2 = Vector2.ZERO
var _has_aim_target: bool = false
var _locked_target: Node2D = null
## Counter rather than a bool so overlapping nebula zones don't prematurely
## clear each other's effect when one is exited while still inside another.
var _nebula_depth: int = 0
## Recomputed once per layout apply rather than per call — get_layout_extent()
## walks every placement's every cell, and the AI reads it several times per
## physics frame (own hull, target's hull, avoidance probe range, and once per
## other enemy ship for separation). -1.0 means "not computed yet".
var _cached_layout_extent: float = -1.0

@onready var _health: Health = $Health
@onready var _hull_renderer: ShipLayoutRenderer = $HullRenderer
@onready var _inventory: Inventory = $Inventory
@onready var _hit_sound_player: AudioStreamPlayer2D = $HitSound
@onready var _scanner: Scanner = $Scanner
@onready var _energy: ShipEnergy = $Energy
@onready var _systems: ShipSystems = $Systems
@onready var _hardpoints: HardpointBank = $Hardpoints
@onready var _hull_damage: HullDamageModel = $HullDamage
@onready var _wreckage: WreckageSpawner = $Wreckage


## Claiming the local player's ship happens here rather than in _ready(): every
## node in a scene enters the tree before any of them is readied, so a UI script
## calling PlayerContext.get_ship() from its own _ready() is guaranteed to find
## it. That is the same ordering the group lookup this replaced relied on.
##
## The group is still what marks a ship as player-controlled at all; which of
## them is *this machine's* is the separate question PlayerContext answers, and
## in a crewed-ship session every peer will answer it with the same ship.
func _enter_tree() -> void:
	if is_in_group("player_ship"):
		PlayerContext.set_ship(self)


func _exit_tree() -> void:
	PlayerContext.clear_ship(self)


func _ready() -> void:
	_hull_damage.configure(self, _hardpoints, _wreckage)
	_hull_damage.regenerates = regenerates_hull
	# The damage model never touches this ship's Health pool directly — it
	# reports what happened and the ship decides what that costs.
	_hull_damage.modules_changed.connect(_recompute_thrust_stats)
	_hull_damage.modules_changed.connect(_recompute_energy_stats)
	_hull_damage.modules_changed.connect(_refresh_systems)
	_hull_damage.hull_healed.connect(_health.heal)
	_hull_damage.hull_lost.connect(_on_hull_lost)
	_energy.energy_changed.connect(_on_energy_changed)
	_energy.usage_changed.connect(_on_energy_usage_changed)
	_systems.configure(_energy)

	# A restoring player ship is about to have GameState.apply() push its saved
	# layout in, which rebuilds everything anyway — building the scene's own
	# default layout first (thrusters, collision shapes, every hardpoint node)
	# just to throw it away was a wasted full rebuild on every warp arrival.
	var will_restore: bool = is_in_group("player_ship") and GameState.has_snapshot()
	if not will_restore:
		# Every ship owns its own layout. The exported .tres is a single shared
		# resource across every instance of the scene that exports it, and each
		# module's condition now lives on the ModuleInstance inside that layout
		# — without this copy, damaging one pirate would damage every pirate of
		# the same type. (The restore path is already handed a fresh duplicate
		# by GameState.apply, as is the ship builder's.)
		if ship_layout != null:
			ship_layout = ship_layout.duplicate(true)
		_apply_ship_layout()

	_health.destroyed.connect(_on_destroyed)
	_health.health_changed.connect(_on_health_changed)
	_health.damaged.connect(_on_health_damaged)
	_base_hull_modulate = _hull_renderer.modulate

	if is_in_group("player_ship"):
		# Only on a session's very first region (no snapshot yet) — a warp
		# restore already carries forward whatever owned counts the player
		# had, seeding again on top would hand out free duplicates.
		if not GameState.has_snapshot():
			_seed_starter_owned_modules()
		GameState.apply(self)


## The parts you start a session holding. The starter hull is a bare Command
## Core, so these are not spares — they are the whole ship, sitting in the hold
## waiting to be bolted on, and the first thing a session asks you to do is walk
## into the builder and assemble something.
##
## Deliberately granted as parts rather than as materials to build parts from:
## there is no currency and no shop, so the honest way to hand the player their
## opening kit is to hand them the objects (see docs/direction.md §1). Only ever
## called once, on a session's first region (see _ready()).
const STARTER_PART_TYPE_IDS: Array[String] = [
	ModuleCatalog.HULL_SPAR_TYPE_ID,
	ModuleCatalog.HULL_WEDGE_TYPE_ID,
	ModuleCatalog.GUN_MK1_TYPE_ID,
	ModuleCatalog.REACTOR_PAIR_TYPE_ID,
	ModuleCatalog.THRUSTER_BLOCK_TYPE_ID,
	# The salvage loop's two halves. Both are starting equipment rather than
	# something to find: cutting a part off an enemy and dragging it home is the
	# game's core verb, and it can't be the reward for a loop it is required to
	# run.
	ModuleCatalog.SALVAGER_HARDPOINT_TYPE_ID,
	ModuleCatalog.GRAPPLE_MK1_TYPE_ID,
]


func _seed_starter_owned_modules() -> void:
	for type_id in STARTER_PART_TYPE_IDS:
		_inventory.add_owned_module(Inventory.owned_module_key(type_id))


func apply_layout(new_layout: ShipLayout) -> void:
	ship_layout = new_layout
	_apply_ship_layout()


func _apply_ship_layout() -> void:
	if ship_layout == null:
		return
	mass = ship_layout.total_mass()
	_cached_layout_extent = -1.0
	_health.configure(ship_layout.total_max_health() * personality.health_multiplier)
	_hull_renderer.faction_id = personality.faction_id
	_hull_renderer.set_layout(ship_layout)

	_wreckage.configure(self, ship_layout, _hull_renderer, personality.faction_id)
	_hull_damage.rebuild(ship_layout, _hull_renderer, personality.health_multiplier)
	_refresh_layout_stats()
	_spawn_thrusters()
	_hardpoints.rebuild(self, ship_layout, _hull_renderer)
	# After the bank exists, so modules that came in already destroyed get their
	# hardpoint visuals hidden again.
	_hull_damage.sync_hardpoint_visuals()
	layout_applied.emit()


## The aggregate stats every layout change re-derives. Kept separate from
## _apply_ship_layout() so a future caller can move these numbers without
## disturbing the ship's Health pool — a full apply still refills that, which is
## right for "I rebuilt my ship at the workbench" and wrong for anything
## narrower. Module condition is no longer among the things an apply resets: it
## belongs to the mounted parts and comes in with them (see ModuleInstance).
func _refresh_layout_stats() -> void:
	mass = ship_layout.total_mass()
	_energy.configure(ship_layout.total_energy_capacity(), ship_layout.total_energy_generation())
	_inventory.set_cargo_capacity(base_cargo_capacity + ship_layout.total_cargo_capacity())
	_inventory.rebuild_hold(ship_layout, base_hold_cells)
	_recompute_thrust_stats()
	_refresh_systems()


## Re-derives thrust and the speed caps from whichever engine modules are
## currently alive.
##
## Deliberately does not re-derive `mass`: a hull losing modules getting lighter
## — and therefore more agile — is a gameplay change, not a bug fix.
## Re-derives the energy pool from whatever the reactors and batteries are still
## managing. Separate from _refresh_layout_stats because this also has to run
## when nothing about the *layout* changed and only the parts' condition did —
## a reactor at half efficiency is a smaller reactor.
##
## ShipEnergy.configure keeps the pool's fill fraction across the change, so
## being shot does not hand the ship free energy or empty it.
func _recompute_energy_stats() -> void:
	if ship_layout == null:
		return
	_energy.configure(ship_layout.total_energy_capacity(), ship_layout.total_energy_generation())


func _recompute_thrust_stats() -> void:
	var live_thrust: float = 0.0
	for placement in ship_layout.placements:
		if is_module_destroyed(placement.placement_id):
			continue
		live_thrust += ship_layout.thrust_for(placement)

	thrust_force = maxf(live_thrust, 0.0)
	reverse_thrust_force = thrust_force * reverse_thrust_ratio

	var acceleration_estimate: float = (thrust_force / mass) if mass > 0.0 else 0.0
	max_speed = minf(acceleration_estimate * speed_per_acceleration, max_speed_ceiling)
	reverse_max_speed = max_speed * reverse_speed_ratio


# --- Geometry ----------------------------------------------------------------

## Approximate "collision radius" for HardpointWinch's touch/arrival checks
## against another ship — see get_layout_extent(), which this just aliases
## under a name meaningful to the winch.
func get_winch_radius() -> float:
	return get_layout_extent()


## Cached until the next layout apply — deliberately NOT invalidated when a
## module is destroyed or severed: the value is used as an approximate hull
## radius for AI spacing, winch reach and camera zoom, all of which are better
## served by a stable silhouette than by one that shrinks mid-fight.
func get_layout_extent() -> float:
	if ship_layout == null:
		return 0.0
	if _cached_layout_extent >= 0.0:
		return _cached_layout_extent
	_cached_layout_extent = _compute_layout_extent()
	return _cached_layout_extent


func _compute_layout_extent() -> float:
	var max_distance: float = 0.0
	for placement in ship_layout.placements:
		for cell in ship_layout.get_occupied_cells(placement):
			var local_pos: Vector2 = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
			max_distance = maxf(max_distance, local_pos.length() + _hull_renderer.cell_size)
	return max_distance


## World-space position of the ship's Command Core hex — the point Salvage
## must actually reach to self-collect via plain hull contact (see
## Salvage._is_near_core), rather than any point on the hull. Falls back to
## the ship's own origin if the layout somehow has no core yet (shouldn't
## happen in practice — exactly one Core is an enforced layout rule).
func get_core_global_position() -> Vector2:
	if ship_layout == null or ship_layout.core_placement_id.is_empty():
		return global_position
	var core_placement: ModulePlacement = ship_layout.get_placement_by_id(ship_layout.core_placement_id)
	if core_placement == null:
		return global_position
	var local_pos: Vector2 = HexUtils.axial_to_pixel(core_placement.hex_coord, _hull_renderer.cell_size).rotated(_hull_renderer.rotation)
	return to_global(local_pos)


## How close a drifting Salvage must get to the Core to self-collect via hull
## contact — one hex-cell's reach, the same scale as any other module.
func get_core_collect_radius() -> float:
	return _hull_renderer.cell_size


# --- Health and module condition ---------------------------------------------

func get_module_condition(placement_id: String) -> float:
	return _hull_damage.get_condition(placement_id)


func is_module_destroyed(placement_id: String) -> bool:
	return _hull_damage.is_destroyed(placement_id)


## How much of its rated output the part at this placement still delivers, 0..1
## (see ModuleInstance.efficiency). A destroyed or severed module returns 0 —
## everything that reads this is already gated on is_module_destroyed elsewhere,
## but a wrecked module reporting partial output would be a quiet way for a dead
## gun to keep shooting.
func get_module_efficiency(placement_id: String) -> float:
	if ship_layout == null or is_module_destroyed(placement_id):
		return 0.0
	var placement: ModulePlacement = ship_layout.get_placement_by_id(placement_id)
	return ship_layout.efficiency_of(placement) if placement != null else 1.0


## Health readouts as a small public API, so the HUD, trade panel and GameState
## never do ship.get_node("Health") to read them.
func get_current_health() -> float:
	return _health.current_health


func get_max_health() -> float:
	return _health.max_health


func get_health_fraction() -> float:
	return (_health.current_health / _health.max_health) if _health.max_health > 0.0 else 1.0


## Restores a previously captured health fraction (see GameState) without going
## through take_damage/heal, which would fire hit feedback for what is really
## just state being carried across a scene change.
func set_health_fraction(fraction: float) -> void:
	_health.current_health = _health.max_health * clampf(fraction, 0.0, 1.0)
	_health.health_changed.emit(_health.current_health, _health.max_health)


func get_missing_health() -> float:
	return _health.max_health - _health.current_health


func needs_repair() -> bool:
	return get_missing_health() > 0.01


func get_repair_cost() -> int:
	return ceili(get_missing_health() * repair_cost_per_health)


## Paid station repair: tops every attached module back to full condition and
## heals the overall Health pool to match.
func repair_fully() -> void:
	_hull_damage.repair_fully()
	_health.heal(get_missing_health())


func take_damage(amount: float) -> void:
	if invulnerable:
		return
	_hull_damage.note_damage_taken()
	_health.take_damage(amount)


## Same as take_damage(), but also attributes the hit to whichever module
## occupies the impact point, so individual engines/weapons can be knocked out
## mid-fight — the ship's overall Health pool takes the same damage either way;
## module condition is a separate, parallel effect.
func take_damage_at(amount: float, impact_point: Vector2) -> void:
	if invulnerable:
		return
	take_damage(amount)
	_hull_damage.damage_at(amount, impact_point)


## Fired by HardpointPhaseLance — a piercing hit along a line rather than one
## hex plus splash. Overall Health only takes the hit once, same as a normal shot.
func take_beam_damage(amount: float, entry_point: Vector2, aim_direction: Vector2, max_travel_distance: float) -> void:
	if invulnerable:
		return
	take_damage(amount)
	_hull_damage.damage_beam(amount, entry_point, aim_direction, max_travel_distance)


## Fired by HardpointSlicer. Deliberately unlike take_beam_damage on two counts:
## the overall Health pool is NOT touched, and only the single part under the
## contact point is affected — no splash, and nothing behind it.
##
## The Slicer is a dismantling tool, not a weapon. It should never be able to
## kill a ship, only take it apart, so recovering a part means cutting it free
## rather than grinding a hull down until it dies.
##
## Anything that loses its connection to the core as a result is severed intact
## rather than rolled for (see HullDamageModel's `clean_cut`).
## `band_fraction` is a share of the cuttable band, not raw damage — see
## HullDamageModel.damage_cut, which also documents the returned dictionary.
func take_slicer_cut(band_fraction: float, impact_point: Vector2, aim_direction: Vector2) -> Dictionary:
	return _hull_damage.damage_cut(band_fraction, impact_point, aim_direction)


## Geometry of the hex a cutting beam is touching, in world space — see
## HullDamageModel.cut_cell_at. Public so the Slicer's effect can draw its
## reticle and walk its contact point around the actual cell instead of
## reconstructing the hull's hex layout from outside.
func get_cut_cell(impact_point: Vector2, aim_direction: Vector2) -> Dictionary:
	return _hull_damage.cut_cell_at(impact_point, aim_direction)


## The same geometry for a cell already locked on to — see
## HullDamageModel.cell_geometry.
func get_cell_geometry(coord: Vector2i) -> Dictionary:
	return _hull_damage.cell_geometry(coord)


## Where a cut seam should be parented so it stays on this hull as it moves and
## survives the tile coming off (see SalvageCutTrail).
func get_hull_renderer_node() -> Node2D:
	return _hull_renderer


## Credits one kill to the specific part that fired the fatal shot, recorded on
## the mounted ModuleInstance rather than on the ship or the module type. That is
## the point: the tally travels with the object, so a gun cut off a raider
## arrives on your hull already carrying what it did while it was theirs, and
## keeps counting.
##
## Enemy hardpoints go through exactly the same path — a pirate's cannon is
## accumulating a record the whole time it is shooting at you, and that record is
## what you take when you cut it free.
##
## Silently ignores a placement that no longer exists or has already handed its
## part over to the wreckage: a gun can be shot off its mount while its last bolt
## is still travelling.
func record_hardpoint_kill(placement_id: String) -> void:
	if ship_layout == null or placement_id.is_empty():
		return
	var placement: ModulePlacement = ship_layout.get_placement_by_id(placement_id)
	if placement == null or placement.instance == null:
		return
	placement.instance.record_kill()


## Entry point for a hardpoint to damage its own mount — see
## HardpointGun.malfunction_chance.
func damage_own_module(placement_id: String, amount: float) -> void:
	_hull_damage.damage_placement(placement_id, amount)


## The damage model found nothing functional left (Core gone, or every module
## gone). Finishing the ship goes through Health so destruction, loot and the
## destroyed signal all follow their normal path.
func _on_hull_lost() -> void:
	_health.take_damage(_health.current_health)


func _on_health_changed(current: float, max_health: float) -> void:
	health_changed.emit(current, max_health)


## Hit feedback, driven by Health.damaged rather than by comparing successive
## health_changed values here: health_changed also fires for configure() (a ship
## rebuild) and heal() (module regrowth), and gating the white hull flash on it
## restarted the flash tween every physics frame throughout a passive repair.
func _on_health_damaged(amount: float, current: float) -> void:
	damaged.emit(amount, current)

	if hit_sound != null:
		_hit_sound_player.stream = hit_sound
		_hit_sound_player.play()

	if _flash_tween:
		_flash_tween.kill()
	_hull_renderer.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_hull_renderer, "modulate", _base_hull_modulate, hit_flash_duration)


# --- Energy ------------------------------------------------------------------

func get_energy() -> float:
	return _energy.current


func get_max_energy() -> float:
	return _energy.maximum


## The ship builder previews a working layout's totals before it's applied, and
## needs the same baselines the live ship adds on top of them (see ShipEnergy).
func get_base_energy_generation() -> float:
	return _energy.base_generation


func get_base_energy_capacity() -> float:
	return _energy.base_capacity


func has_energy(amount: float) -> bool:
	return _energy.has(amount)


func spend_energy(amount: float) -> bool:
	return _energy.spend(amount)


func _on_energy_changed(current: float, maximum: float) -> void:
	energy_changed.emit(current, maximum)


func _on_energy_usage_changed(usage: float, generation: float) -> void:
	energy_usage_changed.emit(usage, generation)


# --- Systems -----------------------------------------------------------------

## The ship's power-management component. Exposed whole (like get_inventory())
## because the HUD binds to its signals and reads several values per system;
## what nothing outside may do is reach in with get_node("Systems").
func get_systems() -> ShipSystems:
	return _systems


## The gate every system consumer asks about: switched on by the player *and*
## backed by at least one live module.
func is_system_enabled(system_id: StringName) -> bool:
	return _systems.is_active(system_id)


func _refresh_systems() -> void:
	_systems.refresh(self, ship_layout)


## Boosted thrust costs proportionally more, same multiplier as the extra
## speed/force it grants.
func _try_spend_thrust_energy(delta: float) -> bool:
	var boosting: bool = _boost_active and _thrust_input > 0.0
	var cost: float = thrust_energy_cost * absf(_thrust_input) * (boost_multiplier if boosting else 1.0) * delta
	return spend_energy(cost)


# --- Hardpoints --------------------------------------------------------------

## The Salvager system's switch ("G" — see ship_input.gd). Every mounted, intact
## HardpointSlicer pulls this flag each physics frame (same pull-model as
## is_module_destroyed) rather than being pushed a one-shot command, so a slicer
## that mounts or repairs mid-toggle picks up the current state immediately
## instead of needing a fresh key press.
func is_slicer_active() -> bool:
	return is_system_enabled(ShipSystems.SALVAGER)


func get_scanner() -> Scanner:
	return _scanner


## Radar is a pure capability flag (see ModuleCatalog.RADAR_HARDPOINT_TYPE_ID)
## rather than a spawned hardpoint node — it has no fixed facing or world-space
## visual of its own, it just gates whether RadarDisplay (the HUD) runs at all.
## True if the layout has at least one radar hardpoint that isn't currently
## destroyed/detached, and the Sensors system is switched on — powering sensors
## down blanks the radar exactly as losing the module does.
func has_radar() -> bool:
	if ship_layout == null or not is_system_enabled(ShipSystems.SENSORS):
		return false
	return _has_live_placement(ship_layout.get_radar_hardpoint_placements())


## Same "pure capability flag" shape as has_radar() — see
## ModuleCatalog.SCANNER_HARDPOINT_TYPE_ID. Also gated on the Sensors system,
## which means switching sensors off mid-pulse cancels the scan (Scanner
## re-checks this every frame) rather than letting it finish for free.
func has_scanner() -> bool:
	if ship_layout == null or not is_system_enabled(ShipSystems.SENSORS):
		return false
	return _has_live_placement(ship_layout.get_scanner_hardpoint_placements())


func _has_live_placement(placements: Array[ModulePlacement]) -> bool:
	for placement in placements:
		if not is_module_destroyed(placement.placement_id):
			return true
	return false


# --- Aim and targeting -------------------------------------------------------

## Where this ship's aimable hardpoints point. Falls back to straight ahead
## when no controller is aiming (see ShipIntent.has_aim_target).
func get_aim_target() -> Vector2:
	return _aim_target if _has_aim_target else global_position + transform.x * 1000.0


## The object homing missiles steer toward: set through ShipIntent by the
## player's lock-on (see ship_input.gd) or by whatever an AI ship is currently
## pursuing (see ship_ai.gd). Null means "no lock" — HardpointMissileLauncher
## then fires unguided, straight-outward missiles.
func get_locked_target() -> Node2D:
	if _locked_target != null and not is_instance_valid(_locked_target):
		_locked_target = null
	return _locked_target


func enter_nebula() -> void:
	_nebula_depth += 1


func exit_nebula() -> void:
	_nebula_depth = maxi(_nebula_depth - 1, 0)


func is_in_nebula() -> bool:
	return _nebula_depth > 0


# --- Cargo -------------------------------------------------------------------

## The ship's cargo/credits/research store. Exposed as a component rather than
## proxied method-by-method because the HUD and every economy panel bind to a
## dozen of its signals; what they must not do is reach in with
## get_node("Inventory"), which is the coupling this replaces.
func get_inventory() -> Inventory:
	return _inventory


func add_material(material_id: String, amount: int) -> void:
	_inventory.add_material(material_id, amount)


## Capacity-respecting version of add_material() — see Inventory.try_add_material.
## Used by Salvage pickup so a full cargo hold rejects the item instead of
## silently exceeding capacity.
func try_add_material(material_id: String, amount: int) -> bool:
	return _inventory.try_add_material(material_id, amount)


func discard_material(material_id: String, amount: int) -> int:
	return _inventory.discard_material(material_id, amount)


func add_component(component_id: String, amount: int) -> void:
	_inventory.add_component(component_id, amount)


## Capacity-respecting version of add_component() — see Inventory.
## try_add_component. Used by Salvage pickup (Phase 5.3 component drops) so
## a full cargo hold rejects the item the same way a material drop would.
func try_add_component(component_id: String, amount: int) -> bool:
	return _inventory.try_add_component(component_id, amount)


## Called by HardpointWinch/HardpointTractorBeam once it finishes reeling in a
## CapturedTechPart: the recovered module goes straight into the hold as the
## same object that was mounted on the wreck — same instance_id, same wear, same
## origin — ready to be placed. There is deliberately no per-type count and no
## repair step in between; that pair of conversions is what used to launder a
## specific part into an anonymous type (docs/direction.md §4).
##
## A non-empty manufacturer_id also discovers that manufacturer (see
## Inventory.discover_manufacturer) — knowing "Atlas Heavy exists" is a separate
## fact from holding one of their guns.
## Returns false if the hold has no room for it, in which case the part is NOT
## taken and stays wherever it is — on the end of the grapple, usually (see
## take_in_tow). A part is only owned once it physically has cells.
func capture_tech_part(instance: ModuleInstance) -> bool:
	if instance == null:
		return false
	if not _inventory.add_captured_instance(instance):
		return false
	if not instance.manufacturer_id.is_empty():
		_inventory.discover_manufacturer(instance.manufacturer_id)
	return true


# --- Towing ------------------------------------------------------------------

## The part currently on the end of the grapple, hauled home but not yet stowed
## (see HardpointWinch._on_secured). It is a world object the whole time — the
## player is carrying it around rather than having absorbed it — and the ship
## builder is where it gets put into a bay.
var _towed_part: Node2D = null


## Called by the grapple once a part is docked at the hull. The part keeps
## living in the world on the end of the line; this is only the ship knowing it
## is there, so the builder can offer to stow it.
func take_in_tow(part: Node2D) -> void:
	_towed_part = part


## The towed part, or null. Clears itself if the part has been freed — cut loose,
## shot, or claimed by something else.
func get_towed_part() -> Node2D:
	if _towed_part != null and not is_instance_valid(_towed_part):
		_towed_part = null
	return _towed_part


func clear_tow() -> void:
	_towed_part = null


## Puts the towed part into a specific bay cell — the INVENTORY tab's click.
## False, and nothing changes, if it will not fit from that cell: the part stays
## on the line and the player can try another cell, another bay, or let it go.
func stow_towed_part(bay_index: int, cell: Vector2i) -> bool:
	var part: Node2D = get_towed_part()
	if part == null or not part.has_method("peek_instance"):
		return false
	var instance: ModuleInstance = part.call("peek_instance")
	if instance == null:
		return false
	if not _inventory.stow_instance(instance, bay_index, cell):
		return false
	# Only now does the part stop being a world object. Taking the instance and
	# freeing the node are deliberately the last steps, after the hold has
	# committed — a refused stow must leave the part exactly as it was.
	part.call("release_instance")
	if not instance.manufacturer_id.is_empty():
		_inventory.discover_manufacturer(instance.manufacturer_id)
	part.call("collect")
	_towed_part = null
	return true


## Lets the towed part go. The grapple holding it drops the line; the part drifts
## off from wherever it was, still recoverable if the player changes their mind.
func jettison_towed_part() -> void:
	_hardpoints.drop_towed_parts()


# --- Flight ------------------------------------------------------------------

## The single entry point for commanding this ship — the local player's input,
## an AI personality, and eventually a remote peer all arrive here. `roles` is
## what the submitter is entitled to command (see ShipIntent.Role); fields
## outside it are discarded rather than trusted, so several crew members can
## submit partial intents for one ship and no station can act outside its own.
##
## Submissions accumulate until the next _physics_process consumes them.
## Controllers run at process_physics_priority -1 so their submission lands
## before the ship reads it, rather than a frame late.
func submit_intent(intent: ShipIntent, roles: int = ShipIntent.ALL_ROLES) -> void:
	_pending_intent.merge_from(intent, roles)
	_submitted_roles |= roles


## Applies whatever was submitted this frame. Any role nobody submitted for is
## released first, so an uncrewed station — a disconnected player, a ship with
## no controller at all — stops commanding rather than latching its last order.
func _consume_intent() -> void:
	_pending_intent.clear_roles(ShipIntent.ALL_ROLES & ~_submitted_roles)
	_submitted_roles = 0

	_thrust_input = clampf(_pending_intent.thrust, -1.0, 1.0)
	_turn_input = clampf(_pending_intent.turn, -1.0, 1.0)
	_boost_active = _pending_intent.boost

	if _pending_intent.has_aim_target:
		_aim_target = _pending_intent.aim_target
		_has_aim_target = true

	if _pending_intent.set_lock:
		_locked_target = _pending_intent.locked_target

	# Powered-down weapons simply don't fire — the gate is here rather than in
	# HardpointBank so every weapon kind is covered by one check.
	var weapons_online: bool = is_system_enabled(ShipSystems.WEAPONS)
	if _pending_intent.fire_primary and weapons_online:
		_hardpoints.fire_primary()
	if _pending_intent.fire_secondary and weapons_online:
		_hardpoints.fire_secondary()
	if _pending_intent.fire_winch:
		_hardpoints.press_winch()
	if _pending_intent.toggle_scan:
		_scanner.fire_ping()
	for system_id in _pending_intent.toggled_systems:
		_systems.toggle(system_id)

	# Edge commands are consumed once; held states (thrust, turn, boost)
	# persist until the next submission overwrites them.
	_pending_intent.clear_one_shots()


## Guarded against a zero/negative mass (a layout whose modules all report no
## mass_contribution, or one stripped by negative manufacturer/upgrade
## deltas) — dividing by it produced INF velocity and threw the ship out of
## the region.
func apply_impulse(impulse: Vector2) -> void:
	if mass <= 0.0:
		return
	velocity += impulse / mass


func _physics_process(delta: float) -> void:
	_consume_intent()
	_energy.tick(delta)
	# Idle load is charged after regeneration, so a ship whose systems out-draw
	# its reactor spends what it just made and then eats into the reserve.
	_systems.process(delta)
	_hull_damage.process(delta)
	_apply_turn(delta)

	if _thrust_input != 0.0 and _try_spend_thrust_energy(delta):
		var thrust: float = thrust_force if _thrust_input > 0.0 else reverse_thrust_force
		var current_max_speed: float = max_speed
		if _boost_active and _thrust_input > 0.0:
			thrust *= boost_multiplier
			current_max_speed *= boost_multiplier
		var acceleration: float = thrust / mass

		# Drag is not suspended just because an engine is lit — only because it
		# is pushing the way the ship is already going. Retro-thrust used to
		# replace the coasting drag rather than add to it, and reverse thrust is
		# far weaker than that drag (0.2 of forward), so holding the brake
		# stopped the ship roughly three times *slower* than releasing the
		# throttle. Braking must never be worse than doing nothing.
		if _thrust_input * velocity.dot(transform.x) < 0.0:
			velocity = velocity.move_toward(Vector2.ZERO, drag * max_speed * delta)

		velocity += transform.x * _thrust_input * acceleration * delta

		if _thrust_input > 0.0:
			_bleed_overspeed(current_max_speed, acceleration, delta)
		else:
			var forward_speed: float = velocity.dot(transform.x)
			if forward_speed < -reverse_max_speed:
				velocity -= transform.x * (forward_speed + reverse_max_speed)
	else:
		# No thrust input, or thrust requested but not enough energy for it —
		# either way the ship just coasts/drags rather than accelerating.
		velocity = velocity.move_toward(Vector2.ZERO, drag * max_speed * delta)

	# Generous absolute safety net (not a directional cap) so nothing — e.g.
	# weapon recoil stacking — can send velocity unbounded; normal flight,
	# including turning around while carrying momentum, never reaches it.
	velocity = velocity.limit_length(max_speed * boost_multiplier)

	move_and_slide()
	_update_engine_particles()
	if _hardpoints.has_aimable_hardpoints():
		_hardpoints.update_aim(get_aim_target())


## Spins the ship up toward its top turn rate while there is turn input, and
## lets the spin bleed off when there isn't, rather than snapping to either.
##
## Both the acceleration and the drag are scaled by the same mass factor as the
## top rate, so a heavy hull is slow to start turning, slow to stop, and never
## turns as fast — three consequences of one number, which is what makes hull
## mass legible in the hand instead of only on the stat strip.
##
## The bleed is applied even while turning, against the *opposite* direction
## only, so reversing a turn is quicker than starting one from rest. Without
## that, flicking left-to-right feels like the ship is fighting itself.
func _apply_turn(delta: float) -> void:
	var handling: float = _mass_handling_factor()
	var top_rate: float = rotation_speed * handling
	# Squared, not linear. Scaling the acceleration and the top rate by the same
	# factor cancels out — time-to-top-rate is rate/acceleration — so mass moved
	# the ceiling but every hull still reached its own ceiling in the same 0.25s,
	# which is the opposite of feeling heavy. The extra power is what makes a big
	# hull slow to answer the stick as well as slow at the end of it.
	var authority: float = handling * handling
	var bleed: float = angular_drag * rotation_speed * authority * delta

	if is_zero_approx(_turn_input):
		_angular_velocity = move_toward(_angular_velocity, 0.0, bleed)
	else:
		if not is_zero_approx(_angular_velocity) \
				and signf(_angular_velocity) != signf(_turn_input):
			_angular_velocity = move_toward(_angular_velocity, 0.0, bleed)
		_angular_velocity += _turn_input * angular_acceleration * authority * delta
		_angular_velocity = clampf(_angular_velocity, -top_rate, top_rate)

	rotation += _angular_velocity * delta


## How much this hull's mass slows its turn rate. Turning used to be a flat
## constant, completely independent of the ship — a 13-cell hull and a 60-cell
## hull rotated identically, which made filling in the interior free. Since
## rotation is the handling stat combat legibility leans on hardest, that was
## most of why a solid blob was the optimal shape.
##
## Deliberately mass only, not moment of inertia: this punishes volume, which is
## the blob. It does NOT punish sprawl, so a long thin hull currently turns just
## as well as a compact one of the same mass. Scaling by mass * extent^2 would
## add that opposing pressure (get_layout_extent() already exists), but it is a
## separate design decision and wants its own playtest.
func _mass_handling_factor() -> float:
	if mass <= 0.0:
		return handling_factor_max
	var ratio: float = handling_reference_mass / mass
	if ratio < 1.0:
		ratio = pow(ratio, handling_mass_falloff)
	return clampf(ratio, handling_factor_min, handling_factor_max)


## Pulls speed down to `cap` gradually instead of snapping to it.
##
## `velocity.limit_length(cap)` used to do this, which was invisible while
## accelerating (the cap is approached from below) but wrong the instant the cap
## itself dropped — releasing boost cut current_max_speed by boost_multiplier and
## the clamp deleted the excess velocity in one frame, so the ship teleported
## down to cruise speed instead of decelerating into it.
##
## The bleed rate is the ship's own coasting drag, so dropping boost feels like
## the same deceleration as letting go of the throttle. It is floored at this
## frame's acceleration so the cap still genuinely holds: without that, a hull
## whose acceleration exceeds its drag would out-accelerate the bleed and creep
## past max_speed indefinitely.
func _bleed_overspeed(cap: float, acceleration: float, delta: float) -> void:
	var speed: float = velocity.length()
	if speed <= cap:
		return
	var bleed: float = maxf(drag * max_speed, acceleration) * delta
	velocity = velocity.normalized() * maxf(cap, speed - bleed)


func _spawn_thrusters() -> void:
	for thruster in _thrusters:
		thruster.queue_free()
	_thrusters.clear()
	_thruster_placement_ids.clear()
	_thruster_particles_boost.clear()
	_thruster_particles_boost_soft.clear()
	_thruster_particles_normal.clear()
	_thruster_particles_turn_left.clear()
	_thruster_particles_turn_right.clear()

	if _engine_audio == null:
		_engine_audio = EngineAudio.new()
		add_child(_engine_audio)
	_engine_audio.configure(ship_layout, personality.faction_id)

	for placement in ship_layout.get_thruster_placements():
		# One flame per *cell*, not per placement. A multi-hex thruster (the
		# Thruster Block is two hexes) used to light only its anchor cell, so half
		# of it sat visibly dead while the ship accelerated on it — the module
		# contributes thrust as a whole, and it should burn as a whole.
		#
		# The parallel arrays below now hold one entry per cell rather than per
		# module, with a multi-hex module's cells repeating its placement_id. That
		# is what _update_engine_particles wants anyway: it asks per flame whether
		# that flame's module is still alive, so every cell of a destroyed block
		# goes dark together.
		for cell in ship_layout.get_occupied_cells(placement):
			var thruster: Node2D = engine_thruster_scene.instantiate()
			add_child(thruster)
			# Offset from the hex's center toward its trailing vertex, so the
			# flame visually bursts from the back tip of the hex instead of its
			# middle. This is in hex-grid-local space (same space as hex_center,
			# pre-_hull_renderer.rotation) — _hull_renderer.rotation is a fixed
			# +90° twist between the hex grid's own authored axes and the ship's
			# true movement-forward (+X) axis, so hex-grid-local "backward" is
			# +Y (a vertex per HexUtils.hex_corners), not -X. Only the *position*
			# needs that rotation applied (matching hex_center below) — the
			# thruster's own rotation stays default (0) so the particle's local
			# -X direction keeps pointing at the ship's real physics-backward,
			# not doubly twisted by the hex grid's separate authoring offset.
			var hex_center: Vector2 = HexUtils.axial_to_pixel(cell, _hull_renderer.cell_size)
			var back_vertex_offset: Vector2 = Vector2(0.0, _hull_renderer.cell_size)
			thruster.position = (hex_center + back_vertex_offset).rotated(_hull_renderer.rotation)
			_thrusters.append(thruster)
			_thruster_placement_ids.append(placement.placement_id)
			_thruster_particles_boost.append(thruster.get_node("Particles"))
			_thruster_particles_boost_soft.append(thruster.get_node("ParticlesSoft"))
			_thruster_particles_normal.append(thruster.get_node("ParticlesNormal"))
			_thruster_particles_turn_left.append(thruster.get_node("ParticlesTurnLeft"))
			_thruster_particles_turn_right.append(thruster.get_node("ParticlesTurnRight"))


func _update_engine_particles() -> void:
	var thrusting_forward: bool = _thrust_input > 0.0
	var boosting: bool = thrusting_forward and _boost_active

	# Any throttle at all, forward or reverse: the engines are burning either
	# way, even though only forward thrust lights the main flame.
	if _engine_audio != null:
		_engine_audio.set_thrusting(
			not is_zero_approx(_thrust_input) and get_current_health() > 0.0, boosting)

	# Attitude jets fire on the side that produces the torque, so the exhaust
	# points opposite the way the nose swings: the engines sit behind the centre
	# of mass, so pushing the tail one way rotates the nose the other. They also
	# fire while the spin is being *killed* — coasting to a stop is now something
	# the ship does over time, and it should be visible that it is doing it.
	var braking: bool = is_zero_approx(_turn_input) and not is_zero_approx(_angular_velocity)
	var turn_direction: float = -signf(_angular_velocity) if braking else signf(_turn_input)
	var turning_left: bool = turn_direction < 0.0
	var turning_right: bool = turn_direction > 0.0

	for i in _thrusters.size():
		# A destroyed/detached engine shouldn't keep showing its own flame,
		# even while other engines (or leftover momentum) keep the ship
		# actually moving forward.
		var alive: bool = not is_module_destroyed(_thruster_placement_ids[i])

		_set_emitting(_thruster_particles_boost[i], boosting and alive)
		_set_emitting(_thruster_particles_boost_soft[i], boosting and alive)
		_set_emitting(_thruster_particles_normal[i], thrusting_forward and not boosting and alive)
		_set_emitting(_thruster_particles_turn_left[i], turning_left and alive)
		_set_emitting(_thruster_particles_turn_right[i], turning_right and alive)


## GPUParticles2D.set_emitting deliberately never early-outs, so assigning it
## unconditionally pushes a RenderingServer command per emitter per physics
## frame — three per thruster, and a large hull has many thrusters. These
## emitters are not one_shot, so `emitting` is authoritative and safe to test.
func _set_emitting(particles: GPUParticles2D, should_emit: bool) -> void:
	if particles.emitting != should_emit:
		particles.emitting = should_emit


# --- Destruction and loot ----------------------------------------------------

## Deferred as a whole: this fires from within the physics engine's collision
## query flush (via Projectile's body_entered signal), and both adding the
## Salvage Area2D to the tree and freeing this body would otherwise touch
## physics server shape state mid-flush.
func _on_destroyed() -> void:
	destroyed.emit()
	_finish_destruction.call_deferred()


func _finish_destruction() -> void:
	var explosion: Explosion = explosion_scene.instantiate()
	explosion.effect_scale = destruction_explosion_scale
	WorldSpawn.attach_at(explosion, global_position)

	if drops_salvage:
		var drop_count: int = GameRng.stream("loot").randi_range(salvage_drop_count_min, salvage_drop_count_max)
		for i in drop_count:
			_spawn_kill_drop()

	queue_free()


func _spawn_kill_drop() -> void:
	var rng: RandomNumberGenerator = GameRng.stream("loot")
	var salvage: Salvage = salvage_scene.instantiate()
	var rolled_rarity: Salvage.Rarity = _roll_salvage_rarity()
	salvage.rarity = rolled_rarity
	if rng.randf() < component_drop_chance:
		salvage.kind = Salvage.Kind.COMPONENT
		salvage.component_id = _roll_combat_component()
	else:
		salvage.material_id = _roll_combat_material()
	salvage.is_dangerous = rng.randf() < _danger_chance_for_rarity(rolled_rarity)
	# Small scatter so multiple drops from one kill don't spawn stacked exactly
	# on top of each other.
	var scatter := Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
	WorldSpawn.attach_at(salvage, global_position + scatter)


func _danger_chance_for_rarity(rolled_rarity: Salvage.Rarity) -> float:
	match rolled_rarity:
		Salvage.Rarity.COMMON:
			return 0.05
		Salvage.Rarity.UNCOMMON:
			return 0.1
		Salvage.Rarity.RARE:
			return 0.2
		Salvage.Rarity.EXPERIMENTAL:
			return 0.35
		Salvage.Rarity.ARTEFACT:
			return 0.5
		_:
			return 0.0


func _roll_salvage_rarity() -> Salvage.Rarity:
	var roll: float = GameRng.stream("loot").randf()
	if roll < 0.55:
		return Salvage.Rarity.COMMON
	elif roll < 0.8:
		return Salvage.Rarity.UNCOMMON
	elif roll < 0.93:
		return Salvage.Rarity.RARE
	elif roll < 0.99:
		return Salvage.Rarity.EXPERIMENTAL
	else:
		return Salvage.Rarity.ARTEFACT


## Combat kills have no "asteroid variant" to anchor a primary material, so
## each drop rolls uniformly from all four raw materials (see
## MaterialCatalog.ALL_IDS) independently of its rarity/amount tier.
func _roll_combat_material() -> String:
	return MaterialCatalog.ALL_IDS[GameRng.stream("loot").randi_range(0, MaterialCatalog.ALL_IDS.size() - 1)]


## See component_drop_chance/rare_component_chance — picks which component a
## kill-drop that already rolled COMPONENT actually carries.
func _roll_combat_component() -> String:
	var rng: RandomNumberGenerator = GameRng.stream("loot")
	var pool: Array[String] = ComponentCatalog.RARE_IDS if rng.randf() < rare_component_chance else ComponentCatalog.COMMON_IDS
	return pool[rng.randi_range(0, pool.size() - 1)]

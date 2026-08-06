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
##   HardpointBank     every mounted hardpoint, spawning them, firing and aiming
##   HullDamageModel   per-module condition, severance and regrowth
##   WreckageSpawner   the debris and sparks a severed module throws off
##
## External systems keep talking to Ship, never to those children — see the
## delegating methods below and the relayed signals.

signal layout_applied
signal energy_changed(current: float, max_energy: float)
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
@export var rotation_speed: float = 3.5
@export var drag: float = 0.6
@export var mass: float = 1.0
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
@export var destruction_explosion_scale: float = 2.2
@export var drops_salvage: bool = true
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
@export var reverse_speed_ratio: float = 0.35

## Cargo capacity available even with no Storage modules installed, matching the
## same "baseline + layout total" shape as ShipEnergy's base_capacity.
@export var base_cargo_capacity: float = 100.0
## Energy/sec spent thrusting at full non-boosted throttle. Deliberately at
## or below ShipEnergy.base_generation so cruising is sustainable forever on
## base power alone — firing weapons or boosting is what actually draws the
## reserve down without a Reactor installed.
@export var thrust_energy_cost: float = 8.0
## Credits charged per point of overall Health restored by repair_fully.
@export var repair_cost_per_health: float = 1.0

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
## Toggled by toggle_grinder ("G" — see ship_input.gd), pulled every frame by
## each mounted HardpointGrinder, same pull-model as is_module_destroyed.
## Unlike the Tractor Beam, grinding needs deliberate activation since it deals
## continuous damage.
var _grinder_active: bool = false
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
@onready var _hardpoints: HardpointBank = $Hardpoints
@onready var _hull_damage: HullDamageModel = $HullDamage
@onready var _wreckage: WreckageSpawner = $Wreckage


func _ready() -> void:
	_hull_damage.configure(self, _hardpoints, _wreckage)
	# The damage model never touches this ship's Health pool directly — it
	# reports what happened and the ship decides what that costs.
	_hull_damage.modules_changed.connect(_recompute_thrust_stats)
	_hull_damage.hull_healed.connect(_health.heal)
	_hull_damage.hull_lost.connect(_on_hull_lost)
	_energy.energy_changed.connect(_on_energy_changed)

	# A restoring player ship is about to have GameState.apply() push its saved
	# layout in, which rebuilds everything anyway — building the scene's own
	# default layout first (thrusters, collision shapes, every hardpoint node)
	# just to throw it away was a wasted full rebuild on every warp arrival.
	var will_restore: bool = is_in_group("player_ship") and GameState.has_snapshot()
	if not will_restore:
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


## Phase 5.2 "avoid soft-locking the player": grants one owned instance of
## every module type/manufacturer combo on the starter loadout, in addition
## to what's already physically installed, so removing a starter module in
## the builder never leaves the player unable to re-place it (own-module
## stock is separate from what's currently mounted). Only ever called once,
## on a session's first region (see _ready()).
func _seed_starter_owned_modules() -> void:
	if ship_layout == null:
		return
	for placement in ship_layout.placements:
		var key: String = Inventory.owned_module_key(placement.module_type_id, placement.manufacturer_id)
		_inventory.add_owned_module(key)


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
	layout_applied.emit()


## The aggregate stats every layout change re-derives, shared by a full rebuild
## and by a single purchased upgrade (see apply_instance_upgrade_effect), which
## must move these numbers without disturbing health or module condition.
func _refresh_layout_stats() -> void:
	mass = ship_layout.total_mass()
	_energy.configure(ship_layout.total_energy_capacity(), ship_layout.total_energy_generation())
	_inventory.set_cargo_capacity(base_cargo_capacity + ship_layout.total_cargo_capacity())
	_recompute_thrust_stats()


## Re-derives thrust and the speed caps from whichever engine modules are
## currently alive, including their own per-instance upgrade deltas.
##
## Deliberately does not re-derive `mass`: a hull losing modules getting lighter
## — and therefore more agile — is a gameplay change, not a bug fix.
func _recompute_thrust_stats() -> void:
	var live_thrust: float = 0.0
	for placement in ship_layout.placements:
		if is_module_destroyed(placement.placement_id):
			continue
		live_thrust += ship_layout.thrust_for(placement)

	thrust_force = maxf(live_thrust, 0.0)
	reverse_thrust_force = thrust_force * reverse_thrust_ratio

	var acceleration_estimate: float = (thrust_force / mass) if mass > 0.0 else 0.0
	max_speed = acceleration_estimate * speed_per_acceleration
	reverse_max_speed = max_speed * reverse_speed_ratio


## Applies one just-unlocked per-instance upgrade (Phase 8.1, see UpgradeMenu)
## to the *live* ship. Deliberately narrower than _apply_ship_layout() (the ship
## builder's full Apply): it re-derives the aggregate stats and, for a hardpoint
## with a live spawned node, pushes the single new upgrade's modifiers onto that
## one node — it never touches health or module-condition state, and respawns
## nothing. A full _apply_ship_layout() would silently heal the ship to full and
## reset every module's condition, which is correct for "I just rebuilt my ship
## at the workbench" but not for "I bought one thruster upgrade". Radar/Scanner
## have no spawned node at all (pure capability flags, see has_radar/has_scanner)
## so upgrades targeting them are a no-op here — see ModuleUpgradeCatalog.
func apply_instance_upgrade_effect(placement: ModulePlacement, upgrade_node: ModuleUpgradeNode) -> void:
	_refresh_layout_stats()
	var target_node: Node = _hardpoints.get_node_for(placement.placement_id)
	if target_node != null:
		_hardpoints.apply_modifiers(target_node, upgrade_node.modifiers)


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
	_hull_damage.note_damage_taken()
	_health.take_damage(amount)


## Same as take_damage(), but also attributes the hit to whichever module
## occupies the impact point, so individual engines/weapons can be knocked out
## mid-fight — the ship's overall Health pool takes the same damage either way;
## module condition is a separate, parallel effect.
func take_damage_at(amount: float, impact_point: Vector2) -> void:
	take_damage(amount)
	_hull_damage.damage_at(amount, impact_point)


## Fired by HardpointPhaseLance — a piercing hit along a line rather than one
## hex plus splash. Overall Health only takes the hit once, same as a normal shot.
func take_beam_damage(amount: float, entry_point: Vector2, aim_direction: Vector2, max_travel_distance: float) -> void:
	take_damage(amount)
	_hull_damage.damage_beam(amount, entry_point, aim_direction, max_travel_distance)


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


## Boosted thrust costs proportionally more, same multiplier as the extra
## speed/force it grants.
func _try_spend_thrust_energy(delta: float) -> bool:
	var boosting: bool = _boost_active and _thrust_input > 0.0
	var cost: float = thrust_energy_cost * absf(_thrust_input) * (boost_multiplier if boosting else 1.0) * delta
	return spend_energy(cost)


# --- Hardpoints --------------------------------------------------------------

func fire_primary() -> void:
	_hardpoints.fire_primary()


func fire_secondary() -> void:
	_hardpoints.fire_secondary()


func fire_winch() -> void:
	_hardpoints.fire_winch()


func set_winch_reel_input(is_held: bool) -> void:
	_hardpoints.set_winch_reel_input(is_held)


## Toggled by the toggle_grinder input action ("G" — see ship_input.gd). Every
## mounted, intact HardpointGrinder pulls this flag each physics frame (same
## pull-model as is_module_destroyed) rather than being pushed a one-shot
## command, so a grinder that mounts/repairs mid-toggle picks up the current
## state immediately instead of needing a fresh key press.
func toggle_grinder() -> void:
	_grinder_active = not _grinder_active


func is_grinder_active() -> bool:
	return _grinder_active


## Toggled by the scan input action (see ship_input.gd) — starts scanning the
## nearest valid target if idle, cancels an in-progress scan otherwise.
func toggle_scan() -> void:
	_scanner.toggle_scan()


func get_scanner() -> Scanner:
	return _scanner


## Radar is a pure capability flag (see ModuleCatalog.RADAR_HARDPOINT_TYPE_ID)
## rather than a spawned hardpoint node — it has no fixed facing or world-space
## visual of its own, it just gates whether RadarDisplay (the HUD) runs at all.
## True if the layout has at least one radar hardpoint that isn't currently
## destroyed/detached.
func has_radar() -> bool:
	if ship_layout == null:
		return false
	return _has_live_placement(ship_layout.get_radar_hardpoint_placements())


## Same "pure capability flag" shape as has_radar() — see
## ModuleCatalog.SCANNER_HARDPOINT_TYPE_ID.
func has_scanner() -> bool:
	if ship_layout == null:
		return false
	return _has_live_placement(ship_layout.get_scanner_hardpoint_placements())


func _has_live_placement(placements: Array[ModulePlacement]) -> bool:
	for placement in placements:
		if not is_module_destroyed(placement.placement_id):
			return true
	return false


# --- Aim and targeting -------------------------------------------------------

func set_aim_target(target: Vector2) -> void:
	_aim_target = target
	_has_aim_target = true


func get_aim_target() -> Vector2:
	return _aim_target if _has_aim_target else global_position + transform.x * 1000.0


## The object homing missiles should steer toward: manually toggled by the
## player's lock-on (see ship_input.gd) or automatically set to whatever an
## AI ship is currently pursuing (see ship_ai.gd). Null means "no lock" —
## HardpointMissileLauncher then fires unguided, straight-outward missiles.
func set_locked_target(target: Node2D) -> void:
	_locked_target = target


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


## Called by WinchBeam/HardpointTractorBeam once it finishes reeling in a
## CapturedTechPart. A non-empty manufacturer_id also discovers that
## manufacturer (see Inventory.discover_manufacturer) — separate from the
## per-module research unlock, since knowing "Atlas Heavy exists" is a
## different fact from "I can build a Weapon Hardpoint I."
func capture_tech_part(module_type_id: String, manufacturer_id: String = "") -> void:
	_inventory.add_captured_tech(module_type_id)
	if not manufacturer_id.is_empty():
		_inventory.discover_manufacturer(manufacturer_id)


# --- Flight ------------------------------------------------------------------

func set_thrust_input(thrust: float) -> void:
	_thrust_input = clampf(thrust, -1.0, 1.0)


func set_turn_input(turn: float) -> void:
	_turn_input = clampf(turn, -1.0, 1.0)


func set_boost_input(boosting: bool) -> void:
	_boost_active = boosting


## Guarded against a zero/negative mass (a layout whose modules all report no
## mass_contribution, or one stripped by negative manufacturer/upgrade
## deltas) — dividing by it produced INF velocity and threw the ship out of
## the region.
func apply_impulse(impulse: Vector2) -> void:
	if mass <= 0.0:
		return
	velocity += impulse / mass


func _physics_process(delta: float) -> void:
	_energy.regenerate(delta)
	_hull_damage.process(delta)
	rotation += _turn_input * rotation_speed * delta

	if _thrust_input != 0.0 and _try_spend_thrust_energy(delta):
		var thrust: float = thrust_force if _thrust_input > 0.0 else reverse_thrust_force
		var current_max_speed: float = max_speed
		if _boost_active and _thrust_input > 0.0:
			thrust *= boost_multiplier
			current_max_speed *= boost_multiplier
		var acceleration: float = thrust / mass
		velocity += transform.x * _thrust_input * acceleration * delta

		if _thrust_input > 0.0:
			velocity = velocity.limit_length(current_max_speed)
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


func _spawn_thrusters() -> void:
	for thruster in _thrusters:
		thruster.queue_free()
	_thrusters.clear()
	_thruster_placement_ids.clear()
	_thruster_particles_boost.clear()
	_thruster_particles_boost_soft.clear()
	_thruster_particles_normal.clear()

	for placement in ship_layout.get_thruster_placements():
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
		var hex_center: Vector2 = HexUtils.axial_to_pixel(placement.hex_coord, _hull_renderer.cell_size)
		var back_vertex_offset: Vector2 = Vector2(0.0, _hull_renderer.cell_size)
		thruster.position = (hex_center + back_vertex_offset).rotated(_hull_renderer.rotation)
		_thrusters.append(thruster)
		_thruster_placement_ids.append(placement.placement_id)
		_thruster_particles_boost.append(thruster.get_node("Particles"))
		_thruster_particles_boost_soft.append(thruster.get_node("ParticlesSoft"))
		_thruster_particles_normal.append(thruster.get_node("ParticlesNormal"))


func _update_engine_particles() -> void:
	var thrusting_forward: bool = _thrust_input > 0.0
	var boosting: bool = thrusting_forward and _boost_active

	for i in _thrusters.size():
		# A destroyed/detached engine shouldn't keep showing its own flame,
		# even while other engines (or leftover momentum) keep the ship
		# actually moving forward.
		var alive: bool = not is_module_destroyed(_thruster_placement_ids[i])

		var particles: GPUParticles2D = _thruster_particles_boost[i]
		particles.emitting = boosting and alive
		particles.amount_ratio = 1.0

		var particles_soft: GPUParticles2D = _thruster_particles_boost_soft[i]
		particles_soft.emitting = boosting and alive
		particles_soft.amount_ratio = 1.0

		_thruster_particles_normal[i].emitting = thrusting_forward and not boosting and alive


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
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	explosion.effect_scale = destruction_explosion_scale

	if drops_salvage:
		var drop_count: int = randi_range(salvage_drop_count_min, salvage_drop_count_max)
		for i in drop_count:
			_spawn_kill_drop()

	queue_free()


func _spawn_kill_drop() -> void:
	var salvage: Salvage = salvage_scene.instantiate()
	var rolled_rarity: Salvage.Rarity = _roll_salvage_rarity()
	salvage.rarity = rolled_rarity
	if randf() < component_drop_chance:
		salvage.kind = Salvage.Kind.COMPONENT
		salvage.component_id = _roll_combat_component()
	else:
		salvage.material_id = _roll_combat_material()
	salvage.is_dangerous = randf() < _danger_chance_for_rarity(rolled_rarity)
	get_tree().current_scene.add_child(salvage)
	# Small scatter so multiple drops from one kill don't spawn stacked exactly
	# on top of each other.
	salvage.global_position = global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))


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
	var roll: float = randf()
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
	return MaterialCatalog.ALL_IDS[randi_range(0, MaterialCatalog.ALL_IDS.size() - 1)]


## See component_drop_chance/rare_component_chance — picks which component a
## kill-drop that already rolled COMPONENT actually carries.
func _roll_combat_component() -> String:
	var pool: Array[String] = ComponentCatalog.RARE_IDS if randf() < rare_component_chance else ComponentCatalog.COMMON_IDS
	return pool[randi_range(0, pool.size() - 1)]

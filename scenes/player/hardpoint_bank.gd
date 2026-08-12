class_name HardpointBank
extends Node2D

## Every hardpoint node mounted on a ship, plus the code that spawns them from
## the ship's ShipLayout and the fire/aim commands that fan out across them.
##
## Split out of ship.gd, which held five parallel typed arrays, five
## near-identical spawn functions (each repeating the same
## instantiate/add_child/position/setup/source_placement_id/append block), and
## two linear searches — _find_hardpoint_node_for and
## _set_hardpoint_visual_visible — that walked four of those arrays in turn.
##
## Mounted nodes are this node's own children. This node sits at the ship's
## origin with an identity transform, so a hardpoint's local position and
## rotation mean exactly what they did when Ship parented them directly.
##
## Lookups go through _by_placement (placement_id -> node), so applying an
## upgrade to one placement and hiding a destroyed module's turret are both
## O(1) rather than a scan across every mounted hardpoint.

@export var gun_scene: PackedScene = preload("res://scenes/player/hardpoint_gun.tscn")
@export var missile_launcher_scene: PackedScene = preload("res://scenes/player/hardpoint_missile_launcher.tscn")
@export var winch_scene: PackedScene = preload("res://scenes/player/hardpoint_winch.tscn")
@export var tractor_beam_scene: PackedScene = preload("res://scenes/player/hardpoint_tractor_beam.tscn")
@export var slicer_scene: PackedScene = preload("res://scenes/player/hardpoint_slicer.tscn")

var _ship: Ship
var _layout: ShipLayout
var _renderer: ShipLayoutRenderer

## Kind-specific lists, kept alongside _by_placement because firing and aiming
## address one kind at a time and each kind has its own typed API.
var _guns: Array[HardpointGun] = []
var _launchers: Array[HardpointMissileLauncher] = []
var _winches: Array[HardpointWinch] = []

## Guns take turns rather than all firing on the same frame. _next_gun_index is
## whose turn it is; _salvo_gate is the wait until the next gun in the rotation
## may shoot. See fire_primary.
var _next_gun_index: int = 0
var _salvo_gate: float = 0.0

## The gate is set to this fraction of the ideal spacing between shots, so the
## guns' own cooldowns stay the only thing deciding rate of fire. At a full 1.0
## the two limits are exactly equal and frame quantisation makes the gate win by
## a hair on every shot: measured at a 0.30s cycle against the guns' own 0.267s,
## an 11% loss of damage output, which is not a trade this feature is allowed to
## make. The slack costs nothing — the gate still lets only one gun through per
## frame, which is the part that matters.
const SALVO_GATE_SLACK: float = 0.9

## placement_id -> mounted node, across every kind.
var _by_placement: Dictionary = {}
## Every mounted node, for teardown on the next rebuild.
var _mounted: Array[Node2D] = []


## Replaces every mounted hardpoint from the given layout. Called on each
## layout apply (ship builder, warp restore, initial spawn).
func rebuild(ship: Ship, layout: ShipLayout, renderer: ShipLayoutRenderer) -> void:
	_ship = ship
	_layout = layout
	_renderer = renderer

	for node in _mounted:
		node.queue_free()
	_mounted.clear()
	_by_placement.clear()
	_guns.clear()
	_launchers.clear()
	_winches.clear()
	_next_gun_index = 0
	_salvo_gate = 0.0

	for placement in layout.get_weapon_hardpoint_placements():
		_guns.append(_mount_gun(placement))
	for placement in layout.get_missile_hardpoint_placements():
		_launchers.append(_mount_launcher(placement))
	for placement in layout.get_winch_hardpoint_placements():
		_winches.append(_mount_winch(placement))
	for placement in layout.get_tractor_hardpoint_placements():
		_mount_tractor_beam(placement)
	for placement in layout.get_salvager_hardpoint_placements():
		_mount_slicer(placement)


## The live spawned node for placement_id, across every hardpoint kind. Null for
## a placement with no live node — a non-hardpoint module type (Engine,
## Reactor), or Radar/Scanner, which are pure capability flags (see
## Ship.has_radar/has_scanner) with no world-space node at all.
func get_node_for(placement_id: String) -> Node:
	return _by_placement.get(placement_id)


## A destroyed/detached module's hex goes dark, but its hardpoint is a separate
## node positioned on top of that hex — without this it kept floating there
## fully visible (turret and all) over a scorched or already-departed hole.
## Repairing the module reverses it. No-op for a placement with no mounted node.
func set_visual_visible(placement_id: String, should_be_visible: bool) -> void:
	var node: Node2D = _by_placement.get(placement_id)
	if node != null:
		node.visible = should_be_visible


func _process(delta: float) -> void:
	_salvo_gate = maxf(_salvo_gate - delta, 0.0)


## Fires at most one gun per call, cycling through them in turn, so a ship with
## four cannons ripples rather than discharging all four on the same frame.
##
## Deliberately does not change anyone's rate of fire: each gun keeps its own
## cooldown, and the gate between shots is that cooldown divided by the number
## of live guns, so the rotation comes back around to each gun exactly when it
## was going to be ready anyway. Four guns still put out four times one gun's
## damage — they just spread it evenly across the interval instead of stacking
## it into one spike and then a long silence.
##
## The gate (rather than seeding each gun with a phase offset) is what makes
## this hold from a standing start: guns left idle all sit at zero cooldown, so
## offsets decay to nothing and the first volley after any pause would go off in
## lockstep again.
func fire_primary() -> void:
	if _salvo_gate > 0.0 or _guns.is_empty():
		return
	for offset in _guns.size():
		var index: int = (_next_gun_index + offset) % _guns.size()
		var gun: HardpointGun = _guns[index]
		if _ship.is_module_destroyed(gun.source_placement_id) or not gun.is_ready_to_fire():
			continue
		gun.fire()
		_next_gun_index = (index + 1) % _guns.size()
		_salvo_gate = SALVO_GATE_SLACK / maxf(gun.fire_rate * _live_gun_count(), 0.001)
		return


## Guns whose module is still intact. Destroyed guns are excluded so losing one
## tightens the remaining guns' rotation back up instead of leaving a silent
## gap where it used to fire.
func _live_gun_count() -> int:
	var count: int = 0
	for gun in _guns:
		if not _ship.is_module_destroyed(gun.source_placement_id):
			count += 1
	return maxi(count, 1)


func fire_secondary() -> void:
	for launcher in _launchers:
		if not _ship.is_module_destroyed(launcher.source_placement_id):
			launcher.fire()


## Called on fire_winch's just-pressed edge (see ship_input.gd) — starts a cast
## on every mounted, still-intact winch hardpoint (usually just one).
func fire_winch() -> void:
	for winch in _winches:
		if not _ship.is_module_destroyed(winch.source_placement_id):
			winch.fire()


## Called every physics frame with fire_winch's current held state — only has an
## effect on a winch that's already ATTACHED to a part (see
## HardpointWinch.set_reel_input).
func set_winch_reel_input(is_held: bool) -> void:
	for winch in _winches:
		if not _ship.is_module_destroyed(winch.source_placement_id):
			winch.set_reel_input(is_held)


## Guns and launchers track a world-space aim point; every other kind has either
## a fixed facing or no facing at all, so nothing else is touched here.
func update_aim(aim_target: Vector2) -> void:
	for gun in _guns:
		gun.aim_at(aim_target)
	for launcher in _launchers:
		launcher.aim_at(aim_target)


func has_aimable_hardpoints() -> bool:
	return not _guns.is_empty() or not _launchers.is_empty()


## Shared mount step for every kind: instance, parent, place on the hex, and
## register. Kind-specific configuration (tier, facing, modifiers) happens in
## each _mount_* below, before setup() hands the node its shooter.
func _mount(scene: PackedScene, placement: ModulePlacement) -> Node2D:
	var node: Node2D = scene.instantiate()
	add_child(node)
	node.position = _hardpoint_center(placement)
	node.source_placement_id = placement.placement_id
	_by_placement[placement.placement_id] = node
	_mounted.append(node)
	return node


func _mount_gun(placement: ModulePlacement) -> HardpointGun:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	# A weapon module type may carry its own hardpoint scene (Railgun, Phase
	# Lance); everything else falls back to the plain gun.
	var scene: PackedScene = module_type.hardpoint_scene if module_type.hardpoint_scene != null else gun_scene
	var gun: HardpointGun = _mount(scene, placement)
	gun.set_cell_size(_renderer.cell_size, HardpointGun.tier_visual_scale(module_type.tier))
	# The turret art follows the part, not the hull. A pirate gun bolted onto a
	# corporate ship kept drawing the corporate turret while its own base plate
	# was already tinted pirate, so the two halves of one module disagreed about
	# where it came from. Tinted to match the plate for the same reason.
	var art_faction: String = HullPaint.art_faction_for(placement.instance, _ship.personality.faction_id)
	var overlay: Texture2D = module_type.get_hex_overlay_texture(art_faction)
	if overlay == null:
		overlay = module_type.get_hex_overlay_texture(_ship.personality.faction_id)
	gun.set_turret_texture(overlay, HullPaint.part_tint(placement, _ship.personality.faction_id))
	# Not every weapon hardpoint is a plain gun (Railgun, Phase Lance carry their
	# own scenes), so this is asked for rather than assumed.
	if gun.has_method("set_laser_color"):
		var hull_faction: String = _ship.personality.faction_id
		gun.set_laser_color(
			LaserPalette.base_color(placement.instance, hull_faction),
			LaserPalette.bolt_color(placement.instance, hull_faction),
			LaserPalette.halo_color(placement.instance, hull_faction))
	gun.apply_tier(module_type.tier)
	gun.apply_core_distance_bonus(_layout.distance_from_core(placement))
	gun.setup(_ship)
	_apply_manufacturer_modifiers(gun, placement)
	return gun


func _mount_launcher(placement: ModulePlacement) -> HardpointMissileLauncher:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	var launcher: HardpointMissileLauncher = _mount(missile_launcher_scene, placement)
	launcher.set_cell_size(_renderer.cell_size, HardpointGun.tier_visual_scale(module_type.tier))
	launcher.apply_tier(module_type.tier)
	launcher.apply_core_distance_bonus(_layout.distance_from_core(placement))
	launcher.setup(_ship)
	_apply_manufacturer_modifiers(launcher, placement)
	return launcher


## Unlike guns/launchers, a winch hardpoint has a fixed facing rather than
## tracking the mouse — set once here from the placement's own rotation_steps
## (the same per-hex facing the ship builder's R hotkey edits), plus the hull's
## fixed rendering offset, so "the direction the room is facing" is whatever the
## player pointed it at in the builder.
func _mount_winch(placement: ModulePlacement) -> HardpointWinch:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	var winch: HardpointWinch = _mount(winch_scene, placement)
	winch.rotation = _fixed_facing(placement)
	# Only overridden when the module type actually says where its aperture is.
	# Every Grapple mark does; a module that doesn't keeps the scene's own muzzle
	# placement rather than collapsing it onto the footprint centre.
	if module_type.muzzle_offset_cells != Vector2.ZERO:
		winch.set_muzzle_offset(module_type.muzzle_offset_cells * _renderer.cell_size)
	winch.setup(_ship)
	return winch


## Tractor beams aim nowhere in particular (the beam always targets whatever it
## finds, see HardpointTractorBeam) — mounted at the hex center only, no facing.
func _mount_tractor_beam(placement: ModulePlacement) -> HardpointTractorBeam:
	var tractor_beam: HardpointTractorBeam = _mount(tractor_beam_scene, placement)
	tractor_beam.setup(_ship)
	return tractor_beam


## Same fixed-facing convention as _mount_winch — the muzzle the beam leaves
## from (see HardpointSlicer) is a specific direction out of the anchor cell.
func _mount_slicer(placement: ModulePlacement) -> HardpointSlicer:
	var slicer: HardpointSlicer = _mount(slicer_scene, placement)
	slicer.rotation = _fixed_facing(placement)
	slicer.set_cell_size(_renderer.cell_size)
	slicer.setup(_ship)
	return slicer


func _fixed_facing(placement: ModulePlacement) -> float:
	return float(placement.rotation_steps) * (PI / 3.0) + _renderer.rotation


## Centroid of a hardpoint's occupied cells, so multi-hex (tier 2/3) hardpoints
## mount their gun/launcher in the middle of their footprint rather than at the
## anchor cell's corner.
func _hardpoint_center(placement: ModulePlacement) -> Vector2:
	var occupied_cells: Array[Vector2i] = _layout.get_occupied_cells(placement)
	var center_local: Vector2 = Vector2.ZERO
	for cell in occupied_cells:
		center_local += HexUtils.axial_to_pixel(cell, _renderer.cell_size)
	center_local /= occupied_cells.size()
	return center_local.rotated(_renderer.rotation)


## Applies a placement's manufacturer stat_modifiers (additive deltas, same
## technique as the upgrade-tree modifiers below) to its spawned hardpoint node.
## Also passes through Black Market Foundry's malfunction risk, if any — see
## HardpointGun._apply_malfunction_damage.
func _apply_manufacturer_modifiers(node: Node, placement: ModulePlacement) -> void:
	var manufacturer: Manufacturer = ManufacturerCatalog.get_by_id(placement.manufacturer_id)
	if manufacturer == null:
		return
	apply_modifiers(node, manufacturer.stat_modifiers)
	if "malfunction_chance" in node:
		node.set("malfunction_chance", manufacturer.malfunction_chance)
		node.set("malfunction_self_damage", manufacturer.malfunction_self_damage)


## Additive stat deltas onto a hardpoint node, skipping any property the node
## doesn't have. Public so a system that changes one stat on an already-spawned
## hardpoint can push it through here rather than rebuilding the hardpoint —
## which is the hook the ship-wide upgrades (ShipUpgradeService) will need once
## their effects are authored.
## Static so the ship builder's part card can quote a weapon's real numbers by
## applying the same rule to a throwaway probe, instead of keeping a second copy
## of it that would drift (see BuilderPartCard._probe_hardpoint).
static func apply_modifiers(node: Node, modifiers: Dictionary) -> void:
	for property_name in modifiers:
		if property_name in node:
			node.set(property_name, node.get(property_name) + modifiers[property_name])

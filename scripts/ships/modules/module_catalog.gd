class_name ModuleCatalog
extends RefCounted

## Prototype-only stand-in for loading ModuleType resources from
## res://resources/modules/. Do not let wider systems assume a
## hard-coded catalog once real module content grows.

const CORE_TYPE_ID: String = "command_core"
const WEAPON_HARDPOINT_TYPE_ID: String = "weapon_hardpoint"
const MISSILE_HARDPOINT_TYPE_ID: String = "missile_hardpoint"
const RAILGUN_HARDPOINT_TYPE_ID: String = "railgun_hardpoint"
const PHASE_LANCE_HARDPOINT_TYPE_ID: String = "phase_lance_hardpoint"
const WINCH_HARDPOINT_TYPE_ID: String = "winch_hardpoint"
const TRACTOR_HARDPOINT_TYPE_ID: String = "tractor_beam_hardpoint"
const RADAR_HARDPOINT_TYPE_ID: String = "radar_hardpoint"
const SCANNER_HARDPOINT_TYPE_ID: String = "scanner_hardpoint"
const GRINDER_HARDPOINT_TYPE_ID: String = "mining_grinder_hardpoint"

const SINGLE_CELL: Array[Vector2i] = [Vector2i.ZERO]
const LINE_2_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const LINE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
## Three mutually-adjacent hexes forming a compact triangle, rather than a
## straight line, for a bulkier-looking tier-3 mount.
const TRIANGLE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]

const HULL_TEXTURE: Texture2D = preload("res://art/ships/hull_v1.png")
const MISSILE_HARDPOINT_TEXTURE: Texture2D = preload("res://art/ships/missile_silo_v1.png")
const COCKPIT_TEXTURE: Texture2D = preload("res://art/ships/cockpit_v1.png")


## Built once and reused — get_by_id() (called for every hex on every
## placement lookup, including every AI ship's per-frame get_layout_extent())
## used to rebuild this whole ~14-entry catalog from scratch on every single
## call, which was a real per-frame cost that scaled with how many ships
## were active in combat. Safe to cache: nothing in the codebase mutates a
## ModuleType's fields after fetching it, so every caller sharing the same
## instances is fine — this is still a read-only prototype catalog, only
## built lazily now instead of eagerly every call.
static var _cached_types: Array[ModuleType] = []


static func get_all() -> Array[ModuleType]:
	if not _cached_types.is_empty():
		return _cached_types

	var types: Array[ModuleType] = []
	# Losing the Core ends the ship outright (see Ship._on_module_destroyed),
	# so it needs to be the best-armored single point on the whole hull rather
	# than one of the flimsiest — a heavy weapon shouldn't be able to end a
	# fight in one lucky hit to the cockpit.
	var core_type: ModuleType = _make(CORE_TYPE_ID, "Command Core", Color(0.9, 0.85, 0.2), SINGLE_CELL, 0.4, 140.0, 0.0, COCKPIT_TEXTURE,
		"", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 20})
	core_type.faction_hex_textures = FactionArtImporter.load_faction_textures("command_core")
	types.append(core_type)

	# Fragile enough to be crackable within a normal engagement (with splash
	# from nearby hits, see Ship.module_splash_fraction), but not so fragile
	# that whatever's behind sturdier armor is exposed within a few seconds
	# of sustained close-range fire.
	var hull_type: ModuleType = _make("hull", "Hull", Color(0.5, 0.55, 0.6), SINGLE_CELL, 0.3, 50.0, 0.0, HULL_TEXTURE,
		"", 1, {Materials.STEEL_ALLOY: 5})
	hull_type.faction_hex_textures = FactionArtImporter.load_faction_textures("hull_mk1")
	types.append(hull_type)

	var engine_type: ModuleType = _make("engine", "Engine", Color(0.3, 0.7, 1.0), SINGLE_CELL, 0.25, 20.0, 500.0, null,
		"", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 5})
	engine_type.faction_hex_textures = FactionArtImporter.load_faction_textures("engine_mk1")
	engine_type.is_capturable_tech = true
	types.append(engine_type)

	# Meant to actually function as a wall: tough enough that sustained
	# close-range fire can't punch through to whatever it's shielding within
	# a few seconds, even from several guns at once.
	var heavy_hull_type: ModuleType = _make("heavy_hull", "Heavy Hull", Color(0.45, 0.3, 0.55), LINE_3_CELLS, 0.9, 240.0, 0.0, null,
		"", 1, {Materials.STEEL_ALLOY: 20})
	heavy_hull_type.faction_hex_textures = FactionArtImporter.load_faction_textures("armour_module")
	types.append(heavy_hull_type)

	# Deliberately cheaper, lighter and far more fragile than Hull: a strut's
	# only job is connecting a wing/appendage back to the core, so a snapped-off
	# wing costs little to have risked and rebuilt, unlike investing in Hull.
	# Ancient has no strut art yet — falls back to a flat tinted hex for that
	# faction only (see ShipLayoutRenderer/HexGridControl).
	var strut_type: ModuleType = _make("strut", "Strut", Color(0.55, 0.58, 0.5), SINGLE_CELL, 0.15, 25.0, 0.0, null,
		"", 1, {Materials.STEEL_ALLOY: 3})
	strut_type.faction_hex_textures = FactionArtImporter.load_faction_textures("strut")
	types.append(strut_type)

	# Every weapon-hardpoint tier's base plate is exported as one image PER
	# HEX it occupies — "laser_cannon_mk1_0_0" for the single-hex tier I,
	# "laser_cannon_mk2_0_0"/"_1_0" for tier II (LINE_2_CELLS' two offsets),
	# "laser_cannon_mk3_0_0"/"_1_0"/"_0_1" for tier III (TRIANGLE_3_CELLS'
	# three offsets) — rather than one image stretched across the whole
	# footprint, which left most of a multi-hex footprint showing flat
	# background margin with the actual art shrunk into one corner (see
	# ShipLayoutRenderer history). Each piece is loaded per-cell and matched
	# up via ModuleType.faction_hex_textures_per_cell. Factions missing
	# pieces for a tier fall back to hex_texture/no texture for that cell
	# until matching art is added.
	# Tier turret overlays ("turret_360"/"_mk2"/"_mk3") stay single images —
	# see ModuleType.faction_hex_overlay_textures and HardpointGun's rotating
	# turret sprite, which draws them as one centered icon, not per-cell.
	#
	# Also load the old unsuffixed single-image name for each tier as a
	# fallback (faction_hex_textures, via get_hex_texture_for_cell's built-in
	# fallback) — factions that haven't re-exported a tier with the new
	# per-cell pieces yet (Ancient/Pirates only have "laser_cannon_mk1.png"
	# so far) keep showing their existing art instead of going blank.
	var laser_t1_per_cell: Array[Dictionary] = FactionArtImporter.load_faction_textures_per_cell("laser_cannon_mk1", SINGLE_CELL)
	var laser_t2_per_cell: Array[Dictionary] = FactionArtImporter.load_faction_textures_per_cell("laser_cannon_mk2", LINE_2_CELLS)
	var laser_t3_per_cell: Array[Dictionary] = FactionArtImporter.load_faction_textures_per_cell("laser_cannon_mk3", TRIANGLE_3_CELLS)
	var laser_t1_fallback: Dictionary = FactionArtImporter.load_faction_textures("laser_cannon_mk1")
	var laser_t2_fallback: Dictionary = FactionArtImporter.load_faction_textures("laser_cannon_mk2")
	var laser_t3_fallback: Dictionary = FactionArtImporter.load_faction_textures("laser_cannon_mk3")
	var turret_t1_textures: Dictionary = FactionArtImporter.load_faction_textures("turret_360")
	var turret_t2_textures: Dictionary = FactionArtImporter.load_faction_textures("turret_360_mk2")
	var turret_t3_textures: Dictionary = FactionArtImporter.load_faction_textures("turret_360_mk3")

	var weapon_t1: ModuleType = _make(WEAPON_HARDPOINT_TYPE_ID, "Weapon Hardpoint I", Color(0.9, 0.35, 0.3), SINGLE_CELL,
		0.2, 15.0, 0.0, null, "weapon", 1, {Materials.STEEL_ALLOY: 8, Materials.ELECTRONICS: 4})
	weapon_t1.faction_hex_textures = laser_t1_fallback
	weapon_t1.faction_hex_textures_per_cell = laser_t1_per_cell
	weapon_t1.faction_hex_overlay_textures = turret_t1_textures
	weapon_t1.is_capturable_tech = true
	types.append(weapon_t1)
	var weapon_t2: ModuleType = _make("weapon_hardpoint_t2", "Weapon Hardpoint II", Color(0.8, 0.25, 0.2), LINE_2_CELLS,
		0.5, 35.0, 0.0, null, "weapon", 2, {Materials.STEEL_ALLOY: 18, Materials.ELECTRONICS: 10})
	weapon_t2.faction_hex_textures = laser_t2_fallback
	weapon_t2.faction_hex_textures_per_cell = laser_t2_per_cell
	weapon_t2.faction_hex_overlay_textures = turret_t2_textures
	weapon_t2.is_capturable_tech = true
	types.append(weapon_t2)
	var weapon_t3: ModuleType = _make("weapon_hardpoint_t3", "Weapon Hardpoint III", Color(0.65, 0.15, 0.1), TRIANGLE_3_CELLS,
		0.9, 60.0, 0.0, null, "weapon", 3,
		{Materials.STEEL_ALLOY: 32, Materials.ELECTRONICS: 20, Materials.REACTOR_COMPONENTS: 5})
	weapon_t3.faction_hex_textures = laser_t3_fallback
	weapon_t3.faction_hex_textures_per_cell = laser_t3_per_cell
	weapon_t3.faction_hex_overlay_textures = turret_t3_textures
	weapon_t3.is_capturable_tech = true
	types.append(weapon_t3)

	# Same reuse-across-tiers reasoning as the laser cannon above.
	var missile_textures: Dictionary = FactionArtImporter.load_faction_textures("missile_launcher_mk1")
	var missile_t1: ModuleType = _make(MISSILE_HARDPOINT_TYPE_ID, "Missile Rack I", Color(1.0, 0.6, 0.15), SINGLE_CELL,
		0.3, 20.0, 0.0, MISSILE_HARDPOINT_TEXTURE, "missile", 1, {Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 8})
	missile_t1.faction_hex_textures = missile_textures
	missile_t1.is_capturable_tech = true
	types.append(missile_t1)
	var missile_t2: ModuleType = _make("missile_hardpoint_t2", "Missile Rack II", Color(0.9, 0.5, 0.1), LINE_2_CELLS,
		0.7, 45.0, 0.0, null, "missile", 2, {Materials.STEEL_ALLOY: 22, Materials.ELECTRONICS: 16})
	missile_t2.faction_hex_textures = missile_textures
	missile_t2.is_capturable_tech = true
	types.append(missile_t2)
	var missile_t3: ModuleType = _make("missile_hardpoint_t3", "Missile Rack III", Color(0.75, 0.4, 0.05), LINE_3_CELLS,
		1.2, 75.0, 0.0, null, "missile", 3,
		{Materials.STEEL_ALLOY: 38, Materials.ELECTRONICS: 26, Materials.REACTOR_COMPONENTS: 10})
	missile_t3.faction_hex_textures = missile_textures
	missile_t3.is_capturable_tech = true
	types.append(missile_t3)

	var reactor_type: ModuleType = _make("reactor_mk1", "Reactor Mk1", Color(1.0, 0.75, 0.2), SINGLE_CELL,
		0.35, 25.0, 0.0, null, "", 1,
		{Materials.STEEL_ALLOY: 15, Materials.ELECTRONICS: 15, Materials.REACTOR_COMPONENTS: 10},
		15.0, 0.0)
	reactor_type.faction_hex_textures = FactionArtImporter.load_faction_textures("reactor_mk1")
	reactor_type.is_capturable_tech = true
	types.append(reactor_type)

	var battery_type: ModuleType = _make("battery_mk1", "Battery Mk1", Color(0.85, 0.75, 0.95), SINGLE_CELL,
		0.3, 20.0, 0.0, null, "", 1,
		{Materials.STEEL_ALLOY: 10, Materials.ELECTRONICS: 20},
		0.0, 80.0)
	battery_type.faction_hex_textures = FactionArtImporter.load_faction_textures("battery_mk1")
	battery_type.is_capturable_tech = true
	types.append(battery_type)

	# Cargo storage (see ShipLayout.total_cargo_capacity/Ship._apply_layout_
	# cargo_capacity). A plain stat contributor like Reactor/Battery, not a
	# hardpoint category — storage has no facing/muzzle/HUD gate of its own,
	# it just raises the cap Inventory.try_add_material() checks. No
	# dedicated art yet — a generic flat-tinted hex, same approach as Strut.
	# Brown/tan to stay distinct from every other module's color.
	var storage_type: ModuleType = _make("storage_mk1", "Cargo Container", Color(0.6, 0.45, 0.3), SINGLE_CELL,
		0.4, 30.0, 0.0, null, "", 1,
		{Materials.STEEL_ALLOY: 8},
		0.0, 0.0, null, false, 0.5, 0.35, 60.0)
	types.append(storage_type)

	# Corporate Alliance: standardised, industrial kinetic weapon. Tougher
	# than a laser hardpoint of similar footprint since it's built to
	# withstand its own recoil (see HardpointRailgun).
	var railgun_type: ModuleType = _make(RAILGUN_HARDPOINT_TYPE_ID, "Railgun", Color(0.8, 0.85, 0.92), LINE_2_CELLS,
		0.7, 40.0, 0.0, null, "weapon", 1,
		{Materials.STEEL_ALLOY: 25, Materials.ELECTRONICS: 10, Materials.REACTOR_COMPONENTS: 8},
		0.0, 0.0, preload("res://scenes/player/hardpoint_railgun.tscn"))
	railgun_type.is_capturable_tech = true
	railgun_type.requires_research = true
	types.append(railgun_type)

	# Ancient Civilisation: alien energy weapon. Lighter and more fragile
	# than the industrial Railgun — it's exotic technology, not armor plate.
	var phase_lance_type: ModuleType = _make(PHASE_LANCE_HARDPOINT_TYPE_ID, "Phase Lance", Color(0.35, 0.2, 0.45), SINGLE_CELL,
		0.25, 30.0, 0.0, null, "weapon", 1,
		{Materials.ELECTRONICS: 20, Materials.REACTOR_COMPONENTS: 18},
		0.0, 0.0, preload("res://scenes/player/hardpoint_phase_lance.tscn"))
	phase_lance_type.is_capturable_tech = true
	phase_lance_type.requires_research = true
	types.append(phase_lance_type)

	# Tractor beam hardpoint (see HardpointTractorBeam/Ship._spawn_hardpoint_tractor_beams).
	# No dedicated art yet — a generic flat-tinted hex, same approach as Strut.
	var tractor_type: ModuleType = _make(TRACTOR_HARDPOINT_TYPE_ID, "Tractor Beam", Color(0.4, 0.75, 0.85), SINGLE_CELL,
		0.2, 30.0, 0.0, null, "tractor", 1, {Materials.STEEL_ALLOY: 8, Materials.ELECTRONICS: 8})
	types.append(tractor_type)

	# Radar hardpoint (see RadarDisplay.has_radar/Ship.has_radar) — a pure
	# capability flag, no per-hex spawned node or fixed facing needed (radar
	# is an omnidirectional sensor centered on the ship, not a directional
	# beam like the tractor beam), so unlike most hardpoints above it never
	# gets a hardpoint_scene. No dedicated art yet — a generic flat-tinted
	# hex, same approach as Strut/the tractor beam hardpoint. Green (matching
	# RadarDisplay's own sweep/label color) rather than another blue/teal —
	# distinct at a glance from Engine and the Tractor Beam hardpoint, which
	# sat right next to it in the same blue family.
	var radar_type: ModuleType = _make(RADAR_HARDPOINT_TYPE_ID, "Radar", Color(0.3, 1.0, 0.55), SINGLE_CELL,
		0.2, 25.0, 0.0, null, "radar", 1, {Materials.STEEL_ALLOY: 6, Materials.ELECTRONICS: 10})
	types.append(radar_type)

	# Scanner hardpoint (see Scanner.has_scanner/Ship.has_scanner) — same
	# "pure capability flag" shape as Radar: the pulse originates from the
	# ship's own position, not a per-hex muzzle, so no spawned node or fixed
	# facing is needed. No dedicated art yet — a generic flat-tinted hex.
	var scanner_type: ModuleType = _make(SCANNER_HARDPOINT_TYPE_ID, "Scanner", Color(0.9, 0.35, 0.75), SINGLE_CELL,
		0.2, 25.0, 0.0, null, "scanner", 1, {Materials.STEEL_ALLOY: 6, Materials.ELECTRONICS: 12})
	types.append(scanner_type)

	# Mining Grinder hardpoint (see HardpointGrinder/Ship._spawn_hardpoint_
	# grinders) — a 2-hex line, like Railgun/Weapon Hardpoint II, so it has a
	# distinct anchor (back) cell and front cell; the front cell (offset
	# (1,0), rotated with the placement) is the actual contact/grind point.
	# Toggled on/off by the player (Ship.toggle_grinder, "G") rather than
	# always-on like the Tractor Beam, since it deals continuous damage and
	# should require deliberate activation. No dedicated art yet — a generic
	# flat-tinted hex. Lime-green to stay distinct from every warm-toned
	# module (Weapon/Missile/Reactor/Storage) and from Radar's pure green.
	var grinder_type: ModuleType = _make(GRINDER_HARDPOINT_TYPE_ID, "Mining Grinder", Color(0.65, 0.85, 0.15), LINE_2_CELLS,
		0.5, 30.0, 0.0, null, "grinder", 1,
		{Materials.STEEL_ALLOY: 15, Materials.ELECTRONICS: 6},
		0.0, 0.0, preload("res://scenes/player/hardpoint_grinder.tscn"))
	types.append(grinder_type)

	# Winch hardpoint (casts a physical rope — see HardpointWinch/WinchRope/
	# Ship._spawn_hardpoint_winches) is disabled for now, per explicit user
	# request — a good work-in-progress, not abandoned, just not offered as
	# buildable in the meantime. Left commented rather than deleted: all the
	# supporting code/scenes/input action are still in place to pick back up.
	# types.append(_make(WINCH_HARDPOINT_TYPE_ID, "Winch", Color(0.6, 0.55, 0.4), SINGLE_CELL,
	# 	0.3, 20.0, 0.0, null, "winch", 1,
	# 	{Materials.STEEL_ALLOY: 12, Materials.ELECTRONICS: 6},
	# 	0.0, 0.0, preload("res://scenes/player/hardpoint_winch.tscn")))

	_cached_types = types
	return types


static func get_by_id(id: String) -> ModuleType:
	for type in get_all():
		if type.id == id:
			return type
	return null


static func _make(id: String, display_name: String, color: Color, footprint_cells: Array[Vector2i],
		mass_contribution: float = 0.0, health_contribution: float = 0.0, thrust_contribution: float = 0.0,
		hex_texture: Texture2D = null, hardpoint_category: String = "", tier: int = 1,
		build_costs: Dictionary = {}, energy_generation: float = 0.0,
		energy_capacity_contribution: float = 0.0, hardpoint_scene: PackedScene = null,
		is_capturable_tech: bool = false, capture_health_fraction: float = 0.5,
		capture_chance: float = 0.35, cargo_capacity_contribution: float = 0.0) -> ModuleType:
	var type := ModuleType.new()
	type.id = id
	type.display_name = display_name
	type.color = color
	type.footprint_cells = footprint_cells
	type.mass_contribution = mass_contribution
	type.health_contribution = health_contribution
	type.thrust_contribution = thrust_contribution
	type.hex_texture = hex_texture
	type.hardpoint_category = hardpoint_category
	type.tier = tier
	type.build_costs = build_costs
	type.energy_generation = energy_generation
	type.energy_capacity_contribution = energy_capacity_contribution
	type.hardpoint_scene = hardpoint_scene
	type.is_capturable_tech = is_capturable_tech
	type.capture_health_fraction = capture_health_fraction
	type.capture_chance = capture_chance
	type.cargo_capacity_contribution = cargo_capacity_contribution
	return type

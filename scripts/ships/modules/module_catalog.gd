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
const GRAPPLE_MK1_TYPE_ID: String = "grapple_mk1"
const GRAPPLE_MK2_TYPE_ID: String = "grapple_mk2"
const GRAPPLE_MK3_TYPE_ID: String = "grapple_mk3"
const TRACTOR_HARDPOINT_TYPE_ID: String = "tractor_beam_hardpoint"
const RADAR_HARDPOINT_TYPE_ID: String = "radar_hardpoint"
const SCANNER_HARDPOINT_TYPE_ID: String = "scanner_hardpoint"
const SALVAGER_HARDPOINT_TYPE_ID: String = "salvager_hardpoint"

const SINGLE_CELL: Array[Vector2i] = [Vector2i.ZERO]
const LINE_2_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const LINE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
## Three mutually-adjacent hexes forming a compact triangle, rather than a
## straight line, for a bulkier-looking tier-3 mount.
const TRIANGLE_3_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]

# --- The bundled build set ---------------------------------------------------
# The only types the ship builder offers (see ShipBuilderPanel.BUILDABLE_TYPE_IDS
# and _rebuild_module_list). A ship is assembled from a handful of named, chunky
# parts rather than placed a hex at a time: nothing here is a single hex except
# the Command Core, and every one of them can be cut off a wreck and bolted
# straight onto your own hull.
#
# The older single-hex types below are deliberately still in this catalog. They
# are what the enemy layouts and any part already in a player's hold reference by
# id, and deleting them would break every one of those. They simply are not
# offered for building any more.
const CONDUIT_TYPE_ID: String = "conduit"
const HULL_SPAR_TYPE_ID: String = "hull_spar"
const HULL_WEDGE_TYPE_ID: String = "hull_wedge"
const GUN_MK1_TYPE_ID: String = "gun_mk1"
const REACTOR_PAIR_TYPE_ID: String = "reactor_pair"
const THRUSTER_BLOCK_TYPE_ID: String = "thruster_block"

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
## id -> ModuleType, built alongside _cached_types. get_by_id() used to walk
## the whole array on every call, and it sits under ShipLayout.
## get_occupied_cells()/get_placement_at(), which run per hex per placement on
## every hit resolution and (before ShipLayout's own index) every frame per AI
## ship — a linear scan there was pure waste.
static var _index: Dictionary = {}


static func get_all() -> Array[ModuleType]:
	if not _cached_types.is_empty():
		return _cached_types

	var types: Array[ModuleType] = []
	# Losing the Core ends the ship outright (see Ship._on_module_destroyed),
	# so it needs to be the best-armored single point on the whole hull rather
	# than one of the flimsiest — a heavy weapon shouldn't be able to end a
	# fight in one lucky hit to the cockpit.
	var core_type: ModuleType = _make(CORE_TYPE_ID, "Command Core", Color(0.9, 0.85, 0.2), SINGLE_CELL, 0.4, 140.0, 0.0, COCKPIT_TEXTURE,
		"", 1, {MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 20})
	FactionArtImporter.apply_hex_art(core_type, "command_core")
	types.append(core_type)

	# --- The bundled build set ----------------------------------------------
	# Five parts, none smaller than two hexes. Health and mass are roughly the
	# sum of the single-hex parts each one replaces, so a ship built from these
	# is comparable to the hex-at-a-time ships that came before rather than a
	# straight upgrade.

	# The structural spine: long, light, cheap. Reaches a weapon or a thruster
	# out away from the hull, and is what gets severed when that reach turns out
	# to have been a bad idea.
	var hull_spar: ModuleType = _make(HULL_SPAR_TYPE_ID, "Hull Spar", Color(0.5, 0.55, 0.6), LINE_3_CELLS,
		0.75, 150.0, 0.0, HULL_TEXTURE, "", 1, {MaterialCatalog.IRON: 12},
		0.0, 0.0, null, true)
	FactionArtImporter.apply_hex_art(hull_spar, "hull_mk1")
	types.append(hull_spar)

	# The armour block: compact rather than long, so it actually shields what
	# sits behind it instead of presenting a three-hex-wide face.
	var hull_wedge: ModuleType = _make(HULL_WEDGE_TYPE_ID, "Hull Wedge", Color(0.45, 0.3, 0.55), TRIANGLE_3_CELLS,
		1.0, 220.0, 0.0, null, "", 1, {MaterialCatalog.IRON: 20},
		0.0, 0.0, null, true)
	FactionArtImporter.apply_hex_art(hull_wedge, "armour_module")
	types.append(hull_wedge)

	# Mount hex plus barrel hex. Uses the two-piece laser plate art (see
	# faction_hex_textures_per_cell on the tiered lasers below) with the plain
	# turret overlay — it is a starter gun in a bigger housing, not a tier II
	# weapon.
	var gun_mk1: ModuleType = _make(GUN_MK1_TYPE_ID, "Gun Mk1", Color(0.9, 0.35, 0.3), LINE_2_CELLS,
		0.5, 40.0, 0.0, null, "weapon", 1,
		{MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 6},
		0.0, 0.0, null, true)
	FactionArtImporter.apply_hex_art(gun_mk1, "laser_cannon_mk2", "turret_360")
	types.append(gun_mk1)

	# Carries a little capacity of its own as well as generation, so a ship with
	# no battery still has somewhere to hold a shot's worth of energy.
	var reactor_pair: ModuleType = _make(REACTOR_PAIR_TYPE_ID, "Reactor Pair", Color(1.0, 0.75, 0.2), LINE_2_CELLS,
		0.7, 50.0, 0.0, null, "", 1,
		{MaterialCatalog.IRON: 12, MaterialCatalog.COPPER: 14, MaterialCatalog.NICKEL: 6},
		30.0, 40.0, null, true)
	FactionArtImporter.apply_hex_art(reactor_pair, "reactor_mk1")
	types.append(reactor_pair)

	# The only source of thrust in the build set, so losing one is the
	# difference between manoeuvring and drifting.
	var thruster_block: ModuleType = _make(THRUSTER_BLOCK_TYPE_ID, "Thruster Block", Color(0.3, 0.7, 1.0), LINE_2_CELLS,
		0.5, 45.0, 800.0, null, "", 1,
		{MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 8},
		0.0, 0.0, null, true)
	FactionArtImporter.apply_hex_art(thruster_block, "thruster_mk1")
	types.append(thruster_block)

	# --- Legacy single-hex types --------------------------------------------
	# No longer offered in the builder (see ShipBuilderPanel.BUILDABLE_TYPE_IDS)
	# but still referenced by id from saved layouts and by any part already in a
	# player's hold, so they stay in the catalog.

	# Fragile enough to be crackable within a normal engagement (with splash
	# from nearby hits, see Ship.module_splash_fraction), but not so fragile
	# that whatever's behind sturdier armor is exposed within a few seconds
	# of sustained close-range fire.
	# Phase 5.2 example cost: built from crafted components rather than raw
	# Iron directly, once ComponentCatalog/CraftingCatalog exist to produce
	# them (build_costs is spent when the module is *built*, not placed —
	# see ShipBuilderPanel._on_build_pressed).
	var hull_type: ModuleType = _make("hull", "Hull", Color(0.5, 0.55, 0.6), SINGLE_CELL, 0.3, 50.0, 0.0, HULL_TEXTURE,
		"", 1, {ComponentCatalog.METAL_SHEETS: 2, ComponentCatalog.REINFORCED_STEEL: 1})
	FactionArtImporter.apply_hex_art(hull_type, "hull_mk1")
	types.append(hull_type)

	# Phase 5.2 example cost ("Thruster" in the spec) — Metal Sheets for the
	# housing, Wiring + a crafted Motor for the actual drive.
	var engine_type: ModuleType = _make("engine", "Engine", Color(0.3, 0.7, 1.0), SINGLE_CELL, 0.25, 20.0, 500.0, null,
		"", 1, {ComponentCatalog.METAL_SHEETS: 1, ComponentCatalog.WIRING: 2, ComponentCatalog.MOTOR: 1})
	FactionArtImporter.apply_hex_art(engine_type, "engine_mk1")
	engine_type.is_capturable_tech = true
	types.append(engine_type)

	# Meant to actually function as a wall: tough enough that sustained
	# close-range fire can't punch through to whatever it's shielding within
	# a few seconds, even from several guns at once.
	var heavy_hull_type: ModuleType = _make("heavy_hull", "Heavy Hull", Color(0.45, 0.3, 0.55), LINE_3_CELLS, 0.9, 240.0, 0.0, null,
		"", 1, {MaterialCatalog.IRON: 20})
	FactionArtImporter.apply_hex_art(heavy_hull_type, "armour_module")
	types.append(heavy_hull_type)

	# Deliberately cheaper, lighter and far more fragile than Hull: a strut's
	# only job is connecting a wing/appendage back to the core, so a snapped-off
	# wing costs little to have risked and rebuilt, unlike investing in Hull.
	# Ancient has no strut art yet — falls back to a flat tinted hex for that
	# faction only (see ShipLayoutRenderer/HexGridControl).
	var strut_type: ModuleType = _make("strut", "Strut", Color(0.55, 0.58, 0.5), SINGLE_CELL, 0.15, 25.0, 0.0, null,
		"", 1, {MaterialCatalog.IRON: 3})
	FactionArtImporter.apply_hex_art(strut_type, "strut")
	types.append(strut_type)

	# Carries power and nothing else — see docs/design_handoff_conduits/README.md.
	# An open scaffold hex with a clamped junction hub at its centre: no plating
	# fill, no module, no stats. What it buys is a power path (PowerGrid), which
	# makes it the one part whose value is entirely in where it sits.
	#
	# Priced between Strut and Hull: lighter than Hull because there is no armour
	# in it, but tougher than a Strut, because a conduit run that snapped as
	# easily as a strut would make every powered limb a liability rather than a
	# decision.
	var conduit_type: ModuleType = _make(CONDUIT_TYPE_ID, "Conduit", Color(0.42, 0.5, 0.58), SINGLE_CELL,
		0.2, 35.0, 0.0, null, "", 1, {MaterialCatalog.IRON: 4, MaterialCatalog.COPPER: 6})
	FactionArtImporter.apply_hex_art(conduit_type, "conduit")
	types.append(conduit_type)

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
	# apply_hex_art also claims the old unsuffixed single-image name for each
	# tier as a fallback (via get_hex_texture_for_cell's built-in fallback) —
	# factions that haven't re-exported a tier with the new per-cell pieces yet
	# (Ancient/Pirates only have "laser_cannon_mk1.png" so far) keep showing
	# their existing art instead of going blank — and picks up a "_lights" layer
	# for either shape the day one is exported.
	var weapon_t1: ModuleType = _make(WEAPON_HARDPOINT_TYPE_ID, "Weapon Hardpoint I", Color(0.9, 0.35, 0.3), SINGLE_CELL,
		0.2, 15.0, 0.0, null, "weapon", 1, {MaterialCatalog.IRON: 8, MaterialCatalog.COPPER: 4})
	FactionArtImporter.apply_hex_art(weapon_t1, "laser_cannon_mk1", "turret_360")
	weapon_t1.is_capturable_tech = true
	types.append(weapon_t1)
	var weapon_t2: ModuleType = _make("weapon_hardpoint_t2", "Weapon Hardpoint II", Color(0.8, 0.25, 0.2), LINE_2_CELLS,
		0.5, 35.0, 0.0, null, "weapon", 2, {MaterialCatalog.IRON: 18, MaterialCatalog.COPPER: 10})
	FactionArtImporter.apply_hex_art(weapon_t2, "laser_cannon_mk2", "turret_360_mk2")
	weapon_t2.is_capturable_tech = true
	types.append(weapon_t2)
	var weapon_t3: ModuleType = _make("weapon_hardpoint_t3", "Weapon Hardpoint III", Color(0.65, 0.15, 0.1), TRIANGLE_3_CELLS,
		0.9, 60.0, 0.0, null, "weapon", 3,
		{MaterialCatalog.IRON: 32, MaterialCatalog.COPPER: 20, MaterialCatalog.TITANIUM: 5})
	FactionArtImporter.apply_hex_art(weapon_t3, "laser_cannon_mk3", "turret_360_mk3")
	weapon_t3.is_capturable_tech = true
	types.append(weapon_t3)

	# Same reuse-across-tiers reasoning as the laser cannon above.
	var missile_t1: ModuleType = _make(MISSILE_HARDPOINT_TYPE_ID, "Missile Rack I", Color(1.0, 0.6, 0.15), SINGLE_CELL,
		0.3, 20.0, 0.0, MISSILE_HARDPOINT_TEXTURE, "missile", 1, {MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 8})
	FactionArtImporter.apply_hex_art(missile_t1, "missile_launcher_mk1")
	missile_t1.is_capturable_tech = true
	types.append(missile_t1)
	var missile_t2: ModuleType = _make("missile_hardpoint_t2", "Missile Rack II", Color(0.9, 0.5, 0.1), LINE_2_CELLS,
		0.7, 45.0, 0.0, null, "missile", 2, {MaterialCatalog.IRON: 22, MaterialCatalog.COPPER: 16})
	FactionArtImporter.apply_hex_art(missile_t2, "missile_launcher_mk1")
	missile_t2.is_capturable_tech = true
	types.append(missile_t2)
	var missile_t3: ModuleType = _make("missile_hardpoint_t3", "Missile Rack III", Color(0.75, 0.4, 0.05), LINE_3_CELLS,
		1.2, 75.0, 0.0, null, "missile", 3,
		{MaterialCatalog.IRON: 38, MaterialCatalog.COPPER: 26, MaterialCatalog.NICKEL: 10})
	FactionArtImporter.apply_hex_art(missile_t3, "missile_launcher_mk1")
	missile_t3.is_capturable_tech = true
	types.append(missile_t3)

	var reactor_type: ModuleType = _make("reactor_mk1", "Reactor Mk1", Color(1.0, 0.75, 0.2), SINGLE_CELL,
		0.35, 25.0, 0.0, null, "", 1,
		{MaterialCatalog.IRON: 15, MaterialCatalog.COPPER: 15, MaterialCatalog.NICKEL: 10},
		15.0, 0.0)
	FactionArtImporter.apply_hex_art(reactor_type, "reactor_mk1")
	reactor_type.is_capturable_tech = true
	types.append(reactor_type)

	var battery_type: ModuleType = _make("battery_mk1", "Battery Mk1", Color(0.85, 0.75, 0.95), SINGLE_CELL,
		0.3, 20.0, 0.0, null, "", 1,
		{MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 20},
		0.0, 80.0)
	FactionArtImporter.apply_hex_art(battery_type, "battery_mk1")
	battery_type.is_capturable_tech = true
	types.append(battery_type)

	# Cargo storage (see ShipLayout.total_cargo_capacity/Ship._refresh_layout_
	# stats). A plain stat contributor like Reactor/Battery, not a
	# hardpoint category — storage has no facing/muzzle/HUD gate of its own,
	# it just raises the cap Inventory.try_add_material() checks.
	# Brown/tan tint stays as the fallback for factions with no cargo art.
	# Phase 5.2 example cost — Metal Sheets for the walls, Canisters for the
	# actual holding cells.
	var storage_type: ModuleType = _make("storage_mk1", "Cargo Container", Color(0.6, 0.45, 0.3), SINGLE_CELL,
		0.4, 30.0, 0.0, null, "", 1,
		{ComponentCatalog.METAL_SHEETS: 2, ComponentCatalog.CANISTER: 3},
		# The two -1.0s are "use ModuleType's own capture defaults"; they are only
		# here to reach cargo_capacity_contribution, and a Cargo Container is not
		# capturable tech in any case.
		0.0, 0.0, null, false, -1.0, -1.0, 60.0)
	storage_type.hold_cells = 4
	FactionArtImporter.apply_hex_art(storage_type, "cargo_container")
	types.append(storage_type)
	types.append_array(_bigger_storage_types(storage_type))

	# Corporate Alliance: standardised, industrial kinetic weapon. Tougher
	# than a laser hardpoint of similar footprint since it's built to
	# withstand its own recoil (see HardpointRailgun).
	var railgun_type: ModuleType = _make(RAILGUN_HARDPOINT_TYPE_ID, "Railgun", Color(0.8, 0.85, 0.92), LINE_2_CELLS,
		0.7, 40.0, 0.0, null, "weapon", 1,
		{MaterialCatalog.IRON: 25, MaterialCatalog.COPPER: 10, MaterialCatalog.TITANIUM: 8},
		0.0, 0.0, preload("res://scenes/player/hardpoint_railgun.tscn"))
	railgun_type.is_capturable_tech = true
	types.append(railgun_type)

	# Ancient Civilisation: alien energy weapon. Lighter and more fragile
	# than the industrial Railgun — it's exotic technology, not armor plate.
	var phase_lance_type: ModuleType = _make(PHASE_LANCE_HARDPOINT_TYPE_ID, "Phase Lance", Color(0.35, 0.2, 0.45), SINGLE_CELL,
		0.25, 30.0, 0.0, null, "weapon", 1,
		{MaterialCatalog.COPPER: 20, MaterialCatalog.TITANIUM: 18},
		0.0, 0.0, preload("res://scenes/player/hardpoint_phase_lance.tscn"))
	phase_lance_type.is_capturable_tech = true
	types.append(phase_lance_type)

	# Tractor beam hardpoint (see HardpointTractorBeam/HardpointBank._mount_tractor_beam).
	var tractor_type: ModuleType = _make(TRACTOR_HARDPOINT_TYPE_ID, "Tractor Beam", Color(0.4, 0.75, 0.85), SINGLE_CELL,
		0.2, 30.0, 0.0, null, "tractor", 1, {MaterialCatalog.IRON: 8, MaterialCatalog.COPPER: 8})
	FactionArtImporter.apply_hex_art(tractor_type, "tractor_beam")
	types.append(tractor_type)

	# Radar hardpoint (see RadarDisplay.has_radar/Ship.has_radar) — a pure
	# capability flag, no per-hex spawned node or fixed facing needed (radar
	# is an omnidirectional sensor centered on the ship, not a directional
	# beam like the tractor beam), so unlike most hardpoints above it never
	# gets a hardpoint_scene. Green (matching RadarDisplay's own sweep/label
	# color) is the fallback tint for factions with no radar art — distinct at
	# a glance from Engine and the Tractor Beam hardpoint, which sat right
	# next to it in the same blue family.
	var radar_type: ModuleType = _make(RADAR_HARDPOINT_TYPE_ID, "Radar", Color(0.3, 1.0, 0.55), SINGLE_CELL,
		0.2, 25.0, 0.0, null, "radar", 1, {MaterialCatalog.IRON: 6, MaterialCatalog.COPPER: 10})
	FactionArtImporter.apply_hex_art(radar_type, "radar")
	types.append(radar_type)

	# Scanner hardpoint (see Scanner.has_scanner/Ship.has_scanner) — same
	# "pure capability flag" shape as Radar: the pulse originates from the
	# ship's own position, not a per-hex muzzle, so no spawned node or fixed
	# facing is needed.
	# Phase 5.2 example cost — Circuit Board for the sensor electronics,
	# Wiring, and raw Glass as the "suitable transparent... component" the
	# spec calls for (no dedicated lens/sensor component exists yet — see
	# CraftingCatalog, don't invent a seventh component for one line item).
	var scanner_type: ModuleType = _make(SCANNER_HARDPOINT_TYPE_ID, "Scanner", Color(0.9, 0.35, 0.75), SINGLE_CELL,
		0.2, 25.0, 0.0, null, "scanner", 1,
		{ComponentCatalog.CIRCUIT_BOARD: 1, ComponentCatalog.WIRING: 1, MaterialCatalog.GLASS: 2})
	FactionArtImporter.apply_hex_art(scanner_type, "scanner")
	types.append(scanner_type)

	# Hull Slicer (see HardpointSlicer) — the tool the salvage loop runs on. Two
	# hexes, mounted with a fixed facing. Toggled on/off by the player (the
	# Salvager system's switch, "G") rather than always-on like the Tractor Beam,
	# since the beam damages whatever it touches and should require deliberate
	# activation.
	#
	# Cold white in the fallback tint, matching the beam — this is industrial
	# equipment and should not read as a weapon at any point.
	var slicer_type: ModuleType = _make(SALVAGER_HARDPOINT_TYPE_ID, "Hull Slicer", Color(0.85, 0.93, 1.0), LINE_2_CELLS,
		0.6, 45.0, 0.0, null, "salvager", 1,
		{MaterialCatalog.IRON: 15, MaterialCatalog.COPPER: 6},
		0.0, 0.0, preload("res://scenes/player/hardpoint_slicer.tscn"), true)
	# Art key, not a gameplay id: the hex sprites are still filed under the name
	# the module had when they were drawn (resources/exports/*/…_mining_grinder.png).
	# Renaming them is an art-pipeline job (re-export, re-import, mipmap check —
	# see CLAUDE.md) rather than part of this rename.
	FactionArtImporter.apply_hex_art(slicer_type, "mining_grinder")
	types.append(slicer_type)

	types.append_array(_grapple_types())

	_cached_types = types
	for type in types:
		_index[type.id] = type
	return types


## The Grapple line: three tiers of the other half of the salvage loop. The
## Slicer frees a part, a Grapple drags it home.
##
## Replaces the "Salvage Winch", which was the same module under a name that
## never stuck — it is gone rather than kept as a retired id, since nothing
## persists a player's parts between runs yet and the one ship layout that
## mounted it (custodian.tres) now carries a Mk2, which has the identical
## two-cell footprint. The scene it spawns is still named for the winch
## (HardpointWinch); that is internal and renaming it is a mechanical job of its
## own — the line it casts is already GrappleRope.
##
## Each mark is physically bigger than the last, and its aperture — the hole
## the chain actually pays out of — sits
## somewhere different on the assembly, which is what muzzle_offset_cells
## records (measured off the art, in cell-size units, -y pointing forward):
##
##   Mk1  one hex, aperture near the front vertex — the chain leaves the nose.
##   Mk2  two hexes abreast, aperture on the seam between them, so with the pair
##        sitting across the hull the chain fires straight ahead out of the
##        middle.
##   Mk3  two hexes abreast with a third behind carrying the reel drum, aperture
##        at the mouth between the front pair.
##
## All three are "winch" category, so ShipLayout's lookup, the Salvager loop and
## HardpointWinch pick them up with no further plumbing.
static func _grapple_types() -> Array[ModuleType]:
	var grapples: Array[ModuleType] = []
	var winch_scene: PackedScene = preload("res://scenes/player/hardpoint_winch.tscn")
	# Plate steel, matching the art. Only ever seen if the sprites fail to load.
	var plate := Color(0.227, 0.275, 0.322)

	var mk1: ModuleType = _make(GRAPPLE_MK1_TYPE_ID, "Grapple Mk1", plate, SINGLE_CELL,
		0.35, 30.0, 0.0, null, "winch", 1,
		{MaterialCatalog.IRON: 10, MaterialCatalog.COPPER: 4},
		0.0, 0.0, winch_scene, true)
	mk1.muzzle_offset_cells = Vector2(0.0, -0.518)
	FactionArtImporter.apply_hex_art(mk1, "grapple_mk1")
	grapples.append(mk1)

	var mk2: ModuleType = _make(GRAPPLE_MK2_TYPE_ID, "Grapple Mk2", plate, LINE_2_CELLS,
		0.6, 55.0, 0.0, null, "winch", 2,
		{MaterialCatalog.IRON: 16, MaterialCatalog.COPPER: 8},
		0.0, 0.0, winch_scene, true)
	mk2.muzzle_offset_cells = Vector2(0.0, -0.064)
	FactionArtImporter.apply_hex_art(mk2, "grapple_mk2")
	grapples.append(mk2)

	var mk3: ModuleType = _make(GRAPPLE_MK3_TYPE_ID, "Grapple Mk3", plate, TRIANGLE_3_CELLS,
		0.85, 80.0, 0.0, null, "winch", 3,
		{MaterialCatalog.IRON: 24, MaterialCatalog.COPPER: 12},
		0.0, 0.0, winch_scene, true)
	mk3.muzzle_offset_cells = Vector2(0.0, -0.361)
	FactionArtImporter.apply_hex_art(mk3, "grapple_mk3")
	grapples.append(mk3)

	return grapples


## The two larger cargo tiers. Storage is now measured in hold cells rather than
## bulk capacity (see ShipHold), so what a tier buys is hexes to put parts in:
## 4, 8 and 12. Bulk material capacity scales with them, keeping ore and parts on
## the same physical container.
##
## Built from the Mk1 rather than repeating its stats, because the only things
## that differ between the tiers are size and what that size costs — writing all
## three out separately is how they drift apart.
##
## They share the Mk1's art. There is no cargo_container_mk2/mk3 plate drawn yet;
## when there is, dropping the files in and changing the two names below is the
## whole job (see FactionArtImporter).
static func _bigger_storage_types(mk1: ModuleType) -> Array[ModuleType]:
	var bigger: Array[ModuleType] = []

	var mk2: ModuleType = _make("storage_mk2", "Cargo Bay", mk1.color, LINE_2_CELLS,
		0.75, 55.0, 0.0, null, "", 2,
		{ComponentCatalog.METAL_SHEETS: 4, ComponentCatalog.CANISTER: 6},
		0.0, 0.0, null, false, -1.0, -1.0, 120.0)
	mk2.hold_cells = 8
	FactionArtImporter.apply_hex_art(mk2, "cargo_container")
	bigger.append(mk2)

	var mk3: ModuleType = _make("storage_mk3", "Cargo Hold", mk1.color, TRIANGLE_3_CELLS,
		1.1, 80.0, 0.0, null, "", 3,
		{ComponentCatalog.METAL_SHEETS: 6, ComponentCatalog.CANISTER: 9},
		0.0, 0.0, null, false, -1.0, -1.0, 180.0)
	mk3.hold_cells = 12
	FactionArtImporter.apply_hex_art(mk3, "cargo_container")
	bigger.append(mk3)

	return bigger


static func get_by_id(id: String) -> ModuleType:
	get_all()
	return _index.get(id)


static func _make(id: String, display_name: String, color: Color, footprint_cells: Array[Vector2i],
		mass_contribution: float = 0.0, health_contribution: float = 0.0, thrust_contribution: float = 0.0,
		hex_texture: Texture2D = null, hardpoint_category: String = "", tier: int = 1,
		build_costs: Dictionary = {}, energy_generation: float = 0.0,
		energy_capacity_contribution: float = 0.0, hardpoint_scene: PackedScene = null,
		is_capturable_tech: bool = false, capture_health_fraction: float = -1.0,
		capture_chance: float = -1.0, cargo_capacity_contribution: float = 0.0) -> ModuleType:
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
	# Negative means "not specified for this type" — leave ModuleType's own default
	# standing. These used to be repeated as defaults in this signature too, which
	# silently shadowed the ones on ModuleType: retuning capture there changed
	# nothing, because every catalogue entry overwrote it on the way past.
	if capture_health_fraction >= 0.0:
		type.capture_health_fraction = capture_health_fraction
	if capture_chance >= 0.0:
		type.capture_chance = capture_chance
	type.cargo_capacity_contribution = cargo_capacity_contribution
	return type

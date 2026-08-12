class_name ModuleType
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var hex_texture: Texture2D = null
@export var footprint_cells: Array[Vector2i] = [Vector2i.ZERO]
## Faction id (e.g. "corporate", "ancient", "pirate" — see
## ShipPersonality.faction_id) -> a reskinned Texture2D for this exact module,
## drawn instead of hex_texture when the owning ship belongs to that faction.
## hex_texture remains the fallback for any faction with no entry here, so a
## module without faction-specific art (Strut, Railgun, Phase Lance — no
## assets provided yet) still renders correctly for everyone.
@export var faction_hex_textures: Dictionary = {}
## Same idea as faction_hex_textures, but drawn as a second layer on top of
## it rather than instead of it — e.g. a weapon hardpoint's turret art sits
## on top of its base mount plate (see ModuleCatalog's weapon-tier entries),
## so the base plate stays shared across tiers while the turret on top
## changes to show the tier. Empty for any module with no overlay (no
## faction/tier entry here just means "draw nothing extra").
@export var faction_hex_overlay_textures: Dictionary = {}
## For multi-hex modules only: per-footprint-cell base art, one Dictionary
## (faction_id -> Texture2D) per entry in footprint_cells, same order. A
## multi-hex base plate is exported as one image per hex it occupies rather
## than a single image stretched across the whole footprint — the source art
## has a large flat background margin around a small centered icon, so
## stretching one texture across multiple hexes shrank the actual artwork
## down to a tiny fraction in the middle (see ShipLayoutRenderer history).
## Empty (or an empty entry for a given cell/faction) falls back to
## get_hex_texture() for that cell, same texture repeated in every hex.
@export var faction_hex_textures_per_cell: Array[Dictionary] = []
## The emissive half of a module's art: the lit windows, indicator strips and
## emitter rings, authored as a separate layer over a transparent background and
## drawn additively on top of the base plate (see ShipLayoutRenderer's glow
## layer). Kept out of the base image so the lights can be blown past white and
## caught by the world's glow — a lamp painted into the base plate can only ever
## be as bright as the hull it sits on.
##
## Same shape as the two above: one Dictionary for a single-hex module, one per
## footprint cell for a multi-hex one. Both empty means "this module has no lit
## parts", which is most of them.
##
## Never assigned by hand — FactionArtImporter.apply_hex_art fills these in from
## whatever "<base_name>_lights" files exist, so lighting a module up is an art
## job with no code in it. See FactionArtImporter.LIGHTS_SUFFIX for the naming.
@export var faction_hex_glow_textures: Dictionary = {}
@export var faction_hex_glow_textures_per_cell: Array[Dictionary] = []
@export var mass_contribution: float = 0.0
@export var health_contribution: float = 0.0
@export var thrust_contribution: float = 0.0

## "weapon" or "missile" for hardpoint modules (any tier), "" otherwise.
## Lets ShipLayout find all hardpoints of a kind without hard-coding every
## tier's module id.
@export var hardpoint_category: String = ""
## Hardpoint size tier (1-3). Scales the spawned gun/launcher's stats and
## visual size; ignored for non-hardpoint modules.
@export var tier: int = 1
## Material id -> amount required to place this module in the ship builder.
@export var build_costs: Dictionary = {}

## Energy/second this module adds to the ship's regeneration rate (reactors).
@export var energy_generation: float = 0.0
## Energy capacity this module adds to the ship's energy pool (batteries).
@export var energy_capacity_contribution: float = 0.0
## Cargo capacity this module adds to the ship's material storage (see
## ShipLayout.total_cargo_capacity/Ship._refresh_layout_stats).
@export var cargo_capacity_contribution: float = 0.0

## Weapon/missile hardpoints only. Which scene Ship spawns for this specific
## module type instead of its default hardpoint_gun_scene/
## hardpoint_missile_launcher_scene — lets fundamentally different weapons
## (Railgun, Phase Lance) share the hardpoint_category="weapon" plumbing
## (ShipLayout lookups, build costs, tiering) while running their own
## HardpointGun subclass. Null means "use the ship's default for this
## category", which is every existing hardpoint type's behavior unchanged.
@export var hardpoint_scene: PackedScene = null

## Where this module's business end actually is, as a multiple of cell_size,
## measured from the footprint's centre in the module's own un-rotated art space
## (+x right, -y toward the front of the ship). Rope, beam and muzzle flash all
## leave from here.
##
## Needed because a hardpoint is mounted at its footprint centroid, which for
## most modules is nowhere near the hole the art draws the equipment coming out
## of: the Grapple Mk1's aperture sits near its front vertex, the Mk2's between
## its two hexes, the Mk3's at the mouth of its emitter. Zero keeps the old
## behaviour (straight out of the centre) for everything that predates this.
@export var muzzle_offset_cells: Vector2 = Vector2.ZERO

## Whether a severed (not destroyed-outright) instance of this module can be
## recovered intact as a research item rather than just flying off as inert
## ShipDebris — see WreckageSpawner.spawn_severed_piece. Only
## meaningful "unique tech" modules should opt in; plain armor (Hull, Heavy
## Hull, Strut) has nothing worth reverse-engineering.
@export var is_capturable_tech: bool = false
## Minimum fraction of this module's own max condition it must still have at
## the instant it's severed to be capturable — a module chewed down to a
## sliver of health isn't intact enough to recover, only a clean severance.
@export var capture_health_fraction: float = 0.5
## Random roll on top of the health-fraction gate, applied only once that gate is
## already met. Applies ONLY to a part shaken loose by weapon fire; a deliberate
## Slicer cut always recovers (see WreckageSpawner.spawn_severed_piece), so this
## number is really "how often shooting a wing off substitutes for cutting it".
##
## Was 0.35, which measured at ~45% recovery in practice — near enough to the
## Slicer's guaranteed result that holding a beam on a hull for ten seconds was
## strictly the worse option, and the whole salvage loop could be skipped by
## shooting. Low enough now to be a lucky break rather than a strategy.
@export var capture_chance: float = 0.1
## Whether this module must be researched (see Inventory.research) before it
## can be placed in the ship builder — reserved for tech that's meaningfully
## faction-exclusive (Railgun, Phase Lance), not every capturable module,
## so recovering enemy tech has a payoff without gating the core weapon loop.
@export var requires_research: bool = false


## The texture to draw for this module on a ship belonging to faction_id —
## falls back to hex_texture if that faction has no reskin registered (see
## faction_hex_textures above).
func get_hex_texture(faction_id: String) -> Texture2D:
	return faction_hex_textures.get(faction_id, hex_texture)


## The texture for one specific cell of a multi-hex footprint (cell_index
## into footprint_cells) — falls back to get_hex_texture() if no per-cell art
## is registered for this cell/faction (see faction_hex_textures_per_cell).
func get_hex_texture_for_cell(faction_id: String, cell_index: int) -> Texture2D:
	if cell_index < faction_hex_textures_per_cell.size():
		var texture: Texture2D = faction_hex_textures_per_cell[cell_index].get(faction_id, null)
		if texture != null:
			return texture
	return get_hex_texture(faction_id)


## The second-layer texture to draw on top of get_hex_texture(), if any —
## see faction_hex_overlay_textures above. Null means nothing to overlay.
func get_hex_overlay_texture(faction_id: String) -> Texture2D:
	return faction_hex_overlay_textures.get(faction_id, null)


## The emissive layer for one cell, or null if this module has no lit parts —
## see faction_hex_glow_textures.
func get_hex_glow_texture_for_cell(faction_id: String, cell_index: int) -> Texture2D:
	if cell_index < faction_hex_glow_textures_per_cell.size():
		var texture: Texture2D = faction_hex_glow_textures_per_cell[cell_index].get(faction_id, null)
		if texture != null:
			return texture
	return faction_hex_glow_textures.get(faction_id, null)

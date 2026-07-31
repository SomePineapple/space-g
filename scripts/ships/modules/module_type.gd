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

## Weapon/missile hardpoints only. Which scene Ship spawns for this specific
## module type instead of its default hardpoint_gun_scene/
## hardpoint_missile_launcher_scene — lets fundamentally different weapons
## (Railgun, Phase Lance) share the hardpoint_category="weapon" plumbing
## (ShipLayout lookups, build costs, tiering) while running their own
## HardpointGun subclass. Null means "use the ship's default for this
## category", which is every existing hardpoint type's behavior unchanged.
@export var hardpoint_scene: PackedScene = null

## Whether a severed (not destroyed-outright) instance of this module can be
## recovered intact as a research item rather than just flying off as inert
## ShipDebris — see Ship._roll_capturable/_spawn_capturable_part_for. Only
## meaningful "unique tech" modules should opt in; plain armor (Hull, Heavy
## Hull, Strut) has nothing worth reverse-engineering.
@export var is_capturable_tech: bool = false
## Minimum fraction of this module's own max condition it must still have at
## the instant it's severed to be capturable — a module chewed down to a
## sliver of health isn't intact enough to recover, only a clean severance.
@export var capture_health_fraction: float = 0.5
## Random roll on top of the health-fraction gate, applied only once that
## gate is already met — capture is meant to be a notable, not guaranteed,
## outcome even for a clean severance.
@export var capture_chance: float = 0.35
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

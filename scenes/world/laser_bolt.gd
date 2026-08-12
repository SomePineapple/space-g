class_name LaserBolt
extends Sprite2D

## The fired bolt for the Corporate 360 turret line. See
## `images_uploaded/Corporate Turret Lasers v2.dc (1).html`, which is the source
## of truth for these three sprites and for how they are meant to be used.
##
## One texture per mark serves every faction. The art is drawn pure white-to-grey
## with no hue baked into it, so `modulate` multiplies the white core into the
## gun's own colour and the dark capacitor ribs into a darker shade of the same —
## and colour is a property of the gun rather than of the ship carrying it (see
## LaserPalette), so a captured pirate cannon keeps firing pirate red off a
## corporate hull.
##
## Replaces the two flat additive triangles a Projectile used to be.

## Which mark a weapon tier fires: a thin single needle for the agile one-hex
## mount, a twin bolt for the two-hex mount, and one thick heavy-cored round for
## the three-hex mount. Indexed by tier and clamped, same convention as
## HardpointGun's own tier tables.
const MARK_BY_TIER: Array[int] = [1, 1, 2, 3]

## Where each bolt's head core sits along its own texture, as a fraction of the
## texture width.
##
## Measured off the art rather than guessed — the alpha-weighted brightest column
## — because the node's origin is put there, which is also where the collision
## shape sits. The triangle this replaces led its origin by 17 units, so a bolt
## visibly passed through its target before the hit registered.
const HEAD_FRACTION: Dictionary = {1: 0.899, 2: 0.799, 3: 0.833}

## World units per texture pixel, deliberately shared by all three marks so the
## size difference the art was drawn with survives: the mk3 canvas is both wider
## and much taller than mk1's, which is the whole "heavy mount" read. Chosen so
## mk1 spans about the 34 units the triangle it replaces did, which leaves
## HardpointGun's tier scaling (TIER_PROJECTILE_SCALE_MULTIPLIER) to do the
## growth on top rather than counting the size difference twice.
const UNITS_PER_PIXEL: float = 34.0 / 1200.0

## Doc §4: a subtle sine wobble on alpha sells "energy" without a shader.
const FLICKER_DEPTH: float = 0.08
const FLICKER_HZ: float = 25.0
## The heavy round breathes on its thickness instead, slower — a charged, heavier
## shot rather than a flickering one.
const HEAVY_PULSE_DEPTH: float = 0.05
const HEAVY_PULSE_HZ: float = 7.0

## Doc §2: the sprite is a static bolt, so it pops from this fraction of its
## length to full on spawn. Without it a bolt reads as a decal sliding across the
## screen rather than as something launched.
const STRETCH_FROM: float = 0.4
const STRETCH_SECONDS: float = 0.05

## Doc §2's motion streak: a second, dimmer copy of the same texture trailing
## behind, which reads as continuous fire and costs one draw call rather than a
## particle system. Offset is a fraction of the texture width.
const TRAIL_OFFSET: float = 0.16
const TRAIL_ALPHA: float = 0.45

var mark: int = 1

var _base_scale: Vector2 = Vector2.ONE
var _core_alpha: float = 1.0
var _elapsed: float = 0.0
var _trail: Sprite2D


func _ready() -> void:
	# Authored far larger than it draws (a 1200px bolt renders at ~34 units), so
	# without a mip chain it crawls with aliasing — see CLAUDE.md.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_trail = Sprite2D.new()
	_trail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_trail.material = material
	# Behind the bolt in draw order as well as in space.
	add_child(_trail)
	move_child(_trail, 0)
	_apply_geometry()


## `core` and `trail` are the gun's own bolt and halo colours (see
## LaserPalette). Both are allowed past 1.0: the sprite draws additively and the
## region's glow pass turns the overflow into bloom, which is what makes a bolt
## read as light. Unlike a mesh's vertex colour, `modulate` is not quantised to
## 8 bits, so the overflow actually survives.
func configure(bolt_mark: int, faction_id: String, core: Color, trail: Color) -> void:
	mark = clampi(bolt_mark, 1, 3)
	texture = _texture_for(mark, faction_id)
	_core_alpha = core.a
	modulate = core
	if _trail != null:
		_trail.texture = texture
		_trail.modulate = Color(trail.r, trail.g, trail.b, trail.a * TRAIL_ALPHA)
	_apply_geometry()


static func mark_for_tier(tier: int) -> int:
	return MARK_BY_TIER[clampi(tier, 0, MARK_BY_TIER.size() - 1)]


## Loaded through the ordinary faction art path, so the day someone draws a
## pirate bolt it is picked up by dropping the file in — no code here changes.
## Until then every faction borrows the Corporate set, which is the point of it
## being hueless.
static func _texture_for(bolt_mark: int, faction_id: String) -> Texture2D:
	var by_faction: Dictionary = FactionArtImporter.load_faction_textures(
		"laser_bolt_mk%d" % bolt_mark)
	if by_faction.has(faction_id):
		return by_faction[faction_id]
	return by_faction.get("corporate", null)


## Puts the head core on the node's origin and sizes the texture into world
## units. `offset` is in texture pixels and is scaled along with the sprite, so
## both survive the tier scale the Projectile applies to the whole node.
func _apply_geometry() -> void:
	if texture == null:
		return
	var width: float = float(texture.get_width())
	offset = Vector2(width * (0.5 - float(HEAD_FRACTION[mark])), 0.0)
	_base_scale = Vector2.ONE * UNITS_PER_PIXEL
	scale = _base_scale
	if _trail != null:
		_trail.offset = offset
		_trail.position = Vector2(-width * TRAIL_OFFSET, 0.0)


func _process(delta: float) -> void:
	_elapsed += delta

	var stretch: float = 1.0
	if _elapsed < STRETCH_SECONDS:
		var t: float = _elapsed / STRETCH_SECONDS
		# Ease out: the pop is fastest at the muzzle and settles into its length.
		stretch = lerpf(STRETCH_FROM, 1.0, 1.0 - (1.0 - t) * (1.0 - t))

	var thickness: float = 1.0
	if mark == 3:
		thickness += HEAVY_PULSE_DEPTH * sin(_elapsed * TAU * HEAVY_PULSE_HZ)
	scale = Vector2(_base_scale.x * stretch, _base_scale.y * thickness)

	modulate.a = _core_alpha * (1.0 + FLICKER_DEPTH * sin(_elapsed * TAU * FLICKER_HZ))

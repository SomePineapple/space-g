class_name HardpointGun
extends Node2D

@export var projectile_scene: PackedScene = preload("res://scenes/world/projectile.tscn")
@export var fire_rate: float = 4.0
@export var projectile_speed: float = 700.0
@export var recoil_force: float = 24.0
@export var projectile_color: Color = Color(0.4, 0.9, 1.0, 1.0)
@export var projectile_damage: float = 8.0
@export var barrel_color: Color = Color(0.5, 0.85, 1.0, 1.0)
@export var energy_cost: float = 4.0
## Left unassigned by default (no audio assets yet); assign a stream once
## one exists and firing will play it automatically.
@export var fire_sound: AudioStream = null

## Black Market Foundry only (see Manufacturer.malfunction_chance) — zero for
## every other manufacturer/no manufacturer, meaning "never." Set by Ship
## right after instancing, alongside the rest of the manufacturer modifiers.
@export var malfunction_chance: float = 0.0
@export var malfunction_self_damage: float = 0.0

## Tier scaling for bigger (multi-hex) hardpoints: bigger guns hit harder
## and kick more but cycle slower. Tier 1 (index 0) is a 1.0 no-op so
## existing single-hex hardpoints are unaffected.
const TIER_DAMAGE_MULTIPLIER: Array[float] = [1.0, 1.0, 1.8, 2.8]
const TIER_FIRE_RATE_MULTIPLIER: Array[float] = [1.0, 1.0, 0.8, 0.6]
const TIER_RECOIL_MULTIPLIER: Array[float] = [1.0, 1.0, 1.5, 2.2]
const TIER_VISUAL_SCALE: Array[float] = [1.0, 1.0, 1.4, 1.8]
const TIER_PROJECTILE_SCALE_MULTIPLIER: Array[float] = [1.0, 1.0, 1.4, 2.0]
const TIER_ENERGY_COST_MULTIPLIER: Array[float] = [1.0, 1.0, 1.8, 2.8]

## Mirrors ShipLayout's reactor distance penalty (see
## ShipLayout.REACTOR_DISTANCE_PENALTY_PER_CELL): weapons get more damage the
## further out from the Core they're mounted, on the same "cockpit
## interference" idea, so a good hull design has to weigh reactors-close-in
## against weapons-pushed-out rather than clustering everything on one hex.
const CORE_DISTANCE_DAMAGE_BONUS_PER_CELL: float = 0.08
const CORE_DISTANCE_DAMAGE_BONUS_MAX: float = 0.5

## Scales the spawned projectile's whole node (visual and collision shape
## alike, since both are sized relative to this transform), so bigger-tier
## weapons visibly fire bigger shots.
@export var projectile_scale: float = 1.0

## Which ModulePlacement (on the shooter's ShipLayout) this hardpoint was
## spawned from — set by Ship right after instancing, so Ship.fire_primary()/
## fire_secondary() can skip a hardpoint whose module has been destroyed.
var source_placement_id: String = ""

var _cooldown_remaining: float = 0.0
var _shooter: Ship
var _cell_size: float = 24.0
var _tier_scale: float = 1.0

@onready var _barrel: Polygon2D = $Barrel
@onready var _turret: Sprite2D = $Turret
@onready var _muzzle: Marker2D = $Muzzle
@onready var _fire_sound_player: AudioStreamPlayer2D = $FireSound


func _ready() -> void:
	_barrel.color = barrel_color


func setup(shooter: Ship) -> void:
	_shooter = shooter


## Scales this hardpoint's already-set base stats for its module tier (1-3).
## Called once, right after _ready(), before upgrade modifiers are applied.
## Clamped rather than indexed raw: a ModuleType authored with a tier outside
## 1-3 used to crash here on an out-of-bounds read.
func apply_tier(tier: int) -> void:
	var index: int = _tier_index(tier)
	projectile_damage *= TIER_DAMAGE_MULTIPLIER[index]
	fire_rate *= TIER_FIRE_RATE_MULTIPLIER[index]
	recoil_force *= TIER_RECOIL_MULTIPLIER[index]
	projectile_scale *= TIER_PROJECTILE_SCALE_MULTIPLIER[index]
	energy_cost *= TIER_ENERGY_COST_MULTIPLIER[index]


static func _tier_index(tier: int) -> int:
	return clampi(tier, 0, TIER_DAMAGE_MULTIPLIER.size() - 1)


## Called once, right after apply_tier(), before upgrade modifiers.
func apply_core_distance_bonus(distance: int) -> void:
	var bonus: float = minf(CORE_DISTANCE_DAMAGE_BONUS_PER_CELL * distance, CORE_DISTANCE_DAMAGE_BONUS_MAX)
	projectile_damage *= 1.0 + bonus


static func tier_visual_scale(tier: int) -> float:
	return TIER_VISUAL_SCALE[_tier_index(tier)]


## Sizes the barrel to two hex-lengths, pivoting at this node's own
## origin (the hardpoint's hex center) rather than the barrel's midpoint.
## tier_scale grows the barrel for bigger-tier hardpoints (see Ship's
## _spawn_hardpoint_guns()), which also occupy more hex cells.
func set_cell_size(cell_size: float, tier_scale: float = 1.0) -> void:
	_cell_size = cell_size
	_tier_scale = tier_scale
	var length: float = cell_size * 2.0 * tier_scale
	var half_width: float = cell_size * 0.18 * tier_scale
	_barrel.polygon = PackedVector2Array([
		Vector2(0, -half_width),
		Vector2(length, -half_width),
		Vector2(length, half_width),
		Vector2(0, half_width),
	])
	_muzzle.position = Vector2(length, 0)
	_update_turret_transform()


## Faction/tier turret art (see ModuleType.faction_hex_overlay_textures) drawn
## on top of the hardpoint's hex, replacing the plain Barrel polygon so the
## laser visibly fires out of the turret's own barrel rather than a flat
## rectangle. Null (no art for this faction/tier yet, e.g. Railgun, Phase
## Lance, or a faction with no turret sprite) falls back to the Barrel
## polygon unchanged.
func set_turret_texture(texture: Texture2D) -> void:
	_turret.texture = texture
	_barrel.visible = texture == null
	_update_turret_transform()


## The turret art is authored pointing "up" (its barrel tip at the top edge
## of the canvas, muzzle centered on the image's horizontal axis) with its
## rotation pivot at the image's vertical/horizontal center, so a 90-degree
## rotation aligns it with this node's own forward convention (+X, same as
## the Barrel polygon and Muzzle marker). Scaled so the image's half-height
## lands exactly on the existing Muzzle position (two hex-lengths out), so
## the visual barrel tip and the projectile spawn point always match.
func _update_turret_transform() -> void:
	if _turret.texture == null:
		return
	_turret.rotation = PI / 2.0
	var length: float = _cell_size * 2.0 * _tier_scale
	var half_height: float = _turret.texture.get_height() / 2.0
	_turret.scale = Vector2.ONE * (length / half_height)


func aim_at(global_target: Vector2) -> void:
	global_rotation = (global_target - global_position).angle()


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta


func fire() -> Projectile:
	if _cooldown_remaining > 0.0 or _shooter == null:
		return null
	if not _shooter.spend_energy(energy_cost):
		return null
	_cooldown_remaining = 1.0 / fire_rate
	if malfunction_chance > 0.0 and randf() < malfunction_chance:
		_shooter.damage_own_module(source_placement_id, malfunction_self_damage)
		return null
	return _execute_fire()


## Split out from fire() so a charge-up weapon (HardpointRailgun,
## HardpointPhaseLance) can override fire() with its own gating/timing —
## reserving the cooldown slot and consuming energy up front — while still
## reusing the actual projectile-spawn and recoil logic once its charge
## completes.
func _execute_fire() -> Projectile:
	var projectile: Projectile = projectile_scene.instantiate()
	projectile.color = projectile_color
	projectile.damage = projectile_damage
	projectile.scale = Vector2.ONE * projectile_scale
	# Bigger-tier projectiles should leave a bigger impact burst, not just a
	# bigger travelling shot.
	projectile.explosion_scale *= projectile_scale
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = _muzzle.global_position
	projectile.global_rotation = _muzzle.global_rotation
	projectile.launch(projectile_speed, _shooter)

	if fire_sound != null:
		_fire_sound_player.stream = fire_sound
		_fire_sound_player.play()

	_apply_recoil()
	return projectile


## A small straight-line kick opposite the barrel's facing, not a spin — see
## Ship.apply_impulse. Deliberately linear-only: an earlier version also
## applied torque for off-center hardpoints, but that "whipped" the ship's
## rotation around on every shot, which read as unintentional and didn't
## feel good even on a high-recoil weapon like the Railgun.
func _apply_recoil() -> void:
	var recoil_impulse: Vector2 = -_muzzle.global_transform.x * recoil_force
	_shooter.apply_impulse(recoil_impulse)

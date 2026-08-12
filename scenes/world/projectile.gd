class_name Projectile
extends Area2D

@export var speed: float = 700.0
@export var lifetime: float = 2.0
@export var explosion_scene: PackedScene = preload("res://scenes/world/explosion.tscn")
## Impact burst size. Bigger-tier guns multiply this by their projectile_scale
## (see HardpointGun._execute_fire), so this is the tier-1 bolt's hit and every
## other laser hit is relative to it.
@export var explosion_scale: float = 0.21
@export var damage: float = 10.0

## Which of the three bolt sprites this shot draws (see LaserBolt) — set by the
## firing gun from its module tier.
@export var mark: int = 1:
	set(value):
		mark = value
		if is_node_ready():
			_apply_bolt()
## Which faction's bolt art to draw. Only the Corporate set exists so far and it
## is deliberately hueless, so everyone borrows it and supplies their own colour.
@export var bolt_faction: String = "corporate":
	set(value):
		bolt_faction = value
		if is_node_ready():
			_apply_bolt()

## The bolt's core colour. Deliberately allowed past 1.0 — the sprite draws
## additively and the world's glow pass turns the overflow into bloom, which is
## what makes a bolt read as light rather than as a coloured decal. See
## LaserPalette, and note it needs rendering/viewport/hdr_2d to survive.
@export var color: Color = Color(1, 1, 1, 1):
	set(value):
		color = value
		if is_node_ready():
			_apply_bolt()

## The trailing streak's colour (see LaserBolt.TRAIL_OFFSET). Set alongside
## `color` by whoever fires the shot; left as a dimmed version of it if nobody
## does.
@export var halo_color: Color = Color(1, 1, 1, 0.5):
	set(value):
		halo_color = value
		_halo_color_set = true
		if is_node_ready():
			_apply_bolt()

var _halo_color_set: bool = false

## Which ModulePlacement on the shooter fired this, so a kill can be credited
## back to that specific gun (see Ship.record_hardpoint_kill). Carried on the
## shot rather than looked up on impact because the gun may well be shot off its
## mount during the second the bolt is in flight.
var source_placement_id: String = ""

var _velocity: Vector2 = Vector2.ZERO
var _time_alive: float = 0.0
var _shooter: Node = null

@onready var _bolt: LaserBolt = $Bolt


func launch(travel_speed: float, shooter: Node = null) -> void:
	speed = travel_speed
	_velocity = transform.x * speed
	_shooter = shooter


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_bolt()


func _apply_bolt() -> void:
	var trail: Color = halo_color if _halo_color_set else Color(color.r, color.g, color.b, 0.5)
	_bolt.configure(mark, bolt_faction, color, trail)


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()


func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return
	# Sampled before and after the hit: Health.destroyed fires synchronously
	# inside take_damage, but the victim's node survives until its deferred
	# teardown, so its health is still readable here.
	#
	# Asked for by method rather than by `is Ship`, like the damage calls below.
	# A static reference to Ship from this script closes a parse cycle — Ship ->
	# HardpointBank -> HardpointGun -> (preload) projectile.tscn -> here — which
	# breaks class resolution across every hardpoint script. Only Ship has either
	# of these methods, so the duck-typing costs no precision.
	var was_alive: bool = body.has_method("get_current_health") \
		and body.get_current_health() > 0.0
	if body.has_method("take_damage_at"):
		body.take_damage_at(damage, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(damage)
	if was_alive and body.get_current_health() <= 0.0 \
			and _shooter != null and _shooter.has_method("record_hardpoint_kill"):
		_shooter.record_hardpoint_kill(source_placement_id)
	_destroy()


func _destroy() -> void:
	var explosion: Explosion = explosion_scene.instantiate()
	explosion.tint = color
	explosion.effect_scale = explosion_scale
	WorldSpawn.attach_at(explosion, global_position)

	# Deferred: this runs from within the physics engine's collision query
	# flush (_on_body_entered), where freeing a CollisionObject2D
	# synchronously triggers a physics server error.
	queue_free.call_deferred()

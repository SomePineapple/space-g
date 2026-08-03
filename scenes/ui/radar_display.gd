extends Control

## Broad-detection radar. Deliberately reports category only (a colored/shaped
## blip), never specific object identity — see docs/roadmap "Radar should not
## provide detailed object information."
enum Category { SHIP, STATION, ELECTRONIC_SIGNAL, ENEMY_CAMP, DISTRESS_BEACON }

## Which existing group each broad category is read from. "electronic_signal",
## "enemy_camp" and "distress_beacon" have no in-game instances yet — nothing
## joins those groups today, so radar simply shows nothing for them until a
## future feature adds contacts to those groups.
const GROUP_CATEGORY: Dictionary = {
	"enemy_ship": Category.SHIP,
	"home_base": Category.STATION,
	"electronic_signal": Category.ELECTRONIC_SIGNAL,
	"enemy_camp": Category.ENEMY_CAMP,
	"distress_beacon": Category.DISTRESS_BEACON,
}

const CATEGORY_COLOR: Dictionary = {
	Category.SHIP: Color(1.0, 0.3, 0.3),
	Category.STATION: Color(0.3, 0.8, 1.0),
	Category.ELECTRONIC_SIGNAL: Color(1.0, 0.9, 0.3),
	Category.ENEMY_CAMP: Color(1.0, 0.55, 0.15),
	Category.DISTRESS_BEACON: Color(0.4, 1.0, 0.5),
}

@export var detection_range: float = 2000.0
@export var refresh_interval: float = 0.25
@export var sweep_speed: float = 1.5
@export var radius: float = 75.0
## How long a blip lingers after the sweep passes over it before fading out —
## a contact is only ever as fresh as the last time the sweep line touched it.
@export var blip_fade_duration: float = 2.5
## Blips within this world-distance of each other (per refresh) are treated
## as the same contact re-pinged rather than a new blip — approximate since
## contacts aren't tracked by identity, only position + category.
const BLIP_MATCH_DISTANCE: float = 150.0

var _player: Node2D
var _sweep_angle: float = 0.0
var _prev_sweep_angle: float = 0.0
var _refresh_timer: float = 0.0
var _contacts: Array[Dictionary] = []
var _blips: Array[Dictionary] = []


func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if not players.is_empty():
		_player = players[0]

	custom_minimum_size = Vector2(radius * 2.0 + 10.0, radius * 2.0 + 10.0)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -(radius * 2.0 + 20.0)
	offset_top = -(radius * 2.0 + 20.0)
	offset_right = -10.0
	offset_bottom = -10.0

	_refresh_contacts()


func _process(delta: float) -> void:
	if _player == null:
		return

	_prev_sweep_angle = _sweep_angle
	_sweep_angle = wrapf(_sweep_angle + sweep_speed * delta, 0.0, TAU)

	_refresh_timer += delta
	if _refresh_timer >= refresh_interval:
		_refresh_timer = 0.0
		_refresh_contacts()

	_update_sweep_hits()
	_decay_blips(delta)

	queue_redraw()


func _refresh_contacts() -> void:
	_contacts.clear()
	if _player == null:
		return

	var origin: Vector2 = _player.global_position
	for group_name in GROUP_CATEGORY:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == _player or not (node is Node2D):
				continue
			var offset: Vector2 = (node as Node2D).global_position - origin
			var distance: float = offset.length()
			if distance > detection_range:
				continue
			_contacts.append({
				"offset": offset,
				"category": GROUP_CATEGORY[group_name],
			})


## A contact only becomes a visible blip once the sweep line has just passed
## its bearing — no live drawing of anything the sweep hasn't touched yet.
func _update_sweep_hits() -> void:
	for contact in _contacts:
		var offset: Vector2 = contact["offset"]
		var bearing: float = wrapf(offset.angle(), 0.0, TAU)
		if _sweep_passed(bearing):
			_ping_blip(offset, contact["category"])


func _sweep_passed(bearing: float) -> bool:
	if _sweep_angle >= _prev_sweep_angle:
		return bearing >= _prev_sweep_angle and bearing <= _sweep_angle
	# Sweep wrapped past TAU back to 0 this frame.
	return bearing >= _prev_sweep_angle or bearing <= _sweep_angle


func _ping_blip(offset: Vector2, category: Category) -> void:
	for blip in _blips:
		if blip["category"] == category and (blip["offset"] as Vector2).distance_to(offset) <= BLIP_MATCH_DISTANCE:
			blip["offset"] = offset
			blip["age"] = 0.0
			return
	_blips.append({"offset": offset, "category": category, "age": 0.0})


func _decay_blips(delta: float) -> void:
	for i in range(_blips.size() - 1, -1, -1):
		_blips[i]["age"] += delta
		if _blips[i]["age"] >= blip_fade_duration:
			_blips.remove_at(i)


func _draw() -> void:
	var center: Vector2 = Vector2(radius, radius) + Vector2(5.0, 5.0)

	draw_circle(center, radius, Color(0.0, 0.15, 0.05, 0.55))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.3, 1.0, 0.5, 0.6), 1.5)
	draw_arc(center, radius * 0.5, 0.0, TAU, 32, Color(0.3, 1.0, 0.5, 0.25), 1.0)

	var sweep_dir: Vector2 = Vector2.RIGHT.rotated(_sweep_angle)
	draw_line(center, center + sweep_dir * radius, Color(0.4, 1.0, 0.6, 0.9), 2.0)

	var scale: float = radius / detection_range
	for blip in _blips:
		var point: Vector2 = center + (blip["offset"] as Vector2) * scale
		var color: Color = CATEGORY_COLOR.get(blip["category"], Color.WHITE)
		color.a *= 1.0 - ((blip["age"] as float) / blip_fade_duration)
		_draw_contact(point, blip["category"], color)


func _draw_contact(point: Vector2, category: Category, color: Color) -> void:
	match category:
		Category.SHIP:
			draw_circle(point, 3.0, color)
		Category.STATION:
			draw_rect(Rect2(point - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), color)
		_:
			var diamond: PackedVector2Array = PackedVector2Array([
				point + Vector2(0.0, -4.0),
				point + Vector2(4.0, 0.0),
				point + Vector2(0.0, 4.0),
				point + Vector2(-4.0, 0.0),
			])
			draw_colored_polygon(diamond, color)

class_name Salvage
extends Area2D

signal collected(value: int)

enum Rarity { COMMON, ELECTRONICS, ENERGY, EXPERIMENTAL, ARTEFACT }

const RARITY_DATA: Dictionary = {
	Rarity.COMMON: {"color": Color(0.75, 0.78, 0.8), "value": 10},
	Rarity.ELECTRONICS: {"color": Color(0.3, 0.6, 1.0), "value": 20},
	Rarity.ENERGY: {"color": Color(0.3, 1.0, 0.5), "value": 35},
	Rarity.EXPERIMENTAL: {"color": Color(0.7, 0.3, 1.0), "value": 60},
	Rarity.ARTEFACT: {"color": Color(1.0, 0.85, 0.3), "value": 100},
}

const DANGER_COLOR: Color = Color(1.0, 0.15, 0.15)
const DANGER_PULSE_SPEED: float = 6.0
const DANGER_PULSE_STRENGTH: float = 0.7

@export var rarity: Rarity = Rarity.COMMON
@export var drift_speed: float = 20.0
@export var is_dangerous: bool = false
@export var danger_damage: float = 15.0

var salvage_value: int = 10
var _drift_direction: Vector2 = Vector2.ZERO
var _base_color: Color
var _time: float = 0.0

@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	add_to_group("salvage")
	body_entered.connect(_on_body_entered)
	_drift_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

	var data: Dictionary = RARITY_DATA[rarity]
	_base_color = data["color"]
	_visual.modulate = _base_color
	salvage_value = data["value"]

	set_process(is_dangerous)


func _process(delta: float) -> void:
	_time += delta
	var pulse: float = (sin(_time * DANGER_PULSE_SPEED) + 1.0) * 0.5
	_visual.modulate = _base_color.lerp(DANGER_COLOR, pulse * DANGER_PULSE_STRENGTH)


func _physics_process(delta: float) -> void:
	position += _drift_direction * drift_speed * delta


func pull_toward(target_position: Vector2, speed: float, delta: float) -> void:
	global_position = global_position.move_toward(target_position, speed * delta)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player_ship"):
		return
	if body.has_method("add_salvage"):
		body.add_salvage(salvage_value)
	if is_dangerous and body.has_method("take_damage"):
		body.take_damage(danger_damage)
	collected.emit(salvage_value)
	queue_free()

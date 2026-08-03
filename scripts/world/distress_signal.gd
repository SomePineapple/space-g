class_name DistressSignal
extends Node2D

## "Distress Signal" point of interest (see "2.3 Basic points of interest").
## Broadcasts on radar's "distress_beacon" category (see radar_display.gd)
## until every Salvage child here has been collected, then goes quiet and
## stops drawing its beacon light — a resolved distress call shouldn't keep
## pinging forever. The stranded hull itself stays in the world as scenery;
## only the beacon (group membership + light) turns off. Deliberately not
## in the "scannable" group: distress calls are active/live signals, the
## kind Radar covers, not the off-grid derelicts Scanner covers (see
## scannable.gd and the Radar/Scanner boundary rule).

@export var beacon_color: Color = Color(1.0, 0.9, 0.3)
@export var beacon_offset: Vector2 = Vector2(0.0, -60.0)
@export var pulse_speed: float = 2.5

var _pending_salvage: Array[Node] = []
var _active: bool = true
var _time: float = 0.0


func _ready() -> void:
	add_to_group("distress_beacon")
	for child in get_children():
		if child is Salvage:
			_pending_salvage.append(child)
			(child as Salvage).collected.connect(_on_salvage_collected.bind(child))


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var pulse: float = (sin(_time * pulse_speed) + 1.0) * 0.5
	var color: Color = beacon_color
	color.a = lerpf(0.35, 1.0, pulse)
	draw_circle(beacon_offset, 6.0, color)


func _on_salvage_collected(_material_id: String, _amount: int, salvage: Node) -> void:
	_pending_salvage.erase(salvage)
	if _pending_salvage.is_empty():
		_active = false
		remove_from_group("distress_beacon")
		queue_redraw()

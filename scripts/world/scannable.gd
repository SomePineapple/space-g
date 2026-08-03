class_name Scannable
extends Node2D

## Generic "this can be scanned" component for physical objects that have no
## script of their own (planets, derelict wrecks) — gives them the same
## is_identified / scan_category / mark_identified surface Scanner expects.
## Anything that already has its own script (e.g. Asteroid) implements this
## same surface directly instead of adding this as a second script, since a
## node can only have one.
signal identified(category: String)

@export var scan_category: String = "Unknown Object"

var is_identified: bool = false


func _ready() -> void:
	add_to_group("scannable")


func mark_identified() -> void:
	if is_identified:
		return
	is_identified = true
	identified.emit(scan_category)

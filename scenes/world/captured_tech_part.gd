class_name CapturedTechPart
extends DriftingHexPiece

## A severed module that stayed intact enough to be worth recovering (see
## Ship._roll_capturable). Drifts exactly like ordinary ShipDebris (both share
## DriftingHexPiece), but persists far longer and can be reeled in by
## HardpointWinch/HardpointTractorBeam instead of just fading away — see
## begin_reel_in(). Stores which module/faction/manufacturer it came from for
## the research and manufacturer-discovery systems to consume on pickup.

signal captured

var module_type_id: String = ""
var faction_id: String = ""
## Empty means "generic/no manufacturer" — see Manufacturer/ManufacturerCatalog.
var manufacturer_id: String = ""

var _being_reeled_in: bool = false


func _init() -> void:
	# Far longer than ShipDebris': this is a pickup the player has to notice,
	# fly to and reel in, not a one-second visual flourish.
	lifetime = 45.0
	fade_duration = 2.0


func _ready() -> void:
	super._ready()
	add_to_group("capturable_tech")


## Provenance, set by Ship right after setup(). Kept separate from setup()
## rather than widening it: GDScript requires an override to match its base
## class's signature exactly, and every other DriftingHexPiece has no source
## module to record.
func set_source(source_module_type_id: String, source_faction_id: String, source_manufacturer_id: String = "") -> void:
	module_type_id = source_module_type_id
	faction_id = source_faction_id
	manufacturer_id = source_manufacturer_id


## Called by a winch or tractor beam once it locks on. Stops the part drifting
## and spinning, and stops its lifetime countdown, so the puller has full
## control of its motion until collect().
func begin_reel_in() -> void:
	_being_reeled_in = true
	_velocity = Vector2.ZERO
	_spin = 0.0


func is_drifting() -> bool:
	return not _being_reeled_in


func collect() -> void:
	captured.emit()
	queue_free()

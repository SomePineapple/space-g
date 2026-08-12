class_name CapturedTechPart
extends DriftingHexPiece

## A severed module that stayed intact enough to be worth recovering (see
## WreckageSpawner._roll_capturable). Drifts exactly like ordinary ShipDebris (both share
## DriftingHexPiece), but persists far longer and can be reeled in by
## HardpointWinch/HardpointTractorBeam instead of just fading away — see
## begin_reel_in().
##
## It doesn't describe a module, it *carries* one: the very ModuleInstance that
## was mounted on the hull, with its wear and origin already on it. Whoever
## reels it in asks for that object through release_instance() rather than
## reading fields off this node and rebuilding something equivalent, which is
## both the scene-ownership rule and what keeps the part non-fungible.

signal captured

var _instance: ModuleInstance = null

var _being_reeled_in: bool = false


func _init() -> void:
	# Far longer than ShipDebris': this is a pickup the player has to notice,
	# fly to and reel in, not a one-second visual flourish.
	lifetime = 45.0
	fade_duration = 2.0


func _ready() -> void:
	super._ready()
	add_to_group("capturable_tech")


## The part this piece is, set by WreckageSpawner right after setup(). Kept
## separate from setup() rather than widening it: GDScript requires an override
## to match its base class's signature exactly, and every other
## DriftingHexPiece has no module to carry.
func set_instance(module_instance: ModuleInstance) -> void:
	_instance = module_instance


## Read-only look at the carried part, for a caller that has to decide whether
## it can take it before actually taking it — the hold has to know the part's
## footprint before it can claim cells for it (see Ship.stow_towed_part).
func peek_instance() -> ModuleInstance:
	return _instance


## Hands the carried module over to whatever reeled this piece in, exactly
## once — null if it has already been taken. Callers get the object itself, not
## a description of it.
func release_instance() -> ModuleInstance:
	var released: ModuleInstance = _instance
	_instance = null
	return released


## Stops this part ever ageing out. Used for a part the player deliberately cut
## free (WreckageSpawner.spawn_severed_piece's `clean_cut`): a precise cut is
## already exempt from the capture roll, and a part that survives that roll and
## then evaporates while the player flies over to collect it is the same broken
## promise one step later. Explosively recovered parts keep their timer.
func make_permanent() -> void:
	lifetime = 0.0
	modulate.a = 1.0


## Called by a winch or tractor beam once it locks on. Stops the part drifting
## and spinning, and stops its lifetime countdown, so the puller has full
## control of its motion until collect().
func begin_reel_in() -> void:
	_being_reeled_in = true
	_velocity = Vector2.ZERO
	_spin = 0.0


## Let go: the part drifts again, under its own momentum from wherever it was
## dropped. Used when the player releases a tow rather than stowing it.
func end_reel_in() -> void:
	_being_reeled_in = false


func is_drifting() -> bool:
	return not _being_reeled_in


func collect() -> void:
	captured.emit()
	queue_free()

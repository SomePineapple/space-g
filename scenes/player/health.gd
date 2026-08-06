class_name Health
extends Node

signal health_changed(current: float, max: float)
## Fires only when current_health actually drops. health_changed alone can't
## be used for "was I hit?" — configure() (a ship rebuild) and heal() (module
## regrowth) emit it too — so Ship, HUD and ShipAI each kept their own
## _last_known_health copy to work this out. This is that comparison, done
## once, at the source.
signal damaged(amount: float, current: float)
signal destroyed

@export var max_health: float = 100.0

var current_health: float


func _ready() -> void:
	current_health = max_health


func configure(max_health_value: float) -> void:
	max_health = max_health_value
	current_health = max_health_value
	health_changed.emit(current_health, max_health)


func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return

	var previous: float = current_health
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

	var applied: float = previous - current_health
	if applied > 0.0:
		damaged.emit(applied, current_health)

	if current_health <= 0.0:
		destroyed.emit()


## Mirrors module repair (see HullDamageModel._advance_repair): a holed-out module
## regrowing restores the same amount to the overall Health pool, so a fully
## repaired ship doesn't still carry invisible splash-damage debt from
## before.
func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

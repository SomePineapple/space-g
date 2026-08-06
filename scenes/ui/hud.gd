extends CanvasLayer

## Gameplay HUD root. Owns only the pieces that need ship signals routed to
## them (vitals, credits, damage vignette, storage-full cue) — CargoWidget,
## RadarDisplay and ScannerDisplay each subscribe to their own sources.
## Layout and colours come from docs/HUD-1d-Godot-spec.md via HudPalette.

@export var damage_flash_peak_alpha: float = 0.35
@export var damage_flash_fade_duration: float = 0.35
@export var storage_full_display_duration: float = 1.5
@export var storage_full_fade_duration: float = 0.6
## Held longer than the storage cue: losing a system to a brownout is a state
## change the player has to act on, not a transient "that pickup bounced".
@export var power_warning_display_duration: float = 2.5
@export var power_warning_fade_duration: float = 0.8

@onready var _vitals: Control = $VitalsReadout
@onready var _credits_label: Label = $CreditsLabel
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _storage_full_label: Label = $StorageFullLabel
@onready var _power_warning_label: Label = $PowerWarningLabel

var _damage_flash_tween: Tween
var _storage_full_tween: Tween
var _power_warning_tween: Tween


func _ready() -> void:
	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return

	var inventory: Inventory = ship.get_inventory()
	inventory.storage_full.connect(_on_storage_full)
	inventory.credits_changed.connect(_update_credits_label)
	_update_credits_label(inventory.get_credits())

	# Health readouts and the damage vignette both come off the Ship's own
	# relayed signals now, rather than this panel reaching into the ship scene
	# for its $Health node and re-deriving "was that a hit" itself.
	ship.health_changed.connect(_vitals.set_health)
	ship.damaged.connect(_on_ship_damaged)
	_vitals.set_health(ship.get_current_health(), ship.get_max_health())

	ship.energy_changed.connect(_vitals.set_energy)
	_vitals.set_energy(ship.get_energy(), ship.get_max_energy())

	ship.energy_usage_changed.connect(_vitals.set_power_load)
	ship.get_systems().system_auto_disabled.connect(_on_system_auto_disabled)


func _update_credits_label(amount: int) -> void:
	_credits_label.text = "%s CR" % HudPalette.group_digits(amount)


## Transient "storage full" cue — see Inventory.storage_full, fired whenever
## Salvage pickup gets rejected for lack of cargo space.
func _on_storage_full() -> void:
	if _storage_full_tween:
		_storage_full_tween.kill()
	_storage_full_label.modulate.a = 1.0
	_storage_full_tween = create_tween()
	_storage_full_tween.tween_interval(storage_full_display_duration)
	_storage_full_tween.tween_property(_storage_full_label, "modulate:a", 0.0, storage_full_fade_duration)


## The ship browned out and cut a system by itself (see ShipSystems) — said
## out loud, because a system going quiet with no explanation is exactly the
## confusion power management is supposed to avoid.
func _on_system_auto_disabled(system_id: StringName) -> void:
	_power_warning_label.text = "POWER SHORTAGE — %s OFFLINE" % ShipSystems.DISPLAY_NAMES[system_id]
	if _power_warning_tween:
		_power_warning_tween.kill()
	_power_warning_label.modulate.a = 1.0
	_power_warning_tween = create_tween()
	_power_warning_tween.tween_interval(power_warning_display_duration)
	_power_warning_tween.tween_property(_power_warning_label, "modulate:a", 0.0, power_warning_fade_duration)


## Health.damaged already means "current actually dropped" — a ship rebuild in
## the builder emits health_changed but never this, so the vignette still
## can't be triggered by a refit.
func _on_ship_damaged(_amount: float, _current: float) -> void:
	_flash_damage()


func _flash_damage() -> void:
	if _damage_flash_tween:
		_damage_flash_tween.kill()
	# color.a= on its own doesn't write back (Color is a value type), so the
	# peak alpha has to be set through a full Color reassignment.
	var flash_color: Color = _damage_flash.color
	flash_color.a = damage_flash_peak_alpha
	_damage_flash.color = flash_color
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "color:a", 0.0, damage_flash_fade_duration)

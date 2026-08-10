extends CanvasLayer

## Gameplay HUD root. Owns only the pieces that need ship signals routed to
## them (vitals, credits, damage vignette, storage-full cue) — CargoWidget,
## RadarDisplay and ScannerDisplay each subscribe to their own sources.
## Layout and colours come from docs/HUD-1d-Godot-spec.md via HudPalette.

## Ceiling on the damage vignette. The flash accumulates toward this rather than
## being set to it outright (see _flash_damage) — every hit used to slam the
## overlay straight back to peak and restart the fade, so anything more than one
## attacker held the screen at full red indefinitely, which is when the vignette
## stops being feedback and starts being a blindfold.
@export var damage_flash_peak_alpha: float = 0.34
@export var damage_flash_fade_duration: float = 0.35
## A hit costing this share of max health flashes at full strength; smaller hits
## scale down toward damage_flash_min_alpha. Being clipped by a stray laser and
## being hit by a missile should not look identical.
@export var damage_flash_full_hit_health_fraction: float = 0.2
## Floor, so even a graze still registers as "that hit me". Deliberately near the
## threshold of visibility: one laser bolt from a light pirate is the most common
## event in the game and must not wash the screen.
@export var damage_flash_min_alpha: float = 0.05
@export var storage_full_display_duration: float = 1.5
@export var storage_full_fade_duration: float = 0.6
## Held longer than the storage cue: losing a system to a brownout is a state
## change the player has to act on, not a transient "that pickup bounced".
@export var power_warning_display_duration: float = 2.5
@export var power_warning_fade_duration: float = 0.8

## Phase 0a freeze — see docs/frozen_systems.md. With the exchange frozen there
## is nothing that earns or spends credits, so the readout is a permanently
## static number occupying the top-right corner. Hidden rather than deleted;
## flip to false to bring it (and the HUD spec's element 4) back.
const CREDITS_FROZEN: bool = true

@onready var _vitals: Control = $VitalsReadout
@onready var _credits_label: Label = $CreditsLabel
## An edge vignette, not a full-screen wash: a radial gradient that is fully
## transparent across the middle of the screen and only reaches full strength at
## the frame. A flat rect over the whole viewport dimmed the one place the player
## is actually looking, which made even a light hit feel blinding — this can be
## brighter at the border while obscuring less.
@onready var _damage_flash: TextureRect = $DamageFlash
@onready var _storage_full_label: Label = $StorageFullLabel
@onready var _power_warning_label: Label = $PowerWarningLabel

var _ship: Ship
var _damage_flash_tween: Tween
var _storage_full_tween: Tween
var _power_warning_tween: Tween


func _ready() -> void:
	_credits_label.visible = not CREDITS_FROZEN

	var ship: Ship = PlayerContext.get_ship()
	if ship == null:
		return
	# Kept because the damage vignette scales each flash against the ship's
	# current max health, which changes with the hull's layout.
	_ship = ship

	var inventory: Inventory = ship.get_inventory()
	inventory.storage_full.connect(_on_storage_full)
	if not CREDITS_FROZEN:
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
func _on_ship_damaged(amount: float, _current: float) -> void:
	_flash_damage(amount)


## Adds to whatever is already on screen instead of replacing it, and scales the
## addition by how hard the hit was.
##
## Both halves matter under fire from several ships at once. Scaling stops a
## stream of chip damage from looking like a killing blow; accumulating (rather
## than resetting to peak) means those hits build a low, steady tint that still
## drains between volleys, instead of every single one re-arming the overlay at
## maximum and the fade never getting anywhere.
func _flash_damage(amount: float) -> void:
	if _damage_flash_tween:
		_damage_flash_tween.kill()

	var severity: float = 1.0
	var max_health: float = _ship.get_max_health() if _ship != null else 0.0
	if max_health > 0.0 and damage_flash_full_hit_health_fraction > 0.0:
		severity = clampf(
			(amount / max_health) / damage_flash_full_hit_health_fraction, 0.0, 1.0)
	var added: float = lerpf(damage_flash_min_alpha, damage_flash_peak_alpha, severity)

	# The red lives in the gradient texture; intensity is carried by modulate, so
	# alpha is the only thing this touches.
	_damage_flash.modulate.a = minf(_damage_flash.modulate.a + added, damage_flash_peak_alpha)
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "modulate:a", 0.0, damage_flash_fade_duration)

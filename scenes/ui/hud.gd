extends CanvasLayer

@export var damage_flash_peak_alpha: float = 0.35
@export var damage_flash_fade_duration: float = 0.35

@onready var _salvage_label: Label = $SalvageLabel
@onready var _health_label: Label = $HealthLabel
@onready var _energy_label: Label = $EnergyLabel
@onready var _credits_label: Label = $CreditsLabel
@onready var _damage_flash: ColorRect = $DamageFlash

var _inventory: Inventory
var _health: Health
var _last_known_health: float = -1.0
var _damage_flash_tween: Tween


func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_inventory = players[0].get_node("Inventory")
	_inventory.materials_changed.connect(_on_materials_changed)
	_update_salvage_label(_inventory.get_all_materials())
	_inventory.credits_changed.connect(_on_credits_changed)
	_update_credits_label(_inventory.get_credits())

	_health = players[0].get_node("Health")
	_health.health_changed.connect(_on_health_changed)
	_update_health_label(_health.current_health, _health.max_health)

	var ship: Ship = players[0]
	ship.energy_changed.connect(_on_energy_changed)
	_update_energy_label(ship.current_energy, ship.max_energy)


func _on_materials_changed(totals: Dictionary) -> void:
	_update_salvage_label(totals)


func _on_credits_changed(amount: int) -> void:
	_update_credits_label(amount)


func _update_credits_label(amount: int) -> void:
	_credits_label.text = "Credits: %d" % amount


func _update_salvage_label(totals: Dictionary) -> void:
	var parts: Array = []
	for material_id in [Materials.STEEL_ALLOY, Materials.ELECTRONICS, Materials.REACTOR_COMPONENTS]:
		var amount: int = totals.get(material_id, 0)
		parts.append("%s: %d" % [Materials.display_name(material_id), amount])
	_salvage_label.text = "  |  ".join(parts)


## Only current < last-known counts as damage — a ship rebuild in the
## builder also emits health_changed, but resets to full health rather
## than lowering it, so it never triggers the flash.
func _on_health_changed(current: float, max_health: float) -> void:
	_update_health_label(current, max_health)

	var took_damage: bool = _last_known_health >= 0.0 and current < _last_known_health
	_last_known_health = current
	if took_damage:
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


func _update_health_label(current: float, max_health: float) -> void:
	_health_label.text = "Health: %d / %d" % [current, max_health]


func _on_energy_changed(current: float, max_energy: float) -> void:
	_update_energy_label(current, max_energy)


func _update_energy_label(current: float, max_energy: float) -> void:
	_energy_label.text = "Energy: %d / %d" % [current, max_energy]

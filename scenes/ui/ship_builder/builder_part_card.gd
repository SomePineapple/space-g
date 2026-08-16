class_name BuilderPartCard
extends PanelContainer

## The identity readout for one specific part, shown in the ship builder's right
## column: what it is, its serial, how beaten up it is, what it has killed, and
## where it came from.
##
## Deliberately about *this object* rather than about its type. The whole design
## thesis is that a mounted module is not "a railgun", it is **this** railgun
## (see docs/direction.md §1), and until now the only place that showed was a
## one-line status message at the top of the screen that the next action
## overwrote. A part with a serial, a dent and a body count deserves somewhere to
## say so.
##
## Fed by ShipBuilderPanel from two places — a part picked out of the hold, and a
## part already bolted to the hull — so the same card answers "what am I about to
## place" and "what is already there".
##
## Sits over the top-left of the build field rather than in the right column, so
## it reads against the hull it describes instead of against the parts list.
## Deliberately narrow and quiet: it overlays the field, so it has to stay out of
## the way of the hull being edited.

## Performance numbers are quoted for *this* part in its current state — wear
## included — but with no hull bonuses applied. Where a gun ends up matters
## (HardpointGun.apply_core_distance_bonus pays out to half again for a weapon
## mounted far from the Core), and that is a property of the hull design rather
## than of the part being inspected.
const PERFORMANCE_NOTE: String = "this part, at its current wear"
## Shown instead when the part is unworn, so the numbers are not silently read as
## already-degraded ones.
const PERFORMANCE_NOTE_INTACT: String = "at full condition"

## Fixed, because the card floats over the build field instead of being sized by
## a column — long part names wrap at this width rather than stretching the card
## across the hull.
const CARD_WIDTH: float = 248.0

## Which hardpoint categories are worth quoting damage numbers for.
const WEAPON_CATEGORIES: Array[String] = ["weapon", "missile"]

var _name_label: Label
var _serial_label: Label
var _stats: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", BuilderTheme.padded(BuilderTheme.card_style(), 11.0, 9.0))
	custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	_name_label = BuilderTheme.mono_label("", 16, BuilderTheme.TEXT_BRIGHT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_name_label)

	_serial_label = BuilderTheme.mono_label("", 10, BuilderTheme.TEXT_HINT)
	column.add_child(_serial_label)

	# Sits below the serial with a gap, so the identity block reads as a heading
	# and the numbers below it as a body.
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 3)
	column.add_child(_spacer(6))
	column.add_child(_stats)

	_empty_label = BuilderTheme.mono_label(
		"No part selected.", 11, BuilderTheme.TEXT_HINT)
	column.add_child(_empty_label)

	clear()


static func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func clear() -> void:
	_name_label.visible = false
	_serial_label.visible = false
	_stats.visible = false
	_empty_label.visible = true
	_clear_stats()


## `instance` may be null for a placement whose part has already been handed over
## to the wreckage; the module type alone is then all there is to show.
func show_instance(instance: ModuleInstance, module_type_id: String = "") -> void:
	if instance == null:
		if module_type_id.is_empty():
			clear()
			return
		_show_type_only(module_type_id)
		return

	_name_label.text = instance.display_name()
	_serial_label.text = instance.serial
	_name_label.visible = true
	_serial_label.visible = true
	_empty_label.visible = false
	_stats.visible = true

	_clear_stats()
	_add_stat("Condition", "%d%%" % roundi(instance.condition_fraction * 100.0),
		_condition_color(instance.condition_fraction))
	_add_integrity(instance)
	_add_mount(instance)
	_add_efficiency(instance)
	_add_stat("Kills", str(instance.kill_count))
	_add_weapon_stats(instance)
	_add_output_stats(instance)
	_add_origin(instance)


## How much life the part has permanently left — the ceiling repair can restore
## it to (see ModuleInstance.integrity). Shown right under Condition, because the
## pair is the whole story: what is wrong with it now, and how much of that will
## never come back.
##
## Hidden on a factory-fresh part, like Efficiency, so the rows only appear once
## they mean something.
func _add_integrity(instance: ModuleInstance) -> void:
	if instance.integrity >= 1.0:
		return
	_add_stat("Integrity", "%d%%" % roundi(instance.integrity * 100.0),
		_condition_color(instance.integrity))


## How this part is bolted on, shown only when that is costing it something.
##
## Two different states, and the difference between them is the whole mechanic:
## a live field rig is recoverable — fly home, unbolt, bolt it back on — while
## the cap it leaves behind is not. The first says what to do about it; the
## second is there so the player can see, on a part that is already back at full
## condition, why it still is not pulling its full weight.
##
## Sits directly above Efficiency, which is where the two halves of that number
## (wear, mount) are already listed in the order they are explained.
func _add_mount(instance: ModuleInstance) -> void:
	if instance.field_attached:
		_add_stat("Mount", "FIELD RIG · %d%%" % roundi(instance.mount_efficiency() * 100.0),
			BuilderTheme.WARN)
		_add_note("Jury-rigged in open space. A dock will get it back to %d%% — no further."
			% roundi(instance.mount_efficiency_ceiling() * 100.0), BuilderTheme.WARN)
		return
	if instance.ever_field_attached:
		_add_stat("Mount", "REFITTED · %d%%" % roundi(instance.mount_efficiency() * 100.0),
			BuilderTheme.AMBER)
		_add_note("Cut on in the field once. The mounting points never came back true.",
			BuilderTheme.AMBER)


## Condition says how beaten up a part is; efficiency says what that costs. They
## are not the same number (see ModuleInstance.efficiency — light wear costs
## nothing at all), and showing only the first left the player to guess the
## conversion.
##
## Hidden when a part is working perfectly: a row reading "100%" on every intact
## part is noise, and its absence is what makes it worth reading when it appears.
func _add_efficiency(instance: ModuleInstance) -> void:
	var efficiency: float = instance.efficiency()
	if efficiency >= 1.0:
		return
	# Coloured by condition, not by the number itself, so the row keeps meaning
	# "how hurt is this part" — except when a mount is dragging it down, which is
	# worth flagging regardless of how clean the part underneath is.
	var color: Color = _condition_color(instance.condition_fraction)
	if instance.field_attached:
		color = BuilderTheme.WARN
	elif instance.ever_field_attached:
		color = BuilderTheme.AMBER
	_add_stat("Efficiency", "%d%%" % roundi(efficiency * 100.0), color)


func _show_type_only(module_type_id: String) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	_name_label.text = module_type.display_name if module_type != null else module_type_id
	_name_label.visible = true
	_serial_label.visible = false
	_empty_label.visible = false
	_stats.visible = false
	_clear_stats()


## Damage-per-second and rate of fire, for a part that actually shoots. Both are
## read off a throwaway instance of the module's own hardpoint scene with its
## tier and manufacturer modifiers applied, rather than from a table kept
## alongside — a second copy of these numbers would drift the first time a
## weapon was retuned.
##
## Silent for anything that is not a weapon, so the card does not sprout an empty
## "DPS —" row on a reactor.
func _add_weapon_stats(instance: ModuleInstance) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(instance.module_type_id)
	if module_type == null or not WEAPON_CATEGORIES.has(module_type.hardpoint_category):
		return

	var probe: Node = _probe_hardpoint(module_type, instance.manufacturer_id)
	if probe == null:
		return
	var fire_rate: float = probe.fire_rate
	var damage: float = probe.projectile_damage
	probe.free()

	if fire_rate <= 0.0:
		return
	# DPS is efficiency applied once and nothing else, so the headline number on
	# this card and the number in the fight are the same claim. Rate of fire takes
	# the gentler share of that (HardpointGun.FIRE_RATE_WEAR_SHARE) and damage
	# makes up the difference, which is why the two rows do not scale together.
	var efficiency: float = instance.efficiency()
	_add_stat("DPS", "%.1f" % (damage * fire_rate * efficiency))
	_add_stat("Fire rate", "%.2f/s" % (fire_rate * HardpointGun.fire_rate_factor(efficiency)))
	_add_note(PERFORMANCE_NOTE if efficiency < 1.0 else PERFORMANCE_NOTE_INTACT)


## An unparented, never-readied hardpoint node used purely to read its stats.
## _init() runs on instantiate (which is where HardpointMissileLauncher and the
## charged weapons set their own defaults) but _ready() does not, so nothing is
## spawned, aimed or wired up by asking.
func _probe_hardpoint(module_type: ModuleType, manufacturer_id: String) -> Node:
	var scene: PackedScene = module_type.hardpoint_scene
	if scene == null:
		scene = preload("res://scenes/player/hardpoint_gun.tscn")
	var probe: Node = scene.instantiate()
	if not ("fire_rate" in probe and "projectile_damage" in probe):
		probe.free()
		return null
	probe.apply_tier(module_type.tier)
	var manufacturer: Manufacturer = ManufacturerCatalog.get_by_id(manufacturer_id)
	if manufacturer != null:
		# The same additive-delta rule a real mount applies, called rather than
		# reimplemented so the card cannot disagree with the gun.
		HardpointBank.apply_modifiers(probe, manufacturer.stat_modifiers)
	return probe


## What a non-weapon part contributes, after wear. Wear means something different
## for each of these — a thruster pushes softer, a reactor makes less power, a
## battery holds less charge — but it is the same one efficiency figure behind
## all three, so they are quoted the same way.
##
## Base rates only: the core-distance multiplier that reactors and batteries also
## carry (see ShipLayout._core_distance_energy_multiplier) depends on where the
## part is bolted, which is a fact about the hull rather than about the part.
func _add_output_stats(instance: ModuleInstance) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(instance.module_type_id)
	if module_type == null:
		return

	var efficiency: float = instance.efficiency()
	var quoted: bool = false
	quoted = _add_output("Thrust", module_type.thrust_contribution, efficiency, "%.0f") or quoted
	quoted = _add_output("Output", module_type.energy_generation, efficiency, "%.1f/s") or quoted
	quoted = _add_output("Capacity", module_type.energy_capacity_contribution, efficiency, "%.0f") or quoted
	if quoted:
		_add_note(PERFORMANCE_NOTE if efficiency < 1.0 else PERFORMANCE_NOTE_INTACT)


## Returns whether the row was worth showing at all, so a part that contributes
## nothing here (a plain hull plate) does not get a trailing performance note
## attached to no numbers.
func _add_output(label: String, base: float, efficiency: float, format: String) -> bool:
	if base <= 0.0:
		return false
	_add_stat(label, format % (base * efficiency))
	return true


func _add_origin(instance: ModuleInstance) -> void:
	if instance.is_salvaged():
		_add_note(instance.origin_description, BuilderTheme.AMBER)
		return
	_add_note("Fabricated — no combat history")


func _add_stat(label: String, value: String, value_color: Color = BuilderTheme.TEXT_BRIGHT) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label: Label = BuilderTheme.mono_label(label, 11, BuilderTheme.TEXT_LABEL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(BuilderTheme.mono_label(value, 11, value_color))
	_stats.add_child(row)


func _add_note(text: String, color: Color = BuilderTheme.TEXT_HINT) -> void:
	var note: Label = BuilderTheme.mono_label(text, 10, color)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_child(_spacer(4))
	_stats.add_child(note)


func _clear_stats() -> void:
	for child in _stats.get_children():
		child.queue_free()
		_stats.remove_child(child)


static func _condition_color(fraction: float) -> Color:
	# Matches HullPaint.CUTTABLE_CONDITION: below 30% a part is soft enough for a
	# Slicer to cut free, which is worth seeing before a fight rather than after.
	if fraction < HullPaint.CUTTABLE_CONDITION:
		return BuilderTheme.WARN
	if fraction < 0.7:
		return BuilderTheme.AMBER
	return BuilderTheme.HEALTH_GOOD

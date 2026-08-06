class_name BuilderStatStrip
extends PanelContainer

## Top-left HP / MASS / EN / CARGO readout on the ship-builder screen
## (handoff README "Top HUD"). Shows what the working layout *would* give the
## ship, not the ship's current live values.

const DOT_SIZE: float = 6.0
const LABEL_FONT_SIZE: int = 10
const VALUE_FONT_SIZE: int = 12
const ENTRY_SEPARATION: int = 22

var _health_dot: Panel
var _health_value: Label
var _mass_value: Label
var _energy_value: Label
var _cargo_value: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.with_alpha(BuilderTheme.GLASS, 0.5),
			BuilderTheme.with_alpha(BuilderTheme.CYAN, 0.22), BuilderTheme.RADIUS_MEDIUM),
		16.0, 9.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ENTRY_SEPARATION)
	add_child(row)

	_health_dot = BuilderTheme.make_glow_dot(BuilderTheme.HEALTH_GOOD, DOT_SIZE)
	_health_value = _add_entry(row, "HP", _health_dot)
	row.add_child(BuilderTheme.make_divider())
	_mass_value = _add_entry(row, "MASS", null)
	row.add_child(BuilderTheme.make_divider())
	_energy_value = _add_entry(row, "EN", BuilderTheme.make_glow_dot(BuilderTheme.CYAN, DOT_SIZE))
	row.add_child(BuilderTheme.make_divider())
	_cargo_value = _add_entry(row, "CARGO", null)


func _add_entry(row: HBoxContainer, label_text: String, dot: Panel) -> Label:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 7)
	row.add_child(entry)

	if dot != null:
		entry.add_child(dot)

	var label: Label = BuilderTheme.mono_label(label_text, LABEL_FONT_SIZE, BuilderTheme.TEXT_LABEL)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_child(label)

	var value: Label = BuilderTheme.mono_label("—", VALUE_FONT_SIZE, BuilderTheme.TEXT_BRIGHT)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_child(value)
	return value


## health_fraction only tints the HP dot (green / amber / red) — the builder
## has no live damage to show, but a layout applied to a damaged ship still
## reads correctly.
func set_stats(max_health: float, health_fraction: float, mass: float,
		energy_generation: float, energy_capacity: float,
		cargo_used: int, cargo_capacity: float) -> void:
	_health_value.text = str(int(roundf(max_health)))
	BuilderTheme.set_dot_color(_health_dot, _health_color(health_fraction))
	_mass_value.text = "%.2f" % mass
	_energy_value.text = "+%.0f/s  cap %.0f" % [energy_generation, energy_capacity]
	_cargo_value.text = "%d/%.0f" % [cargo_used, cargo_capacity]


func _health_color(fraction: float) -> Color:
	if fraction > 0.5:
		return BuilderTheme.HEALTH_GOOD
	if fraction > 0.2:
		return BuilderTheme.AMBER
	return BuilderTheme.WARN

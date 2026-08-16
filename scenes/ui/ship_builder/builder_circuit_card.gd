class_name BuilderCircuitCard
extends PanelContainer

## The ship's circuits, one row each: colour, what its reactor makes, and what
## everything assigned to it would draw with all of it running at once.
##
## The question this card exists to answer is the one the player can only answer
## *here*, before undocking: "can this circuit carry what I have hung off it".
## It is measured against potential draw rather than live usage on purpose — a
## circuit that copes while you cruise and dies the moment you fire everything at
## once is exactly the mistake the builder should catch, and the fight is a bad
## place to find out.
##
## Rows are colour-matched to the hexes on the grid (see CircuitPalette), so
## "the amber circuit" means the same thing in both places.

const CARD_WIDTH: float = 248.0
const LABEL_FONT_SIZE: int = 10
const VALUE_FONT_SIZE: int = 12
const DOT_SIZE: float = 8.0

## Shown in place of the rows when the hull has no reactor at all. A warning
## rather than an error: with the Command Core generating a trickle of its own
## (see ModuleCatalog.CORE_GENERATION) such a ship does fly — badly — and telling
## the player it is broken when it demonstrably works would teach them to
## distrust the readout.
const NO_REACTOR_TEXT: String = "NO REACTOR — running on core power. Everything will be slow."

var _rows_box: VBoxContainer
var _notice: Label


func _ready() -> void:
	custom_minimum_size.x = CARD_WIDTH
	add_theme_stylebox_override("panel", BuilderTheme.padded(
		BuilderTheme.card_style(), 12.0, 10.0))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var heading: Label = BuilderTheme.mono_label("CIRCUITS", LABEL_FONT_SIZE, BuilderTheme.TEXT_LABEL)
	column.add_child(heading)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	column.add_child(_rows_box)

	_notice = BuilderTheme.mono_label("", LABEL_FONT_SIZE, BuilderTheme.WARN_TEXT)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = CARD_WIDTH - 24.0
	column.add_child(_notice)


## `focused_circuit_id` is the circuit the player currently has selected on the
## grid, brightened here so the two halves of the screen agree about which one is
## being edited.
func refresh(layout: ShipLayout, focused_circuit_id: String) -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()

	var circuit_ids: Array[String] = layout.get_circuit_ids()
	for index in circuit_ids.size():
		_rows_box.add_child(_build_row(layout, circuit_ids[index], index, focused_circuit_id))

	_notice.text = NO_REACTOR_TEXT if layout.get_assignable_circuit_ids().is_empty() else ""
	_notice.visible = not _notice.text.is_empty()


func _build_row(layout: ShipLayout, circuit_id: String, index: int,
		focused_circuit_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var tint: Color = CircuitPalette.color_for(index)
	var focused: bool = circuit_id == focused_circuit_id
	row.add_child(BuilderTheme.make_glow_dot(
		tint if focused else BuilderTheme.with_alpha(tint, 0.55), DOT_SIZE))

	var generation: float = layout.circuit_generation(circuit_id)
	var draw: float = layout.circuit_draw(circuit_id)
	var name_text: String = "CORE" if not layout.circuit_accepts_members(circuit_id) \
		else "CIRCUIT %d" % index
	var name_label: Label = BuilderTheme.mono_label(name_text, LABEL_FONT_SIZE,
		BuilderTheme.TEXT_BRIGHT if focused else BuilderTheme.TEXT_MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Over-commitment is stated as the comparison rather than as a separate
	# warning line, because the two numbers *are* the warning — a player who can
	# see 18/24 does not need to be told which way round it goes.
	var over: bool = draw > generation
	var value: Label = BuilderTheme.mono_label("%.0f/%.0f" % [draw, generation], VALUE_FONT_SIZE,
		BuilderTheme.WARN_TEXT if over else BuilderTheme.TEXT_BODY)
	row.add_child(value)
	return row

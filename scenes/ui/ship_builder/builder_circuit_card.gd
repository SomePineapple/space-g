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
## Rows are colour-matched to the hexes on the grid (see CircuitPalette) and named
## by the layout (ShipLayout.circuit_display_name), so "CIRCUIT 1" and "the amber
## one" both mean the same thing here, on the hull, and on the HUD in flight.
##
## Only visible while the builder is in energy mode — it is that mode's readout,
## not a permanent fixture (see ShipBuilderPanel._on_energy_toggled).

signal split_by_role_requested

const CARD_WIDTH: float = 248.0
const LABEL_FONT_SIZE: int = 10
const VALUE_FONT_SIZE: int = 12
const DOT_SIZE: float = 8.0

## Shown when the hull has no reactor at all. A warning rather than an error: with
## the Command Core generating a trickle of its own (see
## ModuleCatalog.CORE_GENERATION) such a ship does fly — badly — and telling the
## player it is broken when it demonstrably works would teach them to distrust the
## readout.
const NO_REACTOR_TEXT: String = "NO REACTOR — running on core power. Everything will be slow."

## The next step, which changes depending on whether a circuit is armed.
##
## Two lines rather than one static instruction because the interaction has two
## states and the useless half of a static line is what players learn to stop
## reading. Before arming, the only useful thing to say is how to arm; after, the
## only useful thing is what the armed circuit will now do — named, so there is no
## doubt about which one is listening.
const HINT_PICK: String = "Click a reactor on the hull to pick its circuit."
const HINT_ASSIGN_FORMAT: String = "Click modules to move them onto %s. Click it again to finish."

var _rows_box: VBoxContainer
var _notice: Label
var _hint: Label


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

	column.add_child(_make_rule())

	_hint = BuilderTheme.mono_label(HINT_PICK, LABEL_FONT_SIZE, BuilderTheme.TEXT_HINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = CARD_WIDTH - 24.0
	column.add_child(_hint)

	# The preset lives here rather than in the bottom bar with the layout actions:
	# it acts on circuits, and a button that only means anything in this mode
	# should only be reachable in this mode.
	var split_button := Button.new()
	split_button.text = "SPLIT BY ROLE"
	split_button.tooltip_text = \
		"Puts propulsion, weapons and everything else on separate reactors."
	split_button.focus_mode = Control.FOCUS_NONE
	split_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	BuilderTheme.style_button(split_button, BuilderTheme.AMBER, BuilderTheme.TEXT_MUTED,
		BuilderTheme.TEXT_BRIGHT, 11, 12.0, 8.0)
	split_button.pressed.connect(split_by_role_requested.emit)
	column.add_child(split_button)


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

	_hint.text = HINT_PICK if focused_circuit_id.is_empty() \
		else HINT_ASSIGN_FORMAT % layout.circuit_display_name(focused_circuit_id)


## 1px horizontal hairline separating the readout from the controls under it.
## BuilderTheme.make_divider() is the stat strip's *vertical* equivalent and
## renders as a sliver in a column, so this is its own thing rather than a
## parameter on that.
func _make_rule() -> Panel:
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override("panel",
		BuilderTheme.flat_style(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0))
	return rule


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
	# Named by the layout, not here — the in-flight HUD reports the same circuits
	# and the two labels have to be the same words (see
	# ShipLayout.circuit_display_name).
	var name_label: Label = BuilderTheme.mono_label(
		layout.circuit_display_name(circuit_id), LABEL_FONT_SIZE,
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

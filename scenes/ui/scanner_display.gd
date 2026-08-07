extends Control

## The scanner instrument panel — the column the A-scope sits in
## (docs/design_handoff_scanner_radar/README.md, option 1D): header, display,
## control row with the PING button and its two readouts, and the returns list
## that fills in as the wavefront reaches each contact.
##
## Deliberately separate from RadarDisplay: radar is live broad detection and
## never shows identity, this is one deliberate pulse that does.
##
## Shown/hidden rather than always on, because at 360x540 the column is too
## large to co-exist with the rest of the HUD. Pressing "scan" opens it (and,
## if the emitter is ready, fires the same press as a ping through the usual
## ShipIntent path); the X button or Escape closes it. It also hides itself
## whenever the ship has no working scanner, checked live every frame the same
## way RadarDisplay does.

const GAP: int = 12
## Breathing room between the backdrop's edge and the column inside it.
const PADDING: int = 14
const HEADER_HEIGHT: float = 20.0
const CONTROL_HEIGHT: float = 28.0
const LIST_MIN_HEIGHT: float = 96.0
const ROW_FADE_DURATION: float = 0.22

const STATUS_IDLE: String = "IDLE — drag the beam bar, then PING"
const STATUS_TRANSMITTING: String = "TRANSMITTING…"
const STATUS_EMPTY: String = "NOISE ONLY — NO RETURN"

## Verbatim from the prototype's help card.
const HELP_LINES: Array[String] = [
	"[color=#f2c14e]BEAM BAR[/color] — drag the band to aim, drag the amber arrows to narrow the beam. Narrow beam = higher gain = cleaner trace, further reach.",
	"[color=#e0ffec]TRANSMIT LINE[/color] — the bright vertical line walking right is the pulse travelling out. 1000 units per second.",
	"[color=#7ee0a0]PEAKS[/color] — a return. Taller = stronger signal (wrecks read loudest, rock quietest). Peaks smear wider the further out they sit, so distant contacts are vague.",
	"[color=#6b7784]NOISE FLOOR[/color] — the jitter beneath. It grows with distance; anything not clearing it is not a contact.",
	"[color=#4c5a66]Horizontal axis is RANGE, not position. Bearing comes from where you pointed the beam.[/color]",
]

var _ship: Ship
var _scanner: Scanner
var _scope: ScannerScope
var _fire_button: Button
var _beam_readout: Label
var _gain_readout: Label
var _rows: VBoxContainer
var _status: Label
var _help_card: PanelContainer
var _is_open: bool = false
## Last cooldown value pushed to the button, so the label is only rewritten
## when its one-decimal reading actually changes.
var _shown_cooldown: float = -1.0


func _ready() -> void:
	_ship = PlayerContext.get_ship()
	if _ship == null:
		return

	_scanner = _ship.get_scanner()
	_scanner.scan_started.connect(_on_scan_started)
	_scanner.contact_resolved.connect(_on_contact_resolved)
	_scanner.scan_completed.connect(_on_scan_completed)
	_scanner.scan_cancelled.connect(_on_scan_cancelled)
	_scanner.beam_changed.connect(_on_beam_changed)

	_build_ui()
	_scope.set_scanner(_scanner)
	_on_beam_changed(_scanner.get_beam_bearing(), _scanner.get_beam_width())
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _scanner == null:
		return
	if event.is_action_pressed("scan") and not _is_menu_open():
		_is_open = true
	elif event.is_action_pressed("ui_cancel") and _is_open:
		_is_open = false
		accept_event()


## Same rule ship_input uses: an open builder/upgrade panel owns the keyboard,
## so V there must not pop the scanner up behind it.
func _is_menu_open() -> bool:
	for panel in get_tree().get_nodes_in_group("menu_panel"):
		if panel.visible:
			return true
	return false


func _process(_delta: float) -> void:
	if _ship == null:
		return

	visible = _is_open and _ship.has_scanner()
	if not visible:
		return

	_update_fire_button()
	_scope.queue_redraw()


# --- Construction ------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var total_height: float = HEADER_HEIGHT + ScannerPalette.SCOPE_SIZE + CONTROL_HEIGHT \
			+ LIST_MIN_HEIGHT + GAP * 3 + PADDING * 2
	var total_width: float = ScannerPalette.COLUMN_WIDTH + PADDING * 2
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -(total_width + HudPalette.CORNER_MARGIN)
	offset_right = -HudPalette.CORNER_MARGIN
	offset_top = -total_height * 0.5
	offset_bottom = total_height * 0.5

	# The handoff's column sits on the page background; in-game it sits over the
	# starfield, so it gets its own backdrop — without one the header, readouts
	# and returns rows are unreadable against whatever is behind them.
	var backdrop := Panel.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", ScannerPalette.flat_style(
			ScannerPalette.with_alpha(ScannerPalette.BACKDROP, 0.92),
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.16), 8))
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, PADDING)
	column.add_theme_constant_override("separation", GAP)
	add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_display())
	column.add_child(_build_controls())
	column.add_child(_build_returns())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, HEADER_HEIGHT)
	header.add_theme_constant_override("separation", 10)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", ScannerPalette.padded_style())
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(ScannerPalette.mono_label("SCAN", ScannerPalette.FONT_SIZE_READOUT,
			ScannerPalette.BACKDROP))
	header.add_child(badge)

	var title := Label.new()
	title.text = "Return trace"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", ScannerPalette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.custom_minimum_size = Vector2(20.0, 20.0)
	close.add_theme_font_override("font", ScannerPalette.mono_font())
	close.add_theme_font_size_override("font_size", ScannerPalette.FONT_SIZE_READOUT)
	close.add_theme_color_override("font_color", ScannerPalette.TEXT_DIM)
	close.add_theme_color_override("font_hover_color", ScannerPalette.ACCENT)
	close.pressed.connect(func(): _is_open = false)
	header.add_child(close)
	return header


func _build_display() -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(ScannerPalette.COLUMN_WIDTH, ScannerPalette.SCOPE_SIZE)
	frame.add_theme_stylebox_override("panel", ScannerPalette.flat_style(
			ScannerPalette.PANEL_FILL,
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.16), 8))

	_scope = ScannerScope.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(_scope)

	var help_toggle := Button.new()
	help_toggle.text = "?"
	help_toggle.position = Vector2(ScannerPalette.SCOPE_SIZE - 28.0, 8.0)
	help_toggle.size = Vector2(20.0, 20.0)
	help_toggle.add_theme_font_override("font", ScannerPalette.mono_font())
	help_toggle.add_theme_font_size_override("font_size", ScannerPalette.FONT_SIZE_READOUT)
	help_toggle.add_theme_color_override("font_color", ScannerPalette.ACCENT)
	help_toggle.add_theme_stylebox_override("normal", ScannerPalette.flat_style(
			Color.TRANSPARENT, ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.4), 10))
	help_toggle.add_theme_stylebox_override("hover", ScannerPalette.flat_style(
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.15),
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.4), 10))
	help_toggle.add_theme_stylebox_override("pressed", ScannerPalette.flat_style(
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.25),
			ScannerPalette.with_alpha(ScannerPalette.ACCENT, 0.4), 10))
	help_toggle.pressed.connect(func(): _help_card.visible = not _help_card.visible)
	frame.add_child(help_toggle)

	_help_card = _build_help_card()
	frame.add_child(_help_card)
	return frame


func _build_help_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.visible = false
	card.add_theme_stylebox_override("panel",
			ScannerPalette.padded_style(ScannerPalette.HELP_FILL, Color.TRANSPARENT, 8, 18.0))

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 11)
	card.add_child(lines)

	lines.add_child(ScannerPalette.mono_label("SCOPE — HOW TO READ",
			ScannerPalette.FONT_SIZE_READOUT, ScannerPalette.ACCENT))
	for line in HELP_LINES:
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.text = line
		text.fit_content = true
		text.scroll_active = false
		text.add_theme_font_override("normal_font", ScannerPalette.mono_font())
		text.add_theme_font_size_override("normal_font_size", ScannerPalette.FONT_SIZE_READOUT)
		text.add_theme_color_override("default_color", ScannerPalette.HELP_TEXT)
		lines.add_child(text)

	var close := Button.new()
	close.text = "CLOSE"
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ScannerPalette.style_fire_button(close, ScannerPalette.ACCENT, ScannerPalette.BACKDROP)
	close.pressed.connect(func(): _help_card.visible = false)
	lines.add_child(close)
	return card


func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, CONTROL_HEIGHT)
	row.add_theme_constant_override("separation", GAP)

	_fire_button = Button.new()
	_fire_button.text = "PING"
	_fire_button.custom_minimum_size = Vector2(96.0, 0.0)
	ScannerPalette.style_fire_button(_fire_button, ScannerPalette.ACCENT, ScannerPalette.BACKDROP)
	_fire_button.pressed.connect(func(): _scanner.fire_ping())
	row.add_child(_fire_button)

	_beam_readout = ScannerPalette.mono_label("BEAM 40°", ScannerPalette.FONT_SIZE_READOUT,
			ScannerPalette.ACCENT)
	_beam_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_beam_readout)

	_gain_readout = ScannerPalette.mono_label("GAIN 50dB", ScannerPalette.FONT_SIZE_READOUT,
			ScannerPalette.TEXT_DIM)
	_gain_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_gain_readout)
	return row


func _build_returns() -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(ScannerPalette.COLUMN_WIDTH, LIST_MIN_HEIGHT)
	frame.add_theme_stylebox_override("panel", ScannerPalette.top_rule_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	column.add_child(_rows)

	_status = ScannerPalette.mono_label(STATUS_IDLE, ScannerPalette.FONT_SIZE_ROW,
			ScannerPalette.TEXT_STATUS)
	column.add_child(_status)
	return frame


# --- Scanner signals ---------------------------------------------------------

func _on_scan_started() -> void:
	_is_open = true
	for row in _rows.get_children():
		row.queue_free()
	_status.text = STATUS_TRANSMITTING
	_status.visible = true


## One row per return, appended as the wavefront reaches it rather than all at
## once when the pulse finishes.
func _on_contact_resolved(contact: Dictionary) -> void:
	_status.visible = false
	_rows.add_child(_build_row(_rows.get_child_count() + 1, contact))


func _on_scan_completed(results: Array[Dictionary]) -> void:
	if results.is_empty():
		_status.text = STATUS_EMPTY
		_status.visible = true


func _on_scan_cancelled() -> void:
	if _rows.get_child_count() == 0:
		_status.text = STATUS_IDLE
		_status.visible = true


## Bearing is shown on the scope's own bar readout, so the control row only
## mirrors the width and the gain derived from it.
func _on_beam_changed(_bearing_degrees: float, width_degrees: float) -> void:
	_beam_readout.text = "BEAM %d°" % roundi(width_degrees)
	# Narrower beam reads as higher gain, per the handoff's formula.
	_gain_readout.text = "GAIN %ddB" % roundi(60.0 - width_degrees * 0.25)


# --- Returns list ------------------------------------------------------------

func _build_row(index: int, contact: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var number := ScannerPalette.mono_label(str(index), ScannerPalette.FONT_SIZE_ROW,
			ScannerPalette.LIST_INDEX)
	number.custom_minimum_size = Vector2(12.0, 0.0)
	row.add_child(number)

	# Contacts the scanner has identified before are dimmed rather than given a
	# fifth column — the handoff's row is four columns wide.
	var name_color: Color = ScannerPalette.LIST_MUTED if contact["already_known"] \
			else ScannerPalette.ACCENT
	var name_label := ScannerPalette.mono_label(contact["category"], ScannerPalette.FONT_SIZE_ROW,
			name_color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	row.add_child(ScannerPalette.mono_label("%du" % int(contact["distance"]),
			ScannerPalette.FONT_SIZE_ROW, ScannerPalette.LIST_RANGE))
	row.add_child(ScannerPalette.mono_label(ScannerPalette.format_bearing(contact["bearing"]),
			ScannerPalette.FONT_SIZE_ROW, ScannerPalette.LIST_MUTED))

	# The handoff's blipIn is a fade plus a 4px rise; only the fade survives,
	# because animating position inside a container fights the layout.
	row.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(row, "modulate:a", 1.0, ROW_FADE_DURATION).set_ease(Tween.EASE_OUT)
	return row


## The countdown reads to one decimal, so the label is only rewritten ten times
## a second; the styleboxes are only rebuilt when the button actually changes
## state, not on every tick.
func _update_fire_button() -> void:
	var remaining: float = snappedf(_scanner.get_cooldown_remaining(), 0.1)
	if is_equal_approx(remaining, _shown_cooldown):
		return
	var was_cooling: bool = _shown_cooldown > 0.0
	_shown_cooldown = remaining

	var cooling: bool = remaining > 0.0
	_fire_button.text = ("COOL %0.1fs" % remaining) if cooling else "PING"
	_fire_button.disabled = cooling
	if cooling == was_cooling:
		return
	if cooling:
		ScannerPalette.style_fire_button(_fire_button, ScannerPalette.COOL_FILL,
				ScannerPalette.TEXT_DIM)
	else:
		ScannerPalette.style_fire_button(_fire_button, ScannerPalette.ACCENT,
				ScannerPalette.BACKDROP)

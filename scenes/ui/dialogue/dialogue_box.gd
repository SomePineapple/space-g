class_name DialogueBox
extends CanvasLayer

## The bottom-of-screen comms panel: typewriter text, a speaker identity line,
## click or key to advance, and an optional list of numbered replies on the last
## line. Built to docs/design_handoff_dialogue_box (option 1C, the only option
## that handoff asks for).
##
## Generic on purpose. It knows how to *show* dialogue and nothing about who is
## talking or why — callers hand it lines and listen for `finished` or
## `choice_selected`. That is what lets one panel serve tutorial help, a station
## trader and a hostile hail without any of them being special-cased here.
##
## Found by group rather than by an autoload (see find()): a dialogue box belongs
## to the region it is drawn over, and the project deliberately keeps autoloads
## for things that genuinely outlive a scene.
##
## Sits on CanvasLayer 20, above the full-screen menus at 10 (ship builder,
## trade, upgrades) and the gameplay HUD at 1. Anything worth interrupting the
## player with is worth them seeing over whatever screen they have open — the
## opening's boot and build lines play *while* the builder is up, and at a lower
## layer they were being spoken to an invisible panel.

## The last line has been advanced past and the panel has closed. Not emitted
## when a conversation ends on a reply — `choice_selected` covers that.
signal finished
## A reply was chosen. `index` is 0-based; `label` is the text the player saw.
signal choice_selected(index: int, label: String)

const GROUP: StringName = &"dialogue_box"

# --- Layout and timing (docs/design_handoff_dialogue_box/README.md) -----------
# Colours, fonts and styleboxes live in DialogueStyle.

const SIDE_INSET: float = 28.0
## Sits close to the screen edge now that the bottom-left cargo chip it used to
## clear has been taken out of the HUD (it was 96 for exactly that reason).
## Matches the side inset so the panel is evenly framed.
const BOTTOM_OFFSET: float = 28.0
## How much of the bust's base is hidden behind the panel. Negative separation on
## the stack is what keeps it covered in both the reply and no-reply states.
const BUST_OVERLAP: float = -42.0
const BUST_SIZE: Vector2 = Vector2(210.0, 230.0)
## The bust is deliberately not at the far left — there it collided with the
## SYSTEMS panel in the top-left HUD.
const BUST_LEFT_MARGIN: float = 244.0
## One line's worth, rather than the handoff's 50. The larger floor existed so the
## panel would not grow line by line while typing, but it left an empty band under
## every short line — and most of what this panel shows is one short line.
const BODY_MIN_HEIGHT: float = 26.0

const SECONDS_PER_CHARACTER: float = 0.028
const CARET_BLINK_SECONDS: float = 1.0
## Step-end blink: the caret is simply on for this share of each cycle, not faded.
const CARET_DUTY: float = 0.55
const BOB_SECONDS: float = 1.4
const BOB_PIXELS: float = 3.0

## Named actions rather than raw keycodes, per the project's input rule. Answers
## the handoff's open question "are replies number-key selectable": yes, as the
## amber hints imply.
const REPLY_ACTIONS: Array[String] = [
	"dialogue_reply_1", "dialogue_reply_2", "dialogue_reply_3",
]

@export var advance_action: String = "ui_accept"

var _lines: Array[DialogueLine] = []
var _index: int = 0
var _revealed: int = 0
var _reveal_timer: float = 0.0
var _elapsed: float = 0.0
## Passive mode: the panel is a subtitle for something else and must not offer
## to advance itself (see show_subtitle).
var _subtitle_mode: bool = false

var _root: Control
var _stack: VBoxContainer
var _bust_row: HBoxContainer
var _bust: TextureRect
var _panel: PanelContainer
var _speaker_label: Label
var _affiliation_label: Label
var _hint_margin: MarginContainer
var _hint_label: Label
var _body: RichTextLabel
var _replies: VBoxContainer


## The dialogue box for whatever scene `node` is in, or null if that scene has
## none. Callers are expected to cope with null so a region without a box simply
## has no dialogue rather than crashing.
static func find(node: Node) -> DialogueBox:
	if node == null or node.get_tree() == null:
		return null
	var boxes: Array = node.get_tree().get_nodes_in_group(GROUP)
	return boxes[0] if not boxes.is_empty() else null


func _ready() -> void:
	add_to_group(GROUP)
	_build_ui()
	_root.visible = false
	set_process(false)


# --- Public API --------------------------------------------------------------

## The common case: one line of help, no speaker art, no replies.
func show_line(speaker: String, affiliation: String, text: String) -> void:
	_subtitle_mode = false
	show_lines([DialogueLine.create(speaker, affiliation, text)])


## One line shown alongside something else that owns the timing — a voice clip,
## typically. Passive: no advance hint, no click target, and it cannot be
## advanced past. Whatever is speaking replaces or clears it.
##
## Distinct from show_line because the advance affordance would be a lie here:
## "SPACE ▾" on a subtitle promises a next line that the panel does not control.
func show_subtitle(speaker: String, affiliation: String, text: String) -> void:
	show_lines([DialogueLine.create(speaker, affiliation, text)])
	_subtitle_mode = true
	_hint_label.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows a sequence. Replaces anything already on screen — a conversation that
## interrupts another is the caller's decision to make, not this box's.
func show_lines(lines: Array[DialogueLine]) -> void:
	if lines.is_empty():
		dismiss()
		return
	_lines = lines
	_index = 0
	_subtitle_mode = false
	_hint_label.visible = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = true
	set_process(true)
	_begin_line()


func dismiss() -> void:
	_lines = []
	_root.visible = false
	set_process(false)


func is_open() -> bool:
	return _root != null and _root.visible


# --- Playback ----------------------------------------------------------------

func _begin_line() -> void:
	var line: DialogueLine = _lines[_index]
	_revealed = 0
	_reveal_timer = 0.0
	_speaker_label.text = line.speaker
	_affiliation_label.text = line.affiliation
	_bust.texture = line.bust
	# Hidden rather than left blank for a voice-only speaker; the stack collapses
	# and the panel keeps its own position.
	_bust_row.visible = line.bust != null
	_clear_replies()
	_refresh_body()


func _process(delta: float) -> void:
	_elapsed += delta
	_animate_hint()

	if not _is_line_complete():
		_reveal_timer += delta
		while _reveal_timer >= SECONDS_PER_CHARACTER and not _is_line_complete():
			_reveal_timer -= SECONDS_PER_CHARACTER
			_revealed += 1
		_refresh_body()
		if _is_line_complete():
			_show_replies_if_any()
	else:
		# Only the caret needs redrawing once the text is whole.
		_refresh_body()


func _is_line_complete() -> bool:
	return _lines.is_empty() or _revealed >= _lines[_index].text.length()


func _refresh_body() -> void:
	var line: DialogueLine = _lines[_index]
	var shown: String = line.text.substr(0, _revealed)
	var caret: String = ""
	if not _is_line_complete() and _caret_visible():
		caret = "[color=#%s]▌[/color]" % HudPalette.CYAN.to_html(false)
	_body.text = "%s%s" % [shown.xml_escape(), caret]


func _caret_visible() -> bool:
	return fmod(_elapsed, CARET_BLINK_SECONDS) < CARET_BLINK_SECONDS * CARET_DUTY


## SKIP while typing, SPACE when another line follows, END on the last one.
func _hint_text() -> String:
	if not _is_line_complete():
		return "SKIP ▾"
	return "END ▾" if _index >= _lines.size() - 1 else "SPACE ▾"


func _animate_hint() -> void:
	_hint_label.text = _hint_text()
	var phase: float = fmod(_elapsed, BOB_SECONDS) / BOB_SECONDS
	# Ease-in-out down and back up over the cycle.
	var bob: float = (1.0 - cos(phase * TAU)) * 0.5 * BOB_PIXELS
	_hint_margin.add_theme_constant_override("margin_top", roundi(bob))


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	for i in REPLY_ACTIONS.size():
		if InputMap.has_action(REPLY_ACTIONS[i]) and event.is_action_pressed(REPLY_ACTIONS[i]):
			_choose(i)
			get_viewport().set_input_as_handled()
			return
	if InputMap.has_action(advance_action) and event.is_action_pressed(advance_action):
		_advance()
		get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


## Typing → finish the line. Complete → next line. Last line → close. A line
## showing replies is not advanced past; the player has to pick one.
func _advance() -> void:
	if _lines.is_empty() or _subtitle_mode:
		return
	if not _is_line_complete():
		_revealed = _lines[_index].text.length()
		_refresh_body()
		_show_replies_if_any()
		return
	if not _lines[_index].choices.is_empty():
		return
	if _index >= _lines.size() - 1:
		dismiss()
		finished.emit()
		return
	_index += 1
	_begin_line()


func _choose(index: int) -> void:
	if _lines.is_empty() or not _is_line_complete():
		return
	var choices: Array[String] = _lines[_index].choices
	if index < 0 or index >= choices.size():
		return
	var label: String = choices[index]
	dismiss()
	choice_selected.emit(index, label)


func _show_replies_if_any() -> void:
	if _replies.get_child_count() > 0:
		return
	for i in _lines[_index].choices.size():
		_replies.add_child(_build_reply_row(i, _lines[_index].choices[i]))
	_replies.visible = _replies.get_child_count() > 0


func _clear_replies() -> void:
	for child in _replies.get_children():
		_replies.remove_child(child)
		child.queue_free()
	_replies.visible = false


# --- Construction ------------------------------------------------------------
# The bust and the panel are siblings in one bottom-anchored vertical stack
# rather than being positioned independently. That is what keeps the bust's open
# base hidden behind the panel in both states, since the panel's height changes
# when replies appear.

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stack.offset_left = SIDE_INSET
	_stack.offset_right = -SIDE_INSET
	_stack.offset_bottom = -BOTTOM_OFFSET
	# Grow upward from the anchored bottom edge, so adding replies pushes the
	# panel's top up instead of dragging it off the bottom of the screen.
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.add_theme_constant_override("separation", int(BUST_OVERLAP))
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stack)

	_build_bust()
	_build_panel()


func _build_bust() -> void:
	_bust_row = HBoxContainer.new()
	_bust_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(_bust_row)

	var offset := Control.new()
	offset.custom_minimum_size = Vector2(BUST_LEFT_MARGIN, 0.0)
	offset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bust_row.add_child(offset)

	_bust = TextureRect.new()
	_bust.custom_minimum_size = BUST_SIZE
	_bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bust_row.add_child(_bust)
	_bust_row.visible = false


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", DialogueStyle.panel_style())
	# The whole panel is the advance target, per the handoff.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_stack.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_body())
	column.add_child(_build_reply_list())


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_speaker_label = DialogueStyle.label("", DialogueStyle.SPEAKER_SIZE,
		HudPalette.CYAN_BRIGHT, DialogueStyle.SPEAKER_TRACKING)
	header.add_child(_speaker_label)

	_affiliation_label = DialogueStyle.label("", DialogueStyle.AFFILIATION_SIZE,
		DialogueStyle.AFFILIATION, DialogueStyle.AFFILIATION_TRACKING)
	header.add_child(_affiliation_label)

	# The hint bobs. A Label inside a container cannot be moved directly, so the
	# animation drives a wrapper's top margin instead.
	_hint_margin = MarginContainer.new()
	_hint_margin.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_hint_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label = DialogueStyle.label("", DialogueStyle.HINT_SIZE,
		HudPalette.CYAN, DialogueStyle.HINT_TRACKING)
	_hint_margin.add_child(_hint_label)
	header.add_child(_hint_margin)
	return header


func _build_body() -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed floor so the panel does not grow line by line as the text types.
	_body.custom_minimum_size = Vector2(0.0, BODY_MIN_HEIGHT)
	_body.add_theme_font_override("normal_font", DialogueStyle.mono(DialogueStyle.BODY_SIZE))
	_body.add_theme_font_size_override("normal_font_size", DialogueStyle.BODY_SIZE)
	_body.add_theme_color_override("default_color", DialogueStyle.BODY_TEXT)
	_body.add_theme_constant_override("line_separation", DialogueStyle.BODY_LINE_SPACING)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_body)
	return holder


func _build_reply_list() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 12)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(DialogueStyle.divider())

	_replies = VBoxContainer.new()
	_replies.add_theme_constant_override("separation", 6)
	_replies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_replies)

	# The divider belongs to the list, so both disappear together.
	_replies.visibility_changed.connect(func() -> void: holder.visible = _replies.visible)
	holder.visible = false
	return holder


func _build_reply_row(index: int, label_text: String) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", DialogueStyle.reply_style(false))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(func() -> void:
		row.add_theme_stylebox_override("panel", DialogueStyle.reply_style(true)))
	row.mouse_exited.connect(func() -> void:
		row.add_theme_stylebox_override("panel", DialogueStyle.reply_style(false)))
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_choose(index))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(DialogueStyle.label(str(index + 1), DialogueStyle.REPLY_KEY_SIZE,
		DialogueStyle.KEY_HINT, DialogueStyle.KEY_TRACKING))
	line.add_child(DialogueStyle.label(label_text, DialogueStyle.REPLY_LABEL_SIZE,
		HudPalette.LIST_NAME))
	row.add_child(line)
	return row

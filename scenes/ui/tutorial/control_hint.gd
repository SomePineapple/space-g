class_name ControlHint
extends CanvasLayer

## The first-time control hint: a small top-right panel that names one control,
## draws its key(s) as key-caps, waits for the player to actually press them, and
## then gets out of the way. Built to docs/design_handoff_controls_tutorial.
##
## That handoff leaves one question open — one fixed opening sequence, or one
## hint per control at the moment that control first matters. This is the second
## model: a hint is raised by whatever system knows the feature has just become
## relevant (see IntroDirector), which is why every hint carries its own id and is
## remembered on its own.
##
## The panel itself knows nothing about which controls exist or when they matter,
## and nothing about the keys either — it is handed input actions and reads the
## bindings out of the InputMap, so a rebound key teaches itself correctly. Same
## division DialogueBox makes: the caller owns the "when" and the words.
##
## Found by group rather than through an autoload, like DialogueBox: the panel
## belongs to the region it is drawn over. What the player has already been
## taught outlives the region, and lives in the statics below instead.
##
## Sits on CanvasLayer 5 — above the gameplay HUD (1), below the full-screen
## menus (10). A hint teaches a control used while flying, so the builder or the
## trade screen covering it is right.

## Every key of a hint has been pressed, or it was skipped. Nothing listens yet;
## it exists so a caller can chain a follow-up onto a control being learned.
signal hint_finished(id: StringName)

const GROUP: StringName = &"control_hint"

## How the caps are arranged. MOVEMENT_PAD is the handoff's WASD formation and
## expects exactly four actions, in the order forward, left, backward, right.
enum Formation { ROW, MOVEMENT_PAD }

# --- Layout (docs/design_handoff_controls_tutorial/README.md) -----------------
# Sizes are the handoff's, taken down to about 70%: at full size the panel read
# as a dialog sitting on the game rather than as a corner readout alongside the
# rest of the HUD. Everything was scaled together, so the proportions the handoff
# specifies are intact.

const PANEL_WIDTH: float = 276.0
const SIDE_MARGIN: float = 20.0
## Tucked into the corner. The credits readout that would otherwise be here is
## hidden while the exchange is frozen (Hud.CREDITS_FROZEN) — if it comes back,
## this has to drop below it, since it occupies y 20–42.
const TOP_MARGIN: float = 20.0
const PANEL_PADDING_X: int = 17
const PANEL_PADDING_TOP: int = 15
const PANEL_PADDING_BOTTOM: int = 14
const PANEL_RADIUS: int = 5
## rgba(20,26,33,0.82). No backdrop blur: Godot would need a screen-reading
## shader for it, which is not worth a frame's worth of texture copy on a panel
## this small.
const PANEL_FILL: Color = Color(0.0784, 0.1020, 0.1294, 0.82)
const PANEL_BORDER_ALPHA: float = 0.28

const EYEBROW_SIZE: int = 9
const EYEBROW_TRACKING: float = 0.16
const SKIP_SIZE: int = 9
const SKIP_TRACKING: float = 0.1
const BODY_SIZE: int = 12
const BODY_MIN_HEIGHT: float = 18.0
const FOOTER_SIZE: int = 8
const FOOTER_TRACKING: float = 0.08

const KEY_GAP: int = 4
const DOT_SIZE: float = 5.0
const DOT_GAP: int = 6
const DOT_UPCOMING_ALPHA: float = 0.15

const EYEBROW_TEXT: String = "NEW CONTROL"
const SKIP_TEXT: String = "SKIP ✕"
const DONE_TEXT: String = "GOT IT ▸"

const SKIP_COLOR: Color = Color(0.3608, 0.4196, 0.4706)  # 5c6b78
const SKIP_HOVER_COLOR: Color = Color(0.7804, 0.8157, 0.8471)  # c7d0d8

## Rise-and-fade entrance.
const FADE_SECONDS: float = 0.25
const RISE_PIXELS: float = 6.0
## Held on the confirmed state before moving on, so the player sees the ✓ land.
const ADVANCE_DELAY: float = 0.55

# --- Player-facing state -----------------------------------------------------
# Static, because the panel is rebuilt every time a region loads and what the
# player has already been taught must not be. Session-scoped: the project has no
# save file yet (CLAUDE.md scope control), and when it grows one these two are
# what it stores.

## The eventual pause-menu "tooltips" switch writes here. Off hides anything
## on screen as well as suppressing new hints.
static var _enabled: bool = true
## Hint id -> true. Set when a hint is raised rather than when it is completed,
## so a hint the player ignores does not queue up again the next time the same
## trigger fires.
static var _seen: Dictionary = {}


## One queued hint. A class rather than a Dictionary so a caller passing the
## wrong shape fails at the call site instead of at draw time.
class Hint:
	var id: StringName
	var text: String
	var actions: Array[StringName]
	var formation: int

	func _init(hint_id: StringName, hint_text: String,
			hint_actions: Array[StringName], hint_formation: int) -> void:
		id = hint_id
		text = hint_text
		actions = hint_actions
		formation = hint_formation


## Current first. Empty means nothing is on screen.
var _queue: Array[Hint] = []
var _caps: Array[ControlHintCap] = []
var _advance_timer: float = -1.0

var _root: Control
var _panel: PanelContainer
var _body: Label
var _keys_holder: CenterContainer
var _footer: Label
var _dots: HBoxContainer


# --- Public API --------------------------------------------------------------

## The one call a teaching system makes. Silently does nothing if hints are off,
## if this one has been shown before, or if the scene has no hint panel — so a
## caller never has to guard, and a region without the panel simply has no hints.
##
## Returns whether the hint was actually raised, for a caller that wants to know.
static func teach(source: Node, id: StringName, text: String,
		actions: Array[StringName], formation: Formation = Formation.ROW) -> bool:
	if not _enabled or _seen.has(id):
		return false
	var panel: ControlHint = find(source)
	if panel == null:
		return false
	_seen[id] = true
	panel._enqueue(Hint.new(id, text, actions, formation))
	return true


static func find(node: Node) -> ControlHint:
	if node == null or node.get_tree() == null:
		return null
	var panels: Array = node.get_tree().get_nodes_in_group(GROUP)
	return panels[0] if not panels.is_empty() else null


static func is_enabled() -> bool:
	return _enabled


## For the pause menu's tooltips switch. Turning hints back on does not replay
## what has already been shown — reset_seen() is the separate "replay tutorials"
## action the handoff describes.
static func set_enabled(enabled: bool) -> void:
	_enabled = enabled


static func has_seen(id: StringName) -> bool:
	return _seen.has(id)


static func reset_seen() -> void:
	_seen.clear()


func _ready() -> void:
	add_to_group(GROUP)
	_build_ui()
	_root.visible = false
	set_process(false)


# --- Queue -------------------------------------------------------------------

func _enqueue(hint: Hint) -> void:
	_queue.append(hint)
	if _queue.size() == 1:
		_begin(hint)
	else:
		_refresh_dots()


func _begin(hint: Hint) -> void:
	_advance_timer = -1.0
	_body.text = hint.text
	_build_caps(hint)
	_refresh_dots()
	_refresh_footer()
	_root.visible = true
	set_process(true)
	_play_entrance()


## Drops the current hint and shows the next, if any.
func _finish_current() -> void:
	if _queue.is_empty():
		return
	var done: StringName = _queue.pop_front().id
	if _queue.is_empty():
		_hide()
	else:
		_begin(_queue[0])
	hint_finished.emit(done)


## SKIP dismisses what is on screen and anything queued behind it, but does not
## turn hints off for good — a later feature still gets its one explanation. The
## permanent off switch is set_enabled(), which is what the pause menu will own.
func _skip() -> void:
	var dropped: Array[Hint] = _queue.duplicate()
	_queue.clear()
	_hide()
	for hint in dropped:
		hint_finished.emit(hint.id)


func _hide() -> void:
	_queue.clear()
	_advance_timer = -1.0
	_root.visible = false
	set_process(false)


func is_open() -> bool:
	return _root != null and _root.visible


# --- Input -------------------------------------------------------------------

## Never marks the event handled: gameplay carries on underneath, which is the
## whole point of teaching a control by having the player use it.
func _input(event: InputEvent) -> void:
	if _queue.is_empty() or _menu_open():
		return
	var actions: Array[StringName] = _queue[0].actions
	var changed: bool = false
	for i in mini(_caps.size(), actions.size()):
		if _caps[i].is_confirmed():
			continue
		if event.is_action_pressed(actions[i]):
			_caps[i].confirm()
			changed = true
	if not changed:
		return
	_refresh_footer()
	if _all_confirmed():
		_advance_timer = ADVANCE_DELAY


## A key pressed with the builder or trade screen open moves nothing, because
## ship control is suspended there (see ShipInput._is_menu_open) — so it must not
## count as having learned the control either.
func _menu_open() -> bool:
	for panel in get_tree().get_nodes_in_group("menu_panel"):
		if panel.visible:
			return true
	return false


func _process(delta: float) -> void:
	if not _enabled:
		_hide()
		return
	if _advance_timer < 0.0:
		return
	_advance_timer -= delta
	if _advance_timer <= 0.0:
		_finish_current()


func _all_confirmed() -> bool:
	for cap in _caps:
		if not cap.is_confirmed():
			return false
	return not _caps.is_empty()


# --- Key labels --------------------------------------------------------------

## What to print on the cap for an action, read from the live InputMap so a
## rebound control teaches its new key rather than a hard-coded one. Falls back
## to the action's own name, which is ugly but honest, rather than drawing a
## blank cap.
static func key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return String(action).to_upper()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
			var text: String = OS.get_keycode_string(code)
			if not text.is_empty():
				return text.to_upper()
		elif event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
	return String(action).to_upper()


# --- Construction ------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -(PANEL_WIDTH + SIDE_MARGIN)
	_panel.offset_right = -SIDE_MARGIN
	# Height is intrinsic: a Control outside a container is still clamped to its
	# own minimum size, so an equal top and bottom offset lets the panel grow
	# downwards to fit whichever key formation it is showing.
	_panel.offset_top = TOP_MARGIN
	_panel.offset_bottom = TOP_MARGIN
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_body())
	column.add_child(_build_keys_holder())
	column.add_child(_build_footer())


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.set_border_width_all(1)
	style.border_color = HudPalette.with_alpha(HudPalette.CYAN, PANEL_BORDER_ALPHA)
	style.set_corner_radius_all(PANEL_RADIUS)
	style.content_margin_left = PANEL_PADDING_X
	style.content_margin_right = PANEL_PADDING_X
	style.content_margin_top = PANEL_PADDING_TOP
	style.content_margin_bottom = PANEL_PADDING_BOTTOM
	return style


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(DialogueStyle.label(EYEBROW_TEXT, EYEBROW_SIZE,
		DialogueStyle.KEY_HINT, EYEBROW_TRACKING))

	var skip: Label = DialogueStyle.label(SKIP_TEXT, SKIP_SIZE, SKIP_COLOR, SKIP_TRACKING)
	skip.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip.mouse_entered.connect(func() -> void:
		skip.add_theme_color_override("font_color", SKIP_HOVER_COLOR))
	skip.mouse_exited.connect(func() -> void:
		skip.add_theme_color_override("font_color", SKIP_COLOR))
	skip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_skip())
	header.add_child(skip)
	return header


func _build_body() -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	holder.add_theme_constant_override("margin_bottom", 13)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_body = DialogueStyle.label("", BODY_SIZE, DialogueStyle.BODY_TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A floor so a one-line hint and a two-line one do not sit at noticeably
	# different heights on screen.
	_body.custom_minimum_size = Vector2(0.0, BODY_MIN_HEIGHT)
	holder.add_child(_body)
	return holder


func _build_keys_holder() -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_bottom", 14)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_holder = CenterContainer.new()
	_keys_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_keys_holder)
	return holder


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer = DialogueStyle.label("", FOOTER_SIZE, SKIP_COLOR, FOOTER_TRACKING)
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_footer)

	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", DOT_GAP)
	_dots.alignment = BoxContainer.ALIGNMENT_END
	_dots.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_dots)
	return footer


# --- Per-hint content --------------------------------------------------------

func _build_caps(hint: Hint) -> void:
	for child in _keys_holder.get_children():
		_keys_holder.remove_child(child)
		child.queue_free()
	_caps.clear()

	for action in hint.actions:
		_caps.append(ControlHintCap.create(key_label(action)))

	if hint.formation == Formation.MOVEMENT_PAD and _caps.size() == 4:
		_keys_holder.add_child(_movement_pad())
	else:
		_keys_holder.add_child(_cap_row())


## The handoff's WASD block: forward on the top row's middle column, the other
## three side by side beneath it. _caps stays in the caller's action order —
## only the cells are rearranged.
func _movement_pad() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", KEY_GAP)
	grid.add_theme_constant_override("v_separation", KEY_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(_pad_spacer())
	grid.add_child(_caps[0])
	grid.add_child(_pad_spacer())
	grid.add_child(_caps[1])
	grid.add_child(_caps[2])
	grid.add_child(_caps[3])
	return grid


func _pad_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = ControlHintCap.SIZE
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _cap_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", KEY_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cap in _caps:
		row.add_child(cap)
	return row


func _refresh_footer() -> void:
	if _all_confirmed():
		_footer.text = DONE_TEXT
		return
	_footer.text = "PRESS THE HIGHLIGHTED KEY%s TO CONTINUE" \
		% ("S" if _caps.size() > 1 else "")


## One dot per queued hint, and none at all for the usual case of a single hint
## standing alone. This is deliberately less than the handoff draws: its dots
## track position in one fixed opening sequence, and in the per-feature model
## there is no sequence to be partway through — only a backlog, on the rare
## occasions two features become relevant at once.
func _refresh_dots() -> void:
	for child in _dots.get_children():
		_dots.remove_child(child)
		child.queue_free()
	if _queue.size() < 2:
		return
	for i in _queue.size():
		_dots.add_child(_dot(HudPalette.CYAN if i == 0 \
			else HudPalette.with_alpha(HudPalette.CYAN, DOT_UPCOMING_ALPHA)))


func _dot(color: Color) -> Control:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(DOT_SIZE * 0.5))
	dot.add_theme_stylebox_override("panel", style)
	return dot


## Fades up and settles down into place. Driven on the panel's offsets rather
## than its position because it is anchored, and an anchored control recomputes
## its position from those offsets whenever the window changes size.
func _play_entrance() -> void:
	_panel.modulate.a = 0.0
	_set_panel_top(TOP_MARGIN - RISE_PIXELS)
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(_panel, "modulate:a", 1.0, FADE_SECONDS)
	tween.tween_method(_set_panel_top, TOP_MARGIN - RISE_PIXELS, TOP_MARGIN, FADE_SECONDS) \
		.set_ease(Tween.EASE_OUT)


func _set_panel_top(value: float) -> void:
	_panel.offset_top = value
	_panel.offset_bottom = value

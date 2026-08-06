class_name UpgradeDetailPanel
extends PanelContainer

## The card pinned to the bottom of the upgrade screen's left rail
## (docs/design_handoff_upgrade_tree/README.md "Detail panel"). Describes
## whichever node the player is pointing at and carries the unlock action.
##
## Presentation only: it is handed a already-resolved dictionary and emits
## `unlock_pressed`; UpgradeMenu owns every rule about whether that is allowed.

signal unlock_pressed(node_id: String)

const NAME_FONT_SIZE: int = 15
const TIER_FONT_SIZE: int = 11
const DESC_FONT_SIZE: int = 13
const COST_FONT_SIZE: int = 11
const REQUIREMENT_FONT_SIZE: int = 12
const REQUIREMENT_DOT_SIZE: float = 7.0

var _column: VBoxContainer
var _name_label: Label
var _tier_label: Label
var _description: Label
var _cost_label: Label
var _effect_label: Label
var _reason_label: Label
var _requirements: VBoxContainer
var _button: Button

var _node_id: String = ""


func _ready() -> void:
	_apply_border(Color(1, 1, 1, 0.15))

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	add_child(_column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_column.add_child(title_row)

	_name_label = BuilderTheme.sans_label("", NAME_FONT_SIZE, BuilderTheme.TEXT_SELECTED)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(_name_label)

	_tier_label = BuilderTheme.mono_label("", TIER_FONT_SIZE, BuilderTheme.TEXT_HINT)
	_tier_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_tier_label)

	_description = BuilderTheme.sans_label("", DESC_FONT_SIZE, BuilderTheme.TEXT_MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_description)

	# Not in the handoff: the game's upgrades carry real stat modifiers and the
	# screen this replaces showed them. Dropping them would lose information.
	_effect_label = BuilderTheme.mono_label("", COST_FONT_SIZE, BuilderTheme.TEXT_MUTED_DIM)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_effect_label)

	_requirements = VBoxContainer.new()
	_requirements.add_theme_constant_override("separation", 4)
	_column.add_child(_requirements)

	_cost_label = BuilderTheme.mono_label("", COST_FONT_SIZE, BuilderTheme.TEXT_LABEL)
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_cost_label)

	_reason_label = BuilderTheme.mono_label("", COST_FONT_SIZE, BuilderTheme.WARN_TEXT)
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_reason_label)

	_button = Button.new()
	_button.pressed.connect(func(): unlock_pressed.emit(_node_id))
	_column.add_child(_button)

	show_message("Hover a node for details.")


## Fields: id, label, tier, is_base, description, cost_text, effect_text,
## state (UpgradeTreeView.STATE_*), hue, can_unlock, reason,
## requirements: Array of {"label": String, "met": bool, "hue": float}.
func show_node(data: Dictionary) -> void:
	_node_id = data["id"]
	var state: String = data["state"]
	var hue: float = data["hue"]
	var accent: Color = UpgradePalette.bright(hue)

	_name_label.text = data["label"]
	_name_label.visible = true
	_tier_label.text = "BASE MODULE" if data["is_base"] else "TIER %d" % data["tier"]
	_tier_label.visible = true
	_set_optional(_description, data.get("description", ""))
	_set_optional(_effect_label, data.get("effect_text", ""))
	_set_optional(_cost_label, "COST · %s" % data["cost_text"] if not data.get("cost_text", "").is_empty() else "")
	_set_optional(_reason_label, data.get("reason", ""))

	_apply_border(accent if state != UpgradeTreeView.STATE_LOCKED else Color(1, 1, 1, 0.15))
	_build_requirements(data.get("requirements", []))
	_style_button(state, data.get("can_unlock", false), accent)


## Empty state — no node pointed at, or nothing selectable at all.
func show_message(message: String) -> void:
	_node_id = ""
	_name_label.text = message
	_name_label.visible = true
	_tier_label.visible = false
	_set_optional(_description, "")
	_set_optional(_effect_label, "")
	_set_optional(_cost_label, "")
	_set_optional(_reason_label, "")
	_build_requirements([])
	_apply_border(Color(1, 1, 1, 0.15))
	_button.visible = false


func _set_optional(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


## A merge node's "REQUIRES ALL" block — the detail-panel half of the two-tone
## fill, spelling out which branches have to converge.
func _build_requirements(requirements: Array) -> void:
	for child in _requirements.get_children():
		child.queue_free()
	_requirements.visible = not requirements.is_empty()
	if requirements.is_empty():
		return

	_requirements.add_child(BuilderTheme.mono_label("REQUIRES ALL", TIER_FONT_SIZE, BuilderTheme.TEXT_HINT))
	for requirement in requirements:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var met: bool = requirement["met"]
		var dot_colour: Color = UpgradePalette.bright(requirement["hue"]) if met else Color(1, 1, 1, 0.2)
		row.add_child(BuilderTheme.make_glow_dot(dot_colour, REQUIREMENT_DOT_SIZE))
		row.add_child(BuilderTheme.mono_label(requirement["label"], REQUIREMENT_FONT_SIZE,
			BuilderTheme.TEXT_BODY if met else BuilderTheme.TEXT_LABEL))
		_requirements.add_child(row)


func _style_button(state: String, can_unlock: bool, accent: Color) -> void:
	_button.visible = true
	_button.add_theme_font_override("font", BuilderTheme.mono_font())
	_button.add_theme_font_size_override("font_size", 12)

	match state:
		UpgradeTreeView.STATE_UNLOCKED:
			_button.text = "UNLOCKED"
			_button.disabled = true
			_paint_button(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.15), BuilderTheme.HEALTH_GOOD)
		UpgradeTreeView.STATE_AVAILABLE:
			_button.text = "UNLOCK"
			# Available in the handoff's sense (prerequisites met) but still
			# gated on cost or a cross-module requirement: the game keeps the
			# label and greys the button, with the reason spelled out above.
			_button.disabled = not can_unlock
			if can_unlock:
				_paint_button(BuilderTheme.with_alpha(accent, 0.15), accent, accent)
			else:
				_paint_button(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.1), BuilderTheme.TEXT_HINT)
		_:
			_button.text = "LOCKED"
			_button.disabled = true
			_paint_button(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.1), BuilderTheme.TEXT_HINT)


func _paint_button(fill: Color, border: Color, text_colour: Color) -> void:
	_button.add_theme_color_override("font_color", text_colour)
	_button.add_theme_color_override("font_hover_color", text_colour)
	_button.add_theme_color_override("font_pressed_color", text_colour)
	_button.add_theme_color_override("font_disabled_color", text_colour)
	var style: StyleBoxFlat = BuilderTheme.padded(
		BuilderTheme.flat_style(fill, border, BuilderTheme.RADIUS_MEDIUM), 12.0, 9.0)
	var hover: StyleBoxFlat = BuilderTheme.padded(
		BuilderTheme.flat_style(BuilderTheme.with_alpha(fill, minf(fill.a * 2.0, 1.0)), border,
			BuilderTheme.RADIUS_MEDIUM), 12.0, 9.0)
	_button.add_theme_stylebox_override("normal", style)
	_button.add_theme_stylebox_override("hover", hover)
	_button.add_theme_stylebox_override("pressed", hover)
	_button.add_theme_stylebox_override("disabled", style)
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_border(border: Color) -> void:
	add_theme_stylebox_override("panel", BuilderTheme.padded(
		BuilderTheme.flat_style(Color(0.0392, 0.0510, 0.0706, 0.6), border, BuilderTheme.RADIUS_FIELD),
		16.0, 14.0))

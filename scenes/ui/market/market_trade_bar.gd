class_name MarketTradeBar
extends VBoxContainer

## Quantity chips, the in-hold readout, the BUY/SELL buttons and the YOUR
## IMPACT banner (docs/design_handoff_trade_market/README.md "Centre — focus
## panel", from "Trade bar" down).
##
## The disabled states are part of the design, not decoration: when a trade
## can't happen the button greys out *and its label says why* — HOLD FULL,
## NOT ENOUGH CREDITS, NOTHING TO SELL. A button that looks live and silently
## does nothing is the bug this replaces.

signal quantity_selected(quantity: int)
signal trade_requested(direction: int)

const QUANTITIES: Array[int] = [10, 25, 50, 100]
const BAR_PADDING_HORIZONTAL: int = 24
const BAR_PADDING_VERTICAL: int = 16
const BANNER_PADDING_HORIZONTAL: int = 20
const BANNER_PADDING_VERTICAL: int = 12

var _quantity: int = 50
var _quantity_buttons: Dictionary = {}
var _hold_label: Label
var _buy_button: Button
var _sell_button: Button
var _banner: PanelContainer
var _impact_label: Label
var _spillover_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", MarketTheme.PANEL_GAP)
	add_child(_build_bar())
	add_child(_build_banner())


func _build_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", MarketTheme.padded(
		MarketTheme.panel(MarketTheme.PANEL_ALPHA_TRADE),
		BAR_PADDING_HORIZONTAL, BAR_PADDING_VERTICAL,
		BAR_PADDING_HORIZONTAL, BAR_PADDING_VERTICAL))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)

	row.add_child(_build_quantities())
	row.add_child(_divider())
	row.add_child(_build_hold_block())
	row.add_child(_build_actions())
	return bar


func _build_quantities() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 7)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(_caption("QUANTITY"))

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	for quantity in QUANTITIES:
		var button := Button.new()
		button.text = "%du" % quantity
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: quantity_selected.emit(quantity))
		chips.add_child(button)
		_quantity_buttons[quantity] = button
	block.add_child(chips)
	_restyle_quantities()
	return block


func _build_hold_block() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 3)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(_caption("IN HOLD"))
	_hold_label = MarketTheme.sans_label("", MarketTheme.SIZE_ROW_NAME, MarketTheme.TEXT_BODY)
	block.add_child(_hold_label)
	return block


func _build_actions() -> Control:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_buy_button = Button.new()
	_buy_button.focus_mode = Control.FOCUS_NONE
	_buy_button.pressed.connect(func() -> void: trade_requested.emit(1))
	actions.add_child(_buy_button)

	_sell_button = Button.new()
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_button.pressed.connect(func() -> void: trade_requested.emit(-1))
	actions.add_child(_sell_button)
	return actions


func _build_banner() -> Control:
	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.add_theme_stylebox_override("panel", MarketTheme.padded(
		MarketTheme.flat_style(MarketTheme.with_alpha(MarketTheme.CYAN, 0.07),
			MarketTheme.with_alpha(MarketTheme.CYAN, 0.25)),
		BANNER_PADDING_HORIZONTAL, BANNER_PADDING_VERTICAL,
		BANNER_PADDING_HORIZONTAL, BANNER_PADDING_VERTICAL))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(MarketTheme.caption("YOUR IMPACT"))
	_impact_label = MarketTheme.sans_label("", MarketTheme.SIZE_IMPACT, MarketTheme.CYAN_BRIGHT)
	row.add_child(_impact_label)
	_spillover_label = MarketTheme.sans_label("", MarketTheme.SIZE_TICKER, MarketTheme.TEXT_SUBTLE)
	_spillover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spillover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_spillover_label)
	_banner.add_child(row)
	return _banner


func _caption(text: String) -> Label:
	return MarketTheme.mono_label(text, MarketTheme.SIZE_LABEL, MarketTheme.TEXT_LABEL, true)


func _divider() -> Panel:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(1, 40)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_stylebox_override("panel", MarketTheme.flat_style(Color(1, 1, 1, 0.08)))
	return line


# --- State ------------------------------------------------------------------

func set_quantity(quantity: int) -> void:
	_quantity = quantity
	_restyle_quantities()


func _restyle_quantities() -> void:
	for quantity in _quantity_buttons:
		var on: bool = quantity == _quantity
		MarketTheme.style_button(_quantity_buttons[quantity],
			MarketTheme.with_alpha(MarketTheme.CYAN, 0.2) if on else Color(1, 1, 1, 0.04),
			MarketTheme.with_alpha(MarketTheme.CYAN, 0.5) if on else Color(1, 1, 1, 0.1),
			MarketTheme.CYAN_BRIGHT if on else MarketTheme.TEXT_SUBTLE,
			MarketTheme.SIZE_QUANTITY, 14, 8)


## `blocker` is empty when the trade is possible, otherwise the reason to
## print on the button in place of the total.
func refresh(held: int, buy_total: int, sell_total: int,
		buy_blocker: String, sell_blocker: String) -> void:
	_hold_label.text = "%du in hold" % held if held > 0 else "none in hold"
	_style_action(_buy_button, MarketTheme.CYAN, buy_blocker,
		"BUY · %s cr" % HudPalette.group_digits(buy_total))
	_style_action(_sell_button, MarketTheme.AMBER, sell_blocker,
		"SELL · %s cr" % HudPalette.group_digits(sell_total))


func _style_action(button: Button, tint: Color, blocker: String, enabled_label: String) -> void:
	var blocked: bool = not blocker.is_empty()
	button.disabled = blocked
	button.text = blocker if blocked else enabled_label
	button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if blocked else Control.CURSOR_POINTING_HAND
	if blocked:
		MarketTheme.style_button(button, Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.1),
			MarketTheme.TEXT_FAINT, MarketTheme.SIZE_BUTTON, 26, 14)
	else:
		MarketTheme.style_button(button, MarketTheme.with_alpha(tint, 0.12),
			MarketTheme.with_alpha(tint, 0.45),
			MarketTheme.CYAN_BRIGHT if tint == MarketTheme.CYAN else MarketTheme.AMBER,
			MarketTheme.SIZE_BUTTON, 26, 14)


func show_impact(message: String, spillover: String, color: Color) -> void:
	_banner.visible = true
	_impact_label.text = message
	_impact_label.add_theme_color_override("font_color", color)
	_spillover_label.text = "spillover %s" % spillover


func clear_impact() -> void:
	_banner.visible = false

extends GamePanel

## The Station Exchange — the full-screen market that replaced the old flat
## Buy/Sell list. `docs/design_handoff_trade_market/` is the source of truth
## for its appearance and behaviour; MarketService owns the economy, and this
## screen only reads it and reports the player's trades back into it.
##
## Opened and closed with T at a station. Composed of MaterialListPanel (left),
## MarketFocusCard + MarketTradeBar (centre) and MarketRail (right); this
## script owns the screen state the handoff lists — selected material,
## quantity and the last impact — plus the header, ticker and footer strips.

## The handoff's design canvas. The screen is never laid out narrower than
## this — see _fit_canvas().
const REFERENCE_SIZE: Vector2 = Vector2(1600, 900)
const DEFAULT_QUANTITY: int = 50
## Quantity chips in order, so the 1–4 keys and the buttons stay in step.
const QUANTITY_ACTIONS: Array[String] = [
	"market_quantity_1", "market_quantity_2", "market_quantity_3", "market_quantity_4",
]

var _material_ids: Array = []
var _selected_id: String = ""
var _quantity: int = DEFAULT_QUANTITY

var _canvas: Control
var _canvas_content: VBoxContainer
var _fit_queued: bool = false
var _header: MarketHeader
var _ticker: MarketTicker
var _list: MaterialListPanel
var _focus: MarketFocusCard
var _trade_bar: MarketTradeBar
var _rail: MarketRail
var _footer: MarketFooter


func _init() -> void:
	toggle_action = "toggle_trade"
	requires_home_base = true
	# Full-screen takeover: has to sit above the gameplay HUD and the station
	# prompt, which share CanvasLayer 1.
	layer = 10


func _setup() -> void:
	_material_ids = MaterialCatalog.ALL_IDS
	_build_ui()
	_list.populate(_material_ids)
	if not _material_ids.is_empty():
		_select_material(_material_ids[0])
	MarketService.ticked.connect(_on_market_ticked)
	_connect_inventory()
	set_process(false)


func _on_ship_bound() -> void:
	_connect_inventory()
	if visible:
		_refresh()


## The old inventory is freed with its ship, taking its connections with it,
## so a rebind only ever has to connect the new one.
func _connect_inventory() -> void:
	if inventory == null:
		return
	inventory.materials_changed.connect(_on_inventory_changed)
	inventory.credits_changed.connect(_on_inventory_changed)


func _on_opened() -> void:
	_ticker.rebuild(_material_ids)
	set_process(true)
	_refresh()


func _on_closed() -> void:
	set_process(false)
	# The impact banner reports one trade, not a running total — it belongs to
	# the visit, so it does not survive leaving the screen.
	_trade_bar.clear_impact()


# --- Construction -----------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	# ...and_offsets_preset, not set_anchors_preset: the latter preserves the
	# control's current (zero) rect by writing compensating offsets.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.resized.connect(_queue_fit)

	_canvas = Control.new()
	root.add_child(_canvas)
	_canvas.add_child(MarketBackdrop.new())

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	_canvas.add_child(column)
	_canvas_content = column
	# The screen's own width requirement moves with its contents: a button
	# reading "BUY · 21,300 cr" is wider than the same button reading
	# "BUY · 400 cr", so the fit has to be redone when that changes.
	column.minimum_size_changed.connect(_queue_fit)

	_header = MarketHeader.new()
	column.add_child(_header)
	_ticker = MarketTicker.new()
	column.add_child(_ticker)
	column.add_child(_build_body())
	_footer = MarketFooter.new()
	column.add_child(_footer)
	_fit_canvas()


## Coalesced and deferred: minimum_size_changed fires during a layout pass,
## and resizing the canvas from inside that pass would re-enter it.
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_canvas.call_deferred()


## Three fixed-width columns plus a trade bar full of labelled buttons do not
## fit in a 1152-wide window, and the handoff is explicit that clipped panels
## are a bug rather than graceful degradation. So the screen is laid out on a
## canvas no smaller than the design's 1600 x 900 — nor than whatever its
## contents currently need — and scaled down to fit. It still flexes, with the
## centre column taking the slack, on anything larger.
func _fit_canvas() -> void:
	_fit_queued = false
	var available: Vector2 = _canvas.get_parent().size
	if available.x <= 0.0 or available.y <= 0.0:
		return

	var required := Vector2(
		maxf(REFERENCE_SIZE.x, _canvas_content.get_combined_minimum_size().x),
		REFERENCE_SIZE.y)
	var factor: float = minf(1.0,
		minf(available.x / required.x, available.y / required.y))
	_canvas.scale = Vector2(factor, factor)
	# Exactly `available` once scaled, so there is never a letterboxed edge,
	# and never below `required`, so nothing clips.
	_canvas.size = available / factor


func _build_body() -> Control:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", MarketTheme.GUTTER)
	margin.add_theme_constant_override("margin_right", MarketTheme.GUTTER)
	margin.add_theme_constant_override("margin_top", MarketTheme.BODY_PAD)
	margin.add_theme_constant_override("margin_bottom", MarketTheme.BODY_PAD)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", MarketTheme.COLUMN_GAP)
	margin.add_child(columns)

	_list = MaterialListPanel.new()
	_list.material_selected.connect(_select_material)
	columns.add_child(_list)

	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", MarketTheme.PANEL_GAP)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus = MarketFocusCard.new()
	centre.add_child(_focus)
	_trade_bar = MarketTradeBar.new()
	_trade_bar.quantity_selected.connect(_set_quantity)
	_trade_bar.trade_requested.connect(_trade)
	centre.add_child(_trade_bar)
	columns.add_child(centre)

	_rail = MarketRail.new()
	columns.add_child(_rail)
	return margin


# --- Screen state -----------------------------------------------------------

func _select_material(material_id: String) -> void:
	_selected_id = material_id
	_list.set_selected(material_id)
	_focus.show_material(material_id)
	if visible:
		_refresh()


## Selection moves through the whole catalog, not just the visible tab: the
## handoff keeps a filtered-out selection alive rather than snapping it.
func _step_selection(step: int) -> void:
	var index: int = _material_ids.find(_selected_id)
	if index < 0:
		return
	_select_material(_material_ids[wrapi(index + step, 0, _material_ids.size())])


func _set_quantity(quantity: int) -> void:
	_quantity = quantity
	_trade_bar.set_quantity(quantity)
	_refresh_trade_bar()


# --- Trading ----------------------------------------------------------------

## Buys (`direction` +1) or sells (−1) the selected quantity, then reports the
## price move it caused. Re-checks the blockers rather than trusting the
## button state, since the keyboard path reaches here too.
func _trade(direction: int) -> void:
	if _selected_id.is_empty() or inventory == null:
		return
	# Both taken before the order lands, since applying it moves the price the
	# quote was struck at.
	var order: Dictionary = MarketService.quote(_selected_id, _quantity, direction)
	var price_before: int = MarketService.get_price(_selected_id)

	if direction > 0:
		if not _buy_blocker(order).is_empty():
			return
		inventory.spend_credits(order["total"])
		inventory.add_material(_selected_id, _quantity)
	else:
		if not _sell_blocker().is_empty():
			return
		inventory.spend_materials({_selected_id: _quantity})
		inventory.add_credits(order["total"])

	MarketService.apply_trade(_selected_id, _quantity, direction)
	_show_impact(order, price_before, direction)
	_refresh()


## Quotes the move the order actually produced rather than the term that
## caused it, so the banner and the big price above it can never disagree.
func _show_impact(order: Dictionary, price_before: int, direction: int) -> void:
	var change: float = 0.0
	if price_before > 0:
		change = float(MarketService.get_price(_selected_id) - price_before) / price_before
	var percent: float = change * 100.0

	var message: String = "Your %du %s filled at %d cr and %s %s %s%.1f%% here" % [
		_quantity, "buy" if direction > 0 else "sale", order["unit_price"],
		"lifted" if direction > 0 else "pushed",
		MaterialCatalog.display_name(_selected_id), "+" if percent >= 0.0 else "", percent,
	]
	var parts: PackedStringArray = PackedStringArray()
	for entry in MarketService.get_spillover(change):
		parts.append("%+.1f%% at %s" % [entry["percent"], entry["name"]])
	_trade_bar.show_impact(message, " · ".join(parts),
		MarketTheme.CYAN_BRIGHT if direction > 0 else MarketTheme.AMBER)


func _buy_blocker(order: Dictionary) -> String:
	if not inventory.has_cargo_space(_quantity):
		return "HOLD FULL"
	if not inventory.has_credits(order["total"]):
		return "NOT ENOUGH CREDITS"
	return ""


func _sell_blocker() -> String:
	if inventory.get_material_amount(_selected_id) < _quantity:
		return "NOTHING TO SELL"
	return ""


func _repair() -> void:
	if ship == null or not ship.needs_repair():
		return
	if inventory.spend_credits(ship.get_repair_cost()):
		ship.repair_fully()
		_refresh()


# --- Refresh ----------------------------------------------------------------

func _on_market_ticked() -> void:
	if visible:
		_refresh()
		_ticker.rebuild(_material_ids)


func _on_inventory_changed(_value) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if inventory == null or _selected_id.is_empty():
		return
	_header.refresh(inventory.get_credits(), inventory.get_cargo_used(),
		int(inventory.get_cargo_capacity()))
	_list.refresh(inventory.get_all_materials())
	_focus.refresh()
	_refresh_trade_bar()
	_rail.refresh_nearby(_selected_id)
	_rail.refresh_forces()
	_rail.refresh_activity()


func _refresh_trade_bar() -> void:
	if inventory == null or _selected_id.is_empty():
		return
	var buy: Dictionary = MarketService.quote(_selected_id, _quantity, 1)
	var sell: Dictionary = MarketService.quote(_selected_id, _quantity, -1)
	_trade_bar.refresh(inventory.get_material_amount(_selected_id),
		buy["total"], sell["total"], _buy_blocker(buy), _sell_blocker())


## Only the footer needs per-frame work: its tick countdown is the one readout
## that has to move between market ticks.
func _process(_delta: float) -> void:
	var repair_cost: int = 0
	if ship != null and ship.needs_repair():
		repair_cost = ship.get_repair_cost()
	_footer.refresh(repair_cost)


# --- Input ------------------------------------------------------------------

## Handled in _input, not _unhandled_input, so the market's letter and number
## keys never also reach the gameplay actions bound to the same keys (B opens
## the ship builder, 1–3 toggle ship systems).
func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var consumed: bool = true
	if event.is_action_pressed("market_select_previous"):
		_step_selection(-1)
	elif event.is_action_pressed("market_select_next"):
		_step_selection(1)
	elif event.is_action_pressed("market_buy"):
		_trade(1)
	elif event.is_action_pressed("market_sell"):
		_trade(-1)
	elif event.is_action_pressed("market_repair"):
		_repair()
	else:
		consumed = _handle_quantity_keys(event)
	if consumed:
		get_viewport().set_input_as_handled()


func _handle_quantity_keys(event: InputEvent) -> bool:
	for index in QUANTITY_ACTIONS.size():
		if event.is_action_pressed(QUANTITY_ACTIONS[index]):
			_set_quantity(MarketTradeBar.QUANTITIES[index])
			return true
	return false

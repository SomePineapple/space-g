extends GamePanel

## Home-base trading screen: buy/sell every raw material, plus paid hull repair.
## Layout constants, the menu-panel plumbing and the home-base gate live on
## GamePanel.
const TRADE_QUANTITY: int = 10

## Every raw material is tradeable — pulled from the catalog so a future
## fifth material shows up here automatically (see MaterialCatalog.ALL_IDS).
static var TRADEABLE_MATERIAL_IDS: Array[String] = MaterialCatalog.ALL_IDS

var _credits_label: Label
var _repair_label: Label
var _repair_button: Button
var _rows: Dictionary = {}


func _init() -> void:
	toggle_action = "toggle_trade"
	requires_home_base = true


func _setup() -> void:
	if ship == null:
		return

	inventory.materials_changed.connect(_on_state_changed)
	inventory.credits_changed.connect(_on_state_changed)
	ship.health_changed.connect(_on_health_changed)

	_build_ui()
	_refresh()


func _on_opened() -> void:
	_refresh()


func _build_ui() -> void:
	var repair_row_top: float = HEADER_HEIGHT
	var materials_top: float = repair_row_top + ROW_HEIGHT + ROW_GAP
	var content_height: float = materials_top + TRADEABLE_MATERIAL_IDS.size() * (ROW_HEIGHT + ROW_GAP)
	# Header text is empty: the credits readout occupies the header row here.
	var panel: Control = build_panel_root(content_height, "")

	_credits_label = Label.new()
	_credits_label.position = Vector2.ZERO
	_credits_label.size = Vector2(panel_width, HEADER_HEIGHT)
	panel.add_child(_credits_label)

	var repair_row: HBoxContainer = build_row(panel, repair_row_top)

	_repair_label = Label.new()
	_repair_label.custom_minimum_size = Vector2(190, ROW_HEIGHT)
	repair_row.add_child(_repair_label)

	_repair_button = Button.new()
	_repair_button.custom_minimum_size = Vector2(220, ROW_HEIGHT)
	_repair_button.pressed.connect(_on_repair_pressed)
	repair_row.add_child(_repair_button)

	for i in TRADEABLE_MATERIAL_IDS.size():
		var material_id: String = TRADEABLE_MATERIAL_IDS[i]
		var row: HBoxContainer = build_row(panel, materials_top + i * (ROW_HEIGHT + ROW_GAP))

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(190, ROW_HEIGHT)
		row.add_child(name_label)

		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(105, ROW_HEIGHT)
		buy_button.pressed.connect(_on_buy_pressed.bind(material_id))
		row.add_child(buy_button)

		var sell_button := Button.new()
		sell_button.custom_minimum_size = Vector2(105, ROW_HEIGHT)
		sell_button.pressed.connect(_on_sell_pressed.bind(material_id))
		row.add_child(sell_button)

		_rows[material_id] = {"name": name_label, "buy": buy_button, "sell": sell_button}


func _on_repair_pressed() -> void:
	var cost: int = ship.get_repair_cost()
	if not inventory.spend_credits(cost):
		return
	ship.repair_fully()


func _on_buy_pressed(material_id: String) -> void:
	var cost: int = MaterialCatalog.buy_price(material_id) * TRADE_QUANTITY
	if not inventory.spend_credits(cost):
		return
	inventory.add_material(material_id, TRADE_QUANTITY)


func _on_sell_pressed(material_id: String) -> void:
	if not inventory.spend_materials({material_id: TRADE_QUANTITY}):
		return
	inventory.add_credits(MaterialCatalog.sell_price(material_id) * TRADE_QUANTITY)


func _on_state_changed(_value) -> void:
	_refresh()


func _on_health_changed(_current: float, _max_health: float) -> void:
	_refresh()


func _refresh() -> void:
	if inventory == null or _credits_label == null:
		return

	_credits_label.text = "Credits: %d" % inventory.get_credits()

	_repair_label.text = "Hull: %d / %d" % [ship.get_current_health(), ship.get_max_health()]
	if ship.needs_repair():
		var repair_cost: int = ship.get_repair_cost()
		_repair_button.text = "Repair Fully (%d cr)" % repair_cost
		_repair_button.disabled = not inventory.has_credits(repair_cost)
	else:
		_repair_button.text = "Fully Repaired"
		_repair_button.disabled = true

	for material_id in TRADEABLE_MATERIAL_IDS:
		var row: Dictionary = _rows[material_id]
		var owned: int = inventory.get_material_amount(material_id)
		var buy_cost: int = MaterialCatalog.buy_price(material_id) * TRADE_QUANTITY
		var sell_gain: int = MaterialCatalog.sell_price(material_id) * TRADE_QUANTITY

		row["name"].text = "%s: %d" % [MaterialCatalog.display_name(material_id), owned]
		row["buy"].text = "Buy %d (%d cr)" % [TRADE_QUANTITY, buy_cost]
		row["buy"].disabled = not inventory.has_credits(buy_cost)
		row["sell"].text = "Sell %d (+%d cr)" % [TRADE_QUANTITY, sell_gain]
		row["sell"].disabled = owned < TRADE_QUANTITY

extends CanvasLayer

const TRADE_QUANTITY: int = 10
const ROW_HEIGHT: float = 32.0
const ROW_WIDTH: float = 420.0
const CONTENT_TOP: float = 108.0
const CONTENT_LEFT: float = 20.0
const HEADER_HEIGHT: float = 30.0
const ROW_GAP: float = 6.0
const BACKGROUND_MARGIN: float = 10.0
const BACKGROUND_COLOR: Color = Color(0.05, 0.07, 0.1, 0.55)

const TRADEABLE_MATERIAL_IDS: Array[String] = [
	Materials.STEEL_ALLOY, Materials.ELECTRONICS, Materials.REACTOR_COMPONENTS,
]

## Only lets the trade panel open near the region's home base marker,
## matching the ship builder's and upgrade panel's gating.
@export var home_base_range: float = 300.0

var _ship: Ship
var _inventory: Inventory
var _credits_label: Label
var _rows: Dictionary = {}


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to this specific panel.
	add_to_group("menu_panel")

	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_ship = players[0]
	_inventory = _ship.get_node("Inventory")
	_inventory.materials_changed.connect(_on_state_changed)
	_inventory.credits_changed.connect(_on_state_changed)

	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_trade"):
		return

	if visible:
		visible = false
		return

	if _is_near_home_base():
		visible = true
		_refresh()


func _is_near_home_base() -> bool:
	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if _ship == null or home_bases.is_empty():
		return false
	return _ship.global_position.distance_to(home_bases[0].global_position) <= home_base_range


func _build_ui() -> void:
	var panel := Control.new()
	panel.position = Vector2(CONTENT_LEFT, CONTENT_TOP)
	add_child(panel)

	var content_height: float = HEADER_HEIGHT + TRADEABLE_MATERIAL_IDS.size() * (ROW_HEIGHT + ROW_GAP)

	var background := ColorRect.new()
	background.position = Vector2(-BACKGROUND_MARGIN, -BACKGROUND_MARGIN)
	background.size = Vector2(ROW_WIDTH + BACKGROUND_MARGIN * 2, content_height + BACKGROUND_MARGIN * 2)
	background.color = BACKGROUND_COLOR
	panel.add_child(background)

	_credits_label = Label.new()
	_credits_label.position = Vector2(0, 0)
	_credits_label.size = Vector2(ROW_WIDTH, HEADER_HEIGHT)
	panel.add_child(_credits_label)

	for i in TRADEABLE_MATERIAL_IDS.size():
		var material_id: String = TRADEABLE_MATERIAL_IDS[i]
		var row_top: float = HEADER_HEIGHT + i * (ROW_HEIGHT + ROW_GAP)

		var row := HBoxContainer.new()
		row.position = Vector2(0, row_top)
		row.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)

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


func _on_buy_pressed(material_id: String) -> void:
	var cost: int = Materials.buy_price(material_id) * TRADE_QUANTITY
	if not _inventory.spend_credits(cost):
		return
	_inventory.add_material(material_id, TRADE_QUANTITY)


func _on_sell_pressed(material_id: String) -> void:
	if not _inventory.spend_materials({material_id: TRADE_QUANTITY}):
		return
	_inventory.add_credits(Materials.sell_price(material_id) * TRADE_QUANTITY)


func _on_state_changed(_value) -> void:
	_refresh()


func _refresh() -> void:
	if _inventory == null:
		return

	_credits_label.text = "Credits: %d" % _inventory.get_credits()

	for material_id in TRADEABLE_MATERIAL_IDS:
		var row: Dictionary = _rows[material_id]
		var owned: int = _inventory.get_material_amount(material_id)
		var buy_cost: int = Materials.buy_price(material_id) * TRADE_QUANTITY
		var sell_gain: int = Materials.sell_price(material_id) * TRADE_QUANTITY

		row["name"].text = "%s: %d" % [Materials.display_name(material_id), owned]
		row["buy"].text = "Buy %d (%d cr)" % [TRADE_QUANTITY, buy_cost]
		row["buy"].disabled = not _inventory.has_credits(buy_cost)
		row["sell"].text = "Sell %d (+%d cr)" % [TRADE_QUANTITY, sell_gain]
		row["sell"].disabled = owned < TRADE_QUANTITY

extends CanvasLayer

## Dedicated cargo-hold screen (Phase 3.2/3.3 spec) — capacity readout plus a
## discard button per material. Deliberately not gated to home-base range
## like TradePanel/ShipBuilderPanel: discarding cargo is something a player
## may need mid-flight (e.g. to free space for better salvage), not a base
## activity.
const DISCARD_QUANTITY: int = 10
const ROW_HEIGHT: float = 32.0
const ROW_WIDTH: float = 420.0
const CONTENT_TOP: float = 108.0
const CONTENT_LEFT: float = 20.0
const HEADER_HEIGHT: float = 30.0
const CAPACITY_HEIGHT: float = 24.0
const ROW_GAP: float = 6.0
const BACKGROUND_MARGIN: float = 10.0
const BACKGROUND_COLOR: Color = Color(0.05, 0.07, 0.1, 0.55)

const CARGO_MATERIAL_IDS: Array[String] = [
	Materials.STEEL_ALLOY, Materials.ELECTRONICS, Materials.REACTOR_COMPONENTS,
]

var _inventory: Inventory
var _capacity_label: Label
var _rows: Dictionary = {}


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to this specific panel.
	add_to_group("menu_panel")

	var players: Array = get_tree().get_nodes_in_group("player_ship")
	if players.is_empty():
		return

	_inventory = players[0].get_node("Inventory")
	_inventory.materials_changed.connect(_on_state_changed)
	_inventory.cargo_capacity_changed.connect(_on_state_changed)

	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_cargo"):
		return
	visible = not visible
	if visible:
		_refresh()


func _build_ui() -> void:
	var panel := Control.new()
	panel.position = Vector2(CONTENT_LEFT, CONTENT_TOP)
	add_child(panel)

	var materials_top: float = HEADER_HEIGHT + CAPACITY_HEIGHT + ROW_GAP
	var content_height: float = materials_top + CARGO_MATERIAL_IDS.size() * (ROW_HEIGHT + ROW_GAP)

	var background := ColorRect.new()
	background.position = Vector2(-BACKGROUND_MARGIN, -BACKGROUND_MARGIN)
	background.size = Vector2(ROW_WIDTH + BACKGROUND_MARGIN * 2, content_height + BACKGROUND_MARGIN * 2)
	background.color = BACKGROUND_COLOR
	panel.add_child(background)

	var header := Label.new()
	header.position = Vector2(0, 0)
	header.size = Vector2(ROW_WIDTH, HEADER_HEIGHT)
	header.text = "Cargo Hold"
	header.add_theme_font_size_override("font_size", 18)
	panel.add_child(header)

	_capacity_label = Label.new()
	_capacity_label.position = Vector2(0, HEADER_HEIGHT)
	_capacity_label.size = Vector2(ROW_WIDTH, CAPACITY_HEIGHT)
	panel.add_child(_capacity_label)

	for i in CARGO_MATERIAL_IDS.size():
		var material_id: String = CARGO_MATERIAL_IDS[i]
		var row_top: float = materials_top + i * (ROW_HEIGHT + ROW_GAP)

		var row := HBoxContainer.new()
		row.position = Vector2(0, row_top)
		row.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(230, ROW_HEIGHT)
		row.add_child(name_label)

		var discard_button := Button.new()
		var discard_all_button := Button.new()
		discard_button.custom_minimum_size = Vector2(160, ROW_HEIGHT)
		discard_button.pressed.connect(_on_discard_pressed.bind(material_id))
		row.add_child(discard_button)

		discard_all_button.text = "Discard All"
		discard_all_button.custom_minimum_size = Vector2(100, ROW_HEIGHT)
		discard_all_button.pressed.connect(_on_discard_all_pressed.bind(material_id))
		row.add_child(discard_all_button)

		_rows[material_id] = {"name": name_label, "discard": discard_button, "discard_all": discard_all_button}


func _on_discard_pressed(material_id: String) -> void:
	_inventory.discard_material(material_id, DISCARD_QUANTITY)


func _on_discard_all_pressed(material_id: String) -> void:
	_inventory.discard_material(material_id, _inventory.get_material_amount(material_id))


func _on_state_changed(_value) -> void:
	_refresh()


func _refresh() -> void:
	if _inventory == null:
		return

	_capacity_label.text = "Capacity: %d / %.0f" % [_inventory.get_cargo_used(), _inventory.get_cargo_capacity()]

	for material_id in CARGO_MATERIAL_IDS:
		var row: Dictionary = _rows[material_id]
		var owned: int = _inventory.get_material_amount(material_id)
		row["name"].text = "%s: %d" % [Materials.display_name(material_id), owned]
		row["discard"].text = "Discard %d" % DISCARD_QUANTITY
		row["discard"].disabled = owned <= 0
		row["discard_all"].disabled = owned <= 0

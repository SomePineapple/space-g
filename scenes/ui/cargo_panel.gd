extends GamePanel

## Dedicated cargo-hold screen (Phase 3.2/3.3 spec) — capacity readout plus a
## discard button per material. Deliberately not gated to home-base range
## like TradePanel/ShipBuilderPanel: discarding cargo is something a player
## may need mid-flight (e.g. to free space for better salvage), not a base
## activity.
##
## Layout constants, the menu-panel plumbing and the home-base gate all live on
## GamePanel now; what remains here is this screen's own content.
const DISCARD_QUANTITY: int = 10
const CAPACITY_HEIGHT: float = 24.0

## Pulled from the catalog so a future fifth material shows up here
## automatically (see MaterialCatalog.ALL_IDS).
static var CARGO_MATERIAL_IDS: Array[String] = MaterialCatalog.ALL_IDS

var _capacity_label: Label
var _rows: Dictionary = {}


func _init() -> void:
	toggle_action = "toggle_cargo"


func _setup() -> void:
	if inventory == null:
		return

	inventory.materials_changed.connect(_on_state_changed)
	inventory.cargo_capacity_changed.connect(_on_state_changed)

	_build_ui()
	_refresh()


func _on_opened() -> void:
	_refresh()


func _build_ui() -> void:
	var materials_top: float = HEADER_HEIGHT + CAPACITY_HEIGHT + ROW_GAP
	var content_height: float = materials_top + CARGO_MATERIAL_IDS.size() * (ROW_HEIGHT + ROW_GAP)
	var panel: Control = build_panel_root(content_height, "Cargo Hold")

	_capacity_label = Label.new()
	_capacity_label.position = Vector2(0, HEADER_HEIGHT)
	_capacity_label.size = Vector2(panel_width, CAPACITY_HEIGHT)
	panel.add_child(_capacity_label)

	for i in CARGO_MATERIAL_IDS.size():
		var material_id: String = CARGO_MATERIAL_IDS[i]
		var row: HBoxContainer = build_row(panel, materials_top + i * (ROW_HEIGHT + ROW_GAP))

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(230, ROW_HEIGHT)
		row.add_child(name_label)

		var discard_button := Button.new()
		discard_button.custom_minimum_size = Vector2(160, ROW_HEIGHT)
		discard_button.pressed.connect(_on_discard_pressed.bind(material_id))
		row.add_child(discard_button)

		var discard_all_button := Button.new()
		discard_all_button.text = "Discard All"
		discard_all_button.custom_minimum_size = Vector2(100, ROW_HEIGHT)
		discard_all_button.pressed.connect(_on_discard_all_pressed.bind(material_id))
		row.add_child(discard_all_button)

		_rows[material_id] = {"name": name_label, "discard": discard_button, "discard_all": discard_all_button}


func _on_discard_pressed(material_id: String) -> void:
	inventory.discard_material(material_id, DISCARD_QUANTITY)


func _on_discard_all_pressed(material_id: String) -> void:
	inventory.discard_material(material_id, inventory.get_material_amount(material_id))


func _on_state_changed(_value) -> void:
	_refresh()


func _refresh() -> void:
	if inventory == null or _capacity_label == null:
		return

	_capacity_label.text = "Capacity: %d / %.0f" % [inventory.get_cargo_used(), inventory.get_cargo_capacity()]

	for material_id in CARGO_MATERIAL_IDS:
		var row: Dictionary = _rows[material_id]
		var owned: int = inventory.get_material_amount(material_id)
		row["name"].text = "%s: %d" % [MaterialCatalog.display_name(material_id), owned]
		row["discard"].text = "Discard %d" % DISCARD_QUANTITY
		row["discard"].disabled = owned <= 0
		row["discard_all"].disabled = owned <= 0

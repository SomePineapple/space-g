extends GamePanel

## Phase 5.1 crafting screen — one row per CraftingCatalog recipe, each with
## its own quantity selector and Craft button. Recipe data (inputs/outputs)
## lives entirely in CraftingRecipe/CraftingCatalog; this panel only reads
## it, so a new recipe needs zero UI changes (see CraftingCatalog).
##
## Layout constants and the menu-panel plumbing live on GamePanel.
const STATUS_HEIGHT: float = 22.0

var _status_label: Label
## recipe_id -> {"info": Label, "quantity": SpinBox, "craft": Button}
var _rows: Dictionary = {}


func _init() -> void:
	toggle_action = "toggle_crafting"
	# Wider than the default: recipe rows carry an ingredient list.
	panel_width = 460.0


func _setup() -> void:
	if inventory == null:
		return

	inventory.materials_changed.connect(_on_state_changed)
	inventory.components_changed.connect(_on_state_changed)
	inventory.cargo_capacity_changed.connect(_on_state_changed)

	_build_ui()
	_refresh()


func _on_opened() -> void:
	_refresh()


func _build_ui() -> void:
	var recipes: Array[CraftingRecipe] = CraftingCatalog.get_all()
	var rows_top: float = HEADER_HEIGHT + STATUS_HEIGHT + ROW_GAP
	var content_height: float = rows_top + recipes.size() * (ROW_HEIGHT + ROW_GAP)
	var panel: Control = build_panel_root(content_height, "Crafting")

	_status_label = Label.new()
	_status_label.position = Vector2(0, HEADER_HEIGHT)
	_status_label.size = Vector2(panel_width, STATUS_HEIGHT)
	_status_label.clip_text = true
	_status_label.text = "Select a quantity and craft."
	panel.add_child(_status_label)

	for i in recipes.size():
		var recipe: CraftingRecipe = recipes[i]
		var row: HBoxContainer = build_row(panel, rows_top + i * (ROW_HEIGHT + ROW_GAP))
		row.add_theme_constant_override("separation", 8)

		var info_label := Label.new()
		info_label.custom_minimum_size = Vector2(300, ROW_HEIGHT)
		info_label.clip_text = true
		row.add_child(info_label)

		var quantity_box := SpinBox.new()
		quantity_box.min_value = 1
		quantity_box.max_value = 999
		quantity_box.value = 1
		quantity_box.custom_minimum_size = Vector2(60, ROW_HEIGHT)
		row.add_child(quantity_box)

		var craft_button := Button.new()
		craft_button.text = "Craft"
		craft_button.custom_minimum_size = Vector2(70, ROW_HEIGHT)
		craft_button.pressed.connect(_on_craft_pressed.bind(recipe.id))
		row.add_child(craft_button)

		quantity_box.value_changed.connect(_on_quantity_changed.bind(recipe.id))

		_rows[recipe.id] = {"info": info_label, "quantity": quantity_box, "craft": craft_button}


func _on_craft_pressed(recipe_id: String) -> void:
	if inventory == null:
		return

	var recipe: CraftingRecipe = CraftingCatalog.get_by_id(recipe_id)
	var quantity: int = int(_rows[recipe_id]["quantity"].value)

	if not inventory.can_craft(recipe, quantity):
		if not inventory.has_cargo_space(recipe.output_amount * quantity):
			_status_label.text = "Cannot craft %s: not enough cargo space." % recipe.display_name
		else:
			_status_label.text = "Cannot craft %s: missing ingredients." % recipe.display_name
		return

	inventory.craft(recipe, quantity)
	_status_label.text = "Crafted %d %s." % [recipe.output_amount * quantity, recipe.display_name]


func _on_state_changed(_value) -> void:
	_refresh()


func _refresh() -> void:
	if inventory == null:
		return

	for recipe in CraftingCatalog.get_all():
		var row: Dictionary = _rows[recipe.id]
		var quantity: int = int(row["quantity"].value)

		row["info"].text = "%s: %s -> %d owned" % [
			recipe.display_name, _format_inputs(recipe), inventory.get_component_amount(recipe.output_component_id),
		]
		row["craft"].disabled = not inventory.can_craft(recipe, quantity)
		row["quantity"].value_changed.connect(_on_quantity_changed.bind(recipe.id), CONNECT_REFERENCE_COUNTED)


func _on_quantity_changed(_new_value: float, recipe_id: String) -> void:
	var recipe: CraftingRecipe = CraftingCatalog.get_by_id(recipe_id)
	var quantity: int = int(_rows[recipe_id]["quantity"].value)
	_rows[recipe_id]["craft"].disabled = inventory == null or not inventory.can_craft(recipe, quantity)


func _format_inputs(recipe: CraftingRecipe) -> String:
	var parts: Array = []
	for material_id in recipe.input_materials:
		parts.append("%d %s" % [recipe.input_materials[material_id], MaterialCatalog.display_name(material_id)])
	for component_id in recipe.input_components:
		parts.append("%d %s" % [recipe.input_components[component_id], ComponentCatalog.display_name(component_id)])
	return ", ".join(parts)

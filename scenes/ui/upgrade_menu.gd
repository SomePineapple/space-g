extends CanvasLayer

## Standalone per-instance module upgrade menu (Phase 8.1), opened with a
## dedicated key (toggle_upgrades — "U") rather than a button buried inside
## the ship builder, per explicit request: category submenus first (Weapons,
## Sensors, ...), then pick which mounted instance of that category to
## upgrade, then its radial tree (ModuleUpgradeTree, same overlay class the
## ship builder briefly used and this replaced entirely).
##
## Operates on the *live* player ship's own ship_layout, not the ship
## builder's in-progress working_layout — unlike the builder, this screen
## never rebuilds the ship wholesale (see Ship.apply_instance_upgrade_effect),
## so it's safe to use without silently resetting health/module condition.

@export var home_base_range: float = 300.0

const CATEGORY_WIDTH: float = 150.0
const INSTANCE_LIST_WIDTH: float = 340.0
const PANEL_HEIGHT: float = 420.0
const ROW_HEIGHT: float = 34.0

var _ship: Ship
var _inventory: Inventory

var _category_container: VBoxContainer
var _instance_container: VBoxContainer

var _tree_overlay: ModuleUpgradeTree = null
var _tree_overlay_placement: ModulePlacement = null

var _selected_category: String = ""
## category label -> Array[String] (module_type_id)
var _categories: Dictionary = {}
var _category_order: Array[String] = []


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to this specific panel.
	add_to_group("menu_panel")

	_build_categories()

	_ship = PlayerContext.get_ship()
	if _ship != null:
		_inventory = _ship.get_inventory()

	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_upgrades"):
		return

	if visible:
		visible = false
		_close_tree_overlay()
		return

	if _is_near_home_base():
		visible = true
		_refresh_categories()


func _is_near_home_base() -> bool:
	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if _ship == null or home_bases.is_empty():
		return false
	return _ship.global_position.distance_to(home_bases[0].global_position) <= home_base_range


## Groups every ModuleType into a small set of player-facing categories —
## purely a UI grouping, doesn't touch ModuleType.hardpoint_category itself.
## Every current module type matches one of these buckets; a hypothetical
## future one that doesn't falls back to "Other" rather than being dropped.
func _category_for(module_type: ModuleType) -> String:
	match module_type.hardpoint_category:
		"weapon":
			return "Weapons"
		"missile":
			return "Missiles"
		"radar", "scanner", "tractor":
			return "Sensors"
		"grinder":
			return "Mining"
	match module_type.id:
		"engine":
			return "Propulsion"
		"reactor_mk1", "battery_mk1":
			return "Power"
		"storage_mk1":
			return "Storage"
		"hull", "heavy_hull", "strut", "command_core":
			return "Hull"
	return "Other"


func _build_categories() -> void:
	_categories.clear()
	_category_order.clear()
	for module_type in ModuleCatalog.get_all():
		var label: String = _category_for(module_type)
		if not _categories.has(label):
			_categories[label] = []
			_category_order.append(label)
		_categories[label].append(module_type.id)


func _build_ui() -> void:
	var panel := Control.new()
	panel.position = Vector2(20, 108)
	add_child(panel)

	var bg := ColorRect.new()
	bg.size = Vector2(CATEGORY_WIDTH + INSTANCE_LIST_WIDTH + 24, PANEL_HEIGHT)
	bg.color = Color(0.05, 0.07, 0.1, 0.75)
	panel.add_child(bg)

	var title := Label.new()
	title.text = "Module Upgrades"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 18)
	panel.add_child(title)

	_category_container = VBoxContainer.new()
	_category_container.position = Vector2(8, 36)
	_category_container.size = Vector2(CATEGORY_WIDTH - 16, PANEL_HEIGHT - 44)
	_category_container.add_theme_constant_override("separation", 4)
	panel.add_child(_category_container)

	_instance_container = VBoxContainer.new()
	_instance_container.position = Vector2(CATEGORY_WIDTH + 16, 36)
	_instance_container.size = Vector2(INSTANCE_LIST_WIDTH - 16, PANEL_HEIGHT - 44)
	_instance_container.add_theme_constant_override("separation", 4)
	panel.add_child(_instance_container)


func _refresh_categories() -> void:
	for child in _category_container.get_children():
		child.queue_free()

	for label in _category_order:
		var button := Button.new()
		button.text = label
		button.toggle_mode = true
		button.button_pressed = (label == _selected_category)
		button.pressed.connect(_on_category_pressed.bind(label))
		_category_container.add_child(button)

	_refresh_instances()


func _on_category_pressed(label: String) -> void:
	_selected_category = label
	for child in _category_container.get_children():
		child.button_pressed = (child.text == label)
	_refresh_instances()


## Lists every placement on the live ship whose type falls in the selected
## category, one button per mounted instance — a category can have zero, one
## or several (e.g. two Weapon hardpoints), each upgraded independently.
func _refresh_instances() -> void:
	for child in _instance_container.get_children():
		child.queue_free()

	if _selected_category.is_empty() or _ship == null or _ship.ship_layout == null:
		return

	var type_ids: Array = _categories.get(_selected_category, [])
	var placements: Array = _ship.ship_layout.placements.filter(func(p): return type_ids.has(p.module_type_id))

	if placements.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No %s modules mounted." % _selected_category
		_instance_container.add_child(empty_label)
		return

	for placement in placements:
		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		var tree_size: int = ModuleUpgradeService.get_tree_for_placement(placement).size()
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)

		if tree_size == 0:
			button.text = "%s at (%d, %d) — no upgrades yet" % [module_type.display_name, placement.hex_coord.x, placement.hex_coord.y]
			button.disabled = true
		else:
			var level: int = placement.ensure_instance().get_level()
			button.text = "%s at (%d, %d) — Level %d/%d" % [module_type.display_name, placement.hex_coord.x, placement.hex_coord.y, level, tree_size]
			button.pressed.connect(_on_instance_pressed.bind(placement))

		_instance_container.add_child(button)


func _on_instance_pressed(placement: ModulePlacement) -> void:
	if _tree_overlay == null:
		_tree_overlay = ModuleUpgradeTree.new()
		add_child(_tree_overlay)
		_tree_overlay.closed.connect(_close_tree_overlay)
		_tree_overlay.upgrade_unlocked.connect(_on_upgrade_unlocked)

	_tree_overlay_placement = placement
	_tree_overlay.open(_ship.ship_layout, _inventory, placement)


func _close_tree_overlay() -> void:
	if _tree_overlay != null:
		_tree_overlay.queue_free()
	_tree_overlay = null
	_tree_overlay_placement = null


## Applies the just-unlocked upgrade to the live ship (see
## Ship.apply_instance_upgrade_effect) and refreshes the instance list's
## level readout — costs were already spent inside ModuleUpgradeTree itself.
func _on_upgrade_unlocked(upgrade_id: String) -> void:
	if _tree_overlay_placement == null:
		return
	var node: ModuleUpgradeNode = ModuleUpgradeCatalog.get_by_id(upgrade_id)
	_ship.apply_instance_upgrade_effect(_tree_overlay_placement, node)
	_refresh_instances()

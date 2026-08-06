class_name GamePanel
extends CanvasLayer

## Shared behaviour for the full-screen gameplay menus (cargo, crafting, trade,
## upgrades, ship builder).
##
## Each of them had its own copy of: the same eight layout constants, the
## hide-and-join-"menu_panel" opening lines, the resolve-the-player's-ship-and-
## inventory lookup, a toggle-on-an-action handler, an identical near-the-home-
## base range check, and the positioned-Control-plus-translucent-background-
## plus-header scaffolding every _build_ui() starts with.
##
## The home-base gate in particular was four separate copies of the same
## function, which is the kind of thing that quietly drifts apart.
##
## Panels bind to PlayerContext rather than looking up a player ship
## themselves, and rebind when it changes — so a panel left open across a warp
## follows the new ship instead of holding a freed one, and in a crewed-ship
## session every station's panels resolve to the shared ship.

const ROW_HEIGHT: float = 32.0
const CONTENT_TOP: float = 108.0
const CONTENT_LEFT: float = 20.0
const HEADER_HEIGHT: float = 30.0
const ROW_GAP: float = 6.0
const BACKGROUND_MARGIN: float = 10.0
const BACKGROUND_COLOR: Color = Color(0.05, 0.07, 0.1, 0.55)
const HEADER_FONT_SIZE: int = 18

## Input action that opens and closes this panel. Empty means the subclass
## handles its own opening (see ShipBuilderPanel, which shares its toggle with
## extra in-panel hotkeys).
@export var toggle_action: String = ""
## Whether the panel may only be opened near the region's home base marker, so
## building and spending happen at a fixed "home" rather than mid-flight.
@export var requires_home_base: bool = false
@export var home_base_range: float = 300.0
## Width of the panel body; a couple of screens are wider than the default.
@export var panel_width: float = 420.0

## The local player's ship and its inventory, kept current via PlayerContext.
var ship: Ship
var inventory: Inventory


func _ready() -> void:
	visible = false
	# So gameplay input (ship_input.gd) can suspend itself while any menu is
	# open, without hard-coding a reference to any specific panel.
	add_to_group("menu_panel")

	_adopt_ship(PlayerContext.get_ship())
	_setup()
	# Connected only after _setup(), so _on_ship_bound() never fires before the
	# subclass has built the UI it would be repointing.
	PlayerContext.ship_changed.connect(_rebind_ship)


func _adopt_ship(new_ship: Node) -> void:
	ship = new_ship
	inventory = ship.get_inventory() if ship != null else null


func _rebind_ship(new_ship: Node) -> void:
	_adopt_ship(new_ship)
	_on_ship_bound()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action.is_empty() or not event.is_action_pressed(toggle_action):
		return
	if visible:
		close()
	else:
		open()


## Returns false when the home-base gate refused — the caller can report that
## if it wants to; nothing does today, matching the previous silent behaviour.
func open() -> bool:
	if requires_home_base and not is_near_home_base():
		return false
	visible = true
	_on_opened()
	return true


func close() -> void:
	visible = false
	_on_closed()


func is_near_home_base() -> bool:
	var home_bases: Array = get_tree().get_nodes_in_group("home_base")
	if ship == null or home_bases.is_empty():
		return false
	return ship.global_position.distance_to(home_bases[0].global_position) <= home_base_range


## Builds the positioned body, its translucent background and its header, which
## every panel opened with. Returns the Control to add rows to; its origin is
## the top-left of the content area, so a row at y=HEADER_HEIGHT sits directly
## under the title.
func build_panel_root(content_height: float, header_text: String) -> Control:
	var panel := Control.new()
	panel.position = Vector2(CONTENT_LEFT, CONTENT_TOP)
	add_child(panel)

	var background := ColorRect.new()
	background.position = Vector2(-BACKGROUND_MARGIN, -BACKGROUND_MARGIN)
	background.size = Vector2(panel_width + BACKGROUND_MARGIN * 2, content_height + BACKGROUND_MARGIN * 2)
	background.color = BACKGROUND_COLOR
	panel.add_child(background)

	if not header_text.is_empty():
		var header := Label.new()
		header.position = Vector2.ZERO
		header.size = Vector2(panel_width, HEADER_HEIGHT)
		header.text = header_text
		header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
		panel.add_child(header)

	return panel


## A row container at the standard height, spanning the panel width.
func build_row(parent: Control, top: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position = Vector2(0, top)
	row.size = Vector2(panel_width, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row


# --- Virtuals ---------------------------------------------------------------

## Build the UI and connect to inventory signals. Runs once, after the first
## ship binding, so `ship`/`inventory` are already available (or null, if the
## panel loaded before any player ship existed).
func _setup() -> void:
	pass


## The local player's ship changed — a warp, a respawn. Repoint anything cached
## off the old one. Called on the initial bind too.
func _on_ship_bound() -> void:
	pass


func _on_opened() -> void:
	pass


func _on_closed() -> void:
	pass

extends Node2D

## THROWAWAY. Delete this whole folder when the question below is answered.
##
## `docs/spaceg-phase-4-spec-rev3.md` §6 asks for exactly one thing before any of
## Phase 4 is built: a scene that tests whether *"destroy the threat" versus
## "preserve the prize"* is fun. Ugly, hardcoded, deleted afterwards. The spec is
## explicit about why (§6, last paragraph): the pattern this project keeps
## repeating is systems built before the assumption under them is checked, and a
## "prototype" that is secretly the real implementation is how that happens
## again. So this file cheats wherever cheating is quicker, and every cheat is
## marked CHEAT. None of it is a first pass at 4.1 or 4.2.
##
## The bet, run twice on the same enemy:
##
##   Route A — shoot the gun    -> condition falls -> destroyed -> nothing to take
##   Route B — cut the conduit  -> gun goes dark, stays attached and intact
##                              -> cut it off at ~95%, reel it in, bolt it on
##
## Controls: fly and fight as normal. **P** rebuilds the enemy so both routes can
## be tried without restarting. The readout top-left names the state of every
## part on the enemy hull.

## The enemy's hull, hand-authored so the two routes are one hex apart.
##
##            (-1,2) (0,2) (1,2) (2,2) (3,2)     <- the bypass arm, all plating
##           /                               \
##   Core(0,0) -- Reactor(1,0)(2,0) -- CONDUIT(3,0) -- Gun(4,0)(5,0)
##                                                    /
##                                              (4,1) -- joins the bypass
##
## The shape is the whole point, and it is worth understanding before judging the
## result:
##
## - **Power** flows from the *reactor* outward, and only ever through conduits
##   (PowerGrid.CONDUCTING_TYPE_IDS). The gun's entire supply line is the single
##   conduit at (3,0); the bypass arm is plating, so it carries nothing.
## - **Attachment** is measured from the *core*, which is what the shipped
##   severance rule already does. The gun keeps its core path through the bypass.
##
## Those being two different graphs is what lets a cut leave the gun dark and
## still bolted on, instead of just knocking it off into space — which is what
## the shipped game does today and is not the same mechanic at all. If Phase 4
## gets built for real, this distinction is the load-bearing idea in it.
const CORE_CELL: Vector2i = Vector2i(0, 0)
const REACTOR_CELL: Vector2i = Vector2i(1, 0)
const CONDUIT_CELL: Vector2i = Vector2i(3, 0)
const GUN_CELL: Vector2i = Vector2i(4, 0)
const BYPASS_CELLS: Array[Vector2i] = [
	Vector2i(-1, 1), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2),
	Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 1),
]

@export var ship_scene: PackedScene = preload("res://scenes/player/ship.tscn")
@export var enemy_personality: ShipPersonality = preload("res://resources/ai/personality_test_dummy.tres")
@export var enemy_offset: Vector2 = Vector2(620.0, -120.0)

## CHEAT: the conduit is spawned already softened so the Slicer can open it without
## a preliminary gunfight. The real mechanic keeps the shoot-then-cut sequence
## (HullPaint.CUTTABLE_CONDITION); this is here so the bet can be tried in ten
## seconds rather than ninety.
@export var conduit_condition: float = 0.18

var _enemy: Ship = null
var _reactor_id: String = ""
var _gun_id: String = ""
var _unpowered_ids: Dictionary = {}
## placement_id -> the fire_rate the gun had before it went dark. CHEAT: zeroing
## fire_rate is how a gun is silenced here, because the shipped disable path runs
## through condition and condition is exactly what this prototype must not touch.
var _muted_fire_rates: Dictionary = {}
var _readout: Label = null


func _ready() -> void:
	_build_readout()
	_spawn_enemy()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_P:
		_spawn_enemy()


func _physics_process(_delta: float) -> void:
	_update_power()
	_update_readout()
	queue_redraw()


# --- The enemy ---------------------------------------------------------------

func _spawn_enemy() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	_unpowered_ids.clear()
	_muted_fire_rates.clear()

	var layout := ShipLayout.new()
	layout.place(ModuleCatalog.CORE_TYPE_ID, CORE_CELL, 0)
	var reactor: ModulePlacement = layout.place(ModuleCatalog.REACTOR_PAIR_TYPE_ID, REACTOR_CELL, 0)
	# Placed before the conduit so the bypass exists as a legal (connected) chain;
	# ShipLayout.place refuses anything not touching what is already there.
	for cell in BYPASS_CELLS:
		layout.place("hull", cell, 0)
	# A conduit, not plating: only conduits conduct now, so this one hex is the
	# gun's entire supply line — which is exactly the cell the probe wants the
	# player to cut. The bypass above stays plating, so it holds the gun on
	# without feeding it.
	layout.place(ModuleCatalog.CONDUIT_TYPE_ID, CONDUIT_CELL, 0)
	var gun: ModulePlacement = layout.place(ModuleCatalog.GUN_MK1_TYPE_ID, GUN_CELL, 0)

	if reactor == null or gun == null:
		push_error("phase4 probe: hand-authored layout did not place; check the cells")
		return

	_reactor_id = reactor.placement_id
	_gun_id = gun.placement_id

	_enemy = ship_scene.instantiate()
	_enemy.ship_layout = layout
	_enemy.personality = enemy_personality
	# A wreck that heals would undo the conduit softening within seconds, and a cut
	# in progress would regrow faster than the beam removes it.
	_enemy.regenerates_hull = false
	_enemy.position = enemy_offset
	add_child(_enemy)

	# Everything below has to go through `_enemy.ship_layout`, NOT the `layout`
	# built above: Ship deep-duplicates its layout in _ready, so the placements it
	# is actually flying are different objects with the same placement_ids. Worth
	# remembering if Phase 4 gets built for real — it cost a debug cycle here.
	# Both flags, not one: Ship.regenerates_hull and HullDamageModel.regenerates
	# are separate switches, and with only the first cleared the softened conduit
	# healed back past HullPaint.CUTTABLE_CONDITION within seconds and the beam
	# stopped biting. Cost a debug cycle here; it is in docs/gotchas.md territory.
	var damage_model: Node = _enemy.get_node_or_null("HullDamage")
	if damage_model != null:
		damage_model.regenerates = false

	var live: ShipLayout = _enemy.ship_layout
	for placement in live.placements:
		placement.ensure_instance()
	var conduit: ModulePlacement = live.get_placement_at(CONDUIT_CELL)
	if conduit != null and conduit.instance != null:
		conduit.instance.condition_fraction = conduit_condition
		conduit.instance.worst_condition_fraction = conduit_condition
	var renderer: Node2D = _enemy.get_hull_renderer_node()
	if renderer != null:
		renderer.queue_redraw()


# --- Power through structure -------------------------------------------------

## Flood-fill outward from the reactor. Anything it does not reach is cold.
##
## **Only conduits conduct.** Everything else — plating, the core, a gun — is a
## leaf: it can be *fed* by an adjacent conduit but it does not pass power on.
## The first version of this probe let every occupied cell conduct, and the result
## was that cutting the supply hex isolated nothing: power ran reactor -> core ->
## the far arm -> back round to the gun.
##
## The reason is worth writing down, because it will come back if Phase 4 is built
## for real. Power and attachment are both measured over the same hexes, so if
## everything conducts, then "the gun has one power path" and "the gun hangs on by
## one cell" become the same statement — and cutting that cell knocks the gun off
## into space instead of leaving it dark and attached, which is the shipped
## behaviour and a different mechanic entirely. Making structure conduct and
## modules not is what prises the two graphs apart: the gun can hang on the far
## arm while its only *power* route runs through the conduit.
##
## Deliberately recomputed from scratch every physics frame. It is O(cells) on a
## 13-cell hull and this is a throwaway — an incremental version would be the
## first piece of infrastructure built before the bet was checked.
func _update_power() -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _enemy.ship_layout == null:
		return
	var layout: ShipLayout = _enemy.ship_layout

	var reactor: ModulePlacement = layout.get_placement_by_id(_reactor_id)
	var powered_ids: Dictionary = {}
	if reactor != null and not _enemy.is_module_destroyed(_reactor_id):
		var reached_cells: Dictionary = {}
		var frontier: Array[Vector2i] = []
		for cell in layout.get_occupied_cells(reactor):
			reached_cells[cell] = true
			frontier.append(cell)
		powered_ids[_reactor_id] = true

		while not frontier.is_empty():
			for neighbor in HexUtils.neighbors(frontier.pop_back()):
				if reached_cells.has(neighbor):
					continue
				var occupant: ModulePlacement = layout.get_placement_at(neighbor)
				if occupant == null or _enemy.is_module_destroyed(occupant.placement_id):
					continue
				reached_cells[neighbor] = true
				powered_ids[occupant.placement_id] = true
				# Fed, but only a conduit passes it on. Read from PowerGrid rather
				# than kept as a second list here: the probe existing to test the
				# rule is no reason for it to disagree with the rule.
				if PowerGrid.CONDUCTING_TYPE_IDS.has(occupant.module_type_id):
					frontier.append(neighbor)

	_unpowered_ids.clear()
	for placement in layout.placements:
		if powered_ids.has(placement.placement_id):
			_restore(placement)
			continue
		if _enemy.is_module_destroyed(placement.placement_id):
			continue
		_unpowered_ids[placement.placement_id] = true
		_cut_power(placement)


func _cut_power(placement: ModulePlacement) -> void:
	if placement.instance != null:
		placement.instance.powered = false
	if _muted_fire_rates.has(placement.placement_id):
		return
	var node: Node = _hardpoint_for(placement.placement_id)
	if node != null and "fire_rate" in node:
		_muted_fire_rates[placement.placement_id] = node.fire_rate
		node.fire_rate = 0.0


func _restore(placement: ModulePlacement) -> void:
	if placement.instance != null:
		placement.instance.powered = true
	if not _muted_fire_rates.has(placement.placement_id):
		return
	var node: Node = _hardpoint_for(placement.placement_id)
	if node != null and "fire_rate" in node:
		node.fire_rate = _muted_fire_rates[placement.placement_id]
	_muted_fire_rates.erase(placement.placement_id)


## CHEAT: reaches into the ship's hardpoint bank by node name rather than through
## a public accessor, because Ship deliberately does not expose one and adding it
## would be building 4.2's plumbing before the bet is checked.
func _hardpoint_for(placement_id: String) -> Node:
	var bank: Node = _enemy.get_node_or_null("Hardpoints")
	if bank == null or not bank.has_method("get_node_for"):
		return null
	return bank.get_node_for(placement_id)


# --- Readout -----------------------------------------------------------------

## CHEAT: an overlay drawn straight onto the world, not a HUD element. §5 says the
## ship sprite is the readout and there is to be no new UI — this exists only so a
## tester can confirm what the graph thinks, and goes with the folder.
func _draw() -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _enemy.ship_layout == null:
		return
	var renderer: Node2D = _enemy.get_hull_renderer_node()
	if renderer == null:
		return

	for placement in _enemy.ship_layout.placements:
		if not _unpowered_ids.has(placement.placement_id):
			continue
		for cell in _enemy.ship_layout.get_occupied_cells(placement):
			var local: Vector2 = HexUtils.axial_to_pixel(cell, renderer.cell_size)
			var corners: PackedVector2Array = HexUtils.hex_corners(local, renderer.cell_size)
			var world := PackedVector2Array()
			for corner in corners:
				world.append(to_local(renderer.to_global(corner)))
			draw_colored_polygon(world, Color(0.0, 0.02, 0.06, 0.72))


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_readout = Label.new()
	_readout.position = Vector2(20, 20)
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override("outline_size", 6)
	layer.add_child(_readout)


func _update_readout() -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _enemy.ship_layout == null:
		_readout.text = "enemy gone — P to respawn"
		return

	var lines: PackedStringArray = ["PHASE 4 PROBE — P respawns the enemy", ""]
	for entry in [["REACTOR", _reactor_id], ["GUN", _gun_id]]:
		lines.append("%s  %s" % [entry[0], _describe(entry[1])])
	var conduit: ModulePlacement = _enemy.ship_layout.get_placement_at(CONDUIT_CELL)
	lines.append("CONDUIT  %s" % (_describe(conduit.placement_id) if conduit != null else "destroyed"))
	lines.append("")
	lines.append("Route A: shoot the gun.   Route B: cut the conduit, then cut what holds the gun on.")
	_readout.text = "\n".join(lines)


func _describe(placement_id: String) -> String:
	if placement_id.is_empty() or _enemy.is_module_destroyed(placement_id):
		return "DESTROYED — nothing to take"
	var placement: ModulePlacement = _enemy.ship_layout.get_placement_by_id(placement_id)
	if placement == null or placement.instance == null:
		return "gone"
	var condition: String = "%d%%" % roundi(placement.instance.condition_fraction * 100.0)
	if _unpowered_ids.has(placement_id):
		return "DISABLED at %s — dark, attached, cuttable" % condition
	return "functional at %s%s" % [
		condition, "  (cut-ready)" if HullPaint.is_cuttable(placement.instance) else ""]

class_name Inventory
extends Node

signal materials_changed(totals: Dictionary)
signal research_unlocked(module_type_id: String)
signal manufacturer_discovered(manufacturer_id: String)
signal credits_changed(amount: int)
signal cargo_capacity_changed(capacity: float)
## Emitted when try_add_material() rejects a pickup for lack of space — a
## live "storage full" cue for the HUD, distinct from materials_changed
## (which only fires on an actual change).
signal storage_full()
## Crafted intermediate components (Phase 5.1) — separate Dictionary from
## raw materials, same shared cargo capacity pool (see get_cargo_used()).
signal components_changed(totals: Dictionary)
## Built-but-not-placed module instances (Phase 5.2) — keyed by the same
## composite "module_type_id" / "module_type_id::manufacturer_id" string the
## ship builder's palette already uses (see ShipBuilderPanel._palette_key).
signal owned_modules_changed(totals: Dictionary)
## Bays or their contents changed (see ShipHold), so the builder's INVENTORY tab
## can redraw without polling. Fires alongside owned_modules_changed for anything
## that moves a part in or out, and on its own when the bays themselves change.
signal hold_changed

var _credits: int = 0
var _material_totals: Dictionary = {}
var _component_totals: Dictionary = {}
## key (see owned_module_key) -> Array[ModuleInstance]. A pool of individually
## tracked instances rather than a bare count, so a specific module keeps its
## identity through being built, placed, removed, cut off a wreck and re-placed.
## take_owned_module()/return_owned_module()/add_captured_instance() move a real
## instance in and out of this pool; add_owned_module() is the only thing that
## creates a brand new one.
##
## This is now the only place a module the player holds can be — there is no
## separate count-keyed store for salvaged parts. A count is exactly the thing
## that cannot tell two railguns apart (docs/direction.md §1).
var _owned_module_pool: Dictionary = {}
## Total cargo capacity, recomputed by Ship whenever its layout changes (see
## Ship._refresh_layout_stats) — kept here rather than derived on the
## fly so try_add_material() has a cheap, always-current limit to check.
var _cargo_capacity: float = 0.0
## Set of module_type_id (module_type_id -> true) that have been researched
## and are now buildable despite ModuleType.requires_research. Session-only,
## like the rest of this prototype's economy state.
var _researched_ids: Dictionary = {}
## Set of manufacturer_id (manufacturer_id -> true) discovered by capturing a
## part built by that manufacturer (see Ship.capture_tech_part) — distinct
## from _researched_ids: knowing a manufacturer exists is a separate fact
## from being able to build a given module type. Buying from a known
## manufacturer once a station/trading system exists is a deliberate future
## hook, not implemented yet.
var _known_manufacturer_ids: Dictionary = {}
## Where each held part physically sits (see ShipHold). The pool above is what
## the player owns; this is where it is stowed, and a part cannot be in one
## without being in the other — every path that adds to the pool goes through
## a stow, and every path that takes from it releases the cells.
var _hold: ShipHold = ShipHold.new()


func get_credits() -> int:
	return _credits


func add_credits(amount: int) -> void:
	_credits += amount
	credits_changed.emit(_credits)


func has_credits(amount: int) -> bool:
	return _credits >= amount


func spend_credits(amount: int) -> bool:
	if not has_credits(amount):
		return false
	_credits -= amount
	credits_changed.emit(_credits)
	return true


func add_material(material_id: String, amount: int) -> void:
	_material_totals[material_id] = get_material_amount(material_id) + amount
	materials_changed.emit(_material_totals)


func get_material_amount(material_id: String) -> int:
	return _material_totals.get(material_id, 0)


func get_all_materials() -> Dictionary:
	return _material_totals


func set_cargo_capacity(capacity: float) -> void:
	_cargo_capacity = capacity
	cargo_capacity_changed.emit(_cargo_capacity)


func get_cargo_capacity() -> float:
	return _cargo_capacity


## Includes crafted components as well as raw materials — they share one
## physical cargo hold, not two separate capacity pools.
func get_cargo_used() -> int:
	var total: int = 0
	for material_id in _material_totals:
		total += _material_totals[material_id]
	for component_id in _component_totals:
		total += _component_totals[component_id]
	return total


func has_cargo_space(amount: int) -> bool:
	return get_cargo_used() + amount <= _cargo_capacity


## Capacity-respecting collection path — used by Salvage pickup so a full
## cargo hold rejects new material instead of silently exceeding capacity.
## add_material() itself stays uncapped on purpose: refunds (ship builder
## module removal), the debug resource cheat, and GameState's scene-change
## restore all call it expecting it to never fail.
func try_add_material(material_id: String, amount: int) -> bool:
	if not has_cargo_space(amount):
		storage_full.emit()
		return false
	add_material(material_id, amount)
	return true


## Discards up to amount of material_id, clamped to what's actually held.
## Returns how much was actually discarded (0 if none was held).
func discard_material(material_id: String, amount: int) -> int:
	var available: int = get_material_amount(material_id)
	var discarded: int = mini(available, amount)
	if discarded <= 0:
		return 0
	_material_totals[material_id] = available - discarded
	materials_changed.emit(_material_totals)
	return discarded


func has_materials(costs: Dictionary) -> bool:
	for material_id in costs:
		if get_material_amount(material_id) < costs[material_id]:
			return false
	return true


func spend_materials(costs: Dictionary) -> bool:
	if not has_materials(costs):
		return false
	for material_id in costs:
		_material_totals[material_id] = get_material_amount(material_id) - costs[material_id]
	materials_changed.emit(_material_totals)
	return true


## Uncapped, mirrors add_material() — only craft()'s own capacity check (see
## below) gates whether crafting can happen at all, so once it's decided to
## proceed the output must never be silently dropped for space.
func add_component(component_id: String, amount: int) -> void:
	_component_totals[component_id] = get_component_amount(component_id) + amount
	components_changed.emit(_component_totals)


func get_component_amount(component_id: String) -> int:
	return _component_totals.get(component_id, 0)


func get_all_components() -> Dictionary:
	return _component_totals


## Capacity-respecting version of add_component() — mirrors try_add_material,
## used by Salvage pickup (Phase 5.3 component drops) so a full cargo hold
## rejects the item instead of silently exceeding capacity.
func try_add_component(component_id: String, amount: int) -> bool:
	if not has_cargo_space(amount):
		storage_full.emit()
		return false
	add_component(component_id, amount)
	return true


func has_components(costs: Dictionary) -> bool:
	for component_id in costs:
		if get_component_amount(component_id) < costs[component_id]:
			return false
	return true


func spend_components(costs: Dictionary) -> bool:
	if not has_components(costs):
		return false
	for component_id in costs:
		_component_totals[component_id] = get_component_amount(component_id) - costs[component_id]
	components_changed.emit(_component_totals)
	return true


## Whether recipe could be crafted quantity times right now: enough raw
## materials, enough of any component inputs it itself depends on, and
## enough free cargo space for the output — checked all at once so craft()
## never partially consumes inputs it can't actually deliver output for.
func can_craft(recipe: CraftingRecipe, quantity: int = 1) -> bool:
	if recipe == null or quantity <= 0:
		return false
	if not has_materials(_scaled_costs(recipe.input_materials, quantity)):
		return false
	if not has_components(_scaled_costs(recipe.input_components, quantity)):
		return false
	return has_cargo_space(recipe.output_amount * quantity)


## Player-triggered only (see CraftingPanel) — never called automatically.
## Consumes inputs exactly once and produces output exactic once, only if
## can_craft() already passed.
func craft(recipe: CraftingRecipe, quantity: int = 1) -> bool:
	if not can_craft(recipe, quantity):
		return false
	spend_materials(_scaled_costs(recipe.input_materials, quantity))
	spend_components(_scaled_costs(recipe.input_components, quantity))
	add_component(recipe.output_component_id, recipe.output_amount * quantity)
	return true


func _scaled_costs(costs: Dictionary, quantity: int) -> Dictionary:
	var scaled: Dictionary = {}
	for id in costs:
		scaled[id] = costs[id] * quantity
	return scaled


## True if id belongs to ComponentCatalog — used by the generic item helpers
## below so a single build_costs Dictionary can mix material_id and
## component_id keys (Phase 5.2 module construction costs) without the
## caller needing to know which catalog each key came from.
func _is_component_id(id: String) -> bool:
	return ComponentCatalog.get_by_id(id) != null


func get_item_amount(id: String) -> int:
	return get_component_amount(id) if _is_component_id(id) else get_material_amount(id)


func has_items(costs: Dictionary) -> bool:
	for id in costs:
		if get_item_amount(id) < costs[id]:
			return false
	return true


## Uncapped, mirrors add_material()/add_component() — used for refunds
## (ship-builder module removal returns owned instances, not raw items, but
## kept here for symmetry/future use).
func add_items(costs: Dictionary) -> void:
	for id in costs:
		if _is_component_id(id):
			add_component(id, costs[id])
		else:
			add_material(id, costs[id])


func spend_items(costs: Dictionary) -> bool:
	if not has_items(costs):
		return false
	for id in costs:
		if _is_component_id(id):
			_component_totals[id] = get_component_amount(id) - costs[id]
		else:
			_material_totals[id] = get_material_amount(id) - costs[id]
	materials_changed.emit(_material_totals)
	components_changed.emit(_component_totals)
	return true


## Composite key for one ownable module "blueprint": a manufacturer-flavored
## build is tracked separately from the generic one. Shared by
## ShipBuilderPanel's palette rows and Ship's starter-loadout seeding (see
## Ship._seed_starter_owned_modules) so both always agree on the same key
## for the same (module_type_id, manufacturer_id) pair.
static func owned_module_key(module_type_id: String, manufacturer_id: String = "") -> String:
	return module_type_id if manufacturer_id.is_empty() else "%s::%s" % [module_type_id, manufacturer_id]


## Built-but-not-placed module instances (Phase 5.2) — key from
## owned_module_key(). Creates `amount` brand new (nothing-upgraded)
## ModuleInstance objects — used by Build/Repair/starter-loadout seeding,
## none of which have an existing instance to preserve. See
## return_owned_module() for the "give back a specific instance" path
## (ship-builder removal), which never creates a new one.
func add_owned_module(key: String, amount: int = 1) -> void:
	if not _owned_module_pool.has(key):
		_owned_module_pool[key] = []
	var parts: PackedStringArray = key.split("::")
	for i in amount:
		var made: ModuleInstance = ModuleInstance.create(
			parts[0], parts[1] if parts.size() > 1 else "")
		_owned_module_pool[key].append(made)
		_ensure_stowed(made)
	owned_modules_changed.emit(get_all_owned_modules())
	hold_changed.emit()


## Gives a part a place in the hold if it does not have one. Deliberately does
## not fail: a part built, unbolted or restored with the bays full stays owned
## and simply has no cell yet (see get_unstowed_instances) — refusing a build the
## player has already paid for, or deleting a part on a region change, would both
## be worse than a part waiting for room.
##
## The one path that *does* refuse is a part arriving from a wreck
## (add_captured_instance): that one has somewhere else to be — still out there,
## on the end of the grapple.
func _ensure_stowed(instance: ModuleInstance) -> void:
	if instance == null or _hold.is_stowed(instance.instance_id):
		return
	_hold.auto_stow(instance.instance_id, part_size(instance))


## Returns an already-existing instance to the pool, its condition and origin
## intact — the ship builder's Remove action uses this instead of
## add_owned_module() so nothing tracked against that specific module is lost.
##
## The one thing that does *not* survive the trip is the field-mount penalty:
## that describes a mount, and a part in the hold has none. Every way a part
## comes off a hull ends here (unbolted in the builder, cut free and reeled in),
## so this is the single place that has to say so.
func return_owned_module(key: String, instance: ModuleInstance) -> void:
	if not _owned_module_pool.has(key):
		_owned_module_pool[key] = []
	if instance != null:
		instance.field_attached = false
	_owned_module_pool[key].append(instance)
	_ensure_stowed(instance)
	owned_modules_changed.emit(get_all_owned_modules())
	hold_changed.emit()


## A part cut off a wreck and reeled in (see Ship.capture_tech_part) enters the
## same owned-but-unplaced pool a fabricated one does, as the very same object:
## the damage it took before it came free and the hull it came off arrive with
## it, and it is directly placeable.
##
## It deliberately does not matter here whether the part's type is researched.
## Taking a Railgun intact off a corvette is the whole way to own a Railgun.
## Auto-stows, so it is the path for a part that arrives without the player
## choosing a spot for it. Returns false and keeps the part out of the pool
## entirely if the hold has no room — a part that cannot be stowed is not owned,
## it is still out there (see Ship.take_in_tow).
func add_captured_instance(instance: ModuleInstance) -> bool:
	if instance == null:
		return false
	if not _hold.auto_stow(instance.instance_id, part_size(instance)):
		return false
	return_owned_module(owned_module_key(instance.module_type_id, instance.manufacturer_id), instance)
	hold_changed.emit()
	return true


# --- The hold (see ShipHold) -------------------------------------------------

func get_hold() -> ShipHold:
	return _hold


## How many hold cells a part takes: the same footprint it occupies on a hull.
## A part is the shape it is, and a two-hex gun should be an awkward thing to
## find room for.
static func part_size(instance: ModuleInstance) -> int:
	if instance == null:
		return 1
	var module_type: ModuleType = ModuleCatalog.get_by_id(instance.module_type_id)
	if module_type == null:
		return 1
	return maxi(1, module_type.footprint_cells.size())


## Re-derives the bays from the ship's current layout. Any part whose bay is gone
## goes with it — the parts are dropped from the pool as well, because a hold
## cell is where a part *is*, and a container blown off the hull takes its
## contents. The ship builder refuses a removal that would do this (see
## ShipBuilderPanel), so in practice this is combat damage.
func rebuild_hold(layout: Resource, base_cells: int = 0) -> void:
	var displaced: Array[String] = _hold.rebuild(layout, base_cells)
	for instance_id in displaced:
		take_owned_instance(instance_id)
	# Anything owned but homeless — built while the bays were full, or arriving
	# from a region change — takes a cell as soon as one exists.
	for instance in get_owned_instances():
		_ensure_stowed(instance)
	hold_changed.emit()


## Parts the player owns that have no cell (see _ensure_stowed). The builder
## lists them separately rather than hiding them, so a part is never invisible
## just because the bays were full when it arrived.
func get_unstowed_instances() -> Array[ModuleInstance]:
	var homeless: Array[ModuleInstance] = []
	for instance in get_owned_instances():
		if not _hold.is_stowed(instance.instance_id):
			homeless.append(instance)
	return homeless


## Stows a specific part into a specific bay cell — the INVENTORY tab's click.
## False if it will not fit from there, leaving everything untouched.
func stow_instance(instance: ModuleInstance, bay_index: int, cell: Vector2i) -> bool:
	if instance == null:
		return false
	if not _hold.stow(bay_index, cell, instance.instance_id, part_size(instance)):
		return false
	return_owned_module(owned_module_key(instance.module_type_id, instance.manufacturer_id), instance)
	hold_changed.emit()
	return true


func has_hold_room_for(instance: ModuleInstance) -> bool:
	return _hold.has_room_for(part_size(instance))


func get_owned_module_count(key: String) -> int:
	return _owned_module_pool.get(key, []).size()


## Counts only, for UI display — see get_all_owned_module_instances() for the
## real pool (GameState snapshotting needs the actual instances, not counts).
func get_all_owned_modules() -> Dictionary:
	var counts: Dictionary = {}
	for key in _owned_module_pool:
		counts[key] = _owned_module_pool[key].size()
	return counts


func get_all_owned_module_instances() -> Dictionary:
	return _owned_module_pool


## Bulk-restore for GameState after a scene change — replaces the whole pool
## outright (GameState always captures the complete pool, never a partial
## delta, so there's nothing to merge).
## Cell positions are deliberately not part of the snapshot — the destination
## ship rebuilds its own bays, and re-stowing on arrival keeps the two from
## disagreeing. The cost is that the exact arrangement inside a bay is not
## preserved across a region change; what is preserved is which parts you have.
func restore_owned_module_pool(pool: Dictionary) -> void:
	_owned_module_pool = pool
	_hold.clear()
	for instance in get_owned_instances():
		_ensure_stowed(instance)
	owned_modules_changed.emit(get_all_owned_modules())
	hold_changed.emit()


## Every part in the hold, flattened out of the per-type buckets — what the ship
## builder lists, one row per object. Order is stable for a given pool so the
## list doesn't reshuffle itself between refreshes.
func get_owned_instances() -> Array[ModuleInstance]:
	var instances: Array[ModuleInstance] = []
	for key in _owned_module_pool:
		for instance in _owned_module_pool[key]:
			instances.append(instance)
	return instances


func get_owned_instance(instance_id: String) -> ModuleInstance:
	for instance in get_owned_instances():
		if instance.instance_id == instance_id:
			return instance
	return null


## Consumes and returns one *specific* part — the builder places the exact part
## the player picked out of the hold, not an interchangeable one of its type.
## Null if the hold doesn't have it (already placed, or gone with a wreck).
func take_owned_instance(instance_id: String) -> ModuleInstance:
	for key in _owned_module_pool:
		var pool: Array = _owned_module_pool[key]
		for i in pool.size():
			if pool[i].instance_id != instance_id:
				continue
			var instance: ModuleInstance = pool[i]
			pool.remove_at(i)
			# Leaving the hold frees its cells: bolted onto the hull, it is not
			# in the hold any more.
			_hold.release(instance.instance_id)
			owned_modules_changed.emit(get_all_owned_modules())
			hold_changed.emit()
			return instance
	return null


## Consumes and returns one owned instance of key — called when a module is
## actually placed on the grid, not when it's built. Null if none owned.
func take_owned_module(key: String) -> ModuleInstance:
	var pool: Array = _owned_module_pool.get(key, [])
	if pool.is_empty():
		return null
	var instance: ModuleInstance = pool.pop_back()
	_hold.release(instance.instance_id)
	owned_modules_changed.emit(get_all_owned_modules())
	hold_changed.emit()
	return instance


## True if module_type_id doesn't need research at all, or already has it.
func is_researched(module_type_id: String) -> bool:
	return _researched_ids.get(module_type_id, false)


## Whether research() would currently succeed — used to enable/disable the ship
## builder's Research button, which is frozen (see
## ShipBuilderPanel.RESEARCH_FROZEN), so nothing reaches this in a normal
## session.
##
## Repointed at the owned-module pool because the per-type captured count it
## used to read no longer exists — a recovered part is now a specific object in
## the hold like any other. The frozen behaviour is otherwise unchanged: spend a
## part of this type to unlock manufacturing it.
func can_research(module_type_id: String) -> bool:
	return not is_researched(module_type_id) \
		and get_owned_module_count(owned_module_key(module_type_id)) > 0


## Spends one owned part of module_type_id to permanently unlock it for
## building. Returns false without effect if already researched or no part is
## available to spend. Frozen — see can_research().
func research(module_type_id: String) -> bool:
	if not can_research(module_type_id):
		return false
	take_owned_module(owned_module_key(module_type_id))
	_researched_ids[module_type_id] = true
	research_unlocked.emit(module_type_id)
	return true


func get_researched_ids() -> Array:
	return _researched_ids.keys()


## Bulk-restore for GameState after a scene change — bypasses research()'s
## owned-part requirement since the part was already spent when this was
## originally researched.
func set_researched(module_type_id: String) -> void:
	_researched_ids[module_type_id] = true


func is_manufacturer_known(manufacturer_id: String) -> bool:
	return _known_manufacturer_ids.get(manufacturer_id, false)


## Marks a manufacturer known permanently once its part is captured. Does
## nothing if already known (no duplicate signal spam on repeat captures).
func discover_manufacturer(manufacturer_id: String) -> void:
	if is_manufacturer_known(manufacturer_id):
		return
	_known_manufacturer_ids[manufacturer_id] = true
	manufacturer_discovered.emit(manufacturer_id)


func get_known_manufacturer_ids() -> Array:
	return _known_manufacturer_ids.keys()

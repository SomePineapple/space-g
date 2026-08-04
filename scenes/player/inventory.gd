class_name Inventory
extends Node

signal materials_changed(totals: Dictionary)
signal captured_tech_changed(totals: Dictionary)
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

var _credits: int = 0
var _material_totals: Dictionary = {}
var _component_totals: Dictionary = {}
## key (see owned_module_key) -> Array[ModuleInstance]. A pool of individually
## tracked instances rather than a bare count (Phase 8.1) — so a specific
## instance's upgrade state survives being built, placed, removed and
## re-placed. take_owned_module()/return_owned_module() move a real instance
## in and out of this pool; add_owned_module() is the only thing that ever
## creates a brand new (unupgraded) one.
var _owned_module_pool: Dictionary = {}
## Total cargo capacity, recomputed by Ship whenever its layout changes (see
## Ship._apply_layout_cargo_capacity) — kept here rather than derived on the
## fly so try_add_material() has a cheap, always-current limit to check.
var _cargo_capacity: float = 0.0
## module_type_id -> count. Distinct from _material_totals: these are
## specific captured tech parts (see Ship.capture_tech_part), spent one at a
## time to research/unlock a locked ModuleType (see research()).
var _captured_tech_totals: Dictionary = {}
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
		var instance := ModuleInstance.new()
		instance.instance_id = "mi_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
		instance.module_type_id = parts[0]
		instance.manufacturer_id = parts[1] if parts.size() > 1 else ""
		_owned_module_pool[key].append(instance)
	owned_modules_changed.emit(get_all_owned_modules())


## Returns an already-existing instance to the pool, upgrade state intact —
## the ship builder's Remove action uses this instead of add_owned_module()
## so upgrades purchased on that specific instance aren't lost.
func return_owned_module(key: String, instance: ModuleInstance) -> void:
	if not _owned_module_pool.has(key):
		_owned_module_pool[key] = []
	_owned_module_pool[key].append(instance)
	owned_modules_changed.emit(get_all_owned_modules())


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
func restore_owned_module_pool(pool: Dictionary) -> void:
	_owned_module_pool = pool
	owned_modules_changed.emit(get_all_owned_modules())


## Consumes and returns one owned instance of key — called when a module is
## actually placed on the grid, not when it's built. Null if none owned.
func take_owned_module(key: String) -> ModuleInstance:
	var pool: Array = _owned_module_pool.get(key, [])
	if pool.is_empty():
		return null
	var instance: ModuleInstance = pool.pop_back()
	owned_modules_changed.emit(get_all_owned_modules())
	return instance


func add_captured_tech(module_type_id: String) -> void:
	_captured_tech_totals[module_type_id] = get_captured_tech_count(module_type_id) + 1
	captured_tech_changed.emit(_captured_tech_totals)


func get_captured_tech_count(module_type_id: String) -> int:
	return _captured_tech_totals.get(module_type_id, 0)


func get_all_captured_tech() -> Dictionary:
	return _captured_tech_totals


## True if module_type_id doesn't need research at all, or already has it.
func is_researched(module_type_id: String) -> bool:
	return _researched_ids.get(module_type_id, false)


## Whether research() would currently succeed — used to enable/disable the
## ship builder's Research button.
func can_research(module_type_id: String) -> bool:
	return not is_researched(module_type_id) and get_captured_tech_count(module_type_id) > 0


## Spends one captured part of module_type_id to permanently unlock it for
## building. Returns false without effect if already researched or no part
## is available to spend.
func research(module_type_id: String) -> bool:
	if not can_research(module_type_id):
		return false
	_captured_tech_totals[module_type_id] = get_captured_tech_count(module_type_id) - 1
	_researched_ids[module_type_id] = true
	captured_tech_changed.emit(_captured_tech_totals)
	research_unlocked.emit(module_type_id)
	return true


func get_researched_ids() -> Array:
	return _researched_ids.keys()


## Phase 5.3 "damaged modules require repair before use": a captured tech
## part (see Ship.capture_tech_part — a severed module recovered from
## combat) is never directly placeable, unlike a Build-crafted instance —
## repairing it is what converts one into a normal owned module instance
## (see owned_module_key/add_owned_module). Cost is half a fresh build
## (rounded up), reusing ModuleType.build_costs rather than a whole separate
## repair-cost data table — a damaged part should be cheaper to restore than
## building one from scratch, not free.
func get_repair_cost(module_type_id: String) -> Dictionary:
	var module_type: ModuleType = ModuleCatalog.get_by_id(module_type_id)
	if module_type == null:
		return {}
	var cost: Dictionary = {}
	for id in module_type.build_costs:
		cost[id] = ceili(module_type.build_costs[id] / 2.0)
	return cost


## Whether repair_module() would currently succeed — a captured part to
## spend and enough materials/components to cover get_repair_cost().
func can_repair(module_type_id: String) -> bool:
	return get_captured_tech_count(module_type_id) > 0 and has_items(get_repair_cost(module_type_id))


## Spends one captured part of module_type_id plus its repair cost to
## produce one placeable owned module instance (always generic — a captured
## part carries no manufacturer_id in this Dictionary, see capture_tech_part).
## Returns false without effect if can_repair() would be false.
func repair_module(module_type_id: String) -> bool:
	if not can_repair(module_type_id):
		return false
	spend_items(get_repair_cost(module_type_id))
	_captured_tech_totals[module_type_id] = get_captured_tech_count(module_type_id) - 1
	captured_tech_changed.emit(_captured_tech_totals)
	add_owned_module(owned_module_key(module_type_id))
	return true


## Bulk-restore for GameState after a scene change — bypasses research()'s
## captured-tech requirement since the tech was already spent when this was
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

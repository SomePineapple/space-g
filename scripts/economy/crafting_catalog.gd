class_name CraftingCatalog
extends RefCounted

## Prototype-only stand-in for loading CraftingRecipe resources from
## res://resources/recipes/ — same documented shortcut as MaterialCatalog/
## ModuleCatalog/ComponentCatalog. Phase 5.1 initial recipes: one recipe per
## ComponentCatalog component, each consuming only raw materials (no
## component-on-component chains yet — CraftingRecipe.input_components
## exists for when that's actually needed).
##
## Ratios are first-pass, not tuned against real crafting/building play.

static var _cached_recipes: Array[CraftingRecipe] = []


static func get_all() -> Array[CraftingRecipe]:
	if not _cached_recipes.is_empty():
		return _cached_recipes

	var recipes: Array[CraftingRecipe] = []
	recipes.append(_make(ComponentCatalog.METAL_SHEETS, "Metal Sheets",
		{MaterialCatalog.IRON: 3}))
	recipes.append(_make(ComponentCatalog.WIRING, "Wiring",
		{MaterialCatalog.COPPER: 2}))
	# Copper for the conductive traces, Glass for the transparent casing —
	# see the Phase 5.1 "glass source" decision, MaterialCatalog.GLASS.
	recipes.append(_make(ComponentCatalog.CIRCUIT_BOARD, "Circuit Board",
		{MaterialCatalog.COPPER: 2, MaterialCatalog.GLASS: 1}))
	recipes.append(_make(ComponentCatalog.REINFORCED_STEEL, "Reinforced Steel",
		{MaterialCatalog.IRON: 3, MaterialCatalog.NICKEL: 2}))
	recipes.append(_make(ComponentCatalog.MOTOR, "Motor",
		{MaterialCatalog.COPPER: 3, MaterialCatalog.IRON: 3}))
	recipes.append(_make(ComponentCatalog.CANISTER, "Canister",
		{MaterialCatalog.IRON: 4}))

	_cached_recipes = recipes
	return recipes


static func get_by_id(recipe_id: String) -> CraftingRecipe:
	for recipe in get_all():
		if recipe.id == recipe_id:
			return recipe
	return null


static func _make(output_component_id: String, display_name: String, input_materials: Dictionary,
		input_components: Dictionary = {}, output_amount: int = 1) -> CraftingRecipe:
	var recipe := CraftingRecipe.new()
	recipe.id = output_component_id
	recipe.display_name = display_name
	recipe.input_materials = input_materials
	recipe.input_components = input_components
	recipe.output_component_id = output_component_id
	recipe.output_amount = output_amount
	return recipe

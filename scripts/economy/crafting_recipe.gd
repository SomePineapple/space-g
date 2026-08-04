class_name CraftingRecipe
extends Resource

## Pure data for one crafting recipe — see CraftingCatalog for the catalog
## that builds these. Recipe data is deliberately separate from
## CraftingPanel (the UI just iterates CraftingCatalog.get_all() and reads
## these fields), so a new recipe is a catalog-only change.

@export var id: String = ""
@export var display_name: String = ""
## material_id (MaterialCatalog) -> amount consumed per single craft.
@export var input_materials: Dictionary = {}
## component_id (ComponentCatalog) -> amount consumed per single craft.
## Lets a recipe build on top of an earlier component (none of the initial
## six do, but this keeps deeper crafting chains a data-only addition later).
@export var input_components: Dictionary = {}
@export var output_component_id: String = ""
@export var output_amount: int = 1

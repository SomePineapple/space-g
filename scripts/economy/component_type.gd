class_name ComponentType
extends Resource

## Pure data for one crafted intermediate component — see ComponentCatalog
## for the catalog that builds these. Components live in Inventory's
## component pool (separate Dictionary from raw materials, same shared cargo
## capacity), produced only by CraftingCatalog recipes, never mined/salvaged
## directly.

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
## HUD/cargo icon — unused placeholder, same convention as MaterialType.icon.
@export var icon: Texture2D = null

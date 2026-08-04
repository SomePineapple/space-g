class_name MaterialType
extends Resource

## Pure data for one raw material — see MaterialCatalog for the catalog that
## builds these. Adding a new material never requires touching Inventory
## (which just keys a Dictionary by plain material_id Strings).

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
## HUD/cargo icon — not wired into any UI yet (deferred per the 4.2 spec),
## but every material carries the field so adding real art later is a
## MaterialCatalog-only change, not a UI rewrite.
@export var icon: Texture2D = null
@export var sell_price: int = 0
@export var buy_price: int = 0
## Multiplies every Salvage drop's material_amount for this material — rarer,
## pricier materials yield less per drop (see Salvage._ready()). 1.0 = no
## reduction; lower = scarcer per pickup.
@export var yield_multiplier: float = 1.0

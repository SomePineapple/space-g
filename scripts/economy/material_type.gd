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
## Anchor the station exchange's random walk drifts around, in credits per
## unit (docs/design_handoff_trade_market/README.md "Per-material data").
## There is no separate sell price: the station always pays 50% of the live
## buy price, so a second field could only ever disagree with it.
@export var base_price: int = 0
## Size of one tick's random step, in credits. The handoff's materials all sit
## at roughly 7.5% of base_price — bigger swings for pricier goods.
@export var volatility: float = 0.0
## Market category tab this material files under (Ore / Refined / Volatile /
## Tech). The exchange derives its tab list from these, so a new category is
## a catalog-only change.
@export var category: String = ""
## Multiplies every Salvage drop's material_amount for this material — rarer,
## pricier materials yield less per drop (see Salvage._ready()). 1.0 = no
## reduction; lower = scarcer per pickup.
@export var yield_multiplier: float = 1.0

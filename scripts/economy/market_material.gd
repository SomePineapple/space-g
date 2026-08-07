class_name MarketMaterial
extends RefCounted

## The price model for one commodity on the station exchange.
##
## The shape of it, and why it is not just a random walk: the station holds a
## finite stock of each material. Buying takes units off the shelf, which
## raises what the next unit costs and *keeps* it raised until the stock is
## replenished — that is the lasting half of a trade's impact. On top sits a
## short-lived `pressure` term for the cost of hitting the market hard, which
## decays away within a few ticks.
##
## Splitting the two is the point. With only the decaying term (the handoff's
## own model) the price sprang straight back to where it started, so the "your
## buy lifted this +6%" banner was contradicted by the chart seconds later.
## Now a trade settles at a new level and only drains away as the station
## restocks.
##
## Constructed from MaterialCatalog, so adding a material there is all it
## takes for it to trade here — see build_all().

const HISTORY_SAMPLES: int = 26
## How far back the "24h" delta compares against.
const DELTA_LOOKBACK: int = 9

## Per-tick noise, as a fraction of the material's authored volatility. The
## handoff's raw figure is roughly 7.5% of base every 1.8s, which is louder
## than any real market and drowned out the player's own orders.
const NOISE_SCALE: float = 0.8
## How fast the traded price chases the stock-implied fair value: a ~2.4 tick
## half-life, so an order's lasting effect arrives within about five seconds
## of the click. Slower than this and the move lands so long after the trade
## that the player never connects the two.
const REVERSION: float = 0.25

## Units the station aims to hold, before the material's own scarcity applies.
## Rarer materials keep a thinner book, so the same order moves them further —
## yield_multiplier is reused for that rather than a second rarity number that
## could drift out of agreement with it.
const STOCK_TARGET_UNITS: float = 1000.0
## Share of the shortfall made good each tick: about a 40s half-life, so a big
## order is still legible on the chart a minute later.
const RESTOCK_RATE: float = 0.03
## Price premium at a total shortfall, before SCARCITY_LIMIT clamps it. At
## these numbers a 100u order out of a 1000u book moves the price ~9% and it
## stays moved.
const SCARCITY_ELASTICITY: float = 0.9
const SCARCITY_LIMIT: float = 0.6
## Stock swing, as a fraction of target, that spans the whole SUPPLY bar.
const SUPPLY_SPAN: float = 0.5

const PRESSURE_DECAY: float = 0.88
const PRESSURE_EPSILON: float = 0.0005
## Immediate, decaying impact per unit — the station widening against a large
## order, rather than a real change in what it holds.
const TEMPORARY_IMPACT_PER_UNIT: float = 0.0005
## An order fills across its own impact, so on average it pays about half of
## it. This is what makes one 100u order dearer than four 25u ones.
const SLIPPAGE_SHARE: float = 0.5

## Hard rails, kept from the handoff.
const PRICE_FLOOR_FACTOR: float = 0.55
const PRICE_CEILING_FACTOR: float = 1.6
## What the station pays, as a fraction of the live price.
const SELL_FRACTION: float = 0.5

var id: String = ""
var display_name: String = ""
var category: String = ""
var color: Color = Color.WHITE
var base_price: float = 0.0
var volatility: float = 0.0
var stock_target: float = 0.0

## What the market has settled at, before live pressure.
var _value: float = 0.0
var _stock: float = 0.0
var _pressure: float = 0.0
## Decaying marker for "the local player did this", used only to label the
## nearby-markets rows. Deliberately separate from _pressure, which is
## source-agnostic and also carries other traders' orders and outside news.
var _player_impact: float = 0.0
var _history: Array = []


## One model per material in the catalog, in catalog order.
static func build_all() -> Array:
	var models: Array = []
	for material_id in MaterialCatalog.ALL_IDS:
		models.append(MarketMaterial.new(material_id))
	return models


func _init(material_id: String = "") -> void:
	var type: MaterialType = MaterialCatalog.get_by_id(material_id)
	if type == null:
		return
	id = type.id
	display_name = type.display_name
	category = type.category
	color = type.color
	base_price = float(type.base_price)
	volatility = type.volatility
	stock_target = STOCK_TARGET_UNITS * type.yield_multiplier


## Back-fills a full history so the chart is never empty on the first open,
## starting from a stock level a little off target so no two materials open at
## exactly their base price.
func seed(rng: RandomNumberGenerator) -> void:
	_stock = stock_target * rng.randf_range(0.85, 1.15)
	_value = _fair_value()
	_history.clear()
	for sample in HISTORY_SAMPLES:
		_step_value(rng)
		_history.append(price())


func tick(rng: RandomNumberGenerator) -> void:
	_restock()
	_step_value(rng)
	_pressure = _decayed(_pressure)
	_player_impact = _decayed(_player_impact)
	# The history is the series of prices the player was actually shown, so
	# their own spike and its recovery are on the chart rather than only on the
	# big number above it.
	_history.append(price())
	_history.remove_at(0)


# --- Reads ------------------------------------------------------------------

## Moves the instant a trade lands, not on the next tick.
func price() -> int:
	return maxi(1, int(round(_value * (1.0 + _pressure))))


func sell_price() -> int:
	return int(round(price() * SELL_FRACTION))


## How far above or below its anchor this market is sitting, counting both the
## stock shortfall and live pressure. The one number that answers "is anyone
## leaning on this?".
func deviation() -> float:
	if base_price <= 0.0:
		return 0.0
	return price() / base_price - 1.0


func player_impact() -> float:
	return _player_impact


func history() -> Array:
	return _history


func delta() -> int:
	if _history.is_empty():
		return 0
	return price() - int(round(float(_history[maxi(0, _history.size() - DELTA_LOOKBACK)])))


## 6–96, read straight off what is on the shelf: buying drains it toward
## SCARCE and the restock walks it back. Unlike the handoff's version this is
## a cause of the price rather than a restatement of it.
func supply_percent() -> int:
	if stock_target <= 0.0:
		return 50
	var offset: float = (_stock - stock_target) / (stock_target * SUPPLY_SPAN)
	return clampi(int(round(50.0 + 50.0 * offset)), 6, 96)


## What `quantity` units would really cost (`direction` +1) or fetch (−1),
## including the slippage the order causes itself. Returns
## {"unit_price": int, "total": int}.
func quote(quantity: int, direction: int) -> Dictionary:
	var slippage: float = 1.0 + direction * order_impact(quantity) * SLIPPAGE_SHARE
	var unit: float = _value * (1.0 + _pressure) * slippage
	if direction < 0:
		unit *= SELL_FRACTION
	var unit_price: int = maxi(1, int(round(unit)))
	return {"unit_price": unit_price, "total": unit_price * quantity}


## The whole price move an order of this size causes, as a fraction: what it
## takes off the shelf plus how far it widens the price against itself. An
## order fills across this, which is why buying 100u in one go costs more per
## unit than four orders of 25u.
func order_impact(quantity: int) -> float:
	var scarcity: float = 0.0
	if stock_target > 0.0:
		scarcity = quantity / stock_target * SCARCITY_ELASTICITY
	return quantity * TEMPORARY_IMPACT_PER_UNIT + scarcity


# --- Writes -----------------------------------------------------------------

## Records a trade. `direction` is +1 to buy from the station, −1 to sell to
## it. `by_player` only controls the "reacting to you" label — the stock and
## pressure terms are source-agnostic, so other traders' (and, later, other
## players') orders feed exactly the same accumulators.
func apply_trade(quantity: int, direction: int, by_player: bool = true) -> void:
	_stock = maxf(0.0, _stock - direction * quantity)
	var move: float = direction * quantity * TEMPORARY_IMPACT_PER_UNIT
	_pressure += move
	if by_player:
		_player_impact += move


## Outside news — a strike, a blockade lifting. Transient on purpose: distant
## events move sentiment here, they do not move this station's shelves.
func apply_news(move: float) -> void:
	_pressure += move


# --- Model ------------------------------------------------------------------

func _restock() -> void:
	_stock += (stock_target - _stock) * RESTOCK_RATE


## Where the price belongs given what is on the shelf.
func _fair_value() -> float:
	var scarcity: float = 0.0
	if stock_target > 0.0:
		scarcity = clampf((stock_target - _stock) / stock_target, -SCARCITY_LIMIT, SCARCITY_LIMIT)
	return base_price * (1.0 + SCARCITY_ELASTICITY * scarcity)


## Mean-reverting rather than a free walk: the price chases fair value and
## jitters around it, so it neither wanders off nor ends up pinned to a clamp,
## and a change in fair value actually pulls it somewhere.
func _step_value(rng: RandomNumberGenerator) -> void:
	var noise: float = (rng.randf() - 0.5) * volatility * NOISE_SCALE
	_value += (_fair_value() - _value) * REVERSION + noise
	_value = clampf(_value, base_price * PRICE_FLOOR_FACTOR, base_price * PRICE_CEILING_FACTOR)


func _decayed(value: float) -> float:
	var next: float = value * PRESSURE_DECAY
	return next if absf(next) > PRESSURE_EPSILON else 0.0

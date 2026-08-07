extends Node

## The station commodity market: the tick loop, the neighbouring markets,
## outside events and the floor's order flow. One MarketMaterial per commodity
## carries the actual price model — see that script for why a trade leaves a
## lasting mark rather than springing back.
##
## docs/design_handoff_trade_market/README.md "The economy model" is the
## source of the structure; the numbers have been retuned for a market that
## reacts legibly to a player order, which the handoff explicitly invites.
##
## An autoload because the handoff is explicit that the simulation keeps
## running while the player is elsewhere, and because a future multiplayer
## market plugs other players' orders into the same accumulators this one
## writes to. The Exchange screen only reads it.
##
## Signatures stay on built-in types only, never the project's own global
## classes — see the autoload compile-order note in docs/gotchas.md.

## Emitted after each price tick, once every value below is current.
signal ticked()

const TICK_SECONDS: float = 1.8
## Samples the list's sparkline plots; the focus chart plots the full history.
const SPARK_SAMPLES: int = 14

const EVENT_CHANCE: float = 0.55
const EVENT_STRENGTH_MIN: float = 0.02
const EVENT_STRENGTH_MAX: float = 0.07
const MAX_EVENTS: int = 3

## Chance a floor-activity line is a real order rather than dock chatter.
## Orders are put through the same apply_trade() the player's go through, so
## the log explains the chart instead of just decorating it.
const ORDER_CHANCE: float = 0.6
## Kept well under the player's own order sizes: floor traffic should give the
## chart a reason to move without drowning out what the player just did.
const ORDER_MIN_UNITS: int = 10
const ORDER_MAX_UNITS: int = 40

const ACTIVITY_LINES: int = 9
const BERTH_COUNT: int = 8
## Below this, a neighbour is not labelled as reacting to the player.
const REACTION_EPSILON: float = 0.002

## Neighbouring markets, with their jump distance and their standing price
## multiplier against this station. Fictional for now: the handoff expects a
## real world sim to supply these later, and the shape not to change.
const NEIGHBOURS: Array[Dictionary] = [
	{"name": "Kestrel Yards", "jumps": 2, "multiplier": 0.93},
	{"name": "Halcyon Drift", "jumps": 3, "multiplier": 1.09},
	{"name": "Rell Freeport", "jumps": 5, "multiplier": 0.84},
	{"name": "Ashgrave Hulk", "jumps": 1, "multiplier": 1.16},
	{"name": "Vosk Refinery", "jumps": 4, "multiplier": 0.98},
]

## `{mat}` is filled with the material's lower-cased name; `direction` is the
## sign of the price move the event causes.
const EVENT_KINDS: Array[Dictionary] = [
	{"text": "refinery strike halted {mat} output", "direction": 1},
	{"text": "dumped a full hold of {mat}", "direction": -1},
	{"text": "convoy raided — {mat} lost in transit", "direction": 1},
	{"text": "opened a {mat} surplus auction", "direction": -1},
	{"text": "signed a fleet contract for {mat}", "direction": 1},
	{"text": "reopened its {mat} seams", "direction": -1},
	{"text": "blockade lifted, {mat} flowing again", "direction": -1},
]

const TRADER_NAMES: Array[String] = [
	"Vela Okonkwo", "Hauler MERIDIAN", "Sable Run", "Tuk & Sons",
	"CDF Quartermaster", "Ashgrave Salvage", "Nine-Fold Consortium", "Pilot Ridley",
]

## Non-trading dock chatter. `tail` names what gets appended to the verb.
const FLAVOUR_KINDS: Array[Dictionary] = [
	{"text": "docked at berth", "tail": "berth"},
	{"text": "filed a demand contract for", "tail": "material"},
	{"text": "undocked, hold full of", "tail": "material"},
	{"text": "cleared customs with a load of", "tail": "material"},
]

## Array of MarketMaterial, in catalog order.
var _materials: Array = []
## material id -> MarketMaterial.
var _by_id: Dictionary = {}
var _events: Array = []
var _activity: Array = []
var _tick_count: int = 0
var _time_to_tick: float = TICK_SECONDS
var _rng: RandomNumberGenerator


func _ready() -> void:
	# Simulation randomness, not presentation: every player has to see the same
	# market (see GameRng's own header).
	_rng = GameRng.stream("market")
	_materials = MarketMaterial.build_all()
	for material in _materials:
		material.seed(_rng)
		_by_id[material.id] = material
	for i in ACTIVITY_LINES:
		# Back-fill only — these are history, so they place no orders.
		_activity.append(_make_activity_line(ACTIVITY_LINES - 1 - i, false))


func _process(delta: float) -> void:
	_time_to_tick -= delta
	# A loop, not a single subtract: a long frame (scene change, first-time
	# shader compile) must not leave the market permanently behind.
	while _time_to_tick <= 0.0:
		_time_to_tick += TICK_SECONDS
		_tick()


# --- Reads ------------------------------------------------------------------

func get_material_ids() -> Array:
	var ids: Array = []
	for material in _materials:
		ids.append(material.id)
	return ids


func get_price(material_id: String) -> int:
	var material = _by_id.get(material_id)
	return material.price() if material != null else 0


func get_sell_price(material_id: String) -> int:
	var material = _by_id.get(material_id)
	return material.sell_price() if material != null else 0


func get_history(material_id: String) -> Array:
	var material = _by_id.get(material_id)
	return material.history() if material != null else []


func get_delta(material_id: String) -> int:
	var material = _by_id.get(material_id)
	return material.delta() if material != null else 0


func get_supply_percent(material_id: String) -> int:
	var material = _by_id.get(material_id)
	return material.supply_percent() if material != null else 50


## How far this market currently sits from its anchor price.
func get_deviation(material_id: String) -> float:
	var material = _by_id.get(material_id)
	return material.deviation() if material != null else 0.0


## Total cost or proceeds for an order, slippage included. Always read this
## before apply_trade(), which moves the price the quote was taken from.
func quote(material_id: String, quantity: int, direction: int) -> Dictionary:
	var material = _by_id.get(material_id)
	if material == null:
		return {"unit_price": 0, "total": 0}
	return material.quote(quantity, direction)


## Flavour, but it has to move: the handoff wants the screen busy even when
## the player is doing nothing.
func get_shift_volume(material_id: String) -> int:
	return 300 + (_tick_count * 37 + material_id.length() * 91) % 1800


func get_trader_count() -> int:
	var busy: int = 0
	for i in BERTH_COUNT:
		if (_tick_count + i * 3) % 7 < 4:
			busy += 1
	return busy * 3 + 4


func get_station_clock() -> String:
	return "%02d:%02d" % [14 + _tick_count % 10, (_tick_count * 7) % 60]


func seconds_to_next_tick() -> float:
	return _time_to_tick


## Recent outside events, newest first.
func get_events() -> Array:
	return _events


## Rolling floor log, newest first. Each is {"time", "text", "kind"}.
func get_activity() -> Array:
	return _activity


## One row per neighbour: {"name", "jumps", "price", "difference_percent",
## "reacting"}.
##
## A neighbour is priced off the *shared* anchor plus a reach-scaled share of
## how far this station has moved from it — not off this station's live price.
## Pricing them off the local price made five markets that tracked this one
## perfectly; this way a big local order genuinely opens up arbitrage.
func get_neighbour_markets(material_id: String) -> Array:
	var material = _by_id.get(material_id)
	if material == null:
		return []
	var local_price: int = material.price()
	var deviation: float = material.deviation()
	var player_impact: float = material.player_impact()

	var rows: Array = []
	for station in NEIGHBOURS:
		var station_reach: float = reach(station["jumps"])
		var their_price: int = maxi(1, int(round(
			material.base_price * float(station["multiplier"]) * (1.0 + station_reach * deviation))))
		var difference: int = 0
		if local_price > 0:
			difference = int(round(float(their_price - local_price) / local_price * 100.0))
		rows.append({
			"name": station["name"],
			"jumps": station["jumps"],
			"price": their_price,
			"difference_percent": difference,
			"reacting": absf(player_impact * station_reach) > REACTION_EPSILON,
		})
	return rows


## How much of this station's movement reaches a market `jumps` away. The one
## falloff curve: player orders, floor orders and outside news all ride it,
## which is what makes the five markets read as one economy.
func reach(jumps: int) -> float:
	if jumps <= 2:
		return 0.40
	if jumps == 3:
		return 0.20
	return 0.08


## The two nearest neighbours' share of a local price change, as percentages,
## for the YOUR IMPACT banner. Array of {"name", "percent"}.
func get_spillover(change: float) -> Array:
	var sorted: Array = NEIGHBOURS.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["jumps"] < b["jumps"])
	var result: Array = []
	for station in sorted.slice(0, 2):
		result.append({"name": station["name"], "percent": change * reach(station["jumps"]) * 100.0})
	return result


# --- Writes -----------------------------------------------------------------

## Puts an order through the market. `direction` is +1 to buy from the station,
## −1 to sell to it; `by_player` distinguishes the local player's orders from
## the floor's, and only affects the "reacting to you" label.
func apply_trade(material_id: String, quantity: int, direction: int, by_player: bool = true) -> void:
	var material = _by_id.get(material_id)
	if material != null:
		material.apply_trade(quantity, direction, by_player)


# --- Simulation -------------------------------------------------------------

func _tick() -> void:
	_tick_count += 1
	# Floor orders land before the price step, so the line the log shows and
	# the move the chart draws are the same event.
	_activity.push_front(_make_activity_line(_tick_count, true))
	_activity.resize(ACTIVITY_LINES)

	_age_events()
	if _rng.randf() < EVENT_CHANCE:
		_fire_event()

	for material in _materials:
		material.tick(_rng)
	ticked.emit()


func _age_events() -> void:
	for event in _events:
		event["age"] += 1


## Something happened at another station. The move is scaled by that station's
## reach, so a strike five jumps away barely registers and a blockade next door
## bites — the same falloff the player's own orders spill along.
func _fire_event() -> void:
	var material = _random_material()
	var station: Dictionary = NEIGHBOURS[_rng.randi_range(0, NEIGHBOURS.size() - 1)]
	var kind: Dictionary = EVENT_KINDS[_rng.randi_range(0, EVENT_KINDS.size() - 1)]

	var strength: float = _rng.randf_range(EVENT_STRENGTH_MIN, EVENT_STRENGTH_MAX)
	var move: float = int(kind["direction"]) * strength * reach(station["jumps"])
	material.apply_news(move)

	_events.push_front({
		"station": station["name"],
		"jumps": station["jumps"],
		"material_id": material.id,
		"material_name": material.display_name,
		"color": material.color,
		"text": "%s %s" % [station["name"],
			String(kind["text"]).replace("{mat}", material.display_name.to_lower())],
		"percent": move * 100.0,
		"direction": int(kind["direction"]),
		"age": 0,
	})
	if _events.size() > MAX_EVENTS:
		_events.resize(MAX_EVENTS)


## One line of floor traffic. Most are real orders: when `place_orders` is set
## they go through apply_trade() before the line quotes a price, so the log
## reports what actually happened rather than inventing a number.
func _make_activity_line(ordinal: int, place_orders: bool) -> Dictionary:
	var who: String = TRADER_NAMES[_rng.randi_range(0, TRADER_NAMES.size() - 1)]
	var material = _random_material()
	var text: String = ""
	var kind: String = "move"

	if _rng.randf() < ORDER_CHANCE:
		var quantity: int = _rng.randi_range(ORDER_MIN_UNITS, ORDER_MAX_UNITS)
		var direction: int = 1 if _rng.randf() < 0.5 else -1
		if place_orders:
			material.apply_trade(quantity, direction, false)
		kind = "buy" if direction > 0 else "sell"
		text = "%s %s %d %s at %d cr" % [who, "bought" if direction > 0 else "sold",
			quantity, material.display_name, material.price()]
	else:
		var flavour: Dictionary = FLAVOUR_KINDS[_rng.randi_range(0, FLAVOUR_KINDS.size() - 1)]
		var tail: String = material.display_name
		if flavour["tail"] == "berth":
			tail = "B-0%d" % _rng.randi_range(1, BERTH_COUNT)
		text = "%s %s %s" % [who, flavour["text"], tail]

	return {
		"time": "%02d:%02d" % [14 + (ordinal / 30) % 10, (6 * (ordinal % 60)) % 60],
		"text": text,
		"kind": kind,
	}


func _random_material():
	return _materials[_rng.randi_range(0, _materials.size() - 1)]

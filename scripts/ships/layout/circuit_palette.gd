class_name CircuitPalette
extends RefCounted

## The colour each of a ship's circuits is drawn in, by its position in
## ShipLayout.get_circuit_ids().
##
## Lives on its own rather than in BuilderTheme or HudPalette because both of
## them need it and they must agree: a circuit the player coloured green on the
## bench has to still be green on the HUD when its reactor dies mid-fight, or the
## builder taught them a mapping the fight then contradicts.
##
## Hues are chosen to survive being read at a glance, against the hull plating,
## by someone who may not distinguish red from green: the amber/blue/magenta
## trio differ in lightness as well as hue, and none of them sits on the
## builder's own cyan or on the WARN orange used for over-commitment.

## Index 0 is always the Command Core's circuit — a dim, unsaturated grey-blue,
## because it is the one circuit the player neither chooses nor manages. It
## should read as "the floor", not as a competitor to the reactors.
const CORE_COLOR: Color = Color(0.45, 0.52, 0.58)

## Reactor circuits, in assignment order. Wraps if a hull ever carries more
## reactors than there are entries; six is already more than a hull has hexes to
## spare for.
const REACTOR_COLORS: Array[Color] = [
	Color(0.96, 0.71, 0.24),  # amber
	Color(0.38, 0.62, 0.95),  # blue
	Color(0.85, 0.42, 0.80),  # magenta
	Color(0.46, 0.86, 0.55),  # green
	Color(0.95, 0.50, 0.36),  # coral
	Color(0.62, 0.78, 0.90),  # pale steel
]


## The colour for the circuit at `index` in ShipLayout.get_circuit_ids().
## A negative index (a module on no circuit at all) has no colour of its own —
## callers draw those as dead rather than tinting them.
static func color_for(index: int) -> Color:
	if index <= 0:
		return CORE_COLOR
	return REACTOR_COLORS[(index - 1) % REACTOR_COLORS.size()]


## What an unassigned or unpowered module is marked with. Deliberately not one of
## the circuit hues: "nothing feeds this" has to read as an absence of colour,
## not as a seventh circuit.
const DEAD_COLOR: Color = Color(0.85, 0.35, 0.28)

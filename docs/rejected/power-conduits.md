# Rejected: power conduits

**Status:** cut, 2026-08-16. Replaced by reactor circuits — one circuit per
reactor, membership assigned by the player in the builder, no geometry involved.
See `ShipLayout`'s circuit functions and `ModulePlacement.circuit_id`.

**The code and design docs live on `archive/power-conduits`, commit
`264a1b0b48724753dc34825290969ee814401821`.** Everything described below is
recoverable from there in full: `scripts/ships/layout/power_grid.gd`, the
`conduit` `ModuleType`, `docs/design_handoff_conduits/`,
`docs/spaceg-phase-4-spec-rev3.md`, `scenes/prototypes/phase4_power_probe.gd`,
and the builder's cable rendering.

## What it was

A module was powered if a structural path existed through occupied hull cells
back to a reactor. Only the Conduit — a light structural hex that carried
wiring and nothing else — passed power along; plating was inert. Attachment was
measured from the **core**, power from the **reactors**: two graphs over the
same hexes, deliberately prised apart so that cutting a supply line left a part
dark and still attached rather than knocking it into space.

The bet was a conflict between how you destroy something and how you acquire
it: shoot a gun down to 12% and you get a wrecked gun, cut its supply line and
you get a 95% one.

## Why it was cut

**The builder became a topology puzzle instead of a question about what ship
you want.** Every limb needed a run out to it, so the interesting decision —
what this ship is *for* — got crowded out by the uninteresting one of how to
route wire to the thing you already decided to mount.

**The routing is invisible once the hull is drawn.** At flight zoom the cables
were finer than the hull's own seams and read as speckle. That is why the wire
layer was builder-only, which meant the mechanic's entire state was legible
only on the screen you are not on when it matters.

**It was never load-bearing.** `PowerGrid.solve()` was called from the builder's
overlay and a probe scene. `Ship`, `HullDamageModel` and `HardpointBank` never
mentioned it — a gun wired to nothing fired at full rate. Meanwhile a *second*,
live notion of power (`ShipLayout.total_energy_generation()`, a single pool with
a distance-from-core falloff) fed the HUD and regen. Two disagreeing models,
neither finished.

**No authored layout contained a conduit.** All 17 files in `resources/ships/`
predate it, so switching power on would have left roughly two thirds of every
enemy's consumers dark. Authoring runs across all of them was the larger half of
the remaining work, and it was content, not code.

## What survived into reactor circuits

- **Circuits as a concept**, but assigned logically by the player rather than
  derived from geometry. No adjacency, no routing, no pathfinding.
- **Role-based grouping** (propulsion / weapons / systems). It was the design's
  best idea and its worst rule: as a fixed law it removed all agency, so it now
  exists as a one-click "split by role" preset in the builder — a sensible
  starting split the player is free to overrule.
- **The cockpit fallback** (rev-3 spec §3). The Command Core now generates a
  meagre trickle of its own and forms a permanent circuit nothing can be
  assigned to, so losing every reactor leaves you limping rather than drifting.
- **Cut the supply, take the part** (rev-3 spec §2). `ModuleInstance.powered`
  and `HullPaint.is_cuttable()` are still in place and still unwritten — see the
  comment on that field for why it is deliberately not wired to circuit state.

## What did not survive

The Conduit module, all adjacency-based power routing, the "structure conducts,
modules are leaves" rule, the distance-from-core energy falloff
(`REACTOR_DISTANCE_PENALTY_*`), and the builder's POWER PATHS overlay.

**Do not reintroduce any of it.** If a future session finds this document and
thinks the reasoning above sounds recoverable, the answer is that it was
recovered — as circuits, without the geometry.

The conduit **art** is kept on disk (`resources/exports/*/[faction]_conduit*.png`)
because it is cheap to keep and expensive to redraw, and cable art may be
reskinned into something else. It is referenced by nothing.

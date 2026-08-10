# Frozen systems

Systems whose entry points have been disabled under the Phase 0 freeze. The
implementations stay in the repo untouched — freezing is removal of *access*,
not restructuring. Each entry records the flag that does the freezing, so the
list is greppable and every freeze is one flip away from being undone.

Phase 5 needs this list to decide what comes back.

---

## Inventory.research() — frozen Phase 0a

**Flag:** `ShipBuilderPanel.RESEARCH_FROZEN`

**What it did:** spent one captured tech part (`Inventory._captured_tech_totals`)
to permanently unlock a `ModuleType` with `requires_research = true`, making that
type craftable from `build_costs` thereafter.

**Why frozen:** it inverts the design thesis. A specific gun cut off a specific
corvette is consumed to make that gun an anonymous manufacturable type — the
part is destroyed and fungibility is what you get in exchange. The intended
replacement is mounting the recovered part itself.

**What's disabled:** the per-row RESEARCH button in the ship builder's module
list. `Inventory.research()`, `can_research()`, `get_researched_ids()`,
`set_researched()` and the `GameState` round-trip are all untouched and still
work if the flag is flipped.

**Known consequence:** `railgun_hardpoint` and `phase_lance_hardpoint`
(`ModuleCatalog` sets `requires_research = true` on both) now have no unlock
path at all and cannot be built. They stay dead content until the salvage path
can mount a captured part directly. Their rows still appear in the builder,
locked, and the craft-rejection message says so.

**Not affected:** the REPAIR button, which converts a captured part into a
placeable instance. It's a separate action on the same data and is due to be
rewritten in Phase 1 rather than frozen — it's the path that currently launders
part identity (`Inventory.repair_module` → `add_owned_module`), so it's a fix,
not a removal.

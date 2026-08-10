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

**Knock-on change:** `railgun_hardpoint` and `phase_lance_hardpoint` were the
only two types with `requires_research = true`, so freezing research would have
left them permanently unbuildable. Both flags were cleared rather than leave
dead content sitting in the builder — they're ordinary buildable types for now.
That's temporary: they become salvage-only once the recovered part can be
mounted directly, at which point the whole locked-type mechanism is decided
again from scratch.

`ModuleType.requires_research` now has no type using it. It's left in place
because `RESEARCH_FROZEN` is meant to be reversible; the craft path still checks
it and reports the freeze if anything ever sets it again.

**Not affected:** the REPAIR button, which converts a captured part into a
placeable instance. It's a separate action on the same data and is due to be
rewritten in Phase 1 rather than frozen — it's the path that currently launders
part identity (`Inventory.repair_module` → `add_owned_module`), so it's a fix,
not a removal.

---

## Module upgrade tree — frozen Phase 0a

**Flag:** `UpgradeMenu.frozen` (via the new `GamePanel.frozen`)

**What it did:** a full-screen radial tree of 89 unlockable nodes across seven
ship systems, each costing materials/components through
`ShipUpgradeService.try_unlock`, recorded ship-wide by id in `GameState`.

**Why frozen:** not one node has a stat effect. Unlocking spends resources and
changes nothing a player can feel — it fails the scope test ("does it change
what the player does in the 5-10 second loop?") outright, and it is the largest
single piece of build that ran ahead of validation.

**What's disabled:** the `toggle_upgrades` action ("U") no longer opens the
screen, and "U: Upgrades" is gone from `StationPrompt.PROMPT_TEXT`.
`UpgradeMenu`, `UpgradeTreeView`, `ShipUpgradeCatalog`, `ShipUpgradeService`,
`resources/upgrades/upgrade_data.json` and the `GameState` round-trip are all
untouched.

**Mechanism note:** freezing this needed a switch on `GamePanel` rather than in
`UpgradeMenu` alone, because the next freezes (crafting, trade, cargo) are the
same shape. `GamePanel.frozen` makes `_unhandled_input` ignore the toggle and
`open()` return false. That's an added switch, not a restructure — no panel
behaviour changed for any unfrozen screen.

**Watch for:** nothing calls `GamePanel.open()` from outside the panels
themselves today, so refusing to open has no other caller to surprise. If that
changes, `open()` returning false is the signal.

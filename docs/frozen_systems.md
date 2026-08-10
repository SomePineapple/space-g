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

---

## Crafting recipes (CraftingPanel) — frozen Phase 0a

**Flag:** `CraftingPanel.frozen`

**What it did:** converted raw materials into the six `ComponentCatalog`
intermediates (Metal Sheets, Wiring, Canister, Circuit Board, Reinforced Steel,
Motor) via `CraftingCatalog` recipes and `Inventory.craft()`.

**Why frozen:** it is the middle of the pipeline the design brief names as the
failure case — shoot asteroid → material → menu → component → menu → module.
Every layer is a translation the player has to perform in a list rather than in
the world.

**What's disabled:** the `toggle_crafting` action ("K") no longer opens the
screen. No UI anywhere advertised that key, so nothing else needed changing.
`CraftingCatalog`, `CraftingRecipe`, `ComponentCatalog` and
`Inventory.craft()/can_craft()` are untouched.

**Components still exist and still arrive** — combat kill-drops roll one with
`Ship.component_drop_chance` (0.3), of which `rare_component_chance` (0.25) come
from `RARE_IDS`. Freezing the panel doesn't strand them; it removes the
manufacturing route and leaves the salvage route, which is the intended
direction. The comment on `Ship.component_drop_chance` already described salvage
as "the alternative route to components" — it is now the only route.

**Known consequence, needs a tuning decision:** `hull` and `engine` are the two
most structural module types and both cost components (Hull: 2 Metal Sheets +
1 Reinforced Steel; Engine: 1 Metal Sheets + 2 Wiring + 1 Motor). A Motor is one
of three `RARE_IDS`, so roughly 2.5% of kill-drops — on the order of one per
15-20 kills at 2-3 drops each. Buildable, but slow. Either raise
`component_drop_chance` on the enemy scenes, or accept it as pressure toward
taking the engine off the wreck instead. Not changed here: that's balance, and
this commit is a freeze.

**Not frozen:** the ship builder's own BUILD button
(`ShipBuilderPanel._on_craft_pressed` → `spend_items(build_costs)`). That's
module construction, not component crafting, and it belongs with the material
economy in Phase 0b — after Phase 1, so salvage can feed the builder before
buying-with-materials stops.

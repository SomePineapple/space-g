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

---

## Trade menu and stock market (TradeMarketPanel) — frozen Phase 0a

**Flag:** `TradeMarketPanel.frozen`

The roadmap lists "Stock market" and "Trade menu" as two rows. In this repo they
are one screen: the Station Exchange, backed by the `MarketService` autoload.
One freeze covers both.

**What it did:** buying and selling all `MaterialCatalog` materials for credits
at a station, against `MarketService`'s live prices, with quantity chips, price
impact and spillover onto related materials. Also the game's only paid hull
repair.

**Why frozen:** credits are a universal solvent. Any part reachable through
money is reproducible — sell salvage, buy the thing — which is precisely what a
part cut off a specific wreck is not supposed to be. Freezing the exchange
before freezing credits themselves is deliberate: it removes the conversion
without touching the number, so nothing that reads a credit balance breaks.

**What's disabled:** the `toggle_trade` action ("T") no longer opens the screen,
and "T: Trade" is gone from `StationPrompt.PROMPT_TEXT` (which the ship
builder's status line also displays). `MarketService`, `MarketMaterial` and
every `scenes/ui/market/` component are untouched, and the service still ticks
in the background — harmlessly, since nothing reads it while the screen is shut.

**Forced change — hull repair.** `TradeMarketPanel._repair()` was the *only*
caller of `Ship.repair_fully()`. Freezing the screen with no other change would
have capped the hull at `passive_repair_cap_fraction` (0.4) permanently, which
fails the "playable after every freeze" rule. Two edits in
`hull_damage_model.gd` replace it:

- `passive_repair_cap_fraction` 0.4 → **1.0**. Holed-out modules now regrow all
  the way instead of stopping at 40% and waiting for a bill.
- `_regenerate_modules()` now also heals modules that took chip damage without
  being holed out. They were skipped entirely before — the paid repair was the
  only thing that ever topped them up — so without this, partial damage
  accumulated forever. They heal in place and do not enter `_regrowing`, which
  would switch them off and respawn a collision shape they never lost;
  `_advance_repair()` takes a `was_regrowing` flag to keep the two apart.

`Ship.repair_fully()`, `needs_repair()`, `get_repair_cost()` and
`repair_credit_cost` all still exist with no caller.

**What this costs:** the station is now weaker as a destination — it repaired
you, and now it only builds. Recovery is entirely passive and automatic, on a
`repair_delay` of 6s at `repair_rate` 6 condition/sec. That is generous; if the
loop wants attrition, the lever is `repair_rate`, not the cap. **Detached
(severed) modules are still gone for good** — the jeopardy the thesis wants
lives in losing the part, not in a repair bill, and that is unchanged.

---

## Credits — frozen Phase 0a

**Flag:** `Hud.CREDITS_FROZEN`

**What it did:** a per-inventory currency (`Inventory._credits`), persisted
through `GameState`, displayed top-right on the gameplay HUD.

**Why frozen:** any part reachable through money is reproducible. Credits are
the mechanism by which a specific thing becomes an amount.

**Why this freeze is small:** the exchange was the only thing that ever created
or consumed credits — `add_credits` had exactly one caller (a market sale) and
`spend_credits` two (a market purchase and the paid repair), all inside the
screen frozen in the previous entry. Freezing that screen already made the
balance inert. What was left was a permanently static number in the corner of
the HUD, so this freeze is just hiding the readout.

**What's disabled:** `Hud`'s `CreditsLabel` is hidden and its `credits_changed`
subscription is skipped. `Inventory.get_credits/add_credits/has_credits/
spend_credits`, the `credits_changed` signal, `Ship.repair_credit_cost`,
`Ship.get_repair_cost()` and the `GameState` round-trip are untouched — a saved
balance still loads and saves, it is simply unreachable and unspendable.

**Spec deviation to remember:** `docs/HUD-1d-Godot-spec.md` element 4 is the
credits readout. The HUD no longer matches its spec on that one element. Don't
"fix" it back; unfreeze it or amend the spec when Phase 5 decides.

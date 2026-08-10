# Direction — what SpaceG is building, and what not to undo

**Read this before `roadmap.md` or `Roadmap v.2-v.9.md`.** Those describe the
game as it was being built up to Phase 5. This document supersedes them on
questions of *direction*: a design review plus the first human playtest changed
what the game is trying to be, and a lot of shipped, working code was
deliberately switched off as a result.

Read alongside:

- `docs/frozen_systems.md` — the seven freezes, each with the flag that undoes it.
- `docs/multiplayer.md` — the seams. **Everything in this document is written to
  hold under both multiplayer modes described there.** That is not decoration;
  see "The multiplayer frame" below.
- `CLAUDE.md` — working rules, still in force and unchanged.

---

## 1. The thesis

**Parts are cut off enemies, not bought from a catalogue.**

That one sentence is the game. Everything else is downstream of it. The
mechanism that carries it is *part instancing*: a mounted module is not "a
railgun", it is **this** railgun — with an identity, an origin, accumulated
damage, and a history of what it has killed. It came off a specific corvette in
a specific fight. If it is destroyed, that particular object is gone. Another
railgun is not the same railgun.

Three properties follow, and they are the actual design requirements:

- **Persistence** — a part survives across fights and carries its state with it.
- **Jeopardy** — losing it is a real loss, because it cannot be re-bought.
- **Non-fungibility** — no mechanism may convert a specific part into an amount
  of anything, or an amount of anything back into that part.

### Two tests to apply to any proposed feature

**The noun test (Minecraft).** How many nouns stand between the player and the
thing they want, and how many are translation layers rather than objects in the
world? Minecraft: wood → plank. Two nouns, one step, both physical. The pipeline
this project had built was ore → material → component → module: four nouns,
three of them existing only in menus. If a feature adds a noun that lives in a
list rather than in space, it is probably wrong.

**The scope test.** Does it change what the player does in the 5–10 second
loop? The 89-node upgrade tree did not change a single stat. That is how a large
amount of work reached the repo without touching the game.

### What the thesis rules out

Currency of any kind. A buy/sell market. Research that converts a captured part
into a manufacturable type. Crafting chains that turn objects into bulk
material. A grinder or smelter that reduces a specific thing to an amount.

These are ruled out **on principle, not on balance**. Do not reintroduce one
because it would solve a supply problem. A supply problem is solved by making
combat drop the right things, not by adding a shop.

---

## 2. The multiplayer frame

The project targets two shapes (`docs/multiplayer.md` §"The two intended
modes"): **mode 1**, one ship per player; **mode 2**, one ship with several
players as crew. No networking exists — what exists is seams. Every design
commitment in this document is stated so it survives both modes, and Phase 1
lands directly on top of the seams. Get these wrong and the work has to be
redone.

**Part identity is replicable state, so build it that way from the first
commit.**

- **IDs must be network-stable.** Use `GameRng.next_id()`. Never wall-clock
  values, never node paths, never `get_instance_id()`. This rule already exists
  because `Time.get_ticks_usec()` was removed from identifier generation for
  exactly this reason — do not walk it back for part instances.
- **`ModuleInstance` must stay pure data.** Serialisable to a dictionary, no
  node references, no `Object` fields, no back-pointer to the ship. An instance
  that can only be described by pointing at a live node cannot be replicated,
  saved, or handed between ships.
- **Do not add a global part registry autoload.** It is the tempting shape for
  instancing and it is wrong twice over: `CLAUDE.md` restricts autoloads, and a
  single global registry is precisely the mode-1 mistake `GameState` already
  makes. Instances are owned by the inventory or the layout that holds them.

**Non-fungibility is a replication asset, not a cost.** A count is a scalar any
client can recompute and any two clients can silently disagree about. An
instance is an object with an ID that must be explicitly replicated — which
means divergence is visible instead of quiet. Deleting the count-keyed capture
path (`Inventory.add_captured_tech(module_type_id)` storing a per-type integer)
is simultaneously the design fix and the networking fix. This is the clearest
case where the thesis and the multiplayer work point the same way.

**Wrecks are world objects, not decoration.** When wrecks stop calling
`queue_free()` and start persisting, they become replicated entities with
lifetimes and IDs. Spawn them through `WorldSpawn.attach_at()` — that is the
hook where authority and replication get enforced. Only genuinely local
presentation (a pickup sound, a screen tint) bypasses it, and each such case is
commented at its site.

**Cutting is an intent, and its outcome is authority-resolved.** The grinder
already has a field on `ShipIntent` under the OPERATIONS role. Keep it that way.
A hardpoint script must not reach into a wreck and mutate its part data
directly; it calls a small public method on the wreck and lets the wreck decide.
That single indirection is what lets an authority be inserted later without
rewriting the tool. It is also just the scene-ownership rule from `CLAUDE.md`.

**Which rolls use `GameRng`.** Anything that decides an outcome — what a wreck
yields, whether a part survives being cut free, damage state on capture — is
simulation randomness and uses a named `GameRng` stream. Sparks, shake and
particle jitter stay on the global `randf()`; drawing them from a shared stream
would advance it a different number of times per machine and desync every
simulation roll downstream.

**The mode-1 landmine to avoid deepening.** `GameState` is one global snapshot:
one inventory, one layout, one health fraction. That is correct for mode 2 (one
ship, one shared hold) and wrong for mode 1. Part instances make this sharper,
because two players must never be able to hold the same instance. Do not add
more global-snapshot state while building Phase 1. Keep instance ownership with
the ship that holds it, so making it per-player later is a change to
`GameState`, not to every system.

**Mode 2 makes the thesis better, and is worth designing toward.** A crew
sharing one hull, one hold, and a small number of irreplaceable parts —
deciding whose station gets the good gun — is a much stronger fit for
non-fungibility than a currency ever was. Where a Phase 1 choice is genuinely
ambiguous, prefer the one that reads well with a crew arguing over a single
part.

---

## 3. Phase 0 is complete — do not quietly undo it

All eight rows of the freeze table are applied across seven commits. Full detail
in `docs/frozen_systems.md`; the flags are:

| System | Flag |
| --- | --- |
| Research (captured part → buildable type) | `ShipBuilderPanel.RESEARCH_FROZEN` |
| 89-node upgrade tree | `UpgradeMenu.frozen` |
| Crafting recipes | `CraftingPanel.frozen` |
| Trade menu + stock market | `TradeMarketPanel.frozen` |
| Credits | `Hud.CREDITS_FROZEN` |
| Asteroid ore drops | `Asteroid.MINING_FROZEN` |
| Grinder ore output | `HardpointGrinder.ORE_OUTPUT_FROZEN` |

**Freezing means disabling the entry point.** The implementations are all still
in the repo, untouched and reversible by one flag. Nothing was deleted.

Rules that still apply:

- **Do not flip a flag back to unblock yourself.** If a freeze is genuinely
  wrong, say so and argue it. Silently unfreezing to make a task easier is the
  one failure mode this whole phase was designed to prevent.
- **Do not delete frozen code either.** Phase 5 revisits the list and decides
  what returns. That decision needs the code to still exist.
- **Do not "fix" the consequences.** Two are recorded deliberately: the HUD no
  longer matches element 4 of `docs/HUD-1d-Godot-spec.md` (the credits readout),
  and region asteroid densities in `resources/regions/*.tres` were tuned as a
  yield curve that no longer exists. Both are noted in `docs/frozen_systems.md`.
  Restoring either to match its old spec re-breaks the freeze.

### What the game is right now

Killing things is the only source of anything: 2–3 salvage pieces per kill,
roughly 70% raw material and 30% components. Those feed the ship builder's BUILD
button, which is the one economy entry point still live — deliberately, because
freezing it before Phase 1 would leave no route at all from a wreck to a mounted
part.

Hull repair is now fully passive (`passive_repair_cap_fraction` 1.0), because
the frozen trade screen held the only paid repair. Severed modules are still
gone for good; the jeopardy lives in losing the part, not in a repair bill.

---

## 4. The build order

**Step 0: play the game for ten minutes.** Before writing Phase 1 code. The loop
is much thinner than the last version anyone played, and that is the point.
Building part instancing on an unfelt loop is how the upgrade tree happened.

**Phase 1 — make parts into things.**

1. Part instances: give `ModuleInstance` an origin, a damage state, and a kill
   count. It currently has only `instance_id`, `module_type_id`,
   `manufacturer_id`.
2. Three part states — intact, damaged, destroyed — as one authoritative
   representation. Today `HullDamageModel.is_destroyed()` conflates destroyed,
   detached and mid-regrowth, and `_conditions` is wiped on every `rebuild()`,
   so condition cannot survive a refit. Condition belongs on the instance.
3. Wrecks persist instead of `queue_free()`.
4. Cutting: take a specific part off a specific wreck.
5. Cargo triage: a hold of named objects, not a table of counts.
6. Mount it: the recovered part itself goes on the ship. This closes the loop
   and is the whole point of the phase.

**Phase 2 — make the parts matter.** 7. A felt difference between parts.
8. Power buses. 9. Disable rather than destroy.

**Phase 3 and beyond** is not planned and should not be planned yet.

### The identity leak Phase 1 has to close

The current capture→mount path launders identity twice and both ends need
fixing:

- `Inventory.add_captured_tech(module_type_id)` stores a **count keyed by
  type**. The specific part stops existing the moment it is picked up.
- `Inventory.repair_module()` calls `add_owned_module()`, which constructs a
  **brand-new** `ModuleInstance`. Even if the first leak were fixed, the second
  would replace the object with a fresh one.

Fixing these is not a refactor to schedule around Phase 1 — it *is* Phase 1.

---

## 5. How to work on this

From `CLAUDE.md`, restated because the freeze made them load-bearing:

- **One system per change, playable after every one.** This was the Phase 0 rule
  and it is a good default for Phase 1 too.
- **Do not refactor while doing something else.** Two of the seven freezes
  required a change beyond the entry point (the `GamePanel.frozen` switch, and
  passive repair replacing the paid one). Both are documented as forced, with
  the reason. That is the bar: a change beyond scope needs a written
  justification, not a judgement call made in passing.
- **Verify by running the project**, not by `--check-only --script`. That mode
  does not load autoloads and reports false "Identifier not found" errors for
  `PlayerContext`, `GameRng` and friends. Use
  `Godot --headless --quit-after 120` on the whole project.
- **`@export` values set in `_init()` are overridden by a `.tscn` that stores
  them.** Every freeze flag was checked against its scene file for this. Check
  yours.
- **Do not commit unless asked.** Suggest a message instead.

### On being agreeable

The design review that produced this direction was preceded by one that agreed
with everything it was shown and expanded the scope while doing so. The user has
asked explicitly for the opposite. Disagreement that is argued is more useful
than confirmation. If a request contradicts the thesis in section 1, say so
before implementing it — then implement what was actually asked for if the user
reaffirms it.

---

## 6. Open, and deliberately not decided

- Whether `Ship.component_drop_chance` (0.3, of which `rare_component_chance`
  0.25) should rise now that crafting is frozen. A Motor is one of three rare
  components and the Engine needs one — roughly one per 15–20 kills.
- What the grinder becomes. Right now it is a rock-breaker that earns nothing.
  Phase 1 step 4 is expected to make it the cutting tool; that is an
  expectation, not a decision.
- Whether asteroid density per region wants re-tuning now that rocks are purely
  spatial.
- What returns from the freeze list in Phase 5, and in what form.

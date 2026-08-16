# SpaceG — Phase 4 Specification (rev 3)

**For handoff to implementation and UI.** Two systems: part states and power capacity, with power delivered through the hull's own structure.

**Change from rev 2:** junctions are gone. They were a separate hex part whose optimal placement was "hidden next to the reactor," which made them a mandatory tax with no gameplay in them — and unusable on a 13-cell starter ship. Modules now draw power through the **structural path** back to the reactor, which is the connectivity graph you already have.

**Read this first.** 4.1 and 4.2 are one mechanic in two commits. Neither pays off alone. Build the throwaway prototype in §6 before either.

---

## 1. Why Phase 4 exists

### The thesis has no mechanism

The premise is *"you don't build your ship, you cut it off the things that tried to kill you."* The moment it must produce, mid-combat:

> *"That ship is dangerous, but I want that gun."*

That requires a **conflict** between how you'd destroy something and how you'd acquire it. Right now there is none — parts are functional or destroyed with nothing between. To stop a gun firing you must destroy it, and a destroyed gun isn't worth taking.

### Combat is a DPS race

No cost to firing, no cost to running everything at once, no reason to reposition beyond avoiding damage. The only decision is aim.

### Blobbing is unpunished

Measured: hull costs 5.4–6.9% acceleration per cell against +23–34% health. Immediate benefit, diffuse cost.

- **A percentage penalty per part never limits part count.** Five guns at 50% out-damage two at 100%. The 50/75/100 field-weld spread makes *when* you attach a decision; it does nothing about *how many*.
- **Connectivity-severance currently rewards density.** A dense hull has redundant paths and no single cut severs anything.

**The capacity model in §3 is the hard cap.** §4 turns the second point from a bug into the central tradeoff.

---

## 2. Part states (4.1)

| State | Functions | On hull | Recoverable | Visual |
|---|---|---|---|---|
| **Functional** | Yes | Yes | Yes, at condition | Lamps lit |
| **Disabled** | No | Yes | **Yes, at condition** | Lamps dark, plating intact |
| **Destroyed** | No | Debris | No | Blackened, broken |

Must work on **live enemies**, not just hulks.

### The damage band — deliberately crude

Damage is a *safety net* route to disabled, not the intended one. A generous band makes the optimal salvage technique "carefully shoot the gun to 24%," which is health-bar surgery and the wrong skill to reward.

| Condition | State |
|---|---|
| 100–35% | Functional |
| 35–15% | Damaged but functional |
| Under ~15% | Disabled |
| 0% | Destroyed |

You *can* disable by shooting, but it's risky and leaves you a wrecked 12% gun. Cutting its power path gets you a 95% one. **The structural route is clearly better for salvage without being mandatory.**

### Routes into disabled

1. **Power path severed** (§4) — the interesting one
2. **Damage under ~15%** — the forgiving one
3. **Deliberate shutdown** (§3) — the player's own lever

### Success criteria

- Shoot an enemy gun until it stops firing. Still visibly attached, dark, cuttable.
- Recovering it yields the part at the condition it was left in.
- Continuing to shoot a disabled gun destroys it. **The player can over-kill and lose the prize.**
- Disabled reads differently from destroyed at gameplay zoom, without a HUD element.

### Failure modes

- **Destroying stops being viable.** Disabling must cost time and exposure — destroying should stay faster and safer when the player doesn't want the part.
- **Enemies feel unkillable.** Disabled core = combat over.

---

## 3. Power capacity (4.2)

### Capacity, not allocation

Two models get conflated and they behave very differently:

- **Capacity** — the core supplies N units. Each module costs a fixed amount to run. N units feeds N units of modules; the rest sit dark. Binary, legible, and a **hard cap on ship size**.
- **Allocation** — you choose how much each system gets, more power meaning better performance. Continuous, fiddly, and **caps nothing** — bolt on ten guns and run them all badly.

**Capacity is the base model.** Allocation exists only as the preset shift in §3.3.

### The numbers

Starter loadout at roughly **60–75% of capacity with all systems idle**, so:

- Everything-on is possible while cruising
- Firing, tractoring or boosting pushes past capacity
- Adding modules moves the ship toward permanent deficit

**Weapons must draw meaningfully while firing, not just at idle.** Idle-only draw is a build-screen decision. Firing draw is a combat decision.

### More potential capability, not more simultaneous capability

The goal is **not** "the fifth weapon makes the ship worse than four" — that makes the builder's answer "never add anything," a different degenerate outcome.

- **4 guns** — all usable at once, good sustained fighting, simple management
- **5 guns** — can't sustain all five, but can volley harder, alternate banks, survive losing one

Adding modules broadens what the ship *can* do while forcing choices about what it does *at any moment*.

### Presets, not sliders

FTL pauses by default with discrete pips and unlimited thinking time. SpaceG is real-time with inertia, aiming and dodging. **Every second on a power panel is a second not flying, and flying is the thing that tests well.**

Three or four modes on single keys — **Cruise / Combat / Burn / Silent**. Each a fixed allocation. One key changes the ship's posture.

The decision becomes *when to switch*, which is real in real time — rather than *how many pips go where*, which is arithmetic solved once.

Power is an **emergency lever, three or four moments a fight** — not a rhythm the player babysits.

### Efficiency scaling — sparing

Most systems are **binary**: fed or dark. Only two or three have a meaningful high/low state (engines: move vs. boost; weapons: slow vs. full rate).

Binary is what makes §2 legible — a module is lit or it isn't, and the ship reads at a glance.

### Multiple cores

Each core anchors its own power paths. **Two cores means two independent power islands** — lose one and you lose that half of the ship. Redundancy paid for physically.

**Watch the reactor tax.** If a second core is simply "10 units instead of 5," then "I need more power" → "add another reactor" is accountancy. A second core must cost enough — hexes, mass, a shootable target — that it trades against carrying a gun.

### Cockpit fallback

A small, unkillable trickle from the cockpit keeping **only thrusters and basic control** alive. Not enough to fight. Enough to limp home.

The difference between "lost the fight" and "died." Turns worst moments into escape stories rather than reload screens.

### Success criteria

- Starter ship: headroom cruising, short while fighting.
- Player switches preset mid-fight without a menu, and feels it.
- A fifth weapon changes *how* the ship fights rather than simply making it worse.
- "Why did you switch to Burn?" answerable in one sentence.
- Losing all reactors leaves the player crawling home, not dead.

### Failure modes

- **Power as accountancy** — see reactor tax.
- **Set-and-forget** — if one preset is always right, it's decoration. Combat draw prevents this.
- **Punishing rather than interesting** — shedding weapons is a setback; shedding thrusters mid-nebula is unfair. Hence the fallback.

---

## 4. Power through structure

### The model

**No junction part. No conduits. No routing UI.**

A module is powered if a **structural path exists through occupied hull cells back to a reactor**. Sever the path and everything beyond it goes dark — undamaged, still attached, still cuttable.

This reuses the connectivity graph already driving severance. The verb is the one already established and already better than the original spec: **you aim at what holds a part on, not at the part.** Now the same shot also decides whether it keeps working.

### Why this beats a junction part

- **No hex cost, no mass cost.** Works on a 13-cell starter ship immediately.
- **No hiding problem.** A junction's optimal placement was "buried next to the reactor," making it unshootable and therefore pointless. Structural paths run through hull, and hull is by definition exposed somewhere.
- **It finally makes blobbing a real tradeoff** (below).
- **It's already built.** Connectivity exists.

### This is where blobbing gets priced

Previously the severance model rewarded density with no counterweight. Now it cuts both ways:

| Hull shape | Effect |
|---|---|
| **Dense blob** | Redundant paths; one cut isolates nothing. Survivable, but **also impossible to dismantle surgically** — a blob enemy is a brute-force target, not a shopping list. |
| **Sprawling limbs** | Single paths; one cut isolates a whole arm. Fragile, but **highly lootable** — a sprawling enemy can be surgically stripped. |

The player faces the same trade on their own hull: **build a brick and you're hard to disable but slow and blunt; build limbs and you're fast and expressive but a good pilot can shut you down a section at a time.**

That is a genuine build decision with no dominant answer, produced by systems already in the codebase.

### Redundancy must be possible

**Non-negotiable.** Losing one path should be a serious problem played through, never instantly fatal.

- Do not funnel all paths through a single cell adjacent to the cockpit
- The cockpit fallback (§3) is the floor — the player always keeps thrusters
- If a hull shape can be one-shot into total shutdown, the model needs a floor, not a redesign

### Legibility check — the one real risk

**Does the path from reactor to module match player intuition?**

- Sever mid-arm, everything outboard goes dark → reads correctly
- Power routes through a non-obvious cell and something unrelated dies → reads arbitrary

If the graph produces surprising results, the fix is **making the path visible** (§5), not changing the rule. But this needs checking early — an illegible model is worse than no model.

### Deferred to later

**Salvageable Power Distributor.** A part that adds a redundant path, so a single cut no longer isolates. Genuinely good — it puts power architecture inside the salvage thesis, and pirate/corporate/ancient variants would give factions systemic identity. **But it's an hour-20 upgrade and hour-1 overhead.** Bring it back once the base model is proven.

---

## 5. UI

### Principle

**Does this let the player keep their eyes on the ship?** In the builder they've already stopped, so a dedicated view is fine. In combat, never.

If the player reads a panel more than they read their ship, the visual design isn't carrying its weight. **The ship sprite is the primary readout.**

### Builder — showing power paths

An overlay *inside* the build screen, not a separate destination.

The player needs to see which cells carry power and where a cut would isolate something. Worth prototyping:

- Path highlight from reactor outward, on toggle
- Hover a module, see its path back to the core
- A "what if this cell is cut?" preview showing what would go dark

**The colour collision is the real constraint.** Plating already carries faction origin (rust Kessari, violet Voidwright). A second fill colour will fight it and the player will read neither. Use contrast, not hue: a dim-everything-else mode, or an outline on the active path.

### In flight

Powered parts glow; unpowered go dark (§7 — a dependency, not polish). When a path is cut, the player must immediately know which capability went.

Systems panel needs:

- **Capacity as a bar, not a number.** `3.2/10` is arithmetic; a bar near its limit is tension.
- **Deficit as the loudest element** when demand exceeds supply.
- **Combat draw, not idle draw.** A weapon listed at 0.8/s that costs 4/s firing is lying.
- **Current preset, visible.** One word, always on screen.

### On enemies

The player should be able to look at a hostile hull and see where it's thin — where one cut isolates a limb. This is silhouette reading, not a HUD marker, and it's the skill the whole mechanic is teaching.

---

## 6. Build this first — the throwaway prototype

**Before 4.1 or 4.2.** Ugly, hardcoded, deleted afterwards.

```
Enemy ship:
  Reactor ── hull ── hull ── Big Gun

Route A — shoot the gun
  → condition drops → destroyed → nothing to salvage

Route B — cut the hull between them
  → gun goes dark, stays intact
  → approach, cut it off, attach it, power it, fire it
```

No power bar. No presets. No priority system. No overlay. One enemy, one gun, one connecting path.

**The entire phase is one bet:** *"destroy the threat" versus "preserve the prize" is fun enough to build a game around.* Validate the bet before building the infrastructure.

**Build it as a genuine throwaway** — a scene you delete, not a first pass at 4.1. The pattern this project keeps repeating is systems built before the assumption under them is checked, and a "prototype" that's secretly the real implementation is how that happens again.

---

## 7. Dependency: glow bound to power state

Destroyed modules currently go dark, but a powered-off module still glows. **Cutting a power path is meaningless if the modules look identical afterwards.**

Land this with §4, not before, not after.

**Faction decision stands:** plating carries origin, lamps carry ownership. A captured part visibly *joins* your ship rather than staying foreign forever.

---

## 8. Gate 2 — three variants

**A — "I want that gun."**
Can the player deliberately disable it and take it intact?

**B — "I just want this thing dead."**
Is destroying still quicker and satisfying? If surgical play is strictly better, there's no choice.

**C — "Something went wrong."**
The player destroys the gun they wanted. **Do they immediately understand what they did?** If not, the mechanic is illegible and no tuning fixes illegibility. **Most important variant.**

The goal is not that surgical combat works. It's that **surgical and destructive combat feel like two legitimate approaches to the same encounter.**

Judged on:
- Does the player notice the choice unprompted?
- Does the harder route feel worth it, or does everyone just blow ships up?
- Does the fight get more interesting, or just longer?
- Twenty minutes in, is the player still thinking about which part they want?

**If this fails, the hook is wrong** — and that must be known before Track B, which is eight zones designed around a verb this gate validates.

---

## 9. Explicitly deferred

**Salvageable Power Distributor.** See §4. Hour-20 upgrade, hour-1 overhead.

**Enemy rerouting.** A ship that restores power to a weapon after a few seconds is a good idea and would give factions systemic identity. It also directly undermines the verb being validated — the player cuts power to take a gun, and the enemy switches it back on. **Revisit after Gate 2.**

**Continuous allocation sliders.** See §3.3.

**Weapon arc occlusion.** Cheap version when part supply is real: fixed firing cone blocked by adjacent occupied cells — a neighbour lookup, not a raycast.

---

## 10. What this must not become

- **Per-hex cable routing.** The reason junctions were dropped. Do not reintroduce it as "power conduits."
- **A build-screen optimisation problem.** Every decision should be felt in the 5–10 second loop.
- **A power management game.** Presets and emergencies, not a rhythm.
- **More UI.** The ship sprite is the readout.

---

## Prerequisite

**Gate 1 is still unrun.** Wreck pressure is the last item before it. The prototype in §6 is downstream of that answer — if cutting isn't fun with stakes attached, Phase 4 is building on sand.

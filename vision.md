# Project Vision & Design Bible

## Working Title

*(To be decided)*

---

# Vision Statement

We are building a handcrafted space adventure where **flying through space is as enjoyable as arriving somewhere**.

Every battle should leave a story. Every discovery should expand the player's possibilities. Every upgrade should make the ship feel more personal.

The ship is not just a vehicle.

**The ship is the player.**

By the end of the game, every player's ship should look different because every player's journey has been different.

---

# Core Pillars

## 1. Piloting Comes First

If flying isn't fun, nothing else matters.

Travelling should never feel like simply moving from point A to point B.

Players should constantly be making small decisions:

* Investigate an anomaly?
* Salvage a wreck?
* Scan an unknown signal?
* Avoid pirates?
* Explore a hidden asteroid field?

Movement itself should feel satisfying through:

* Responsive controls
* Weight and inertia
* Weapon recoil
* Beautiful engine trails
* Environmental effects
* Smooth camera movement
* Memorable warp travel

A player should enjoy flying even if absolutely nothing happens.

---

## 2. The Ship Tells the Story

The player's ship is their identity.

Every upgrade, repair, battle and discovery should leave a visible mark.

Examples include:

* Battle scars
* Repaired armour panels
* Mismatched salvaged parts
* Different coloured engine exhausts
* Alien technology growing around the hull
* Corporate shield emitters
* Pirate weapon mounts
* Cargo physically attached to the hull

The ship should become a visual diary of the player's adventure.

If someone shares a screenshot, another player should immediately think:

> "I wonder where they found that."

---

## 3. Exploration Should Always Matter

Exploration is never just about revealing the map.

Every discovery should provide something meaningful:

* New technology
* Resources
* Story
* Beautiful scenery
* New factions
* Strange phenomena
* Hidden locations

Quality is more important than quantity.

Five unforgettable systems are better than fifty forgettable ones.

---

## 4. Salvage Is Gameplay

Destroyed ships should not simply become numbers.

Instead, they become opportunities.

Wreckage should scatter into space.

Players use a tractor beam to collect valuable components.

Salvage should be instantly recognisable through colour and visual effects rather than reading tooltips.

Example rarity colours:

* Grey — Common materials
* Blue — Electronics
* Green — Energy components
* Purple — Experimental technology
* Gold — Ancient artefacts

Some salvage should also be dangerous.

Examples:

* Unstable reactors
* Radioactive cores
* Explosive ammunition
* Alien biological material
* Corrupted AI components

The player should sometimes ask:

> "Is that worth risking?"

---

## 5. Combat Creates Stories

Combat is not about reducing a health bar.

Ships are physical objects.

Modules can be disabled.

Weapons destroyed.

Engines knocked out.

Shield generators overloaded.

Enemy ships should visibly change throughout battle.

Players should make tactical decisions such as:

* Remove engines first?
* Destroy shields?
* Disable weapons?
* Preserve valuable technology for salvage?

Every battle should feel different.

---

## 6. Reverse Engineering, Not Unlock Trees

Technology should feel discovered rather than purchased.

Instead of filling progress bars, players recover unknown technology.

Initially:

Unknown Device

↓

After research:

Gravity Core

↓

After mastering it:

Manufacturing unlocked.

The player should feel like they are learning how the universe works.

---

# Factions

Each faction should have a clear identity.

Technology should reflect philosophy rather than simply increasing statistics.

Examples include:

## Pirates

* Improvised engineering
* Ballistic weapons
* Powerful but unreliable
* Patchwork appearance
* Cheap modifications

---

## Corporate Alliance

* Precision engineering
* Energy weapons
* Efficient reactors
* Strong shields
* Clean industrial aesthetics

---

## Ancient Civilisation

* Gravity technology
* Exotic energy
* Warp manipulation
* Mysterious relics
* Advanced automation

---

## Organic Species

* Living ships
* Regenerating armour
* Biological weapons
* Symbiotic reactors
* Technology that grows over time

Players should gradually create hybrid ships using technology from multiple factions.

---

# Manufacturers

Within factions, manufacturers should have distinct personalities.

Players shouldn't simply say:

"I found a Level 5 Cannon."

They should say:

"I finally found an Atlas railgun."

Example manufacturers:

### Atlas Heavy Industries

"If it survives the recoil, it'll survive the enemy."

* Massive recoil
* Huge damage
* Heavy construction

---

### Nova Precision

"Every shot matters."

* Accurate
* Fast
* Low recoil

---

### Black Market Foundry

"If it works... don't ask why."

* Illegal
* Experimental
* High risk
* High reward

Manufacturers help create memorable equipment rather than generic upgrades.

---

# Atmosphere

Atmosphere is more important than realism.

Space should feel alive.

Examples include:

* Nebulae affecting sensors
* Asteroid storms
* Ancient megastructures
* Ringed planets
* Drifting wreck fields
* Solar flares
* Strange cosmic phenomena

Even empty travel should be beautiful.

---

# Multiplayer Philosophy

The game is designed as a **single-player experience first**.

However, systems should be built so that multiple ships can naturally exist within the same world.

Future co-op vision:

* Drop-in / drop-out
* Same campaign
* Bring your own ship
* Shared exploration
* Shared combat
* Shared adventures

Friends should feel like they have travelled into your universe—not joined a lobby.

Multiplayer should enhance stories, never become a requirement.

---

# Design Rules

When making any feature, ask:

* Does this make flying more enjoyable?
* Does this make the universe feel more alive?
* Does this create memorable moments?
* Does this make the player's ship feel more personal?
* Does this encourage meaningful decisions?
* Would I want to stop and take a screenshot?

If the answer is **no**, the feature probably doesn't belong.

---

# Things We Will Avoid

* Artificial grind
* Huge empty maps
* Generic loot
* Upgrades that are simply larger numbers
* Mandatory multiplayer
* Repetitive resource farming
* Copying Starcom feature-for-feature

Our goal is inspiration, not imitation.

---

# Long-Term Goal

We want players to finish the game, look at their ship, and remember where every important part came from.

The ship should become the physical record of their journey.

---

# Guiding Principle

> **"If a player screenshots their ship after twenty hours, another player should be able to guess the story of their adventure."**

## Long-Term Crew Vision

The immediate game is a single-player, ship-focused space exploration experience built around:

* enjoyable piloting
* modular ship construction
* tactical combat
* salvage
* exploration
* technology discovery

These systems must succeed independently before crew management or multiplayer is developed.

Long term, the same ship may be operable by either one player or several players working together.

A future crew layer could introduce responsibilities such as:

* Helm and navigation
* Weapons and targeting
* Engineering and power management
* Shields and damage control
* Scanning, salvage and ship operations

In single-player, these systems should remain manageable by one person through automation, shortcuts, AI assistance and clear interfaces.

In multiplayer, responsibilities may be divided in two ways:

1. Players pilot separate ships within the same universe.
2. Multiple players operate different stations aboard one shared ship.

This is an end-state direction, not a requirement for the initial game.

No system should be made more complicated solely to support hypothetical multiplayer. Crew-operable systems should first improve the single-player experience.

The current development priority remains:

> Build the strongest possible single-player modular space exploration game first.

## Architectural Implication

The game should remain ship-centric rather than player-centric.

Where practical, ship capabilities should be represented as independently operable systems or stations. Control of those systems may eventually be assigned to:

* the primary local player
* AI assistance
* another local or networked player

This should influence clean system boundaries, but must not introduce premature networking, crew simulation or multiplayer-specific complexity.

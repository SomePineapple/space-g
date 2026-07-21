# Roadmap

## Guiding Architecture

### Core Principle

The game is **not** built around a player.

The game is built around **ships**.

A ship can be controlled by:

* A human
* An AI
* A Network Client (future)

The game world should never care who controls the ship.

Every major system should operate on a ship entity rather than a player entity.

This is our biggest investment towards future drop-in co-op.

---

# Phase 1 — Flight Prototype

**Goal:** Make flying enjoyable.

## Features

* Ship entity
* Ship controller
* Physics-based movement
* Rotation
* Thrust
* Reverse thrust
* Boost
* Inertia
* Camera
* Engine particles
* Weapon recoil affecting movement
* Screen shake
* Background parallax
* Asteroids to fly around

## Success Criteria

Players should happily fly around an empty map for ten minutes.

If this isn't fun, nothing else matters.

---

# Phase 2 — Combat Prototype

**Goal:** Combat feels satisfying.

## Features

* Modular ship health
* Projectiles
* Lasers
* Ballistic weapons
* Enemy AI ships
* Damage effects
* Module destruction
* Engine destruction
* Weapon destruction
* Explosions
* Floating wreckage

## Architecture

Ships own modules.

Modules own behaviour.

Weapons don't belong to the player.

Weapons belong to the ship.

## Success Criteria

Every fight should tell a slightly different story.

---

# Phase 3 — Salvage Loop

**Goal:** Complete first gameplay loop.

Fight

↓

Destroy

↓

Salvage

↓

Upgrade

↓

Fight stronger enemies

## Features

* Tractor beam
* Floating resources
* Resource rarity
* Dangerous salvage
* Inventory
* Shipyard

## Success Criteria

The gameplay loop becomes enjoyable without any story.

---

# Phase 4 — Ship Builder

**Goal:** Create emotional attachment.

## Features

* Grid-based construction
* Hull pieces
* Engines
* Weapons
* Shield modules
* Cargo
* Reactors
* Power distribution
* Hardpoints

Every part should visibly appear on the ship.

The ship should become recognisable.

## Architecture

Ship

├── Hull

├── Modules

├── Inventory

├── Power Grid

├── Damage State

└── Visual State

## Success Criteria

Players spend as much time building as fighting.

---

# Phase 5 — World Prototype

**Goal:** Make exploration worthwhile.

## Features

* Multiple star systems
* Warp gates
* Planets
* Stations
* Asteroid belts
* Nebulae
* Derelicts
* Friendly ships
* Traders
* Patrols

## Success Criteria

Travelling is entertaining without combat.

---

# Phase 6 — Research & Technology

**Goal:** Progress through discovery.

## Features

* Unknown artefacts
* Reverse engineering
* Research lab
* Manufacturing
* Faction technologies
* Prototype equipment

Technology is discovered.

Not purchased.

## Success Criteria

Players become excited about finding unknown objects.

---

# Phase 7 — Factions

## Features

* Pirate faction
* Corporate faction
* Ancient civilisation
* Organic civilisation

Each faction includes:

* Ship design
* Weapon style
* Behaviour
* Music
* Visual language
* Salvage
* Technology

Players should recognise a faction instantly.

---

# Phase 8 — Living Universe

## Features

* Dynamic patrols
* Traders
* Pirate raids
* Distress calls
* Wreck generation
* Environmental hazards
* Ancient events

The galaxy should continue existing without the player.

---

# Phase 9 — Story

Only once every previous system is enjoyable.

The story should guide players through existing systems, not compensate for weak gameplay.

---

# Phase 10 — Polish

The stage that separates a good game from a memorable one.

Focus on:

* Audio
* Music
* Lighting
* Particles
* UI
* Animations
* Engine trails
* Warp effects
* Planet landings
* Accessibility
* Performance

No major mechanics should be introduced here.

---

# Future Phase — Co-op

This phase only begins once the single-player game is genuinely fun.

## Design Philosophy

Friends don't join a lobby.

They enter your universe.

## Vision

* Drop-in / drop-out
* Bring your own ship
* Shared campaign
* Shared exploration
* Shared combat
* Independent inventories
* Independent ship progression

The host owns:

* World state
* Story progression
* NPC simulation

Each player owns:

* Ship
* Inventory
* Research
* Equipment

## Requirements Already Met

Because the game is built around ships rather than players:

* AI ships already exist
* Friendly ships already exist
* Escort missions already exist
* Fleets already exist

A friend's ship becomes just another ship in the universe.

Networking becomes an extension of the architecture rather than a rewrite.

---

# Technical Principles

Every new system should satisfy these rules.

## Rule 1

Nothing should reference "the player".

Everything references a Ship.

---

## Rule 2

Game logic should be separate from visuals.

Visual effects can change without affecting gameplay.

---

## Rule 3

Modules own behaviour.

Ships coordinate modules.

The world interacts with ships.

---

## Rule 4

The universe continues to simulate whether or not the player's ship is nearby.

---

## Rule 5

Features should compose rather than depend on one-off code.

For example:

* Tractor beam works on cargo, wreckage and mission items.
* Damage system works for player ships, enemies and stations.
* Power system works for every ship.
* Research works for every technology.

---

# Milestone Checklist

## Milestone 1

☐ Flying feels incredible

---

## Milestone 2

☐ Combat tells stories

---

## Milestone 3

☐ Salvaging is addictive

---

## Milestone 4

☐ Ship building creates attachment

---

## Milestone 5

☐ Exploration feels rewarding

---

## Milestone 6

☐ The universe feels alive

---

## Milestone 7

☐ The player forgets they're playing systems and starts telling stories.

---

# Definition of Success

We will know the game is succeeding when players stop saying:

> "I unlocked a better engine."

and start saying:

> "I ripped this engine off a pirate dreadnought after barely surviving the fight."

Or:

> "Look at my ship."

If players want to share screenshots of **their** ship because it reflects **their** journey, then we've achieved the vision.

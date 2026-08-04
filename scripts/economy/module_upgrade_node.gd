class_name ModuleUpgradeNode
extends Resource

## One node in a per-module-type upgrade tree (Phase 8.1). Data-driven
## replacement for the old ship-wide UpgradeNode — see ModuleUpgradeCatalog.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
## Which upgrade tree this node belongs to — matches ModuleUpgradeService.
## tree_key_for(module_type_id) (a ModuleType's hardpoint_category if it has
## one, otherwise its own id) so every tier of "weapon"/"missile" hardpoint
## shares one tree, while a non-hardpoint type like "engine" gets its own.
@export var tree_key: String = ""
## Material id / component id -> amount (same shape as ModuleType.build_costs).
@export var costs: Dictionary = {}
## Prerequisite node ids within this same tree that must already be unlocked
## on the instance before this one can be.
@export var requires: Array[String] = []
## ModuleType ids that must be present somewhere else on the ship's layout
## before this node can be unlocked (e.g. an Engine upgrade that needs a
## Reactor installed to draw enough power) — a deliberate cross-module gate,
## distinct from requires above.
@export var requires_ship_modules: Array[String] = []
## Stat name (a ModuleType field like "thrust_contribution", or a live
## hardpoint property like "projectile_damage") -> additive delta.
@export var modifiers: Dictionary = {}
## Short glyph drawn on the node's icon in place of real art (no upgrade icon
## art exists yet, same "placeholder" situation as MaterialType.icon/
## ComponentType.icon) — one or two characters, e.g. "II", "DMG".
@export var glyph: String = ""

# Space Game Prototype — Claude Instructions

## Communication style

Be extremely concise.

- Do not narrate routine file reads, searches or command execution.
- Do not explain obvious code changes unless asked.
- Before working, give at most one short sentence describing the action.
- After working, report only:
  1. what changed,
  2. whether verification passed,
  3. anything requiring my decision.
- Keep normal completion messages under 100 words.
- Do not provide lengthy summaries after each edit.
- Prefer acting over explaining.

## Project purpose

This is a Godot 4 top-down space exploration and combat game.

The immediate goal is not to build the complete game. The goal is to create a small, polished vertical slice with:

* satisfying spaceship movement;
* responsive combat;
* one explorable region;
* one enemy encounter;
* salvage collection;
* a basic modular ship-building system;
* a short upgrade loop.

The game may eventually become a genuine commercial indie project, so code should remain understandable and maintainable. However, avoid designing systems for hypothetical future requirements.

## Technology

* Engine: Godot 4
* Language: GDScript
* Rendering: 2D
* Version control: Git
* Do not introduce C#, third-party plugins, external frameworks or new dependencies without explicit permission.
* Use Godot 4 APIs only. Do not use outdated Godot 3 syntax.

## Working principles

1. Implement one small, testable feature at a time.
2. Inspect the existing project before making changes.
3. Prefer the simplest implementation that meets the current requirement.
4. Do not create speculative systems for features that have not been requested.
5. Preserve working behaviour unless the task explicitly changes it.
6. Do not delete or rename files without explaining why.
7. Do not perform large refactors while implementing an unrelated feature.
8. Run or validate the project after meaningful changes.
9. Read Godot errors and fix errors caused by your changes.
10. Clearly report anything that could not be tested.

## Before implementing a task

Before changing files:

1. Inspect the relevant scenes, scripts and resources.
2. Summarise the intended implementation briefly.
3. Identify which files will be created or changed.
4. Mention any meaningful architectural decision.
5. Ask for clarification only when ambiguity could substantially change the result.

For a small and obvious change, proceed without unnecessary discussion.

## After implementing a task

Report:

* what changed;
* which files changed;
* how the feature works;
* how it was tested;
* any known limitations;
* a suggested Git commit message.

Do not claim a feature works unless it was actually run, validated or otherwise tested.

## Architecture

Prefer composition over deep inheritance.

Use:

* scenes for reusable visual or behavioural objects;
* scripts for focused behaviour;
* custom Resources for reusable gameplay data;
* signals for communication between systems that should remain loosely coupled;
* clearly typed variables, parameters and return values.

Avoid:

* large manager scripts controlling unrelated systems;
* unnecessary global state;
* excessive Autoload singletons;
* hard-coded references to distant nodes;
* repeated gameplay values across different scripts;
* scripts that mix input, movement, combat, UI and persistence;
* creating a node for data that could be represented by a Resource or plain object.

Godot recommends deliberate scene organisation and distinguishes between scenes, scripts, nodes and data objects. Signals should be used where they reduce direct coupling between systems.

## Scene ownership

A scene should manage its own internal nodes.

External systems should interact through:

* a small public API;
* exported configuration;
* signals;
* shared data Resources where appropriate.

Avoid reaching deeply into another scene’s node hierarchy.

Prefer:

```gdscript
enemy.take_damage(10.0)
```

over:

```gdscript
enemy.get_node("Components/Health").current_health -= 10.0
```

## GDScript standards

Follow the official Godot GDScript style guide.

Use:

* `snake_case` for variables and functions;
* `PascalCase` for named classes;
* `SCREAMING_SNAKE_CASE` for constants;
* typed variables where practical;
* typed function parameters and return values;
* descriptive names;
* small functions with one clear responsibility;
* `@export` for values intended to be tuned in the editor;
* `@onready` only when a node reference genuinely depends on scene readiness.

Example:

```gdscript
@export var acceleration: float = 500.0
@export var maximum_speed: float = 350.0

func apply_thrust(delta: float) -> void:
    velocity += transform.x * acceleration * delta
    velocity = velocity.limit_length(maximum_speed)
```

Do not create comments that merely restate the code. Comment decisions, constraints and non-obvious behaviour.

## Script size

Keep scripts focused.

A script exceeding approximately 250 lines should prompt consideration of whether it contains multiple responsibilities. Do not split files purely to satisfy a line limit.

## Gameplay data

Gameplay values should not be duplicated or scattered through scripts.

Ship modules, weapons, enemies and upgrades should eventually use custom Resources or similarly data-driven definitions.

Examples of data that should remain configurable:

* damage;
* fire rate;
* projectile speed;
* health;
* mass;
* thrust;
* energy consumption;
* module cost;
* salvage value.

Do not build the entire data framework before it is needed. Introduce it when the first system genuinely benefits from it.

## Ship architecture

The ship should initially behave as one physics body.

Do not make every ship module an independent physics body unless explicitly requested.

The modular ship should eventually use one authoritative data representation containing information such as:

* module identifier;
* grid position;
* rotation;
* current condition;
* configuration data.

Visuals, statistics, saving and combat should read from the same authoritative ship data rather than maintaining separate conflicting representations.

## Input

Use named Godot Input Map actions.

Do not hard-code keyboard keys inside gameplay scripts.

Example actions may include:

* `move_forward`
* `move_backward`
* `turn_left`
* `turn_right`
* `fire_primary`
* `interact`

Input collection should remain separable from ship movement logic so AI-controlled and player-controlled ships can eventually share movement components.

## Physics

Use `_physics_process(delta)` for physics movement.

Use frame-rate-independent calculations.

Do not multiply values by `delta` more than once.

Choose deliberately between:

* `CharacterBody2D`;
* `RigidBody2D`;
* `Area2D`;
* `Node2D`.

Explain the choice when introducing a major gameplay object.

For the initial player ship, prioritise controllable and tunable movement over physically perfect simulation.

## Signals

Use signals for meaningful events such as:

* health changed;
* ship destroyed;
* weapon fired;
* salvage collected;
* module installed;
* target selected.

Do not use signals simply to avoid every direct method call. Local parent-child communication can remain direct where ownership is clear.

Prefer local signals over one enormous global event bus.

## Autoloads

Do not create an Autoload unless the system genuinely needs to exist across scenes.

Potential future Autoloads could include:

* save management;
* persistent game state;
* audio coordination;
* scene transitions.

The player ship, enemies, weapons and ordinary UI should not be Autoloads.

## File organisation

Use the following general structure when relevant:

```text
res://
├── art/
├── audio/
├── docs/
├── resources/
│   ├── modules/
│   ├── ships/
│   └── weapons/
├── scenes/
│   ├── enemies/
│   ├── player/
│   ├── ui/
│   └── world/
├── scripts/
└── project.godot
```

Keep scripts near their associated scenes when that makes ownership clearer. Do not create empty folders solely to satisfy this proposed structure.

Use clear filenames such as:

```text
player_ship.gd
player_ship.tscn
laser_projectile.gd
laser_projectile.tscn
ship_module_data.gd
```

Avoid vague names such as:

```text
manager.gd
controller.gd
utils.gd
thing.gd
```

unless the responsibility is genuinely clear from context.

## Git safety

Before substantial work:

* check the current Git status;
* identify unrelated uncommitted changes;
* avoid overwriting user changes.

Never run destructive Git commands without explicit permission.

Do not run:

```text
git reset --hard
git clean -fd
git checkout -- .
git restore .
```

unless explicitly instructed.

Do not commit automatically unless explicitly requested.

After completing a stable feature, suggest a concise commit message.

## MCP and editor usage

When MCP access is available:

* inspect the running Godot project before editing;
* use the editor to create or modify scenes when appropriate;
* validate scene paths and node names;
* run the project after meaningful changes;
* inspect the debugger and output for errors;
* avoid creating duplicate scenes or nodes when an appropriate one already exists.

MCP access does not justify making broad unrequested changes.

If MCP is unavailable, state that clearly and use direct file editing only where safe.

## Testing

Every gameplay feature should have clear acceptance criteria.

For example, player thrust is complete only when:

* the configured input accelerates the ship;
* maximum speed is respected;
* releasing input produces the intended inertia or deceleration;
* movement is frame-rate independent;
* the project runs without new errors.

Test the smallest relevant scene whenever possible.

Do not continue stacking features on top of known errors.

## Visual style

Until a final art direction is chosen, use coherent programmer art:

* simple geometric silhouettes;
* restrained particle effects;
* readable projectiles;
* clear enemy/player differentiation;
* consistent scale;
* uncluttered UI.

Do not download generated or third-party art without permission.

Prioritise readability and game feel over visual complexity.

### Texture import settings

Any texture that is actually drawn in the world must have
`mipmaps/generate=true` in its `.import` file. Module sprites are authored
far larger than the hex they are drawn into, and the hex renderers sample
with `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` — without a mip chain they alias
and shimmer.

Godot's default for a newly created `.import` is `false`, so the setting is
lost whenever a re-export deletes the `.import` files. After adding or
re-exporting any art, check and fix before doing anything else:

```bash
grep -rl "mipmaps/generate=false" resources/exports/   # must return nothing
sed -i 's|^mipmaps/generate=false$|mipmaps/generate=true|' <files>
```

Then reimport (`filesystem_manage(op="reimport", paths=[...])`) so the
change takes effect. See `docs/gotchas.md` for the full diagnosis.

This applies to rendered art only. `art/reference/`, `images_uploaded/`,
`docs/` and `icon.svg` are never drawn in-game and are deliberately left
alone — do not "fix" them.

## Scope control

The current priority order is:

1. Player ship movement
2. Camera behaviour
3. Basic weapon firing
4. One enemy
5. Health and destruction
6. Combat feedback and polish
7. Salvage collection
8. One upgrade interaction
9. Basic modular ship building
10. One short playable region

Do not introduce factions, dialogue systems, procedural galaxies, crafting trees, multiplayer or a full save system before the core loop is enjoyable.

## Definition of done

A feature is done when:

* it works in the running project;
* there are no new Godot errors;
* the implementation is understandable;
* relevant values can be tuned;
* it does not unnecessarily couple unrelated systems;
* its limitations are documented;
* the user has been told how to test it.

## Current task

Begin with a minimal player-flight prototype.

The first playable milestone should contain:

* a simple triangular placeholder ship;
* rotational control;
* forward thrust;
* acceleration and maximum speed;
* intentional inertia or drag;
* a following camera;
* an empty test environment;
* no weapons, enemies, inventory or ship-building yet.

Movement should feel responsive and enjoyable before additional systems are introduced.

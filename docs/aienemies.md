# AI Enemy Navigation

Implements roadmap item **"1.4 Better AI navigation"** (a user-supplied spec,
not part of `roadmap.md`/`Roadmap v.2-v.9.md`). Improves how existing pirate
archetypes move and fight — obstacle avoidance, stuck recovery, ship-ship
separation, combat-distance hysteresis, and a de-aggro leash — without
introducing any new archetypes (no miners/salvagers/escorts yet).

## Files

- `scripts/ships/ai/ai_navigator.gd` — `AINavigator extends RefCounted`. Owns
  all low-level movement concerns: obstacle/ship avoidance steering, stuck
  detection, and the recovery maneuver. One instance per `ShipAI`.
- `scenes/enemies/ship_ai.gd` — unchanged responsibility (the
  Idle/Suspicious/Alert combat state machine, target selection, firing), now
  delegating movement steering to `AINavigator` instead of turning straight
  at the target.

Split into two files deliberately: "how to move without getting stuck" and
"when to fight" are different concerns. `ship_ai.gd` stayed focused on the
state machine; `ai_navigator.gd` is the reusable movement layer.

## Steering model

Every physics frame, `ShipAI` asks `AINavigator.compute_desired_heading()`
for a single world-space angle to turn toward. That angle blends three
vectors:

1. **Seek** — normalized direction straight at the target (the player).
2. **Avoidance** — pushes away from asteroids/ships hit by a 5-ray fan cast
   from the ship's current heading (0°, ±30°, ±55°), weighted by how close
   each hit is. Probe range scales with the ship's own
   `get_layout_extent()`, so bigger hulls get a proportionally wider berth.
3. **Separation** — pushes away from other `"enemy_ship"`-group ships within
   a gap based on both ships' combined `get_layout_extent()`, so several
   pirates converging on the same target don't pack into each other.

The blended vector becomes a *target angle*, which is then:

- **Rate-limited** to `MAX_TARGET_ANGLE_RATE` (260°/s) before anything else —
  damps the raw signal itself, independent of how fast the ship can turn.
- **Smoothed** via `lerp_angle` at `HEADING_SMOOTHING_RATE` (6.0) into
  `_smoothed_heading`, which `ShipAI` then turns toward.

Weapon aim/fire gating is **not** affected by any of this — `ShipAI` still
checks the real angle/distance to the target for firing accuracy, so combat
behavior in open space (no obstacles nearby) is unchanged from before this
system existed.

### Why both a rate limiter and smoothing exist (two different bugs)

These were added in response to two distinct oscillation bugs found via live
testing, not designed upfront:

1. **Ambiguous dead-ahead avoidance.** An obstacle sitting almost directly on
   the path makes "steer away from the hit point" point nearly straight
   backward, with no reliable left/right signal. Recomputing a side choice
   from near-zero noise every frame flipped the direction randomly, and when
   the blended vector nearly canceled to zero, the old fallback snapped
   straight back to "aim at the target" — which immediately re-triggered
   avoidance, producing a fast seek/avoid loop that looked like the ship
   spinning in place. Fixed with:
   - A **sticky avoidance-side bias** (`_avoidance_bias_sign`): once the
     avoidance signal clearly favors a side (cross product above
     `AMBIGUOUS_LATERAL_EPS`), that side is remembered and reused whenever
     the signal later becomes ambiguous, instead of re-deciding from noise.
     Resets to "undecided" once no obstacle is being avoided at all.
   - **Holding heading through cancellation**: below
     `NEAR_CANCELLATION_THRESHOLD`, the target angle stays at the ship's
     current smoothed heading rather than snapping back to the target.
   - **Excluding the pursuit target from avoidance.** Since players and
     enemies share the `Ship` class, avoidance raycasts were also hitting
     the ship's own chase target once in combat range — fighting the seek
     force with the exact same ambiguous-dead-ahead problem, except aimed at
     the one thing the ship is trying to reach. `compute_desired_heading`
     and `compute_avoidance_vector` both take an `exclude_target: Node2D`
     parameter; `ShipAI` passes the player.

2. **Reactive feedback loop between close obstacles.** Even with the above
   fixed, weaving through several closely-spaced asteroids could still
   ping-pong the *target angle* between two different obstacles fast enough
   to look like jitter — the ship's current heading picks the ray
   directions, which picks the desired heading, which changes the heading
   next frame, and that loop isn't damped by how smoothly the ship *follows*
   a target if the target itself is swinging wildly. Fixed by rate-limiting
   the raw target angle (`MAX_TARGET_ANGLE_RATE`, set above every
   personality's own turn speed so it never limits a genuine deliberate
   turn) before it's fed into the heading smoothing.

## Stuck detection and recovery

`AINavigator.update_stuck_recovery(ship, delta)` is called first every
physics frame; while it returns `true`, `ShipAI` skips its normal state
logic entirely (the navigator has already driven thrust/turn that frame).

- `ShipAI` reports every nonzero thrust input via `note_movement_attempt()`.
- Every `STUCK_CHECK_INTERVAL` (0.5s), the navigator compares actual
  displacement against `STUCK_DISPLACEMENT_THRESHOLD` (18px). If the ship
  *tried* to move but didn't, a low-progress timer accumulates; two
  consecutive bad windows (`STUCK_TRIGGER_TIME`, 1.0s) triggers recovery.
- Recovery drives reverse thrust + a turn for `RECOVERY_DURATION` (1.1s),
  turning away from whatever the avoidance vector says is closest (or an
  arbitrary side if nothing registers) via `_pick_recovery_turn_direction`.

Verified directly (deterministic unit test via `game_eval`, not relying on
physics randomness): freezing position while forcing thrust input shows
`_low_progress_time` climbing every check interval, recovery firing at the
1.0s mark, `_recovery_timer` counting down over 1.1s, then resetting
cleanly.

## Combat state machine changes (`ship_ai.gd`)

- **Movement-intent hysteresis.** Approach/retreat/hold around
  `personality.keep_distance` now uses a `DISTANCE_HYSTERESIS` (40 units)
  band with sticky state (`MovementIntent` enum) instead of a single
  threshold — prevents thrust flipping every frame when hovering right at
  the boundary.
- **Leash / de-aggro.** ALERT was previously fully sticky (never reverted).
  Now `_update_leash()` reverts to IDLE if the target stays beyond
  `personality.detection_range * LEASH_RANGE_MULTIPLIER` (1.6x) for
  `LEASH_TIMEOUT` (2.5s) straight — a ship that lands one lucky hit and then
  loses the target for good no longer chases forever.

## What wasn't changed

- Detection/fire/keep-distance range *values* per personality (raider,
  gunship, missile boat, scout, sniper, rammer, corporate, ancient) were
  reviewed, not retuned — existing numbers already keep `fire_range <
  detection_range` and `keep_distance <= fire_range` sensibly across every
  archetype.
- No new archetypes (miners, salvagers, escorts) — explicitly out of scope
  per the spec.
- Weapon aim/fire accuracy logic — untouched, still based on the real
  angle/distance to target.

## Known limitations

- `STUCK_DISPLACEMENT_THRESHOLD` (18px/0.5s) is a fixed constant, not scaled
  to ship mass/thrust. Not an issue for any archetype tested so far
  (including the heaviest pirate hull), but worth revisiting if a much
  slower/heavier ship is added later.
- Live testing never observed stuck-recovery trigger from a *real* physics
  collision — every asteroid-crossing/wedge scenario tried resolved via
  avoidance steering alone. The recovery path is confirmed correct via a
  direct, deterministic unit test instead (see above), not an organic
  in-game reproduction.
- Avoidance/separation/leash constants (`AVOIDANCE_WEIGHT`,
  `SEPARATION_WEIGHT`, `LEASH_RANGE_MULTIPLIER`, etc.) are first-pass values
  confirmed to work, not tuned by feel in an extended playtest.
- Not re-verified specifically against the Dense/Dangerous Belt region (see
  `docs/region_design.md`), which has the tightest asteroid packing in the
  game.

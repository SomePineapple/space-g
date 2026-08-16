# Session Handover — Space Game Prototype

Purpose: bring a fresh chat up to speed without re-deriving context.
**Read `docs/direction.md` first.** A design review and the first human playtest
changed what the game is trying to be, and seven working systems were
deliberately switched off as a result (`docs/frozen_systems.md`) — so
`roadmap.md` and `Roadmap v.2-v.9.md` are now history rather than instructions
wherever the two disagree. Then read this, `CLAUDE.md`, `roadmap.md`, and
`Roadmap v.2-v.9.md`.
`vision.md` is longer-term aspirational material — only relevant if the user
explicitly brings it up. `docs/gotchas.md` has durable GDScript/Godot/MCP
gotchas pulled out of session history — check it before fighting a weird
engine/tooling behavior. **`docs/multiplayer.md` is required reading before
touching ship control, the player-ship lookup, randomness or object spawning**
— those four areas now have deliberate seams in them and it explains what is
and (mostly) is not prepared for multiplayer. **`docs/HUD-1d-Godot-spec.md`
plus `docs/hud-1d-reference.png` are the source of truth for the gameplay
HUD's appearance** — check them before restyling anything under
`scenes/ui/hud*`. **`docs/design_handoff_ship_builder/`,
`docs/design_handoff_upgrade_tree/` and `docs/design_handoff_scanner_radar/`
are likewise the source of truth for the ship-builder, module-upgrade and
scanner screens** — read the whole folder (README, LAYOUT_SPEC/STYLE_GUIDE
where present, and the JSON/HTML) before touching
`scenes/ui/ship_builder/`, `scenes/ui/upgrades/` or `scenes/ui/scanner_*`.
**`docs/design_handoff_grapple/` and `docs/design_handoff_controls_tutorial/`
are the same for the grapple line and the first-time control hints** — read
them before touching `scenes/player/salvage/` or `scenes/ui/tutorial/`.
**`docs/design_handoff_conduits/` governs the Conduit tile, the reactor's
grommet ring and how circuit runs are drawn** — read it before touching
`scripts/ships/layout/power_grid.gd`. Note that it and
`docs/spaceg-phase-4-spec-rev3.md` **contradict each other**: the spec's §4 and
§10 say power flows through plain hull and explicitly forbid reintroducing
"power conduits", and the handoff (which is newer, and which the user then
asked for) makes conduits the only conductor. The handoff won. One of the two
documents should be amended; neither has been.
**`docs/performance.md`
is required reading before writing or changing any `_draw()` loop, starfield
or particle emitter** — it records why the 2D canvas renderer's lack of
command batching dominated frame cost, how the starfield and hull renderers
were rebuilt around that, and how to measure before optimising.

**Read "Most recent session" first.** Sessions older than the two kept in
full below are compressed to short summaries — full narrative detail (exact
iteration steps, every dead end tried) has been trimmed since it's rarely
needed again; if you need it, it's in git history / this file's prior
versions. Design-reference docs (`docs/aienemies.md`, `docs/region_design.md`)
remain the source of truth for the systems they cover, not this file.

**How to read this file across the freeze.** The session logs below are a
*record of what happened*, and many of them describe systems that were
switched off afterwards — trading, crafting, credits, research, the upgrade
tree, asteroid mining — or rebuilt into something else (the Mining Grinder is
now the Salvager). They are history, not instructions, and are deliberately
left as written. **"Where things stand" is the only section that claims to
describe the game as it is now**; sections there that document a frozen
system are marked **FROZEN**. If a session log and that section disagree, the
session log is the old one.

## Most recent session (field-attach mounts, weapon wear made linear, and the Phase 4 power grid + conduits)

One long session in three parts. The third is much the biggest.

### Field attachment and mount quality

`ModuleInstance` gained `field_attached` / `ever_field_attached` and two
constants: `FIELD_MOUNT_EFFICIENCY` (0.5) while jury-rigged, and
`REFITTED_MOUNT_EFFICIENCY` (0.7) permanently thereafter, even once re-seated
at a dock. `efficiency()` is now `wear_efficiency() * mount_efficiency()` —
**two independent multiplicative factors, deliberately**, so a part's history
and its condition are separate numbers rather than one blended one.

The 0.7 ceiling was the user's call and is the point of the mechanic: bolting
a part on in the field is always possible and always costs you something
permanent, so waiting for a dock is a real trade against efficiency, mass,
thrust, turn rate and storage.

- `Inventory.return_owned_module()` is the single choke point for a part
  leaving a hull, and clears `field_attached` but never `ever_field_attached`.
- `ShipBuilderPanel.requires_home_base` is gone; `always_docked` is the
  override the scripted opening uses so the fitting-out isn't penalised.

### Weapon wear made linear (user correction)

DPS was splitting wear across damage and fire rate as a square root, which is
defensible and unreadable. The user's objection was that a player should be
able to look at a number and know what it means. Now `HardpointGun` has
`FIRE_RATE_WEAR_SHARE` (0.5): fire rate takes half the wear, and damage is
scaled by whatever is left so that **DPS falls exactly linearly with
efficiency**. Don't reintroduce a curve here without re-reading that exchange.

### The power grid (`docs/design_handoff_conduits/`, `docs/spaceg-phase-4-spec-rev3.md`)

New `scripts/ships/layout/power_grid.gd` (`PowerGrid extends RefCounted`) —
pure data, no nodes, no drawing, so the builder and anything later read the
same answer from the same place. `solve(layout)` returns routes, powered ids,
unpowered ids, reactor ids and per-edge wire segments.

**The load-bearing idea, and the one thing not to undo:** power and attachment
are measured over *different* graphs. Attachment is walked from the **core**
(`ShipLayout.find_unreachable_from_core`); power is walked from the
**reactors**. If everything conducted, "this gun has one power path" and "this
gun hangs on by one cell" would be the same sentence, and cutting that cell
would knock the gun into space rather than leave it dark and attached — which
is a mechanic the game already has. Prising the two apart is the whole point.

**Only the Conduit conducts** (`PowerGrid.CONDUCTING_TYPE_IDS`). This was a
mid-session correction from the user: plating conducting for free meant wiring
was never a decision, because a hull is made of plating by definition. Armour
is now inert, and reach costs hexes — a compact ship is cheap to power, a limb
needs a run out to it, and every cell of that run is a cell not spent on armour
and a thinner line to cut. New `conduit` module type in `ModuleCatalog`
(single-cell, mass 0.2, health 35, 4 Iron + 6 Copper): deliberately light
structure as well as wire, so a run is partial hull rather than a pure tax.

Two traps found while building it, both fixed by rewriting the rule rather
than patching the symptom:
- `_draws_power` was originally "isn't a conductor", which was the same test as
  "is a module" only while plating conducted. The moment it stopped, every hull
  plate reported itself as an unpowered consumer. It is now derived from what a
  part *does* (core, hardpoint, thrust, or charge capacity).
- A reactor carries `energy_capacity_contribution`, so it classed as something
  needing to be fed and drew a supply line to itself. Reactors are now excluded
  explicitly.

### Drawing the circuits (builder only)

`HexGridControl` draws two separate things: the hull's **own cabling**, always
on, and the **POWER PATHS** overlay behind a toggle. The cabling is four
stacked strokes per run (recessed channel, cable, clamp tick, pulsing
highlight), per the handoff.

**This is drawn on the build screen only.** An in-flight wire layer
(`HullWireLayer`) was built and then deleted at the user's request — at flight
zoom the cables were finer than the hull's own seams and read as speckle across
the plating. `ShipLayoutRenderer` carries a comment where it used to hook in,
so "the builder shows wires and the ship doesn't" doesn't read as an oversight.

**The geometry constants were measured off the art programmatically, not
eyeballed, and the two tiles genuinely disagree.** The reactor's grommet ring
clamps at reach 0.6765R with lanes ±0.1093R; the conduit's hub is a small
hexagon whose 18 holes sit on its own six edges at apothem 0.2462R with lanes
±0.0861R. A single shared lane constant — which is what the handoff's `CD_SLOT`
amounts to — cannot land in both rings. That is why a run is now **one straight
stroke from clamp to clamp** rather than two halves meeting at the shared edge:
each half was straight and they still kinked where they met.

Also here: circuits are fixed by what a part does (weapons red, propulsion and
the core green, utility blue) with no player assignment step; the lane
perpendicular is folded to `face % 3` so a colour keeps one physical side of
the ship across a seam (the art is painted to match); and wire endpoints ride
each plate's own jitter via the new `HullPaint.jittered_point`, because the
clamp is a hole painted on the plate.

### Conduit art, and a flight/builder split

`corporate_conduit.png` is an open junction box showing the hub and all 18
holes — right for the builder, wrong for a hull flying past at speed. So
`FactionArtImporter` gained a `_cover` layer that works exactly like `_lights`:
any `<base>_cover.png` is picked up automatically into
`ModuleType.faction_hex_cover_textures`, and `get_flight_hex_texture_for_cell()`
prefers it. `ShipLayoutRenderer` and `WreckageSpawner` ask for the flight plate;
the builder, the parts list and the hold keep the cutaway. No per-module code.

### Verified

Live, in the running game: the flight hull draws the cover and the builder the
cutaway; a hull forcing the hard case (reactor → two conduits, red/green/blue
sharing the first run, blue leaving at the first junction and green at the
second) draws cables that start in the correct coloured grommets, run parallel
and separate cleanly; the flight renderer's children are scar + glow only.
`scenes/prototypes/phase4_power_probe.gd`/`.tscn` is a **throwaway** probe for
the Phase 4 §6 bet — every shortcut in it is marked `CHEAT`.

### A tooling trap that cost real time twice

After deleting a `class_name` script, **the editor kept reporting parse errors
against lines that no longer contained the symbol** — `HullWireLayer` at
`ship_layout_renderer.gd:80/114/116`, long after the file was clean. A
filesystem scan, a reimport, and rewriting the file through the editor's own
API all failed to clear it; the stale copy is held in the editor's in-memory
`GDScript`, not in `.godot` (grep found nothing there). **The on-disk truth is
a headless run** (`--headless --quit-after`), which was clean throughout, and
the game itself came up live every time. If `project_run` reports `not_live`
with these errors attached, check `editor_state` before believing it — the
3-second helper window is often just too short, and the errors are noise.
Restarting the editor is the only thing that clears them. This belongs in
`docs/gotchas.md` and is not there yet.

### An unresolved art report

The user reported the new hexes shimmering in motion on the flying hull.
Ruled out with evidence: `mipmaps/generate=true` is set on all three new
`.import` files **and** the loaded textures were confirmed to carry real mip
chains at runtime; every hex-drawing surface sets
`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`; source edge antialiasing is identical
(~2px) across every export. The one structural oddity is that the three new
files are 666×768 where every other hex tile is 222×256.

`process/size_limit=256` was set on `corporate_conduit_cover.png.import` so the
flight tile imports at the house size (it is never drawn large — the builder
uses the cutaway). **The same limit was tried on the reactor and reverted**,
because an eight-frame sub-pixel sweep measuring per-pixel temporal variance
could not show the change helping: the conduit bands moved +1.2%, the reactor
−0.1%, and the control — untouched hull plates — moved +17.7%, which
invalidates the test. **So the shimmer is not fixed and the cause is not
established.** The standing hypothesis is content, not filtering: the cover
carries three saturated indicator dots and a hard bar that are sub-pixel at
flight scale. If so the in-architecture fix is to move those dots into a
`corporate_conduit_cover_lights.png` so `HullGlowLayer` blooms them instead —
the importer would pick it up with no code change — but that needs the art
re-authored and was not done.

## Session before that (first-time control hints, and three fixes to the opening)

### The control-hint panel (`docs/design_handoff_controls_tutorial/`)

New under `scenes/ui/tutorial/`: `control_hint.gd` (`ControlHint`, the panel),
`control_hint.tscn` (CanvasLayer 5) and `control_hint_cap.gd`
(`ControlHintCap`, one key-cap). Instanced in `intro_region.tscn`.
**The handoff folder is the source of truth for this screen.**

- **The handoff's open question is answered: one hint per control, raised at
  the moment that control first matters** — not a fixed opening sequence. The
  user's ask was a screen "only used when explaining a new feature and how to
  use it", so every hint carries its own id and is remembered individually.
- **Hints are given input *actions*, never keys.** The panel reads the live
  `InputMap` (`ControlHint.key_label`), so rebinding teaches the new key with
  no edit anywhere. Gamepad still shows the action name — the handoff flags
  controller glyphs as open.
- **`_enabled` and `_seen` are statics**, so they survive the region changes
  that rebuild every node. `set_enabled()` / `is_enabled()` / `reset_seen()` /
  `has_seen()` are the hooks for the pause-menu "tooltips" switch the user
  asked to tie in later. **Session-scoped: when a save file exists, these two
  are what it stores.**
- Layer 5 — above the HUD (1), below the full-screen menus (10), so the
  builder covering a flight-control hint is correct. The panel **never
  consumes input** (gameplay keeps running under it) and ignores presses made
  while a `menu_panel` is open, since ship control is suspended there anyway.
- Deviations, commented in-file: no backdrop blur (needs a screen-reading
  shader); progress dots only appear when a second hint is queued, because in
  the per-feature model there is no sequence to be partway through.
- **Sized to ~70% of the handoff's px and anchored 20/20 in the top-right.**
  That corner is only free because `Hud.CREDITS_FROZEN` hides the credits
  readout — **if credits come back, `TOP_MARGIN` has to drop below y 42.**

Triggers all live in `IntroDirector` (constants `HINT_*`), in play order:
move (builder closes) → boost (opening lines end) → salvage beam (salvage
proximity cue) → grapple (part comes free, `_begin_fitting`) → builder (part
reaches the hold, new `_prize_in_hold()`) → fire (part installed).

Verified live: labels resolve (W/A/S/D, SHIFT, G, L, B, SPACE), caps confirm
individually, 0.55s advance, queue + dots, SKIP click, dismissal, and the move
hint appearing in-region as the builder closes with gameplay live underneath.
**Not seen firing: the salvager/grapple/builder/fire triggers** — reaching them
needs the opening played through to the wreck.

One trap worth knowing when testing this: **key presses at the real keyboard
reach the panel**, so a hint can complete itself while you watch a scripted
run. Two "impossible" early completions turned out to be exactly that.

### Three fixes to the opening

1. **A completed cut now switches the Salvager off** (`HardpointSlicer._power_down`).
   `post_cut_hold` alone was not enough — the beam drew in, waited its beat and
   reached straight back out, because the switch was still on and the cursor was
   still on the wreck. Switching the system off (rather than latching the
   hardpoint) is what makes the stowed beam legible: SALVAGER goes dark on the
   systems panel, and G starts the next cut.
2. **Slicer-cut parts never age out.** `WreckageSpawner` calls
   `CapturedTechPart.make_permanent()` on a `clean_cut`; `DriftingHexPiece`
   treats `lifetime <= 0.0` as "never expires". This is deliberately the general
   rule, not a tutorial special case — a clean cut is already exempt from the
   capture roll, and letting the part evaporate 45s later breaks the same
   promise one step further on. Explosively recovered parts keep their timer.
   **Known cost: cut parts left lying around now persist for the session.**
3. **New `Ship.invulnerable`**, set on the salvage target by
   `Battleground._prepare_salvage_target`. Per-module `damage_immune` was never
   enough on its own: Health is a separate pool, so a wreck shot to zero dies
   and takes every part with it — which soft-locked a playtest when the prize
   was shot before it could be cut. The flag blocks `take_damage`,
   `take_damage_at` and `take_beam_damage`, and **deliberately not
   `take_slicer_cut`**, so the lesson still works.

Verified live: 150 damage across all three entry points left the target's
health at 305 unchanged; a scripted cut still severed the prize; the freed
piece came out with `lifetime 0` and survived being aged to 500s;
`_power_down()` flipped the real system off.

## Earlier session (grapple rebuilt as a simulated chain; hull light maps and glow; the three laser bolt sprites)

Several related art/feel passes. `docs/design_handoff_grapple/` is the source
of truth for the grapple, and `images_uploaded/Corporate Turret Lasers v2.dc
(1).html` for the bolts.

### Grapple (`docs/design_handoff_grapple/grapple-line-Godot-spec.md`)

The cosmetic `WinchRope` was replaced by a real verlet chain:
`scenes/player/salvage/grapple_rope.gd` (fixed 1/120s substep, one-sided
distance constraints, payout velocity inheritance, wrap-spiral pinning, load
transfer on the outermost wrapped link, body speed caps), `grapple_chain.gd`
(four stacked Line2D passes plus a shared-mesh MultiMesh for the links) and
`grapple_fx.gd`. `winch_rope.gd`/`.tscn` were deleted — nothing referenced them.

- **Control is press-to-toggle, not hold-to-reel** (user-requested): one press
  casts, the next winds in. `ShipIntent.winch_reel` was removed entirely;
  `fire_winch` is the only grapple field, and `HardpointBank.press_winch()`
  replaced `set_winch_reel_input`.
- The spec's `TENSION_SCALE = 22` does not fit this geometry — measured 5–7 on
  a free cast and 50–60 on a loaded haul, so it is 70 here.
- A hauled part stalls about three free rest-lengths short of the muzzle; the
  fix is a direct docking pull (`_draw_in`), not more reel.
- Two wedged-input bugs fixed: a freed-but-non-null rope read as live
  (`_forget_dead_rope`), and `stowed` only fired at the end of one particular
  reel (`_check_stowed`).

### Light maps, hull glow, and the Corporate art drop

- `FactionArtImporter.apply_hex_art(type, base, overlay)` now also loads
  `<base>_lights` (whole-plate and per-cell), so adding an emissive layer is
  dropping a file in. All 29 call sites in `ModuleCatalog` were converted.
- **Light layers inherit their hex geometry from the base layer.** Fitting each
  layer's radius from its own sparse content gave mk2 78 vs the base's 130 and
  mk3 two axes disagreeing 40.41 vs 68.29. Mismatched axes now hard-fail.
- **A hull's emissive layer cannot be brightened through mesh vertex colours:**
  Godot stores `ARRAY_COLOR` as 8-bit unorm, so anything over 1.0 clamps to
  white. Proven — gain 1.0/1.7/6.0 produced byte-identical frames. The glow is
  now its own child CanvasItem (`HullGlowLayer` + `hull_glow.gdshader`) driven
  by shader uniforms, which are not quantised, with an independent
  `glow_min`/`glow_max` and a per-hull random phase from `GameRng`.
- **A lamp only visibly dims when its level crosses below 1.0**, the glow
  threshold. The first pulse ran 1.53→3.4 — two identical whites on screen.
- **Measure perceptible brightness with channels clamped to 1.0.**
  `get_viewport().get_texture().get_image()` returns the HDR buffer, and raw
  luminance sums badly overstate what the eye sees.
- **`TAU` is built into Godot's shading language.** Declaring one is a
  redefinition error, and a canvas shader that fails to compile falls back
  silently to unlit drawing with no in-game sign. Grep `SHADER ERROR` as well
  as `SCRIPT ERROR`.
- 26 Corporate base plates replaced and 23 `_lights` added. All three region
  environments use additive glow — a bloom sweep done with Godot's default
  SOFTLIGHT blend is worthless.

### Laser bolts

`scenes/world/laser_bolt.gd` (`LaserBolt`) replaced the two flat additive
Polygon2D triangles in `projectile.tscn`. One greyscale texture per mark, tinted
by `modulate` (not quantised, so the HDR overflow survives into bloom), so a
captured pirate gun keeps firing pirate red. `LaserBolt.mark_for_tier` maps
weapon tier 1/2/3 to needle/twin/heavy, and textures load through the ordinary
faction-art path, so a pirate bolt is a drop-in file.

- **The node origin sits on each bolt's measured head core** (0.899 / 0.799 /
  0.833 of texture width — they differ). The old triangle led its origin by 17
  units, so bolts passed through targets before the hit registered.
- One shared px→unit scale for all three marks, so the art's own size
  progression survives without double-counting `TIER_PROJECTILE_SCALE_MULTIPLIER`.
  Measured lengths 34.0 / 50.8 / 81.6.
- Doc §1 (additive), §2 (spawn stretch + trailing copy, driven by `halo_color`)
  and §4 (flicker; the mk3 breathes on thickness instead) are implemented.
  **§5's per-bolt Light2D was deliberately skipped** — dozens are in flight in a
  fight, which is exactly the per-element cost `docs/performance.md` is about.

Also this session: the Slicer's beam now collapses on a completed cut
(`cut_retract_speed`, `post_cut_hold`) — the follow-up fix is in the session
above.

## Earlier session (scanner rebuilt as the directional A-scope from `docs/design_handoff_scanner_radar/`)

Short, single-purpose session. The user supplied a fourth design handoff and
asked for "the new scanner UI hooked up to the scanner system, still returning
the first n (depending on upgrades) results". **The handoff folder is the
source of truth for this screen, not this file.**

The handoff offers four presentations (1A cone, 1B grid, 1C B-scope, 1D
A-scope) of one shared scan model and says only one ships; **1D was
implemented**, as the README recommends. The other three were not built.

### The scan model replaced the channel-bar model

`scenes/player/scanner.gd` was rewritten. Gone: the 1.5s channel with a
progress fraction that resolved into a static list. Now:

- **Directional.** The beam has a world-space bearing (0° = +X, wrapped to
  ±180) and a width clamped 6°–120°. World rather than ship-relative on
  purpose — a snapshot has to stay put while the ship turns under it.
- **Time of flight.** `WAVEFRONT_SPEED` is a fixed 1000 u/s; `scan_range`
  (3000, was 3600) is MAXR and **is the upgradeable stat**. `cooldown` is 6s,
  so a full cycle is 9s. Firing is rejected silently while cooling down.
- **Contacts are snapshotted once, when the ping fires**, then emitted one at
  a time via `contact_resolved` as the wavefront reaches each range. Nothing
  is tracked live; letting markers follow moving objects would break the
  fiction the display represents.
- **`max_results` still caps the returns** (the user's "first n") — candidates
  are filtered to the beam, sorted nearest-first, then truncated. That
  ordering is what makes the cap mean "nearest n", so don't reorder it.
- Contact dicts gained `bearing` and `signature`. `Scanner.signature_of()`
  maps scan categories to the handoff's rock/ice/wreck plus a **`body`** type
  this project added for planets — the README explicitly invites extending the
  type table.
- `toggle_scan()` → `fire_ping()` (one call site, `ship.gd`). The old
  `scan_progress_updated` signal is gone.

Everything the old scanner did that wasn't about presentation survives
unchanged: the scannable/asteroid-cluster split, count-named clusters,
`already_known`, `mark_identified()` at fire time, and the self-cancel when
`has_scanner()` goes false mid-pulse.

### The instrument

Three new files under `scenes/ui/`:

- **`scanner_palette.gd`** — the handoff's 1D tokens (green accent, not the
  HUD's cyan — deliberately its own palette, not an alias of `HudPalette`),
  the signature colour/strength tables, geometry consts, `mono_font()` (same
  `SystemFont` approach as `BuilderTheme`, no font asset added) and stylebox
  factories.
- **`scanner_scope.gd`** (`ScannerScope`) — the 360×360 A-scope, a direct port
  of the handoff's `drawScope()`. **Horizontal axis is RANGE, not position.**
  Beam bar with amber edge handles, a 260-segment polyline trace redrawn every
  frame (noise scaled by distance + a Gaussian bump per return, σ widening
  with range), transmit line with gradient trail, and peak callouts that
  stagger upward 14px at a time when they'd collide. Owns the drag-to-aim
  only; everything around it belongs to the display.
- **`scanner_display.gd`** — rewritten as the column shell: header, scope
  frame, PING/`COOL 4.3s` button, `BEAM`/`GAIN` readouts, returns list, and
  the `?` help card (copy verbatim from the prototype).

Deviations, all commented in-file: the canvas `shadowBlur` phosphor glow is a
wide faint polyline under the sharp one; the rotated `↑ SIGNAL` caption is
stacked glyphs (rotating `draw_string` needs a canvas transform for two
words); `blipIn` is fade-only (animating position inside a container fights
the layout); the column got a backdrop the handoff doesn't have, because its
page background is a starfield in-game; range gridlines scale to keep ~6
labels instead of a fixed 500u step, which collides past ~6000 range.

### Decisions worth not relitigating

- **The panel is toggled, not always-on.** At 388×568 the column cannot share
  a 1152×648 HUD with the other widgets. **While open it covers the radar
  dial** — that is the known cost of the current placement.
- **V opens the panel and fires a ping in the same press.** Opening is local
  HUD input (`_unhandled_input`); firing still goes through
  `ShipIntent.toggle_scan` → `Ship` → `Scanner.fire_ping()`, so the
  multiplayer seam is intact. X or Escape closes.
- **Beam aim bypasses `ShipIntent`** — the HUD calls `scanner.set_beam()`
  directly, the same shape as the old display reaching for `get_scanner()`.
  A remote peer aiming would need an intent field. See `docs/multiplayer.md`.
- `already_known` contacts are dimmed rather than given a fifth column; the
  handoff's row is four columns wide.

### Verified / not verified

Verified live via `game_eval` and real screenshots, game log clean: trace,
peaks, staggered callouts, transmit line, help card, cooldown countdown and
recovery, the `max_results` cap (120° beam → exactly 5 rows), the empty case
(`NOISE ONLY — NO RETURN`), sensors-off cancelling a pulse and hiding the
panel, V opening the panel and firing in one press, and drag re-aim /
edge-resize / 6°–120° clamps.

Not verified: real mouse drag on the beam bar (handlers were called directly —
the documented MCP limitation), and no human has played it.

### Still open

- **No upgrade raises `scan_range` yet.** The `sensors` tree exists but
  `ShipUpgradeService` still authors no stat modifiers (see the section
  below), so `scan_range` / `max_results` remain plain exports. The handoff
  also asks whether upgrades should lower the noise floor or shorten the
  cooldown — undecided.
- No audio. The README notes an A-scope wants a transmit chirp and a
  per-return blip.
- 1A/1B/1C were not built and there is no option switch.

## Earlier session (ship builder + module upgrades rebuilt to their design handoffs; per-instance upgrade system deleted)

Two design handoffs implemented back to back, then a dead-code strip. Both
handoff folders are the source of truth for their screen's appearance — not
this file.

### Ship builder (`docs/design_handoff_ship_builder/`)

Full visual rebuild of `ShipBuilderPanel`; gameplay logic preserved. Three
scoping calls were made via `AskUserQuestion` and should not be relitigated:
real faction hex art in the module icons with the mock's gradient+glyph as
fallback, a static cell-count readout (no build-size dropdown — no such system
exists), and Research/Repair living in the selected row's expansion strip.

New under `scenes/ui/ship_builder/`: `builder_theme.gd` (every colour/metric
from the handoff plus StyleBox and font factories — monospace via `SystemFont`,
no font asset added), `module_presentation.gd` (category grouping/glyphs
derived from `ModuleType`'s own fields rather than a new field on every type),
`module_hex_icon.gd`, `module_list_view.gd`, `builder_stat_strip.gd`,
`builder_presets_card.gd`, `builder_backdrop.gd`. `hex_grid_control.gd` gained
the fading lattice, field glow, vignette, per-module glow, a dashed pulsing
placement preview and responsive cell sizing. `station_prompt.gd` gained
`class_name` + `PROMPT_TEXT` so the builder's status line reuses the string.

Known deviations, all commented in-file: Godot has no cheap `backdrop-filter`,
so cards are translucent-not-blurred; filter tabs are 10px not 10.5px or they
wrap to two rows in the 336px panel.

### Module upgrades (`docs/design_handoff_upgrade_tree/`)

**This one took three corrections to land — read the whole handoff folder
before touching it.** The first attempt kept the game's per-mounted-module
trees and only borrowed the visuals; the user's actual intent was the
handoff's own data model. The final shape:

- **The rail is the seven systems** (Hull, Propulsion, Weapons, Power,
  Storage, Sensors, Mining) and each owns **one ship-wide tree**. There are no
  per-module rows. Weapons is the 17-node tree with Laser/Missile/Rail branch
  hues and three merge nodes.
- **Content is `upgrade_data.json` copied to
  `res://resources/upgrades/upgrade_tree_data.json`** (verbatim apart from
  dropping `_schema`) — 7 categories, 89 nodes. Adding an upgrade is a data
  edit; nothing in code enumerates nodes.
- `ShipUpgradeCatalog` loads it and resolves the handoff's display-string costs
  ("8 Copper, 3 Wiring") against `MaterialCatalog`/`ComponentCatalog` by
  display name. Every name in the data currently resolves.
- `ShipUpgradeService` is the two predicates and nothing else —
  `is_unlocked` / `is_available`. `parents` is an AND list and arity 2+ *is*
  the merge mechanic; there is no separate flag.
- **Unlocks are ship-wide, stored by id per category in `GameState`**
  (`is_upgrade_unlocked`/`unlock_upgrade`/`get_unlocked_upgrades`, plus
  `last_upgrade_category`). Deliberately *not* part of `capture()`/`apply()`:
  those mirror one ship across a warp, whereas unlocks are player progression
  that outlives any hull.

UI under `scenes/ui/upgrades/`: `upgrade_palette.gd` (OKLCH→sRGB so the
handoff's hue-per-category tokens stay as numbers), `upgrade_tree_layout.gd`
(the polar fan — span allocation with mirroring, merge placement at
+0.4×STEP, label anchoring, frame measurement), `upgrade_tree_view.gd`
(drawing and hit-testing only), `upgrade_rail_list.gd`,
`upgrade_detail_panel.gd`. `upgrade_menu.gd` assembles them.

Two things worth knowing before editing the view:
- **The renderer reads only `UpgradeTreeLayout.entries`.** It used to keep its
  own node list too and crashed indexing a stale id when switching categories
  mid-frame. Don't reintroduce a second copy.
- **All trees share one fit scale** — `UpgradeMenu._shared_frame()` unions
  every tree's extent and passes it as the view's reference frame, so nodes
  don't resize when you switch system. Each tree still centres on its own
  extent.

### Dead-code strip

The per-`ModuleInstance` upgrade system (Phase 8.1) was superseded and is
**deleted**: `module_upgrade_catalog.gd`, `module_upgrade_node.gd`,
`module_upgrade_service.gd`, `module_upgrade_tree.gd`, and the long-orphaned
`upgrade_tree_lines.gd`. With them went `ModuleInstance`'s upgrade state
(`unlocked_upgrade_ids`, `get_stat_modifier`, `get_level`, …),
`ShipLayout._instance_stat_delta` and its six call sites,
`HardpointBank._apply_instance_upgrade_modifiers` and its four, and
`Ship.apply_instance_upgrade_effect`. Net −327 lines.

`ModuleInstance` survives as identity/provenance only — the owned-module pool
still needs it so removing and re-placing returns the *same* module.
`HardpointBank.apply_modifiers()` survives and is still used by the
manufacturer path.

### Verified / not verified

Verified live via `game_eval` and real screenshots: both screens render and
match their references; builder place/remove/validate/craft/filter/preset;
upgrade rail switching across all 7 trees, unlocking (costs actually spent),
merge REQUIRES ALL with unmet dots, progress roll-up, persistence across
close/reopen. After the strip: ship stats unchanged (mass 3.25, hp 435, thrust
500, cargo 60, max speed 153.8), 4 hardpoints mount and fire, builder
round-trips. Game log clean throughout.

Not verified: real mouse/keyboard input into either screen (handlers were
called directly — the documented MCP limitation), and no human has played it.

### Still open

- **No upgrade changes ship behaviour.** The handoff authors no stat
  modifiers, so unlocking spends resources and records the id and that is all.
  The user is writing the upgrade list and will hook effects up next. The
  wiring points are `ShipUpgradeService.unlock()` (apply the effect) and
  `HardpointBank.apply_modifiers()` (reach an already-spawned hardpoint
  without rebuilding it); `Ship._refresh_layout_stats()` re-derives aggregates
  without touching health or module condition.
- Node icons are 2-letter glyphs; the schema reserves an `icon` slot.
- `Missiles` as a separate player-facing category is gone — guns and launchers
  are both "Weapons" now.
- Editor-side `PlayerContext`/`GameRng` "not declared" parse errors appear in
  `logs_read(source="editor")` throughout and are pre-existing autoload reload
  artefacts; the *running game* log is the one that matters.

## Earlier session (gameplay HUD rebuilt to the "1d" visual spec)

The user supplied `docs/HUD-1d-Godot-spec.md` + `docs/hud-1d-reference.png`
and asked for the gameplay HUD to be rebuilt against them; **those two files,
not this one, govern HUD appearance.** Three scoping calls (full replacement
not side-by-side, flat tinted-glass dropdown not a blur shader, engine default
font for now) should not be relitigated.

Produced `HudPalette` (colours as float consts — GDScript `const` can't fold
`Color("rrggbb")`; **material dot colours deliberately excluded**, they come
from `MaterialCatalog.color()` so the HUD can't drift from the cargo/trade/
crafting panels), `VitalsReadout` (top-left, `_draw`-based dot+bar+number
rows), `CargoWidget` (bottom-left chip + upward-growing dropdown, subscribes
to `Inventory` itself so `hud.gd` doesn't relay cargo), and a restyled — not
rewritten — `RadarDisplay` (cyan, one faint ring per 1000 units of range so an
upgrade adds rings, trailing sweep wedge, ping pulses clocked off blip `age`).
`hud.gd`/`hud.tscn` lost the old background rect and four stacked labels.

Verified live against the reference. **The cargo chip's actual mouse click is
untested** — injected mouse events don't reach the viewport GUI in this MCP
environment (`gui_get_hovered_control()` returns null even over the chip);
handlers were called directly and a hit-test confirmed nothing occludes the
rect, but one real click is worth doing.

## Earlier session (code review + four-tranche refactor: bugs/perf, DRY, ship.gd decomposition, multiplayer foundations)

A user-requested four-part code review implemented as four tranches, all done
and verified live via `game_eval` (tranches 1–3 committed as `b9122c5`,
`5d09b49`, `cebcaea`). **No human has played any of it.**

- **Tranche 1 — bugs/perf**: destroyed engines no longer leave their thrust
  bonus behind and `max_speed` is re-derived; dictionary indexes on the
  catalogs and `ShipLayout`; cached extents/particles; throttled energy signal;
  winch rope leak.
- **Tranche 2 — DRY**: `DriftingHexPiece`, `ChargedHardpoint`, `BeamVisual`
  bases; `Health.damaged()` replaced four `_last_known_health` copies. Fixed
  the white hull flash re-triggering every frame during regrowth.
- **Tranche 3 — ship.gd 1449 → 779 lines**: four child components on
  `ship.tscn`, all delegated to and relayed for — `HullDamageModel`,
  `HardpointBank`, `WreckageSpawner`, `ShipEnergy`. The loot-drop split was
  deliberately deferred (its exports are overridden in nine scene files; the
  right home is a `LootTable` Resource).
- **Tranche 4 — multiplayer seams**: `ShipIntent` (commands as data, filtered
  by `Role` *on arrival* rather than trusting the sender), `PlayerContext`
  autoload (replaced twelve `get_nodes_in_group("player_ship")[0]` lookups),
  `GameRng` autoload (simulation randomness only — presentation stays on
  global `randf()`), `WorldSpawn`, and `GamePanel` as the base for the five
  gameplay menus. Two real bugs were found and fixed during its verification:
  a station that stopped submitting left its last order latched, and the
  lock-on indicator was destroyed the frame it spawned.

**`docs/multiplayer.md` is the authoritative record here, including a long
"what is still single-player-only" section. Do not infer readiness from the
seams existing.**

## Earlier session (Phase 8.1 Module Upgrades — SUPERSEDED, code deleted)

**Historical only. Almost nothing described here still exists** — the most
recent session replaced this system wholesale with the ship-wide upgrade trees
from `docs/design_handoff_upgrade_tree/`. Kept as a short note so a fresh agent
who meets a stale reference knows what it was.

It built per-`ModuleInstance` upgrades: each specific built module carried its
own `unlocked_upgrade_ids`, so removing and re-placing a module preserved what
had been bought on it. `ModuleUpgradeCatalog`/`ModuleUpgradeNode`/
`ModuleUpgradeService` held ~12 nodes across five `tree_key`s, applied in two
tiers (aggregate `ModuleType` fields summed by `ShipLayout`, plus live
hardpoint node properties pushed at spawn). A radial `ModuleUpgradeTree`
overlay opened from a `UpgradeMenu` category → mounted-instance drilldown.

All of that is deleted. **What survives from it and still matters:**
- `ModuleInstance` and `ModulePlacement.instance`/`ensure_instance()`, now
  identity and provenance only — the owned-module pool is
  `Dictionary[key] -> Array[ModuleInstance]` rather than counts, so a specific
  built module keeps its identity through Build → Place → Remove → re-Place,
  and `GameState` snapshots the real pool across warps.
- `HardpointBank.apply_modifiers()` — additive stat deltas onto an
  already-spawned hardpoint, skipping properties the node lacks. Still used by
  the `Manufacturer.stat_modifiers` path and the intended hook for ship-wide
  upgrade effects.
- The `toggle_upgrades` ("U") binding and the home-base gate on the screen.

Radar/Scanner were flagged then as unwireable for stat modifiers because they
have no per-placement spawned node (`Ship.has_radar()`/`has_scanner()` are
boolean flags). **That is still true** and still applies to the new system —
worth checking before authoring Sensors effects.

## Older session (Phase 5 Crafting & Construction Economy, then a fix-up pass)

Implements a user-supplied "Phase 5 — Crafting and Construction Economy" spec
across three back-to-back requests in the same session: 5.1 (crafting
framework), 5.2 (module construction costs), 5.3 (salvaging constructed
parts), then a fourth request ("fix the limitation") closing two gaps
explicitly flagged at the end of the 5.3 report.

- **5.1 Crafting framework**: new `MaterialCatalog.GLASS` (5th raw material
  — chosen over a glass-free substitute via `AskUserQuestion`; deliberately
  has no `VARIANT_PRIMARY_MATERIAL` of its own in `asteroid.gd`, so it's
  only ever the existing uniform-random "otherwise" pick every asteroid
  variant already rolls among `MaterialCatalog.ALL_IDS` — a source needed
  zero asteroid.gd changes). `scripts/economy/component_type.gd`/
  `component_catalog.gd` (6 components: Metal Sheets, Wiring, Circuit Board,
  Reinforced Steel, Motor, Canister — same static-catalog-prototype pattern
  as `MaterialCatalog`/`ModuleCatalog`) and `crafting_recipe.gd`/
  `crafting_catalog.gd` (one recipe per component, raw-materials-only
  inputs; `CraftingRecipe.input_components` exists for future
  component-on-component chains, unused by any of the 6 initial recipes).
  `Inventory` gained a component pool (`_component_totals`, shares cargo
  capacity with materials — `get_cargo_used()` sums both) and
  `can_craft()`/`craft()` (checked-then-atomic: inputs consumed exactly
  once, output produced exactly once, blocked up front if cargo lacks room
  for the output). New `scenes/ui/crafting_panel.gd`/`.tscn` (**K** key,
  wired into `map_tester.tscn`) — one row per recipe with live
  inputs→owned-output text, a quantity `SpinBox`, a Craft button disabled
  when unaffordable, and a status-label failure/success message.
- **5.2 Module construction costs — the session's biggest architectural
  shift.** Previously `ModuleType.build_costs` (raw materials) were spent
  directly at ship-builder placement time, with unlimited free placement as
  long as materials were on hand. Now placement itself is free; owning a
  module is the gate. `Inventory` gained a third pool
  (`_owned_module_totals`, keyed by `Inventory.owned_module_key(module_type_id,
  manufacturer_id)` — a new static helper shared by `ShipBuilderPanel`'s
  palette and `Ship`'s starter-loadout seeding so both always agree on the
  same key). Each palette row in `ShipBuilderPanel` split into two buttons:
  **Build** (spends `build_costs` — now interpreted as *construction* cost,
  materials and/or crafted components mixed via new `Inventory.has_items`/
  `spend_items`/`add_items` generic helpers — to craft one owned instance)
  and **Select/Place** (free, disabled until `owned > 0`, consumes one owned
  instance on placement). Removing a placed module returns it to owned
  stock, not a raw-material refund. Hull/Engine/Scanner/Storage build costs
  were rewritten to the spec's own component-based examples (e.g. Hull =
  2 Metal Sheets + 1 Reinforced Steel); every other module type's build
  cost was left as plain raw materials — not a scope the spec asked to
  rebalance. **Soft-lock avoidance**: `Ship._seed_starter_owned_modules()`
  grants one owned instance of every module type/manufacturer on the
  starter loadout on a fresh player ship's very first `_ready()` (gated on
  `GameState.has_snapshot()` being false, so a warp-gate scene reload never
  re-grants), in addition to what's already physically mounted — so
  stripping the starter ship down in the builder can never leave the player
  unable to rebuild it. `GameState` now also carries components and owned
  module counts across warp-gate scene changes (previously only materials/
  captured-tech/research/manufacturers survived a warp).
- **5.3 Salvaging constructed parts**: `Salvage` gained a `kind` (MATERIAL |
  COMPONENT) — a component drop carries `component_id`/`component_amount`
  instead of `material_id`/`material_amount`, colored/collected through the
  parallel component path (`Ship`/`Inventory` gained `try_add_component`/
  `add_component`, mirroring the material versions exactly). Asteroid
  mining/`HardpointGrinder` fragments never set `kind`, so they stay
  material-only by construction — components are deliberately combat/wreck
  -exclusive, the alternative route to crafting materials, not a mining
  bonus. `Ship` gained `component_drop_chance`/`rare_component_chance`
  exports (new `ComponentCatalog.COMMON_IDS`/`RARE_IDS` split the 6
  components by how many raw materials they need) so each kill-drop rolls
  material vs. component, then common vs. rare. **Damaged modules already
  existed** as `CapturedTechPart`/`Inventory._captured_tech_totals` (severed
  wings, chance-based, pre-Phase-5) but could previously only be spent via
  `research()` to permanently unlock a locked type — new
  `Inventory.get_repair_cost()`/`can_repair()`/`repair_module()` is a second
  way to spend one: half the module's build cost (materials/components,
  rounded up) converts one captured part into a real owned-and-placeable
  instance. New **Repair** button per capturable module type in
  `ShipBuilderPanel`, next to the existing Research button, showing live
  cost/count. A captured part is structurally never placeable on its own —
  only `repair_module()` ever adds to `_owned_module_totals` from that pool.
- **Fix-up pass** (separate follow-up request, same session): hand-tuned
  `component_drop_chance`/`rare_component_chance` per enemy archetype
  (Scout/Light pirates 0.15/0.15 → Med 0.3/0.25 → Heavy 0.45/0.35 →
  Missile Cruiser 0.55/0.45 with a bumped 3–5 drop count) directly as
  `.tscn` node property overrides — first time this project has hand-edited
  per-instance `Ship` export overrides in an enemy scene file (existing
  precedent was only `drops_salvage = false` on the derelict-station
  region's own player-ship instance). Also gave `abandoned_ship.tscn`,
  `distress_signal.tscn`, and 3 of `derelict_station.tscn`'s 9 salvage
  nodes explicit `kind = 1`/`component_id` overrides so wrecks concretely
  hand out components, not just material.
- **Process miss, not a new discovery: `docs/gotchas.md` already documented
  "`.tscn` files have no comment syntax... silently reverts that property to
  its default" before this session** — this agent added `#` comments to 6
  enemy `.tscn` files anyway, hit exactly that bug (a comment left the very
  next property line at its script default, e.g. `component_drop_chance`
  stuck at 0.3 despite the file text clearly showing `0.45`), and only
  caught it because every override was live-verified via `game_eval`
  afterward rather than trusted from the file text. Fixed by removing every
  `#` comment from the 6 files; wreck-scene edits (no comments used) were
  unaffected. **Lesson: check `docs/gotchas.md` before hand-editing a
  `.tscn`, per this file's own opening instructions — don't rediscover a
  documented gotcha live.**

### Still open from this session
- Recipe ratios (1 output per craft, first-pass material costs),
  construction-cost splits for the 4 rewritten module types, repair's
  "half cost rounded up" rule, and the new per-archetype drop chances are
  all first-pass numbers reached by design reasoning, not real playtest —
  none of Phase 5's economy has been played by a human yet.
- No crafting/building/repair UI icon art — `MaterialType.icon`/
  `ComponentType.icon` both exist as unused placeholder fields.
- Scanner's construction cost uses raw `MaterialCatalog.GLASS` directly for
  the spec's "suitable transparent... component" line item rather than a
  dedicated 7th component — a deliberate scope call, not an oversight, but
  worth revisiting if a real sensor/lens component is ever needed elsewhere.
- Manufacturer-flavored owned-module keys exist (`owned_module_key` takes a
  manufacturer_id) but `repair_module()` only ever produces the generic
  (no-manufacturer) key — a repaired part is always generic, matching
  `Inventory._captured_tech_totals` itself having no manufacturer axis.
- The CraftingPanel/toggle_crafting **K** keybind could not be exercised via
  simulated key input in this MCP session (confirmed a pre-existing,
  environment-wide limitation — the already-shipped Cargo panel's **C** key
  showed the identical non-response — not a regression); panel visibility,
  row rendering, and the underlying craft/build/place/remove logic were all
  verified directly via `game_eval` instead.
- Only `derelict_station.tscn` (3 of 9) and the two small POI wrecks got
  hand-authored component drops this session — `PirateCamp`'s pirates
  inherit their drop table from whichever base pirate `.tscn` they
  instance, not a camp-specific table.

## Earlier sessions (compressed)

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

- **Phase 4.2 Raw materials + mining/collection economy tuning:** replaced
  generic mined scrap with a resource-driven Iron/Copper/Nickel/Titanium set
  (`MaterialType`/`MaterialCatalog`, mirrors `ModuleType`/`ModuleCatalog`,
  chosen to fully replace rather than coexist with the old Steel Alloy/
  Electronics/Reactor Components via `AskUserQuestion`). Each asteroid
  variant rolls one primary material most of the time
  (`Asteroid.roll_ore_material()`); combat kills drop 2–3 independently
  rolled pieces; `MaterialType.yield_multiplier` (material scarcity) and
  `Salvage.amount_multiplier` (per-source yield) are two orthogonal knobs
  multiplied together. Two rounds of live-playtest-driven tuning: mining
  filled cargo far too fast (`HardpointGrinder.fragment_yield_multiplier`
  1.5→0.5) and salvage collection felt wrong, reworked into
  `Ship.get_core_global_position()`-gated self-collection (must reach the
  Command Core specifically, not just graze the hull) plus
  `HardpointTractorBeam` pulling to its own Muzzle instead of the ship's
  center. Verified live via `game_eval` throughout.

- **Ship-builder hex preview art + single-hex Mining Grinder rework:** three
  user-reported follow-ups to the Mining Grinder. Builder placement preview
  now renders the real module texture (`hex_grid_control.gd`'s
  `set_preview()`/`_draw_preview()`) instead of a flat color swatch, with
  the green/red valid/invalid tint as a semi-transparent overlay. Grinder
  footprint shrunk 2 hexes → 1 (`ModuleCatalog.SINGLE_CELL`). Beam exit
  point moved from hex face-centre to hex vertex, then corrected once after
  landing on the wrong vertex — final formula is muzzle-local **-90°** at
  `cell_size * 1.15` reach, verified live via `game_eval` against the
  starter ship's real grinder. Confirmed again: `game_eval` multi-statement
  scripts need tabs, not spaces, or `EVAL_COMPILE_ERROR` (see
  `docs/gotchas.md`).

- **Phase 4.1 Basic Mining Grinder:** first version of the grinder — a
  2-cell hex module (later shrunk to 1, see the session above), modeled on
  `HardpointTractorBeam` but **player-toggled** (`Ship.toggle_grinder()`/
  `is_grinder_active()`, **G**) rather than always-on, since continuous
  damage needs deliberate activation. While toggled on and an `Asteroid` is
  within `contact_range` of the Muzzle: drains energy, applies damage via
  plain `Asteroid.take_damage()` (not `take_damage_at()` — no knockback
  while held, see "Decisions made"), and breaks off one `Salvage` ore
  fragment on a fixed interval — real `Salvage` nodes, so the whole existing
  Tractor Beam/cargo-capacity pipeline applied with zero new code. Weapons
  deliberately not nerfed — the grinder's edge was continuous partial yield
  vs. a gun's kill-only drop (numbers were later retuned twice, see the two
  sessions above). New `toggle_grinder` input (**G**). Follow-up bug hunt in
  the same session: user reported the beam exiting the wrong hex face —
  turned out the beam itself was correct; the ship-builder's rotation-arrow
  formula was the real mismatch, and per explicit user request the arrow
  formula itself was left as-is (reverted after a brief "fix") since its
  "always point up by default" UX mattered more than hex-exact accuracy —
  see "Decisions made" for the standing rule. Verified live end-to-end via
  godot-ai MCP throughout.
- **Storage capacity + Storage module (Phase 3.2/3.3):** cargo capacity on
  `Inventory` (`get_cargo_capacity()`/`get_cargo_used()`, recomputed by
  `Ship._apply_layout_cargo_capacity()` from `base_cargo_capacity` (100) +
  layout total). Two collection paths kept deliberately separate:
  `add_material()` stays uncapped (refunds/debug cheat/`GameState` restore,
  must never fail), `try_add_material()` is the only capacity-checked path
  (real Salvage pickup), emitting `storage_full` on rejection. `Salvage.gd`
  rejects cleanly instead of consuming — stays alive overlapping the ship,
  retries pickup every frame until space frees. New "Cargo Container" module
  (`storage_mk1`, +60 capacity, plain stat contributor like Reactor/Battery,
  not a hardpoint category). Ship builder blocks removing a Storage module
  if current cargo would exceed the reduced capacity. New dedicated Cargo
  screen (**C** key, not home-base-gated) + HUD `Cargo: used/capacity` +
  transient "STORAGE FULL" flash. Starter ship gained one Cargo Container
  (now 160 total capacity). Real gotcha hit and documented: editing a
  `.tres` on disk while the editor runs gets silently reverted by
  `project_run`'s default `autosave=true`. Verified live via MCP; ship-
  builder removal-block/stats-readout were code-reviewed only, not clicked
  through the actual UI.
- **Tractor Beam + Radar/Scanner as hex modules (Phase 3.1):** moved the
  always-on `TractorBeam` off `ship.tscn` onto a real hex module
  (`tractor_beam_hardpoint`, `scenes/player/hardpoint_tractor_beam.gd`) —
  after two explicit pivots (player-held single-key version reverted to
  always-on; multi-target-at-once narrowed to exactly one target,
  "upgradable later") landed on: always active while mounted/intact, single
  nearest valid target (`Salvage`/`CapturedTechPart`) in range with clear
  line of sight, drops safely if blocked/out of range/energy. Radar and
  Scanner got the same treatment but as a **"pure capability flag"**
  instead (no spawned node — `Ship.has_radar()`/`has_scanner()` just check
  for an intact hardpoint of that category; `radar_hardpoint`/
  `scanner_hardpoint`, HUD hides live on loss/repair). Radar recolored green
  (was too close to Engine/Tractor's blues), Scanner given magenta. Starter
  ship gained one of each. Two real bugs fixed: a freed-instance-into-typed-
  parameter crash (fix: `is_instance_valid()` inline at the call site, not
  inside a helper — this pattern recurs, see `HardpointGrinder`/
  `HardpointTractorBeam`), and a `.tres`-outside-an-open-scene stale-cache
  issue (now in `docs/gotchas.md`). Verified live throughout.
- **Points of Interest (Phase 2.3):** implements a user-supplied "Phase 2 —
  Information and Discovery / 2.3 Basic points of interest" spec, built
  entirely from existing systems (no new framework). Four hand-placed types
  in `map_tester.tscn`: **Small Pirate Camp** (`scripts/world/poi_camp.gd`,
  radar `"enemy_camp"`, clears once all pirates die — combat/reward needed
  zero new code, reusing existing idle-AI/salvage-drop behavior), **Distress
  Signal** (`distress_signal.gd`/`.tscn`, radar `"distress_beacon"`, clears
  once its child Salvage is collected), **Abandoned Ship** (`scannable.gd`,
  `"Wreck"` category, reused hull/cockpit art tinted/scaled), **Scenic
  Formation** (`scannable.gd`, `"Ancient Formation"`, discovery-only, no
  reward). "Wrecks"/"Abandoned ships" spec bullets were deliberately merged
  into one type; "Simple derelict structures" wasn't built as a separate
  fifth (would have been pure duplication) — confirmed via
  `AskUserQuestion` first. Every POI stayed strictly on one side of the
  Radar/Scanner boundary rule (camp/distress = radar-only, wreck/formation =
  scanner-only). Not a data-driven spawner — four hand-placed instances
  didn't justify one. Verified live (group membership, kill-clears-camp,
  collect-clears-beacon, real Scanner pulses against both scannables).

Newest first. Full narrative/iteration detail for these lives in git history;
what's below is what still matters for picking related work back up.

- **Scanner (Phase 2.2) + a radar rework:** implements a user-supplied
  "Phase 2.2 Scanner" spec. Went through several live pivots: single-target
  identify-scan → long-range list scan (one press, 1.5s channel, closest-5
  results — the current shape; a "player writes their own guess"
  memory/journal alternative was explicitly deferred, not built);
  Common/Dense/Rare asteroid composition → count-based clusters ("Asteroid
  Cluster (6)"), proximity-grouped; briefly added then reverted both a
  scannable home station and asteroid-cluster radar blips, establishing the
  **hard Radar/Scanner boundary rule** (radar = live faction/activity,
  short-range; Scanner = off-the-grid identification, long-range) — Radar
  pulled down to 1800, Scanner pushed out to 3600, the reverse of their
  original launch numbers (don't revert without checking). New
  `scripts/world/scannable.gd` (generic duck-typed component — reused again
  by the POI session below and by the later hex-module session).
  `scenes/player/scanner.gd` (`Scanner extends Node2D`) originally shipped
  as a fixed `ship.tscn` child, same as `TractorBeam` at the time — both
  were later turned into hex modules, see the most recent session. Verified
  live throughout, no errors.
- **Radar (Phase 2.1 broad-detection sweep display):** implements a
  user-supplied "Phase 2.1 Radar" spec. New `scenes/ui/radar_display.gd`
  (`extends Control`), child of the always-on HUD `CanvasLayer`, built
  procedurally in `_ready()`. Detection reuses existing groups —
  `"enemy_ship"` → SHIP, `"home_base"` → STATION, plus three categories
  (`"electronic_signal"`/`"enemy_camp"`/`"distress_beacon"`) that were wired
  from day one but had **no live instances until the POI session above**
  finally populated `"enemy_camp"`/`"distress_beacon"`; `"electronic_signal"`
  still has none. Broad-category-only by design — a contact is
  `{offset, category}`, no name/faction/health/identity. Reworked mid-session
  into a classic sweep-reveal model: contacts only become visible "blips"
  once the rotating sweep line crosses their bearing, then fade over time;
  blips are matched to contacts by category + proximity, not node identity.
  Range/position/category set were **all later changed by the Scanner
  session** — see that section above for current numbers, this entry is
  mostly useful for the sweep-reveal mechanic itself. Verified live
  (spawned a pirate, confirmed blip-on-sweep-pass, fade, and removal on
  death). One MCP-tooling detour (frozen-looking live value from an editor
  debugger "break" state) — see `docs/gotchas.md`.
- **Better AI navigation** (obstacle/ship avoidance, stuck recovery,
  combat-distance hysteresis, de-aggro leash): implements a user-supplied
  "1.4 Better AI navigation" spec, full design reference in
  `docs/aienemies.md`. New `scripts/ships/ai/ai_navigator.gd`
  (`AINavigator extends RefCounted`, one per `ShipAI`) blends seek-target
  with a 5-ray obstacle-avoidance fan and ship-separation, fixing three real
  oscillation bugs found via live testing (dead-ahead jitter, ships dodging
  their own pursuit target, reactive ping-pong through tight asteroid
  clusters — the last one was the actual reported symptom). Also added
  stuck detection/recovery (thrust-vs-displacement tracking, reverse-and-turn
  maneuver) and movement-distance hysteresis + a de-aggro leash in
  `ship_ai.gd`. Verified live across several real scenarios, no new errors.
  Still open: stuck-recovery threshold is a fixed constant not scaled to
  ship mass; constants are first-pass; not re-verified against the
  Dense/Dangerous Belt region; `pirate_light_two`/`pirate_heavy_one`
  severability audit remains untouched.
- **Basic world regions** (`scripts/world/region_type.gd` +
  `region_spawner.gd`, full reference in `docs/region_design.md`): data-driven
  `RegionType` resource (density/spacing/size-tier weights/tint) +
  `RegionSpawner` node, applied to `asteroid_field.tscn` (refactored from 14
  hand-placed asteroids) and 3 new zones in `map_tester.tscn` (Sparse Open
  Space, Small Asteroid Cluster, Dense/Dangerous Belt). Density values were
  tuned down once after user feedback ("way too many asteroids") — current
  numbers are the approved second pass, don't revert to first-guess values.
  Scope was explicitly narrowed from a full grid-addressed universe (the
  user's own framing) to this handcrafted-zone approach via `AskUserQuestion`
  — the grid idea is unstarted, not rejected, and is a materially bigger
  architecture change if picked up later. Verified live (determinism, counts,
  clearance around arrival points).
- **Asteroid size tiers, splitting, hit knockback**
  (`scenes/world/asteroid.gd`): 3 size tiers (LARGE/MEDIUM/SMALL) with
  splitting into next-tier fragments on death, 4 visual variants auto-picked
  from `random_seed`, deterministic RNG (same seed → same shape/split
  result), optional `drift_velocity`, and `take_damage_at()` knockback
  reusing the split-scatter mechanism. Asteroids remain `StaticBody2D` — no
  real physics collision response. Verified live. Committed together with
  the region/camera/nebula/wreck work below (one combined commit, user's
  explicit choice).
- **Camera zoom rework + starfield tiling/perf fixes**
  (`camera_shake.gd`/`starfield_layer.gd`): ship-size-driven zoom widened
  50%, scroll-wheel zoom added (zoom-out capped at the ship's own
  `_base_zoom`, zoom-in capped by a flat `scroll_max_zoom`). Starfield
  `field_size`/`star_count` retuned to fix pop-in on large-ship zoom-out
  without the earlier attempt's severe perf hit; still an accepted edge-case
  gap at the most extreme zoom-out on wide monitors. Small-screen star
  flicker addressed with a size-floor bump only (antialiasing was tried,
  reverted — caused a frame-rate regression); not confirmed with the user
  whether that alone fixed it. **This session's changes were not verified
  live in the editor** — flagged to the user at the time.
- **3 more abandoned-station wrecks + a second nebula**
  (`derelict_station.tscn`, `map_tester.tscn`): added pirate/ancient/
  corporate faction station wrecks (same mipmap-generate=false fix as the
  original faction art). Second nebula placed far from the first with its
  own teal tint — the particle cloud itself is still visually identical
  between the two (only tint differs), a known simplification. Verified live.
- **Frame stutter fix** (`tractor_beam.gd`/`warp_gate.gd`): diagnosed a
  reported ~0.5s (actually multi-second, up to ~8.4s) stutter to fresh
  `CanvasItemMaterial`/`ParticleProcessMaterial` allocation on every
  use forcing shader/pipeline recompiles — fixed by caching both as
  `static var`s. See `docs/gotchas.md` for the general lesson. Verified live
  (before/after spike-monitor instrumentation).
- **Version 0.6 (trading, station, warp gates, new locations, nebula)** — a
  large multi-part session, roadmap Version 0.6 now essentially complete:
  - Trading: new `int` Credits currency on `Inventory`, `trade_panel.gd`
    (bound to `T`), `sell_price`/`buy_price` per material (buy always >
    sell).
  - Station: `station.tscn` real visual (was a bare `Marker2D`), always-on
    `station_prompt.gd` prompt, and a real repair mechanic — passive regen
    caps at `passive_repair_cap_fraction` (0.4), paid `Ship.repair_fully()`
    tops everything to 100%.
  - Warp Gates (`warp_gate.gd`): `GATE` mode (instant scene change via a new
    `GameState` autoload carrying Credits/materials/tech/layout/health-
    fraction across scene changes — **per-module condition does not survive
    a warp**, only aggregate Health) and `SPEED_LANE` mode (in-scene dash,
    2.5s ramping camera-shake hold then a fixed-speed 1600px/s dash). Both
    modes are always built in pairs (retrofitted after an early one-way gate
    had no way back).
  - New Locations: `asteroid_field.tscn` (14 dense asteroids),
    `derelict_station.tscn` (darkened/tilted station + salvage, no
    trade/build panels).
  - Nebula (`nebula.gd`): drifting particle cloud + screen tint zone;
    `Ship.is_in_nebula()` (depth-counter) cuts target-lock range to 35%
    inside. Sizing went through a real correction (see `docs/gotchas.md`-
    adjacent lesson: particle *scale* shouldn't track field radius).
  - `RegionBoundary` (the old distance cap around home base) removed
    entirely per explicit request, since the nebula needed to sit outside it.
  - Real bugs found via live testing: a signal-handler arg-count mismatch in
    `trade_panel.gd`; the `GameState` autoload typing bug (now in
    `docs/gotchas.md`); a missing background image layer on 3 new scenes
    causing flat grey backgrounds.
  - Verified live end-to-end for all pieces above.
  - Still open: per-module condition doesn't survive a `GATE` warp
    (accepted); "abandoned wrecks" as a distinct non-station location isn't
    built (now partially addressed by the POI session's Abandoned Ship, but
    the original derelict_station "wrecks" are still station-shaped, not
    ship-shaped); a user-reported performance concern was investigated
    (`fps`/`process`/`node_count`) but inconclusive at the time (later
    resolved by the frame-stutter session above).
- **Reverse engineering, pirate_light_one's wing, debris/thruster fixes,
  Manufacturers** (Roadmap Version 0.5):
  - Reverse engineering: `ModuleType.requires_research` flags only Railgun
    and Phase Lance (not every capturable-tech module, chosen via
    `AskUserQuestion`); `Inventory.research()` spends one captured part to
    permanently unlock a module type; ship builder shows `[LOCKED]` +
    a live Research button.
  - Gave `pirate_light_one` a real severable wing (relocated an engine +
    added a single connecting Strut) — it previously had zero severable
    points by construction. `pirate_light_two`/`pirate_heavy_one` are
    **not** audited for the same issue.
  - Two real bugs fixed: severed-module debris always rendered with the
    generic fallback texture instead of actual faction/rotation-correct art;
    engine thruster particles kept showing on a destroyed engine regardless
    of that specific module's state.
  - Manufacturers (`scripts/economy/manufacturer.gd`/`manufacturer_catalog.gd`):
    stat-modifier profiles (Atlas Heavy Industries / Nova Precision / Black
    Market Foundry) keyed by `ModulePlacement.manufacturer_id`, deliberately
    orthogonal to faction — see "Decisions made" below. Black Market
    Foundry's malfunction-backfire is a real mechanic
    (`Ship.damage_own_module()`). Discovery (via capture) is tracked
    separately from research/unlock. Buying from a known manufacturer has no
    UI yet — waits on the trading system (built in the Version 0.6 session
    above). Verified live end-to-end.
  - Still open: no Corporate/Ancient enemy ship exists (explicitly deferred
    by the user); no faction-specific salvage; Atlas Heavy/Nova Precision
    have no in-game seed yet (only Black Market Foundry was placed on a real
    enemy).
- **Mipmap fix, capturable tech parts, disabled winch grapple**:
  - Fixed the same `mipmaps/generate=false` issue (see `docs/gotchas.md`)
    across all 61 newer faction-art assets.
  - New capturable-tech-parts system: a severed module that's flagged
    `is_capturable_tech`, survived severance with enough condition, and
    passes a capture-chance roll spawns a `CapturedTechPart` instead of
    cosmetic debris, added to a new `Inventory` bucket (research/unlock came
    later, see Manufacturers session above).
  - Built a full player-driven winch grapple (`hardpoint_winch.gd`/
    `winch_rope.gd` — verlet rope, real tether cap, grapple via
    `Ship.apply_impulse`) through several real bug fixes (miss auto-retract,
    frozen anchor, tether cap, dead tip point), then **disabled per explicit
    user request** ("good work in progress... let's disable the idea for
    now") — only the `ModuleCatalog` registration is commented out, every
    supporting file is left in place to pick back up later.
  - Restored `CapturedTechPart` pickup via the existing `TractorBeam` once
    the winch was disabled, so captured parts remain collectible.
  - Still open: winch balance untuned (irrelevant while disabled); no UI
    shows captured-tech counts yet.
- **Faction weapon art + recoil**:
  - Turret art now renders on the actual gun (`HardpointGun`'s `Turret`
    sprite, rotated/scaled to the `Muzzle` marker), replacing an earlier
    hull-overlay approach (still used only by the ship-builder preview).
  - Multi-hex weapon tiers (II/III) use one PNG per occupied hex
    (`<faction>_<name>_<q>_<r>.png`), not one stretched image — fixes a
    margin/stretching visual bug. `HexUtils.hex_uv_corners_for_rotation()`
    keeps per-cell art aligned when a multi-hex weapon rotates.
  - Fixed a real bug: `personality_user.tres` was missing `faction_id`
    entirely, silently falling back to `"pirate"` hex art.
  - Recoil wasn't actually broken — ship drag was cancelling it within one
    physics frame. `recoil_force` bumped 6x across all weapon tiers per
    explicit request. Noted: recoil is inherently inversely proportional to
    ship mass — intentional.
  - Ancient and Pirates given full weapon art (base + turret, all 3 tiers)
    to match Corporate — no code changes needed, `FactionArtImporter` is
    faction-agnostic.

## Where things stand

**This section describes the game after the Phase 0 freeze and the Phase 1
work that followed. `docs/direction.md` is the authority; where anything
below disagrees with it, it is wrong and should be fixed.** The subsections
further down still document frozen systems in full detail — that is
deliberate (the code is all still in the repo and Phase 5 decides what
returns), but each is now marked, and a **FROZEN** subsection describes
something the player currently cannot reach.

### The loop as it actually is

Killing things is the only source of anything. A fight leaves a wreck; the
Salvager cuts a specific part off it; the Winch reels that part in; it goes
into a hold of named objects; the ship builder bolts that same object onto
the hull. That is the whole economy — there is no currency, no market, no
crafting chain, and no research. Six of the seven Phase 0 freezes are what
removed the alternatives, and they are not to be flipped back to unblock a
task (`docs/direction.md` §3).

Underneath that loop, unchanged by the freeze and still current: flight
movement, camera, asteroids, bounded data-driven regions with a home base,
a 4-archetype pirate AI (Raider/Gunship/Missile Boat/Scout) with an
Idle→Suspicious→Alert state machine, per-module hex damage with wing
severance, a sweep-reveal radar paired with the directional A-scope scanner,
four points of interest, a single-target tractor beam, and the scripted
opening in `intro_region.tscn`.

### Phase 1 — where it got to

`docs/direction.md` §4 lists six steps. Five are done:

1. **Part instances — done.** `ModuleInstance` carries `instance_id`,
   nickname/serial, origin faction + description, `kill_count`,
   `condition_fraction`, `integrity`, `worst_condition_fraction`,
   `field_attached`/`ever_field_attached` and `damage_immune`. Still pure
   exported-primitive data, per the multiplayer rule.
2. **Condition on the instance — done.** `HullDamageModel` converts to and
   from absolute points at the boundary and is the only writer while a part
   is mounted; condition survives a refit, a warp and the ship builder.
3. **Wrecks persist — NOT done.** This is the one open step, and the biggest
   gap in the plan. Slicer-cut parts no longer age out
   (`CapturedTechPart.make_permanent()`), but the hulls themselves still go
   away; persistent hulks are Phase 2.1 work that has not started.
4. **Cutting — done.** `HardpointSlicer` ("Salvager"), a real 3.6s cut on a
   part already damaged below `HullPaint.CUTTABLE_CONDITION` (0.30).
5. **Cargo triage — done.** `ShipHold` (`scripts/ships/hold/ship_hold.gd`) is
   a hold of named objects in bays, drawn with the parts' real hex art.
6. **Mount it — done.** The builder places the exact recovered object, wear
   and history intact.

Built on top of Phase 1 since:

- **Visible damage.** `HullScarLayer`/`HullScarPattern` draw append-only scar
  tiers onto the plating from `worst_condition_fraction`, so a breach is
  permanent even after the part is repaired.
- **Field attachment.** A part can be bolted on anywhere, but away from a
  dock it is jury-rigged: `ModuleInstance.FIELD_MOUNT_EFFICIENCY` (0.5) while
  field-rigged, and `REFITTED_MOUNT_EFFICIENCY` (0.7) permanently thereafter
  even once re-seated at a station. Stacks on top of wear rather than
  replacing it.
- **A power grid that is drawn but not yet wired to anything** — see its own
  subsection below before assuming it does something.

### The power grid (conduits) — **COSMETIC ONLY, nothing reads it**

This is the most likely thing in the repo to be mistaken for a working system.
It is modelled, drawn and reported on, and **no gameplay depends on it.**

- `PowerGrid.solve()` is called from exactly three places, all off to one side:
  `HexGridControl` (draws the cables and the POWER PATHS overlay),
  `ShipBuilderPanel._on_power_toggled` (the overlay's status line), and the
  throwaway probe scene. `Ship`, `HullDamageModel` and `HardpointBank` never
  mention it. **A gun wired to nothing still fires at full rate.**
- The one gameplay hook that exists is inert by design.
  `HullPaint.is_cuttable()` makes an unpowered part cuttable at any condition —
  the actual Phase 4 bet, "cut the supply line and take a 95% gun instead of
  shooting it down to 12%". But `ModuleInstance.powered` defaults to `true` and
  only `scenes/prototypes/phase4_power_probe.gd` ever writes `false`, so the
  branch never fires in the shipped game. It is marked in-file as a prototype
  seam; that is deliberate, not an unfinished edit.
- **There are two disagreeing notions of "power" in the codebase.** The live
  one is `ShipLayout.total_energy_generation()`: a single pool summing every
  reactor, scaled per part by `_core_distance_energy_multiplier` — distance
  from the **core**. That is what feeds the HUD and energy regen today.
  `PowerGrid` measures connectivity to a **reactor**. Making power load-bearing
  means reconciling these, not just calling `solve()` in flight.
- **No authored layout contains a conduit.** Zero references across all 17
  files in `resources/ships/`, and conduits are now the only conductor, so only
  parts bolted directly onto a reactor cell are fed. An earlier count this
  session put it at 58 of 91 consumers dark (worst: `warlord` 7/9; `lancer` and
  `fang` entirely; `bastion` 6/8), and the starter hull reads 1/1 dark.
  **Turning power on today would leave almost every ship in the game inert.**
  Authoring conduit runs is the larger half of this job.

### What no longer exists (don't go looking for it)

- **The Mining Grinder module is gone.** It became the Salvager — same art
  (`mining_grinder` sprite), a cutting tool instead of a rock-breaker. There
  is no `HardpointGrinder` class any more, which means
  `docs/frozen_systems.md`'s `HardpointGrinder.ORE_OUTPUT_FROZEN` row and the
  matching row in `docs/direction.md` §3 both name a flag that no longer
  exists. **Asteroids are now purely spatial** — scenery and obstacles.
- **`Inventory.repair_module()` / `_captured_tech_totals` are gone.** They
  were the identity leak Phase 1 existed to close: a captured part was a
  per-type count, and "repairing" it built a brand-new instance. A recovered
  part is now the same object throughout.
- Steel Alloy / Electronics / Reactor Components — replaced by
  Iron/Copper/Nickel/Titanium long before the freeze.

### Ship building (done, wired into the flyable ship)
- Hex-grid (axial coordinates) layout data model under `scripts/ships/...`:
  `module_type.gd`, `module_placement.gd`, `module_catalog.gd` (still a
  static prototype catalog, documented as a stand-in for real `.tres`
  resources), `ship_layout.gd` (place/remove/rotate, BFS connectivity,
  `validate_layout()`/`find_unreachable_from_core()`), `hex_utils.gd`,
  `ship_layout_renderer.gd`.
- `scenes/ui/ship_builder/` — rebuilt against
  `docs/design_handoff_ship_builder/`, which is the source of truth for its
  appearance. Full-screen (`CanvasLayer` layer 10 so it occludes the HUD):
  backdrop, top instruction line + HP/MASS/EN/CARGO strip, hex field, a 336px
  right column (Modules card, ship name + Save, collapsible Presets), and a
  bottom bar with the cell pill and ROTATE / REMOVE SELECTED / VALIDATE.
  `BuilderTheme` holds every colour and metric plus the StyleBox/font
  factories, and is shared with the upgrade screen. **R** rotates, **X**
  deletes. Any visible `"menu_panel"`-grouped CanvasLayer suspends
  `ship_input.gd` polling. The placement preview renders the actual module
  texture at the real placement rotation under a pulsing dashed cyan/red
  valid-invalid outline.
- **Ownership model (Phase 1.3, superseding Phase 5.2's craft-then-place).**
  **There is no manufacturing on this screen.** Every row in the list is a
  *specific part the player physically has* — the list is the hold — and
  building is putting those objects onto the hull. Placing takes the exact
  instance out of the pool (`Inventory.take_owned_instance`); unbolting
  returns that same object to it (`return_owned_module`), serial, wear and
  history intact. The pool lives on `Inventory` keyed by
  `Inventory.owned_module_key(module_type_id, manufacturer_id)`. A fresh
  player ship is seeded with one instance of every starter-loadout type
  (`Ship._seed_starter_owned_modules()`, first region of a session only) so
  stripping the starter ship down can never soft-lock rebuilding it.
  `ModuleType.build_costs` and `Inventory.research()` still exist and are
  simply unreached — nothing is deleted. Saving/loading custom ships to disk
  works, with the known hole that a saved layout carries its own instances
  (see `_load_current_name`).
- **The builder opens anywhere.** Its home-base gate is gone: being near a
  dock no longer decides whether you can build, it decides mount quality (see
  Field attachment above). `ShipBuilderPanel.always_docked` is the override
  the opening uses so the fitting-out is not penalised.
- **INVENTORY tab** — the hold's bays, drawn as the parts' real hex plates,
  plus whatever is on the end of the grapple. A towed part is picked up and
  then placed into a bay, mirroring how the hull half works.

### Economy / energy / cargo — **partly FROZEN**

> Materials and components still drop from kills and still fill the hold, but
> **nothing spends them**: the trade market (`TradeMarketPanel.frozen`),
> credits (`Hud.CREDITS_FROZEN`) and crafting are all frozen, and asteroid ore
> is gone. Treat the material economy below as plumbing that currently runs
> into a wall — do not build on it, and do not "fix" the fact that the hold
> fills with things that have no use. Energy and cargo capacity are live and
> unaffected.
- **Raw materials (Phase 4.2)**: `scripts/economy/material_type.gd`
  (`MaterialType extends Resource` — id/display_name/color/icon [unused
  placeholder]/sell_price/buy_price/yield_multiplier) +
  `scripts/economy/material_catalog.gd` (`MaterialCatalog`, same
  build-once-and-cache pattern as `ModuleCatalog`) replace the old static
  `Materials` script entirely. Exactly four materials —
  `MaterialCatalog.IRON`/`COPPER`/`NICKEL`/`TITANIUM` — with an ordered
  `ALL_IDS` array every UI panel/combat-drop roll iterates instead of a
  hardcoded list, so a future fifth material is a two-line addition. Rarer
  materials have a lower `yield_multiplier` (Titanium 0.45 vs. Iron 1.0),
  applied once in `Salvage._ready()` so it affects every source (mining,
  combat, asteroid kill-drops) automatically. `scenes/player/inventory.gd`
  (Dictionary-based multi-material pool, unchanged — already generic over
  material_id strings, no rewrite needed to support the swap).
- Energy: `ModuleType.energy_generation`/`energy_capacity_contribution`,
  `Ship.current_energy`/`max_energy`/`energy_generation_rate`. Thrust,
  weapon fire, and tractor beam all draw from the same pool. **AI ships use
  the exact same energy system as the player.**
- Numpad 5 (`debug_add_resources`) adds 1000 of each material — dev-only.
  Bypasses cargo capacity on purpose (see Cargo capacity below).
- **Cargo capacity** (Phase 3.2/3.3): `Inventory.get_cargo_capacity()`/
  `get_cargo_used()` (sum of `_material_totals`), recomputed by
  `Ship._apply_layout_cargo_capacity()` from `base_cargo_capacity` (100) +
  `ShipLayout.total_cargo_capacity()` (sum of `ModuleType.
  cargo_capacity_contribution`, no distance-from-core falloff unlike
  energy). New **Storage Container** module (`storage_mk1`, +60 capacity, a
  plain stat contributor like Reactor/Battery, not a hardpoint category).
  Two collection paths: `Inventory.add_material()` stays uncapped (ship-
  builder refunds, the debug cheat above, `GameState` restore all rely on it
  never failing); `Inventory.try_add_material()` is the only capacity-
  checked path, used exclusively by `Salvage` pickup, emitting `storage_full`
  on rejection. Dedicated Cargo screen (`cargo_panel.gd`/`.tscn`, **C** key,
  not home-base-gated) shows per-material totals with Discard 10/Discard
  All buttons; the HUD's bottom-left `CargoWidget` chip shows a live
  `used/max` readout (its dropdown lists per-material counts), plus a
  transient "STORAGE FULL" flash. Ship builder blocks removing a Storage
  module if current cargo would exceed the reduced capacity.

### Crafting & construction economy (Phase 5) — **FROZEN**

> **Frozen Phase 0a** (`CraftingPanel.frozen`). The **K** key opens nothing.
> Crafting chains turn objects into bulk material, which the thesis rules out
> on principle (`docs/direction.md` §1). Components still drop from kills and
> still occupy cargo; nothing consumes them. Kept below because the code is
> untouched and Phase 5 decides what returns.
- **Raw materials now include Glass** (`MaterialCatalog.GLASS`, 5th
  material) alongside Iron/Copper/Nickel/Titanium — no asteroid variant
  claims it as a primary, so it's only ever the existing uniform-random
  "otherwise" pick every variant already rolls among `ALL_IDS`.
- **Components** (`scripts/economy/component_type.gd`/`component_catalog.gd`):
  6 intermediate items — Metal Sheets, Wiring, Circuit Board, Reinforced
  Steel, Motor, Canister — held in their own `Inventory` pool
  (`_component_totals`) but sharing the same cargo capacity as materials.
  `ComponentCatalog.COMMON_IDS`/`RARE_IDS` group them by craft cost (single
  vs. double raw-material input) for combat-drop weighting.
- **Crafting** (`scripts/economy/crafting_recipe.gd`/`crafting_catalog.gd`,
  `scenes/ui/crafting_panel.gd`/`.tscn`, **K** key): one recipe per
  component, raw-materials-only inputs. `Inventory.can_craft()`/`craft()`
  check-then-atomically-spend inputs and produce output, blocked up front if
  cargo lacks room for the result — a craft never partially consumes.
  Quantity-selectable per recipe row; disabled when unaffordable.
- **Module construction**: see the Ship building section above —
  `ModuleType.build_costs` is now spent to *build* an owned instance, not to
  place one. Hull/Engine/Scanner/Storage use component-based costs (the
  spec's own examples); every other module type still costs plain raw
  materials.
- **Repair**: see the Salvage collection section below — converts a
  captured/damaged module part into a placeable owned instance.

### Module upgrades (ship-wide trees) — **FROZEN**

> **Frozen Phase 0a** (`UpgradeMenu.frozen`). The **U** key opens nothing and
> "U: Upgrades" is gone from `StationPrompt.PROMPT_TEXT`. Not one of the 89
> nodes has a stat effect, so it failed the scope test outright — it is the
> largest piece of build that ran ahead of validation, and the cautionary
> example the whole freeze exists around. **Wiring stat effects to it is no
> longer the next piece of work; do not start it.**

Source of truth: `docs/design_handoff_upgrade_tree/` (README + LAYOUT_SPEC +
`upgrade_data.json`). Read the whole folder before changing this screen.

- **Ship-wide, not per-module.** Seven systems (Hull, Propulsion, Weapons,
  Power, Storage, Sensors, Mining), one tree each, 89 nodes total. Guns and
  launchers are both "Weapons".
- **Content** is `res://resources/upgrades/upgrade_tree_data.json`, a verbatim
  copy of the handoff's `upgrade_data.json` minus its `_schema` block. Adding
  an upgrade is a data edit — no code enumerates nodes. Node fields:
  `id`/`tier`/`parents`/`label`/`glyph`/`desc`/`cost`, optional `icon` and
  `hue` (starts a coloured branch, inherited by descendants).
- **`ShipUpgradeCatalog`** loads it and resolves the handoff's display-string
  costs against `MaterialCatalog`/`ComponentCatalog` by display name, so they
  are spent from the real inventory. An unrecognised name warns rather than
  silently costing nothing.
- **`ShipUpgradeService`** is the whole rule: `is_unlocked` (root is always
  owned) and `is_available` (every parent unlocked). `parents` is an AND list;
  arity 2+ *is* the merge mechanic, there is no separate flag.
- **State** lives in `GameState` — `is_upgrade_unlocked`/`unlock_upgrade`/
  `get_unlocked_upgrades`, ids only, plus `last_upgrade_category`.
  Deliberately outside `capture()`/`apply()`: those mirror one ship across a
  warp, unlocks are player progression that outlives any hull.
- **UI**: `scenes/ui/upgrade_menu.gd` (`UpgradeMenu`, **U** key,
  home-base-gated, `CanvasLayer` layer 10 so it occludes the HUD) plus
  `scenes/ui/upgrades/` — `upgrade_palette.gd` (OKLCH→sRGB; a category's whole
  palette derives from one hue number), `upgrade_tree_layout.gd` (the polar
  fan: span allocation, mirroring in the right half, merges placed from their
  parents' angles at +0.4×STEP, label anchoring that flips near the arc ends),
  `upgrade_tree_view.gd` (drawing + hit-testing), `upgrade_rail_list.gd`,
  `upgrade_detail_panel.gd`. Surfaces/text/StyleBoxes come from the ship
  builder's `BuilderTheme` — same palette, deliberately shared.
- **Two invariants worth not breaking**: the view renders from
  `UpgradeTreeLayout.entries` only (it used to keep a parallel node list and
  crashed on a stale id when switching category mid-frame), and every tree is
  fitted against one shared reference frame (`UpgradeMenu._shared_frame()`) so
  node size doesn't change between systems.
- **Nothing an upgrade unlocks changes ship behaviour yet** — the handoff
  authors no stat modifiers. Unlocking spends resources and records the id.
  Effects hook into `ShipUpgradeService.unlock()`;
  `HardpointBank.apply_modifiers()` reaches an already-spawned hardpoint
  without rebuilding it, and `Ship._refresh_layout_stats()` re-derives
  aggregates without touching health or module condition (a full
  `_apply_ship_layout()` would heal the ship and reset every module).
- **Radar and Scanner still have no per-placement spawned node**
  (`Ship.has_radar()`/`has_scanner()` are boolean flags; `Scanner` is one
  fixed node on `ship.tscn`). Sensors effects will need a pull-at-point-of-use
  mechanism, not the push-at-spawn one everything else uses.

### Cutting parts free (the Salvager — what the Mining Grinder became)

**`HardpointGrinder` no longer exists.** The module was rebuilt as
`scenes/player/hardpoint_slicer.gd`/`.tscn` (`HardpointSlicer`, "Salvager",
`hardpoint_category="salvager"`), keeping the `mining_grinder` hex art. The
old mining behaviour is described in the compressed sessions above and is
history, not instructions.

- **A cut is a duration, not a damage rate.** `cut_duration` 3.6s of held
  beam consumes the whole cuttable band, after a fixed 2.4s lock/spool ramp —
  so every part takes the same wall-clock time regardless of its health pool.
  `beam_range` 420 (10 hexes), 9 energy/sec.
- **It can only open a seam damage has already started.** A part at or above
  `HullPaint.CUTTABLE_CONDITION` (0.30) reports `"intact"` and the beam gives
  its "cannot be opened" feedback. Guns are what make a part cuttable; the
  Salvager is what takes it off. That is the intended division of labour.
- **You cut the connector, not the prize.** The cut part is destroyed and
  becomes debris; anything that loses its path to the core as a result is
  severed *intact* at its current condition, with no capture roll
  (`_clean_cut_active` → `WreckageSpawner.spawn_severed_piece(clean_cut)`).
  Blowing a ship apart instead multiplies the recovered part's integrity by
  `explosive_recovery_integrity` (0.6) — same prize, permanently worse.
- Cut parts never age out, and a completed cut switches the system off.

**Asteroids are scenery now.** `Asteroid.MINING_FROZEN` is true, so rocks
drop nothing; `roll_ore_material()` and the per-variant primary-material
table still exist behind the flag. Region asteroid densities in
`resources/regions/*.tres` were tuned as a yield curve that no longer
exists — that mismatch is deliberate, recorded in `docs/frozen_systems.md`,
and re-tuning them back to the old spec would re-break the freeze.

### Salvage collection (Phase 3.1 Tractor Beam, Phase 3.2 capacity, Phase 4.1/4.2 mining + collection rework)
- `scenes/player/hardpoint_tractor_beam.gd`/`.tscn`: a hex module
  (`hardpoint_category="tractor"`), always active while mounted and intact,
  no player input. Locks onto the single nearest valid target (`Salvage` or
  `CapturedTechPart`, groups `"salvage"`/`"capturable_tech"`) within
  `max_range` (250) with a clear physics-raycast line of sight — **one
  target at a time by design**, framed as a future upgrade path (more
  simultaneous targets), not built. Costs energy/sec from the ship's shared
  pool while actively pulling. **Pulls the target all the way to this
  hardpoint's own Muzzle** (not the ship's center/hull, see most recent
  session) and collects it there via `Salvage.collect_for()` once within
  `salvage_collect_radius` (20) — a failed collection (full cargo) holds the
  target at the Muzzle and keeps retrying every frame rather than dropping
  it.
- Salvage can still self-collect without a Tractor Beam by physically
  touching the ship (`Area2D.body_entered`, `scenes/world/salvage.gd`), but
  **only once it actually reaches the Command Core specifically**
  (`Ship.get_core_global_position()`/`get_core_collect_radius()`, one
  hex-cell radius) — a piece merely touching an outer hull module doesn't
  collect, it sits there (`_pending_pickup_body` retried every frame,
  `_is_near_core()` gate) until it drifts further in or the ship moves away.
  This is the same retry mechanism a full cargo hold uses (both conditions
  are checked in the same loop): a piece is never silently dropped, just
  held pending until it's both near the Core and there's room for it.
- **Component salvage (Phase 5.3)**: `Salvage.kind` (MATERIAL | COMPONENT) —
  a component drop carries `component_id`/`component_amount` and collects
  through `Ship`/`Inventory`'s `try_add_component`/`add_component`, the
  parallel path to the material versions. Asteroid mining/`HardpointGrinder`
  fragments never set `kind`, so mining stays material-only by
  construction; components are combat/wreck-exclusive — see Combat below.
- **Recovered parts (Phase 1.3, superseding the Phase 5.3 description).** A
  severed module becomes a `CapturedTechPart` **carrying the actual
  `ModuleInstance` that was on the hull a frame ago**, and that object goes
  into the owned pool unchanged — directly placeable, damage and origin and
  kill count and all. `Inventory._captured_tech_totals` (a per-type count) and
  `Inventory.repair_module()` (which built a brand-new instance) were the two
  identity leaks `docs/direction.md` §4 named, and both are **deleted, not
  frozen** — removing them was the fix. `ModuleListView`'s repair button
  remains in the widget, permanently textless and therefore hidden.
- Whether a shot-off part survives at all is still `ModuleType.capture_chance`
  against `capture_health_fraction`; a Slicer cut skips that roll entirely.

### Combat
- `hardpoint_gun.gd`/`hardpoint_missile_launcher.gd` + `missile.gd`:
  tier-scaled stats, torpedo-style missile flight homing off a live target
  reference.
- `scenes/enemies/ship_ai.gd`: one AI script for every archetype, driven by
  a `ShipPersonality` resource, `IDLE → SUSPICIOUS → ALERT` state machine.
  AI aim is deliberately imprecise (`_jittered_aim_point()`, re-rolled every
  0.35s) — see "Decisions made" for why. `Ship._finish_destruction()` drops
  `Salvage` on death for any ship with `drops_salvage` true (the default) —
  this is what makes killing Pirate Camp members automatically rewarding,
  no extra code needed.
- **Phase 5.3 drop weighting**: each kill-drop rolls `Ship.
  component_drop_chance` for material-vs-component, then `rare_component_chance`
  for `ComponentCatalog.COMMON_IDS` vs. `RARE_IDS`. Both are per-instance
  `@export`s, hand-tuned per enemy `.tscn` (Scout/Light pirates 0.15/0.15 →
  Med 0.3/0.25 → Heavy 0.45/0.35 → Missile Cruiser 0.55/0.45 + a bumped 3–5
  drop count) — a harder kill pays out more/rarer components, not just more
  material. `PirateCamp` pirates inherit whichever base `.tscn` they
  instance; there's no camp-specific override.
- `ai_navigator.gd`: obstacle/ship avoidance, stuck recovery, hysteresis —
  see AI navigation session above / `docs/aienemies.md`.

### Per-module ship damage + wing detachment (Version 0.4)
A hit resolves to a specific hex module (world impact point → hex coordinate
via `HexUtils.pixel_to_axial`) and can destroy/sever it independently of the
ship's overall `Health` pool.
- `Ship._module_conditions` is runtime-only state on the `Ship` node, never
  on the shared `ShipLayout` resource.
- Splash damage (`module_splash_fraction` = 0.35) hits neighbors too — the
  Command Core is exempt (only dies from a direct hit).
- `ShipLayout.find_unreachable_from_core()` (BFS) drives severance;
  `Ship._detach_module()` disconnects a wing (loses stats/collision, spawns
  cosmetic `ShipDebris`). A destroyed-but-attached module also frees its
  collision shape (no longer blocks shots to what's behind it).
- Core destruction = instant ship death (no anchor to measure connectivity
  otherwise). `_check_all_modules_gone()` catches the case where splash
  damage guts every module before `Health` itself reaches zero.
- New single-cell "Strut" module: cheap, fragile, connective tissue for
  wings. Current module health balance: Core 140, Hull 50, Heavy Hull 240,
  Strut 25 — reached via live pirate-vs-test-ship combat, not pure math (see
  "Decisions made" for the methodology if re-tuning).

### Information & discovery (Phase 2, ad-hoc spec — not in either roadmap)
- **Radar** (`scenes/ui/radar_display.gd`): live sweep-reveal, bottom-right,
  1800-unit range, "RANGE N" label under the circle, cyan per the 1d HUD
  spec, with one faint range ring per 1000 units of range (so an upgrade
  adds rings rather than rescaling fixed ones). Categories: Ship,
  Station, Electronic Signal, Enemy Camp, Distress Beacon — **Enemy Camp and
  Distress Beacon now have live instances** (see Points of Interest below);
  Electronic Signal still has none. Never shows anything Scanner identifies.
  **Requires a Radar hardpoint** (green hex, `hardpoint_category="radar"`,
  see most recent session) — `Ship.has_radar()` gates the whole display,
  checked live every frame so losing/repairing the module shows/hides the
  HUD immediately.
- **Scanner** (`scenes/player/scanner.gd` + `scenes/ui/scanner_display.gd`,
  `scanner_scope.gd`, `scanner_palette.gd`): a **directional time-of-flight
  pulse** drawn as the A-scope from `docs/design_handoff_scanner_radar/` (see
  most recent session — that folder governs its appearance). Aim a beam
  (6°–120°), fire with V or the PING button, and returns arrive as the
  wavefront reaches them at 1000 u/s out to `scan_range` 3000, then a 6s
  cooldown. Still **closest-`max_results` (5)**. Identifies Planet/Wreck/
  Ancient Formation individually (`scripts/world/scannable.gd`) and asteroids
  as count-named clusters ("Asteroid Cluster (6)"). Deliberately excludes the
  home station and anything radar-only (signals/camps/beacons) — "off the
  grid" objects only. **Requires a Scanner hardpoint** (magenta hex,
  `hardpoint_category="scanner"`) — `fire_ping()` refuses without one, and a
  pulse in flight self-cancels if the module or Sensors power is lost.
- **Points of Interest** (Phase 2.3, `map_tester.tscn`): four hand-placed
  destinations built entirely from existing systems. `scripts/world/poi_camp.gd`
  (Small Pirate Camp, radar `enemy_camp`), `scripts/world/distress_signal.gd`
  + `scenes/world/distress_signal.tscn` (radar `distress_beacon`),
  `scenes/world/abandoned_ship.tscn` (Scanner "Wreck"),
  `scenes/world/scenic_formation.tscn` (Scanner "Ancient Formation",
  discovery-only, no reward). Each has a real completion/exhausted state
  (camp clears from radar once cleared; beacon clears once its salvage is
  collected; wrecks don't respawn rewards).

### Gameplay HUD (rebuilt to the "1d" spec)
`scenes/ui/hud.tscn` — a `CanvasLayer` with corner-anchored Control widgets,
24px margins, no fixed pixel layout. Appearance is governed by
`docs/HUD-1d-Godot-spec.md` + `docs/hud-1d-reference.png`, not by taste.
- `VitalsReadout` (top-left) — HP/EN dot+bar+number rows, `_draw`-based.
- `CargoWidget` (bottom-left) — `used/max` chip, click toggles an
  upward-growing material list. Subscribes to `Inventory` itself.
- `RadarDisplay` (bottom-right) and `ScannerDisplay` (right edge, vertically
  centred, **only while open** — V opens it, X/Escape closes) — both still
  gate themselves on `Ship.has_radar()`/`has_scanner()` every frame. The
  scanner panel covers the radar dial while open; that's the known cost of
  fitting a 388×568 instrument on a 1152×648 HUD.
- `CreditsLabel` (top-right) — **hidden**, `Hud.CREDITS_FROZEN`. The HUD
  therefore no longer matches element 4 of `docs/HUD-1d-Godot-spec.md`; that
  is a recorded consequence of the freeze, not a bug to fix. The control-hint
  panel occupies that corner only because the readout is gone — if credits
  ever return, `ControlHint.TOP_MARGIN` has to drop below y 42.
- Plus the pre-existing damage vignette and STORAGE FULL cue.
- `HudPalette` (`scenes/ui/hud_palette.gd`) is the one place HUD colours
  live — **except material dot colours, which come from
  `MaterialCatalog.color()` on purpose.**
- Known gaps: engine default font (the spec wants an embedded monospace
  `FontFile`; the project ships no `.ttf`), and the cargo dropdown uses the
  spec's flat tinted-glass fallback rather than a `BackBufferCopy` + blur
  shader.

### World
- `starfield_layer.gd` + `ParallaxBackground` layers, bloom via one
  `WorldEnvironment` node.
- One planet (`scenes/world/planet.tscn`), visual-only, no data/catalog
  system (scannable, see above).

## Decisions made (and why — don't relitigate without reason)

- **Ship-centric, not player-centric architecture** — AI and player ships
  share the same `Ship`/`ship_ai.gd`/`ship_input.gd` split.
- **Hex grid with axial coordinates (`Vector2i`)**, not a square grid.
- **Static `ModuleCatalog` is a deliberate, documented prototype shortcut.**
- **Never silently no-op** — every rejected ship-builder action surfaces a
  specific reason string.
- **Exactly one Command Core** enforced as a current layout rule.
- **Menu-open input suspension is group-based** (`"menu_panel"` group).
- **Missile behavior is a one-shot torpedo phase sequence**, not a repeating
  burst/coast cycle (explicitly tried and rejected).
- **Planets are visual-only for now** — no catalog/orbit system until asked.
- **Per-module combat state lives only on `Ship`, never `ShipLayout`** — the
  load-bearing reason the damage system is safe on shared enemy-scene
  resources.
- **The Core is a deliberate special case**: toughest single module, exempt
  from splash damage, destroying it ends the ship immediately.
- **AI aim is intentionally imprecise** — added because AI previously aimed
  at the exact ship origin (= the Core's location by convention), making the
  Core a guaranteed bullseye the instant front armor broke. Player accuracy
  is untouched.
- **Splash damage exists specifically to make focused-fire severing
  achievable** against a moving target — side effect: modules clustered near
  each other take more effective cumulative damage than an isolated one,
  which is why the Core had to be splash-exempt.
- **Module health/splash/Core numbers were reached via live combat testing**
  (a real long test ship fought by a real spawned pirate), not math — if
  re-tuning, repeat that methodology rather than guessing from stat sheets.
- **Manufacturers are deliberately separate from Factions.** A `Manufacturer`
  is a stat-modifier profile ("what engineering philosophy built this part")
  independent of faction ("whose territory/art is this") — lives on
  `ModulePlacement.manufacturer_id`, not `ModuleType`/`ShipPersonality`, so
  the same module type can exist with or without one. Discovering a
  manufacturer (via capture) and researching a locked module type are two
  separate gates on purpose.
- **Radar and Scanner are strictly non-overlapping by design.** Radar =
  live faction/activity detection (ships, stations, signals), broad category
  only, never identity. Scanner = deliberate, longer-range identification of
  "off the grid" objects (asteroids, wrecks, planets — never active
  infrastructure, never anything radar already covers). This was corrected
  back into place twice in the Scanner session after both boundaries got
  blurred mid-iteration — treat it as a hard rule, not a preference. The
  Points of Interest session kept every new POI strictly on one side of this
  line (camp/distress = radar-only, wreck/formation = scanner-only, never
  both).
- **Scanner reports asteroids as count-named clusters, never individual
  rock identity** — "Asteroid Cluster (6)" style naming, proximity-grouped.
  Explicitly replaced an earlier Common/Dense/Rare composition-based design
  per user request.
- **Points of Interest reuse existing systems rather than a new framework.**
  No `PointOfInterest` resource/spawner was built — each POI is a small,
  configurable scene (same pattern nebulae/gates already use), and reward/
  combat mechanics (salvage-on-death, idle-until-provoked AI) already
  existed and needed zero new code. Only add a generation framework if a
  much larger number of POIs is requested later.
- **"Wrecks" and "Abandoned ships" are treated as one implemented type**, and
  "Simple derelict structures" wasn't built as a distinct fifth type — all
  three spec bullets describe the same physical shape/mechanic (a scannable
  hulk with finite salvage); building them separately would have been pure
  duplication.
- **Tractor Beam, Radar and Scanner are hex modules, not fixed ship/HUD
  components.** Two flavors of the same idea: Tractor Beam is a spawned
  hardpoint node (needs a muzzle position/beam visual, like weapons/winch),
  while Radar and Scanner are a "pure capability flag" — `Ship.has_radar()`/
  `has_scanner()` just check the layout for an intact hardpoint of that
  category, no spawned world node at all, since neither has a fixed facing
  or world-space visual of its own. Apply the same flag pattern to any
  future module that's really a sensor/HUD gate rather than a physical
  object on the hull.
- **Tractor Beam pulls exactly one target at a time**, not everything in
  range at once — an explicit, repeated user correction (built multi-target
  first, twice) framed as "upgradable later." Don't silently expand this
  without a fresh request.
- **New hardpoint module colors must be visually distinct from existing
  ones** — Radar's first color was too close to Engine/Tractor Beam's blues
  and had to be corrected. Check the existing palette in
  `ModuleCatalog.get_all()` before picking a color for a new module type.
- **Two separate material-add paths on `Inventory` by design:
  `add_material()` uncapped, `try_add_material()` capacity-checked.**
  Refunds (ship-builder removal), the debug resource cheat, and `GameState`
  restore all call `add_material()` and must never fail — capacity is only
  ever enforced on the one path real gameplay collection (Salvage pickup)
  goes through. This means cargo *can* end up over capacity through those
  other paths (allowed — nothing is ever deleted to force it back under),
  it just blocks further real collection until it's back under again.
- **A full cargo hold rejects Salvage pickup instead of destroying the
  item** — the Salvage node stays alive in the world and retries every
  frame it's still overlapping the ship until space frees up or it drifts
  away. Never silently drop salvage on the floor of a full hold.
- **Storage capacity is a plain stat contributor (like Reactor/Battery),
  not a hardpoint category like Tractor/Radar/Scanner.** It has no
  facing/muzzle/HUD gate of its own to need the "pure capability flag"
  treatment — it just raises a number `try_add_material()` checks. Don't
  give it a `hardpoint_category` or a `has_storage()`-style gate unless a
  future spec actually needs one.
- **The Mining Grinder is player-toggled (G), not always-on like the
  Tractor Beam.** Deliberate: it deals continuous damage, so it needs
  explicit activation the way a passive pull-in tool doesn't. Uses a
  pull-model flag (`Ship.is_grinder_active()`, checked every frame by each
  mounted grinder) rather than a pushed command, matching
  `is_module_destroyed`'s existing convention — don't push a one-shot state
  change to hardpoints, let them poll Ship each frame.
- **The grinder damages asteroids via `take_damage()`, not `take_damage_at()`,
  on purpose.** `take_damage_at()`'s knockback/scatter-velocity mechanic was
  built for one-off weapon hits; applying it every frame during a *held*
  grind would fight the asteroid drifting away out of contact range. Any
  future continuous-damage-over-time module should default to plain
  `take_damage()` for the same reason — only a discrete hit should knock
  something back.
- **Weapons were deliberately not nerfed to make the Grinder the better
  mining tool.** A gun only yields material on an asteroid's final kill; the
  Grinder yields fragments continuously while the asteroid is still alive,
  which is strictly more resource-efficient per second without touching any
  weapon stat. If a future request wants weapons *actively* worse at mining
  (not just less efficient), that's a fresh, separate decision — don't
  assume it's implied by this one.
- **The ship builder's rotation-arrow indicator intentionally does NOT
  track the real hex-neighbor direction.** It uses `60° * rotation_steps -
  90°` so an unrotated module always visually points "up," even though the
  actual 6 hex-neighbor directions never include exactly "up" (only
  0/60/120/180/240/300°). This was found and briefly "fixed" (arrow made
  hex-accurate) during the Mining Grinder investigation below, then
  **explicitly reverted by the user** in favor of keeping the simpler
  "points up by default" UX. For a multi-hex module, the module's own
  second hex tile is the real ground truth for its front direction, not
  this arrow — see the comment at `hex_grid_control.gd`'s arrow formula and
  the matching `docs/gotchas.md` entry before touching this again.
- **The Mining Grinder's beam is the one exception that deliberately does
  chase the builder arrow's direction, in the opposite sense of the bullet
  above.** The arrow formula itself stayed untouched (per the decision
  above), but a later session moved the *grinder's own muzzle exit point* to
  the vertex that makes the beam visually line up with what the arrow shows
  — a real, user-reported "beam doesn't point where the arrow says" com-
  plaint, fixed by changing the grinder's geometry rather than the shared
  arrow. Live-verified twice via `game_eval` (a first attempt landed on the
  wrong adjacent vertex, 120° off, before the correct `-90°` muzzle-local
  angle was found) — see the hex-preview/grinder session for the derivation.
  Don't assume this generalizes to Winch or any other fixed-facing
  hardpoint; nothing else has been audited or requested.
- **Raw materials replace the old Steel Alloy/Electronics/Reactor Components
  set entirely, not alongside it.** Confirmed via `AskUserQuestion` before
  building — the alternative (keep the old 3 for building/trading, add the
  new 4 as mining-only) would have left 7 materials total and duplicated
  the "structural/electronics/rare" tiering for no real benefit. Every build
  cost, upgrade cost, and trade price was remapped, not left dual-tracked.
- **Material data is resource-driven (`MaterialType`/`MaterialCatalog`),
  mirroring `ModuleType`/`ModuleCatalog`'s existing "documented prototype
  catalog, not real `.tres` files yet" shape.** Adding a material should stay
  a two-line change (one id const, one `_make()` call) — don't hardcode a
  material list anywhere else; iterate `MaterialCatalog.ALL_IDS` instead.
- **Per-material yield_multiplier and per-source amount_multiplier are two
  separate, orthogonal knobs on Salvage's final amount, multiplied
  together.** yield_multiplier (on `MaterialType`) says "this material is
  scarce regardless of how you got it"; amount_multiplier (on `Salvage`,
  set by the spawner) says "this source yields more/less than baseline
  regardless of which material it happens to be." Don't conflate them when
  tuning — a "materials feel too rare/common" complaint is a
  yield_multiplier problem, a "this specific tool gives too much/little"
  complaint is an amount_multiplier problem.
- **The Mining Grinder's per-fragment yield is deliberately *smaller* than a
  weapon kill-drop's, not bigger.** An initial pass (`fragment_yield_
  multiplier` 1.5, an individual fragment briefly outyielding a kill-drop)
  was corrected to 0.5 after live feedback that mining one Large asteroid
  nearly filled the entire cargo hold in a single ~6s grind. The Grinder's
  edge over a gun is still real — fragments accumulate throughout a grind
  on top of the same final kill-drop every asteroid always releases — but
  it comes from the *total across a full grind*, not from any one fragment.
  If pacing needs to move again, tune `fragment_yield_multiplier` (chip
  size) or `fragment_interval` (chip frequency) on `HardpointGrinder`, not
  the shared `Salvage`/`MaterialType` yield math those other sources rely on
  too.
- **Plain hull-touch self-collection requires reaching the Command Core
  specifically; only a Tractor Beam can collect anywhere else (at its own
  Muzzle).** A user-reported complaint that salvage vanished the instant it
  grazed any outer hull hex. `Ship.get_core_global_position()` resolves the
  Core's actual position from `ship_layout.core_placement_id` rather than
  assuming it sits at the ship's local origin (it usually does, by the
  existing "ship origin = Core" convention, but the check doesn't rely on
  that). A side effect worth remembering: `is_dangerous` mine-style salvage
  can no longer detonate on a first graze against an outer module — it only
  triggers once something actually reaches the Core (or a Tractor Beam
  drags it to its Muzzle). Not requested, not treated as a problem, just a
  consequence of the same fix.
- **Ship-builder module placement is now free; owning a built instance is
  the gate (Phase 5.2).** Replaces the old "spend `build_costs` directly at
  placement" model entirely, not alongside it — mirrors the raw-materials
  "replace, don't dual-track" precedent above. `ModuleType.build_costs` is
  reinterpreted as a *construction* cost, spent only by the new Build
  action; Select/Place and Remove move an owned-instance count, never
  materials, directly.
- **Mining stays raw-material-only; crafted components are combat/wreck
  -exclusive (Phase 5.3).** A deliberate asymmetry, not an oversight —
  `Asteroid`/`HardpointGrinder` never set `Salvage.kind`, so a component
  drop can only ever come from a kill or a hand-placed wreck. This is what
  makes salvage a genuine *second* progression route rather than a faster
  version of mining, per the spec's own framing.
- **Repair and Research are two independent ways to spend one captured tech
  part, not a tiered upgrade of each other.** `research()` permanently
  unlocks a locked module *type* for building; `repair_module()` produces
  one *placeable instance* of any capturable type, locked or not. A type
  can be repaired from captured parts before it's ever researched (if it
  doesn't require research), or researched without ever being repaired.
  Both drain the same `_captured_tech_totals` count, so a part is spent by
  whichever the player picks — there's no rule forcing one before the other.
- **`.tscn` node property blocks cannot safely use `#` comments** — already
  documented in `docs/gotchas.md` before this session, re-confirmed the hard
  way while hand-tuning per-enemy drop-chance exports (a comment line
  silently corrupted the *next* property assignment, leaving it at the
  script default with no load error). Check `docs/gotchas.md` before
  hand-editing a `.tscn`, not after.
- **Module upgrades are ship-wide and driven entirely by
  `docs/design_handoff_upgrade_tree/`.** This is the third upgrade system the
  project has had: a ship-wide `UpgradeManager`/`UpgradeCatalog`, then
  per-`ModuleInstance` trees (Phase 8.1), now the handoff's seven system trees.
  The user corrected the third one into shape across several messages —
  the rail is the seven systems, each with **one** tree; there are no
  per-mounted-module rows and no separate "Missiles" category. Don't
  reintroduce either without a fresh request, and read the whole handoff
  folder (README, LAYOUT_SPEC, `upgrade_data.json`) before changing the screen
  — the first attempt went wrong precisely by implementing the layout spec
  while keeping the game's own content model.
- **Upgrade content is data, not code.** `resources/upgrades/
  upgrade_tree_data.json` is the whole tree; adding an upgrade is a data edit
  and nothing in code enumerates nodes. Keep it that way.
- **The upgrade menu is a dedicated `U`-key screen, not a button inside the
  ship builder.** Built inside the ship builder first; the user found that
  "clunky" and asked for its own key instead — a real, explicit UX correction,
  not a preference call made unprompted. Don't move upgrading back into the
  ship builder without a fresh request.
- **`Inventory`'s owned-module pool must stay a pool of real
  `ModuleInstance`s**, not a `Dictionary[key]->int` count. It was changed from
  counts for the per-instance upgrade system, and although that system is gone
  the pool is still what makes "remove a module and re-place it and it's the
  *same* module" true.
- **A narrow live stat refresh must never reach for the ship builder's full
  `_apply_ship_layout()`.** That call silently heals the ship to full and
  resets every module's condition — correct for "I just applied a rebuilt
  layout at the workbench," wrong for anything smaller.
  `Ship._refresh_layout_stats()` is the narrow path, and
  `HardpointBank.apply_modifiers()` is how a single stat reaches an
  already-spawned hardpoint. Any future live mutation of a running ship's
  stats should follow that shape.
- **Radar and Scanner cannot take push-at-spawn stat modifiers.** They're the
  only hardpoints with no per-placement spawned node (pure capability flags —
  see the Radar/Scanner decision entry above). Before authoring Sensors
  effects, give `Scanner`/`RadarDisplay` a way to pull their modifiers live at
  point of use. `Scanner.scan_range` is the one the scanner handoff names as
  *the* upgradeable stat, and both the scope's range axis and its gridline
  spacing already re-derive from it, so raising it needs no UI work.


## Not yet started (no explicit user request yet — don't start without one)

**Several entries in this list predate the freeze and assume systems that are
now switched off.** Anything below that depends on trading, crafting, credits,
research, upgrade effects or asteroid mining is *not* a gap to be filled — it
is downstream of a deliberate decision (`docs/direction.md` §1). Those entries
are kept for the Phase 5 review of the freeze list, not as work.

The live gaps, in the order they matter:

- **Persistent wrecks (Phase 1 step 3, the one unfinished step).** Hulls still
  disappear; only cut parts persist. This is the biggest open item in the plan.
- **Severed parts and the ship-builder grid draw no scars.** `DriftingHexPiece`
  and the builder's hex grid each draw their own hexes and never call
  `HullScarLayer`, so a battered part looks factory-fresh the moment it comes
  off the hull — exactly where its history should be most visible.
- **A dock as a real place.** "Docked" is currently proximity to the
  `home_base`-group marker within 300 units. The station the field-attach
  penalty is written against does not exist yet; building it means joining that
  group, nothing more.
- **Removing a part in the field is unpenalised.** The field-attach design says
  a dock is also where things come off *cleanly*; only the attach half was
  built. Deliberate — the success criteria covered attaching — but it is a
  known asymmetry, not an oversight.
- **`FIELD_MOUNT_EFFICIENCY` (0.5) and `REFITTED_MOUNT_EFFICIENCY` (0.7) are
  unplayed numbers**, as is the mass-scaled turn-rate falloff
  (`Ship.handling_mass_falloff`).
- **Conduit runs on the 17 authored layouts.** None has one, so power cannot be
  switched on without every enemy going dark. This gates the whole Phase 4 bet
  and is a content job, not a code one.
- **Power isn't wired to anything.** See the power-grid subsection above: the
  flight game never solves the grid, `ModuleInstance.powered` is never written
  false, and `PowerGrid` disagrees with the pooled `total_energy_generation()`
  model that is actually live.
- **The conduit hub's 18 grommet holes don't fill with circuit colour.** The
  handoff §2 asks for a live hole to take its circuit's colour; the cables are
  drawn but the holes underneath them are still painted as drilled metal.
- **The new hexes shimmer in motion on the flying hull and it is unexplained.**
  Mipmaps and filtering were ruled out with runtime evidence; the resolution
  fix could not be shown to help. See the session log for the measurement and
  the light-map hypothesis.

Pre-freeze entries, retained for the Phase 5 review:

- **Corporate or Ancient enemy ships.** Explicitly deferred by the user
  ("we can do the enemy ships later") — every enemy in `scenes/enemies/` is
  currently a Pirate variant or the generic missile cruiser, so faction
  identity never actually shows up in combat for the other two factions.
- Faction-specific/unique salvage — materials are fully generic across all
  three factions.
- ~~Buying from a known manufacturer once discovered~~ — **ruled out.** A
  buy/sell market is excluded on principle, not deferred (`direction.md` §1).
- Severability audit for `pirate_light_two`/`pirate_heavy_one` — only
  `pirate_light_one` was fixed for the "zero severable points" blob issue.
- Reactor/Battery/other non-engine/weapon modules have no mechanical effect
  beyond losing the hex when destroyed. (Don't confuse with the new Phase
  5.3 `Inventory.repair_module()` — that converts a captured/damaged part
  into an owned instance, it's not a condition/HP repair-over-time system;
  no such system exists.)
- Player weapon accuracy/spread — untouched on purpose.
- More module types / a real data-driven (non-static) module catalog as
  `.tres` resources.
- A planet catalog, multiple planet instances, orbit/parallax motion, or any
  planet-surface gameplay.
- A wreck field that isn't station-shaped (destroyed ships, not stations) —
  partially addressed by the new Abandoned Ship POI, but `derelict_station.tscn`
  itself is still 4 station wrecks in one scene, not ship-shaped wrecks.
- The grid-of-squares universe idea the user floated during the world-
  regions session — unstarted, not rejected; a materially bigger
  architecture change than the regions work actually done.
- The "player writes their own guess" scanner memory/journal design —
  explicitly deferred during the Scanner session's pivot, not rejected;
  bigger scope than the count-based-cluster version actually built.
- Resource deposits and unknown structures as real spawned content — Scanner
  supports the categories, nothing in the game joins those groups yet.
- Electronic Signal as a live radar category — still no in-game instance
  (Enemy Camp and Distress Beacon now have instances via the POI session,
  Electronic Signal doesn't).
- A reusable POI generation/configuration framework (resource + spawner, in
  the `RegionType`/`RegionSpawner` sense) — the 4 current POIs are hand-placed
  scene instances; only worth building if many more POIs are requested.
- Anything in `vision.md` or later phases of `roadmap.md`/`Roadmap
  v.2-v.9.md` (research beyond reverse-engineering, co-op).
- Dedicated art for the Tractor Beam, Radar, and Scanner hexes — all three
  are still generic flat-tinted hexes (distinct colors, no sprite).
- Tractor Beam's multi-target upgrade — explicitly framed as "for later"
  when the single-target limit was imposed, nothing designed yet for what
  unlocks it (a second hardpoint? a per-hardpoint upgrade tier?).
- Dedicated art for the Storage Container hex — generic flat-tinted hex like
  the other undecorated hardpoints.
- Arbitrary-amount cargo discard (currently fixed 10 or all) — no numeric
  input field on the Cargo screen.
- Capacity/cargo effects for captured tech parts — that bucket stays
  separate and uncapped by design, not extended by the Storage session.
- Dedicated art for the Mining Grinder hex — generic flat-tinted hex.
- Mining Grinder audio feedback — explicitly deferred by the 4.1 spec
  itself ("audio will come later").
- Mining Grinder upgrade path ("one generic mining speed (upgradable?)") —
  only the flat generic speed was built, no upgrade tier/tree exists.
- Grinder damage/effectiveness against ships — the spec explicitly scoped
  this to asteroids only ("maybe ships later").
- Auditing Weapon/Missile/Railgun/Winch hardpoints for the same builder-
  arrow-vs-real-facing mismatch the Grinder just had fixed — not reported as
  an issue for any of them, so left untouched.
- Visual confirmation (screenshot/live look) of the new texture-based ship
  builder placement preview — code-reviewed only so far.
- Material HUD/inventory icons — `MaterialType.icon` exists as a field but
  no art or UI wiring for it yet, per the 4.2 spec's own "will come later."
- Investigating why `Ship.toggle_grinder()` didn't reliably flip
  `_grinder_active` when called directly via `game_eval` (worked fine via
  direct field assignment) — noticed during live testing, not investigated,
  real "G" keypress input untested.
- Crafting/component/repair icon art — `MaterialType.icon`/`ComponentType.icon`
  both exist as unused placeholder fields, same as the earlier 4.2 material
  icon gap.
- A dedicated "sensor/lens" component for Scanner's construction cost —
  currently uses raw `MaterialCatalog.GLASS` directly instead of inventing a
  7th `ComponentCatalog` entry for one line item; revisit if a real
  sensor-type component is ever needed elsewhere.
- Manufacturer-flavored repair — `repair_module()` only ever produces the
  generic (no-manufacturer) owned key; `CapturedTechPart` does carry a
  `manufacturer_id` but `Inventory._captured_tech_totals` itself has no
  manufacturer axis to preserve it through repair.
- Per-camp or per-region drop-table overrides — `PirateCamp` pirates
  currently just inherit whichever base pirate `.tscn` they instance.
- Component drops for the other 6 of `derelict_station.tscn`'s 9 salvage
  nodes, and for `PirateCamp`/other POIs that still only drop material —
  only 3 of the 9 got hand-authored component overrides this session.
- ~~**Stat effects for any upgrade**~~ — **no longer the next piece of work.**
  The tree is frozen precisely *because* no node has an effect; adding effects
  now would be unfreezing it by the back door. Phase 5 decides its fate.
- Sensors effects specifically need a pull-at-point-of-use mechanism first —
  see "Decisions made" above for why Radar/Scanner are different from every
  other hardpoint, not just an oversight.
- Upgrade icon art — every node shows a 2-letter glyph; the data schema
  reserves an `icon` slot per node, sized at 52% of the node diameter.
- An embedded monospace font for the HUD — the 1d spec asks for one
  (JetBrains Mono / Space Mono as a `FontFile` resource); the project ships
  no `.ttf` at all, so the HUD currently uses the engine default. Dropping a
  font in and applying it is a small, self-contained job.
- A real blur behind the cargo dropdown (`BackBufferCopy` + blur
  `ShaderMaterial`) — the spec itself calls this optional polish and
  recommends the flat fallback that's in place.
- Restyling the remaining full-screen panels (Cargo/Trade/Crafting) to match
  the newer palette — the Builder and Upgrade screens have been rebuilt
  against their own design handoffs and share `BuilderTheme`, but the other
  three still use their older look.

## Suggested next step

No specific next item has been chosen yet. Candidates on the table, most
relevant first.

**`docs/direction.md` §4 "Step 0: play the game for ten minutes" is still the
standing instruction, and it has not been done.** The loop is much thinner
than the last version anyone played, and several systems below have been
verified only by scripted `game_eval` checks. Building further on an unfelt
loop is how the upgrade tree happened.

- **Play the opening end to end.** It is the most-changed and least-played
  path in the game: five of the six control hints have never been seen firing,
  the Salvager's power-down on a completed cut changes how cutting feels, the
  salvage target is newly invulnerable, and the whole cut → tow → stow → bolt
  chain now runs through the field-attach penalty.
- **Decide what the power grid is for, before building more of it.** It is
  fully drawn and reads on nothing (see "The power grid" under "Where things
  stand"). The two live questions are whether `PowerGrid` replaces or coexists
  with the pooled `total_energy_generation()` model, and who writes
  `ModuleInstance.powered` in flight — it has to re-solve when `HullDamageModel`
  severs a conduit, which is the entire mechanic. Authoring conduit runs across
  the 17 layouts has to land in the same stretch or every enemy goes dark.
- **Finish Phase 1 step 3: persistent wrecks.** The one incomplete step of the
  phase, and the thing every "wrecks are world objects" note in
  `direction.md` §2 is written against.
- **Reconcile the conduits handoff with the Phase 4 spec.** They contradict
  each other on whether conduits should exist at all (see the top of this
  file). Cheap, and it will cost a future session real time if left.
- **Scar the parts that aren't on a hull.** Severed pieces and the builder
  grid draw their own hexes and show no damage, which undercuts the one system
  built specifically to make a part's history visible.
- **Play the field-attach trade-off.** 50% now / 70% forever are reasoned
  numbers with no play behind them; the same goes for the heavier turn-rate
  falloff on big hulls.
- **Build the pause/escape menu with the "tooltips" switch**, which is what the
  control-hint statics were written for — `ControlHint.set_enabled()` and
  `reset_seen()` are waiting. The user asked for this to be tied in
  "eventually", so it is a stated intent rather than a guess.
- **Decide whether persistent cut parts need a cap.** Slicer-cut parts no
  longer expire at all; a player who cuts a lot and collects nothing will
  accumulate them for the session. A long timer instead of none is the obvious
  alternative if it becomes clutter.
- **Look at the rebuilt screens and the HUD in motion.** The ship builder,
  the upgrade screen, the scanner instrument and the HUD were all verified by
  `game_eval` plus screenshots, but nobody has clicked or dragged through any
  of them with a real mouse — injected mouse events don't reach the viewport
  GUI in this MCP environment (see `docs/gotchas.md`). Cheap to confirm, and
  it gates further UI work. **The scanner's drag-to-aim beam bar is the most
  worth trying**, since aiming is the whole interaction.
- **Decide where the scanner panel lives.** It currently covers the radar dial
  while open, because a 388×568 instrument doesn't fit a 1152×648 HUD
  alongside everything else. Options: move it, shrink it, or hide the radar
  while it's up.
- **A real human playtest of the refactor** — four tranches reshaped the ship's
  internals and every input path, verified only by scripted checks. Fly it,
  fight something, cut a part off, build a ship, warp.
- **Commit tranche 4** if it is still uncommitted, and decide whether the
  deferred `LootTable` Resource (see tranche 3) is worth doing now.
- A real playtest pass on Radar (1800) / Scanner (3000) range and the
  scanner's beam-width / 6s-cooldown / 5-result-cap feel, now that both have
  been corrected several times by feel rather than tuned in one deliberate
  pass. The 9s full cycle in particular is the handoff's number, not a played
  one.
- Playtest the Tractor Beam's single-target pull speed/range/energy cost
  for real feel, now that it's mounted on a hex rather than always-on —
  same "corrected by feel, not one deliberate pass" caveat as Radar/Scanner.
- A pass through the Dense/Dangerous Belt region specifically with the
  current AI navigation (tightest asteroid packing, not yet re-checked).
- Audit `pirate_light_two`/`pirate_heavy_one` for the same severability
  issue `pirate_light_one` had.
- Pick up the deferred Version 0.5 gap: no Corporate/Ancient enemy ship
  exists yet.
- Have the user actually playtest current combat end-to-end for the first
  time since per-module damage/wing severance/research gating/Manufacturers
  all landed together.
- Decide whether "abandoned wrecks" should be a distinct non-station
  location (currently same as derelict stations, aside from the new
  Abandoned Ship POI).
- Populate the still-unused Electronic Signal radar category, and/or
  resource deposits/unknown structures on the Scanner side.
- Playtest the 4 new Points of Interest for real (camp difficulty, distress
  signal/wreck reward sizing, whether the reused hull/cockpit art actually
  reads well at normal play zoom, not just the screenshot pass done this
  session).
- Playtest cargo capacity/Storage module for real feel — 160 starting
  capacity, 60/module, 100 base were first-pass numbers, not tuned against
  actual play. Note the caveat: with trading and crafting frozen, material
  cargo has nowhere to go, so "does the hold fill too fast" is a question
  about the *parts* hold (`ShipHold`) now, not the material one.

Do not start any of these without the user confirming which first. **And
check any candidate against `docs/direction.md` before starting it** — this
list has outlived one change of direction already.

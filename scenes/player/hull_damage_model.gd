class_name HullDamageModel
extends Node

## Per-module hull state for one ship: each placement's own condition, which
## placements are destroyed, severed or regrowing, and the collision shape each
## one contributes to the ship's body.
##
## Deliberately separate from the ship's overall Health pool — a module can be
## individually knocked out mid-fight without that being a second way to destroy
## the ship. This script owns that parallel model end to end (damage
## resolution, connectivity/detachment, passive regrowth, paid repair); ship.gd
## previously interleaved all of it with flight, energy and hardpoint code.
##
## Reports back to the ship through three signals rather than reaching for its
## Health node, so the ship stays the only thing that decides how its own health
## pool moves.

## Something changed that affects the ship's derived stats — a module was
## destroyed, severed or finished repairing. The ship re-sums thrust from
## whatever is still alive.
signal modules_changed
## A regrowing/repaired module restored this much condition; the ship's overall
## Health pool follows it up.
signal hull_healed(amount: float)
## Nothing functional is left (the Command Core is gone, or every module is).
## The ship finishes itself off.
signal hull_lost

## Fraction of a hit's damage that also lands on the modules directly adjacent
## to the exact hex hit. Landing a hit on precisely the same hex repeatedly
## (needed to break a specific module) is hard against a moving, rotating
## target; without this, focused fire on a wing feels like it does nothing until
## one lucky hit lines up exactly right.
##
## Deliberately tiny. At the 0.35 this ran at, a hit anywhere near a module took
## a third of its condition off too, so damage spread across a hull far faster
## than anything was actually being aimed at and modules died without ever being
## hit. It is kept non-zero only so that repeated fire in one area still nudges
## its surroundings; hitting a specific module is now genuinely a matter of
## hitting it.
@export var splash_fraction: float = 0.03

## Seconds the ship must go without taking any damage before holed-out modules
## start regrowing. Prevents repair from meaningfully undoing damage mid-fight —
## it's a recovery mechanic for between engagements, not a heal button under
## fire.
@export var repair_delay: float = 6.0
## Condition/second restored to a regrowing module once it's eligible.
@export var repair_rate: float = 6.0
## Passive regrowth brings a holed-out module back to this fraction of its max
## condition. Was 0.4, with the remainder sold for credits at the station; that
## was the only paid repair in the game, and freezing the trade screen (Phase 0a,
## see docs/frozen_systems.md) would otherwise have left the hull permanently
## capped at 40%. Detached modules are still gone for good — the jeopardy lives
## in losing the part, not in a repair bill.
@export var passive_repair_cap_fraction: float = 1.0

## Integrity permanently lost when a part absorbs damage equal to its entire
## condition pool (see ModuleInstance.integrity). Deliberately slow: at this rate
## a module has to be shot to pieces around six times over before it bottoms out,
## so wear accumulates across a campaign rather than across one fight. It is the
## dial that decides how badly the player needs fresh parts.
@export var integrity_loss_per_full_hit: float = 0.1

## Whether this hull patches up its own chip damage. False for a derelict: a
## wreck that has been adrift for years does not knit itself back together, and —
## the reason this exists — passive repair otherwise heals a deliberately damaged
## part back above HullPaint.CUTTABLE_CONDITION a few seconds after it spawns,
## which silently removes the cut-ready marker and makes the part uncuttable.
##
## Holed-out modules regrow regardless (see _regenerate_modules). This used to
## gate that too, which meant every stray shot and every slipped cut left a
## permanent hole in the one hull the player is meant to practise cutting on —
## a tutorial wreck accumulating damage it can never shed.
@export var regenerates: bool = true

var _ship: Ship
var _bank: HardpointBank
var _wreckage: WreckageSpawner
var _layout: ShipLayout
var _renderer: ShipLayoutRenderer
var _health_multiplier: float = 1.0
## True only for the duration of a Slicer's damage_beam() call, so any part that
## comes loose during it is recovered whole rather than rolled for.
var _clean_cut_active: bool = false

## Condition is no longer stored here at all: it lives on the ModuleInstance
## mounted at each placement (see ModuleInstance.condition_fraction), so a
## module's damage belongs to the part rather than to the hull's bookkeeping and
## survives a refit. This model still owns everything below, which is genuinely
## about *this hull*: what is severed from it, what is regrowing into it, and
## which collision shapes it contributes.
##
## That only works because each ship owns its own copy of its ShipLayout — the
## .tres is shared across every instance of a scene that exports it, so Ship
## deep-duplicates it before applying (see Ship._ready).

## placement_id -> true. A module ends up here when it's still intact but has
## lost its connection back to the core (see _check_for_detachment) — distinct
## from its condition reaching zero, which means the module itself was destroyed
## outright. Either way counts as "gone" (see is_destroyed).
var _detached: Dictionary = {}

## placement_id -> true. A holed-out module regrowing stays here — and counts as
## destroyed for every gameplay purpose — for its whole climb back to full
## condition, not just while condition is at zero. Without this, is_destroyed
## would flip back to false (restoring fire/thrust) the instant condition ticked
## above zero, and a multi-hex hole's neighbors would all unlock on top of each
## other in the same frame instead of visibly sweeping outward.
var _regrowing: Dictionary = {}

## placement_id -> Array[CollisionPolygon2D], so a destroyed or detached
## module's hitbox can be removed from the ship's body along with its visual.
var _shapes_by_placement: Dictionary = {}
var _shapes: Array[CollisionPolygon2D] = []

var _time_since_last_damage: float = 0.0


func configure(ship: Ship, bank: HardpointBank, wreckage: WreckageSpawner) -> void:
	_ship = ship
	_bank = bank
	_wreckage = wreckage


## Rebinds this model to a freshly applied layout: severance and regrowth
## bookkeeping starts clean and collision shapes are respawned, but module
## condition is deliberately *not* reset — it belongs to the mounted parts and
## comes in with them. A module that was holed out before the refit is still a
## hole afterwards, and picks its regrowth back up where it left off.
func rebuild(layout: ShipLayout, renderer: ShipLayoutRenderer, health_multiplier: float) -> void:
	_layout = layout
	_renderer = renderer
	_health_multiplier = health_multiplier

	_detached.clear()
	_regrowing.clear()

	for shape in _shapes:
		shape.queue_free()
	_shapes.clear()
	_shapes_by_placement.clear()

	for placement in layout.placements:
		# A layout authored in the editor has no instances until something needs
		# one; every mounted module needs one now, since that's where its
		# condition is kept.
		placement.ensure_instance()
		if _condition_of(placement) > 0.0:
			_spawn_collision_shape_for(placement)
		else:
			_regrowing[placement.placement_id] = true
			_renderer.set_module_destroyed(placement.placement_id)


## Hardpoint visuals are rebuilt *after* this model is (see
## Ship._apply_ship_layout), so a weapon module that arrived already holed out
## has to have its gun hidden once the bank exists — otherwise a refit puts the
## turret art back on top of a hex that renders as a hole.
func sync_hardpoint_visuals() -> void:
	if _layout == null:
		return
	for placement in _layout.placements:
		if is_destroyed(placement.placement_id):
			_bank.set_visual_visible(placement.placement_id, false)


func get_condition(placement_id: String) -> float:
	if _layout == null:
		return 0.0
	var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
	return _condition_of(placement) if placement != null else 0.0


## Absolute condition points for a placement, derived from the fraction its
## mounted part carries. A placement with no instance has already handed its
## part over to the wreckage (see _detach_module) and counts as gone.
func _condition_of(placement: ModulePlacement) -> float:
	if placement.instance == null:
		return 0.0
	return placement.instance.condition_fraction * _max_condition_of(placement)


func _max_condition_of(placement: ModulePlacement) -> float:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	return module_type.health_contribution * _health_multiplier if module_type != null else 0.0


## The one place absolute condition points are converted back to the part's own
## fraction. Silently does nothing for a placement whose part has left.
func _set_condition(placement: ModulePlacement, value: float) -> void:
	if placement.instance == null:
		return
	var was_cuttable: bool = HullPaint.is_cuttable(placement.instance)
	var previous_scar_tier: int = HullPaint.scar_tier(placement.instance)
	var previous_efficiency_step: int = _efficiency_step(placement)
	var max_condition: float = _max_condition_of(placement)
	# Clamped to integrity rather than to 1.0, in the one place condition is
	# written, so no repair path anywhere can put a part back above what it has
	# permanently left.
	placement.instance.condition_fraction = clampf(value / max_condition, 0.0,
		placement.instance.integrity) if max_condition > 0.0 else 0.0

	# The hull only redraws when its layout changes, but the cut-ready marker and
	# the scar tier both depend on condition — without this they would not appear
	# until something else happened to force a redraw, which for a part shot down
	# mid-fight could be never.
	if _renderer != null and (was_cuttable != HullPaint.is_cuttable(placement.instance)
			or previous_scar_tier != HullPaint.scar_tier(placement.instance)):
		_renderer.queue_redraw()

	# Thrust and the energy pool are derived from how well each part is working
	# (see ModuleInstance.efficiency), so wear has to reach them as it happens
	# rather than only when something is destroyed outright.
	if _efficiency_step(placement) != previous_efficiency_step:
		modules_changed.emit()


## Efficiency quantised into coarse steps. The stats derived from it are re-summed
## across every placement on the ship, and condition moves on almost every frame
## of sustained fire — announcing each individual point of damage would re-derive
## the whole hull dozens of times a second for changes far too small to feel.
func _efficiency_step(placement: ModulePlacement) -> int:
	if placement.instance == null:
		return 0
	return int(placement.instance.efficiency() * EFFICIENCY_STEPS)


## Number of bands efficiency is reported in. Twenty gives 5% granularity, which
## is finer than the part card's own rounding.
const EFFICIENCY_STEPS: float = 20.0


## True if the module is either destroyed outright (condition at zero), still
## intact but severed from the core's connectivity graph, or mid-regrowth — all
## three mean it no longer contributes to the ship.
func is_destroyed(placement_id: String) -> bool:
	if _detached.has(placement_id) or _regrowing.has(placement_id):
		return true
	return get_condition(placement_id) <= 0.0


## Restarts the repair delay. Called by the ship on every hit to its Health
## pool, including hits that never resolve to a specific module.
func note_damage_taken() -> void:
	_time_since_last_damage = 0.0


func process(delta: float) -> void:
	_time_since_last_damage += delta
	_regenerate_modules(delta)


func get_max_condition(placement_id: String) -> float:
	var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
	return _max_condition_of(placement) if placement != null else 0.0


# --- Damage resolution -------------------------------------------------------

## Resolves a world-space impact point to the specific module occupying that hex
## cell (if any) and damages it, plus a splash fraction to its immediate
## neighbors. Destroying an engine this way costs the ship real thrust;
## destroying a weapon/missile hardpoint stops it firing — both react live, no
## rebuild needed.
func damage_at(amount: float, impact_point: Vector2) -> void:
	if _layout == null:
		return

	var hex_coord: Vector2i = _to_hex(_ship.to_local(impact_point))
	var placement: ModulePlacement = _layout.get_placement_at(hex_coord)
	if placement != null:
		_apply(placement, amount)

	for neighbor_coord in HexUtils.neighbors(hex_coord):
		var neighbor: ModulePlacement = _layout.get_placement_at(neighbor_coord)
		# The Core is exempt from splash: it ends the ship outright if lost, so
		# it shouldn't be catchable in crossfire aimed at whatever else happens
		# to be clustered around it — only a hit landing squarely on it counts.
		if neighbor != null and neighbor != placement and neighbor.placement_id != _layout.core_placement_id:
			_apply(neighbor, amount * splash_fraction)


## Fired by HardpointPhaseLance: unlike a normal hit (one hex + a splash
## fraction to its neighbors), a beam pierces straight through the hull, applying
## the full amount to every module hex it crosses from entry_point onward along
## aim_direction — including the Command Core, which splash damage deliberately
## never reaches. That's the point of this weapon: a well-aligned shot can punch
## through armor into whatever sits directly behind it.
## A Slicer's cut: exactly one part, the one under the beam's contact point. No
## splash onto neighbours and no travel through the hull behind it.
##
## Deliberately NOT damage_beam(). Routing the Slicer through the piercing beam
## meant a cut carried on through the ship along the aim direction and destroyed
## whatever happened to line up behind the cell being cut — parts at the far side
## of a hull dying without ever being touched. A cutting tool acts where it makes
## contact and nowhere else; piercing is the Phase Lance's trick, not this one.
##
## Anything that loses its path to the core as a result is severed intact rather
## than rolled for, same as before.
## `band_fraction` is how much of the cuttable band (the last
## HullPaint.CUTTABLE_CONDITION of a part's condition) to consume this call —
## NOT an absolute damage figure.
##
## Expressed that way so a cut takes the same wall-clock time on every part. A
## flat damage rate meant a 40-condition gun came off three times faster than a
## 150-condition spar, which made the tool's timing a property of whatever you
## happened to be pointing at rather than something the player could learn.
##
## Returns {"result": "cut"|"intact"|"miss", "progress": 0..1} — progress being
## how far through the band the part now is, so the tool can show the cut
## advancing (see HardpointSlicer).
func damage_cut(band_fraction: float, impact_point: Vector2, aim_direction: Vector2) -> Dictionary:
	if _layout == null:
		return {"result": "miss", "progress": 0.0}

	var placement: ModulePlacement = _placement_under_contact(impact_point, aim_direction)
	if placement == null:
		return {"result": "miss", "progress": 0.0}

	# A part still in good condition cannot simply be cut away — the Slicer opens
	# a seam that damage has already started. Without this the beam alone took
	# any part off any hull, and weapons had no role in salvage at all.
	# An immune part reports "intact" rather than silently absorbing the beam, so
	# the tool gives its usual "this cannot be opened" feedback instead of looking
	# broken (see HardpointSlicer.INTACT_BEAM_FADE).
	if not _is_cuttable_cell(placement):
		return {"result": "intact", "progress": 0.0}

	_clean_cut_active = true
	_apply(placement, band_fraction * _max_condition_of(placement) * HullPaint.CUTTABLE_CONDITION)
	_clean_cut_active = false
	# "severed" is the finishing frame — the part has come apart and there is
	# nothing left here to cut. Reported separately from "cut" so the Slicer can
	# draw its beam back in on completion rather than carrying straight on into
	# whatever is behind the hole it just made.
	if is_destroyed(placement.placement_id):
		return {"result": "severed", "progress": 1.0}
	return {"result": "cut", "progress": cut_progress_of(placement)}


## The single hex cell the beam is touching, described in world space, so a
## cutting effect can trace that cell's own outline rather than guessing at the
## geometry from the raycast point alone.
##
## Returns {} when the contact does not land on an occupied cell. Uses the same
## step-half-a-cell-inward trick as _placement_under_contact, and for the same
## reason: a raycast stops on the outer surface, which rounds to the cell outside
## the hull as often as the one inside it.
##
## Reports the *cell*, not the placement: a three-hex spar is one placement but
## the beam is cutting around one hex of it.
func cut_cell_at(impact_point: Vector2, aim_direction: Vector2) -> Dictionary:
	if _layout == null or _renderer == null:
		return {}
	var local_point: Vector2 = _ship.to_local(impact_point)
	var coord: Vector2i = _to_hex(local_point)
	if not _layout.is_occupied(coord) and aim_direction.length() > 0.001:
		var inward: Vector2 = aim_direction.normalized().rotated(-_ship.global_rotation)
		coord = _to_hex(local_point + inward * _renderer.cell_size * 0.5)
	return _describe_cell(coord)


## The same description as cut_cell_at, for a cell already chosen. A cutting beam
## resolves the cell once when it locks on and then asks for it by coordinate
## every frame after: re-resolving from the contact point each frame made the
## lock flicker between neighbouring cells as the two hulls drifted, and the ramp
## never got past its first frame.
##
## Empty once that cell is no longer part of the hull.
func cell_geometry(coord: Vector2i) -> Dictionary:
	return _describe_cell(coord)


## One hex cell, described in every space the cutting effect needs it in.
##
## `corners_hull` are that cell's outline **exactly as the renderer draws it** —
## same jitter, same part offset and rotation — expressed in the hull renderer's
## own local space, which is where a cut seam is parented. `corners` is the same
## outline in world space, for the beam's contact point.
##
## Both are returned rather than letting the caller rebuild the hexagon from
## `center`/`radius`/`rotation`: the renderer's node carries a fixed 90° rotation
## that `center_local` already has folded in, so reconstructing corners outside
## this class applied that rotation a second time and swung every cell off its
## true position by an amount that grew with its distance from the hull's origin.
func _describe_cell(coord: Vector2i) -> Dictionary:
	if _layout == null or _renderer == null:
		return {}
	var placement: ModulePlacement = _layout.get_placement_at(coord)
	if placement == null:
		return {}

	var cell_size: float = _renderer.cell_size
	var corners_hull: PackedVector2Array = HullPaint.jittered_corners(
		HexUtils.hex_corners(HexUtils.axial_to_pixel(coord, cell_size), cell_size),
		HullPaint.part_centroid(_layout, placement, cell_size),
		HullPaint.part_offset(placement.instance, cell_size),
		HullPaint.part_rotation(placement.instance))
	var corners_world := PackedVector2Array()
	for corner in corners_hull:
		corners_world.append(_ship.to_global(corner.rotated(_renderer.rotation)))

	# axial_to_pixel works in un-rotated hull space; the renderer's own fixed
	# rotation has to be put back to land in ship-local space.
	var center_local: Vector2 = HexUtils.axial_to_pixel(coord, cell_size) \
		.rotated(_renderer.rotation)
	return {
		"coord": coord,
		"center_local": center_local,
		"center": _ship.to_global(center_local),
		"radius": cell_size,
		"rotation": _renderer.rotation + _ship.global_rotation,
		"corners_hull": corners_hull,
		"corners": corners_world,
		# Whether the beam may lock here at all. Matches the cut-ready marker the
		# renderer draws (destroyed cells are holes, not parts waiting to be cut),
		# so the tool can only lock onto something the hull is visibly offering.
		"cuttable": _is_cuttable_cell(placement),
	}


## Whether the Slicer is allowed to open this part.
##
## The Command Core is excluded outright. Losing it emits hull_lost and ends the
## ship (see _on_module_destroyed), which the Slicer must never be able to cause:
## it is a dismantling tool, not a weapon, and a cut that destroys the ship also
## destroys everything still bolted to it — including whatever the player was
## trying to salvage. Measured before this guard: a Core already shot into the
## cuttable band could be cut straight through, and the target simply exploded.
func _is_cuttable_cell(placement: ModulePlacement) -> bool:
	if placement.placement_id == _layout.core_placement_id:
		return false
	if is_destroyed(placement.placement_id):
		return false
	return HullPaint.is_cuttable(placement.instance)


## How far through the cuttable band a part is: 0 the moment it becomes
## cuttable, 1 when it comes apart.
func cut_progress_of(placement: ModulePlacement) -> float:
	if placement == null or placement.instance == null:
		return 1.0
	return clampf(1.0 - placement.instance.condition_fraction / HullPaint.CUTTABLE_CONDITION, 0.0, 1.0)


## Which part the beam is actually touching.
##
## A raycast stops on the *outer surface* of a collision shape, and that point
## sits exactly on the hex boundary — so rounding it straight to a cell lands
## outside the hull as often as inside. Measured: only 40% of contact points
## resolved to an occupied cell, meaning 60% of a held beam's frames silently did
## nothing and the cut took roughly two and a half times longer than its damage
## rate implied. Stepping half a cell along the beam puts the sample inside the
## cell that was hit; the raw point is kept as a fallback for a graze that steps
## straight back out again.
func _placement_under_contact(impact_point: Vector2, aim_direction: Vector2) -> ModulePlacement:
	var local_point: Vector2 = _ship.to_local(impact_point)
	if aim_direction.length() > 0.001:
		var inward: Vector2 = aim_direction.normalized().rotated(-_ship.global_rotation)
		var stepped: ModulePlacement = _layout.get_placement_at(
			_to_hex(local_point + inward * _renderer.cell_size * 0.5))
		if stepped != null:
			return stepped
	return _layout.get_placement_at(_to_hex(local_point))


## `clean_cut` marks this beam as a deliberate severing pass (HardpointSlicer)
## rather than a weapon hit. It changes nothing about the damage — only what
## happens to whatever falls off as a result: see _detach_module. Held as state
## for the duration of the call because the detachment it causes happens several
## frames' worth of call stack down (_apply -> _on_module_destroyed ->
## _check_for_detachment -> _detach_module) and threading a parameter through all
## of that would put a slicer-shaped argument on four unrelated functions.
func damage_beam(amount: float, entry_point: Vector2, aim_direction: Vector2,
		max_travel_distance: float, clean_cut: bool = false) -> void:
	if _layout == null or aim_direction.length() < 0.001:
		return

	_clean_cut_active = clean_cut

	var origin: Vector2 = _ship.to_local(entry_point).rotated(-_renderer.rotation)
	var direction: Vector2 = aim_direction.rotated(-_ship.global_rotation - _renderer.rotation).normalized()

	# A zero cell_size would make the sampling loop below never advance.
	var step: float = _renderer.cell_size * 0.5
	if step <= 0.0:
		return

	var traveled: float = 0.0
	var already_hit: Dictionary = {}
	while traveled <= max_travel_distance:
		var hex_coord: Vector2i = HexUtils.pixel_to_axial(origin + direction * traveled, _renderer.cell_size)
		var placement: ModulePlacement = _layout.get_placement_at(hex_coord)
		if placement != null and not already_hit.has(placement.placement_id):
			already_hit[placement.placement_id] = true
			_apply(placement, amount)
		traveled += step

	_clean_cut_active = false


## Entry point for a hardpoint to damage its own mount (e.g. a Black Market
## Foundry weapon backfiring) — reuses the exact same pathway a normal hit uses,
## so a bad enough malfunction streak can genuinely sever the weapon's own module.
func damage_placement(placement_id: String, amount: float) -> void:
	var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
	if placement != null:
		_apply(placement, amount)


func _to_hex(ship_local_point: Vector2) -> Vector2i:
	return HexUtils.pixel_to_axial(ship_local_point.rotated(-_renderer.rotation), _renderer.cell_size)


func _apply(placement: ModulePlacement, amount: float) -> void:
	if is_destroyed(placement.placement_id):
		return
	# The one blanket exemption: a part marked damage_immune absorbs nothing at
	# all, from any source. Checked here rather than at each call site so weapon
	# fire, splash and the Slicer are covered by one rule.
	if placement.instance != null and placement.instance.damage_immune:
		return
	# Damage to a module restarts the repair delay in its own right, not just
	# damage that reaches the Health pool. The Slicer deliberately never touches
	# Health, so without this a hull quietly regrew throughout a cut — and at a
	# ten-second cut rate the regrowth is faster than the cutting, so a part could
	# never be severed at all no matter how long the beam was held.
	note_damage_taken()
	# Fresh hits glow (see HullScarLayer). Lit here rather than off the condition
	# change, because this is the only place that knows a hit landed at all — a
	# graze that barely moves condition still leaves hot metal.
	if _renderer != null:
		_renderer.flash_module_damage(placement.placement_id)
	var current: float = _condition_of(placement)
	var remaining: float = maxf(current - amount, 0.0)
	# Charged on what the part actually absorbed, not on what was aimed at it: an
	# overkill hit (the battleground wrecks its hulls with 99999) must not count as
	# a thousand fights' worth of wear.
	_wear_integrity(placement, current - remaining)
	_set_condition(placement, remaining)
	if remaining <= 0.0:
		_on_module_destroyed(placement)


## Takes a permanent bite out of what this part can ever be repaired back to.
## Never restored anywhere — that is the whole point (see ModuleInstance.integrity).
func _wear_integrity(placement: ModulePlacement, absorbed: float) -> void:
	if placement.instance == null or absorbed <= 0.0:
		return
	var max_condition: float = _max_condition_of(placement)
	if max_condition <= 0.0:
		return
	placement.instance.integrity = maxf(
		placement.instance.integrity - (absorbed / max_condition) * integrity_loss_per_full_hit,
		ModuleInstance.MINIMUM_INTEGRITY)


func _on_module_destroyed(placement: ModulePlacement) -> void:
	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	_renderer.set_module_destroyed(placement.placement_id)
	# A destroyed hex is a hole, not still-solid wreckage — without this, a
	# scorched module keeps blocking incoming shots aimed at whatever's behind
	# it (e.g. the connector further along a wing), which made severing a wing
	# much harder than intended.
	_free_collision_shapes_for(placement.placement_id)
	_bank.set_visual_visible(placement.placement_id, false)

	# Losing the Core ends the ship outright: without it there's no anchor left
	# to measure "still connected" against, so detachment checks would otherwise
	# go permanently inert and leftover modules would sit attached to a dead,
	# driverless hulk forever (see find_unreachable_from_core).
	if placement.placement_id == _layout.core_placement_id:
		hull_lost.emit()
		return

	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()

	_check_for_detachment()
	_check_all_modules_gone()


## The overall Health pool and per-module condition are deliberately separate,
## but splash damage lets modules collectively take more cumulative damage than
## Health ever registers, since a splash hit only affects modules. Without this,
## a ship can end up with every module destroyed/detached — visually a dead hulk
## — while Health still has some left and the ship keeps flying and fighting.
func _check_all_modules_gone() -> void:
	if _layout == null or _layout.placements.is_empty():
		return
	for placement in _layout.placements:
		if not is_destroyed(placement.placement_id):
			return
	hull_lost.emit()


## After any module is destroyed outright, some other still-intact modules may
## no longer have a path back to the core through adjacent modules — a wing
## losing the one piece connecting it to the hull, for example. Any such module
## is severed for good: it stops contributing and flies off as its own debris.
func _check_for_detachment() -> void:
	if _layout == null:
		return

	var gone: Dictionary = {}
	for placement in _layout.placements:
		if is_destroyed(placement.placement_id):
			gone[placement.placement_id] = true

	var newly_unreachable: Array[String] = _layout.find_unreachable_from_core(gone)
	if newly_unreachable.is_empty():
		return

	_wreckage.spawn_seam_sparks(newly_unreachable)
	for placement_id in newly_unreachable:
		_detach_module(_layout.get_placement_by_id(placement_id))


func _detach_module(placement: ModulePlacement) -> void:
	if placement == null or _detached.has(placement.placement_id):
		return
	_detached[placement.placement_id] = true

	var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
	if module_type == null:
		return

	# Re-summing every live module (rather than subtracting this one's share)
	# means it doesn't matter whether this module already lost its contribution
	# in _on_module_destroyed or is detaching while still intact.
	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()

	_renderer.set_module_detached(placement.placement_id)
	_free_collision_shapes_for(placement.placement_id)
	_bank.set_visual_visible(placement.placement_id, false)

	# The part is physically off the hull now, so this placement stops owning
	# it: the wreckage either turns it into a recoverable CapturedTechPart or
	# lets it go with the debris. Handing over the object rather than a copy is
	# the point — recovering it recovers *this* module, wear and all — and
	# clearing the reference is what stops the same instance existing twice.
	var instance: ModuleInstance = placement.instance
	placement.instance = null
	_wreckage.spawn_severed_piece(placement, module_type, instance, _clean_cut_active)


# --- Repair ------------------------------------------------------------------

## Regrows holed-out (destroyed but still attached) modules over time, one ring
## at a time outward from whatever's still healthy — a module can only *start*
## regrowing once it has a neighbor that isn't itself destroyed (or already
## mid-regrow), and it stays non-functional for its whole climb back to full
## condition, so a multi-hex hole visibly sweeps outward from the healthy edge
## inward rather than every hex in it popping back at once. Detached modules are
## excluded entirely — a piece that's already flown off has nothing to grow onto.
##
## Growing a hole shut is deliberately NOT gated on `regenerates`; only topping
## up chip damage is. The two are different promises: a hull that never closes its
## holes accumulates every stray shot forever, while a hull that heals chip damage
## also heals away the cut-ready marker the Slicer depends on.
func _regenerate_modules(delta: float) -> void:
	if _layout == null or _time_since_last_damage < repair_delay:
		return

	for placement in _layout.placements:
		if _detached.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var max_condition: float = _max_condition_of(placement)
		if not _regrowing.has(placement.placement_id):
			if _condition_of(placement) > 0.0:
				# Chip damage: still working, so it heals in place and must not
				# enter _regrowing, which would switch it off and respawn a
				# collision shape it never lost. (Topping these up used to be the
				# station's paid repair; that screen is frozen — Phase 0a.)
				if regenerates:
					_advance_repair(placement, module_type, max_condition, delta, false)
				continue
			if not _has_healthy_neighbor(placement):
				continue # nothing healthy adjacent yet to grow back from
			_regrowing[placement.placement_id] = true

		_advance_repair(placement, module_type, max_condition, delta, true)


func _has_healthy_neighbor(placement: ModulePlacement) -> bool:
	for cell in _layout.get_occupied_cells(placement):
		for neighbor_coord in HexUtils.neighbors(cell):
			var neighbor: ModulePlacement = _layout.get_placement_at(neighbor_coord)
			if neighbor != null and not is_destroyed(neighbor.placement_id):
				return true
	return false


## `was_regrowing` distinguishes a module climbing back from zero — which is
## switched off for the whole climb and has to be brought back online at the top
## — from one that only took chip damage and never stopped working.
func _advance_repair(placement: ModulePlacement, module_type: ModuleType, max_condition: float, delta: float, was_regrowing: bool) -> void:
	# Repair chases the part's remaining integrity, not its original rating — a
	# worn part patches up to being as good as it still gets, not as good as new.
	var passive_cap: float = max_condition * minf(passive_repair_cap_fraction,
		placement.instance.integrity if placement.instance != null else 1.0)
	var current_condition: float = _condition_of(placement)
	if current_condition >= passive_cap:
		return

	var new_condition: float = minf(current_condition + repair_rate * delta, passive_cap)
	_set_condition(placement, new_condition)
	hull_healed.emit(new_condition - current_condition)

	if was_regrowing and new_condition >= passive_cap:
		_regrowing.erase(placement.placement_id)
		_on_module_repaired(placement, module_type)


## Paid station repair: tops every attached module back to full condition
## (bypassing passive_repair_cap_fraction). Detached (severed) modules are
## excluded — they're gone, not repairable in place. The caller heals the
## overall Health pool afterwards.
func repair_fully() -> void:
	if _layout == null:
		return

	for placement in _layout.placements:
		if _detached.has(placement.placement_id):
			continue

		var module_type: ModuleType = ModuleCatalog.get_by_id(placement.module_type_id)
		if module_type == null:
			continue

		var max_condition: float = _max_condition_of(placement)
		if _condition_of(placement) >= max_condition:
			continue

		var was_regrowing: bool = _regrowing.has(placement.placement_id)
		_set_condition(placement, max_condition)
		if was_regrowing:
			_regrowing.erase(placement.placement_id)
			_on_module_repaired(placement, module_type)


## Reverses _on_module_destroyed's effects once a holed-out module finishes
## regrowing to its passive cap (or is topped off by a paid repair): restores its
## stat contribution, collision shape and normal hull appearance all at once
## (firing and thrust all gate on is_destroyed, which only reads false once this
## runs — see _regrowing).
func _on_module_repaired(placement: ModulePlacement, module_type: ModuleType) -> void:
	_renderer.set_module_repaired(placement.placement_id)
	_spawn_collision_shape_for(placement)
	_bank.set_visual_visible(placement.placement_id, true)

	if module_type.thrust_contribution > 0.0:
		modules_changed.emit()


# --- Collision shapes --------------------------------------------------------
# Parented to the ship's CharacterBody2D itself, not to this node: the physics
# server only picks up shapes that are direct children of the body.

func _spawn_collision_shape_for(placement: ModulePlacement) -> void:
	var shapes_for_placement: Array = []
	for cell in _layout.get_occupied_cells(placement):
		var shape := CollisionPolygon2D.new()
		shape.polygon = HexUtils.hex_corners(Vector2.ZERO, _renderer.cell_size)
		shape.position = HexUtils.axial_to_pixel(cell, _renderer.cell_size).rotated(_renderer.rotation)
		_ship.add_child(shape)
		_shapes.append(shape)
		shapes_for_placement.append(shape)
	_shapes_by_placement[placement.placement_id] = shapes_for_placement


func _free_collision_shapes_for(placement_id: String) -> void:
	for shape in _shapes_by_placement.get(placement_id, []):
		_shapes.erase(shape)
		shape.queue_free()
	_shapes_by_placement.erase(placement_id)

class_name IntroDirector
extends Node

## Runs the opening: the player starts in the ship builder, flies out into empty
## space, is told something large is out there, and is then left to find it and
## take a piece off it.
##
## The beats are driven by the voice clips rather than by a script of timers —
## each one waits for its clip to finish before the next thing happens, so the
## sequence stays in step with audio that has not been recorded yet and can
## change length freely. With no clip assigned, each beat falls back to a fixed
## delay so the whole thing still runs end to end.
##
## Deliberately a director rather than logic spread across the scene: it is the
## only script that knows the opening is an opening, and deleting it leaves a
## perfectly ordinary region behind.

signal contact_spawned(contact: Node2D)

## DONE is a real beat rather than the absence of one: the opening ends when the
## player has taken the part, and after that the director must stop pointing at
## things. A marker still hanging off the screen edge is the sequence refusing to
## admit it is over.
enum Beat { BUILDER, OPENING, EXPLORING, CONTACT_CALL, FOUND, FITTING, AMBUSH, DONE }

## Wired in the scene rather than looked up by name, so moving either node is a
## visible edit instead of a silent break. setup() is the alternative path, for
## a test that builds the sequence without a scene around it.
@export var builder_path: NodePath
@export var marker_path: NodePath

@export var colossus_scene: PackedScene = preload("res://scenes/world/colossus.tscn")
@export var battleground_scene: PackedScene = preload("res://scenes/world/battleground.tscn")

## The tutorial script, one array per beat. Named for the beat rather than for
## the file, so re-cutting a line or adding a third to a pair is an edit here and
## nowhere else.
##
## These replace the single `opening_voice`/`contact_voice` slots this script
## shipped with: both were always null placeholders waiting for exactly these
## recordings, and a beat turned out to need several lines rather than one.
@export var boot_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/start_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Boot_01_space.wav"),
]
## Spoken over the ship builder while the player has it open.
@export var build_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Build_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Build_02_space.wav"),
]
## The moment they close the builder and are actually flying.
@export var launch_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Launch_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Launch_02_space.wav"),
]
## "Large ship detected" — the derelict does not exist in the world until these
## have finished playing, so the player never sees it arrive.
@export var scan_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Scan_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Scan_02_space.wav"),
]
## On arriving at the wreck field.
@export var graveyard_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Graveyard_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Graveyard_02_space.wav"),
]
## The cutting lesson, once they are close enough to the target hull to act on it.
@export var salvage_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Salvage_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Salvage_02_space.wav"),
	preload("res://audio/voice lines/Tutorial/Salvage_03_space.wav"),
]
## Once the salvaged gun is bolted onto their own hull.
@export var weapon_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Weapon_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Weapon_02_space.wav"),
]
## The raiders arriving.
@export var pirate_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Pirates_01_space.wav"),
	preload("res://audio/voice lines/Tutorial/Pirates_02_space.wav"),
	preload("res://audio/voice lines/Tutorial/Pirates_03_space.wav"),
]
## Held back until a raider is actually in the fight, rather than stacked onto
## the arrival lines — it is a reaction to being engaged, not to being spotted.
@export var combat_lines: Array[AudioStream] = [
	preload("res://audio/voice lines/Tutorial/Combat_01_space.wav"),
]
@export var voice_volume_db: float = -2.0

## How near the Colossus the player has to get for the graveyard lines, as a
## multiple of its own radius, so rescaling the art cannot leave the cue firing
## from half a region away.
@export var graveyard_cue_radius_scale: float = 1.6
## How near the target hull the salvage lesson waits for. Close enough that the
## thing being described is plainly on screen.
@export var salvage_cue_distance: float = 1400.0
## How near a raider has to be before the combat line plays.
@export var combat_cue_distance: float = 900.0

## Fallback length for any beat whose clip is missing.
@export var silent_beat_seconds: float = 4.0
## Free flight between the opening line and the contact call — long enough to
## have found the controls, short enough that nothing has gone stale.
@export var explore_seconds: float = 22.0

## How far out the derelict is placed, measured from the edge of its own hull
## rather than from its centre. That distinction is the whole fix for a real bug:
## the hull's radius grew past the spawn distance, so the "distant contact" was
## being placed with the player already inside it.
@export var contact_clearance: Vector2 = Vector2(2600.0, 4200.0)

## How close the player has to get before the marker stops pointing at the
## Colossus and starts pointing at the one wreck they are meant to cut. Without
## this hand-off the marker does its job perfectly and then abandons the player
## in a field of two dozen identical-looking hulls.
@export var arm_handoff_distance: float = 7000.0

## Bolting the part on is what draws attention — not cutting it off. Fitting it is
## the moment the player has finished the whole loop and is sitting in a ship they
## just improved, which is the right moment to be asked to defend it; jumping them
## mid-cut only interrupted the lesson.
##
## The squad that answers is
## deliberately feeble — the lesson is "salvage is worth defending", not "here is
## a real fight" — and it exists mostly so the player gets a second, unscripted
## chance to cut something free, this time off a hull that is shooting back.
@export var ambush_scene: PackedScene = preload("res://scenes/enemies/pirate_light_one.tscn")
@export var ambush_count: int = 3
## Grace period between the part going on and the raiders arriving — long enough
## to close the builder and get oriented, short enough to still read as a
## consequence of what was just done.
@export var ambush_delay: float = 10.0
## Multiplies the raiders' usual health. Low: these are meant to come apart.
@export var ambush_health_multiplier: float = 0.45
## Spawned this far out — off screen, so they are seen arriving rather than
## appearing. Their detection range is widened to match (see _ambush_personality),
## since a pirate that spawns outside its own detection range just sits there.
@export var ambush_distance: Vector2 = Vector2(1500.0, 2100.0)

var _beat: Beat = Beat.BUILDER
var _timer: float = 0.0
var _builder: GamePanel
var _marker: ContactMarker
var _voice: VoiceDirector
var _contact: Node2D
var _salvage_ship: Node2D
var _field: Battleground
var _ambushers: Array = []
## Cues that fire on proximity rather than on a beat change, each once.
var _said_graveyard: bool = false
var _said_salvage: bool = false
var _said_combat: bool = false
## Whether the current beat had any dialogue at all, so _beat_finished can tell
## "the lines have finished" from "there were never any lines".
var _spoken_this_beat: bool = false


func setup(builder: GamePanel, marker: ContactMarker) -> void:
	_builder = builder
	_marker = marker


func _ready() -> void:
	if _builder == null and not builder_path.is_empty():
		_builder = get_node_or_null(builder_path)
	if _marker == null and not marker_path.is_empty():
		_marker = get_node_or_null(marker_path)

	_voice = VoiceDirector.new()
	_voice.line_volume_db = voice_volume_db
	add_child(_voice)
	# Deferred so every node in the scene — the builder included — has run its
	# own _ready before the opening tries to drive them.
	_open_builder.call_deferred()


func _open_builder() -> void:
	if _builder == null:
		_begin_opening()
		return
	# The builder normally refuses to open away from a home base. The opening is
	# the one place that gate is wrong: the player is nowhere, and being handed
	# their ship to configure is the first thing that happens.
	_builder.requires_home_base = false
	_builder.open()
	# Boot and build talk over the builder rather than gating it: the player is
	# free to start bolting parts on while the ship is still introducing itself.
	_voice.say(boot_lines + build_lines)


func _process(delta: float) -> void:
	match _beat:
		Beat.BUILDER:
			# Polled rather than driven by a signal, so GamePanel does not have to
			# grow an opening-sequence-shaped hook that nothing else wants.
			if _builder == null or not _builder.visible:
				_begin_opening()
		Beat.OPENING:
			if _beat_finished(delta):
				_beat = Beat.EXPLORING
				_timer = explore_seconds
		Beat.EXPLORING:
			_timer -= delta
			if _timer <= 0.0:
				_beat = Beat.CONTACT_CALL
				_play(scan_lines)
		Beat.CONTACT_CALL:
			if _beat_finished(delta):
				_spawn_contact()
				_beat = Beat.FOUND
		Beat.FOUND:
			_update_approach_cues()
			if _field != null and _field.is_salvage_taken():
				_begin_fitting()
			else:
				_update_marker_target()
		Beat.FITTING:
			# Waiting on the player, not on a clock: they have to get the part
			# home, into the builder and onto the hull, and that takes as long as
			# it takes.
			if _prize_installed():
				_beat = Beat.AMBUSH
				_timer = ambush_delay
				_voice.say(weapon_lines)
		Beat.AMBUSH:
			if _ambushers.is_empty():
				_timer -= delta
				if _timer <= 0.0:
					_spawn_ambush()
			elif _squad_defeated():
				_finish()
			else:
				_update_combat_cue()
		Beat.DONE:
			pass


func _begin_opening() -> void:
	_beat = Beat.OPENING
	# Interrupts: any build instructions still queued are about a screen the
	# player has just closed.
	_play(launch_lines, true)


## Two cues on the way in that belong to where the player is rather than to what
## they have done, so they land while the thing being talked about is on screen:
## the wreck field as it comes into view, and the cutting lesson once the target
## hull is close enough to act on.
func _update_approach_cues() -> void:
	var player: Vector2 = _player_position()
	if not _said_graveyard and _contact != null \
			and player.distance_to(_contact.global_position) \
			< _contact.get_visual_radius() * graveyard_cue_radius_scale:
		_said_graveyard = true
		_voice.say(graveyard_lines)
	if not _said_salvage and _salvage_ship != null and is_instance_valid(_salvage_ship) \
			and player.distance_to(_salvage_ship.global_position) < salvage_cue_distance:
		_said_salvage = true
		_voice.say(salvage_lines)


## The arrival lines play as the raiders appear; this one waits until one of them
## is close enough to actually be a fight.
func _update_combat_cue() -> void:
	if _said_combat:
		return
	var player: Vector2 = _player_position()
	for raider in _ambushers:
		if is_instance_valid(raider) \
				and player.distance_to(raider.global_position) < combat_cue_distance:
			_said_combat = true
			_voice.say(combat_lines)
			return


## True once this beat's dialogue has finished — or once the fallback delay has
## run out, for a beat whose lines are not assigned. The fallback is what keeps
## the whole sequence runnable with the audio stripped out.
func _beat_finished(delta: float) -> bool:
	if _voice.is_speaking():
		return false
	if _spoken_this_beat:
		return true
	_timer -= delta
	return _timer <= 0.0


## Starts a beat's dialogue and arms the silent fallback in case there is none.
func _play(lines: Array, interrupt: bool = false) -> void:
	_spoken_this_beat = not lines.is_empty()
	_timer = silent_beat_seconds
	_voice.say(lines, interrupt)


## The derelict appears at a random bearing at a random distance, so the opening
## does not play out identically twice and the marker has a real job.
##
## A named GameRng stream rather than the global randf: where the world's content
## is placed is a simulation outcome two machines would have to agree on, unlike
## the flicker and shake that stay on the global generator (docs/direction.md §2).
func _spawn_contact() -> void:
	var rng: RandomNumberGenerator = GameRng.stream("intro")
	var bearing: float = rng.randf() * TAU
	var colossus: Node2D = colossus_scene.instantiate()
	WorldSpawn.attach(colossus)
	colossus.rotation = rng.randf() * TAU

	# Clearance is added to the hull's own radius, so however the art is rescaled
	# the player always ends up outside it looking in.
	var distance: float = colossus.get_visual_radius() 		+ rng.randf_range(contact_clearance.x, contact_clearance.y)
	colossus.global_position = _player_position() + Vector2.RIGHT.rotated(bearing) * distance

	# The graveyard is built around the wreck rather than bolted onto it, and it
	# owns the one hull the player is meant to cut.
	var field: Battleground = battleground_scene.instantiate()
	colossus.add_child(field)
	# The player is out along `bearing` from the wreck, so the reverse of it is the
	# side they will come in on — that is where the hull they are meant to cut goes.
	# Less the Colossus's own rotation, since the field is parented to it and would
	# otherwise place a world-space bearing into a rotated frame.
	field.build(colossus.get_visual_radius(), bearing + PI - colossus.rotation)

	_contact = colossus
	_field = field
	_salvage_ship = field.get_salvage_ship()
	if _marker != null:
		_marker.track(colossus)
	contact_spawned.emit(colossus)


## The part is off the hull. The marker's job ends here — it points at things the
## player has been told about but not yet found, and the wreck is neither now.
func _begin_fitting() -> void:
	_beat = Beat.FITTING
	if _marker != null:
		_marker.clear_target()


## Whether the salvaged part is now bolted to the player's own hull. Matched on
## instance_id, which is the same string from the moment the part was stamped on
## the wreck through being cut free, reeled in, held in the hold and finally
## placed — the entire point of parts being objects rather than types
## (docs/direction.md §1). Nothing else would survive that journey: the placement
## it was cut from is gone, and its type is shared with every other gun.
func _prize_installed() -> bool:
	if _field == null or _field.get_prize_instance_id().is_empty():
		return false
	var ship: Ship = PlayerContext.get_ship()
	if ship == null or ship.ship_layout == null:
		return false
	for placement in ship.ship_layout.placements:
		if placement.instance != null \
				and placement.instance.instance_id == _field.get_prize_instance_id():
			return true
	return false


## Raiders converge from every side at once, spread evenly around a random
## bearing rather than dropped at independent random angles — three independent
## rolls cluster often enough that the "ambush" regularly arrives as a single
## group from one direction, which reads as a patrol wandering past.
func _spawn_ambush() -> void:
	var rng: RandomNumberGenerator = GameRng.stream("intro")
	var origin: Vector2 = _player_position()
	var first_bearing: float = rng.randf() * TAU
	for i in ambush_count:
		# Untyped: the scene's root is a Ship, and a static reference to it here
		# closes a parse cycle through ship.tscn (see docs/gotchas.md).
		var raider = ambush_scene.instantiate()
		raider.personality = _ambush_personality(raider.personality)
		var bearing: float = first_bearing + TAU * float(i) / float(ambush_count)
		var distance: float = rng.randf_range(ambush_distance.x, ambush_distance.y)
		WorldSpawn.attach_at(raider, origin + Vector2.RIGHT.rotated(bearing) * distance)
		_ambushers.append(raider)
	_voice.say(pirate_lines)


## A weaker, longer-sighted copy of the raider's usual personality.
##
## duplicate() is not optional: a ShipPersonality .tres is one shared resource
## across every ship that exports it, so weakening it in place would weaken every
## pirate in the game for the rest of the session.
func _ambush_personality(personality: ShipPersonality) -> ShipPersonality:
	var tuned: ShipPersonality = personality.duplicate()
	tuned.health_multiplier *= ambush_health_multiplier
	tuned.detection_range = maxf(tuned.detection_range, ambush_distance.y * 1.3)
	return tuned


## True once nothing from the squad is left flying. Checks health as well as node
## validity because a ship that has just died lingers for its explosion before
## freeing itself, and the opening should not stay in its combat beat waiting for
## the debris to clear.
func _squad_defeated() -> bool:
	for raider in _ambushers:
		if is_instance_valid(raider) and raider.get_current_health() > 0.0:
			return false
	return true


## The opening is over: the player has taken a part, been jumped for it, and come
## out the other side. Nothing here points at anything any more.
func _finish() -> void:
	_beat = Beat.DONE
	if _marker != null:
		_marker.clear_target()


## Hands the marker from the wreck to the arm once the wreck itself is no longer
## the hard thing to find.
func _update_marker_target() -> void:
	if _marker == null or _contact == null:
		return
	if _salvage_ship == null or not is_instance_valid(_salvage_ship):
		return
	var close_enough: bool = _player_position().distance_to(_contact.global_position) 		< arm_handoff_distance
	_marker.track(_salvage_ship if close_enough else _contact)


func _player_position() -> Vector2:
	var ship: Ship = PlayerContext.get_ship()
	return ship.global_position if ship != null else Vector2.ZERO

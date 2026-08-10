class_name EngineAudio
extends Node2D

## The engine note a ship makes while it is under thrust, one looping voice per
## faction of engine actually bolted to the hull.
##
## Faction comes from the *part*, the same rule the plating, the turret art and
## the laser colour follow (HullPaint.art_faction_for): a pirate thruster cut off
## a raider keeps sounding like a pirate thruster once it is on a corporate hull.
## A mongrel ship with engines from two factions runs both voices at once and
## sounds like the assembled thing it is — which is the whole point of the
## salvage loop being audible rather than only visible.
##
## Owned by Ship, which tells it what is mounted and whether the throttle is
## open; it owns the players and nothing else.

## Which sample each faction's engines run. Anything unmapped falls back to
## DEFAULT_ENGINE — there are only two recordings, so an Ancient thruster
## currently borrows the corporate one rather than being silent.
const FACTION_ENGINES: Dictionary = {
	"corporate": "res://audio/rocket_engine_1.mp3",
	"pirate": "res://audio/rocket_engine_2.mp3",
}
const DEFAULT_ENGINE: String = "res://audio/rocket_engine_1.mp3"

## Rocket Engine 1 is only usable for its first seven seconds; past that the
## recording goes somewhere that does not belong under a running engine. Rather
## than re-cutting the asset, the voice is seeked back to the start when it
## reaches this point, which makes those seven seconds the loop.
const LOOP_END_SECONDS: Dictionary = {
	"res://audio/rocket_engine_1.mp3": 7.0,
}

## Deliberately low. This is a continuous sound that plays for as long as the
## player is moving, it can be doubled up when a hull carries two factions of
## engine, and every AI ship in the fight is running its own copy.
@export var volume_db: float = -20.0

## Boost runs the same recording hotter rather than introducing a third sample:
## louder, and pitched up, which is what makes an engine read as strained rather
## than merely turned up. Two knobs instead of one because volume alone just
## sounds like the mix changed, and pitch alone sounds like a different engine.
@export var boost_volume_db: float = -13.0
@export var boost_pitch_scale: float = 1.16

## How fast the note slides between the cruise and boost settings. Slower than
## the on/off fade: the throttle is a switch, but spooling up to full power is
## a movement, and hearing it arrive is most of the effect.
@export var boost_blend_seconds: float = 0.45

## Engines spin up and spin down rather than clicking on and off with the key.
@export var fade_in_seconds: float = 0.18
@export var fade_out_seconds: float = 0.35

const SILENT_DB: float = -60.0

var _players: Array[AudioStreamPlayer2D] = []
var _loop_ends: Array[float] = []
var _thrusting: bool = false
var _boosting: bool = false


## Rebuilds the voices for a layout: one per distinct engine faction present, so
## four corporate thrusters are one voice rather than four stacked copies of the
## same sample.
func configure(layout: ShipLayout, hull_faction_id: String) -> void:
	for player in _players:
		player.queue_free()
	_players.clear()
	_loop_ends.clear()
	if layout == null:
		return

	var factions: Array[String] = []
	for placement in layout.get_thruster_placements():
		var faction: String = HullPaint.art_faction_for(placement.instance, hull_faction_id)
		if not factions.has(faction):
			factions.append(faction)

	for faction in factions:
		var path: String = FACTION_ENGINES.get(faction, DEFAULT_ENGINE)
		_add_voice(path)


func _add_voice(stream_path: String) -> void:
	var stream: AudioStreamMP3 = load(stream_path)
	# duplicate() because the loaded resource is shared across every ship in the
	# scene: setting `loop` on the original would mutate it for all of them.
	var looping: AudioStreamMP3 = stream.duplicate()
	looping.loop = true

	var player := AudioStreamPlayer2D.new()
	player.stream = looping
	player.volume_db = SILENT_DB
	# duplicate() strips resource_path, so the sample a voice is running is
	# otherwise unanswerable from a live ship — name the node after it.
	player.name = stream_path.get_file().get_basename()
	add_child(player)
	# Started immediately and left running for the ship's lifetime, faded rather
	# than stopped: restarting a loop on every tap of the throttle would put an
	# audible attack transient on a sound that is supposed to be continuous.
	player.play()
	_players.append(player)
	_loop_ends.append(LOOP_END_SECONDS.get(stream_path, 0.0))


## Called by Ship every physics frame with the current throttle state.
func set_thrusting(active: bool, boosting: bool = false) -> void:
	_thrusting = active
	_boosting = active and boosting


func _process(delta: float) -> void:
	if _players.is_empty():
		return
	var running_db: float = boost_volume_db if _boosting else volume_db
	var target: float = running_db if _thrusting else SILENT_DB
	var target_pitch: float = boost_pitch_scale if _boosting else 1.0
	var pitch_step: float = absf(boost_pitch_scale - 1.0) * delta / maxf(boost_blend_seconds, 0.001)
	var full_range: float = boost_volume_db - SILENT_DB

	for i in _players.size():
		var player: AudioStreamPlayer2D = _players[i]
		player.volume_db = move_toward(player.volume_db, target,
			_volume_step(player.volume_db, delta, full_range))
		player.pitch_scale = move_toward(player.pitch_scale, target_pitch, pitch_step)
		# Keeps the usable part of a recording that is only good at its head.
		var loop_end: float = _loop_ends[i]
		if loop_end > 0.0 and player.get_playback_position() >= loop_end:
			player.seek(0.0)


## Three different moves share one volume property, and they want different
## speeds: starting and stopping are the throttle opening and closing, while
## sliding between cruise and boost is the engine spooling. Blending at the
## start/stop rate makes boost snap; starting at the blend rate makes the engine
## take three seconds to become audible.
func _volume_step(current_db: float, delta: float, full_range: float) -> float:
	if not _thrusting:
		return full_range * delta / maxf(fade_out_seconds, 0.001)
	if current_db < minf(volume_db, boost_volume_db) - 0.5:
		return full_range * delta / maxf(fade_in_seconds, 0.001)
	return absf(boost_volume_db - volume_db) * delta / maxf(boost_blend_seconds, 0.001)

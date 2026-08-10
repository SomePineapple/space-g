extends Node

## The background ambient track, playing continuously for the whole session.
##
## An autoload — one of the few things that genuinely qualifies under CLAUDE.md's
## restriction, and the "audio coordination" case it names. Every region is a
## separate scene reached through `change_scene_to_file` (see WarpGate), so a
## player node living in a region would be torn down and restarted on every warp:
## the music would cut out, restart from the top, and announce the loading stall
## rather than covering it. Nothing else in the project needs to survive a scene
## change for its own sake.
##
## Deliberately not a general audio manager. It owns one looping stream and
## nothing else; shot, hit and explosion sounds stay with the objects that make
## them, positioned in the world where they belong.

## Well below unity: this plays under everything else for hours at a time, and
## the mix has to leave room for the shot sounds (HardpointGun.fire_volume_db)
## that land on top of it.
@export var volume_db: float = -22.0

## Faded in rather than started at full, so the track arrives instead of
## beginning mid-thought the instant the game window opens.
@export var fade_in_seconds: float = 3.0

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = _looping_stream()
	# Music is not positional and must not be attenuated by where the ship is,
	# so this is a plain AudioStreamPlayer rather than the AudioStreamPlayer2D
	# every in-world sound uses.
	_player.volume_db = -60.0
	add_child(_player)
	_player.play()

	var tween: Tween = create_tween()
	tween.tween_property(_player, "volume_db", volume_db, fade_in_seconds)


## Looping is set here rather than in the .import so the intent is visible in
## code — an import flag silently reverts whenever the asset is re-imported, and
## a background track that stops after six minutes is a subtle thing to notice.
func _looping_stream() -> AudioStream:
	var stream: AudioStreamMP3 = preload("res://audio/ambient_space.mp3")
	# duplicate() because the loaded resource is shared: setting `loop` on the
	# original would mutate it for anything else that ever plays this file.
	var looping: AudioStreamMP3 = stream.duplicate()
	looping.loop = true
	return looping


## Somewhere for a pause menu or a settings screen to reach later, without
## anything having to find the player node itself.
func set_music_volume_db(value: float) -> void:
	volume_db = value
	if _player != null:
		_player.volume_db = value


func stop() -> void:
	if _player != null:
		_player.stop()

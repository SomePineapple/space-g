class_name VoiceDirector
extends AudioStreamPlayer

## The ship's voice. Speaks one line at a time and queues the rest.
##
## AudioStreamPlayer, not AudioStreamPlayer2D, deliberately: the voice is in the
## cockpit with the player at a fixed volume, not at a point in the world. A
## positional version would fade out as the camera panned, which would be wrong
## for something that is meant to be talking to you rather than near you.
##
## The queue is the whole reason this exists rather than a bare
## AudioStreamPlayer: play() restarts, it does not wait, so handing a beat three
## lines meant hearing only the last one. Beats here are written as "say these,
## in order", and something has to hold the rest while the first plays.

## Emitted when the queue empties — the cue for a beat that is waiting on its
## own dialogue to finish before moving on.
signal finished_speaking

## Lines are already mastered with the space filter baked in (the `_space`
## suffix on every file), so they play on the default bus with no effect chain
## and no bus layout to install.
@export var line_volume_db: float = -2.0

var _queue: Array[AudioStream] = []


func _ready() -> void:
	volume_db = line_volume_db
	finished.connect(_advance)


## Speaks these lines back to back, after whatever is already waiting.
##
## Queueing rather than replacing is the default because the beats are a script
## read in order, and two cues landing within a few seconds of each other is
## normal — arriving at the wreck field and then reaching the target hull, say.
## Replacing dropped whichever line was still speaking, so the player simply
## never heard parts of the tutorial.
##
## `interrupt` is for the case where the queued lines have been made obsolete by
## what the player just did: leaving the ship builder abandons the rest of the
## build instructions rather than narrating them at someone already flying.
func say(lines: Array, interrupt: bool = false) -> void:
	if interrupt:
		_queue.clear()
		stop()
	for line in lines:
		if line != null:
			_queue.append(line)
	# stop() does not emit finished, so the chain has to be restarted by hand.
	if not playing:
		_advance()


## True while there is anything left to say, including what is queued behind the
## current line.
func is_speaking() -> bool:
	return playing or not _queue.is_empty()


func silence() -> void:
	_queue.clear()
	stop()


func _advance() -> void:
	if _queue.is_empty():
		finished_speaking.emit()
		return
	stream = _queue.pop_front()
	play()

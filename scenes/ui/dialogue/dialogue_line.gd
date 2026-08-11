class_name DialogueLine
extends Resource

## One spoken line: who is talking, on what channel, and what they say.
##
## Pure data with no node references, like every other data object in the
## project, so a line can be authored in the editor, written into a .tres script
## of a conversation, or built in code at the moment something needs to say
## something (see DialogueBox.show_line).
##
## Deliberately does NOT carry a "next node" id. The design's reply list drives a
## conversation graph, but a graph is a separate system with its own authoring
## and save concerns; this box reports which reply was chosen and lets whatever
## started the conversation decide what happens. That keeps the box usable for
## the thing it is needed for today — a line of help at the bottom of the screen
## — without a dialogue-tree framework existing first.

## Shown in the header, upper-case by convention (e.g. "CORE", "HALLER").
@export var speaker: String = ""
## The smaller, dimmer half of the header (e.g. "SHIP AI", "SALVAGE GUILD · CH 7").
@export var affiliation: String = ""
@export_multiline var text: String = ""

## Optional reply labels. Only meaningful on the last line handed to the box:
## replies appear once that line has finished typing, and choosing one ends the
## conversation with `choice_selected`.
@export var choices: Array[String] = []

## Portrait art for the speaker. Null means a voice-only speaker — the ship's own
## AI, a radio contact — and the bust is simply not drawn. The design calls for
## this to be per-speaker rather than per-conversation.
@export var bust: Texture2D = null


static func create(speaker_name: String, affiliation_text: String, body: String,
		reply_labels: Array[String] = []) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = speaker_name
	line.affiliation = affiliation_text
	line.text = body
	line.choices = reply_labels
	return line

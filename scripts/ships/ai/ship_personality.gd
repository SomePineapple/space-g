class_name ShipPersonality
extends Resource

@export var display_name: String = ""

## Player-controlled ships take no AI action at all — movement and firing
## come from PlayerInput instead. ShipAI checks this first and does nothing
## when true.
@export var is_player_controlled: bool = false

## Stays idle until the target comes within this range, so ships feel like
## something discovered by exploring rather than something that rushes the
## player from across the whole region the instant the scene loads.
@export var detection_range: float = 900.0
@export var fire_range: float = 500.0
@export var keep_distance: float = 300.0

## Seconds spent "noticing" the target (turning to face it, not yet moving
## or firing) after it enters detection_range before escalating to full
## Alert. Skipped entirely if the target is already within fire_range, or
## if this ship takes damage (ShipAI jumps straight to Alert on damage).
@export var suspicion_delay: float = 0.6
@export var aim_tolerance_deg: float = 10.0
@export var turn_response: float = 2.0

## Rammer-style ships close in and hold, never backing off even at
## point-blank range. Sniper-style ships actively retreat if the target
## gets closer than keep_distance, instead of just holding position.
@export var retreats_when_too_close: bool = false

@export var use_primary_weapon: bool = true
@export var use_secondary_weapon: bool = true

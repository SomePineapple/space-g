class_name RegionType
extends Resource

## Data describing one flavor of asteroid region: how densely it's
## populated, what mix of asteroid sizes it favors, how tightly packed
## obstacles are allowed to be, and a tint so regions read as visually
## distinct at a glance. Used by RegionSpawner instead of hand-placing
## every asteroid in a region — see "1.3 Basic world regions".

@export var display_name: String = "Region"

## Asteroids per 1,000,000 sq. units (i.e. per 1000x1000 area). Density is a
## property of the region type, not a fixed count, so the same type can be
## reused at different area sizes.
@export_range(0.0, 60.0) var asteroid_density: float = 3.0

## Minimum center-to-center distance enforced between spawned asteroids.
@export var min_spacing: float = 220.0

@export_range(0.0, 1.0) var large_weight: float = 0.2
@export_range(0.0, 1.0) var medium_weight: float = 0.5
@export_range(0.0, 1.0) var small_weight: float = 0.3

## Multiplied into each spawned asteroid's self_modulate for a
## region-distinct visual identity (same technique the faction station
## wrecks use).
@export var asteroid_tint: Color = Color(1.0, 1.0, 1.0)


func pick_size_tier(rng: RandomNumberGenerator) -> Asteroid.SizeTier:
	var total: float = large_weight + medium_weight + small_weight
	if total <= 0.0:
		return Asteroid.SizeTier.MEDIUM
	var roll: float = rng.randf() * total
	if roll < large_weight:
		return Asteroid.SizeTier.LARGE
	elif roll < large_weight + medium_weight:
		return Asteroid.SizeTier.MEDIUM
	else:
		return Asteroid.SizeTier.SMALL

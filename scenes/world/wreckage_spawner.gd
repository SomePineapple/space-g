class_name WreckageSpawner
extends Node

## Everything a ship throws off when part of it comes apart: the drifting hex
## piece a severed module becomes (plain ShipDebris, or a recoverable
## CapturedTechPart), and the sparks that trace the seam it tore away along.
##
## Split out of ship.gd. HullDamageModel decides *that* a module is gone; this
## decides what visibly leaves the hull because of it, so the damage bookkeeping
## and the wreckage presentation stop sharing one script.

## Outward speed/spin added on top of the ship's own velocity when a module
## detaches, so a severed wing visibly kicks away rather than just trailing
## along at the exact same velocity as the ship that lost it.
@export var detach_kick_speed: float = 60.0
@export var detach_spin_range: float = 2.0
## The same two for a part deliberately cut free rather than blown off. Low
## enough that the piece essentially coasts along with the hull it left — it
## still inherits that ship's full velocity, so cutting a part off something
## moving fast still leaves you chasing it, which is the interesting case.
@export var clean_cut_kick_speed: float = 10.0
@export var clean_cut_spin_range: float = 0.3

## What a part keeps of its remaining integrity when it is blown off rather than
## cut off (see ModuleInstance.integrity). Being torn free by an explosion is
## rough treatment, and the difference is the argument for the Slicer: a cut part
## comes off as good as it was, a shot-off one comes off worn. Rarity alone made
## gunfire a worse lottery for the same prize; this makes it a worse prize.
@export var explosive_recovery_integrity: float = 0.6

@export var ship_debris_scene: PackedScene = preload("res://scenes/world/ship_debris.tscn")
@export var captured_tech_part_scene: PackedScene = preload("res://scenes/world/captured_tech_part.tscn")
@export var seam_spark_scene: PackedScene = preload("res://scenes/world/seam_spark.tscn")

var _ship: Ship
var _layout: ShipLayout
var _renderer: ShipLayoutRenderer
var _faction_id: String = ""


func configure(ship: Ship, layout: ShipLayout, renderer: ShipLayoutRenderer, faction_id: String) -> void:
	_ship = ship
	_layout = layout
	_renderer = renderer
	_faction_id = faction_id


## The severed placement leaves as one drifting piece, taking its mounted part
## with it: `instance` is the actual ModuleInstance that was on the hull a frame
## ago, handed over by HullDamageModel._detach_module. A clean enough severance
## (see _roll_capturable) turns it into a recoverable CapturedTechPart still
## holding that object; anything else is inert debris and the part is gone.
## `clean_cut` marks a part that was deliberately severed by a Slicer rather than
## shaken loose by an explosion. Those always survive: the capture roll exists to
## make blowing a ship apart an unreliable way to get its parts, and taxing a
## precise cut with the same dice would mean doing everything right and getting
## nothing — which reads as a bug rather than as risk.
func spawn_severed_piece(placement: ModulePlacement, module_type: ModuleType,
		instance: ModuleInstance, clean_cut: bool = false) -> void:
	var condition_fraction: float = instance.condition_fraction if instance != null else 0.0
	if instance != null and (clean_cut or _roll_capturable(module_type, condition_fraction)):
		var part: CapturedTechPart = _spawn_piece(captured_tech_part_scene, placement, module_type, clean_cut)
		instance.stamp_origin(_faction_id, _origin_description())
		# Immunity protects a part while it is scenery waiting to be taken (see
		# ModuleInstance.damage_immune). Coming free is exactly the moment that
		# job ends — carrying it onto the player's hull would hand them an
		# indestructible module.
		instance.damage_immune = false
		if clean_cut:
			# Deliberately taken, so it waits to be collected rather than ageing out
			# while the player flies over to it.
			part.make_permanent()
		else:
			# Torn free by a detonation rather than opened up along a seam. The part
			# survives, but not unmarked — and integrity never comes back.
			instance.integrity = maxf(instance.integrity * explosive_recovery_integrity,
				ModuleInstance.MINIMUM_INTEGRITY)
			instance.condition_fraction = minf(instance.condition_fraction, instance.integrity)
		part.set_instance(instance)
	else:
		_spawn_piece(ship_debris_scene, placement, module_type, clean_cut)


## Provenance recorded on a part the first time it is cut free — what it came
## off and roughly where. The scene name stands in for a region name; there is
## no runtime region identity to ask, and reaching across the tree for the
## RegionSpawner's RegionType would couple wreckage to world generation.
func _origin_description() -> String:
	var hull_name: String = _ship.personality.display_name
	if hull_name.is_empty():
		hull_name = "an unmarked hull"
	var scene: Node = _ship.get_tree().current_scene if _ship.get_tree() != null else null
	if scene == null:
		return "Cut from %s" % hull_name
	return "Cut from %s in %s" % [hull_name, scene.name]


## Sparks trace the exact hex edge(s) where a severed wing tears away from the
## rest of the hull, one burst per boundary edge, rather than a single generic
## burst at the ship's center — reads as the connection itself breaking,
## especially for a multi-hex limb detaching all at once.
func spawn_seam_sparks(detached_placement_ids: Array[String]) -> void:
	var detached_cells: Dictionary = {}
	for placement_id in detached_placement_ids:
		var placement: ModulePlacement = _layout.get_placement_by_id(placement_id)
		if placement == null:
			continue
		for cell in _layout.get_occupied_cells(placement):
			detached_cells[cell] = true

	for cell in detached_cells:
		for neighbor in HexUtils.neighbors(cell):
			# Only spark where another module (still attached, or the destroyed
			# connector that caused this severance) actually sits — skip edges
			# facing open space, which aren't a "seam" at all.
			if not detached_cells.has(neighbor) and _layout.is_occupied(neighbor):
				_spawn_seam_spark_at(cell, neighbor)


## A severed module only stays intact enough to be worth recovering if it kept
## most of its own health right up to the moment it detached (rather than being
## chewed apart first via splash/direct hits) — and even then only sometimes, so
## capture is a notable outcome, not a guaranteed drop every time a wing
## carrying real tech comes off (see ModuleType.is_capturable_tech).
func _roll_capturable(module_type: ModuleType, condition_fraction: float) -> bool:
	if not module_type.is_capturable_tech:
		return false
	if condition_fraction < module_type.capture_health_fraction:
		return false
	return GameRng.stream("wreckage").randf() < module_type.capture_chance


## Spawns either flavor of severed hex piece. Both are DriftingHexPiece, and the
## placement and launch maths are identical between them, so only the scene
## differs here.
func _spawn_piece(piece_scene: PackedScene, placement: ModulePlacement, module_type: ModuleType,
		clean_cut: bool = false) -> DriftingHexPiece:
	var data: Dictionary = _visual_data(placement, module_type)

	var piece: DriftingHexPiece = piece_scene.instantiate()
	# Same transform as HullRenderer (ship center + its fixed rotation offset),
	# so the piece's cells render exactly where they were an instant ago, before
	# drifting away under their own velocity.
	WorldSpawn.attach_transformed(piece, _renderer.global_transform)

	var centroid_world: Vector2 = piece.global_transform.basis_xform(data["centroid"])
	# Move the node itself onto the piece's own centre and slide the drawn cells
	# back by the same amount, so it looks identical but its global_position is
	# now actually where it appears. Everything that treats a piece as a point —
	# the winch's catch test, the reel, its own spin — was working off the ship's
	# centre before, which for anything out on a limb is a long way from the part.
	piece.global_position += centroid_world
	var kick_direction: Vector2 = centroid_world.normalized() if centroid_world.length() > 0.001 \
		else Vector2.RIGHT.rotated(piece.global_rotation)

	# A part that was cut free did not explode: it keeps the momentum of the hull
	# it came off and little else. A part shaken loose by a detonation gets the
	# full kick. Same code path, different energy — so a deliberate cut leaves
	# something you can line the winch up on rather than chase.
	var kick: float = clean_cut_kick_speed if clean_cut else detach_kick_speed
	var spin: float = clean_cut_spin_range if clean_cut else detach_spin_range

	piece.setup(data["cells"], data["colors"], data["textures"], data["rotation_steps"], _renderer.cell_size,
		_ship.velocity + kick_direction * kick,
		GameRng.stream("wreckage").randf_range(-spin, spin),
		data["centroid"])
	return piece


## The visual description of a severed placement's hex(es). Uses the same
## per-cell, faction-reskinned texture lookup as ShipLayoutRenderer
## (get_hex_texture_for_cell) so the severed piece keeps showing the exact art
## it had on the hull, not the type's generic fallback.
func _visual_data(placement: ModulePlacement, module_type: ModuleType) -> Dictionary:
	var cells: Array[Vector2i] = _layout.get_occupied_cells(placement)
	var colors: Array[Color] = []
	var textures: Array[Texture2D] = []
	var local_centroid: Vector2 = Vector2.ZERO
	for i in cells.size():
		colors.append(module_type.color)
		textures.append(module_type.get_hex_texture_for_cell(_faction_id, i))
		local_centroid += HexUtils.axial_to_pixel(cells[i], _renderer.cell_size)
	local_centroid /= cells.size()
	return {"cells": cells, "colors": colors, "textures": textures, "rotation_steps": placement.rotation_steps, "centroid": local_centroid}


func _spawn_seam_spark_at(cell: Vector2i, neighbor: Vector2i) -> void:
	var cell_center: Vector2 = HexUtils.axial_to_pixel(cell, _renderer.cell_size)
	var neighbor_center: Vector2 = HexUtils.axial_to_pixel(neighbor, _renderer.cell_size)
	var edge_midpoint: Vector2 = (cell_center + neighbor_center) * 0.5
	var local_outward: Vector2 = (neighbor_center - cell_center).normalized()

	var spark: Node2D = seam_spark_scene.instantiate()
	WorldSpawn.attach_at(spark,
		_renderer.global_transform * edge_midpoint,
		_renderer.global_transform.basis_xform(local_outward).angle())

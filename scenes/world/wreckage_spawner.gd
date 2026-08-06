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


## The severed placement leaves as one drifting piece. condition_fraction is
## how much of its own max condition the module still had at the instant it
## detached — see _roll_capturable.
func spawn_severed_piece(placement: ModulePlacement, module_type: ModuleType, condition_fraction: float) -> void:
	if _roll_capturable(module_type, condition_fraction):
		var part: CapturedTechPart = _spawn_piece(captured_tech_part_scene, placement, module_type)
		part.set_source(module_type.id, _faction_id, placement.manufacturer_id)
	else:
		_spawn_piece(ship_debris_scene, placement, module_type)


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
	return randf() < module_type.capture_chance


## Spawns either flavor of severed hex piece. Both are DriftingHexPiece, and the
## placement and launch maths are identical between them, so only the scene
## differs here.
func _spawn_piece(piece_scene: PackedScene, placement: ModulePlacement, module_type: ModuleType) -> DriftingHexPiece:
	var data: Dictionary = _visual_data(placement, module_type)

	var piece: DriftingHexPiece = piece_scene.instantiate()
	get_tree().current_scene.add_child(piece)
	# Same transform as HullRenderer (ship center + its fixed rotation offset),
	# so the piece's cells render exactly where they were an instant ago, before
	# drifting away under their own velocity.
	piece.global_transform = _renderer.global_transform

	var kick_direction: Vector2 = piece.global_transform.basis_xform(data["centroid"])
	kick_direction = kick_direction.normalized() if kick_direction.length() > 0.001 else Vector2.RIGHT.rotated(piece.global_rotation)

	piece.setup(data["cells"], data["colors"], data["textures"], data["rotation_steps"], _renderer.cell_size,
		_ship.velocity + kick_direction * detach_kick_speed, randf_range(-detach_spin_range, detach_spin_range))
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
	get_tree().current_scene.add_child(spark)
	spark.global_position = _renderer.global_transform * edge_midpoint
	spark.global_rotation = _renderer.global_transform.basis_xform(local_outward).angle()

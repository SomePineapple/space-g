class_name WorldSpawn

## The one place a simulated object gets added to the region.
##
## Projectiles, missiles, explosions, salvage, debris, sparks, asteroids and
## enemies were each doing `get_tree().current_scene.add_child(thing)` inline —
## about eighteen copies of the same two lines, with the world root's identity
## assumed at every one of them. That assumption is the problem: in a networked
## build these spawns have to be authority-checked and replicated, and there was
## no single point to do either.
##
## Purely local presentation deliberately does NOT come through here — the
## pickup sound Salvage detaches so it can outlive itself, Nebula's fullscreen
## tint layer, WarpGate's input-lock node. Those exist only on the machine that
## made them and should never be replicated; they're commented as such where
## they are.
##
## Static rather than an autoload: this holds no state, so there's nothing for
## an autoload to own. It reaches the tree through the main loop rather than a
## caller-supplied node so call sites stay two lines instead of three.

## The node new world objects are parented to. Currently the running region's
## root; the seam exists so it can become a dedicated spawn container (or a
## replication root) without touching any caller.
static func world_root() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.current_scene if loop != null else null


## Parents an already-configured node into the region. Use when the caller sets
## the transform itself afterwards (see attach_transformed).
static func attach(node: Node) -> void:
	var root: Node = world_root()
	if root != null:
		root.add_child(node)


## The common case: parent it, then place it. Position and rotation are applied
## after add_child because global_* only means anything once the node is in the
## tree.
static func attach_at(node: Node2D, global_pos: Vector2, global_rot: float = 0.0) -> void:
	attach(node)
	node.global_position = global_pos
	node.global_rotation = global_rot


## For callers that need the whole transform copied from something else (a
## severed hull piece inheriting its ship's hull renderer transform) rather than
## a position and angle.
static func attach_transformed(node: Node2D, global_xform: Transform2D) -> void:
	attach(node)
	node.global_transform = global_xform

extends Node

## Randomness whose outcome has to agree between machines, kept separate from
## randomness that must not.
##
## The distinction matters more than it looks. Two kinds of `randf()` live in
## this project:
##
##   * simulation — a loot roll, a weapon malfunction, whether a severed module
##     is recoverable, which way an AI dodges. Every player has to see the same
##     answer, so these draw from a named stream seeded off one session seed.
##   * presentation — camera shake, starfield twinkle, particle jitter. These
##     are local decoration. Syncing them would be pointless, and worse,
##     drawing them from a shared stream would advance it a different number of
##     times on each machine (different framerates, different things on screen)
##     and desync everything downstream. They deliberately stay on the global
##     `randf()` and are commented as such at their call sites.
##
## Streams are named and cached, so two systems never interleave draws on one
## generator: the loot stream advancing has no effect on what the AI stream
## produces next. Within a stream, results still depend on call order, which is
## the normal constraint for this approach — a networked build resolves it the
## usual way, by having one authority roll and replicate the outcome rather
## than having every peer roll in lockstep.
##
## World generation already worked this way before this existed (see
## RegionSpawner.random_seed and Asteroid.random_seed, which derive per-asteroid
## seeds from a per-region one); this generalises the same pattern to everything
## else and gives it a single session-level root.
##
## Untyped where it touches game objects, and free of static references to the
## project's global classes, for the autoload compile-order reason documented on
## GameState.

signal session_seed_changed(new_seed: int)

## Root seed every stream derives from. Randomised on startup for solo play;
## a host would instead set this once and send it to joining peers, after which
## both sides' streams agree.
var session_seed: int = 0

## stream name -> RandomNumberGenerator, so repeated calls keep advancing the
## same generator rather than restarting it.
var _streams: Dictionary = {}


func _ready() -> void:
	if session_seed == 0:
		randomize_session()


func randomize_session() -> void:
	var generator := RandomNumberGenerator.new()
	generator.randomize()
	set_session_seed(generator.randi())


## Resets every stream — anything already holding a generator from stream()
## keeps the old one, so call this before a session starts, not during it.
func set_session_seed(value: int) -> void:
	session_seed = value
	_streams.clear()
	session_seed_changed.emit(value)


## The named generator for one system's simulation rolls. Cheap enough to call
## per draw; callers that draw every frame should still cache it.
func stream(stream_name: String) -> RandomNumberGenerator:
	var existing: RandomNumberGenerator = _streams.get(stream_name)
	if existing != null:
		return existing

	var generator := RandomNumberGenerator.new()
	generator.seed = derive(stream_name)
	_streams[stream_name] = generator
	return generator


## A seed for something that owns its own generator — a specific asteroid, a
## specific region — reproducible from the session seed plus a caller-chosen
## salt. Used where per-entity determinism matters more than one shared
## sequence, since a per-entity seed doesn't care what order entities are
## created in.
func derive(stream_name: String, salt: int = 0) -> int:
	return hash(stream_name) ^ (session_seed + salt * 0x9E3779B9)


## Monotonic counter for generated identifiers (placement ids, module instance
## ids). Deliberately not a random draw: these only need to be unique, and the
## previous approach mixed Time.get_ticks_usec() into them, which is wall-clock
## dependent and so can never agree between two machines.
var _next_id_ordinal: int = 0


func next_id(prefix: String) -> String:
	_next_id_ordinal += 1
	return "%s_%d_%d" % [prefix, session_seed & 0xFFFF, _next_id_ordinal]

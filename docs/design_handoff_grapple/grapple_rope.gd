extends Node2D
class_name GrappleRope
## Verlet grapple line — cast, wrap, tug, winch.
## Matches the timings and constants in grapple-line-Godot-spec.md.
## Node 0 is the hook. Node NODES-1 is pinned to the muzzle.

signal hooked(body)
signal secured(body)

@export var nodes: int = 64
@export var rest_length: float = 13.0
@export var iterations: int = 12
@export var damping: float = 0.997
@export var cast_speed: float = 820.0
@export var payout_slack: float = 60.0
@export var take_up_rate: float = 300.0
@export var wrap_links: int = 10
@export var wrap_time: float = 0.9
@export var load_transfer: float = 0.055
@export var body_speed_cap: float = 52.0
@export var body_speed_cap_reeling: float = 105.0

var pos: PackedVector2Array
var prev: PackedVector2Array
var deployed: int = 3
var line_len: float = 0.0
var cast_out: bool = false
var hooked_body: Node2D = null
var hook_angle: float = 0.0
var wrap_t: float = 0.0
var wrapped: int = 0
var tension: float = 0.0
var taut: bool = false
var took_up: bool = false
var reeling: bool = false

var _reel_from: float = 0.0
var _reel_to: float = 0.0
var _reel_dur: float = 1.0
var _reel_t: float = 0.0
var _accum: float = 0.0
const STEP := 1.0 / 120.0

@onready var muzzle: Node2D = $Muzzle
@onready var rope_line: Line2D = $Rope

func _ready() -> void:
	_reset()

func _reset() -> void:
	pos.resize(nodes); prev.resize(nodes)
	var m := muzzle.global_position
	for i in nodes:
		pos[i] = m; prev[i] = m
	deployed = 3; line_len = 0.0; cast_out = false
	hooked_body = null; wrapped = 0; wrap_t = 0.0
	tension = 0.0; taut = false; took_up = false; reeling = false

func fire(dir: Vector2) -> void:
	_reset()
	cast_out = true
	prev[0] = pos[0] - dir.normalized() * cast_speed * STEP

func reel_to(target_len: float, seconds: float) -> void:
	_reel_from = line_len; _reel_to = target_len
	_reel_dur = max(0.01, seconds); _reel_t = 0.0
	reeling = true

func release() -> void:
	hooked_body = null; wrapped = 0
	reel_to(40.0, 0.8)

func _physics_process(delta: float) -> void:
	_accum += delta
	var guard := 0
	while _accum >= STEP and guard < 8:
		_step(STEP); _accum -= STEP; guard += 1
	_draw_rope()

func _step(h: float) -> void:
	var m := muzzle.global_position
	if not cast_out:
		for i in nodes:
			pos[i] = m; prev[i] = m
		return

	# --- payout ------------------------------------------------------------
	var hook_dist := pos[0].distance_to(m)
	if reeling:
		_reel_t = min(_reel_dur, _reel_t + h)
		var u := _reel_t / _reel_dur
		line_len = lerp(_reel_from, _reel_to, u * u * (3.0 - 2.0 * u))
	else:
		line_len = max(line_len, hook_dist + payout_slack)
		if hooked_body and not took_up:
			line_len = max(hook_dist + 8.0, line_len - take_up_rate * h)
			if line_len <= hook_dist + 9.0:
				took_up = true

	var k := int(clamp(line_len / rest_length + 2.0, 3.0, float(nodes)))
	if k > deployed:
		# a link leaving the drum inherits the line's speed, or the spool
		# brakes the cast and the hook stalls at half range
		var hv := pos[0] - prev[0]
		for i in range(max(0, deployed - 1), k - 1):
			pos[i] = m
			prev[i] = m - hv * 0.98
	deployed = k

	# --- integrate ---------------------------------------------------------
	for i in nodes:
		if i >= k - 1:
			pos[i] = m; prev[i] = m
			continue
		var v := (pos[i] - prev[i]) * damping
		prev[i] = pos[i]
		pos[i] += v

	# --- wrap --------------------------------------------------------------
	if hooked_body:
		wrap_t = min(1.0, wrap_t + h / wrap_time)
		var w := wrap_t * wrap_t * (3.0 - 2.0 * wrap_t)
		wrapped = int(round(lerp(1.0, float(wrap_links), w)))
		var r0: float = hooked_body.get_meta("salvage_radius", 46.0)
		for i in wrapped:
			var f := float(i) / float(wrap_links)
			var ang: float = hooked_body.rotation + hook_angle + f * 5.4
			var rad: float = lerp(r0 + 3.0, r0 - 9.0, w) - f * 2.4
			pos[i] = hooked_body.global_position + Vector2(cos(ang), sin(ang)) * rad
			prev[i] = pos[i]

	# --- constraints -------------------------------------------------------
	var corr := 0.0
	for it in iterations:
		for i in range(0, k - 1):
			var d: Vector2 = pos[i + 1] - pos[i]
			var dist := max(d.length(), 0.0001)
			if dist <= rest_length:
				continue
			var diff := (dist - rest_length) / dist
			var a_pin := i < wrapped
			var b_pin := (i + 1 >= k - 1) or (i + 1 < wrapped)
			if a_pin and b_pin:
				continue
			var wa := 0.0 if a_pin else 0.5
			var wb := 0.0 if b_pin else 0.5
			if a_pin: wb = 1.0
			if b_pin: wa = 1.0
			if it == 0: corr += dist - rest_length
			pos[i] += d * diff * wa
			pos[i + 1] -= d * diff * wb
			# only the outermost wrapped link hauls the body
			if a_pin and i == wrapped - 1 and hooked_body:
				hooked_body.global_position += d * diff * load_transfer

	if hooked_body:
		_cap_body_speed(h)

	var was_taut := taut
	tension = clamp(corr / 22.0, 0.0, 1.0)
	taut = tension > 0.35
	if taut and not was_taut:
		_on_snap_taut()

	# --- bite --------------------------------------------------------------
	if hooked_body == null:
		var body := _overlap(pos[0])
		if body:
			hooked_body = body
			hook_angle = (pos[0] - body.global_position).angle() - body.rotation
			$Impact.global_position = pos[0]
			$Impact.restart()
			emit_signal("hooked", body)

func _cap_body_speed(h: float) -> void:
	var b := hooked_body
	var v: Vector2 = b.global_position - b.get_meta("prev_pos", b.global_position)
	var cap := body_speed_cap_reeling if reeling else body_speed_cap
	if v.length() > cap * h:
		b.global_position = b.get_meta("prev_pos", b.global_position) + v.normalized() * cap * h
	b.set_meta("prev_pos", b.global_position)

func _on_snap_taut() -> void:
	$Strain.global_position = pos[min(deployed - 2, wrapped + 4)]
	$Strain.restart()
	# camera shake hook goes here

func _overlap(p: Vector2) -> Node2D:
	for body in get_tree().get_nodes_in_group("salvage"):
		var r: float = body.get_meta("salvage_radius", 46.0)
		if p.distance_to(body.global_position) < r + 4.0:
			return body
	return null

func _draw_rope() -> void:
	var pts := PackedVector2Array()
	for i in max(3, deployed):
		pts.append(to_local(pos[i]))
	rope_line.points = pts
	rope_line.modulate.a = 0.75 + 0.25 * tension
	$Hook.global_position = pos[0]
	$Hook.rotation = (pos[0] - pos[min(2, deployed - 1)]).angle()
	# link mesh + additive strain pass are updated from `pts` here

extends TestBase
## 3D Battle speed benchmark: a huge battle, timed headless, step by step.
## It takes about half a minute, so it isn't part of tools/run_tests.sh.
##   godot --headless --path . --fixed-fps 60 -- --test=b3bench
##       [--bench=armies]   4 armies of 90 (360 fighters: knights, archers, gunners,
##                          cavalry, redcoat bayonet lines, raptors...) plus 8 vehicles,
##                          a tower and a bridge with archers on them, mines and barrels
##       [--bench=big]      the 🎖️ Huge Battle scenario (150 fighters)
##       [--size=1.0]       armies: fighters per army x this (1.0 = 90)
##       [--secs=30]        battle seconds to time after Fight!
##       [--map=grassland]
## Every frame runs one physics step (as in the game at 60 fps) as fast as the
## computer can. It prints, for each 5 seconds of battle and in total:
##   frame      everything the computer does for one 1/60 s step (no drawing:
##              it's headless): the scripts, the physics engine, _process, freeing
##   script     all the _physics_process scripts (fighter brains, projectiles...)
##   phys+rest  the physics engine step and the frame's housekeeping (moving the
##              models' parts after the bodies moved, freeing things)
##   proc       all the _process scripts (model animation, effects)
## A frame over 16.7 ms can't keep 60 fps even before drawing anything.
## Milliseconds jump about when the computer is busy with other things. To
## compare two versions, run each a few times, or count the work instead: on
## a Mac, `/usr/bin/time -l godot --headless --path . --fixed-fps 60 -- --test=b3bench`
## ends with "instructions retired", which hardly changes from run to run
## (with --fixed-fps the same battle plays out every time).

var recording := false
var frame_ms: Array[float] = []     # whole frame (ms), one per physics step
var scripts: Array[float] = []      # _physics_process scripts (ms)
var procs: Array[float] = []        # _process scripts (ms)
var _tick_t0 := 0
var _tick_ms := 0.0
var _proc_t0 := 0
var _proc_ms := 0.0
var _have_tick := false


class Probe extends Node:
	var bench = null
	var first := true

	func _init(b_, f: bool) -> void:
		bench = b_
		first = f
		process_physics_priority = -1000000 if f else 1000000
		process_priority = -1000000 if f else 1000000

	func _physics_process(_dt: float) -> void:
		bench.on_tick(first)

	func _process(_dt: float) -> void:
		bench.on_proc(first)


func on_tick(first: bool) -> void:
	var now := Time.get_ticks_usec()
	if first:
		if recording and _have_tick:
			frame_ms.append((now - _tick_t0) / 1000.0)
			scripts.append(_tick_ms)
			procs.append(_proc_ms)
		_tick_t0 = now
		_have_tick = true
		_proc_ms = 0.0
	else:
		_tick_ms = (now - _tick_t0) / 1000.0


func on_proc(first: bool) -> void:
	var now := Time.get_ticks_usec()
	if first:
		_proc_t0 = now
	else:
		_proc_ms += (now - _proc_t0) / 1000.0


func _ready() -> void:
	await get_tree().process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var which := String(args.get("bench", "armies"))
	var secs := float(args.get("secs", "30"))
	var size_k := float(args.get("size", "1.0"))
	var map := String(args.get("map", "grassland"))
	seed(1234)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 4321, "no_ui": true, "map": map})
	add_child(Probe.new(self, true))
	add_child(Probe.new(self, false))
	match which:
		"big":
			B3Scenarios._build(b, "big")
		_:
			_armies(size_k)
	var n_units: int = b.units.size()
	# one physics step per frame, as fast as it goes (each step is still 1/60 s
	# of battle). With --fixed-fps 60 every frame is exactly 1/60 s for
	# _process too, as in the game at 60 fps; without it, frames go 32x faster
	# than real time (so _process sees bigger steps).
	Engine.max_fps = 0
	OS.low_processor_usage_mode_sleep_usec = 0      # headless otherwise naps ~7 ms every frame
	Engine.max_physics_steps_per_frame = 1
	var fixed := true      # (--fixed-fps 60: every frame's delta is exactly 1/60 s)
	for i in 3:
		await get_tree().process_frame
		fixed = fixed and absf(get_process_delta_time() - 1.0 / 60.0) < 1e-6
	if not fixed:
		Engine.physics_ticks_per_second = 60 * 32
		Engine.time_scale = 32.0
		print("(add --fixed-fps 60 before the -- to time it exactly as the game runs at 60 fps)")
	for i in 20:
		await get_tree().physics_frame
	print("b3bench %s on %s: %d units (%d vehicles), %d buildings, %d props" % [which, map, n_units, _vehicles(), b.structs.size(), b.props.size()])
	# standing about before Fight!
	await _window("waiting", 2.0)
	_clear_samples()
	b.set_fighting(true)
	var all_f: Array[float] = []
	var all_s: Array[float] = []
	var all_p: Array[float] = []
	var t_start := Time.get_ticks_usec()
	var sim0: float = b.time
	var w := 0.0
	while w < secs - 0.01:
		var span := minf(5.0, secs - w)
		await _window("%3.0f-%2.0fs" % [w, w + span], span)
		all_f.append_array(frame_ms)
		all_s.append_array(scripts)
		all_p.append_array(procs)
		_clear_samples()
		w += span
	var real := (Time.get_ticks_usec() - t_start) / 1000000.0
	print("b3bench %s TOTAL %d units, %.0f s of battle in %.1f s: frame avg %.2f ms, p50 %.2f, p95 %.2f, p99 %.2f, worst %.1f ms | script avg %.2f worst %.1f | phys+rest avg %.2f | proc avg %.2f" % [
		which, n_units, b.time - sim0, real, _avg(all_f), _pct(all_f, 0.5), _pct(all_f, 0.95), _pct(all_f, 0.99), _pct(all_f, 1.0),
		_avg(all_s), _pct(all_s, 1.0), _avg(all_f) - _avg(all_s) - _avg(all_p), _avg(all_p)])
	b.queue_free()
	for i in 3:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	finish()


func _clear_samples() -> void:
	frame_ms.clear()
	scripts.clear()
	procs.clear()


## Times `t` seconds of battle and prints one line about it.
func _window(label: String, t: float) -> void:
	_clear_samples()
	recording = true
	_have_tick = false
	var end: float = b.time + t
	while b.time < end - 0.0001:
		await get_tree().physics_frame
	recording = false
	var up := 0
	var down := 0
	for u in b.units:
		if u.down:
			down += 1
		else:
			up += 1
	var corpses := 0
	for rd in b.ragdolls:
		if is_instance_valid(rd) and rd.dead:
			corpses += 1
	print("  %-9s frame avg %6.2f ms  p99 %6.2f  worst %6.1f | script %5.2f phys+rest %5.2f proc %5.2f | up %3d down %3d corpses %3d chunks %3d shots %3d" % [
		label, _avg(frame_ms), _pct(frame_ms, 0.99), _pct(frame_ms, 1.0), _avg(scripts),
		_avg(frame_ms) - _avg(scripts) - _avg(procs), _avg(procs),
		up, down, corpses, b.chunks.size(), b.proj_root.get_child_count()])


func _avg(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += x
	return s / a.size()


func _pct(a: Array[float], q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]


func _vehicles() -> int:
	var n := 0
	for u in b.units:
		if u is B3Vehicle:
			n += 1
	return n


## A block of fighters: `mix` is [[kind, how many], ...], filled in rows of
## `cols` facing `face` (a unit vector), centred on `c`.
func _block(team: String, c: Vector3, face: Vector3, mix: Array, k: float) -> void:
	var side := Vector3(-face.z, 0, face.x)
	var cols := 15
	var i := 0
	for m in mix:
		var n := maxi(1, roundi(int(m[1]) * k))
		for j in n:
			var row := i / cols
			var col := i % cols
			var p: Vector3 = c - face * (row * 2.0) + side * ((col - cols * 0.5) * 1.8)
			b.spawn_unit(String(m[0]), team, at(p.x, p.z))
			i += 1


## 4 armies closing in from the 4 sides, with a few vehicles, two buildings
## with archers on top, mines and barrels in the middle.
func _armies(k: float) -> void:
	_block("red", at(-34, 0), Vector3.RIGHT, [["knight", 15], ["soldier", 20], ["redcoat", 10], ["viking", 10], ["gunner", 10], ["archer", 15], ["medic", 5], ["cavalry", 5]], k)
	_block("blue", at(34, 0), Vector3.LEFT, [["ninja", 15], ["soldier", 20], ["linesman", 15], ["stick", 15], ["rocketeer", 10], ["archer", 10], ["grenadier", 5]], k)
	_block("green", at(0, -34), Vector3.BACK, [["raptor", 10], ["wolf", 10], ["bull", 5], ["knight", 15], ["soldier", 20], ["gunner", 10], ["archer", 15], ["horseknight", 5]], k)
	_block("yellow", at(0, 34), Vector3.FORWARD, [["viking", 15], ["union", 20], ["gi", 20], ["archer", 15], ["sniper", 10], ["medic", 5], ["cavalry", 5]], k)
	b.spawn_unit("tank", "red", at(-46, 8))
	b.spawn_unit("tank", "blue", at(46, -8))
	b.spawn_unit("jeep", "green", at(10, -46))
	b.spawn_unit("car", "yellow", at(-10, 46))
	b.spawn_unit("cannon", "red", at(-48, -10))
	b.spawn_unit("mgnest", "blue", at(48, 10))
	b.spawn_unit("heli", "green", at(-10, -48))
	b.spawn_unit("plane", "yellow", at(10, 48))
	# a tower and a bridge with archers on them (they stand guard up there)
	b.spawn_struct("tower", at(-22, -22), 0.0)
	b.spawn_struct("bridge", at(22, 22), deg_to_rad(45.0))
	for o in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(-0.9, 0.9), Vector2(0.9, 0.9)]:
		var p := Vector3(-22 + o.x, 0, -22 + o.y)
		p.y = b.surface_y(Vector3(p.x, 60.0, p.z))
		b.spawn_unit("archer", "green", p, "defend")
	for i in 3:
		var p := Vector3(22, 0, 22) + Basis(Vector3.UP, deg_to_rad(45.0)) * Vector3(0, 0, -1.5 + i * 1.5)
		p.y = b.surface_y(Vector3(p.x, 60.0, p.z))
		b.spawn_unit("archer", "yellow", p, "defend")
	for i in 8:
		var a := TAU * i / 8.0
		b.spawn_prop("mine", at(cos(a) * 9.0, sin(a) * 9.0))
		b.spawn_prop("xbarrel", at(cos(a + 0.4) * 15.0, sin(a + 0.4) * 15.0))

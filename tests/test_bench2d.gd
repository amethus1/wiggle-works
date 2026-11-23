extends TestBase
## A big, busy 2D scene for measuring speed: a 160-fighter battle in Battle
## Valley (more than the game's own limit of 120) with toys, Wigglies, fans,
## magnets, bubblers, a saucer, cars, a Ferris wheel, wired lamps and motors,
## ropes and springs, a water tub, rain and wind, and Wiggly powers and bombs
## going off every second or so (zaps, ice, bubbles, fire, goo, ground pounds).
## It isn't part of the test suite.
##
##   godot --headless --path . --fixed-fps 120 -- --test=bench2d
##       [--fighters=160] [--secs=20] [--seed=7] [--world=battle] [--calm | --ko] [--prof] [--verbose]
##   godot --path . --fixed-fps 120 -- --test=bench2d --secs=3 --shot=big.png   (a picture of it)
##
## --fixed-fps 120 runs exactly one physics step per frame, as fast as the
## computer can, so every run plays out the same battle: the "fingerprint" at
## the end only changes if the game behaves differently (or the seed changes).
## --calm is just the battle: no toys, Wigglies, machines, magic or powers.
## --ko is the aftermath: everyone is knocked out at the start, in heaps.
## --prof also shows which part of the world's physics step the time goes to,
## --verbose prints how things stand every second, and --shot=file.png (in a
## window, not --headless) saves what it looks like at the end.
##
## Prints, per physics step: the average, the 99th percentile and the worst
## time (milliseconds), split into the game's _physics_process scripts and the
## rest (Godot's physics engine and the bodies' _integrate_forces callbacks),
## and per frame the time for _process and drawing. Headless runs don't
## render, so the GPU's share isn't in there.

var w: World
var fx: Effects
var args := {}

# timing, per frame
var _proc_t := 0
var _done_t := 0
var _phys_a := 0
var _script_us := 0
var _steps := 0
var _measuring := false
var _fixed := true               # every frame was exactly one 1/120 s step (--fixed-fps 120)
var _blown_seen := 0
var _blowups: Array = []         # [sim seconds, how many] each time things were thrown miles out of the world at once
var _phys: Array[float] = []     # ms per physics step (everything)
var _script: Array[float] = []   # ms per physics step (_physics_process scripts)
var _frame: Array[float] = []    # ms per frame for _process and drawing


## Runs first (or last) among everyone's _physics_process and _process.
class Stamp extends Node:
	var on_phys := Callable()
	var on_proc := Callable()

	func _physics_process(_d: float) -> void:
		if on_phys.is_valid():
			on_phys.call()

	func _process(d: float) -> void:
		if on_proc.is_valid():
			on_proc.call(d)


func _ready() -> void:
	await get_tree().process_frame
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n_fighters := int(args.get("fighters", "160"))
	var secs := float(args.get("secs", "20"))
	var sd := int(args.get("seed", "7"))
	var wid := String(args.get("world", "battle"))
	Engine.max_fps = 0
	World.profiling = args.has("prof")
	seed(sd)

	w = World.new()
	add_child(w)
	fx = Effects.new()
	fx.world = w
	add_child(fx)
	w.fx.connect(fx.handle)
	w.load_world(wid, false)
	var cam := Cam.new()
	cam.effects = fx if not args.has("shot") else null   # (no screen shake in pictures: it follows the clock)
	add_child(cam)
	cam.make_current()
	cam.fit(w.view_rect, get_viewport().get_visible_rect().size)
	fx.view_rect = w.view_rect
	w.max_fighters = maxi(n_fighters, World.MAX_FIGHTERS)
	_build(n_fighters, args.has("calm") or args.has("ko"))
	w.battle_on = true
	if args.has("ko"):
		await get_tree().physics_frame
		for f in w.fighters():
			f.hurt(1e9, Vector2(randf_range(-250, 250), randf_range(-400, -100)))

	var first := Stamp.new()
	first.process_physics_priority = -1000000000
	first.process_priority = -1000000000
	first.on_phys = func() -> void:
		_phys_a = Time.get_ticks_usec()
	first.on_proc = func(d: float) -> void:
		_proc_t = Time.get_ticks_usec()
		if _measuring and (_steps != 1 or absf(d - 1.0 / Engine.physics_ticks_per_second) > 1e-6):
			_fixed = false
	add_child(first)
	var last := Stamp.new()
	last.process_physics_priority = 1000000000
	last.process_priority = 1000000000
	last.on_phys = func() -> void:
		_script_us += Time.get_ticks_usec() - _phys_a
		_steps += 1
	# the drawing happens after every _process, as deferred calls: this one comes after them
	last.on_proc = func(_d: float) -> void:
		_frame_done.call_deferred()
	add_child(last)

	# warm up for a second, then measure
	var timeline := _events() if not (args.has("calm") or args.has("ko")) else []
	var steps_total := int(secs * Engine.physics_ticks_per_second)
	var step := 0
	var warm := Engine.physics_ticks_per_second
	while step < warm + steps_total:
		await get_tree().physics_frame
		if step == warm:
			_measuring = true
			w.prof.clear()
		var sim_t := float(step) / Engine.physics_ticks_per_second
		if args.has("verbose") and step % 120 == 0:
			var lying := w.fighters().filter(func(f): return f.has_method("is_resting") and f.is_resting()).size()
			print("  %.0f s: %d fighters (%d lying still), %d toys, %d particles, %d ms since start" % [sim_t, w.fighters().size(), lying, w.toys().size(), fx.particle_count(), Time.get_ticks_msec()])
		while not timeline.is_empty() and float(timeline[0][0]) <= sim_t:
			(timeline.pop_front()[1] as Callable).call()
		if w.blown > _blown_seen:
			_blowups.append([sim_t, w.blown - _blown_seen])
			_blown_seen = w.blown
		step += 1
	_measuring = false
	await get_tree().process_frame
	_report(n_fighters, secs, sd, wid, _fixed)
	if args.has("shot") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img = UI.srgb_image(img)      # (HDR viewports hand back linear half-floats)
		img.save_png(String(args.shot))
		print("saved ", args.shot)
	get_tree().quit(0)


## End of a frame: physics steps = everything since the last frame ended,
## except this frame's _process and drawing.
func _frame_done() -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _done_t > 0 and _steps > 0:
		var frame_us := now - _done_t
		var proc_us := now - _proc_t
		var per_step := float(frame_us - proc_us) / _steps / 1000.0
		var script_step := float(_script_us) / _steps / 1000.0
		for i in _steps:
			_phys.append(per_step)
			_script.append(script_step)
		_frame.append(proc_us / 1000.0)
	_done_t = now
	_script_us = 0
	_steps = 0


# ------------------------------------------------------------------ the scene
func _build(n_fighters: int, calm: bool) -> void:
	var people := ["soldier", "knight", "viking", "archer", "gunner", "rocketeer", "grenadier", "ninja", "medic", "stick", "sniper", "soldier"]
	var beasts := ["wolf", "bear", "raptor", "bull", "chicken", "triceratops"]
	var half := n_fighters / 2
	for i in half:
		var row := i / 20
		var col := i % 20
		for side in [-1.0, 1.0]:
			var kind: String = people[(i + (3 if side > 0 else 0)) % people.size()]
			if i % 9 == 4:
				kind = beasts[(i / 9 + (1 if side > 0 else 0)) % beasts.size()]
			var f := w.spawn_fighter(kind, Vector2(side * (320.0 + col * 55.0 + row * 18.0), 120.0 - row * 70.0), "red" if side < 0 else "blue", "")
			if f:
				# tougher than usual, so most are still fighting at the end
				f.max_hp *= 3.0
				f.hp = f.max_hp
	if n_fighters % 2 == 1:
		w.spawn_fighter("trex", Vector2(0, -200), "wild", "")
	if calm:
		return
	# blocks and balls to knock about
	var blocks := ["wood_block", "brick", "abc_block", "plank", "glass_pane", "ice_cube", "pillow", "metal_beam"]
	for i in 24:
		w.spawn_toy(blocks[i % blocks.size()], Vector2(-700.0 + (i % 12) * 120.0, -60.0 - (i / 12) * 60.0))
	var balls := ["beach_ball", "bouncy_ball", "soccer_ball", "bowling_ball", "marble", "steel_ball"]
	for i in 12:
		w.spawn_toy(balls[i % balls.size()], Vector2(-600.0 + i * 100.0, -250.0))
	for x in [-1250.0, 1250.0]:
		w.spawn_toy("barrel", Vector2(x, 0))
	# machines that act on the fighters
	for x in [-900.0, -350.0, 350.0, 900.0]:
		var fan := w.spawn_toy("fan", Vector2(x - 120.0, 200))
		fan.on = true
		fan.nailed = true
		fan.update_freeze()
	for x in [-500.0, 500.0]:
		var mag := w.spawn_toy("magnet", Vector2(x, 200))
		mag.on = true
		var bub := w.spawn_toy("bubbler", Vector2(x + 150.0, 200))
		bub.on = true
		bub.set_facing(-signf(x))
	var saucer := w.spawn_toy("saucer", Vector2(0, -250))
	saucer.on = true
	# rides: cars drive back and forth through the armies
	for x in [-1500.0, 1500.0]:
		var kart := Builders.ride(w, "go_kart", Vector2(x, 50))
		if kart:
			kart.on = true
			kart.set_facing(-signf(x))
		var truck := Builders.ride(w, "monster_truck", Vector2(x * 0.7, -20))
		if truck:
			truck.on = true
			truck.set_facing(-signf(x))
	Builders.build(w, "ferris", Vector2(-1700, -200))
	Builders.build(w, "lamp_show", Vector2(1700, -200))
	Builders.build(w, "catapult", Vector2(0, -420))
	# a power network: a battery and a switch wired to lamps, motors and a bell
	var bat := w.spawn_toy("battery", Vector2(-200, -500))
	var sw := w.spawn_toy("switch", Vector2(-100, -500))
	sw.on = true
	w.add_link("wire", bat, sw, bat.global_position, sw.global_position)
	var prev: Toy = sw
	for i in 8:
		var id: String = ["lamp", "motor", "lamp", "bell", "lamp", "fan", "lamp", "propeller"][i]
		var t := w.spawn_toy(id, Vector2(0 + i * 60.0, -560))
		if t == null:
			continue
		t.nailed = id != "propeller"
		t.update_freeze()
		w.add_link("wire", prev if i % 2 == 0 else sw, t, t.global_position, t.global_position)
		prev = t
	# ropes and springs between blocks
	var ts: Array = w.toys()
	for i in 8:
		var a: Toy = ts[i]
		var b: Toy = ts[i + 12]
		w.add_link("rope" if i % 2 == 0 else "spring", a, b, a.global_position, b.global_position)
	# a tub of water to splash in
	Builders.tub(w, "water_tub", Vector2(-1150, 0))
	# Wigglies of every kind
	var x0 := -1000.0
	for i in 24:
		var kind: String = Catalog.WIGGLY_ORDER[i % Catalog.WIGGLY_ORDER.size()]
		w.spawn_wiggly(kind, Vector2(x0 + i * 85.0, -350.0 - (i % 3) * 60.0), 1.0 + (i % 4) * 0.25)


## Things that happen during the run, at set times: [sim seconds, Callable].
func _events() -> Array:
	var ev: Array = []
	var specials := ["zappy", "frosty", "puffy", "blaze", "gummy", "boulder", "bloop", "twinkle"]
	for i in 24:
		var t := 0.5 + i * 0.9
		var kind: String = specials[i % specials.size()]
		ev.append([t, func() -> void:
			for wg in w.wigglies():
				if wg.kind == kind:
					wg.use_special()
					break])
	for i in 6:
		var t := 1.0 + i * 3.3
		var id: String = ["bubble_bomb", "freeze_bomb", "glue_bomb", "paint_bomb", "boom_barrel", "napalm"][i]
		ev.append([t, func() -> void:
			var b := w.spawn_toy(id, Vector2(-400.0 + i * 160.0, -300))
			if b:
				ToyLogic.light_fuse(w, b)])
	ev.append([3.0, func() -> void: w.cast_magic("rain")])
	ev.append([9.0, func() -> void: w.cast_magic("wind")])
	ev.append([14.0, func() -> void: w.cast_magic("party")])
	ev.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return ev


# ------------------------------------------------------------------ results
static func _stats(a: Array[float]) -> Dictionary:
	if a.is_empty():
		return {"avg": 0.0, "p99": 0.0, "max": 0.0}
	var total := 0.0
	for v in a:
		total += v
	var s := a.duplicate()
	s.sort()
	return {"avg": total / a.size(), "p99": s[mini(s.size() - 1, int(s.size() * 0.99))], "max": s[s.size() - 1]}


func _report(n_fighters: int, secs: float, sd: int, wid: String, fixed: bool) -> void:
	var ph := _stats(_phys)
	var sc := _stats(_script)
	var fr := _stats(_frame)
	var up := {}
	var ko := 0
	var resting := 0
	for f in w.fighters():
		if f.alive():
			up[f.team] = int(up.get(f.team, 0)) + 1
		else:
			ko += 1
			if f.has_method("is_resting") and f.is_resting():
				resting += 1
	var scene := " (calm)" if args.has("calm") else (" (all knocked out)" if args.has("ko") else "")
	print("bench2d: %d fighters on %s%s, %.0f s, seed %d%s" % [n_fighters, wid, scene, secs, sd, "" if fixed else "  (add --fixed-fps 120 for the same battle every run)"])
	print("  now: %d fighters (%s still up, %d knocked out, %d of them lying still), %d toys, %d Wigglies, %d links, %d particles" % [w.fighters().size(), str(up), ko, resting, w.toys().size(), w.wigglies().size(), w.links.size(), fx.particle_count()])
	print("  physics step: avg %.2f ms, p99 %.2f ms, worst %.2f ms   (%d steps)" % [ph.avg, ph.p99, ph.max, _phys.size()])
	print("    _physics_process scripts: avg %.2f ms, p99 %.2f ms, worst %.2f ms" % [sc.avg, sc.p99, sc.max])
	print("    physics engine and callbacks: avg %.2f ms" % [ph.avg - sc.avg])
	print("  frame (_process + drawing): avg %.2f ms, p99 %.2f ms, worst %.2f ms" % [fr.avg, fr.p99, fr.max])
	if World.profiling and not _phys.is_empty():
		var parts: Array = w.prof.keys()
		parts.sort_custom(func(a, b): return int(w.prof[a]) > int(w.prof[b]))
		var line := "  world step by part (avg ms):"
		for k in parts:
			line += " %s %.2f," % [k, float(w.prof[k]) / _phys.size() / 1000.0]
		print(line.trim_suffix(","))
	var most: Array = [0.0, 0]
	for e in _blowups:
		if int(e[1]) > int(most[1]):
			most = e
	print("  out of the world: %d; thrown miles out in one step: %d (the most at once %d at %.1f s)" % [w.flung, w.blown, int(most[1]), float(most[0])])
	print("  fingerprint: %s" % _fingerprint())
	print("test_bench2d: done")


## Changes if anything in the battle turned out differently.
func _fingerprint() -> String:
	var bits: Array = []
	for f in w.fighters():
		var c: Vector2 = f.center()
		bits.append([f.uid, f.state, roundi(c.x), roundi(c.y), roundi(f.hp)])
	for t in w.toys():
		bits.append([t.uid, t.id, roundi(t.global_position.x), roundi(t.global_position.y)])
	for wg in w.wigglies():
		bits.append([wg.uid, roundi(wg.com.x), roundi(wg.com.y)])
	return "%08x" % (str(bits).hash() & 0xffffffff)

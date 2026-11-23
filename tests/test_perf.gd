extends TestBase
## Rough timing: how long one physics step takes in a big battle.
##   godot --headless --path . -- --test=perf          the 2D game
##   godot --path . -- --test=perf --b3=grassland      3D Battle, 150 fighters, real frames
##       [--fp] looks out of a fighter's eyes, [--secs=12]

func _ready() -> void:
	await get_tree().process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("b3"):
		await _battle3d(String(args.b3) if String(args.b3) != "1" else "grassland", args.has("fp"), float(args.get("secs", "12")))
		get_tree().quit(0)
		return
	var w := World.new()
	add_child(w)
	var fx := Effects.new()
	fx.world = w
	add_child(fx)
	w.fx.connect(fx.handle)
	w.load_world("battle", false)
	var kinds := ["soldier", "knight", "viking", "archer", "gunner", "rocketeer", "grenadier", "ninja", "medic", "stick"]
	for i in 40:
		w.spawn_fighter(kinds[i % kinds.size()], Vector2(-1400 + i * 30, 100), "red", "")
		w.spawn_fighter(kinds[(i + 3) % kinds.size()], Vector2(1400 - i * 30, 100), "blue", "")
	for i in 6:
		w.spawn_toy("barrel", Vector2(-200 + i * 80, 100))
	w.battle_on = true
	var worst := 0.0
	var total := 0.0
	var n := 0
	for i in 120 * 20:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		if i > 60:
			worst = maxf(worst, dt)
			total += dt
			n += 1
		if i % 240 == 0:
			print("t=%2ds fighters up=%d avg=%.2fms worst=%.1fms" % [i / 120, w.fighters().filter(func(f): return f.alive()).size(), total / maxf(1, n), worst])
	print("avg frame %.2f ms, worst %.1f ms, physics %.0f/s" % [total / n, worst, Engine.physics_ticks_per_second])
	get_tree().quit(0)


## 3D Battle: 75 v 75 fighters on a big map, with the real renderer (run it
## with a window). Prints frame times, draw calls and what the map holds.
func _battle3d(map: String, fp: bool, secs: float) -> void:
	var old_health := B3Rules.value("health")
	B3Rules.set_value("health", "super")     # so most of them are still up at the end
	var b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 7, "map": map})
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var kinds := ["soldier", "knight", "viking", "archer", "gunner", "rocketeer", "grenadier", "ninja", "medic", "stick"]
	for i in 75:
		var row := i / 15
		var col := i % 15
		for side in [-1.0, 1.0]:
			var x := float(side) * (22.0 + row * 2.2)
			var z := -16.0 + col * 2.3
			b.spawn_unit(kinds[(i + (3 if side > 0 else 0)) % kinds.size()], "red" if side < 0 else "blue",
				Vector3(x, b.world.height_at(x, z), z))
	b.cam.fit(Vector3.ZERO, 60.0)
	b.set_fighting(true)
	if fp and b.tools:
		for u in b.units:
			if u.team == "red":
				b.tools.play_as(u, true)
				break
	var w: B3World = b.world
	var mmi := 0
	var inst := 0
	for c in w.scenery.get_children():
		if c is MultiMeshInstance3D:
			mmi += 1
			inst += (c as MultiMeshInstance3D).multimesh.instance_count
	print("map %s: %d trees/rocks with colliders, %d scenery MultiMeshes holding %d instances" % [map, w._bodies.size(), mmi, inst])
	for i in 30:
		await get_tree().process_frame
	var times: Array[float] = []
	var draws := 0.0
	var prims := 0.0
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n := times.size()
	var total := 0.0
	for t in times:
		total += t
	var sorted := times.duplicate()
	sorted.sort()
	var up := 0
	for u in b.units:
		if not u.dead:
			up += 1
	print("%s %s: %d frames in %.1fs, avg %.2f ms (%.0f fps), 1%% worst %.1f ms, max %.1f ms; %.0f draw calls, %.0fk triangles; %d fighters still up" % [
		map, "first person" if fp else "overhead", n, total / 1000.0, total / n, 1000.0 * n / total,
		sorted[int(n * 0.99)], sorted[n - 1], draws / n, prims / n / 1000.0, up])
	B3Rules.set_value("health", old_health)

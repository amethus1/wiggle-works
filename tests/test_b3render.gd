extends Node
## 3D Battle drawing benchmark: how much the renderer has to do in big
## scenes. It needs a real window (headless doesn't draw), so it isn't part
## of tools/run_tests.sh.
##   godot --path . -- --test=b3render                 every scene below
##       [--scene=big,fp,...]  just these (comma-separated)
##       [--secs=5]            seconds to measure each scene (after warming up)
##       [--out=/abs/file.json] also save the numbers (to compare two runs)
## Scenes (nobody fights, so draw calls and node counts come out the same
## every run; frame times are only worth comparing back-to-back):
##   big        🎖️ Huge Battle: 150 fighters, overhead
##   army400    400 fighters of every kind (people, riders, animals,
##              dinosaurs, History) and 12 vehicles, zoomed out
##   vehicles   🚜 Tank Line (tanks, jeeps, cannon, MG nests and an army)
##   airshow    ✈️ Air Show (6 planes, 4 helicopters, 60 fighters)
##   farmland   the farmland map (crops, grass) overhead, zoomed out, and
##   farm_far   zoomed right out (simpler crops and grass), and
##   farm_fp    looking out of a fighter's eyes on it
##   rain, snow the Huge Battle in the rain / snow
##   fp         the Huge Battle in first person
## For each it prints:
##   draws    draw calls per frame (all passes: shadows, depth, colour)
##   objects  objects drawn per frame (also counted once per pass)
##   tris     triangles per frame (thousands)
##   nodes    nodes in the whole scene tree (HUD and map too); units: nodes
##            making up the fighters and vehicles; meshes: MeshInstance3Ds
##   mats     materials made for the models and effects (B3Mats)
##   frame    whole frame (ms, median); cpu/gpu: the 3D viewport's render
##            time on the CPU (culling, sending draw calls) and on the GPU
##   setup    how long building the scene took (ms)
## GPU time shows "n/a" where the driver can't time the GPU (Metal on a Mac).
##
## Screenshots to compare two versions pixel by pixel (seeded, and the same
## number of frames every run; --fixed-fps 60 makes time step the same too):
##   godot --path . --fixed-fps 60 -- --test=b3render --shots=/abs/dir [--only=lineup,ko,...]
## closeup, lineup, garage, showcase, vehicles, monsters, big, king (crowns),
## fp (playing a fighter in first person), ko (knocked-out ragdolls with X
## eyes), wreck (a tank and a jeep blown apart), poses (raised shields, a kick,
## hit flashes, a fighter that changed team), rain, snow, farm_fp, hangar,
## farm_near / farm_edge / farm_far (farmland overhead at zoom 60, 100, 150)

const ALL := ["big", "army400", "vehicles", "airshow", "farmland", "farm_far", "farm_fp", "rain", "snow", "fp"]

var _rows: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		print("b3render needs a window: run it without --headless")
		get_tree().quit(1)
		return
	# someone may be using the computer: their keys and clicks mustn't land in here
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	if args.has("shots"):
		await _shots(String(args.shots), Array(String(args.get("only", "")).split(",", false)))
		get_tree().quit(0)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var scenes: Array = ALL if not args.has("scene") or String(args.scene) == "all" else Array(String(args.scene).split(",", false))
	var secs := float(args.get("secs", "5"))
	var old_rules := {"weather": B3Rules.value("weather"), "time": B3Rules.value("time"), "health": B3Rules.value("health")}
	print("scene        draws  objects   tris    nodes  units  meshes  mats   frame    cpu    gpu   setup")
	for s in scenes:
		await _scene(String(s), secs)
	for k in old_rules:
		if B3Rules.value(k) != String(old_rules[k]):
			B3Rules.set_value(k, String(old_rules[k]))
	if args.has("out"):
		var f := FileAccess.open(String(args.out), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_rows, "  "))
			f.close()
			print("saved ", args.out)
	get_tree().quit(0)


func _scene(id: String, secs: float) -> void:
	var map := "grassland"
	var sc := ""
	var fp := false
	var weather := "clear"
	var zoom := 0.0
	match id:
		"big", "fp", "rain", "snow":
			sc = "big"
			fp = id == "fp"
			weather = id if id == "rain" or id == "snow" else "clear"
		"army400":
			sc = "army400"
		"vehicles", "airshow":
			sc = id
			map = B3Scenarios.map_for(id)
		"farmland", "farm_far":
			map = "farmland"
			sc = "farm"
			zoom = 110.0 if id == "farmland" else 160.0
		"farm_fp":
			map = "farmland"
			sc = "farm"
			fp = true
		_:
			print("unknown scene ", id)
			return
	if B3Rules.value("weather") != weather:
		B3Rules.set_value("weather", weather)
	if B3Rules.value("time") != "day":
		B3Rules.set_value("time", "day")
	var t0 := Time.get_ticks_usec()
	var b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 7, "map": map})
	_deaf(b)
	match sc:
		"army400":
			_army400(b)
		"farm":
			_farm(b)
		"":
			pass
		_:
			B3Scenarios._build(b, sc)
	if zoom > 0.0:
		b.cam.fit(Vector3.ZERO, zoom)
	var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if fp and b.tools:
		for u in b.units:
			if u.team == "red" and String(u.def.body) == "human":
				b.tools.play_as(u, true)
				break
	# warm up: shaders compiling, particles filling the sky, things settling
	var warm_end := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < warm_end:
		await get_tree().process_frame
	var vp := get_viewport().get_viewport_rid()
	var frames: Array[float] = []
	var cpus: Array[float] = []
	var gpus: Array[float] = []
	var draws: Array[float] = []
	var objs: Array[float] = []
	var tris: Array[float] = []
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		cpus.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	var meshes: int = (b as Node).find_children("*", "MeshInstance3D", true, false).size()
	var unit_nodes: int = (b.unit_root as Node).find_children("*", "", true, false).size()
	var gpu := _med(gpus)
	var row := {"scene": id, "draws": _med(draws), "objects": _med(objs), "tris_k": _med(tris) / 1000.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "unit_nodes": unit_nodes, "meshes": meshes,
		"mats": B3Mats._mats.size(),
		"frame_ms": _med(frames), "frame_avg_ms": _avg(frames), "cpu_ms": _med(cpus), "gpu_ms": gpu,
		"setup_ms": setup_ms, "units": b.units.size(), "frames": frames.size(),
		"vmem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}
	_rows.append(row)
	print("%-10s %7.0f %8.0f %6.0fk %8d %6d %7d %5d %6.2f %6.2f %6s %7.0f" % [id, row.draws, row.objects, row.tris_k,
		row.nodes, row.unit_nodes, row.meshes, row.mats, row.frame_ms, row.cpu_ms, "%.2f" % gpu if gpu > 0.0 else "n/a", row.setup_ms])
	if b.tools:
		b.tools.stop_playing()
	b.queue_free()
	for i in 3:
		await get_tree().process_frame


## 400 fighters of every kind in four armies, plus vehicles.
func _army400(b) -> void:
	var kinds: Array[String] = []
	for cat in ["people", "history", "animals", "dinos"]:
		for k in B3Defs.UNIT_ORDER.get(cat, []):
			var d := B3Defs.unit_def(String(k))
			if not bool(d.get("flying", false)) and String(d.get("body", "")) != "dragon":
				kinds.append(String(k))
	var teams := ["red", "blue", "green", "yellow"]
	for t in 4:
		var a := TAU * t / 4.0 + PI * 0.25
		var c := Vector3(cos(a), 0, sin(a)) * 38.0
		var side := Vector3(-sin(a), 0, cos(a))
		var back := Vector3(cos(a), 0, sin(a))
		for i in 100:
			var p := c + side * ((i % 20) - 9.5) * 2.6 + back * (i / 20) * 3.2
			p.y = b.world.height_at(p.x, p.z)
			b.spawn_unit(kinds[(i * 7 + t * 13) % kinds.size()], teams[t], p, "auto", a + PI)
		for j in 3:
			var vk := String(["tank", "jeep", "cannon"][j])
			var q := c + back * 22.0 + side * (j - 1) * 9.0
			q.y = b.world.height_at(q.x, q.z)
			b.spawn_unit(vk, teams[t], q, "auto", a + PI)
	b.cam.fit(Vector3.ZERO, 95.0)


## Farmland with two small armies standing in the middle.
func _farm(b) -> void:
	B3Scenarios._army(b, "red", -1.0, [["soldier", 0, 10], ["knight", 1, 10]])
	B3Scenarios._army(b, "blue", 1.0, [["soldier", 0, 10], ["viking", 1, 10]])
	b.cam.fit(Vector3.ZERO, 40.0)


func _med(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _avg(a: Array[float]) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / maxf(1.0, a.size())


# ------------------------------------------------------------- screenshots
const SHOTS := ["closeup", "lineup", "garage", "showcase", "vehicles", "monsters", "big", "king", "fp",
	"ko", "wreck", "poses", "rain", "snow", "farm_fp", "hangar", "farm_near", "farm_edge", "farm_far"]


func _shots(dir: String, only: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var old_rules := {"weather": B3Rules.value("weather"), "time": B3Rules.value("time")}
	for id in SHOTS:
		if not only.is_empty() and not only.has(id):
			continue
		await _shot(String(id), dir.path_join(String(id) + ".png"))
	for k in old_rules:
		if B3Rules.value(k) != String(old_rules[k]):
			B3Rules.set_value(k, String(old_rules[k]))


func _shot(id: String, path: String) -> void:
	var weather := id if id == "rain" or id == "snow" else "clear"
	if B3Rules.value("weather") != weather:
		B3Rules.set_value("weather", weather)
	if B3Rules.value("time") != "day":
		B3Rules.set_value("time", "day")
	seed(4242)
	var map := "grassland"
	match id:
		"vehicles", "garage", "hangar":
			map = B3Scenarios.map_for("vehicles")
		"farm_fp", "farm_near", "farm_edge", "farm_far":
			map = "farmland"
	var b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 7, "map": map})
	_deaf(b)
	var frames := 150
	match id:
		"closeup", "lineup", "garage", "showcase", "vehicles", "monsters", "big", "hangar":
			B3Scenarios._build(b, id)
		"king":
			B3Scenarios._build(b, "skirmish")
			for t in ["red", "blue"]:
				for u in b.units:
					if u.team == t and String(u.def.body) == "human":
						u.make_king()
						break
			b.cam.fit(B3Scenarios.at(b, 0, 0), 22.0)
		"fp", "farm_fp", "rain", "snow":
			if id == "farm_fp":
				_farm(b)
			else:
				B3Scenarios._build(b, "big")
			if id != "rain" and id != "snow":
				for u in b.units:
					if u.team == "red" and String(u.def.body) == "human":
						b.tools.play_as(u, true)
						break
				for i in 20:
					await get_tree().process_frame
				b.set_paused(true)      # (playing presses Fight!: pause it so every run looks the same)
		"farm_near", "farm_edge", "farm_far":
			_farm(b)
			b.cam.fit(Vector3(20, 0, -60), {"farm_near": 60.0, "farm_edge": 100.0, "farm_far": 150.0}[id])
			frames = 60
		"ko":
			var kinds := ["soldier", "knight", "robot", "horseknight", "wolf", "trex", "chicken", "gorilla", "hoplite", "wizard"]
			for i in kinds.size():
				var p := Vector3(-9.0 + i * 2.0, 0, (i % 2) * 2.5 - 1.0)
				p.y = b.world.height_at(p.x, p.z)
				b.spawn_unit(String(kinds[i]), "red" if i % 2 == 0 else "blue", p, "peaceful", 0.4)
			for i in 30:
				await get_tree().process_frame
			for u in b.units.duplicate():
				u._ko(Vector3(0.0, 2.0, 1.5), null)
			b.cam.fit(Vector3(0, 0, 0), 14.0)
			frames = 240
		"wreck":
			var tk = b.spawn_unit("tank", "blue", Vector3(-3, b.world.height_at(-3, 0), 0), "peaceful", 0.6)
			var jp = b.spawn_unit("jeep", "red", Vector3(4, b.world.height_at(4, 2), 2), "peaceful", 2.0)
			for i in 30:
				await get_tree().process_frame
			tk._wreck_visual(Vector3(1, 3, 0))
			jp._wreck_visual(Vector3(-1, 3, 0))
			b.cam.fit(Vector3(0, 0, 0), 16.0)
			frames = 200
		"poses":
			var kinds := ["knight", "hoplite", "legionary", "saxon", "soldier", "viking", "dog"]
			var us: Array = []
			for i in kinds.size():
				var p := Vector3(-6.0 + i * 2.0, 0, 0)
				p.y = b.world.height_at(p.x, p.z)
				us.append(b.spawn_unit(String(kinds[i]), "red", p, "peaceful", 0.3))
			for i in 20:
				await get_tree().process_frame
			for i in 4:
				us[i].shield_up = true
			us[4].set_team("green")
			us[6].set_team("yellow")
			b.cam.fit(Vector3(0, 0, 0), 10.0)
			frames = 60
			for i in frames:
				await get_tree().process_frame
			for u in us:
				if u.rig:
					u.rig._flash = 0.0
					u.rig._flash_rest = 0.0
			us[5].rig.flash()
			us[1].rig.flash()
			frames = 1
	for i in frames:
		if B3Player.active():
			# (the mouse would turn the view: keep it looking the same way every run)
			B3Player.me.look_yaw = B3Player.unit.facing + 0.35
			B3Player.me.look_pitch = -0.12
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if ProjectSettings.get_setting("rendering/viewport/hdr_2d", false):
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	img.save_png(path)
	print("saved ", path)
	if b.tools:
		b.tools.stop_playing()
	b.queue_free()
	for i in 3:
		await get_tree().process_frame


## Keys and the mouse do nothing in the battle (nobody's playing it here).
func _deaf(b) -> void:
	for n in [b, b.tools, b.ui, b.cam]:
		if n != null:
			(n as Node).set_process_input(false)
			(n as Node).set_process_unhandled_input(false)
			(n as Node).set_process_unhandled_key_input(false)

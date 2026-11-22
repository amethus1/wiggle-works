extends Node
## Headless checks for the 3D Battle maps (B3World): every map loads, the
## height field matches height_at() out to the edges, fighters placed far
## out (±150 m) stand on the ground, the volcano has its pools, beach water
## stops walkers, the pass is a narrow gap between cliffs, uprootable
## scenery is numbered, and a map is the same every time it's built.
## godot --headless --path . -- --test=maps

const SPEED := 4.0

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map: String) -> void:
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(4242)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 99, "no_ui": true, "map": map})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


## Ground height straight down from above, on the real collider.
func ray_y(x: float, z: float) -> float:
	var hit: Dictionary = b.raycast(Vector3(x, 400, z), Vector3(x, -100, z), B3Defs.L_TERRAIN)
	if hit.is_empty():
		return -9999.0
	var p: Vector3 = hit.position
	return p.y


func _ready() -> void:
	await get_tree().process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("shots"):
		await _shots(String(args.shots), String(args.get("map", "")), String(args.get("time", "")), String(args.get("weather", "clear")))
		get_tree().quit(0)
		return
	var t0 := Time.get_ticks_msec()
	await _every_map()
	await _volcano()
	await _beach_water()
	await _pass()
	await _scenery_numbers()
	await _uproot_tint()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	print("test_maps: done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("test_maps: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _every_map() -> void:
	for id in B3Defs.MAP_ORDER:
		var mid := String(id)
		print(mid)
		var md: Dictionary = B3Defs.MAPS[mid]
		var has_all := true
		for f in ["name", "icon", "ground", "ground2", "skirt", "sky_top", "sky_horizon", "sun", "sun_energy", "ambient", "dust"]:
			has_all = has_all and md.has(f)
		check(has_all, "%s: has every map field" % mid)
		B3World._memo.erase(mid)
		var t0 := Time.get_ticks_usec()
		await fresh(mid)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var w: B3World = b.world
		check(w.map_id == mid and w.half_size() >= 190.0, "%s: loads, %.0f m across (built in %.0f ms)" % [mid, w.half_size() * 2.0, ms])
		var t1 := Time.get_ticks_usec()
		await fresh(mid)
		print("        loading it again takes %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
		w = b.world
		# the collider matches height_at, right out to the edges and corners
		var worst := 0.0
		var spots: Array[Vector2] = []
		var e := w.half_size() - 0.3
		for v in [Vector2(e, e), Vector2(-e, e), Vector2(e, -e), Vector2(-e, -e), Vector2(e, 0), Vector2(-e, 3), Vector2(7, e), Vector2(-11, -e)]:
			spots.append(v)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 40:
			spots.append(Vector2(rng.randf_range(-e, e), rng.randf_range(-e, e)))
		var finite := true
		for s in spots:
			var hy: float = w.height_at(s.x, s.y)
			finite = finite and is_finite(hy) and absf(hy) < 200.0
			worst = maxf(worst, absf(ray_y(s.x, s.y) - hy))
		check(finite, "%s: height_at works out to the edges" % mid)
		check(worst < 0.08, "%s: the collider matches height_at (worst %.3f m)" % [mid, worst])
		# far out: pick dry, not-too-steep spots near ±150 m
		var us: Array = []
		for v in [Vector2(150, 150), Vector2(-150, 150), Vector2(150, -150), Vector2(-150, -150), Vector2(150, 0), Vector2(-150, 0), Vector2(0, -150), Vector2(0, 150)]:
			var p := _dry_spot(w, v)
			if p.x > 1e5:
				continue
			us.append(b.spawn_unit("soldier", "red", at(p.x, p.y) + Vector3(0, 0.3, 0), "peaceful"))
		await sim(2.0)
		var ok := 0
		for u in us:
			if not is_instance_valid(u) or u.dead:
				continue
			var gy: float = w.height_at(u.position.x, u.position.z)
			if u.position.y > gy - 0.5 and u.position.y < gy + 1.0:
				ok += 1
		check(us.size() >= 4 and ok == us.size(), "%s: soldiers placed ±150 m out stand on the ground (%d / %d)" % [mid, ok, us.size()])
		var u0 = b.spawn_unit("soldier", "blue", at(0, 0), "peaceful")
		await sim(0.5)
		check(absf(u0.position.y - w.height_at(u0.position.x, u0.position.z)) < 0.5, "%s: and one in the middle too" % mid)
		check(w.trees.size() > 40, "%s: has lots of trees and scenery (%d that can be knocked over)" % [mid, w.trees.size()])


func _dry_spot(w: B3World, near: Vector2) -> Vector2:
	for r in [0.0, 6.0, 12.0, 20.0, 30.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var p: Vector2 = near + Vector2(cos(a), sin(a)) * float(r)
			if w.water_depth(p.x, p.y) > 0.0 or w.water_level_at(p.x, p.y) > -1e8 and w.height_at(p.x, p.y) < 0.5:
				continue
			if w.normal_at(p.x, p.y).y < 0.85:
				continue
			var hit: Dictionary = b.raycast(Vector3(p.x, 400, p.y), Vector3(p.x, -100, p.y), B3Defs.L_TERRAIN | B3Defs.L_SCENERY | B3Defs.L_STRUCT)
			if hit.is_empty() or absf((hit.position as Vector3).y - w.height_at(p.x, p.y)) > 0.1:
				continue
			return p
	return Vector2(1e6, 1e6)


func _volcano() -> void:
	print("volcano")
	await fresh("volcano")
	var w: B3World = b.world
	check(w.builtin_pools.size() >= 3, "the volcano map comes with lava and acid pools (%d)" % w.builtin_pools.size())
	check(b.hazards.size() == w.builtin_pools.size(), "and they're all on the battlefield (%d)" % b.hazards.size())
	var middle := 0
	for p in w.builtin_pools:
		var pos: Vector3 = p.pos
		if Vector2(pos.x, pos.z).length() < 20.0:
			middle += 1
	check(middle == 3, "the three old pools are still in the middle")


func _beach_water() -> void:
	print("beach")
	await fresh("beach")
	var w: B3World = b.world
	check(w.water_depth(0, 120) > 3.0, "the sea is deep out from the beach (%.1f m)" % w.water_depth(0, 120))
	check(w.water_depth(0, 0) == 0.0 and w.water_depth(0, -60) == 0.0, "the beach and the bluffs are dry")
	check(w.height_at(0, -70) > w.height_at(0, 0) + 6.0, "bluffs rise behind the beach")
	# a berserk knight charges a pterodactyl out over the sea: the water stops him
	var k = b.spawn_unit("knight", "red", at(0, 40), "berserk")
	var k2 = b.spawn_unit("viking", "red", at(10, 40), "attack")
	var bird = b.spawn_unit("ptero", "blue", at(0, 130) + Vector3(0, 6, 0), "peaceful")
	b.set_fighting(true)
	var deepest := 0.0
	for i in 20:
		await sim(0.5)
		for u in [k, k2]:
			if is_instance_valid(u) and not u.dead:
				deepest = maxf(deepest, w.water_depth(u.position.x, u.position.z))
	check(is_instance_valid(bird) and bird.position.z > 90.0, "the bird stays out at sea")
	check(deepest < B3World.DEEP + 0.35, "walkers can't wade into deep water (deepest %.2f m)" % deepest)
	check(is_instance_valid(k) and not k.dead and k.position.z > 35.0, "but they do go into the shallows (z %.0f)" % k.position.z)


func _pass() -> void:
	print("pass")
	await fresh("pass")
	var w: B3World = b.world
	var floor_y: float = w.height_at(0, 0)
	var flat := true
	for x in range(-40, 41, 10):
		for z in [-7.0, 0.0, 7.0]:
			flat = flat and absf(w.height_at(x, z) - floor_y) < 2.5
	check(flat, "the pass floor is flat and about 20 m wide")
	var cliff := true
	for x in range(-40, 41, 10):
		cliff = cliff and w.height_at(x, -18) > floor_y + 15.0 and w.height_at(x, 16) > floor_y + 4.0
	check(cliff, "with steep cliffs on both sides")
	check(absf(w.height_at(-140, 0) - floor_y) < 6.0 and absf(w.height_at(140, 0) - floor_y) < 6.0, "and open ground at both ends")


func _scenery_numbers() -> void:
	print("scenery numbers")
	await fresh("grassland")
	var w: B3World = b.world
	var seen := {}
	var where := {}
	var ok := true
	for sb in w._bodies:
		var i: int = w.scenery_index(sb)
		ok = ok and i >= 0 and not seen.has(i)
		seen[i] = true
		where[i] = sb.global_position
	check(ok and seen.size() > 100, "every uprootable tree and rock has its own number (%d)" % seen.size())
	check(w.scenery_index(w.terrain) == -1 and w.scenery_index(null) == -1, "other things have no number")
	B3World._memo.erase("grassland")
	await fresh("grassland")
	w = b.world
	var same := w._bodies.size() == seen.size()
	for sb in w._bodies:
		var i: int = w.scenery_index(sb)
		same = same and where.has(i) and (where[i] as Vector3).is_equal_approx(sb.global_position)
	check(same, "rebuilding the map gives the same numbers in the same places")
	var some: int = w.scenery_index(w._bodies[7])
	var sb0: StaticBody3D = w._bodies[7]
	var before: int = b.chunks.size()
	w.uproot_index(some, Vector3(0, 8, 3), b)
	await get_tree().physics_frame
	check(b.chunks.size() == before + 1 and not is_instance_valid(sb0), "uproot_index knocks over that tree")
	w.uproot_index(some, Vector3(0, 8, 3), b)
	w.uproot_index(-1, Vector3.ZERO, b)
	w.uproot_index(12345678, Vector3.ZERO, b)
	check(b.chunks.size() == before + 1, "and doing it again (or a bad number) does nothing")


## A rock blown over keeps its colour (volcano rocks are dark, desert rocks
## sandy) instead of turning plain grey.
func _uproot_tint() -> void:
	print("uprooted rocks")
	await fresh("volcano")
	var w: B3World = b.world
	var sb: StaticBody3D = null
	for o in w._bodies:
		if is_instance_valid(o) and String(o.get_meta("scenery", "")) == "rock" and o.has_meta("mm"):
			sb = o
			break
	check(sb != null, "the volcano has rocks that can be blown over")
	if sb == null:
		return
	var before: int = b.chunks.size()
	w.uproot(sb, Vector3(0, 6, 2), b)
	var tint := Color.WHITE
	if b.chunks.size() == before + 1:
		var rb: RigidBody3D = b.chunks[b.chunks.size() - 1]
		for c in rb.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
				tint = ((c as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	check(tint.r < 0.5 and tint.g < 0.5 and tint.b < 0.5, "a blown-over volcano rock stays dark (%s)" % tint.to_html(false))


# ------------------------------------------------------------- screenshots
## Not a test: pictures of every map for checking by eye (needs a window).
## godot --path . -- --test=maps --shots=/abs/dir [--map=beach] [--time=night] [--weather=rain]
func _shots(dir: String, only: String, time: String, weather: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var old_time := B3Rules.value("time")
	var old_weather := B3Rules.value("weather")
	B3Rules.set_value("weather", weather)
	var maps: Array = B3Defs.MAP_ORDER if only == "" else [only]
	var i := 0
	for id in maps:
		var mid := String(id)
		B3Rules.set_value("time", time if time != "" else ("day" if i % 2 == 0 else ("sunset" if i % 4 == 1 else "night")))
		i += 1
		await fresh(mid)
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		var w: B3World = b.world
		b.cam.fit(Vector3.ZERO, 38.0)
		await _snap(dir + "/%s_1over.png" % mid, 40)
		b.cam.size = 160.0
		b.cam.focus = Vector3.ZERO
		await _snap(dir + "/%s_2wide.png" % mid, 4)
		b.cam.focus = Vector3(-120, 0, -120)
		b.cam.size = 130.0
		await _snap(dir + "/%s_3edge.png" % mid, 4)
		var cam := Camera3D.new()
		cam.fov = 72.0
		cam.near = 0.08
		cam.far = 900.0
		add_child(cam)
		cam.make_current()
		var views := [[Vector3(0, 0, 30), Vector3(0, 0, -100)], [Vector3(-40, 0, 40), Vector3(-200, 0, 200)],
			[Vector3(60, 0, -60), Vector3(200, 0, -200)], [Vector3(-150, 0, 20), Vector3(150, 0, 0)]]
		var k := 0
		for v in views:
			var from: Vector3 = v[0]
			var to: Vector3 = v[1]
			from.y = maxf(w.height_at(from.x, from.z), 0.0) + 1.7
			to.y = from.y + 2.0
			cam.look_at_from_position(from, to)
			k += 1
			await _snap(dir + "/%s_fp%d.png" % [mid, k], 4)
		cam.queue_free()
		b.cam.cam.make_current()
	B3Rules.set_value("time", old_time)
	B3Rules.set_value("weather", old_weather)


func _snap(path: String, frames: int) -> void:
	for f in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

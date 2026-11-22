extends Node
## Headless gameplay checks: worlds, Wiggly jelly physics, split & merge,
## power, booms, freezing, undo, saves, every toy and spell.
## godot --headless --path . -- --test=core

var fails := 0
var w: World


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    ", msg)
	else:
		print("  FAIL  ", msg)
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	w = World.new()
	add_child(w)
	var fx := Effects.new()
	fx.world = w
	add_child(fx)
	w.fx.connect(fx.handle)

	print("worlds")
	for wd in Catalog.WORLDS:
		w.load_world(wd.id)
		await frames(240)
		var ok := w.count_wigglies() + w.fighters().size() + w.count_toys() > 0
		for g in w.wigglies():
			if not g.com.is_finite() or g.stretch > 2.0 or not w.bounds.has_point(g.com):
				ok = false
				print("        %s at %s stretch %.2f speed %.0f" % [g.kind, g.com, g.stretch, g.com_vel.length()])
		for f in w.fighters():
			if not f.center().is_finite() or not w.bounds.has_point(f.center()):
				ok = false
				print("        %s at %s" % [f.type, f.center()])
		check(ok, "%s loads and settles (%d Wigglies, %d fighters, %d toys)" % [wd.id, w.count_wigglies(), w.fighters().size(), w.count_toys()])

	print("world pieces")
	w.load_world("meadow", false)
	w.load_world("battle", false)
	check(_water_area() > 10000.0, "switching worlds doesn't cut holes in the new world's water (%.0f px² of river)" % _water_area())
	w.load_world("clouds", false)
	var bridge_top := _ground_top(-125.0)
	check(absf(bridge_top - 60.0) < 15.0, "the Cloud Kingdom rainbow bridge reaches the middle island (its end is at y %.0f)" % bridge_top)
	w.load_world("battle")
	await frames(2)
	var forts := w.platforms.size()
	w.next_group = 1   # like a new game
	w.apply_command(0, {"cmd": "platform", "x0": -300, "y0": -300, "x1": -200, "y1": -280})
	w.apply_command(0, {"cmd": "unplatform", "x": -250, "y": -290})
	await frames(2)
	check(w.platforms.size() == forts, "erasing a platform you built leaves the forts alone (%d of %d left)" % [w.platforms.size(), forts])
	w.apply_command(0, {"cmd": "clear"})
	await frames(2)
	check(w.platforms.size() == forts, "🧹 Clear leaves Battle Valley's forts standing (%d of %d left)" % [w.platforms.size(), forts])

	print("jelly")
	w.load_world("canvas", false)
	var b := w.spawn_wiggly("bloop", Vector2(0, -150))
	b.player_id = 99   # "played" with no keys pressed, so its AI doesn't hop around
	await frames(420)
	check(b.com_vel.length() < 40.0, "a dropped Bloop comes to rest (speed %.1f)" % b.com_vel.length())
	check(b.stretch < 1.35, "and springs back into shape (stretch %.2f)" % b.stretch)
	check(b.com.y > 150.0 and b.com.y < 300.0, "and sits on the ground (y %.0f)" % b.com.y)
	var heavy := w.spawn_wiggly("boulder", Vector2(0, -400))
	await frames(360)
	check(heavy.com.y < b.com.y - 20.0 and absf(heavy.com.x - b.com.x) < 120.0 or heavy.com.y < 300.0, "a Boulder can land on a Bloop without falling through the floor")

	print("split and merge")
	w._clear_all()
	var s := w.spawn_wiggly("gummy", Vector2(0, 200))
	await frames(60)
	w.apply_command(5, {"cmd": "grab", "uid": s.uid, "x": s.pts[0].x, "y": s.pts[0].y})
	for i in 90:
		if w.wigglies().size() > 1:
			break
		var tgt := s.com + Vector2(500, -200)
		w.apply_command(5, {"cmd": "drag", "x": tgt.x, "y": tgt.y})
		await get_tree().physics_frame
	await frames(10)   # still holding the mouse button down
	var gummies := w.wigglies().filter(func(g): return g.kind == "gummy")
	check(gummies.size() == 2, "pulling a Wiggly hard pops it into two (%d now)" % gummies.size())
	var held = w.get_thing(int(w.grabs[5].uid)) if w.grabs.has(5) else null
	check(held is Wiggly and gummies.has(held), "and you keep hold of one half")
	w.apply_command(5, {"cmd": "release"})
	await frames(5)
	check(w.wigglies().size() == 2, "letting go straight away doesn't stick the halves back together")
	await frames(120)
	gummies = w.wigglies().filter(func(g): return g.kind == "gummy")
	if gummies.size() == 2:
		var g1: Wiggly = gummies[0]
		var g2: Wiggly = gummies[1]
		w.apply_command(5, {"cmd": "grab", "uid": g1.uid, "x": g1.com.x, "y": g1.com.y})
		for i in 40:
			w.apply_command(5, {"cmd": "drag", "x": g2.com.x, "y": g2.com.y - 10, "whole": true})
			await get_tree().physics_frame
		w.apply_command(5, {"cmd": "release"})
		await frames(5)
		check(w.wigglies().filter(func(g): return g.kind == "gummy").size() == 1, "dropping one onto the other merges them back")

	print("power")
	w._clear_all()
	var bat := w.spawn_toy("battery", Vector2(-200, 250))
	var sw := w.spawn_toy("switch", Vector2(-100, 250))
	var lamp := w.spawn_toy("lamp", Vector2(0, 250))
	var lamp2 := w.spawn_toy("lamp", Vector2(100, 250))
	w.add_link("wire", bat, lamp2, bat.global_position, lamp2.global_position)
	w.add_link("wire", bat, sw, bat.global_position, sw.global_position)
	w.add_link("wire", sw, lamp, sw.global_position, lamp.global_position)
	await frames(4)
	check(lamp2.powered, "a battery wired to a lamp powers it")
	check(not lamp.powered, "a switch that is off blocks the power")
	w.apply_command(0, {"cmd": "use", "uid": sw.uid})
	await frames(4)
	check(lamp.powered, "flipping the switch on lets power through")

	print("booms")
	w._clear_all()
	var barrel := w.spawn_toy("boom_barrel", Vector2(0, 260))
	var block := w.spawn_toy("wood_block", Vector2(90, 270))
	var glass := w.spawn_toy("glass_pane", Vector2(-90, 240))
	await frames(30)
	var start := block.global_position
	var barrel_uid := barrel.uid
	var glass_uid := glass.uid
	w.apply_command(0, {"cmd": "use", "uid": barrel_uid})
	await frames(180)
	check(not w.things.has(barrel_uid), "a used Boom Barrel goes off")
	check(is_instance_valid(block) and block.global_position.distance_to(start) > 60.0, "and throws nearby toys")
	check(not w.things.has(glass_uid), "and smashes glass")
	var floaty := w.spawn_toy("brick", Vector2(0, -300))
	await frames(10)
	w.freeze_area(floaty.global_position, 100.0, 2.0)
	var y0 := floaty.global_position.y
	await frames(60)
	check(floaty.freeze and absf(floaty.global_position.y - y0) < 1.0, "freezing holds a falling brick in mid-air")
	await frames(240)
	check(not floaty.freeze, "and it thaws after a while")

	print("undo and saves")
	w._clear_all()
	var n0 := w.things.size()
	w.apply_command(0, {"cmd": "spawn", "id": "beach_ball", "x": 0, "y": 0})
	check(w.things.size() == n0 + 1, "spawning adds a toy")
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	check(w.things.size() == n0, "undo takes it away again")
	var k1 := w.spawn_toy("wood_block", Vector2(-40, 200))
	var k2 := w.spawn_toy("wood_block", Vector2(0, 200))
	w.add_link("glue", k1, k2, Vector2(-20, 200), Vector2(-20, 200))
	Builders.ride(w, "go_kart", Vector2(300, 200))
	w.spawn_wiggly("twinkle", Vector2(-300, 150))
	await frames(10)
	var data = JSON.parse_string(JSON.stringify(w.serialize()))
	var counts := [w.count_toys(), w.count_wigglies(), w.links.size()]
	w._clear_all()
	w.restore(data)
	await frames(8)
	check([w.count_toys(), w.count_wigglies(), w.links.size()] == counts, "a saved playground loads back the same (%s)" % str(counts))

	print("glue, hinges and pausing")
	w._clear_all()
	var b1 := w.spawn_toy("wood_block", Vector2(-220, 270))
	var b2 := w.spawn_toy("wood_block", Vector2(-180, 270))
	var b3 := w.spawn_toy("wood_block", Vector2(180, 270))
	var b4 := w.spawn_toy("wood_block", Vector2(220, 270))
	await frames(30)
	# dragged from the middle of one block to the middle of the next, like you do with the mouse
	var gl := w.add_link("glue", b1, b2, b1.global_position, b2.global_position)
	var hg := w.add_link("hinge", b3, b4, b3.global_position, b4.global_position)
	await frames(30)
	check(not gl.broken and not hg.broken, "glue and a hinge dragged from one block to the next hold (they don't snap straight away)")
	var box := w.spawn_toy("wood_block", Vector2(-500, 270))
	var jel := w.spawn_wiggly("bloop", Vector2(500, 220))
	jel.player_id = 99   # keeps still
	await frames(60)
	w.apply_command(0, {"cmd": "pause", "on": true})
	var bx0 := box.global_position
	w.apply_command(0, {"cmd": "grab", "uid": box.uid, "x": bx0.x, "y": bx0.y})
	for i in 20:
		w.apply_command(0, {"cmd": "drag", "x": bx0.x + 150.0, "y": bx0.y - 100.0})
		await get_tree().physics_frame
	w.apply_command(0, {"cmd": "release"})
	check(box.global_position.distance_to(bx0 + Vector2(150, -100)) < 5.0, "while paused you can still drag a toy around")
	var jc0 := jel.com
	w.apply_command(0, {"cmd": "grab", "uid": jel.uid, "x": jc0.x, "y": jc0.y})
	for i in 20:
		w.apply_command(0, {"cmd": "drag", "x": jc0.x - 120.0, "y": jc0.y - 80.0})
		await get_tree().physics_frame
	w.apply_command(0, {"cmd": "release"})
	await get_tree().process_frame
	check(jel.com.distance_to(jc0 + Vector2(-120, -80)) < 10.0, "and a Wiggly (moved to %s)" % str(jel.com - jc0))
	w.apply_command(0, {"cmd": "pause", "on": false})

	print("toys, water and lava")
	w._clear_all()
	var gum := w.spawn_wiggly("gummy", Vector2(-600, 200))
	gum.stuck_links = 3   # it already stuck to 3 things last time
	gum.use_special()
	check(gum.stuck_links == 0, "Gummy's Sticky Mode sticks again every time it starts (not just the first 3 times)")
	var fan := w.spawn_toy("fan", Vector2(-400, 250))
	w.apply_command(0, {"cmd": "use", "uid": fan.uid})
	var draws := [0]
	fan.draw.connect(func(): draws[0] += 1)
	for i in 20:
		await get_tree().process_frame
	check(draws[0] >= 10, "a switched-on fan keeps redrawing, so its blades spin (%d redraws in 20 frames)" % draws[0])
	check(bool(Builders.part_def("rocket", 12.0).get("part", false)), "a copy of a flying bazooka rocket (a friend's, or a save) is a rocket, not a Rocket Booster")
	var hub = w.spawn("build:ferris", Vector2(0, 0))
	await frames(30)
	var turned := 0.0
	var last_a: float = hub.rotation
	for i in 240:
		await get_tree().physics_frame
		turned += wrapf(hub.rotation - last_a, -PI, PI)
		last_a = hub.rotation
	check(absf(turned) > 2.0, "the Spinny Wheel spins (its arms don't jam on its post) (%.1f rad in 2 s)" % absf(turned))
	# a narrow pillar: the kart's body is lifted on top of it, so its wheels must come too
	w.apply_command(0, {"cmd": "platform", "x0": -720, "y0": 0, "x1": -680, "y1": 300})
	var kart = w.spawn("go_kart", Vector2(-700, 100))
	var wheels := w.toys().filter(func(o): return o.parent_uid == kart.uid)
	check(wheels.size() == 2 and wheels.all(func(o): return absf(o.global_position.y - kart.global_position.y) < 40.0), "a go-kart dropped onto a pillar keeps its wheels under it")
	w.apply_command(0, {"cmd": "spawn", "id": "lava_tub", "x": 500, "y": 300})
	w.apply_command(0, {"cmd": "spawn", "id": "water_tub", "x": 900, "y": 300})
	check(w.in_water(Vector2(500, 260)) == Rect2() and w.in_water(Vector2(900, 260)) != Rect2(), "lava doesn't float toys or splash like water does")
	var shapes := w.water_shapes.size()
	w.apply_command(0, {"cmd": "platform", "x0": 860, "y0": 250, "x1": 940, "y1": 270})
	check(w.water_shapes.size() == shapes, "a platform sunk in the water tank doesn't get water drawn over it twice")

	print("everything")
	w.load_world("canvas", false)
	var x := -1300.0
	var y := -200.0
	for t in Catalog.TOYS:
		w.spawn(t.id, Vector2(x, y))
		x += 120.0
		if x > 1300.0:
			x = -1300.0
			y -= 160.0
	for bd in Catalog.BUILDS:
		w.spawn("build:" + bd.id, Vector2(x, y))
		x += 300.0
		if x > 1300.0:
			x = -1300.0
			y -= 200.0
	for k in Catalog.WIGGLY_ORDER:
		w.spawn_wiggly(k, Vector2(x, y))
		x += 100.0
	for t in w.toys():
		w.apply_command(0, {"cmd": "use", "uid": t.uid})
	for g in w.wigglies():
		g.use_special()
	for m in Catalog.MAGIC:
		w.cast_magic(m.id)
	for gr in Catalog.GRAVITIES:
		w.set_gravity(gr.id)
		await frames(20)
	w.set_gravity("normal")
	await frames(400)
	var bad := 0
	for t in w.things.values():
		var p: Vector2 = t.com if t is Wiggly else t.global_position
		if not p.is_finite():
			bad += 1
	check(bad == 0, "every toy, build, Wiggly special, magic spell and gravity runs (%d things left)" % w.things.size())

	print("lists")
	await _lists()

	print("test_core: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## World.fighters(), toys(), wigglies() and ride_parts() are kept between
## calls: they must always match what's really in the world, however things
## come and go (and a friend's copy of the world too).
func _lists() -> void:
	w.load_world("battle")
	await frames(2)
	check(_same_lists(w), "the lists match a freshly loaded world (%d fighters, %d toys)" % [w.fighters().size(), w.toys().size()])
	w.apply_command(0, {"cmd": "spawn", "id": "f:knight", "x": -300, "y": 100, "team": "blue"})
	w.apply_command(0, {"cmd": "spawn", "id": "bowling_ball", "x": -200, "y": 0})
	w.apply_command(0, {"cmd": "spawn", "id": "w:zappy", "x": 0, "y": 0})
	w.apply_command(0, {"cmd": "spawn", "id": "monster_truck", "x": 300, "y": 100})
	w.apply_command(0, {"cmd": "spawn", "id": "water_tub", "x": 600, "y": 250})
	w.apply_command(0, {"cmd": "spawn", "id": "build:ferris", "x": -600, "y": -100})
	check(_same_lists(w), "and after spawning a fighter, toys, a Wiggly, a ride, a tub and a build")
	var held: Array = w.fighters()
	var n := held.size()
	var extra_f := w.spawn_fighter("ninja", Vector2(100, 100), "red", "peaceful")
	check(held.size() == n and w.fighters().size() == n + 1 and held.is_read_only(), "a list you're holding stays as it was (and can't be changed) while fighters come and go")
	var truck: Toy = null
	for t in w.toys():
		if t.id == "monster_truck":
			truck = t
	check(truck != null and w.ride_parts(truck.uid).size() == 2, "the monster truck's two wheels are its parts")
	truck.on = true
	await frames(30)
	w.apply_command(0, {"cmd": "erase", "uid": truck.uid})
	w.apply_command(0, {"cmd": "erase", "uid": extra_f.uid})
	w.apply_command(0, {"cmd": "erase", "uid": w.wigglies()[0].uid})
	check(_same_lists(w), "and after erasing a ride (wheels and all), a fighter and a Wiggly")
	w.apply_command(0, {"cmd": "clone", "uid": w.fighters()[0].uid})
	w.apply_command(0, {"cmd": "resize", "uid": w.fighters()[1].uid, "s": 1.6})
	var jelly := w.spawn_wiggly("bloop", Vector2(-100, 0), 1.4)
	w.apply_command(0, {"cmd": "resize", "uid": jelly.uid, "s": 1.6})
	w.split_wiggly(w.wigglies()[w.wigglies().size() - 1])
	var halves := w.wigglies().filter(func(g): return g.kind == "bloop")
	if halves.size() == 2:
		w.merge_wigglies(halves[0], halves[1])
	check(_same_lists(w), "and after cloning, resizing, splitting and merging")
	w.push_undo()
	w.spawn_toy("brick", Vector2(0, -100))
	w.apply_command(0, {"cmd": "erase", "uid": w.fighters()[0].uid})
	w.undo()
	await frames(2)
	check(_same_lists(w), "and after ↩️ undo")
	# a save loaded into a world that has handed out fewer numbers: the new
	# things get numbers that a saved one is about to take over
	var saved := w.serialize()
	var ts_saved: Array = saved.toys
	ts_saved.reverse()   # newest first, so new numbers land on ones already taken
	var low := 1 << 30
	for e in ts_saved:
		low = mini(low, int(e.uid))
	w._clear_all()
	w.next_uid = low - 1
	w.restore(saved)
	await frames(2)
	check(_same_lists(w), "and after loading a save whose numbers clash with the new things' (%d things)" % w.things.size())
	var lost := w.spawn_toy("marble", Vector2(0, -100))
	lost.global_position = Vector2(0, w.bounds.end.y + 400.0)
	await frames(2)
	check(not w.toys().has(lost) and _same_lists(w), "and after a toy falls out of the world")
	# a friend's copy of the world, kept up to date from the host's snapshots
	var host := _Fake.new()
	host.world = w
	host.net = _FakeNet.new()
	var friend := _Fake.new()
	friend.world = World.new()
	friend.world.puppet = true
	add_child(friend.world)
	friend.world.load_world(w.world_id, false)
	NetCommon.apply_snapshot(friend, NetCommon.snapshot(host))
	check(_same_lists(friend.world) and friend.world.fighters().size() == w.fighters().size() and friend.world.toys().size() == w.toys().size(), "a friend's copy has the same lists (%d fighters, %d toys)" % [friend.world.fighters().size(), friend.world.toys().size()])
	w.apply_command(0, {"cmd": "erase", "uid": w.toys()[0].uid})
	w.spawn_fighter("viking", Vector2(-50, 100), "green", "peaceful")
	w.spawn_wiggly("puffy", Vector2(50, -50))
	NetCommon.apply_snapshot(friend, NetCommon.snapshot(host))
	check(_same_lists(friend.world) and friend.world.fighters().size() == w.fighters().size() and friend.world.wigglies().size() == w.wigglies().size(), "and still does after things come and go on the host")
	friend.world.queue_free()
	# a fighter taking over a toy's number (a save or a friend's copy with numbers
	# that clash): the toy drops out of the toy list
	var brick := w.spawn_toy("brick", Vector2(0, -100))
	var taker := w.spawn_fighter("soldier", Vector2(100, 100), "red", "peaceful", 1.0, false)
	w.toys()
	w.fighters()
	w.renumber(taker, brick.uid)
	check(not w.toys().has(brick) and w.fighters().has(taker) and _same_lists(w), "and when a fighter takes over a toy's number")
	w.apply_command(0, {"cmd": "clear"})
	await frames(2)
	check(_same_lists(w) and w.toys().is_empty() and w.fighters().is_empty(), "and after 🧹 Clear")


class _Fake extends RefCounted:
	var world: World
	var cam = null
	var hud = null
	var net = null


class _FakeNet extends RefCounted:
	func players_snapshot() -> Array:
		return []


func _same_lists(wd: World) -> bool:
	var fs := wd.fighter_layer.get_children().filter(func(f): return f is Fighter and wd.things.get(f.uid) == f)
	var ts := wd.things.values().filter(func(t): return t is Toy)
	var gs := wd.things.values().filter(func(t): return t is Wiggly)
	var ok: bool = fs == wd.fighters() and ts == wd.toys() and gs == wd.wigglies() and wd.count_toys() == ts.size() and wd.count_wigglies() == gs.size()
	for r in ts:
		if wd.ride_parts(r.uid) != ts.filter(func(o): return o.parent_uid == r.uid):
			ok = false
	return ok


## How much water (and lava and acid) is showing, in square pixels.
func _water_area() -> float:
	var a := 0.0
	for ws in w.water_shapes:
		var p: PackedVector2Array = ws.poly
		var s := 0.0
		for i in p.size():
			s += p[i].cross(p[(i + 1) % p.size()])
		a += absf(s) * 0.5
	return a


## The height of the first solid ground at `x`, coming down from the sky.
func _ground_top(x: float) -> float:
	var y := -400.0
	while y < 800.0:
		for g in w.terrain.get_children():
			if g is Ground and not g.is_queued_for_deletion() and Geometry2D.is_point_in_polygon(Vector2(x, y), g.poly):
				return y
		y += 2.0
	return INF

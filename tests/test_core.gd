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
		var tgt := s.com + Vector2(500, -200) if is_instance_valid(s) else Vector2(500, -200)
		w.apply_command(5, {"cmd": "drag", "x": tgt.x, "y": tgt.y})
		await get_tree().physics_frame
	var gummies := w.wigglies().filter(func(g): return g.kind == "gummy")
	check(gummies.size() == 2, "pulling a Wiggly hard pops it into two (%d now)" % gummies.size())
	w.apply_command(5, {"cmd": "release"})
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

	print("test_core: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

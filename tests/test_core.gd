extends TestBase
## Headless gameplay checks: worlds, Wiggly jelly physics, split & merge,
## power, booms, freezing, undo, saves, every toy and spell.
## godot --headless --path . -- --test=core

var w: World


## (frames() waits physics steps here: the playground's clock)
func _init() -> void:
	frames_are_steps = true


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

	print("ground pieces")
	var slanted := 0
	var off_area := 0.0
	var shortest := INF
	for wd in Catalog.WORLDS:
		w.load_world(wd.id, false)
		for g in w.terrain.get_children():
			if not (g is Ground) or g.is_queued_for_deletion():
				continue
			var area := 0.0
			for cs in g.get_children():
				if cs is CollisionShape2D and cs.shape is ConvexPolygonShape2D:
					var pts: PackedVector2Array = cs.shape.points
					area += _area(pts)
					for i in pts.size():
						var a := pts[i]
						var nb := pts[(i + 1) % pts.size()]
						shortest = minf(shortest, a.distance_to(nb))
						if absf(a.x - nb.x) > 0.01 and not _on_outline((a + nb) * 0.5, g.poly):
							slanted += 1
			off_area = maxf(off_area, absf(area - _area(g.poly)) / _area(g.poly))
	# (Godot's own split made fans of needle-thin triangles reaching across the
	# ground: a heap of ragdolls squeezed into them got flung out of the world)
	check(slanted == 0 and off_area < 0.005 and shortest > 0.4, "the ground's collision is cut into upright slices that fill it exactly (%d slanted cuts, %.2f%% off, shortest side %.1f px)" % [slanted, off_area * 100.0, shortest])

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

	print("toy pictures")
	await _toy_pictures()
	print("nailed-down machines")
	await _nailed_machines()
	print("ready-made builds")
	await _builds()
	print("undo for small changes")
	await _small_undo()
	print("ropes and straining Wigglies")
	await _ropes_and_strain()
	print("💾 save slots")
	await _save_slots()

	finish()


## 💾 Six named save slots (Saves), and the old single save moving into slot 1.
func _save_slots() -> void:
	Saves.delete_all_test_saves()
	w.load_world("canvas")
	await frames(2)
	w.spawn_wiggly("bloop", Vector2(-100, -200))
	w.spawn_wiggly("zappy", Vector2(100, -200))
	await frames(10)
	var n1 := w.count_wigglies()
	# the save from before (just the playground, no name) is still there
	var old := FileAccess.open(Saves.legacy_path(), FileAccess.WRITE)
	old.store_string(JSON.stringify(w.serialize()))
	old.close()
	check(Saves.has_slot(1) and not FileAccess.file_exists(Saves.legacy_path()) and FileAccess.file_exists(Saves.legacy_path() + ".old"),
		"the old single save moves into slot 1 (and the old file is kept as .old)")
	var d1 := Saves.read(1)
	check(String(d1.get("name", "")) != "" and String(d1.get("world", "")) == "canvas", "slot 1 has a name and its world (%s, %s)" % [d1.get("name"), d1.get("world")])
	w.load_world("meadow")
	await frames(2)
	check(Saves.load_slot(w, 1) and w.world_id == "canvas" and w.count_wigglies() == n1, "loading it brings the old playground back (%d of %d Wigglies)" % [w.count_wigglies(), n1])
	# a raw old-style file in a slot still loads too
	var raw := FileAccess.open(Saves.path(4), FileAccess.WRITE)
	raw.store_string(JSON.stringify(w.serialize()))
	raw.close()
	check(Saves.read(4).has("data") and Saves.load_slot(w, 4), "a slot holding just a playground (no name) still loads")
	# six slots, each its own
	w.spawn_wiggly("blaze", Vector2(0, -200))
	await frames(4)
	var n3 := w.count_wigglies()
	check(Saves.save_slot(w, 3, "My Castle") and Saves.read(3).name == "My Castle" and Saves.when_text(Saves.read(3)) != "", "saving in slot 3 with a name (and when)")
	check(Saves.save_slot(w, 6) and String(Saves.read(6).name).contains("Blank Canvas"), "a slot saved with no name is named after its world (%s)" % Saves.read(6).name)
	check(Saves.rename(6, "  Rocket Lab  ") and Saves.read(6).name == "Rocket Lab", "✏️ renaming a slot")
	check(not Saves.save_slot(w, 7) and not Saves.save_slot(w, 0), "there are only %d slots" % Saves.SLOTS)
	check(not Saves.has_slot(2) and Saves.read(2).is_empty() and Saves.thumb(3) == null, "an empty slot is empty (and headless saves have no picture)")
	var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	check(Saves.save_slot(w, 2, "", img) and Saves.thumb(2) != null and Saves.thumb(2).get_size() == Vector2(Saves.THUMB), "a slot keeps a little picture of the playground")
	w.load_world("meadow")
	await frames(2)
	check(Saves.load_slot(w, 3) and w.count_wigglies() == n3 and w.world_id == "canvas", "loading slot 3 brings back what was saved there (%d of %d Wigglies)" % [w.count_wigglies(), n3])
	# saved safely: written next to the slot first, then moved over it
	check(not FileAccess.file_exists(Saves.path(3) + ".tmp"), "a save leaves nothing half-written behind")
	DirAccess.rename_absolute(Saves.path(3), Saves.path(3) + ".tmp")   # (as if the game stopped half-way through moving it in)
	check(Saves.has_slot(3) and String(Saves.read(3).get("name", "")) == "My Castle", "and a save cut off half-way is still found")
	Saves.delete_all_test_saves()
	check(not Saves.has_slot(), "(test saves cleaned up)")


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
	var n_saved: int = saved.toys.size() + saved.wigglies.size() + saved.fighters.size()
	w._clear_all()
	await frames(2)   # (the old ones are gone at the end of the frame)
	w.next_uid = low - 1
	w.restore(saved)
	await frames(2)
	check(_same_lists(w), "and after loading a save whose numbers clash with the new things' (%d things)" % w.things.size())
	check(w.things.size() == n_saved and _strays(w) == 0, "loading it brings back all %d things and leaves no strays behind (%d back, %d strays)" % [n_saved, w.things.size(), _strays(w)])
	# undo straight after, with a broken save that has a number twice
	var twice := w.serialize()
	if twice.toys.size() >= 2:
		twice.toys[1].uid = twice.toys[0].uid
	w.restore(twice)
	await frames(2)
	check(_same_lists(w) and _strays(w) == 0 and w.toys().size() == twice.toys.size(), "and a broken save with a number used twice loads everything, with no strays (%d toys, %d strays)" % [w.toys().size(), _strays(w)])
	w.push_undo()
	w.apply_command(0, {"cmd": "spawn", "id": "f:viking", "x": 0, "y": 0})
	w.undo()
	await frames(2)
	check(_same_lists(w) and _strays(w) == 0, "↩️ undo leaves no strays either (%d strays)" % _strays(w))
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


## Toy, Wiggly and fighter nodes in the world that it doesn't know about.
func _strays(wd: World) -> int:
	var n := 0
	for layer: Node in [wd.bodies, wd.wiggly_layer, wd.fighter_layer]:
		for c in layer.get_children():
			if (c is Toy or c is Wiggly or c is Fighter) and not c.is_queued_for_deletion() and wd.things.get(c.uid) != c:
				n += 1
	return n


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


func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return absf(s) * 0.5


func _on_outline(q: Vector2, poly: PackedVector2Array) -> bool:
	for i in poly.size():
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])) < 0.5:
			return true
	return false


## The height of the first solid ground at `x`, coming down from the sky.
func _ground_top(x: float) -> float:
	var y := -400.0
	while y < 800.0:
		for g in w.terrain.get_children():
			if g is Ground and not g.is_queued_for_deletion() and Geometry2D.is_point_in_polygon(Vector2(x, y), g.poly):
				return y
		y += 2.0
	return INF


## Counts redraws of each toy over `n` frames.
func _redraws(ts: Dictionary, n: int) -> Dictionary:
	var counts := {}
	var conns := {}
	for k in ts:
		counts[k] = 0
		var cb := func() -> void: counts[k] += 1
		conns[k] = cb
		(ts[k] as Toy).draw.connect(cb)
	var t0 := Time.get_ticks_msec()
	for i in n:
		await get_tree().process_frame
	while Time.get_ticks_msec() - t0 < 1100:   # (headless frames fly by: give blinkers a second)
		await get_tree().process_frame
	for k in ts:
		(ts[k] as Toy).draw.disconnect(conns[k])
	return counts


## Toys whose picture changes all by itself get redrawn now and then; ones
## that look the same frame after frame don't.
func _toy_pictures() -> void:
	w.load_world("canvas", false)
	var ts := {}
	var x := -700.0
	for id in ["magnet", "timer", "saucer", "c4", "landmine", "lamp", "motor", "battery"]:
		var t := w.spawn_toy(id, Vector2(x, 200))
		t.nailed = true
		t.update_freeze()
		ts[id] = t
		x += 160.0
	var bat := w.spawn_toy("battery", Vector2(0, -300))
	bat.nailed = true
	bat.update_freeze()
	for k in ["magnet", "lamp", "motor"]:
		w.add_link("wire", bat, ts[k], bat.global_position, ts[k].global_position)
	await frames(10)
	var n := await _redraws(ts, 30)
	check(int(n.magnet) >= 30, "a switched-on magnet's pulses keep moving (%d redraws)" % int(n.magnet))
	check(int(n.timer) >= 4 and int(n.timer) < 30, "the Blinky Timer's hand ticks round, a few redraws a second (%d)" % int(n.timer))
	check(int(n.c4) >= 2 and int(n.landmine) >= 1 and int(n.saucer) >= 4, "C4, landmine and saucer lights blink (%d, %d, %d redraws)" % [int(n.c4), int(n.landmine), int(n.saucer)])
	check(int(n.c4) < 15 and int(n.saucer) < 20, "but only when the light changes, not every frame")
	check(int(n.lamp) == 0 and int(n.motor) == 0 and int(n.battery) == 0, "a lit lamp, a running motor and a battery aren't redrawn for nothing (%d, %d, %d)" % [int(n.lamp), int(n.motor), int(n.battery)])
	var bell := w.spawn_toy("bell", Vector2(600, 200))
	bell.nailed = true
	bell.update_freeze()
	await frames(5)
	ToyLogic.use(w, bell)
	var tilt := [0]
	bell.draw.connect(func() -> void: tilt[0] += 1)
	for i in 4:
		await get_tree().process_frame
	check(tilt[0] >= 3, "a dinged bell wobbles")
	await frames(60)
	tilt[0] = 0
	await get_tree().process_frame
	await get_tree().process_frame
	check(bell.cooldown <= 0.0 and not bell._art_key.contains("b1") and tilt[0] == 0, "and comes to rest upright (redrawn once as it stops, then left alone)")


## A nailed toy is frozen and can't feel its own contacts: nailed landmines,
## spring pads and conveyor belts look for what's on them themselves.
func _nailed_machines() -> void:
	w.load_world("canvas", false)
	w.battle_on = false
	var mine := w.spawn_toy("landmine", Vector2(0, 294))
	mine.nailed = true
	mine.update_freeze()
	var mine_id := mine.uid
	var walker := w.spawn_fighter("soldier", Vector2(-250, 150), "red", "peaceful")
	walker.max_hp = 100000.0
	walker.hp = 100000.0
	await frames(40)
	walker.player_id = 0
	walker.move_input = 1.0
	for i in 480:
		await get_tree().physics_frame
		if not w.things.has(mine_id):
			break
	walker.player_id = -1
	check(not w.things.has(mine_id), "a nailed-down landmine still goes off when a soldier walks into it")
	w._clear_all()
	var belt := w.spawn_toy("conveyor", Vector2(0, 288))
	belt.nailed = true
	belt.update_freeze()
	await frames(5)
	var box := w.spawn_toy("wood_block", Vector2(-40, 240))
	var bx := box.global_position.x
	await frames(120)
	check(box.global_position.x - bx > 40.0, "a nailed-down conveyor belt still carries things along (%.0f px)" % (box.global_position.x - bx))
	w._clear_all()
	var pad := w.spawn_toy("spring_pad", Vector2(0, 288))
	pad.nailed = true
	pad.update_freeze()
	await frames(5)
	var ball := w.spawn_toy("bowling_ball", Vector2(0, 150))
	var top := INF
	for i in 180:
		await get_tree().physics_frame
		if i > 40:
			top = minf(top, ball.global_position.y)
	check(top < 100.0, "a nailed-down spring pad still launches what lands on it (back up to y %.0f)" % top)
	w._clear_all()
	var hull = w.spawn("boat", Vector2(0, -200))
	Builders.tub(w, "lava_tub", Vector2(0, 300))
	var lx: float = hull.global_position.x
	await frames(90)
	check(not w.things.has(hull.uid) or absf(hull.global_position.x - lx) < 20.0, "a sail boat doesn't sail across lava (it just sinks)")


## Every ready-made build comes out in one piece, even put down right on the
## ground, and does its thing.
func _builds() -> void:
	w.load_world("canvas", false)
	w.battle_on = false
	var snaps := [0]
	var count := func(n: String, _a: Dictionary) -> void:
		if n == "snap":
			snaps[0] += 1
	w.fx.connect(count)
	for bd in Catalog.BUILDS:
		w._clear_all()
		w.clear_placed()
		await frames(2)   # (what was cleared away is gone at the end of the frame)
		await get_tree().process_frame
		snaps[0] = 0
		w.apply_command(0, {"cmd": "spawn", "id": "build:" + bd.id, "x": 0, "y": 285})
		var parts: Array = w.toys().duplicate()
		await frames(5)
		var fastest := 0.0
		for t in parts:
			if is_instance_valid(t):
				fastest = maxf(fastest, (t as Toy).linear_velocity.length())
		await frames(60)
		var lost := parts.filter(func(t): return not is_instance_valid(t) or not w.things.has(t.uid)).size()
		check(not parts.is_empty() and snaps[0] == 0 and lost == 0 and fastest < 400.0,
			"%s put down on the ground comes out whole (%d parts, %d snapped, fastest %.0f px/s)" % [bd.name, parts.size(), snaps[0], fastest])
	# the see-saw's stand is nailed down, with the plank level on top
	w._clear_all()
	var plank: Toy = w.spawn("build:seesaw", Vector2(0, 100))
	await frames(60)
	var stand := w.toys().filter(func(t): return t.id == "ramp")
	check(stand.size() == 2 and stand.all(func(t): return t.nailed) and absf(plank.rotation) < 0.3 and plank.global_position.y > 150.0,
		"the see-saw stands on the ground on a nailed A-frame, its plank on top (tilt %.2f)" % plank.rotation)
	# the catapult throws its ball when you flip the switch
	w._clear_all()
	w.spawn("build:catapult", Vector2(0, 0))
	await frames(120)
	var ball: Toy = w.toys().filter(func(t): return t.id == "beach_ball")[0]
	var sw: Toy = w.toys().filter(func(t): return t.id == "switch")[0]
	var b0 := ball.global_position
	w.apply_command(0, {"cmd": "use", "uid": sw.uid})
	var hi := b0.y
	var far := 0.0
	for i in 300:
		await get_tree().physics_frame
		hi = minf(hi, ball.global_position.y)
		far = maxf(far, absf(ball.global_position.x - b0.x))
	check(b0.y - hi > 50.0 and far > 250.0, "flipping the catapult's switch flings the ball (%.0f px up, %.0f px away)" % [b0.y - hi, far])
	# the rocket cart waits for its switch
	w._clear_all()
	var kart: Toy = w.spawn("build:rocket_cart", Vector2(0, 200))
	await frames(120)
	var k0 := kart.global_position
	await frames(120)
	check(kart.global_position.distance_to(k0) < 15.0, "a Rocket Cart stays put until you flip its switch (it used to drive off on its own) (%.0f px)" % kart.global_position.distance_to(k0))
	var ksw: Toy = w.toys().filter(func(t): return t.id == "switch")[0]
	w.apply_command(0, {"cmd": "use", "uid": ksw.uid})
	await frames(120)
	check(kart.global_position.distance_to(k0) > 120.0, "and then it zooms off (%.0f px in a second)" % kart.global_position.distance_to(k0))
	# 🔌 Battle Trap Builds
	w._clear_all()
	var booms := [0]
	var count_booms := func(n: String, _a: Dictionary) -> void:
		if n == "boom":
			booms[0] += 1
	w.fx.connect(count_booms)
	var plate: Toy = w.spawn("build:trap_minefield", Vector2(0, 200))
	await frames(10)
	var mines := w.toys().filter(func(t): return t.id == "landmine")
	check(plate.nailed and plate.id == "button" and mines.size() == 3 and mines.all(func(t): return t.nailed), "the Minefield is a nailed pressure plate and three nailed landmines")
	check(w.links.filter(func(l): return l.kind == "wire").size() == 3, "with a wire from the plate to every mine")
	var ball2 := w.spawn_toy("bowling_ball", plate.global_position + Vector2(0, -60))
	await frames(90)
	check(w.toys().filter(func(t): return t.id == "landmine").is_empty() and booms[0] >= 3, "dropping something on the plate sets the whole field off (%d booms)" % booms[0])
	w.fx.disconnect(count_booms)
	w._clear_all()
	w.spawn("build:disarm_gate", Vector2(0, 200))
	var knight := w.spawn_fighter("knight", Vector2(-300, 150), "red", "peaceful")
	knight.max_hp = 99999.0
	knight.hp = 99999.0
	await frames(40)
	var sword: Toy = knight.weapon_toy
	knight.player_id = 0
	knight.move_input = 1.0
	var yanked := false
	for i in 480:
		await get_tree().physics_frame
		if knight.weapon_toy != sword:
			yanked = true
			break
	knight.player_id = -1
	check(yanked, "walking under the Disarm Gate's magnet yanks a knight's sword away")
	w._clear_all()
	w.spawn("build:ufo_abductor", Vector2(0, 200))
	var ufo: Toy = w.toys().filter(func(t): return t.id == "saucer")[0]
	var victim := w.spawn_fighter("stick", Vector2(0, 100), "red", "peaceful")
	var hy := INF
	for i in 240:
		await get_tree().physics_frame
		hy = minf(hy, victim.center().y)
	check(ufo.nailed and hy < ufo.global_position.y + 120.0, "stepping on the UFO Abductor's plate beams you up (up to y %.0f, saucer at %.0f)" % [hy, ufo.global_position.y])
	w.fx.disconnect(count)
	# saves keep toys passing through each other (the Spinny Wheel's arms and its post)
	w._clear_all()
	w.spawn("build:ferris", Vector2(0, 0))
	await frames(5)
	var exc := 0
	for t in w.toys():
		exc += t.get_collision_exceptions().size()
	var ice := w.spawn_toy("brick", Vector2(300, -200))
	ice.frozen_t = 5.0
	ice.update_freeze()
	w.restore(w.serialize())
	await frames(5)
	var exc2 := 0
	for t in w.toys():
		exc2 += t.get_collision_exceptions().size()
	check(exc2 == exc, "a save keeps the Spinny Wheel turning in front of its post (%d of %d)" % [exc2, exc])
	check(w.toys().any(func(t): return t.id == "brick" and t.frozen_t > 0.0 and t.freeze), "and a toy frozen in mid-air stays frozen")


## Painting, resizing, using, magic, and a fighter's team or personality can be
## undone. Doing the same small thing again straight away is one undo step.
func _small_undo() -> void:
	w.load_world("canvas", false)
	var ball := w.spawn_toy("beach_ball", Vector2(0, 200))
	var f := w.spawn_fighter("soldier", Vector2(300, 150), "red", "ranged")
	var sw := w.spawn_toy("switch", Vector2(-300, 280))
	await frames(10)
	var uid := ball.uid
	var sw_id := sw.uid
	var fid := f.uid
	w._undo.clear()
	w.apply_command(0, {"cmd": "paint", "uid": uid, "color": "ff0000"})
	w.apply_command(0, {"cmd": "paint", "uid": uid, "color": "00ff00"})
	w.apply_command(0, {"cmd": "paint", "uid": uid, "color": "0000ff"})
	check(w._undo.size() == 1, "painting the same toy three times is one step to undo (%d)" % w._undo.size())
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	var back = w.things.get(uid)
	check(back is Toy and back.paint.a == 0.0, "and undo takes the paint off")
	w.apply_command(0, {"cmd": "resize", "uid": uid, "s": 2.0})
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	back = w.things.get(uid)
	check(back is Toy and is_equal_approx(back.size_scale, 1.0), "undo puts a resized toy back to its size")
	w.apply_command(0, {"cmd": "use", "uid": sw_id})
	check(w.things.get(sw_id).on, "flipping a switch")
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	check(not w.things.get(sw_id).on, "can be undone")
	w.apply_command(0, {"cmd": "team", "uid": fid, "team": "blue"})
	w.apply_command(0, {"cmd": "pers", "uid": fid, "pers": "berserk"})
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	check(w.things.get(fid).pers == "ranged" and w.things.get(fid).team == "blue", "undo puts a fighter's personality back")
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	check(w.things.get(fid).team == "red", "and its team")
	w.apply_command(0, {"cmd": "magic", "id": "rainbow"})
	check(w.things.get(uid).paint.a > 0.0, "🌈 Rainbow Paint paints everything")
	w.apply_command(0, {"cmd": "undo"})
	await frames(3)
	check(w.things.get(uid).paint.a == 0.0, "and undo takes the spell back")


## Ropes hang by how much slack they have (and swing as they go slack); a
## Wiggly pulled nearly to popping trembles.
func _ropes_and_strain() -> void:
	w.load_world("canvas", false)
	var a := w.spawn_toy("wood_block", Vector2(-150, -100))
	var b := w.spawn_toy("wood_block", Vector2(150, -100))
	for t in [a, b]:
		t.nailed = true
		t.update_freeze()
	var slack := w.add_link("rope", a, b, a.global_position, b.global_position)
	slack.rest = 500.0   # a long rope between two blocks 300 px apart
	var c := w.spawn_toy("wood_block", Vector2(-150, 100))
	var d := w.spawn_toy("wood_block", Vector2(150, 100))
	for t in [c, d]:
		t.nailed = true
		t.update_freeze()
	var tight := w.add_link("rope", c, d, c.global_position, d.global_position)
	for i in 90:
		await get_tree().process_frame
	var lv: LinkView = w.link_view
	var hang: float = lv._sag.get(slack.get_instance_id(), [0.0])[0]
	var taut: float = lv._sag.get(tight.get_instance_id(), [99.0])[0]
	check(hang > 120.0 and taut < 8.0, "a slack rope hangs down (%.0f px) and a tight one is nearly straight (%.0f px)" % [hang, taut])
	# let go of one end: the sag swings past where it settles, then comes back
	lv._sag[tight.get_instance_id()] = [0.0, 0.0]
	tight.rest = 500.0
	var most := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:   # (real time: headless frames fly by)
		await get_tree().process_frame
		most = maxf(most, float(lv._sag[tight.get_instance_id()][0]))
	var settled: float = lv._sag[tight.get_instance_id()][0]
	check(most > settled + 3.0, "a rope that suddenly goes slack swings down and bounces (%.0f px, settling at %.0f)" % [most, settled])
	var g := w.spawn_wiggly("gummy", Vector2(0, 200))
	await frames(60)
	check(Art._tremble(g) == 0.0, "a Wiggly sitting about doesn't tremble")
	g.grabbed_by[5] = true
	g.stretch = 2.2
	g.mood = "strain"
	check(Art._tremble(g) > 2.5, "one pulled nearly to popping trembles (%.1f px)" % Art._tremble(g))
	g.grabbed_by.clear()


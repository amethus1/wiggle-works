class_name WorldCommands
## What players do, for World: every command (a friend's clicks over Wi-Fi go
## through exactly the same code as yours), and grabbing and dragging things
## about. Everything here takes the world; all the state stays in World.


## Everything a player can do. pid 0 = the local/host player.
static func apply(world: World, pid: int, c: Dictionary) -> void:
	var t = world.things.get(int(c.get("uid", -1)))
	var at := Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0)))
	match String(c.get("cmd", "")):
		"spawn":
			WorldSave.push_undo(world)
			var made = world.spawn(String(c.id), at, String(c.get("team", "")), String(c.get("pers", "")))
			if made:
				world.fx_event("spawn", {"p": at})
				if made is Wiggly:
					Settings.award("hello")
					if world.count_wigglies() >= 12:
						Settings.award("family")
		"grab":
			if t:
				grab_start(world, pid, t, at)
		"drag":
			if world.grabs.has(pid):
				world.grabs[pid].target = at
				world.grabs[pid].whole = bool(c.get("whole", false))
				world.grabs[pid].seen = Time.get_ticks_msec()
		"release":
			grab_end(world, pid)
		"use":
			if t is Toy or t is Wiggly or t is Fighter:
				WorldSave.push_undo(world, "use %d" % t.uid)
			if t is Toy:
				ToyLogic.use(world, t)
			elif t is Wiggly:
				t.use_special()
			elif t is Fighter and t.state == "stand" and not t.helpless():
				var en = FighterAI.nearest(t, func(o): return t.enemy_of(o), 900.0)
				var aim_at: Vector2 = en.center() if en else t.center() + Vector2(t.facing * 200.0, -20)
				t.aim = FighterAI.aim_at(t, aim_at, t._wtype())
				FighterAI.attack(t, aim_at, t._wtype())
		"team":
			if t is Fighter:
				WorldSave.push_undo(world, "team %d" % t.uid)
				t.team = String(c.get("team", t.team))
				t.target = null
		"pers":
			if t is Fighter:
				WorldSave.push_undo(world, "pers %d" % t.uid)
				t.pers = String(c.get("pers", t.pers))
				t.home = t.center()
				t.target = null
		"give":
			if t is Toy and (t.def.has("weapon") or t.def.has("armor")):
				var best: Fighter = null
				var bd := 260.0
				for f in world.fighters():
					if f.state == "stand" and not f.beast and f.center().distance_to(t.global_position) < bd:
						bd = f.center().distance_to(t.global_position)
						best = f
				if best and best.equip(t):
					Settings.count("gifts", "armory", 5)
				else:
					world.fx_event("nope", {})
		"drop":
			if t is Fighter:
				t._drop_weapon(Vector2(t.facing * 150.0, -200))
				t.weapon_id = ""
		"revive":
			# just this one fighter (✨ Heal Everyone is the spell for everybody)
			if t is Fighter:
				t.revive()
				world.fx_event("heal", {"p": t.center()})
		"fight":
			world.battle_on = bool(c.get("on", true))
			for f in world.fighters():
				f.target = null
			world.fx_event("battle_start" if world.battle_on else "click", {})
			world.world_changed.emit(false)
		"platform":
			var a := Vector2(c.x0, c.y0)
			var b := Vector2(c.x1, c.y1)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			if r.size.x < 12.0:
				r = r.grow_individual(6, 0, 6, 0)
			if r.size.y < 12.0:
				r = r.grow_individual(0, 6, 0, 6)
			WorldSave.push_undo(world)
			WorldTerrain.add_platform(world, WorldTerrain.rect_poly(r), String(c.get("style", "wood")))
			world.fx_event("build", {"p": r.get_center()})
			Settings.count("platforms", "builder", 10)
		"unplatform":
			var g := WorldTerrain.platform_at(world, at)
			if g != 0:
				WorldSave.push_undo(world)
				WorldTerrain.remove_platform_group(world, g)
		"detonate":
			for o in world.toys():
				if o.id == "c4":
					ToyLogic.trigger(world, o)
		"link":
			var a := WorldLinks.resolve_body(world, int(c.get("a", -1)), int(c.get("ai", -1)), Vector2(c.ax, c.ay))
			var b := WorldLinks.resolve_body(world, int(c.get("b", -1)), int(c.get("bi", -1)), Vector2(c.bx, c.by))
			if a and b:
				WorldSave.push_undo(world)
				var l := WorldLinks.add_link(world, String(c.kind), a, b, Vector2(c.ax, c.ay), Vector2(c.bx, c.by))
				if l:
					world.fx_event("link", {"p": Vector2(c.bx, c.by), "k": String(c.kind)})
					var src = world.things.get(l.uid_a)
					var dst = world.things.get(l.uid_b)
					if l.kind == "wire" and src is Toy and dst is Toy and (ToyLogic.is_source(src) or ToyLogic.is_source(dst)):
						Settings.award("inventor")
		"unlink":
			if t:
				WorldSave.push_undo(world)
				for l in WorldLinks.links_of(world, t.uid):
					l.destroy()
				world.links = world.links.filter(func(l): return not l.broken)
				world.fx_event("click", {"p": world._pos_of(t)})
		"paint":
			if t:
				WorldSave.push_undo(world, "paint %d" % t.uid)
				t.paint = Color(String(c.get("color", "ffffff")))
				if t is Fighter:
					t.queue_redraw()
				world.fx_event("paint", {"p": world._pos_of(t), "c": t.paint})
				Settings.count("paints", "painter", 10)
		"erase":
			if t:
				WorldSave.push_undo(world)
				world.remove(t.uid)
		"clone":
			if t:
				WorldSave.push_undo(world)
				clone(world, t)
		"resize":
			if t:
				WorldSave.push_undo(world, "resize %d" % t.uid)
			if t is Fighter:
				world.resize_fighter(t, float(c.get("s", 1.0)))
			elif t is Toy:
				t.set_size(float(c.get("s", 1.0)))
			elif t is Wiggly:
				WorldPowers.resize_wiggly(world, t, float(c.get("s", 1.0)))
		"flip":
			if t is Toy:
				t.set_facing(-t.facing)
			elif t is Fighter:
				t.facing = -t.facing
		"nail":
			if t is Toy and not t.extra.has("held_by"):
				t.nailed = not t.nailed
				t.update_freeze()
				world.fx_event("nail", {"p": t.global_position, "on": t.nailed})
		"rotate":
			if t is Toy:
				if t.freeze or world.paused:
					t.rotation += float(c.get("d", 0.0)) * 0.12
				else:
					t.angular_velocity = float(c.get("d", 0.0)) * 5.0
		"play":
			for w in world.wigglies():
				if w.player_id == pid:
					w.player_id = -1
			for f in world.fighters():
				if f.player_id == pid:
					f.player_id = -1
					f.want_attack = false
					f.move_input = 0.0
			if t is Wiggly:
				t.player_id = pid
				t.idle_t = 0.0
			elif t is Fighter:
				t.player_id = pid
		"input":
			for w in world.wigglies():
				if w.player_id == pid:
					w.move_input = clampf(float(c.get("move", 0.0)), -1.0, 1.0)
					if bool(c.get("jump", false)):
						w.want_jump = true
					if bool(c.get("special", false)):
						w.use_special()
			for f in world.fighters():
				if f.player_id == pid:
					f.move_input = clampf(float(c.get("move", 0.0)), -1.0, 1.0)
					if bool(c.get("jump", false)):
						f.want_jump = true
					if c.has("attack"):
						f.want_attack = bool(c.attack)
					if c.has("ax"):
						f.aim_point = Vector2(c.ax, c.ay)
		"magic":
			WorldSave.push_undo(world)
			WorldMagic.cast(world, String(c.get("id", "")))
		"gravity":
			world.set_gravity(String(c.get("id", "normal")))
			world.world_changed.emit(false)
		"night":
			world.set_night(bool(c.get("on", false)))
			world.world_changed.emit(false)
		"pause":
			world.set_paused(bool(c.get("on", false)))
			world.world_changed.emit(false)
		"speed":
			world.set_speed(float(c.get("v", 1.0)))
			world.world_changed.emit(false)
		"world":
			if world.allow_world_actions or pid == 0:
				world.load_world(String(c.get("id", "meadow")))
		"clear":
			if world.allow_world_actions or pid == 0:
				world.clear_toys()
				world.world_changed.emit(true)
		"undo":
			if world.allow_world_actions or pid == 0:
				WorldSave.undo(world)


static func clone(world: World, t) -> void:
	if t is Fighter:
		var f := world.spawn_fighter(t.type, t.center() + Vector2(t.radius() + 30.0, -10), t.team, t.pers, t.size / float(t.def.get("scale", 1.0)))
		if f:
			f.paint = t.paint
	elif t is Wiggly:
		var w := world.spawn_wiggly(t.kind, t.com + Vector2(t.radius() * 2.2, -20), t.size)
		if w:
			w.paint = t.paint
	elif t is Toy and t.parent_uid == 0:
		var made = world.spawn(t.id, t.global_position + Vector2(t.bound_radius() * 1.6 + 10, -20))
		if made is Toy:
			made.paint = t.paint
			made.set_size(t.size_scale)
			made.rotation = t.rotation
	world.fx_event("spawn", {"p": world._pos_of(t)})


static func grab_start(world: World, pid: int, t, at: Vector2) -> void:
	if t is Toy and t.extra.has("held_by"):
		return   # a weapon in someone's hands goes where they go
	var g := {"uid": t.uid, "target": at, "whole": false, "seen": Time.get_ticks_msec(), "pull": 0.0}
	if t is Wiggly:
		g.idx = t.nearest_point(at)
		g.off = t.pts[g.idx] - at
		t.grabbed_by[pid] = true
		t.idle_t = 0.0
	elif t is Fighter:
		t.wake()
		if t.frozen_t > 0.0:
			t.thaw(true)   # grabbing an ice block cracks it open
		if t.state == "stand":
			t.ragdoll()
		var part: PhysicsBody2D = t.body_near(at)
		g.part = part
		g.local = part.to_local(at) if part else Vector2.ZERO
		t.held_by[pid] = true
	else:
		g.local = t.to_local(at)
	world.grabs[pid] = g
	world.fx_event("grab", {"p": at})


static func grab_end(world: World, pid: int) -> void:
	if not world.grabs.has(pid):
		return
	var g: Dictionary = world.grabs[pid]
	world.grabs.erase(pid)
	var t = world.things.get(g.uid)
	if t is Fighter:
		t.held_by.erase(pid)
		t.down_t = 0.6
		t.wake()
	elif t is Toy and (t.def.has("weapon") or t.def.has("armor")):
		# drop a weapon or armor on a person to give it to them
		for f in world.fighters():
			if f.state == "stand" and not f.beast and f.hit_test(t.global_position, 18.0):
				if f.equip(t):
					Settings.count("gifts", "armory", 5)
				break
	if t is Wiggly:
		t.grabbed_by.erase(pid)
		# Drop a Wiggly onto one of the same kind to combine them.
		for o in world.wigglies():
			if o != t and o.kind == t.kind and o.com.distance_to(t.com) < (o.radius() + t.radius()) * 0.85 and not WorldPowers.just_popped(o, t):
				WorldPowers.merge_wigglies(world, o, t)
				break


static func drive_grabs(world: World, dt: float) -> void:
	var now := Time.get_ticks_msec()
	for pid in world.grabs.keys():
		var g: Dictionary = world.grabs[pid]
		var t = world.things.get(g.uid)
		if t == null or (pid != 0 and now - int(g.seen) > 1500):
			grab_end(world, pid)
			continue
		var target: Vector2 = g.target
		if t is Wiggly:
			if t.points.is_empty():
				continue
			if world.paused:
				# physics is stopped, so pushing won't move it: carry the whole Wiggly
				var mv: Vector2 = target + g.off - t.points[int(g.idx)].global_position
				t.teleport(t.com + mv)
				continue
			if g.whole or t.frozen_t > 0.0:
				var d: Vector2 = target - t.com
				for p in t.points:
					p.linear_velocity = d * 14.0
				continue
			var n := Wiggly.N
			for k in [-1, 0, 1]:
				var i: int = (int(g.idx) + k + n) % n
				var body: JellyPoint = t.points[i]
				var want: Vector2 = target + g.off
				var err := want - body.global_position
				body.linear_velocity = (err * (22.0 if k == 0 else 12.0)).limit_length(2800.0)
			if t.stretch > World.SPLIT_STRETCH:
				g.pull += dt
				if g.pull > 0.12:
					WorldPowers.split_wiggly(world, t, pid)
			else:
				g.pull = 0.0
		elif t is Fighter:
			var part = g.get("part")
			if part == null or not is_instance_valid(part):
				if t.state == "stand":
					t.ragdoll()
				part = t.body_near(target)
				g.part = part
				g.local = Vector2.ZERO
			if part:
				var pa: Vector2 = part.to_global(g.local)
				if world.paused:
					# physics is stopped: carry every piece of the ragdoll along
					for b in t.all_bodies():
						b.global_position += target - pa
				else:
					part.linear_velocity = ((target - pa) * 16.0).limit_length(2600.0)
				t.down_t = 0.0
		elif t is Toy:
			var anchor: Vector2 = t.to_global(g.local)
			var delta: Vector2 = target - anchor
			world.wake_resting(t.global_position, t.bound_radius() + 40.0)   # (dragging it out from under one)
			if t.freeze or world.paused:
				t.global_position += delta
				if t.freeze:
					PhysicsServer2D.body_set_state(t.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, t.global_transform)
			else:
				t.linear_velocity = (delta * 16.0).limit_length(2600.0)
				t.angular_velocity *= 0.85

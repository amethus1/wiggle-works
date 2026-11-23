class_name WorldSave
## The whole playground as plain data, for World: saving it (serialize),
## loading it back (restore) and Ctrl+Z (undo). Everything here takes the
## world; all the state stays in World.


## Saves the playground for Ctrl+Z. `key` names a small change ("paint 12"):
## doing the same one again within a couple of seconds (painting, resizing,
## flipping a switch, clicking away) is one step to undo, not fifteen.
static func push_undo(world: World, key := "") -> void:
	if world.puppet:
		return
	var now := Time.get_ticks_msec()
	if key != "" and key == world._undo_key and now - world._undo_at < 2000 and not world._undo.is_empty():
		world._undo_at = now
		return
	world._undo_key = key
	world._undo_at = now
	world._undo.append(serialize(world))
	if world._undo.size() > World.UNDO_MAX:
		world._undo.pop_front()


static func undo(world: World) -> void:
	if world._undo.is_empty():
		world.fx_event("nope", {})
		return
	world._undo_key = ""
	world.restore(world._undo.pop_back())
	world.fx_event("undo", {})


## The whole playground as plain data (saves, undo).
static func serialize(world: World) -> Dictionary:
	var ts: Array = []
	var ws: Array = []
	for t in world.all_things():
		if t is Toy:
			var e := {"uid": t.uid, "id": t.id, "x": t.global_position.x, "y": t.global_position.y, "a": t.rotation,
				"vx": t.linear_velocity.x, "vy": t.linear_velocity.y, "va": t.angular_velocity, "s": t.size_scale,
				"paint": t.paint.to_html() if t.paint.a > 0.0 else "", "letter": t.letter, "on": t.on, "f": t.facing,
				"nail": t.nailed, "parent": t.parent_uid, "pr": t.r if t.def.get("part", false) else 0.0}
			if t.frozen_t > 0.0:
				e.ice = t.frozen_t
			if t.bubble_t > 0.0:
				e.bub = t.bubble_t
			# toys this one passes through (see no_collide)
			var nc: Array = []
			for o_uid in t.extra.get("nc", []):
				if world.things.get(int(o_uid)) is Toy:
					nc.append(int(o_uid))
			if not nc.is_empty():
				e.nc = nc
			ts.append(e)
		elif t is Wiggly:
			var pp: Array = []
			for p in t.pts:
				pp.append([p.x, p.y])
			ws.append({"uid": t.uid, "kind": t.kind, "s": t.size, "x": t.com.x, "y": t.com.y,
				"paint": t.paint.to_html() if t.paint.a > 0.0 else "", "pts": pp})
	var fs: Array = []
	for f in world.fighters():
		var c: Vector2 = f.center()
		var e := {"uid": f.uid, "type": f.type, "team": f.team, "pers": f.pers, "s": f.size / float(f.def.get("scale", 1.0)),
			"x": c.x, "y": c.y, "hp": f.hp, "armor": f.armor, "helmet": f.helmet, "body_armor": f.body_armor, "shield": f.shield,
			"weapon": f.weapon_toy.uid if f.weapon_toy and is_instance_valid(f.weapon_toy) else 0, "f": f.facing,
			"paint": f.paint.to_html() if f.paint.a > 0.0 else ""}
		# what toys and powers are doing to them: 🧊 🫧 ⚡ 🍬 💧 🔥
		var fx_now := {"ice": f.frozen_t, "bub": f.bubble_t, "zap": f.stun_t, "goo": f.goo_t, "wet": f.wet, "burn": f.burning, "acid": f.acid}
		for k in fx_now:
			if float(fx_now[k]) > 0.0:
				e[k] = fx_now[k]
		fs.append(e)
	var ps: Array = []
	for pl in world.platforms:
		var pts: Array = []
		for v in pl.poly:
			pts.append([v.x, v.y])
		var pe := {"poly": pts, "style": pl.style, "group": pl.group}
		if float(pl.get("hp", 0.0)) < float(pl.get("max", 0.0)):
			pe.hp = pl.hp   # (cracked by blasts)
		ps.append(pe)
	var lq: Array = []
	for i in world.water.size():
		if i < world.liquid_groups.size() and int(world.liquid_groups[i]) != 0:
			var r: Rect2 = world.water[i]
			lq.append({"r": [r.position.x, r.position.y, r.size.x, r.size.y], "kind": world.liquid_kinds[i], "group": world.liquid_groups[i]})
	var ls: Array = []
	for l in world.links:
		if l.broken or not l.valid():
			continue
		ls.append({"k": l.kind, "a": l.uid_a, "ai": l.a.index if l.a is JellyPoint else -1, "b": l.uid_b,
			"bi": l.b.index if l.b is JellyPoint else -1, "la": [l.la.x, l.la.y], "lb": [l.lb.x, l.lb.y], "rest": l.rest})
	return {"v": 2, "world": world.world_id, "gravity": world.gravity_id, "night": world.night, "next_uid": world.next_uid, "toys": ts, "wigglies": ws, "links": ls,
		"fighters": fs, "platforms": ps, "liquids": lq, "battle": world.battle_on}


## Puts back everything serialize() saved, except the links: World.restore
## waits a physics step for the new bodies, then calls restore_links.
static func restore(world: World, d: Dictionary) -> void:
	if String(d.get("world", world.world_id)) != world.world_id:
		world.load_world(String(d.world), false)
	world._clear_all()
	# Each thing is made under a new number and then given its saved one. New
	# numbers start above every saved one, so a new thing can't land on a number
	# that something loaded a moment ago already has (that knocked the older one
	# out of the world, but left it lying there: a stray nobody could touch).
	for key in ["toys", "wigglies", "fighters"]:
		for e in d.get(key, []):
			world.next_uid = maxi(world.next_uid, int(e.get("uid", 0)))
	# placed platforms and tubs
	for pl in world.platforms:
		if is_instance_valid(pl.node):
			pl.node.queue_free()
	world.platforms.clear()
	for i in range(world.water.size() - 1, -1, -1):
		if i < world.liquid_groups.size() and int(world.liquid_groups[i]) != 0:
			world.water.remove_at(i)
			world.liquid_kinds.remove_at(i)
			world.liquid_groups.remove_at(i)
	world._water_hold += 1
	for e in d.get("platforms", []):
		var poly := PackedVector2Array()
		for v in e.poly:
			poly.append(Vector2(v[0], v[1]))
		var made := WorldTerrain.add_platform(world, poly, String(e.style), int(e.group))
		if e.has("hp"):
			var pl: Dictionary = world.platforms[world.platforms.size() - 1]
			pl.hp = float(e.hp)
			made.set_damage(1.0 - float(pl.hp) / maxf(1.0, float(pl.max)))
		world.next_group = maxi(world.next_group, int(e.group))
	for e in d.get("liquids", []):
		WorldTerrain.add_liquid(world, Rect2(e.r[0], e.r[1], e.r[2], e.r[3]), String(e.kind), int(e.group))
	world._water_hold -= 1
	WorldTerrain.cut_water(world)
	world.battle_on = bool(d.get("battle", true))
	world.set_gravity(String(d.get("gravity", "normal")))
	world.set_night(bool(d.get("night", false)))
	for e in d.get("toys", []):
		var def_o: Dictionary = Builders.part_def(String(e.id), float(e.pr)) if float(e.get("pr", 0.0)) > 0.0 else {}
		var t := world.spawn_toy(String(e.id), Vector2(e.x, e.y), float(e.a), float(e.get("s", 1.0)), def_o)
		if t == null:
			continue
		world._take_saved_number(t, int(e.uid))
		t.linear_velocity = Vector2(e.vx, e.vy)
		t.angular_velocity = float(e.va)
		if String(e.get("paint", "")) != "":
			t.paint = Color(String(e.paint))
		t.letter = String(e.get("letter", ""))
		t.on = bool(e.get("on", false))
		if float(e.get("f", 1.0)) < 0.0:
			t.set_facing(-1.0)
		t.nailed = bool(e.get("nail", false))
		if t.nailed:
			t.global_position = Vector2(e.x, e.y)   # (right where it was nailed, even set into the ground like a trap's plate)
		t.parent_uid = int(e.get("parent", 0))
		t.frozen_t = float(e.get("ice", 0.0))
		if float(e.get("bub", 0.0)) > 0.0:
			ToyLogic._bubble(world, t, float(e.bub))
		t.update_freeze()
		ToyLogic.update_light(world, t)
	for e in d.get("toys", []):
		var t = world.things.get(int(e.get("uid", 0)))
		for o_uid in e.get("nc", []):
			var o = world.things.get(int(o_uid))
			if t is Toy and o is Toy and o != t:
				WorldLinks.no_collide(t, o)
	for e in d.get("wigglies", []):
		var w := world.spawn_wiggly(String(e.kind), Vector2(e.x, e.y), float(e.get("s", 1.0)))
		if w == null:
			continue
		world._take_saved_number(w, int(e.uid))
		if String(e.get("paint", "")) != "":
			w.paint = Color(String(e.paint))
		var pp: Array = e.get("pts", [])
		if pp.size() == Wiggly.N:
			for i in Wiggly.N:
				w.points[i].global_position = Vector2(pp[i][0], pp[i][1])
	for e in d.get("fighters", []):
		var f := world.spawn_fighter(String(e.type), Vector2(e.x, e.y), String(e.team), String(e.pers), float(e.get("s", 1.0)), false)
		if f == null:
			continue
		world._take_saved_number(f, int(e.uid))
		f.hp = float(e.get("hp", f.max_hp))
		f.armor = float(e.get("armor", f.armor))
		f.helmet = String(e.get("helmet", f.helmet))
		f.body_armor = bool(e.get("body_armor", false))
		f.shield = bool(e.get("shield", false))
		f.facing = float(e.get("f", 1.0))
		if String(e.get("paint", "")) != "":
			f.paint = Color(String(e.paint))
		var wt = world.things.get(int(e.get("weapon", 0)))
		if wt is Toy:
			f.equip(wt)
		if f.hp <= 0.0:
			f.hp = 0.0
			f._ko(Vector2.ZERO, null)
		else:
			# what toys and powers were doing to them
			f.wet = float(e.get("wet", 0.0))
			f.burning = float(e.get("burn", 0.0))
			f.acid = float(e.get("acid", 0.0))
			f.goo_t = float(e.get("goo", 0.0))
			f.stun_t = float(e.get("zap", 0.0))
			if float(e.get("bub", 0.0)) > 0.0:
				f.set_bubble(float(e.bub))
			if float(e.get("ice", 0.0)) > 0.0:
				f.set_frozen(float(e.ice))
			if f.stun_t > 0.0:
				f.mood = "zapped"
			f._show_status()
	world.next_uid = maxi(world.next_uid, int(d.get("next_uid", world.next_uid)))


## The second half of World.restore, a physics step later: the saved links
## between the things just loaded.
static func restore_links(world: World, d: Dictionary) -> void:
	for e in d.get("links", []):
		var a := WorldLinks.resolve_body(world, int(e.a), int(e.ai))
		var b := WorldLinks.resolve_body(world, int(e.b), int(e.bi))
		if a == null or b == null:
			continue
		var l := Link.new()
		l.kind = String(e.k)
		l.a = a
		l.b = b
		l.la = Vector2(e.la[0], e.la[1])
		l.lb = Vector2(e.lb[0], e.lb[1])
		l.rest = float(e.get("rest", 20.0))
		l.uid_a = int(e.a)
		l.uid_b = int(e.b)
		l.build(world.pin_parent)
		world.links.append(l)
	world.world_changed.emit(true)

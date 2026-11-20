class_name NetCommon
## Shared network constants and packet packing.

const PORT := 24700
const BEACON_PORT := 24701
const GAME_ID := "wiggle-works"
const VERSION := 1
const MAX_FRIENDS := 7
const SNAP_HZ := 20.0
const EMOJI := ["👋", "😂", "😮", "🎉", "❤️", "👍", "🔥", "💥"]


static func encode(d: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(d)
	if raw.size() > 400:
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
		var out := PackedByteArray([1])
		out.append_array(PackedByteArray([raw.size() & 0xff, (raw.size() >> 8) & 0xff, (raw.size() >> 16) & 0xff, (raw.size() >> 24) & 0xff]))
		out.append_array(z)
		return out
	var plain := PackedByteArray([0])
	plain.append_array(raw)
	return plain


static func decode(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 2:
		return {}
	var raw: PackedByteArray
	if pkt[0] == 1:
		if pkt.size() < 6:
			return {}
		var n := pkt[1] | (pkt[2] << 8) | (pkt[3] << 16) | (pkt[4] << 24)
		if n <= 0 or n > 8 * 1024 * 1024:
			return {}
		raw = pkt.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD)
	else:
		raw = pkt.slice(1)
	var v = bytes_to_var(raw)
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


## Everything a friend needs to draw the world this tick.
static func snapshot(game) -> Dictionary:
	var w: World = game.world
	var toys: Array = []
	var wigs: Array = []
	for t in w.things.values():
		if t is Toy:
			var bits := int(t.on) | (int(t.is_on()) << 1) | (int(t.frozen_t > 0.0) << 2) | (int(t.bubble_t > 0.0) << 3) \
				| (int(t.electric > 0.05) << 4) | (int(t.nailed) << 5) | (int(t.fuse >= 0.0) << 6) \
				| (int(t.extra.get("pressed", false)) << 7) | (int(t.extra.get("blink", false)) << 8)
			toys.append([t.uid, t.id, t.global_position, t.rotation, t.size_scale, t.facing, t.paint.to_html() if t.paint.a > 0.0 else "",
				t.letter, bits, t.r if t.def.get("part", false) else 0.0, float(t.extra.get("tt", 0.0)), t.color.to_html()])
		elif t is Wiggly:
			var bits := int(t.frozen_t > 0.0) | (int(t.bubble_t > 0.0) << 1) | (int(t.electric > 0.0) << 2) | (int(t.special_t > 0.0) << 3)
			wigs.append([t.uid, t.kind, t.size, t.paint.to_html() if t.paint.a > 0.0 else "", t.pts, t.mood, t.look, bits, t.angle, t.com_vel, t.puff])
	var fs: Array = []
	for f in w.fighters():
		var e := [f.uid, f.type, f.team, f.state, f.hp / maxf(1.0, f.max_hp), f.center(), f.facing, f.aim, f.walk, f.move, f.swing,
			f.grounded, f.mood, f.size, f.helmet, f.body_armor, f.shield, f.burning > 0.0, f.player_id >= 0, f.paint.to_html() if f.paint.a > 0.0 else ""]
		if f.state != "stand":
			var ps := {}
			for k in f.parts:
				var p = f.parts[k]
				if is_instance_valid(p):
					ps[k] = [p.global_position, p.rotation, p.half.y]
			e.append(ps)
		fs.append(e)
	var plats: Array = []
	for pl in w.platforms:
		plats.append([pl.poly, pl.style, pl.group])
	var liqs: Array = []
	for i in w.water.size():
		liqs.append([w.water[i], w.liquid_kinds[i] if i < w.liquid_kinds.size() else "water"])
	var links: Array = []
	for l in w.links:
		if not l.broken and l.valid():
			links.append([l.kind, l.world_a(), l.world_b(), l.signal_on])
	return {"m": "snap", "toys": toys, "wigs": wigs, "links": links, "players": game.net.players_snapshot(),
		"fighters": fs, "plats": plats, "liqs": liqs,
		"st": [w.paused, w.night, w.gravity_id, w.time_scale, w.allow_world_actions, w.world_id, w.battle_on]}


## Applies a host snapshot to a puppet world.
static func apply_snapshot(game, s: Dictionary) -> void:
	var w: World = game.world
	var st: Array = s.get("st", [])
	if st.size() >= 6:
		if String(st[5]) != w.world_id:
			w.load_world(String(st[5]), false)
			game.cam.fit(w.view_rect, game.get_viewport_rect().size)
		var changed: bool = w.paused != bool(st[0]) or w.night != bool(st[1]) or w.gravity_id != String(st[2]) or absf(w.time_scale - float(st[3])) > 0.01 or w.allow_world_actions != bool(st[4])
		w.paused = bool(st[0])
		if w.night != bool(st[1]):
			w.set_night(bool(st[1]))
		w.gravity_id = String(st[2])
		w.time_scale = float(st[3])
		w.allow_world_actions = bool(st[4])
		if st.size() > 6:
			changed = changed or w.battle_on != bool(st[6])
			w.battle_on = bool(st[6])
		if changed and game.hud:
			game.hud.refresh()
	var seen := {}
	for e in s.get("toys", []):
		var uid: int = e[0]
		seen[uid] = true
		var t = w.things.get(uid)
		if t == null:
			var id: String = e[1]
			var d := Catalog.toy(id)
			if float(e[9]) > 0.0:
				d = Builders.part_def(id, float(e[9]))
			t = w.spawn_toy(id, e[2], e[3], float(e[4]), d)
			if t == null:
				continue
			w.things.erase(t.uid)
			t.uid = uid
			w.things[uid] = t
			t.global_position = e[2]
			t.rotation = e[3]
		t.set_meta("net_pos", e[2])
		t.set_meta("net_rot", e[3])
		if absf(t.size_scale - float(e[4])) > 0.001:
			t.set_size(float(e[4]))
		if t.facing != float(e[5]):
			t.set_facing(float(e[5]))
		t.paint = Color(String(e[6])) if String(e[6]) != "" else Color(0, 0, 0, 0)
		t.letter = String(e[7])
		t.color = Color(String(e[11]))
		var bits: int = e[8]
		t.on = bits & 1 != 0
		t.powered = bits & 2 != 0 and not t.on
		t.frozen_t = 1.0 if bits & 4 else 0.0
		t.bubble_t = 1.0 if bits & 8 else 0.0
		t.electric = 1.0 if bits & 16 else 0.0
		t.nailed = bits & 32 != 0
		t.fuse = 1.0 if bits & 64 else -1.0
		t.extra.pressed = bits & 128 != 0
		t.extra.blink = bits & 256 != 0
		t.extra.tt = float(e[10])
		t.extra.art = str(bits)
		ToyLogic.update_light(w, t)
	for e in s.get("wigs", []):
		var uid: int = e[0]
		seen[uid] = true
		var wg = w.things.get(uid)
		var pts: PackedVector2Array = e[4]
		if wg == null:
			var c := Vector2.ZERO
			for p in pts:
				c += p
			c /= maxf(1.0, pts.size())
			wg = w.spawn_wiggly(String(e[1]), c, float(e[2]))
			if wg == null:
				continue
			w.things.erase(wg.uid)
			wg.uid = uid
			w.things[uid] = wg
			wg.pts = pts
		wg.set_meta("net_pts", pts)
		wg.paint = Color(String(e[3])) if String(e[3]) != "" else Color(0, 0, 0, 0)
		wg.mood = String(e[5])
		wg.look = e[6]
		var bits: int = e[7]
		wg.frozen_t = 1.0 if bits & 1 else 0.0
		wg.bubble_t = 1.0 if bits & 2 else 0.0
		wg.electric = 1.0 if bits & 4 else 0.0
		wg.special_t = 1.0 if bits & 8 else 0.0
		wg.angle = float(e[8])
		wg.com_vel = e[9]
		wg.puff = float(e[10])
	for e in s.get("fighters", []):
		var uid: int = e[0]
		seen[uid] = true
		var f = w.things.get(uid)
		if f == null:
			f = w.spawn_fighter(String(e[1]), e[5], String(e[2]), "", 1.0, false)
			if f == null:
				continue
			w.things.erase(f.uid)
			f.uid = uid
			w.things[uid] = f
			f.net = {"c": e[5]}
		f.team = String(e[2])
		f.size = float(e[13])
		f.facing = float(e[6])
		f.aim = float(e[7])
		f.walk = float(e[8])
		f.move = float(e[9])
		f.swing = float(e[10])
		f.grounded = bool(e[11])
		f.helmet = String(e[14])
		f.body_armor = bool(e[15])
		f.shield = bool(e[16])
		f.burning = 1.0 if e[17] else 0.0
		f.player_id = 0 if e[18] else -1
		f.paint = Color(String(e[19])) if String(e[19]) != "" else Color(0, 0, 0, 0)
		f.net["st"] = String(e[3])
		f.net["hp"] = float(e[4])
		f.net["mood"] = String(e[12])
		f.net["tc"] = e[5]
		if e.size() > 20:
			f.net["tparts"] = e[20]
			if not f.net.has("parts") or String(f.net.get("prev_st", "")) == "stand":
				f.net["parts"] = (e[20] as Dictionary).duplicate(true)
		else:
			f.net.erase("parts")
		f.net["prev_st"] = String(e[3])
	var plats: Array = s.get("plats", [])
	if str(plats).hash() != int(w.get_meta("plats_hash", 0)):
		w.set_meta("plats_hash", str(plats).hash())
		for pl in w.platforms:
			if is_instance_valid(pl.node):
				pl.node.queue_free()
		w.platforms.clear()
		for e in plats:
			w.add_platform(e[0], String(e[1]), int(e[2]))
	var liqs: Array = s.get("liqs", [])
	if str(liqs).hash() != int(w.get_meta("liqs_hash", 0)):
		w.set_meta("liqs_hash", str(liqs).hash())
		w.water.clear()
		w.liquid_kinds.clear()
		w.liquid_groups.clear()
		for e in liqs:
			w.add_liquid(e[0], String(e[1]))
		w._cut_water()
	for uid in w.things.keys():
		if not seen.has(uid):
			var t = w.things[uid]
			w.things.erase(uid)
			t.queue_free()
	var ls: Array = []
	for l in s.get("links", []):
		ls.append({"k": l[0], "a": l[1], "b": l[2], "on": l[3]})
	w.link_view.remote_links = ls


## Smoothly moves puppets toward the latest snapshot (call every frame on a client).
static func interpolate(w: World, dt: float) -> void:
	var k := minf(1.0, dt * 16.0)
	for t in w.things.values():
		if t is Toy and t.has_meta("net_pos"):
			var target: Vector2 = t.get_meta("net_pos")
			if t.global_position.distance_to(target) > 300.0:
				t.global_position = target
			else:
				t.global_position = t.global_position.lerp(target, k)
			t.rotation = lerp_angle(t.rotation, float(t.get_meta("net_rot")), k)
		elif t is Fighter and t.puppet:
			var tc: Vector2 = t.net.get("tc", t.net.get("c", Vector2.ZERO))
			var cc: Vector2 = t.net.get("c", tc)
			t.net["c"] = tc if cc.distance_to(tc) > 300.0 else cc.lerp(tc, k)
			if t.net.has("tparts") and t.net.has("parts"):
				var cur: Dictionary = t.net.parts
				for name in t.net.tparts:
					var tp: Array = t.net.tparts[name]
					if cur.has(name):
						var cp: Array = cur[name]
						cp[0] = tp[0] if (cp[0] as Vector2).distance_to(tp[0]) > 300.0 else (cp[0] as Vector2).lerp(tp[0], k)
						cp[1] = lerp_angle(float(cp[1]), float(tp[1]), k)
						cp[2] = tp[2]
					else:
						cur[name] = tp.duplicate()
		elif t is Wiggly and t.has_meta("net_pts"):
			var np: PackedVector2Array = t.get_meta("net_pts")
			if np.size() != t.pts.size():
				t.pts = np
			else:
				for i in np.size():
					t.pts[i] = np[i] if t.pts[i].distance_to(np[i]) > 300.0 else t.pts[i].lerp(np[i], k)
			var c := Vector2.ZERO
			for p in t.pts:
				c += p
			t.com = c / maxf(1.0, t.pts.size())
			t.t += dt
			t.blink_t -= dt
			if t.blink_t < -0.12:
				t.blink_t = randf_range(1.8, 4.5)

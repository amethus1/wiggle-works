class_name NetCommon
## Shared network constants and packet packing.

const PORT := 24700
const BEACON_PORT := 24701
const GAME_ID := "wiggle-works"
const VERSION := 3             # 2: fighters' health, personality and weapon are in snapshots; 3: small snapshots (NetDelta)
## What both sides are told when a friend's copy of the game isn't the same version.
const WRONG_VERSION := "Your friend has a different version: update both games."
const MAX_FRIENDS := 7
const SNAP_HZ := 20.0
const EMOJI := ["👋", "😂", "😮", "🎉", "❤️", "👍", "🔥", "💥"]
const MAX_UNPACKED := 4 * 1024 * 1024   # biggest packet we'll unpack (real snapshots are far smaller)


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


## Unpacks a packet from encode(). Anything broken, empty or suspiciously
## big comes back as {} (and is ignored).
static func decode(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 2 or pkt[0] > 1:
		return {}
	var raw: PackedByteArray
	if pkt[0] == 1:
		if pkt.size() < 6:
			return {}
		var n := pkt[1] | (pkt[2] << 8) | (pkt[3] << 16) | (pkt[4] << 24)
		if n <= 0 or n > MAX_UNPACKED:
			return {}
		raw = pkt.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD)
	else:
		raw = pkt.slice(1)
	if raw.size() < 4:
		return {}
	var v: Variant = bytes_to_var(raw)
	return v if typeof(v) == TYPE_DICTIONARY else {}


## True for a real, sensible number (not NaN or infinity, not huge).
static func num_ok(v: Variant, limit := 1.0e6) -> bool:
	if not (v is float or v is int):
		return false
	var f := float(v)
	return is_finite(f) and absf(f) <= limit


static func vec2_ok(v: Variant, limit := 1.0e5) -> bool:
	return v is Vector2 and (v as Vector2).is_finite() and absf((v as Vector2).x) <= limit and absf((v as Vector2).y) <= limit


static func vec3_ok(v: Variant, limit := 1.0e5) -> bool:
	if not (v is Vector3) or not (v as Vector3).is_finite():
		return false
	var p: Vector3 = v
	return absf(p.x) <= limit and absf(p.y) <= limit and absf(p.z) <= limit


## A friend's name from a hello packet: short plain text, or "Friend".
static func clean_name(v: Variant) -> String:
	var nm := String(v).strip_edges().substr(0, 16) if v is String else ""
	return nm if nm != "" else "Friend"


## Rate limit: true if `who` (a friend's info) may do another `what` now.
## Lets `burst` happen at once, then `per_s` a second, so a stuck key or a
## broken copy of the game can't flood the host.
static func allow(who: Dictionary, what: String, per_s: float, burst: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var key := "rate_" + what
	var b: Array = who.get(key, [burst, now])
	var tokens := minf(burst, float(b[0]) + (now - float(b[1])) * per_s)
	if tokens < 1.0:
		who[key] = [tokens, now]
		return false
	who[key] = [tokens - 1.0, now]
	return true


## Takes `n` more from `who`'s `what` allowance (see allow), for what a
## command turned out to make: a whole block of fighters, or a ready-made
## contraption of many toys, costs one each. It can go below nothing: then
## nothing more gets through until it has filled back up.
static func charge(who: Dictionary, what: String, per_s: float, burst: float, n: float) -> void:
	if n <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var key := "rate_" + what
	var b: Array = who.get(key, [burst, now])
	var tokens := minf(burst, float(b[0]) + (now - float(b[1])) * per_s)
	who[key] = [maxf(tokens - n, -burst * 4.0), now]


static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


## The tables of a snapshot (see NetDelta): what each field of a toy,
## Wiggly and fighter entry in snapshot() is, and how it's rounded.
const TOYS := [NetDelta.STR | NetDelta.ONCE, NetDelta.V2, NetDelta.ANG, NetDelta.F32, NetDelta.FIX16, NetDelta.STR, NetDelta.STR,
	NetDelta.U32, NetDelta.F32 | NetDelta.ONCE, NetDelta.FIX32, NetDelta.STR]
const WIGS := [NetDelta.STR | NetDelta.ONCE, NetDelta.F32, NetDelta.STR, NetDelta.PTS, NetDelta.STR, NetDelta.V2S, NetDelta.U32,
	NetDelta.FIX32, NetDelta.V2, NetDelta.FIX16]
const FIGHTERS := [NetDelta.STR | NetDelta.ONCE, NetDelta.STR, NetDelta.STR, NetDelta.FRAC, NetDelta.V2, NetDelta.FIX16, NetDelta.FIX16,
	NetDelta.F32, NetDelta.FIX16, NetDelta.FIX16, NetDelta.BOOL, NetDelta.STR, NetDelta.F32, NetDelta.STR, NetDelta.BOOL, NetDelta.BOOL,
	NetDelta.BOOL, NetDelta.BOOL, NetDelta.STR, NetDelta.FIX32, NetDelta.FIX32, NetDelta.STR, NetDelta.STR, NetDelta.STR, NetDelta.POSE]
## ...and the single values (sent only when they change).
const SINGLES := ["links", "players", "plats", "liqs", "st"]
static var TABLES: Array = [["toys", PackedInt32Array(TOYS)], ["wigs", PackedInt32Array(WIGS)], ["fighters", PackedInt32Array(FIGHTERS)]]


## snapshot() split for NetDelta.Sender.push: [each table's entries, the single values].
static func delta_state(s: Dictionary) -> Array:
	var t := {}
	for tp: Array in TABLES:
		t[tp[0]] = s.get(tp[0], [])
	var g := {}
	for k: String in SINGLES:
		g[k] = s.get(k)
	return [t, g]


## The newest whole snapshot a NetDelta.Receiver has, back the way snapshot() made it.
static func from_delta(rx: NetDelta.Receiver) -> Dictionary:
	var out := rx.snapshot()
	out["m"] = "snap"
	var fs: Array = []
	for e: Array in out.get("fighters", []):
		var e2 := e.slice(0, 24)
		var names := String(e[24]).split(",", false)
		if not names.is_empty():
			e2.append(parts_from(names, e[25], e[5]))
		fs.append(e2)      # (standing: no ragdoll parts)
	out["fighters"] = fs
	return out


## A ragdoll's parts {name: [where, angle, half height]} from the names and
## rounded numbers in a snapshot (see _pose), around the fighter's middle `c`.
static func parts_from(names: PackedStringArray, pose: Variant, c: Variant) -> Dictionary:
	var out := {}
	var a: PackedInt32Array = pose if pose is PackedInt32Array else PackedInt32Array()
	var mid: Vector2 = c if c is Vector2 else Vector2.ZERO
	for i in mini(names.size(), a.size() / 4):
		out[names[i]] = [mid + Vector2(a[i * 4], a[i * 4 + 1]) * 0.5, a[i * 4 + 2] * TAU / 256.0, float(a[i * 4 + 3])]
	return out


## A ragdoll's parts for a snapshot: their names, and each one's place
## (from the fighter's middle `c`, to half a pixel), angle and half height,
## rounded so a ragdoll lying still is the same in every snapshot.
## (The third thing it gives back is the same, much rougher: 4 pixels and
## 1/32 of a turn. snapshot() only sends a new pose when that changes, or
## the middle moves, so a heap that's only jiggling sends nothing.)
static func _pose(f, c: Vector2) -> Array:
	var names: Array = f.parts.keys()
	names.sort()
	var ns := PackedStringArray()
	var a := PackedInt32Array()
	var rough := PackedInt32Array()
	for k in names:
		var p = f.parts[k]
		if not is_instance_valid(p):
			continue
		var d := Vector2i(((p.global_position - c) * 2.0).round()).clamp(Vector2i(-32768, -32768), Vector2i(32767, 32767))
		var ang := posmod(roundi(float(p.rotation) * 256.0 / TAU), 256)
		ns.append(String(k))
		a.append_array([d.x, d.y, ang, clampi(roundi(float(p.half.y)), 0, 255)])
		rough.append_array([d.x >> 3, d.y >> 3, ang >> 3])
	return [",".join(ns), a, rough]


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
			f.grounded, f.mood, f.size, f.helmet, f.body_armor, f.shield, f.burning > 0.0, f.player_id >= 0, f.paint.to_html() if f.paint.a > 0.0 else "",
			f.hp, f.max_hp, f.pers, f.weapon_id]
		# a ragdoll's parts: their names, and where each is from its middle (see _pose)
		if f.state == "stand":
			e.append_array(["", PackedInt32Array()])
		else:
			var c := Vector2((f.center() * 8.0).round()) / 8.0
			var pose := _pose(f, c)
			var was: Variant = f.get_meta("net_pose") if f.has_meta("net_pose") else null
			if was is Array and (was as Array)[0] == pose[0] and (was as Array)[2] == pose[2] and ((was as Array)[3] as Vector2).distance_to(c) < 2.0:
				# a heap that's only jiggling a little: the same as last time (nothing to send)
				e[5] = (was as Array)[3]
				e.append_array([(was as Array)[0], (was as Array)[1]])
			else:
				f.set_meta("net_pose", [pose[0], pose[1], pose[2], c])
				e.append_array([pose[0], pose[1]])
		fs.append(e)
	var plats: Array = []
	for pl in w.platforms:
		# (and how cracked it is, if blasts have been at it)
		plats.append([pl.poly, pl.style, pl.group, pl.node.cracks if is_instance_valid(pl.node) else 0])
	var liqs: Array = []
	for i in w.water.size():
		liqs.append([w.water[i], w.liquid_kinds[i] if i < w.liquid_kinds.size() else "water"])
	var links: Array = []
	for l in w.links:
		if not l.broken and l.valid():
			links.append([l.kind, l.world_a(), l.world_b(), l.signal_on, l.rest])   # (rest: how long a rope is, so it sags)
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
	# first take away what the host no longer has, so nothing new lands on its number
	var seen := {}
	for key in ["toys", "wigs", "fighters"]:
		for e in s.get(key, []):
			seen[int(e[0])] = true
	for uid in w.things.keys():
		if not seen.has(uid):
			_drop_puppet(w, uid)
	for e in s.get("toys", []):
		var uid: int = e[0]
		var t = w.things.get(uid)
		if t != null and not (t is Toy):
			_drop_puppet(w, uid)
			t = null
		if t == null:
			var id: String = e[1]
			var d := Catalog.toy(id)
			if float(e[9]) > 0.0:
				d = Builders.part_def(id, float(e[9]))
			_free_uid(w)
			t = w.spawn_toy(id, e[2], e[3], float(e[4]), d)
			if t == null:
				continue
			w.renumber(t, uid)
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
		var wg = w.things.get(uid)
		if wg != null and not (wg is Wiggly):
			_drop_puppet(w, uid)
			wg = null
		var pts: PackedVector2Array = e[4]
		if wg == null:
			var c := Vector2.ZERO
			for p in pts:
				c += p
			c /= maxf(1.0, pts.size())
			_free_uid(w)
			wg = w.spawn_wiggly(String(e[1]), c, float(e[2]))
			if wg == null:
				continue
			w.renumber(wg, uid)
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
		var f = w.things.get(uid)
		if f != null and not (f is Fighter):
			_drop_puppet(w, uid)
			f = null
		if f == null:
			_free_uid(w)
			f = w.spawn_fighter(String(e[1]), e[5], String(e[2]), "", 1.0, false)
			if f == null:
				continue
			w.renumber(f, uid)
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
		if String(e[3]) in ["stand", "ragdoll", "dead"]:
			f.state = String(e[3])      # knocked out: alive() is false for the HUD, the controls and the grey look
		f.net["hp"] = float(e[4])
		f.net["mood"] = String(e[12])
		f.net["tc"] = e[5]
		f.hp = float(e[20])
		f.max_hp = float(e[21])
		f.pers = String(e[22])
		f.weapon_id = String(e[23])
		# a ragdoll's parts: {name: [where, angle, half]}, or straight from
		# snapshot() as their names and rounded numbers (see _pose)
		var tparts: Variant = e[24] if e.size() > 24 else null
		if tparts is String:
			var names := String(tparts).split(",", false)
			tparts = parts_from(names, e[25] if e.size() > 25 else null, e[5]) if not names.is_empty() else null
		if tparts is Dictionary:
			f.net["tparts"] = tparts
			if not f.net.has("parts") or String(f.net.get("prev_st", "")) == "stand":
				f.net["parts"] = (tparts as Dictionary).duplicate(true)
		else:
			f.net.erase("tparts")
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
			var g := w.add_platform(e[0], String(e[1]), int(e[2]))
			if e.size() > 3 and NetCommon.num_ok(e[3], 4.0):
				g.set_damage(float(e[3]) / 4.0 + 0.01)
	var liqs: Array = s.get("liqs", [])
	if str(liqs).hash() != int(w.get_meta("liqs_hash", 0)):
		w.set_meta("liqs_hash", str(liqs).hash())
		w.water.clear()
		w.liquid_kinds.clear()
		w.liquid_groups.clear()
		for e in liqs:
			w.add_liquid(e[0], String(e[1]))
		w._cut_water()
	var ls: Array = []
	for l in s.get("links", []):
		ls.append({"k": l[0], "a": l[1], "b": l[2], "on": l[3], "r": float(l[4]) if l.size() > 4 and NetCommon.num_ok(l[4], 1.0e5) else 0.0})
	w.link_view.remote_links = ls


## Removes a puppet the host no longer has (node and all).
static func _drop_puppet(w: World, uid: int) -> void:
	var t = w.things.get(uid)
	w.forget(uid)
	if t != null and is_instance_valid(t):
		(t as Node).queue_free()


## A new puppet is spawned under a number of our own, then renumbered to the
## host's. Skips numbers already in use here, so making it can't knock
## another puppet out of the list (it would be left behind as a frozen ghost).
static func _free_uid(w: World) -> void:
	while w.things.has(w.next_uid + 1):
		w.next_uid += 1


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

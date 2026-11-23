class_name B3Saves
## Save slots for 3D battles: the map, rules, fighters (kind, team, mood,
## place, health, size, and the extra toughness or slowness some History
## armies get; a plane or helicopter's flying height and whether it's
## parked), buildings, props (barrels, C4, mines, crates), lava/acid pools,
## the 📜 History battle it is (so it can still earn ⭐) and the camera.
## In 🪙 budget battles each thing also keeps the points paid for it ("c"),
## a 🧩 puzzle's own things say so ("pz"), and crates bought as one stack
## stay one ("g"), so ⏮ Reset gives back exactly what you paid.
## Stored as JSON in user://b3_saves/. Saving during or after a fight saves
## the setup from when Fight! was pressed, so loading it gives you the same
## battle to play again.

const SLOTS := 6


static func _dir() -> String:
	return "user://b3_saves_test" if Settings.testing else "user://b3_saves"


static func _path(slot: int) -> String:
	return "%s/slot%d.json" % [_dir(), slot]


static func snapshot(b) -> Dictionary:
	var us: Array = []
	for u: B3Unit in b.units:
		if not is_instance_valid(u) or u.dead:
			continue
		var p: Vector3 = u.center() if u.down else u.position
		var e := {"k": u.kind, "t": u.team, "p": u.pers_choice, "x": p.x, "y": p.y, "z": p.z, "f": u.facing,
			"hp": u.hp / maxf(1.0, u.max_hp), "mh": u.max_hp, "sp": u.speed, "s": u.size_mult, "sd": int(u.get_meta("seed", -1))}
		if u.has_meta("history"):
			e["h"] = true      # a History battle's fighter (B3History keeps the fight from stalling)
		if u is B3Aircraft:
			e["alt"] = (u as B3Aircraft).alt      # how high it flies
			if (u as B3Aircraft).parked:
				e["pk"] = true                     # (the Hangar's plane and helicopter sit on the ground)
		us.append(_marks(u, e))
	var ss: Array = []
	for s: B3Struct in b.structs:
		if is_instance_valid(s) and not s.pieces.is_empty():
			var e := {"k": s.kind, "x": s.position.x, "y": s.position.y, "z": s.position.z, "yaw": s.rotation.y, "len": s.length,
				"sd": int(s.get_meta("seed", -1))}
			if not B3Defs.STRUCTS.has(s.kind):
				e["pcs"] = s.piece_data()      # History battles' stakes, forts and fences
			ss.append(_marks(s, e))
	var ps: Array = []
	var stacks := {}       # crate stacks (meta "stack") -> 1, 2, 3...
	for p: B3Prop in b.props:
		if is_instance_valid(p) and not p.lit and p.sinking <= 0.0:
			var gp := p.global_position
			var e := {"k": p.kind, "x": gp.x, "y": gp.y, "z": gp.z, "yaw": p.rotation.y}
			if p.has_meta("stack"):
				var sid := int(p.get_meta("stack"))
				if not stacks.has(sid):
					stacks[sid] = stacks.size() + 1
				e["g"] = int(stacks[sid])
			ps.append(_marks(p, e))
	var hs: Array = []
	for h: B3Hazard in b.hazards:
		if is_instance_valid(h) and h.life < 0.0:
			hs.append(_marks(h, {"k": h.kind, "x": h.position.x, "z": h.position.z, "r": h.radius}))
	var d := {"v": 1, "map": b.map_id, "rules": B3Rules.values.duplicate(), "units": us, "structs": ss, "props": ps, "hazards": hs,
		"cam": [b.cam.focus.x, b.cam.focus.z, b.cam.size, b.cam.yaw_target], "when": Time.get_datetime_string_from_system(false, true)}
	if String(b.history_id) != "":
		d["hid"] = String(b.history_id)      # 📜 which History battle (for its ⭐ stars)
	return d


## `e` with `n`'s 🪙 price ("c") and 🧩 puzzle mark ("pz") added, if it has them.
static func _marks(n: Node, e: Dictionary) -> Dictionary:
	if n.has_meta("cost"):
		e["c"] = int(n.get_meta("cost"))
	if n.has_meta("puzzle"):
		e["pz"] = true
	return e


## Puts `e`'s 🪙 price and 🧩 puzzle mark back on `n`. The price only
## counts in a budget battle (⏮ Reset in a 🧩 puzzle or 🌊 Wave Defense).
static func _unmark(b, n: Node, e: Dictionary) -> void:
	if n == null:
		return
	if e.has("c") and int(b.budget) >= 0:
		n.set_meta("cost", int(e.c))
	if bool(e.get("pz", false)):
		n.set_meta("puzzle", true)


## Puts a saved battle back. same_map (⏮ Reset): if it's the map we're on,
## keep the land as it is (History battles clear trees for their armies).
static func restore(b, d: Dictionary, with_rules := true, same_map := false) -> void:
	if b.tools:
		b.tools.stop_playing()
	b.set_fighting(false)
	b.winner = ""
	var rules: Dictionary = d.get("rules", {})
	if with_rules and not rules.is_empty():
		B3Rules.load_from_settings()
		for k in rules:
			# (Screen shake is how you like to watch, not part of the battle)
			if B3Rules.DEFAULTS.has(k) and k != "shake":
				B3Rules.values[k] = String(rules[k])
		Settings.b3_rules = B3Rules.values.duplicate()
		Settings.save()
	var map_s := String(d.get("map", "grassland"))
	if same_map and map_s == b.map_id:
		b.clear_battlefield()
	else:
		b.load_map(map_s)
	b.apply_rules()
	for e in d.get("structs", []):
		var s: Node = null
		if e.has("pcs"):
			s = b.spawn_custom_struct(String(e.k), Vector3(float(e.x), float(e.get("y", 0.0)), float(e.z)), float(e.yaw), e.pcs)
		else:
			s = b.spawn_struct(String(e.k), Vector3(float(e.x), 0, float(e.z)), float(e.yaw), float(e.get("len", 0.0)), int(e.get("sd", -1)))
		_unmark(b, s, e)
	for e in d.get("hazards", []):
		var at := Vector3(float(e.x), 0, float(e.z))
		var dup := false
		for h: B3Hazard in b.hazards:
			if is_instance_valid(h) and h.kind == String(e.k) and Vector2(h.position.x - at.x, h.position.z - at.z).length() < 1.0:
				dup = true    # the volcano's own lava lakes come back with the map
		if not dup:
			_unmark(b, b.spawn_hazard(String(e.k), at, float(e.r)), e)
	var stacks := {}       # a saved crate stack ("g") -> the stack id its crates share now
	for e in d.get("props", []):
		var p = b.spawn_prop(String(e.k), Vector3(float(e.x), float(e.y), float(e.z)), float(e.yaw))
		if p:
			p.global_position = Vector3(float(e.x), float(e.y), float(e.z))
			_unmark(b, p, e)
			if e.has("g") and int(b.budget) >= 0:
				var g := int(e.g)
				if not stacks.has(g):
					stacks[g] = (p as Node).get_instance_id()
				(p as Node).set_meta("stack", int(stacks[g]))
	var watched: Array = []
	for e in d.get("units", []):
		var x := float(e.x)
		var z := float(e.z)
		# the floor right under where it was (inside a bunker, not on its roof);
		# old saves without a height get the top of whatever is there
		var top := float(e.y) + 0.6 if e.has("y") else 60.0
		var u = b.spawn_unit(String(e.k), String(e.t), Vector3(x, b.surface_y(Vector3(x, top, z)), z), String(e.get("p", "auto")), float(e.get("f", 0.0)), float(e.get("s", 1.0)), int(e.get("sd", -1)))
		if u:
			if e.has("mh"):
				u.max_hp = float(e.mh)      # History: tougher hoplites, worn-out French knights...
			if e.has("sp"):
				u.speed = float(e.sp)       # ...and slow ones stuck in the mud
			u.hp = u.max_hp * clampf(float(e.get("hp", 1.0)), 0.05, 1.0)
			if bool(e.get("h", false)):
				watched.append(u)
			if u is B3Aircraft:
				if e.has("alt"):
					(u as B3Aircraft).alt = float(e.alt)
				if bool(e.get("pk", false)):
					(u as B3Aircraft).parked = true
			_unmark(b, u, e)
	if not watched.is_empty():
		B3History.watch(b, watched)
	var hid := String(d.get("hid", ""))
	if hid != "" and not B3History.info(hid).is_empty():
		b.history_id = hid       # 📜 still that History battle, so it can earn its ⭐ stars
	var c: Array = d.get("cam", [])
	if c.size() == 4:
		b.cam.focus = Vector3(float(c[0]), 0, float(c[1]))
		b.cam.size = float(c[2])
		b.cam.yaw_target = float(c[3])
		b.cam.yaw = float(c[3])
		b.cam.apply()
	if b.ui:
		b.ui.refresh()


static func save(b, slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir())
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(what_to_save(b)))
	return true


## The battle's setup from before the fight if one has started, otherwise
## everything as it is now.
static func what_to_save(b) -> Dictionary:
	if (b.fighting or b.winner != "") and not (b.start_layout as Dictionary).is_empty():
		var d: Dictionary = (b.start_layout as Dictionary).duplicate(true)
		d["when"] = Time.get_datetime_string_from_system(false, true)
		return d
	return snapshot(b)


static func read(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func load_slot(b, slot: int) -> bool:
	var d := read(slot)
	if d.is_empty():
		return false
	restore(b, d)
	return true


## "🌳 Grassland · 24 fighters · 2026-11-19 21:40", or "" for an empty slot.
static func describe(slot: int) -> String:
	var d := read(slot)
	if d.is_empty():
		return ""
	var md: Dictionary = B3Defs.MAPS.get(String(d.get("map", "grassland")), B3Defs.MAPS.grassland)
	var n: int = (d.get("units", []) as Array).size()
	var when := String(d.get("when", "")).replace("T", " ")
	if when.length() > 16:
		when = when.substr(0, 16)
	return "%s %s · %d fighter%s · %s" % [md.icon, md.name, n, "" if n == 1 else "s", when]


static func delete_all_test_saves() -> void:
	for i in SLOTS:
		var p := "user://b3_saves_test/slot%d.json" % (i + 1)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

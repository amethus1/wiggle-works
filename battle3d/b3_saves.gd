class_name B3Saves
## Save slots for 3D battles: the map, rules, fighters (kind, team, mood,
## place, health, size), buildings, props (barrels, C4, mines, crates),
## lava/acid pools and the camera. Stored as JSON in user://b3_saves/.
## Saving during or after a fight saves the setup from when Fight! was
## pressed, so loading it gives you the same battle to play again.

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
		us.append({"k": u.kind, "t": u.team, "p": u.pers_choice, "x": p.x, "z": p.z, "f": u.facing, "hp": u.hp / maxf(1.0, u.max_hp), "s": u.size_mult, "sd": int(u.get_meta("seed", -1))})
	var ss: Array = []
	for s: B3Struct in b.structs:
		if is_instance_valid(s) and not s.pieces.is_empty():
			var e := {"k": s.kind, "x": s.position.x, "y": s.position.y, "z": s.position.z, "yaw": s.rotation.y, "len": s.length,
				"sd": int(s.get_meta("seed", -1))}
			if not B3Defs.STRUCTS.has(s.kind):
				e["pcs"] = s.piece_data()      # History battles' stakes, forts and fences
			ss.append(e)
	var ps: Array = []
	for p: B3Prop in b.props:
		if is_instance_valid(p) and not p.lit and p.sinking <= 0.0:
			var gp := p.global_position
			ps.append({"k": p.kind, "x": gp.x, "y": gp.y, "z": gp.z, "yaw": p.rotation.y})
	var hs: Array = []
	for h: B3Hazard in b.hazards:
		if is_instance_valid(h) and h.life < 0.0:
			hs.append({"k": h.kind, "x": h.position.x, "z": h.position.z, "r": h.radius})
	return {"v": 1, "map": b.map_id, "rules": B3Rules.values.duplicate(), "units": us, "structs": ss, "props": ps, "hazards": hs,
		"cam": [b.cam.focus.x, b.cam.focus.z, b.cam.size, b.cam.yaw_target], "when": Time.get_datetime_string_from_system(false, true)}


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
			if B3Rules.DEFAULTS.has(k):
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
		if e.has("pcs"):
			b.spawn_custom_struct(String(e.k), Vector3(float(e.x), float(e.get("y", 0.0)), float(e.z)), float(e.yaw), e.pcs)
		else:
			b.spawn_struct(String(e.k), Vector3(float(e.x), 0, float(e.z)), float(e.yaw), float(e.get("len", 0.0)), int(e.get("sd", -1)))
	for e in d.get("hazards", []):
		var at := Vector3(float(e.x), 0, float(e.z))
		var dup := false
		for h: B3Hazard in b.hazards:
			if is_instance_valid(h) and h.kind == String(e.k) and Vector2(h.position.x - at.x, h.position.z - at.z).length() < 1.0:
				dup = true    # the volcano's own lava lakes come back with the map
		if not dup:
			b.spawn_hazard(String(e.k), at, float(e.r))
	for e in d.get("props", []):
		var p = b.spawn_prop(String(e.k), Vector3(float(e.x), float(e.y), float(e.z)), float(e.yaw))
		if p:
			p.global_position = Vector3(float(e.x), float(e.y), float(e.z))
	for e in d.get("units", []):
		var x := float(e.x)
		var z := float(e.z)
		var u = b.spawn_unit(String(e.k), String(e.t), Vector3(x, b.surface_y(Vector3(x, 60.0, z)), z), String(e.get("p", "auto")), float(e.get("f", 0.0)), float(e.get("s", 1.0)), int(e.get("sd", -1)))
		if u:
			u.hp = u.max_hp * clampf(float(e.get("hp", 1.0)), 0.05, 1.0)
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

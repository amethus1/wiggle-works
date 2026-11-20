extends Node
## Headless checks for 📜 History (B3History) and the History fighters:
## every battle sets up (two or more sides, everyone standing on the ground,
## not too many fighters, nothing moving before Fight), a few play out to a
## winner, and the new fighters work (riders fall off their horses and get
## back on, muskets fire in volleys and stab with bayonets).
## godot --headless --path . -- --test=history

const SPEED := 4.0
const MAX_FIGHTERS := 165
const PLAY_OUT := ["thermopylae", "alesia", "agincourt"]

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map := "grassland") -> void:
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(99)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 777, "no_ui": false, "map": map})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	await _list()
	await _setups()
	await _fighters()
	await _play_out()
	B3Rules.reset()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	print("test_history: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ list
func _list() -> void:
	print("history list")
	var last := -99999
	var ordered := true
	var complete := true
	for d in B3History.LIST:
		var e: Dictionary = d
		for k in ["id", "name", "year", "place", "icon", "map", "sides", "blurb"]:
			if not e.has(k) or str(e[k]) == "":
				complete = false
				print("    %s is missing %s" % [e.get("id", "?"), k])
		if int(e.year) < last:
			ordered = false
		last = int(e.year)
	check(B3History.LIST.size() >= 8, "%d battles" % B3History.LIST.size())
	check(complete, "each has an id, name, year, place, icon, map, sides and blurb")
	check(ordered, "in date order")
	check(B3History.year_text(-480) == "480 BC" and B3History.year_text(1066) == "1066", "years read as \"480 BC\" and \"1066\"")
	var cat_ok := false
	for c in B3Defs.CATS:
		if String(c.id) == "history":
			cat_ok = true
	var units_ok := true
	for id in B3Defs.UNIT_ORDER.get("history", []):
		if not B3Defs.UNITS.has(id) or String(B3Defs.UNITS[id].cat) != "history":
			units_ok = false
	check(cat_ok and B3Defs.UNIT_ORDER.has("history") and units_ok, "📜 History tab in the Toy Box with %d fighters" % B3Defs.UNIT_ORDER.get("history", []).size())


# --------------------------------------------------------------- set-ups
func _setups() -> void:
	print("every battle sets up")
	await fresh()
	for d in B3History.LIST:
		var id := String(d.id)
		B3History.run(b, id)
		await sim(2.0)
		var teams := {}
		var n := 0
		var floating := 0
		var sunk := 0
		var moving := 0
		var down := 0
		for u: B3Unit in b.units:
			n += 1
			teams[u.team] = true
			if u.down:
				down += 1
				continue
			if u.flying:
				continue
			var gy: float = b.world.height_at(u.position.x, u.position.z)
			var sy: float = b.surface_y(u.position + Vector3(0, 1.0, 0))
			if u.position.y < gy - 0.35:
				sunk += 1
				print("    %s %s at %s is under the ground (%.2f)" % [u.team, u.kind, u.position, gy])
			elif u.position.y - sy > (1.0 if u is B3Vehicle else 0.45):
				floating += 1
				print("    %s %s at %s is up in the air (%.2f above %.2f)" % [u.team, u.kind, u.position, u.position.y - sy, sy])
			if u.linear_velocity.length() > 1.2 and not u is B3Vehicle:
				moving += 1
				print("    %s %s at %s is still moving (%.1f m/s)" % [u.team, u.kind, u.position, u.linear_velocity.length()])
		check(teams.size() >= 2 and n >= (12 if id == "britain" else 20) and n <= MAX_FIGHTERS, "%s: %d fighters, %d sides, on %s" % [id, n, teams.size(), b.map_id])
		check(sunk == 0 and floating == 0 and down == 0, "%s: everyone stands on the ground (%d under, %d in the air, %d fallen over)" % [id, sunk, floating, down])
		check(not b.fighting and moving == 0, "%s: waits for ▶ Fight! (%d still moving)" % [id, moving])
	check(true, "no script errors setting up (the suite runner catches them)")


# --------------------------------------------------------------- fighters
func _fighters() -> void:
	print("history fighters")
	await fresh()
	var ok := true
	var x := -20.0
	for id in B3Defs.UNIT_ORDER.get("history", []):
		var u: B3Unit = b.spawn_unit(String(id), "red", Vector3(x, b.world.height_at(x, 8.0), 8.0), "peaceful")
		x += 2.5
		if u == null or u.rig == null or u.rig.meshes.size() < 10:
			ok = false
			print("    %s has no proper model" % id)
	await sim(1.0)
	check(ok, "every History fighter builds its model")

	# a rider gets knocked over: rider and horse fall apart, then it gets back up
	await fresh()
	var cav: B3Unit = b.spawn_unit("cavalry", "red", Vector3(0, b.world.height_at(0, 0), 0), "peaceful")
	await sim(0.5)
	var parts: int = cav.rig.parts.size()
	cav.knock_down(Vector3(6, 7, 0))
	await sim(0.1)
	var n_bodies: int = cav.ragdoll.bodies.size() if cav.ragdoll else 0
	check(cav.down and parts >= 12 and n_bodies == parts, "a knocked-over rider and horse turn into a ragdoll (%d parts)" % parts)
	var sep_max := 0.0
	for i in 20:
		await sim(0.1)
		if cav.ragdoll and is_instance_valid(cav.ragdoll) and cav.ragdoll.bodies.size() > 6:
			sep_max = maxf(sep_max, cav.ragdoll.bodies[0].global_position.distance_to(cav.ragdoll.bodies[6].global_position))
	check(sep_max > 1.2, "the rider tumbles off the horse (%.1f m apart)" % sep_max)
	var t := 0.0
	while is_instance_valid(cav) and cav.down and t < 12.0:
		await sim(0.5)
		t += 0.5
	check(is_instance_valid(cav) and not cav.down and cav.rig != null and cav.rig.pv.has("horse"), "and climbs back on (after %.1f s)" % t)

	# muskets: one volley together, with smoke; bayonets up close
	await fresh()
	var line: Array = []
	for i in 6:
		line.append(b.spawn_unit("redcoat", "red", Vector3(-12, b.world.height_at(-12, i * 1.2), i * 1.2), "defend", PI * 0.5))
	var foes: Array = []
	for i in 6:
		var f: B3Unit = b.spawn_unit("knight", "blue", Vector3(10, b.world.height_at(10, i * 1.2), i * 1.2), "peaceful", -PI * 0.5)
		f.hp = 9999.0
		f.max_hp = 9999.0
		foes.append(f)
	b.set_fighting(true)
	var shot_at := {}
	for i in 140:
		await sim(0.05)
		for u in line:
			var r: B3Unit = u
			if is_instance_valid(r) and r.act == "shoot" and not shot_at.has(r.uid):
				shot_at[r.uid] = b.time
	var first := 1e9
	var last_t := -1e9
	for k in shot_at:
		first = minf(first, float(shot_at[k]))
		last_t = maxf(last_t, float(shot_at[k]))
	check(shot_at.size() >= 5 and last_t - first < 1.0, "redcoats fire together in a volley (%d shots within %.2f s)" % [shot_at.size(), last_t - first])
	var hurt := 0
	for f in foes:
		if (f as B3Unit).hp < 9999.0:
			hurt += 1
	check(hurt >= 1, "and hit (%d knights hit)" % hurt)
	var r0: B3Unit = line[0]
	check(String(r0.melee.get("anim", "")) == "thrust", "redcoats have bayonets for close up")
	await fresh()
	var rc: B3Unit = b.spawn_unit("redcoat", "red", Vector3(0, b.world.height_at(0, 0), 0), "attack", PI * 0.5)
	var vk: B3Unit = b.spawn_unit("viking", "blue", Vector3(1.6, b.world.height_at(1.6, 0), 0), "peaceful", -PI * 0.5)
	vk.hp = 9999.0
	vk.max_hp = 9999.0
	b.set_fighting(true)
	var stabbed := false
	for i in 60:
		await sim(0.05)
		if is_instance_valid(rc) and rc.act == "attack" and String(rc.act_w.get("anim", "")) == "thrust":
			stabbed = true
	check(stabbed, "and stab with them when an enemy is right in front")

	# horses charge a lone soldier, but won't charge into a wall of bayonets
	var charged := {}
	for wall in [false, true]:
		await fresh()
		var horse: B3Unit = b.spawn_unit("cavalry", "blue", Vector3(-12, b.world.height_at(-12, 0), 0), "attack", PI * 0.5)
		var n := 5 if wall else 1
		for i in n:
			var z := (i - (n - 1) * 0.5) * 1.1
			var foot: B3Unit = b.spawn_unit("linesman" if wall else "soldier", "red", Vector3(0, b.world.height_at(0, z), z), "peaceful", -PI * 0.5)
			foot.hp = 9999.0
			foot.max_hp = 9999.0
			foot.speed = 0.0          # stand still (peaceful ones wander about)
		b.set_fighting(true)
		charged[wall] = false
		for i in 60:
			await sim(0.05)
			if is_instance_valid(horse) and horse.act == "charge":
				charged[wall] = true
	check(bool(charged[false]), "cavalry charges a lone soldier")
	check(not bool(charged[true]), "but not a line of bayonets (they ride round it)")


# -------------------------------------------------------------- play out
func _play_out() -> void:
	print("battles play out")
	for id in PLAY_OUT:
		await fresh()
		B3History.run(b, String(id))
		await sim(0.5)
		var n0: int = b.units.size()
		b.set_fighting(true)
		var t := 0.0
		while b.winner == "" and t < 240.0:
			await sim(1.0)
			t += 1.0
		check(b.winner != "", "%s: %s wins after %.0f s (%d of %d left)" % [id, b.winner if b.winner != "" else "nobody", t, b.units.size(), n0])

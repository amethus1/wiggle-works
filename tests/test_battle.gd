extends Node
## Headless checks for 3D Battle (battle3d/): everything spawns, fights end,
## blasts launch ragdolls, knocked-down fighters get back up, nukes clear the
## field, lava and acid KO, and each personality behaves.
## godot --headless --path . -- --test=battle

const SPEED := 4.0          # run the sim 4x faster than real time (dt stays 1/60)

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    ", msg)
	else:
		print("  FAIL  ", msg)
		fails += 1


func fresh(map := "grassland", scenario := "", ui := false) -> void:
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(1234)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 4321, "no_ui": not ui, "map": map, "scenario": scenario})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


## Waits `t` seconds of battle time.
func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


func alive(team := "") -> Array:
	var out := []
	for u in b.units:
		if not u.dead and (team == "" or u.team == team):
			out.append(u)
	return out


func _ready() -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("B3_ONLY")
	if only != "":
		await call(only)
		if b and is_instance_valid(b):
			b.queue_free()
		for i in 3:
			await get_tree().process_frame
		print("test_battle: %d failure(s)" % fails)
		get_tree().quit(1 if fails > 0 else 0)
		return
	await _spawn_everything()
	await _maps()
	await _small_fight()
	await _blast_ragdolls()
	await _get_up()
	await _chain_and_c4()
	await _mine_and_walls()
	await _lava_acid()
	await _personalities()
	await _nuke()
	await _scenarios()
	await _new_kinds_everywhere()
	await _new_kinds_fight()
	await _vehicle_blasts()
	await _vehicle_wrecks()
	await _fire_breathers()
	await _gorilla_and_robot()
	await _vehicle_palette()
	await _ui_smoke()
	await _performance()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	print("test_battle: done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("test_battle: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ spawn
func _spawn_everything() -> void:
	print("spawn everything")
	await fresh()
	var i := 0
	for cat in ["people", "animals", "dinos"]:
		for id in B3Defs.UNIT_ORDER[cat]:
			var x := -24.0 + (i % 8) * 6.0
			var z := -14.0 + int(i / 8) * 7.0
			var u = b.spawn_unit(String(id), B3Defs.TEAM_ORDER[i % 5], at(x, z))
			check(u != null and u.rig != null, "spawns a %s" % id)
			i += 1
	await sim(1.5)
	var standing := 0
	for u in b.units:
		var gy: float = b.world.height_at(u.position.x, u.position.z)
		if not u.down and u.hp > 0.0 and (u.flying or absf(u.position.y - gy) < 0.6):
			standing += 1
	check(standing == i, "all %d fighters stand on the ground before the fight (%d)" % [i, standing])
	var parts_ok := true
	for u in b.units:
		var ragdoll_parts: int = u.rig.parts.size()
		if ragdoll_parts < 4:
			parts_ok = false
	check(parts_ok, "every fighter has a ragdoll recipe")
	# ragdoll every kind once and stand them back up
	for u in b.units.duplicate():
		u.knock_down(Vector3(0, 4, 2))
	await sim(0.5)
	check(b.ragdolls.size() == i, "every kind turns into a ragdoll (%d)" % b.ragdolls.size())
	b.clear_units()
	var s := 0
	for id in B3Defs.STRUCT_ORDER:
		var st = b.spawn_struct(String(id), at(-20 + s * 6.0, 18), 0.3, 6.0)
		check(st != null or id == "crates", "builds a %s" % id)
		s += 1
	check(b.structs.size() == B3Defs.STRUCT_ORDER.size() - 1, "structures are listed (%d)" % b.structs.size())
	check(b.props.size() == 6, "a crate stack makes 6 crates (%d)" % b.props.size())
	var h := 0
	for id in B3Defs.HAZARD_ORDER:
		var d: Dictionary = B3Defs.HAZARDS[id]
		b.spawn_hazard(String(d.kind), at(-24 + h * 15.0, -22), float(d.radius))
		h += 1
	check(b.hazards.size() == 4, "pours every hazard (%d)" % b.hazards.size())
	b.drop("dynamite", at(-20 + 1.8, 18))
	var k := 0
	for id in B3Defs.BOOM_ORDER:
		if id == "nuke":
			continue
		b.drop(String(id), at(-30 + k * 6.0, 2), Vector3.RIGHT)
		k += 1
	await sim(1.0)
	check(b.props.size() >= 6 + 5, "places dynamite, C4, a mine and a barrel")
	check(b.planes.size() == 1, "an airstrike plane flies in")
	b.detonate_c4()
	await sim(7.0)
	check(b.planes.is_empty(), "the plane flies away")
	check(b.proj_root.get_child_count() == 0, "every dropped bomb, shell and grenade has gone off (%d left)" % b.proj_root.get_child_count())
	var fire := 0
	var acid := 0
	for hz in b.hazards:
		if hz.kind == "fire":
			fire += 1
		if hz.kind == "acid" and hz.life > 0.0:
			acid += 1
	check(fire == 1, "napalm leaves a fire patch")
	check(acid == 1, "an acid bomb leaves an acid puddle")
	check(b.chunks.size() > 0, "the blasts broke something into flying chunks (%d)" % b.chunks.size())


func _nothing() -> void:
	await fresh()
	await sim(0.5)


func _maps() -> void:
	print("maps")
	for id in B3Defs.MAP_ORDER:
		await fresh(String(id))
		var u = b.spawn_unit("soldier", "red", at(0, 0))
		await sim(0.5)
		var gy: float = b.world.height_at(u.position.x, u.position.z)
		check(absf(u.position.y - gy) < 0.5, "%s: a soldier stands on the ground (y %.2f vs %.2f)" % [id, u.position.y, gy])
	check(b.map_id == "volcano" and b.hazards.size() >= 3, "the volcano has its own lava and acid pools (%d)" % b.hazards.size())


# ------------------------------------------------------------------ fight
func _small_fight() -> void:
	print("fight")
	await fresh()
	for i in 4:
		b.spawn_unit("soldier", "red", at(-12, -4 + i * 2.5))
		b.spawn_unit("knight", "red", at(-9, -3 + i * 2.0))
	for i in 3:
		b.spawn_unit("soldier", "blue", at(12, -3 + i * 3.0))
	b.spawn_unit("stick", "blue", at(9, 0))
	b.spawn_unit("archer", "blue", at(14, 2))
	b.set_fighting(true)
	var t := 0.0
	while b.winner == "" and t < 90.0:
		await sim(1.0)
		t += 1.0
	check(b.winner == "red" or b.winner == "blue", "red vs blue ends with a winner (%s after %ds)" % [b.winner, int(t)])
	var cheering := 0
	for u in b.units:
		if u.cheer:
			cheering += 1
	check(cheering > 0 and cheering == b.units.size(), "the winners cheer (%d)" % cheering)
	check(b.kos > 0, "fighters were knocked out (%d)" % b.kos)


func _blast_ragdolls() -> void:
	print("explosions")
	await fresh()
	var us := []
	var start := {}
	for i in 6:
		var a := TAU * i / 6.0
		var u = b.spawn_unit("soldier", "red", at(cos(a) * 2.0, sin(a) * 2.0))
		us.append(u)
		start[u] = u.position
	await sim(0.3)
	b.explode(at(0, 0) + Vector3(0, 0.3, 0), 6.0, 18.0, 30.0)
	await sim(0.1)
	var down := 0
	for u in us:
		if is_instance_valid(u) and u.down:
			down += 1
	check(down == 6, "a blast knocks everyone nearby into ragdolls (%d / 6)" % down)
	var maxh := 0.0
	for i in 40:
		await sim(0.025)
		for rd in b.ragdolls:
			maxh = maxf(maxh, rd.center().y - b.world.height_at(rd.center().x, rd.center().z))
	await sim(1.0)
	var far := 0
	for rd in b.ragdolls:
		var c: Vector3 = rd.center()
		if Vector2(c.x, c.z).length() > 5.0:
			far += 1
	check(far >= 5, "they fly far away (%d of 6 landed more than 5 m out)" % far)
	check(maxh > 2.0, "and high into the air (%.1f m)" % maxh)
	# a weak pop only pushes
	var g = b.spawn_unit("giant", "blue", at(20, 0))
	await sim(0.3)
	b.explode(at(22.5, 0), 3.0, 6.0, 10.0)
	await sim(0.2)
	check(not g.down and g.hp > 0.0, "a small pop doesn't knock a giant over")


func _get_up() -> void:
	print("get up")
	await fresh()
	var k = b.spawn_unit("knight", "red", at(0, 0))
	await sim(0.3)
	k.knock_down(Vector3(2, 7, 1))
	check(k.down and k.ragdoll != null, "a knocked knight is a ragdoll")
	await sim(0.4)
	var flew: bool = k.ragdoll != null and k.ragdoll.center().y > b.world.height_at(k.position.x, k.position.z) + 0.8
	check(flew, "it flies up")
	var t := 0.0
	while is_instance_valid(k) and k.down and t < 12.0:
		await sim(0.5)
		t += 0.5
	check(is_instance_valid(k) and not k.down and not k.dead, "it gets back up after %.1fs" % t)
	if is_instance_valid(k):
		check(k.rig != null and k.collision_layer == B3Defs.L_UNIT, "and is a normal fighter again")
		check(b.ragdolls.is_empty(), "its ragdoll is cleaned up")
		await sim(1.0)
		var gy: float = b.world.height_at(k.position.x, k.position.z)
		check(absf(k.position.y - gy) < 0.6, "standing on the ground")


func _chain_and_c4() -> void:
	print("chain reactions")
	await fresh()
	for i in 5:
		b.spawn_prop("xbarrel", at(-6 + i * 2.6, 0))
	await sim(0.5)
	b.explode(at(-7.2, 0), 4.0, 8.0, 60.0)
	await sim(4.0)
	var left := 0
	for p in b.props:
		if p.kind == "xbarrel":
			left += 1
	check(left == 0, "boom barrels set each other off (%d left)" % left)
	for i in 3:
		b.drop("c4", at(10 + i * 3.0, 6))
	await sim(0.3)
	check(b.c4_count() == 3, "C4 waits to be detonated (%d)" % b.c4_count())
	b.detonate_c4()
	await sim(2.0)
	check(b.c4_count() == 0 and b.props.is_empty(), "Detonate sets off all the C4")


func _mine_and_walls() -> void:
	print("mines and buildings")
	await fresh()
	b.drop("mine", at(0, 0))
	var u = b.spawn_unit("stick", "red", at(-6, 0), "attack")
	b.spawn_unit("knight", "blue", at(8, 0), "defend")
	await sim(1.2)
	b.set_fighting(true)
	var t := 0.0
	while b.props.size() > 0 and t < 10.0:
		await sim(0.25)
		t += 0.25
	check(b.props.is_empty(), "a landmine goes off when someone walks over it")
	check(not is_instance_valid(u) or u.down or u.dead, "and launches them")
	await fresh()
	var w = b.spawn_struct("wall", at(0, 0), 0.0, 8.0)
	var n0: int = w.pieces.size()
	await sim(0.3)
	b.explode(at(0, 1.5) + Vector3(0, 0.6, 0), 6.0, 19.0, 90.0)
	await sim(0.5)
	var n1: int = w.pieces.size() if is_instance_valid(w) else 0
	check(n1 < n0, "a big blast breaks a wall (%d -> %d pieces)" % [n0, n1])
	check(b.chunks.size() >= 4, "into flying chunks (%d)" % b.chunks.size())
	var t2 = b.spawn_struct("tower", at(15, 0), 0.0)
	await sim(0.3)
	var top: float = b.surface_y(Vector3(15, 30, 0))
	var a = b.spawn_unit("archer", "blue", Vector3(15, top, 0), "defend")
	b.spawn_unit("stick", "red", at(30, 0), "peaceful")
	await sim(3.0)
	check(a.position.y > 4.0 and not a.down, "an archer stands on a tower (y %.1f)" % a.position.y)
	b.explode(at(15, 1.6) + Vector3(0, 1.0, 0), 5.0, 19.0, 200.0)
	await sim(1.5)
	check(not is_instance_valid(t2) or t2.pieces.size() < 9, "a tower can be blown apart")


func _lava_acid() -> void:
	print("lava and acid")
	await fresh()
	b.spawn_hazard("lava", at(0, 0), 7.0)
	b.spawn_hazard("acid", at(0, 20), 7.0)
	b.spawn_struct("block", at(0, 0), 0.0)
	b.spawn_struct("block", at(0, 20), 0.0)
	await sim(0.2)
	var blue1 = b.spawn_unit("knight", "blue", Vector3(0, b.surface_y(Vector3(0, 20, 0)), 0), "defend")
	var blue2 = b.spawn_unit("knight", "blue", Vector3(0, b.surface_y(Vector3(0, 20, 20)), 20), "defend")
	blue1.hp = 99999.0
	blue2.hp = 99999.0
	blue1.max_hp = 99999.0
	blue2.max_hp = 99999.0
	var reds := []
	for i in 3:
		reds.append(b.spawn_unit("stick", "red", at(-10, -1.5 + i * 1.5), "berserk"))
		reds.append(b.spawn_unit("stick", "red", at(-10, 18.5 + i * 1.5), "berserk"))
	b.set_fighting(true)
	var t := 0.0
	var gone := 0
	while t < 20.0:
		await sim(0.5)
		t += 0.5
		gone = 0
		for r in reds:
			if not is_instance_valid(r) or r.dead:
				gone += 1
		if gone == reds.size():
			break
	check(gone == reds.size(), "fighters who charge into lava or acid get KO'd (%d / %d after %.1fs)" % [gone, reds.size(), t])
	await sim(3.5)
	var in_pool := 0
	for rd in b.ragdolls:
		if b.hazard_at(rd.center(), 0.0) != null:
			in_pool += 1
	check(in_pool == 0, "their ragdolls sink away (%d left in the pools)" % in_pool)
	# sensible fighters walk around a pool
	await fresh()
	b.spawn_hazard("lava", at(0, 0), 4.0)
	var s = b.spawn_unit("soldier", "red", at(-10, 0), "attack")
	b.spawn_unit("knight", "blue", at(10, 0), "defend")
	b.set_fighting(true)
	var burned := false
	for i in 30:
		await sim(0.25)
		if is_instance_valid(s) and not s.dead and b.hazard_at(s.position, 0.0) != null:
			burned = true
	check(not burned, "an attacker walks around the lava instead of through it")
	# crates and barrels sink too
	await fresh()
	b.spawn_hazard("acid", at(0, 0), 4.0)
	var c = b.spawn_prop("crate", at(0, 0) + Vector3(0, 2, 0))
	await sim(3.5)
	check(not is_instance_valid(c), "a crate dropped in acid fizzles away")


func _personalities() -> void:
	print("personalities")
	# defenders stay home, engage close enemies, then return
	await fresh()
	var defs := []
	for i in 3:
		defs.append(b.spawn_unit("knight", "blue", at(12, -3 + i * 3.0), "defend"))
	b.spawn_unit("soldier", "red", at(-22, 0), "defend")
	b.set_fighting(true)
	await sim(6.0)
	var max_off := 0.0
	for d in defs:
		max_off = maxf(max_off, Vector2(d.position.x - d.home.x, d.position.z - d.home.z).length())
	check(max_off < 2.5, "defenders guard their spot while enemies are far (moved %.1f m)" % max_off)
	var intruder = b.spawn_unit("stick", "red", at(5, 0), "attack")
	intruder.hp = 400.0
	intruder.max_hp = 400.0
	var engaged := false
	for i in 24:
		await sim(0.25)
		for d in defs:
			if d.target == intruder:
				engaged = true
	check(engaged, "they fight an enemy who comes close")
	if is_instance_valid(intruder) and not intruder.dead:
		b.remove_unit(intruder, false)
	await sim(8.0)
	max_off = 0.0
	for d in defs:
		if is_instance_valid(d) and not d.down:
			max_off = maxf(max_off, Vector2(d.position.x - d.home.x, d.position.z - d.home.z).length())
	check(max_off < 2.5, "and go back to their spot afterwards (%.1f m away)" % max_off)

	# cowards run away when hurt
	await fresh()
	var cw = b.spawn_unit("soldier", "blue", at(4, 0), "coward")
	cw.hp = cw.max_hp * 0.3
	for i in 3:
		b.spawn_unit("knight", "red", at(-6, -2 + i * 2.0), "attack")
	b.set_fighting(true)
	await sim(0.8)
	var d0: float = cw.position.x
	await sim(3.0)
	check(is_instance_valid(cw) and cw.fleeing, "a hurt coward panics")
	check(is_instance_valid(cw) and cw.position.x > d0 + 4.0, "and runs away from the attackers (%.1f m)" % ((cw.position.x - d0) if is_instance_valid(cw) else 0.0))

	# peaceful fighters never attack
	await fresh()
	var ps := []
	for i in 4:
		ps.append(b.spawn_unit("soldier", "red", at(-1.5, -3 + i * 2.0), "peaceful"))
		ps.append(b.spawn_unit("viking", "blue", at(1.5, -3 + i * 2.0), "peaceful"))
	b.set_fighting(true)
	await sim(8.0)
	var hurt := 0
	for p in ps:
		if not is_instance_valid(p) or p.hp < p.max_hp:
			hurt += 1
	check(hurt == 0 and b.kos == 0, "peaceful fighters never attack (%d hurt)" % hurt)
	var moved := 0
	for p in ps:
		if is_instance_valid(p) and p.position.distance_to(p.home) > 0.8:
			moved += 1
	check(moved >= 3, "they wander about (%d moved)" % moved)

	# ranged keep their distance, attackers close in, berserkers charge into melee
	await fresh()
	var rg = b.spawn_unit("soldier", "red", at(-25, 0), "ranged")
	var at_ = b.spawn_unit("knight", "red", at(-25, 8), "attack")
	var bz = b.spawn_unit("rocketeer", "red", at(-25, -8), "berserk")
	var tg = b.spawn_unit("elephant", "blue", at(12, 0), "defend")
	tg.hp = 1e6
	tg.max_hp = 1e6
	b.set_fighting(true)
	var closest_b := 999.0
	for i in 40:
		await sim(0.25)
		if is_instance_valid(bz) and not bz.down:
			closest_b = minf(closest_b, Vector2(bz.position.x - tg.position.x, bz.position.z - tg.position.z).length())
	var dr := Vector2(rg.position.x - tg.position.x, rg.position.z - tg.position.z).length()
	var da := Vector2(at_.position.x - tg.position.x, at_.position.z - tg.position.z).length() if is_instance_valid(at_) else 0.0
	check(dr > 9.0 and dr < 23.0, "a ranged soldier shoots from a distance (%.1f m)" % dr)
	check(da < 5.0, "an attacker walks right up to its enemy (%.1f m)" % da)
	check(closest_b < 4.5, "a berserk rocketeer charges into melee (%.1f m)" % closest_b)
	check(tg.hp < tg.max_hp, "and they all hit it")


func _nuke() -> void:
	print("nuke")
	await fresh("desert")
	var n := 0
	for i in 36:
		var a := TAU * i / 36.0
		var r := 4.0 + (i % 4) * 5.0
		b.spawn_unit("soldier" if i % 3 != 0 else "knight", "red" if i % 2 == 0 else "blue", at(cos(a) * r, sin(a) * r))
		n += 1
	b.spawn_struct("bunker", at(10, 10), 0.0)
	b.spawn_struct("tower", at(-12, 6), 0.0)
	await sim(0.5)
	b.drop("nuke", at(0, 0))
	await sim(2.6)
	check(b.kos >= 30, "the nuke knocks out the army (%d / %d)" % [b.kos, n])
	await sim(3.0)
	var standing := 0
	for u in b.units:
		if not u.down and Vector2(u.position.x, u.position.z).length() < 25.0:
			standing += 1
	check(standing == 0, "nothing is left standing near ground zero (%d)" % standing)
	check(b.structs.is_empty() or b.chunks.size() > 10, "buildings are blown apart (%d chunks)" % b.chunks.size())
	var far := 0
	for rd in b.ragdolls:
		var c: Vector3 = rd.center()
		if Vector2(c.x, c.z).length() > 25.0:
			far += 1
	check(far + (n - b.ragdolls.size()) >= 10, "ragdolls were thrown far (%d past 25 m, %d gone off the map)" % [far, n - b.ragdolls.size()])


func _scenarios() -> void:
	print("scenarios")
	for sc in ["skirmish", "dinos", "hazards", "structures", "animals", "chaos", "c4", "nuke"]:
		await fresh("", sc)
		var n0: int = b.units.size()
		await sim(6.0)
		check(n0 > 0 and b.fighting, "%s starts a fight (%d fighters, %d KO'd after 6s)" % [sc, n0, b.kos])


func _ui_smoke() -> void:
	print("ui")
	await fresh("", "", true)
	check(b.ui != null and b.tools != null, "the HUD and tools load")
	for c in B3Defs.CATS:
		b.ui.set_cat(String(c.id))
	b.tools.choose("knight")
	b.tools._place(at(-5, -3), at(-5, 5), true, false)
	check(b.units.size() >= 4, "dragging places a line of knights (%d)" % b.units.size())
	b.tools.choose("wall")
	b.tools._place(at(5, -3), at(5, 5), true, false)
	check(b.structs.size() == 1, "dragging builds a wall")
	b.tools.choose("lava")
	b.tools._place(at(15, 0), at(19, 0), true, false)
	check(b.hazards.size() == 1 and absf(b.hazards[0].radius - 4.0) < 0.1, "dragging pours a bigger pool")
	b.tools.select(b.units[0])
	check(b.ui.inspect.visible, "selecting a fighter shows its card")
	b.units[0].set_team("green")
	b.units[0].set_personality("coward")
	check(b.units[0].team == "green" and b.units[0].pers == "coward", "its team and mood can be changed")
	b.toggle_play()
	check(b.fighting, "Fight! starts the battle")
	b.set_paused(true)
	check(Engine.time_scale == 0.0, "pause freezes time")
	b.set_paused(false)
	b.set_slowmo(true)
	check(Engine.time_scale < 0.5, "slow motion")
	b.set_slowmo(false)
	Engine.time_scale = SPEED
	b.ui.toggle_palette()
	check(not b.ui.palette.visible, "Tab hides the Toy Box")
	b.ui.toggle_palette()
	check(b.ui.palette.visible, "and brings it back")
	b.ui.toggle_help()
	b.ui.close_top()
	b.load_map("snow")
	check(b.units.is_empty() and b.map_id == "snow", "picking a map clears the field")
	await sim(0.5)


func _performance() -> void:
	print("performance")
	await fresh("", "big")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var n: int = b.units.size()
	await sim(1.0)
	var t0 := Time.get_ticks_usec()
	var s0: float = b.time
	await sim(4.0)
	var real := (Time.get_ticks_usec() - t0) / 1000000.0
	var ratio: float = (b.time - s0) / maxf(real, 0.001)
	print("        %d fighters: %.2fx real time (%.1fs of battle in %.1fs)" % [n, ratio, b.time - s0, real])
	check(n >= 150 and ratio > 0.8, "%d fighters run at full speed" % n)
	Engine.time_scale = SPEED


# ------------------------------------------- new fighters and vehicles
const NEW_KINDS := ["wizard", "robot", "gorilla", "mammoth", "dragon", "tank", "jeep", "cannon", "mgnest"]


func _new_kinds_everywhere() -> void:
	print("new fighters and vehicles")
	for map in B3Defs.MAP_ORDER:
		await fresh(String(map))
		var us := []
		for i in NEW_KINDS.size():
			var u = b.spawn_unit(String(NEW_KINDS[i]), B3Defs.TEAM_ORDER[i % 5], at(-20.0 + i * 5.0, -6.0 + (i % 2) * 3.0))
			us.append(u)
		await sim(1.5)
		var ok := 0
		for u in us:
			if not is_instance_valid(u) or u.dead or u.down:
				continue
			var gy: float = b.world.height_at(u.position.x, u.position.z)
			var upright: bool = not (u is B3Vehicle) or u.global_basis.y.dot(Vector3.UP) > 0.9
			if upright and (u.flying or absf(u.position.y - gy) < 0.6):
				ok += 1
		check(ok == NEW_KINDS.size(), "%s: every new fighter and vehicle spawns and stands (%d / %d)" % [map, ok, NEW_KINDS.size()])
	check(B3Defs.UNIT_ORDER.vehicles.size() >= 4 and B3Defs.item_cat("tank") == "vehicles", "the vehicles have their own palette tab")
	var vs := 0
	for k in B3Defs.UNIT_ORDER.vehicles:
		var u = b.spawn_unit(String(k), "red", at(0, 0))
		if u is B3Vehicle:
			vs += 1
	check(vs == B3Defs.UNIT_ORDER.vehicles.size(), "vehicles spawn as B3Vehicles (%d)" % vs)
	for sc in ["vehicles", "monsters"]:
		await fresh("", sc)
		var n0: int = b.units.size()
		await sim(8.0)
		var hurt := 0
		for u in b.units:
			if u.hp < u.max_hp:
				hurt += 1
		check(n0 > 0 and b.fighting and (b.kos > 0 or hurt > 0), "the %s scenario starts a fight (%d fighters, %d hurt, %d KO'd after 8s)" % [sc, n0, hurt, b.kos])
	for sc in ["showcase", "garage", "firebreath", "lineup"]:
		await fresh("", sc)
		await sim(2.0)
		check(b.units.size() > 0, "the %s scenario sets up (%d)" % [sc, b.units.size()])


func _new_kinds_fight() -> void:
	for k in NEW_KINDS:
		await fresh()
		var n := 2 if k == "wizard" else 1
		for i in n:
			b.spawn_unit(String(k), "red", at(-14, -1.5 + i * 3.0))
		for i in 3:
			b.spawn_unit("soldier", "blue", at(14, -3 + i * 3.0))
		b.spawn_unit("knight", "blue", at(12, 0))
		await sim(0.5)
		b.set_fighting(true)
		var t := 0.0
		while b.winner == "" and t < 120.0:
			await sim(1.0)
			t += 1.0
		check(b.winner != "" and b.kos > 0, "a %s fights an army to a result (%s after %ds, %d KOs)" % [k, b.winner, int(t), b.kos])


func _vehicle_blasts() -> void:
	print("vehicles and blasts")
	await fresh()
	var vs := []
	var kinds := ["tank", "jeep", "cannon", "mgnest"]
	var start := {}
	for i in 4:
		var a := TAU * i / 4.0
		var v = b.spawn_unit(kinds[i], "red", at(cos(a) * 3.5, sin(a) * 3.5))
		vs.append(v)
	await sim(0.5)
	for v in vs:
		start[v] = v.position
	b.explode(at(0, 0) + Vector3(0, 0.3, 0), 6.0, 19.0, 60.0)
	var high := {}
	var minup := {}
	for i in 60:
		await sim(0.05)
		for v in vs:
			if is_instance_valid(v) and not v.dead:
				high[v] = maxf(float(high.get(v, 0.0)), v.position.y - b.world.height_at(v.position.x, v.position.z))
				minup[v] = minf(float(minup.get(v, 1.0)), v.global_basis.y.dot(Vector3.UP))
	var jeep = vs[1]
	check(float(high.get(jeep, 0.0)) > 1.0 and float(minup.get(jeep, 1.0)) < 0.5, "a big blast flings a jeep and flips it (%.1f m up)" % float(high.get(jeep, 0.0)))
	var moved := 0
	for v in vs:
		if is_instance_valid(v) and (v.position.distance_to(start[v]) > 0.3 or float(minup.get(v, 1.0)) < 0.9):
			moved += 1
	check(moved == 4, "it pushes every vehicle around (%d / 4)" % moved)
	await sim(7.0)
	var upright := 0
	for v in vs:
		if is_instance_valid(v) and not v.dead and not v.tumbling and v.global_basis.y.dot(Vector3.UP) > 0.95:
			upright += 1
	check(upright == 4, "and they hop back onto their wheels (%d / 4)" % upright)
	var tk = vs[0]
	b.explode(tk.position + Vector3(1.6, 0.4, 0), 6.0, 19.0, 10.0)
	var flipped := false
	for i in 30:
		await sim(0.05)
		if is_instance_valid(tk) and tk.tumbling:
			flipped = true
	check(flipped, "a big boom right next to a tank tips it over")
	# the nuke throws vehicles around (or blows them up)
	await fresh("desert")
	var far := []
	for i in 8:
		var a := TAU * i / 8.0
		far.append(b.spawn_unit(kinds[i % 4], "blue", at(cos(a) * 20.0, sin(a) * 20.0)))
	await sim(0.5)
	var p0 := {}
	for v in far:
		p0[v] = v.position
	var c0: int = b.chunks.size()
	b.drop("nuke", at(0, 0))
	var thrown := 0
	var seen := {}
	for i in 60:
		await sim(0.1)
		for v in far:
			if seen.has(v):
				continue
			if not is_instance_valid(v) or v.dead or v.tumbling or v.position.distance_to(p0[v]) > 4.0:
				seen[v] = true
				thrown += 1
	check(thrown == far.size(), "the nuke flings or wrecks every vehicle (%d / %d)" % [thrown, far.size()])
	check(b.chunks.size() > c0, "and blows some into pieces (%d chunks)" % (b.chunks.size() - c0))


func _vehicle_wrecks() -> void:
	await fresh()
	var t = b.spawn_unit("tank", "red", at(-6, 0))
	var j = b.spawn_unit("jeep", "red", at(6, 0))
	var bystander = b.spawn_unit("soldier", "blue", at(-6, 4))
	await sim(0.5)
	var c0: int = b.chunks.size()
	t.hp = 5.0
	j.hp = 5.0
	b.explode(at(-6, 2.6) + Vector3(0, 0.5, 0), 2.5, 6.0, 30.0)
	b.explode(at(6, 2.6) + Vector3(0, 0.5, 0), 2.5, 6.0, 30.0)
	await sim(0.05)
	check((not is_instance_valid(t) or t.dead) and (not is_instance_valid(j) or j.dead) and b.kos >= 2, "destroyed vehicles are knocked out (%d KOs)" % b.kos)
	check(b.chunks.size() - c0 >= 8, "a tank and a jeep break into flying pieces (%d)" % (b.chunks.size() - c0))
	check(b.ragdolls.is_empty() or (is_instance_valid(bystander) and bystander.down), "instead of turning into ragdolls")
	var top := 0.0
	for i in 20:
		await sim(0.05)
		for c in b.chunks:
			if is_instance_valid(c):
				top = maxf(top, c.global_position.y - b.world.height_at(c.global_position.x, c.global_position.z))
	check(top > 2.0, "the pieces fly up in a big blast (%.1f m)" % top)
	check(not is_instance_valid(bystander) or bystander.hp < bystander.max_hp, "the wreck's blast hurts whoever is close")
	await sim(4.0)
	var left := 0
	for c in b.chunks:
		if is_instance_valid(c):
			left += 1
	check(left >= 8, "the wrecks stay on the field as rubble (%d)" % left)


func _fire_breathers() -> void:
	print("fire")
	await fresh()
	var d = b.spawn_unit("dragon", "red", at(-10, 0))
	var vics := []
	for i in 4:
		vics.append(b.spawn_unit("soldier", "blue", at(4, -3 + i * 2.0), "peaceful"))
	b.set_fighting(true)
	var burned := false
	var fires := 0
	for i in 60:
		await sim(0.25)
		for v in vics:
			if is_instance_valid(v) and v.burn_t > 0.0:
				burned = true
		for h in b.hazards:
			if h.kind == "fire":
				fires = maxi(fires, 1)
	var hurt := 0
	for v in vics:
		if not is_instance_valid(v) or v.dead or v.hp < v.max_hp:
			hurt += 1
	check(is_instance_valid(d) and d.flying and hurt >= 2, "a dragon's fire breath hurts fighters (%d / 4)" % hurt)
	check(burned, "and sets them burning")
	check(fires > 0, "and lights the ground on fire")
	# a wizard's fireball
	await fresh()
	var stick = b.spawn_unit("stick", "blue", at(0, 1.0), "peaceful")
	await sim(0.3)
	var from: Vector3 = stick.position + Vector3(-5, 2.5, 0)
	var fb = b.spawn_proj("fireball", from, (stick.position + Vector3(0, 0.6, 0) - from).normalized() * 15.0, null, B3Defs.weapon("fireball"))
	await sim(1.0)
	var fire_n := 0
	for h in b.hazards:
		if h.kind == "fire":
			fire_n += 1
	check(not is_instance_valid(fb), "a fireball explodes when it hits")
	check(not is_instance_valid(stick) or stick.hp < stick.max_hp, "and burns whoever is near")
	check(fire_n == 1, "and leaves a little patch of fire (%d)" % fire_n)
	await fresh()
	var wz = b.spawn_unit("wizard", "red", at(-8, 0))
	var kn = b.spawn_unit("knight", "blue", at(8, 0), "defend")
	b.set_fighting(true)
	var casts := 0
	for i in 40:
		await sim(0.25)
		if is_instance_valid(wz) and wz.act == "cast":
			casts += 1
	check(casts > 0 and (not is_instance_valid(kn) or kn.hp < kn.max_hp), "a wizard casts fireballs at enemies")


func _gorilla_and_robot() -> void:
	await fresh()
	var g = b.spawn_unit("gorilla", "red", at(-4, 0))
	for i in 4:
		b.spawn_unit("stick", "blue", at(-1.5, -1.5 + i * 1.0), "attack")
	b.spawn_unit("soldier", "blue", at(12, 0), "defend")
	b.set_fighting(true)
	var acts := {}
	var rocks := 0
	for i in 120:
		await sim(0.1)
		if is_instance_valid(g) and g.act != "":
			acts[g.act] = true
		for p in b.proj_root.get_children():
			if p is B3Proj and p.kind == "boulder" and not p.has_meta("counted"):
				p.set_meta("counted", true)
				rocks += 1
	check(acts.has("pound"), "a gorilla ground-pounds a crowd")
	check(acts.has("attack"), "and punches")
	check(rocks > 0, "and throws boulders at far-away enemies (%d)" % rocks)
	await fresh()
	var r = b.spawn_unit("robot", "red", at(-8, 0))
	var s = b.spawn_unit("soldier", "blue", at(8, 0), "peaceful")
	b.set_fighting(true)
	var shot := false
	for i in 40:
		await sim(0.25)
		if not is_instance_valid(s) or s.hp < s.max_hp:
			shot = true
			break
	check(shot, "a robot's laser hits")
	r.hurt(9999.0, Vector3.UP, 10.0, null, "blast")
	await sim(0.3)
	var joints := 0
	for rd in b.ragdolls:
		if rd.kind == "robot":
			for c in rd.get_children():
				if c is Joint3D and not c.is_queued_for_deletion():
					joints += 1
	check(b.kos >= 1 and joints == 0, "a knocked-out robot falls apart (%d joints left)" % joints)


func _vehicle_palette() -> void:
	await fresh("", "", true)
	b.ui.set_cat("vehicles")
	check(b.ui.item_btns.size() == B3Defs.UNIT_ORDER.vehicles.size() and b.ui.team_box.visible, "the Vehicles tab lists every vehicle with team colours (%d)" % b.ui.item_btns.size())
	b.tools.choose("tank")
	check(b.tools.team != "wild", "vehicles start on a real team (%s)" % b.tools.team)
	b.tools._place(at(-6, 0), at(-6, 0), false, false)
	b.tools.choose("jeep")
	b.tools.set_team("blue")
	b.tools._place(at(6, -4), at(6, 4), true, false)
	var tanks := 0
	var jeeps := 0
	for u in b.units:
		if u.kind == "tank" and u.team == "red":
			tanks += 1
		if u.kind == "jeep" and u.team == "blue":
			jeeps += 1
	check(tanks == 1 and jeeps >= 2, "placing a tank and dragging a line of jeeps (%d, %d)" % [tanks, jeeps])
	var counts: Dictionary = b.team_counts()
	check(int(counts.get("red", 0)) == 1 and int(counts.get("blue", 0)) == jeeps, "vehicles show up in the team counts")
	await sim(1.5)
	var stacked := 0
	for u in b.units:
		if u is B3Vehicle and u.global_basis.y.dot(Vector3.UP) < 0.9:
			stacked += 1
	check(stacked == 0, "a dragged line of jeeps doesn't pile up")
	var tk: B3Unit = null
	for u in b.units:
		if u.kind == "tank":
			tk = u
	b.tools.select(tk)
	check(b.ui.inspect.visible, "selecting a tank shows its card")
	tk.set_team("green")
	check(tk.team == "green" and tk.rig != null, "and it can change team")
	b.remove_unit(tk)
	check(b.team_counts().get("green", 0) == 0, "and be erased")

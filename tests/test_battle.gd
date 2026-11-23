extends TestBase
## Headless checks for 3D Battle (battle3d/): everything spawns, fights end,
## blasts launch ragdolls, knocked-down fighters get back up, nukes clear the
## field, lava and acid KO, and each personality behaves.
## godot --headless --path . -- --test=battle

const SPEED := 4.0          # run the sim 4x faster than real time (dt stays 1/60)


func fresh(map := "grassland", scenario := "", ui := false) -> void:
	await drop_battle()
	start_battle(1234, {"seed": 4321, "no_ui": not ui, "map": map, "scenario": scenario})


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
		finish()
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
	await _no_air_jumps()
	await _melee_reach()
	await _hazard_damage()
	await _shots_past_friends()
	await _proj_gravity()
	await _fx_pool()
	await _model_bits()
	await _ui_smoke()
	await _tactics()
	await _wood_fire()
	await _fighters_map()
	await _performance()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	print("test_battle: done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	finish()


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
	# (one knocked out by the heat gets thrown up first, lands, then sinks)
	var in_pool := 99
	var waited := 0.0
	while in_pool > 0 and waited < 6.0:
		await sim(0.5)
		waited += 0.5
		in_pool = 0
		for rd in b.ragdolls:
			if b.hazard_at(rd.center(), 0.0) != null:
				in_pool += 1
	check(in_pool == 0, "their ragdolls sink away (%d left in the pools after %.1fs)" % [in_pool, waited])
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


# ------------------------------------------------- fixes from a code review


## A fighter jumps off solid ground only: not again at the top of a jump
## (that gave endless jumps, worst in Moon gravity), but yes off a tower.
func _no_air_jumps() -> void:
	print("jumping")
	for g in ["normal", "moon"]:
		await fresh()
		rule("gravity", g)
		var s: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
		await sim(0.6)
		check(s._grounded, "%s gravity: a soldier on the ground can jump" % g)
		B3Player.start(s)
		var c := B3Player.me
		c.jump = true
		await sim(0.1)
		var up := s.linear_velocity.y
		var top := false
		for i in 300:
			await get_tree().physics_frame
			if s.linear_velocity.y < 0.5:
				top = true
				break
		var high: float = s.position.y - b.world.height_at(s.position.x, s.position.z)
		var air := not s._grounded
		c.jump = true
		for i in 3:
			await get_tree().physics_frame
		check(up > 4.0 and top and high > 0.5 and air, "%s gravity: at the top of a jump it's in the air (%.1f m up)" % [g, high])
		check(s.linear_velocity.y < 1.0, "%s gravity: pressing jump again up there does nothing (%.1f m/s up)" % [g, s.linear_velocity.y])
		B3Player.stop()
	rule("gravity", "normal")
	# standing on a tower still counts as standing
	await fresh()
	b.spawn_struct("tower", at(0, 0), 0.0)
	await sim(0.3)
	var top_y: float = b.surface_y(Vector3(0, 30, 0))
	var a: B3Unit = b.spawn_unit("archer", "blue", Vector3(0, top_y, 0), "defend")
	await sim(1.5)
	check(a.position.y > 4.0 and a._grounded, "an archer on top of a tower is standing on something (y %.1f)" % a.position.y)
	B3Player.start(a)
	B3Player.me.jump = true
	await sim(0.1)
	check(a.linear_velocity.y > 3.0, "and can jump off it")
	B3Player.stop()
	# a jeep up in the air can't drive or steer there
	var j: B3Vehicle = b.spawn_unit("jeep", "red", at(14, 0)) as B3Vehicle
	await sim(0.5)
	var on_ground := j._grounded
	j.global_position = at(14, 0) + Vector3(0, 3.0, 0)
	j.linear_velocity = Vector3.ZERO
	j._drive(1.0 / 60.0)
	check(on_ground and not j._grounded, "a jeep hanging still in mid-air isn't on the ground")


## Melee only reaches things level with you, and a big slam never heals.
func _melee_reach() -> void:
	print("melee reach")
	await fresh()
	# a tiny giant's hammer slam with a big parked plane right at its edge,
	# and a pterodactyl flying over the middle of it
	var g: B3Unit = b.spawn_unit("giant", "red", at(0, 0), "peaceful", 0.0, 0.5)
	var tk: B3Unit = b.spawn_unit("plane", "blue", at(0, 12), "peaceful", 0.0)
	(tk as B3Aircraft).parked = true
	var bird: B3Unit = b.spawn_unit("ptero", "blue", at(-6, 4), "peaceful")
	var foot: B3Unit = b.spawn_unit("stick", "blue", at(6, 4), "peaceful")
	await sim(1.0)
	var w: Dictionary = B3Defs.weapon("hammer")
	var r: float = float(w.aoe) * g.size
	var c: Vector3 = g.position + g.forward() * (float(w.range) * g.size * 0.6 + g.radius)
	tk.global_position = Vector3(c.x, tk.position.y, c.z) + g.forward() * (r + tk.radius * 0.9)
	bird.global_position = Vector3(c.x, bird.position.y, c.z)
	foot.global_position = Vector3(c.x, foot.position.y, c.z) + Vector3(0.3, 0, 0)
	var hp0: float = tk.hp
	g._melee_hit(w)
	check(tk.hp < hp0, "a tiny giant's slam at the edge of a big parked plane hurts it, never heals it (%.0f -> %.0f)" % [hp0, tk.hp])
	check(bird.hp == bird.max_hp and foot.hp < foot.max_hp, "it hits the fighter beside it but not the pterodactyl %.1f m overhead" % (bird.position.y - g.position.y))
	# a knight under a hovering helicopter can't reach it with his sword
	await fresh()
	var h: B3Unit = b.spawn_unit("heli", "blue", at(0, 0), "peaceful")
	var k: B3Unit = b.spawn_unit("knight", "red", at(3, 3), "peaceful")
	var s: B3Unit = b.spawn_unit("soldier", "blue", at(-3, 3), "peaceful")
	await sim(2.5)
	k.global_position = Vector3(h.position.x, k.position.y, h.position.z)
	s.global_position = Vector3(h.position.x + 0.9, s.position.y, h.position.z)
	k.target = h
	var hh: float = h.hp
	k._melee_hit(k.melee)
	check(h.position.y - k.position.y > 5.0 and h.hp == hh, "a knight can't sword a helicopter hovering %.1f m overhead" % (h.position.y - k.position.y))
	k.target = s
	var sh: float = s.hp
	k._melee_hit(k.melee)
	check(s.hp < sh, "but he does hit the soldier next to him")


## Puts `u` in pool `h` for one lava/acid tick and says how much health it lost.
func _dip(u: B3Unit, h: B3Hazard) -> float:
	var back := u.global_position
	u.global_position = h.global_position + Vector3(0, 0.2, 0)
	u._hz_t = 0.0
	var hp0 := u.hp
	u._hazards(0.1)
	var lost := hp0 - u.hp
	u.global_position = back
	u.hp = u.max_hp
	u.burn_t = 0.0
	return lost


## Lava, acid and burning count Toughness, armour and fire resistance like
## any other hit, and dragons don't mind fire.
func _hazard_damage() -> void:
	print("hazard damage")
	await fresh()
	var lava: B3Hazard = b.spawn_hazard("lava", at(0, 0), 3.0)
	var acid: B3Hazard = b.spawn_hazard("acid", at(0, 14), 3.0)
	var s: B3Unit = b.spawn_unit("soldier", "red", at(-10, -8), "peaceful")
	var tk: B3Unit = b.spawn_unit("tank", "red", at(10, -8), "peaceful")
	var d: B3Unit = b.spawn_unit("dragon", "red", at(-10, 10), "peaceful")
	await sim(0.5)
	var ls := _dip(s, lava)
	check(absf(ls - lava.dps * 0.1 * (1.0 - s.armor)) < 0.01, "lava hurts a soldier through its armour (%.2f a tick)" % ls)
	var lt := _dip(tk, lava)
	check(lt > 0.0 and lt < ls * 0.5, "a tank's armour keeps most of the lava's heat out (%.2f a tick)" % lt)
	var ld := _dip(d, lava)
	var ad := _dip(d, acid)
	check(ld == 0.0 and ad > 0.0, "a dragon doesn't mind lava (%.2f), but acid still stings (%.2f)" % [ld, ad])
	rule("health", "super")
	var ls2 := _dip(s, lava)
	check(absf(ls2 - ls / 6.0) < 0.01, "with Super toughness lava does a sixth as much (%.2f)" % ls2)
	# burning, too
	var hp0 := s.hp
	s.burn_t = 0.6
	await sim(0.5)
	var burnt_super := hp0 - s.hp
	rule("health", "normal")
	s.hp = s.max_hp
	s.burn_t = 0.6
	await sim(0.5)
	var burnt := s.max_hp - s.hp
	check(burnt > 1.0 and burnt_super < burnt * 0.3, "and burning does less to tough fighters (%.1f vs %.1f)" % [burnt_super, burnt])


## Bullets fly past friends, like arrows: a gunner doesn't shoot the teammate
## standing in front of it. A rocket whose shooter is knocked out on the way
## still knows its team (for "Blasts hurt teammates: No").
func _shots_past_friends() -> void:
	print("shots past friends")
	await fresh()
	var gun: B3Unit = b.spawn_unit("gunner", "red", at(-6, 0), "peaceful", PI * 0.5)
	var mate: B3Unit = b.spawn_unit("knight", "red", at(-3.5, 0), "peaceful", -PI * 0.5)
	var foe: B3Unit = b.spawn_unit("elephant", "blue", at(3, 0), "peaceful")
	foe.max_hp = 5000.0
	foe.hp = 5000.0
	await sim(0.5)
	gun.target = foe
	for i in 12:
		gun._fire_gun(gun.wpn)
		await get_tree().physics_frame
	check(mate.hp == mate.max_hp and not mate.down, "a gunner's bullets fly past the teammate in front of it")
	check(foe.hp < foe.max_hp, "and hit the enemy behind it (%.0f damage)" % (foe.max_hp - foe.hp))
	# a fast arrow flies past two friends close together in a row (both in
	# one step of its flight), not just the first
	var ar: B3Unit = b.spawn_unit("archer", "red", at(-6, -6), "peaceful", PI * 0.5)
	var row: Array[B3Unit] = []
	for x in [-3.6, -2.6]:
		row.append(b.spawn_unit("knight", "red", at(x, -6), "peaceful", -PI * 0.5))
	var foe2: B3Unit = b.spawn_unit("elephant", "blue", at(3, -6), "peaceful")
	foe2.max_hp = 5000.0
	foe2.hp = 5000.0
	await sim(0.5)
	var from := ar.position + Vector3(0, 1.3, 0)
	b.spawn_proj("arrow", from, B3Proj.lob(from, foe2.center(), 0.08, "arrow"), ar, B3Defs.weapon("bow"))
	await sim(0.8)
	check(row[0].hp == row[0].max_hp and row[1].hp == row[1].max_hp and foe2.hp < foe2.max_hp, "a fast arrow flies past two friends close together and hits the enemy")
	var rk: B3Unit = b.spawn_unit("rocketeer", "red", at(-6, 8), "peaceful")
	await sim(0.3)
	var p: B3Proj = b.spawn_proj("rocket", rk.position + Vector3(0, 3.0, 0), Vector3(0, 0, 0.1), rk, B3Defs.weapon("bazooka"))
	b.remove_unit(rk, false)
	await get_tree().physics_frame
	var o: Dictionary = p._blast_opts() if is_instance_valid(p) else {}
	check(o.get("by") == null and String(o.get("team", "")) == "red", "a rocket still knows its team after its shooter is gone")
	# with "Blasts hurt teammates: No", it lands among the shooter's friends
	rule("friendly", "off")
	var rk2: B3Unit = b.spawn_unit("rocketeer", "red", at(10, 8), "peaceful")
	var mates: Array[B3Unit] = []
	for i in 3:
		mates.append(b.spawn_unit("soldier", "red", at(10 + i * 1.2 - 1.2, 14), "peaceful"))
	await sim(0.4)
	b.spawn_proj("rocket", at(10, 14) + Vector3(0, 3.0, 0), Vector3(0, -12, 0), rk2, B3Defs.weapon("bazooka"))
	b.remove_unit(rk2, false)
	await sim(1.0)
	var hurt := 0
	for m in mates:
		if not is_instance_valid(m) or m.down or m.hp < m.max_hp:
			hurt += 1
	check(hurt == 0, "and spares them with friendly fire off (%d hurt)" % hurt)
	rule("friendly", "on")


## Arrows, grenades and shells fall with the 🌍 Gravity rule, and aiming
## allows for it; a rocketeer's rocket allows for its sag.
func _proj_gravity() -> void:
	print("projectile gravity")
	for g in ["normal", "moon"]:
		await fresh()
		rule("gravity", g)
		var from := at(-10, 0) + Vector3(0, 1.5, 0)
		var to := at(6, 0)
		var p: B3Proj = b.spawn_proj("arrow", from, B3Proj.lob(from, to, 0.9, "arrow"), null, {})
		check(absf(p.g - 9.8 * B3Rules.gravity_k()) < 0.01, "%s gravity: arrows fall at %.1f m/s²" % [g, p.g])
		await sim(1.5)
		var miss: float = p.global_position.distance_to(to) if is_instance_valid(p) else 99.0
		check(is_instance_valid(p) and p.stuck and miss < 0.8, "%s gravity: an arrow lands where it was aimed (%.2f m off)" % [g, miss])
	rule("gravity", "normal")
	await fresh()
	var rk: B3Unit = b.spawn_unit("rocketeer", "red", at(-11, 0), "peaceful", PI * 0.5)
	var tg: B3Unit = b.spawn_unit("elephant", "blue", at(11, 0), "peaceful")
	tg.max_hp = 1e5
	tg.hp = 1e5
	await sim(0.5)
	rk.target = tg
	rk._shoot_proj(rk.wpn)
	var rocket: B3Proj = null
	for c in b.proj_root.get_children():
		if c is B3Proj and (c as B3Proj).kind == "rocket":
			rocket = c
	var last := Vector3(-99, 0, -99)
	for i in 300:
		if not is_instance_valid(rocket):
			break
		last = rocket.global_position
		await get_tree().physics_frame
	var off := Vector2(last.x - tg.position.x, last.z - tg.position.z).length()
	check(off < tg.radius + 1.0, "a rocketeer's rocket reaches its target 22 m away (lands %.1f m from it)" % off)


## A pooled effect node handed to a new effect isn't moved or hidden early
## by the older effect that had it before.
func _fx_pool() -> void:
	print("effect pool")
	await fresh()
	var fx: B3Fx = b.fx
	var n: OmniLight3D = fx._lights[fx._light_i]
	for i in fx._lights.size():
		fx.light(Vector3(i, 2, 0), 5.0, 3.0, 0.3)
	fx.light(Vector3(0, 2, 5), 5.0, 3.0, 3.0)      # the first light again, for longer
	var owners := 0
	for it in fx._items:
		if it.node == n:
			owners += 1
	check(owners == 1, "a reused light is run by one effect at a time (%d)" % owners)
	await sim(1.0)
	check(n.visible and n.light_energy > 0.1 and n.global_position.z > 4.0, "the newer, longer flash is still lit after the old one would have ended")
	await sim(3.0)
	check(not n.visible, "and goes out when it's done")


## Small model fixes: cheering tank crew stay in their hatch, a dragon's
## dangling legs sway out of step, health bars keep their size.
func _model_bits() -> void:
	print("models")
	await fresh()
	var tk: B3Unit = b.spawn_unit("tank", "red", at(0, 0), "peaceful")
	var d: B3Unit = b.spawn_unit("dragon", "red", at(10, 0), "peaceful")
	await sim(0.5)
	var vr := tk.rig as B3VRig
	var seats: Array[float] = []
	for cm in vr.crew:
		seats.append(cm.position.y)
	var bob := 0.0
	for f in 437:
		vr.animate(1.0 / 60.0, 0.0, "", 0.0, false, "cheer")
		for i in vr.crew.size():
			bob = maxf(bob, absf(vr.crew[i].position.y - seats[i]))
	vr.animate(1.0 / 60.0, 0.0, "", 0.0, false, "")
	var back := 0.0
	for i in vr.crew.size():
		back = maxf(back, absf(vr.crew[i].position.y - seats[i]))
	check(seats.size() > 0 and bob > 0.005 and bob < 0.05 and back < 0.0001, "cheering tank crew bob in their hatch and sit back down after (%.3f m, then %.4f m)" % [bob, back])
	var legs: Array[float] = []
	for ln in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
		legs.append((d.rig.pv[ln] as Node3D).rotation.x)
	var spread := legs.max() - legs.min() as float
	check(spread > 0.01, "a dragon's dangling legs don't all swing together (%.3f)" % spread)
	check(B3Mats.HPBAR_SHADER.contains("length(MODEL_MATRIX[0].xyz)") and tk.bar.scale.x > 1.0, "health bars face the camera but keep their size (bigger for big fighters)")


# ------------------------------------------------------------------ tactics
func _wall_hp(w) -> float:
	var t := 0.0
	if is_instance_valid(w):
		for pc in (w as B3Struct).pieces:
			if is_instance_valid(pc):
				t += pc.hp
	return t


func _tactics() -> void:
	print("tactics")
	# 🗼 an archer up on a tower, out of a sword's reach: knights go for
	# someone on the ground first...
	await fresh()
	var tw: B3Struct = b.spawn_struct("tower", at(8, 0), 0.0)
	await sim(0.3)
	var top: float = b.surface_y(Vector3(8, 30, 0))
	var up: B3Unit = b.spawn_unit("archer", "blue", Vector3(8, top, 0), "peaceful")
	var low: B3Unit = b.spawn_unit("stick", "blue", at(22, 0), "peaceful")
	low.speed = 0.0
	var kn: Array[B3Unit] = []
	for z: float in [-1.5, 0.0, 1.5]:
		kn.append(b.spawn_unit("knight", "red", at(0, z), "attack"))
	await sim(0.5)
	b.set_fighting(true)
	await sim(0.8)
	var k0: B3Unit = kn[1]
	check(k0._high_above(up, k0.position) and not k0._high_above(low, k0.position), "🗼 an archer on a tower is out of a knight's reach, a fighter on the ground isn't")
	var on_low := 0
	for k in kn:
		if k.target == low:
			on_low += 1
	check(on_low == 3, "knights go after the fighter on the ground, not the archer they can't reach (%d of 3)" % on_low)
	# ...and with nobody else left, they chop the tower's legs until it comes down
	b.remove_unit(low, false)
	var n0: int = tw.pieces.size()
	var t := 0.0
	var swung_air := 0
	while t < 60.0 and is_instance_valid(up) and not up.down and up.position.y > top - 1.5:
		await sim(0.5)
		t += 0.5
		for k in kn:
			if is_instance_valid(k) and k.act == "attack" and k.act_t < k.act_len * 0.45 and not k._hacking and k.target == up \
					and is_instance_valid(up) and k._high_above(up, k.position):
				swung_air += 1
	var n1: int = tw.pieces.size() if is_instance_valid(tw) else 0
	check(n1 < n0, "🪓 with nobody else left, they chop at the tower's legs (%d → %d pieces in %.0f s)" % [n0, n1, t])
	check(not is_instance_valid(up) or up.down or up.position.y < top - 1.5, "until the archer comes down (%.1f m up)" % (up.position.y - at(8, 0).y if is_instance_valid(up) else 0.0))
	check(swung_air == 0, "and nobody swings at thin air under it (%d)" % swung_air)

	# ⛰️ shooting down from up high reaches further and is steadier
	await fresh()
	var tw2: B3Struct = b.spawn_struct("tower", at(0, 0), 0.0)
	await sim(0.3)
	var top2: float = b.surface_y(Vector3(0, 30, 0))
	var hi: B3Unit = b.spawn_unit("archer", "red", Vector3(0, top2, 0), "defend")
	var lv: B3Unit = b.spawn_unit("archer", "red", at(0, 8), "defend")
	var foe: B3Unit = b.spawn_unit("archer", "blue", at(18, 0), "defend")
	await sim(0.5)
	var bow := float(hi.wpn.range)
	check(is_instance_valid(tw2) and hi.position.y - foe.position.y > 3.5 and hi._reach(hi.wpn, foe) > bow * 1.1 and is_equal_approx(lv._reach(lv.wpn, foe), bow),
		"⛰️ an archer up a tower shoots further (%.1f m) than one on the ground (%.1f m)" % [hi._reach(hi.wpn, foe), lv._reach(lv.wpn, foe)])
	check(hi._high_k(foe) > 0.5 and is_zero_approx(foe._high_k(hi)) and is_zero_approx(lv._high_k(foe)), "and steadier, but not shooting up at it")

	# 🚀 a wall in the way: the rocketeer moves to get a clear shot instead of blasting the wall
	await fresh()
	var wl: B3Struct = b.spawn_struct("wall", at(8, 0), PI * 0.5, 8.0)
	var rk: B3Unit = b.spawn_unit("rocketeer", "red", at(0, 0), "ranged")
	var tgt: B3Unit = b.spawn_unit("knight", "blue", at(15, 0), "peaceful")
	tgt.speed = 0.0
	await sim(0.5)
	var hp0 := _wall_hp(wl)
	b.set_fighting(true)
	await sim(0.3)
	check(not rk.clear_shot(rk._muzzle_pos(), tgt, 3.2), "🚀 a wall between a rocketeer and its enemy: no clear shot")
	var rockets := {}
	var z0 := rk.position.z
	t = 0.0
	while t < 14.0 and is_instance_valid(tgt) and not tgt.down:
		await sim(0.1)
		t += 0.1
		for pj in b.proj_root.get_children():
			if pj is B3Proj and (pj as B3Proj).kind == "rocket":
				rockets[pj.get_instance_id()] = true
	var moved := absf(rk.position.z - z0)
	check(rockets.size() > 0 and moved > 1.5, "it goes round the wall (%.1f m) and fires (%d rockets)" % [moved, rockets.size()])
	check(_wall_hp(wl) >= hp0 - 0.5, "without blowing up the wall (%.0f → %.0f)" % [hp0, _wall_hp(wl)])

	# 🧱 shot at, a soldier gets behind the sandbags nearby
	await fresh()
	var sb: B3Struct = b.spawn_struct("sandbags", at(4, 0), PI * 0.5)
	var sol: B3Unit = b.spawn_unit("soldier", "red", at(0, 3), "ranged")
	sol.max_hp = 5000.0
	sol.hp = 5000.0
	var gun: B3Unit = b.spawn_unit("gunner", "blue", at(15, 0), "defend")
	gun.max_hp = 5000.0
	gun.hp = 5000.0
	await sim(0.5)
	b.set_fighting(true)
	await sim(5.0)
	var behind: bool = sol.position.x > 2.0 and sol.position.x < 4.0 and absf(sol.position.z) < 2.8
	check(is_instance_valid(sb) and sol._cover_on and behind, "🧱 a soldier being shot at gets behind the sandbags (at %.1f, %.1f)" % [sol.position.x, sol.position.z])
	check(sol.cd < 5.0 and sol.target == gun, "and keeps shooting from there")

	# 🛡️ a shield wall keeps a loose line; without it they bunch up
	await fresh()
	var aim: B3Unit = b.spawn_unit("stick", "blue", at(50, 0), "peaceful")
	aim.speed = 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var line_g: Array[B3Unit] = []
	var mob_g: Array[B3Unit] = []
	for i in 9:
		var dx := r.randf_range(-1.2, 1.2)
		var dz := r.randf_range(-1.2, 1.2)
		line_g.append(b.spawn_unit("legionary", "red", at(dx, -10 + dz), "attack"))
		var m: B3Unit = b.spawn_unit("legionary", "red", at(dx, 10 + dz), "attack")
		m._form = ""        # (the same soldiers, not keeping in line)
		mob_g.append(m)
	await sim(0.5)
	b.set_fighting(true)
	await sim(5.0)
	var gl := _spread(line_g)
	var gm := _spread(mob_g)
	check(line_g[0]._form == "shield" and gl.x > gm.x + 0.2 and gl.x > 1.3, "🛡️ a shield wall keeps a loose line: %.1f m to the nearest mate (a crowd: %.1f m)" % [gl.x, gm.x])
	check(gl.y < gm.y + 1.0 and gl.y < 4.0, "nobody running far ahead of it (%.1f m deep, a crowd %.1f m)" % [gl.y, gm.y])
	var musket: B3Unit = b.spawn_unit("redcoat", "red", at(-20, 0), "auto")
	var viking: B3Unit = b.spawn_unit("viking", "red", at(-20, 4), "auto")
	check(musket._form == "line" and viking._form == "" and kn.size() == 3, "musket men keep a line too, wild vikings don't")
	b.set_fighting(false)


## [the average distance to the nearest mate, how deep the group is along x]
func _spread(g: Array[B3Unit]) -> Vector2:
	var nn := 0.0
	var n := 0
	var x0 := INF
	var x1 := -INF
	for u in g:
		if not is_instance_valid(u) or u.down:
			continue
		var best := INF
		for o in g:
			if o != u and is_instance_valid(o) and not o.down:
				best = minf(best, Vector2(o.position.x - u.position.x, o.position.z - u.position.z).length())
		if best < INF:
			nn += best
			n += 1
		x0 = minf(x0, u.position.x)
		x1 = maxf(x1, u.position.x)
	return Vector2(nn / maxf(1.0, n), x1 - x0)


# --------------------------------------------------------------- 🔥 fire
func _wood_fire() -> void:
	print("burning wood")
	await fresh()
	var tw: B3Struct = b.spawn_struct("tower", at(0, 0), 0.0)
	var stone: B3Struct = b.spawn_struct("wall", at(0, -6), 0.0, 6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	B3History._tree(b, at(4.2, 3.0), rng)
	B3History._tree(b, at(7.0, 6.0), rng)
	var trees: Array[Node3D] = []
	for n in b.world.scenery.get_children():
		if n is StaticBody3D and n.has_meta("scenery") and not n.has_meta("sid"):
			trees.append(n as Node3D)
	await sim(0.3)
	var top: float = b.surface_y(Vector3(0, 30, 0))
	var arch: B3Unit = b.spawn_unit("archer", "red", Vector3(0.6, top, 0.6), "peaceful")
	b.spawn_unit("stick", "blue", at(-40, 0), "peaceful")
	await sim(0.4)
	b.set_fighting(true)
	var col0: Color = ((tw.pieces[0] as Node).get_child(1) as MeshInstance3D).material_override.albedo_color
	b.spawn_hazard("fire", at(0, 0), 2.8, 25.0)      # napalm under it
	await sim(1.2)
	var f := B3Fire.of(b)
	var lit := 0
	for pc in tw.pieces:
		if f.is_burning(pc):
			lit += 1
	check(lit >= 3, "🔥 napalm under a wooden tower sets its legs alight (%d pieces)" % lit)
	var stone_lit := false
	for pc in stone.pieces:
		stone_lit = stone_lit or f.is_burning(pc)
	check(not stone_lit, "a stone wall next to it doesn't burn")
	var burnt_arch := false
	var dark := false
	var t := 0.0
	var n0: int = tw.pieces.size()
	while t < 26.0:
		await sim(0.5)
		t += 0.5
		if is_instance_valid(arch) and (arch.burn_t > 0.0 or arch.down):
			burnt_arch = true
		if not dark and is_instance_valid(tw):
			for pc in tw.pieces:
				if is_instance_valid(pc) and f.is_burning(pc):
					var mi := pc.get_child(1) as MeshInstance3D
					if mi and (mi.material_override as StandardMaterial3D).albedo_color.get_luminance() < col0.get_luminance() * 0.75:
						dark = true
	check(dark, "the burning wood turns charcoal black")
	var n1: int = tw.pieces.size() if is_instance_valid(tw) else 0
	check(n1 < n0 - 3, "and the tower burns through and collapses (%d → %d pieces)" % [n0, n1])
	check(burnt_arch, "the archer up on it catches fire")
	var fell := 0
	for tr in trees:
		if not is_instance_valid(tr) or tr.has_meta("gone"):
			fell += 1
	check(fell >= 1, "🌳 the fire spreads to the trees, which burn and fall over (%d of %d)" % [fell, trees.size()])
	var charred := false
	for c in b.chunks:
		if is_instance_valid(c) and c.get_child_count() > 0:
			for m in c.get_children():
				if m is MeshInstance3D and (m as MeshInstance3D).material_override is StandardMaterial3D \
						and ((m as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.get_luminance() < 0.2:
					charred = true
	check(charred, "falling black and charred")
	check(f.burning.size() <= B3Fire.MAX_BURNING, "(never more than %d fires at once)" % B3Fire.MAX_BURNING)
	# a fireball hitting a wooden tower sets it alight
	await fresh()
	var tw3: B3Struct = b.spawn_struct("tower", at(0, 0), 0.0)
	b.spawn_unit("stick", "red", at(-30, 0), "peaceful")
	b.spawn_unit("stick", "blue", at(-30, 6), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	var post: B3Piece = tw3.pieces[0]
	var from: Vector3 = post.global_position + Vector3(-6, 0.3, 0)
	b.spawn_proj("fireball", from, (post.global_position - from).normalized() * 15.0, null, B3Defs.weapon("fireball"))
	await sim(1.0)
	check(B3Fire.of(b).is_burning(post), "🧙 a wizard's fireball sets a wooden tower alight")
	b.set_fighting(false)
	await sim(0.2)
	check(B3Fire.of(b).burning.is_empty(), "and fires go out when the battle stops")


# ------------------------------------------------- the fighters' map (speed)
## B3Battle's fighters' map only makes "who's near?" faster: every fighter
## still picks the same enemy, keeps away from the same neighbours and heals
## the same friend as if it had looked at every fighter on the field in turn
## (_think_the_long_way), and the hits that look nearby find everyone in reach.
func _fighters_map() -> void:
	print("fighters' map")
	await fresh()
	var kinds := ["soldier", "knight", "archer", "medic", "ptero", "raptor", "gunner", "giant", "wolf", "tank", "heli", "dragon", "elephant", "chicken", "sniper"]
	var teams := ["red", "blue", "green", "wild"]
	var moods := ["auto", "auto", "defend", "berserk", "auto", "coward"]
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in 170:
		b.spawn_unit(kinds[i % kinds.size()], teams[i % teams.size()], at(r.randf_range(-45, 45), r.randf_range(-45, 45)), moods[i % moods.size()])
	b.spawn_unit("archer", "green", at(150, -120))      # one far away from everyone
	for tz: float in [-20.0, 20.0]:
		# archers up on towers (out of a sword's reach: _high_above)
		b.spawn_struct("tower", at(10, tz), 0.0)
		await get_tree().physics_frame
		b.spawn_unit("archer", "blue" if tz < 0.0 else "green", Vector3(10, b.surface_y(Vector3(10, 30, tz)), tz), "defend")
	b.set_fighting(true)
	var looked := 0
	var bad_t := 0
	var bad_s := 0
	var bad_a := 0
	var air_looks := 0
	var bad_air := 0
	var hurt_some := false
	for round_i in 8:
		b.grid_min = 0 if round_i % 2 == 0 else 100000      # (with the map and without)
		await sim(1.2)        # (carries on inside a physics step, before anyone has moved)
		for u: B3Unit in b.units:
			if u.down or u.dead:
				continue
			if not hurt_some and u.team == "red" and not (u is B3Vehicle):
				u.hp = u.max_hp * 0.5      # someone for the medics
				hurt_some = true
			var want: Array = _think_the_long_way(u)
			var old_target = u.target
			var old_sep: Vector3 = u.sep
			var old_ally = u.ally
			var old_voice: float = u.voice_t
			u.voice_t = 99.0         # (no roars from this test)
			# (helicopters and planes then pick their own way, the same as before)
			if u._nearest_enemy(u.position) != want[0]:
				bad_t += 1
			var air := u is B3Aircraft
			var want_air: B3Unit = _air_pick_the_long_way(u) if air else null
			u._think()
			looked += 1
			if air:
				# (one look at everyone, their own way; they don't keep apart from those below)
				air_looks += 1
				if u.target != want_air or u.sep != Vector3.ZERO or u.ally != null:
					bad_air += 1
			else:
				if u.sep.distance_to(want[1]) > 1e-5:
					bad_s += 1
				if u.ally != want[2]:
					bad_a += 1
			u.target = old_target if is_instance_valid(old_target) else null
			u.sep = old_sep
			u.ally = old_ally if is_instance_valid(old_ally) else null
			u.voice_t = old_voice
	check(looked > 600 and bad_t == 0, "every fighter picks the same enemy as looking at everyone (%d looks, %d different)" % [looked, bad_t])
	check(bad_s == 0 and bad_a == 0, "and keeps away from the same neighbours and heals the same friend (%d, %d different)" % [bad_s, bad_a])
	check(air_looks > 20 and bad_air == 0, "helicopters and planes pick their enemy with one look at everyone, their own way (%d looks, %d different)" % [air_looks, bad_air])
	# fighters exactly as far away: the first one in battle.units, as before
	await fresh()
	b.grid_min = 0       # (the map even for these few)
	await get_tree().physics_frame
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
	me.global_position = Vector3(0, me.position.y, 0)
	var ties: Array[B3Unit] = []
	# (the first one in a square looked at after the others)
	for o in [Vector2(-4, 0), Vector2(4, 0), Vector2(0, 4), Vector2(0, -4)]:
		var e: B3Unit = b.spawn_unit("soldier", "blue", at(o.x, o.y), "peaceful")
		e.global_position = Vector3(o.x, e.position.y, o.y)
		ties.append(e)
	b.set_fighting(true)
	var first: B3Unit = _think_the_long_way(me)[0]
	me._think()
	check(me.target == ties[0] and first == ties[0], "of enemies exactly as far away, it goes for the first one placed")
	# nobody left to fight, then someone changing sides in the same step
	var mate: B3Unit = b.spawn_unit("knight", "red", at(30, 0), "peaceful")
	await get_tree().physics_frame
	for e in ties:
		b.remove_unit(e, false)
	var none_left: bool = me._nearest_enemy(me.position) == null and _think_the_long_way(me)[0] == null
	mate.set_team("blue")
	check(none_left and me._nearest_enemy(me.position) == mate, "with no enemies left it finds nobody, and a fighter changing sides is found at once")
	b.set_fighting(false)
	# everyone within reach of a spot is found, wherever the squares fall
	await fresh("", "big")
	await sim(1.0)
	var missed := 0
	for i in 300:
		var c := Vector3(r.randf_range(-30, 30), 0, r.randf_range(-30, 30))
		var rad := r.randf_range(0.2, 9.0)
		var near: Array[B3Unit] = b.units_near(c, rad)
		for u: B3Unit in b.units:
			if not u.down and Vector2(u.position.x - c.x, u.position.z - c.z).length() < rad and not near.has(u):
				missed += 1
	check(missed == 0, "looking near a spot finds every fighter within reach (%d missed)" % missed)
	# clearing everyone away empties the map too (it held on to them until the next one)
	b.grid_min = 0
	await get_tree().physics_frame
	b.grid_on()      # (made now, inside the physics step)
	var had: bool = not b.grid.cells.is_empty() and b.grid.big_r > 0.0
	b.clear_units()
	check(had and b.grid.cells.is_empty() and b.grid.big_r == 0.0 and b.grid.step == -1 and b.units_near(Vector3.ZERO, 50.0).is_empty(), "clearing everyone away empties the fighters' map")


## Who a helicopter or plane goes after (B3Aircraft._think): the nearest
## enemy in the air for a plane, on the ground for a helicopter, the one it's
## already after counting a bit closer.
func _air_pick_the_long_way(me: B3Unit) -> B3Unit:
	var a := me as B3Aircraft
	var best: B3Unit = null
	var bs := 1e18
	for u: B3Unit in b.units:
		if u == me or u.down or not me.is_enemy(u):
			continue
		if me.pers == "defend" and Vector2(u.position.x - me.home.x, u.position.z - me.home.z).length() > me.guard_radius():
			continue
		var s := me.position.distance_squared_to(u.position)
		if a.plane and u.flying:
			s *= 0.3
		elif not a.plane and u is B3Aircraft and (u as B3Aircraft).plane:
			s *= 3.0
		if u == me.target:
			s *= 0.55
		if s < bs:
			bs = s
			best = u
	return best


## What B3Unit._think worked out before the fighters' map: [enemy, push
## away from neighbours, friend to heal], looking at every fighter in turn.
func _think_the_long_way(me: B3Unit) -> Array:
	var my := me.position
	var best: B3Unit = null
	var bd := 1e18
	var hurt_u: B3Unit = null
	var hd := 1e18
	var sx := 0.0
	var sz := 0.0
	var guard := me.pers == "defend"
	var guard_r := me.guard_radius()
	var melee_only := String(me.wpn.type) == "melee" or me.pers == "berserk"
	for u: B3Unit in b.units:
		if u == me or u.down:
			continue
		var dx := u.position.x - my.x
		var dz := u.position.z - my.z
		var d2 := dx * dx + dz * dz
		var rr := me.radius + u.radius + 0.45
		if d2 < rr * rr and d2 > 0.0001:
			var d := sqrt(d2)
			var push := (rr - d) / rr
			sx -= dx / d * push
			sz -= dz / d * push
		if me.is_enemy(u):
			if guard:
				var hx := u.position.x - me.home.x
				var hz := u.position.z - me.home.z
				if hx * hx + hz * hz > guard_r * guard_r:
					continue
			var score := d2
			if u == me.target:
				score *= 0.55
			if u.flying and melee_only and not me.flying:
				score = score * 4.0 + 400.0
			elif melee_only and not me.flying and me._high_above(u, my):
				score = score * 4.0 + 400.0      # (up on a tower, out of reach)
			if score < bd:
				bd = score
				best = u
		elif me.heals and u.team == me.team and u.hp < u.max_hp * 0.92:
			if d2 < hd:
				hd = d2
				hurt_u = u
	return [best, Vector3(sx, 0.0, sz), hurt_u if hd < 22.0 * 22.0 else null]

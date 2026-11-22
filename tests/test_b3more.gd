extends Node
## Headless checks for the extra 3D Battle features: Battle Rules, playing as
## a fighter (overhead and first person), the follow camera, screen shake,
## save slots, ⏮ Reset, Surprise Battle, the MVP and the HUD's layout.
## godot --headless --path . -- --test=b3more

const SPEED := 4.0

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map := "grassland", ui := true) -> void:
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(99)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 777, "no_ui": not ui, "map": map})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


func key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


func rule(id: String, v: String) -> void:
	B3Rules.set_value(id, v)
	b.apply_rules()


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	B3Saves.delete_all_test_saves()
	await _rules()
	await _player()
	await _first_person()
	await _player_gravity()
	await _fp_knockout()
	await _play_fixes()
	await _fp_body()
	await _hit_marker()
	await _blast_rules()
	await _shake()
	await _saves()
	await _reset()
	await _reset_more()
	await _grab_vehicle()
	await _sizes()
	await _surprise()
	await _surprise_room()
	await _hud()
	B3Rules.reset()
	B3Saves.delete_all_test_saves()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	print("test_b3more: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ rules
func _rules() -> void:
	print("battle rules")
	await fresh()
	check(B3Rules.is_default(), "rules start at normal")
	rule("gravity", "moon")
	var g: float = PhysicsServer3D.area_get_param(b.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY)
	check(absf(g - 9.8 * 0.32) < 0.01, "Moon gravity lowers gravity (%.2f)" % g)
	rule("gravity", "normal")

	# MEGA explosions reach fighters a normal one can't
	var far: B3Unit = b.spawn_unit("soldier", "red", at(6.0, 0.0), "peaceful")
	await sim(0.3)
	b.explode(at(0.0, 0.0) + Vector3(0, 0.5, 0), 4.0, 12.0, 60.0)
	await sim(0.1)
	var normal_hp: float = far.hp
	rule("booms", "mega")
	b.explode(at(0.0, 0.0) + Vector3(0, 0.5, 0), 4.0, 12.0, 60.0)
	await sim(0.1)
	check(normal_hp >= far.max_hp - 0.01 and (far.hp < normal_hp or far.down or far.dead), "MEGA explosions reach farther")
	rule("booms", "normal")

	# Super toughness: the same hit hurts much less
	await fresh()
	var a: B3Unit = b.spawn_unit("knight", "red", at(-3, 0), "peaceful")
	var c: B3Unit = b.spawn_unit("knight", "blue", at(3, 0), "peaceful")
	await sim(0.3)
	a.hurt(40.0, Vector3.RIGHT, 1.0)
	rule("health", "super")
	c.hurt(40.0, Vector3.RIGHT, 1.0)
	check(c.max_hp - c.hp < (a.max_hp - a.hp) * 0.3, "Super toughness takes less damage (%.0f vs %.0f)" % [c.max_hp - c.hp, a.max_hp - a.hp])
	rule("health", "normal")

	# Crazy knockback: blasts throw fighters much farther
	var dist := {}
	for k in ["normal", "crazy"]:
		await fresh()
		rule("knock", k)
		var u: B3Unit = b.spawn_unit("soldier", "red", at(2.0, 0.0), "peaceful")
		await sim(0.3)
		var start: Vector3 = u.center()
		b.explode(at(0.0, 0.0) + Vector3(0, 0.3, 0), 4.0, 12.0, 1.0)
		var best := 0.0
		for i in 30:
			await sim(0.1)
			if is_instance_valid(u):
				best = maxf(best, u.center().distance_to(start))
		dist[k] = best
	check(float(dist.crazy) > float(dist.normal) * 1.4, "Crazy knockback throws farther (%.1f m vs %.1f m)" % [dist.crazy, dist.normal])
	rule("knock", "normal")

	# Friendly fire off: your own grenade can't knock over your team
	await fresh()
	rule("friendly", "off")
	var thrower: B3Unit = b.spawn_unit("grenadier", "red", at(-8, 0), "peaceful")
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0.8, 0), "peaceful")
	await sim(0.3)
	b.explode(at(0.4, 0) + Vector3(0, 0.4, 0), 3.5, 12.0, 60.0, {"by": thrower})
	await sim(0.1)
	check(mate.hp >= mate.max_hp - 0.01 and not mate.down, "with friendly fire off, blasts spare your own team")
	check(foe.hp < foe.max_hp or foe.down or foe.dead, "but still hit the enemy")
	rule("friendly", "on")

	# Reinforcements: knocked-out fighters come back
	await fresh()
	rule("respawn", "on")
	var r1: B3Unit = b.spawn_unit("soldier", "red", at(-6, 0), "peaceful")
	b.spawn_unit("soldier", "blue", at(6, 0), "peaceful")
	b.set_fighting(true)
	await sim(0.2)
	r1.hurt(9999.0, Vector3.UP, 1.0)
	await sim(0.5)
	check(b.winner == "", "with reinforcements on, a wiped-out team doesn't lose yet")
	await sim(6.0)
	var reds: Array = b.units.filter(func(u): return u.team == "red" and not u.dead)
	check(reds.size() == 1, "and the knocked-out soldier comes back (%d)" % reds.size())
	rule("respawn", "off")

	# Night, sunset and weather
	rule("time", "night")
	check(b.world.sun.light_energy < 0.5, "Night dims the sun")
	rule("time", "sunset")
	check(b.world.sun.rotation_degrees.x > -30.0, "Sunset puts the sun low")
	rule("time", "day")
	rule("weather", "rain")
	check(b.weather._p != null and b.weather._p.emitting, "Rain falls")
	rule("weather", "snow")
	check(b.weather.kind == "snow" and b.weather._p != null, "Snow falls")
	rule("weather", "clear")
	check(b.weather._p == null, "and Clear stops it")
	b.ui._show_rules()
	await sim(0.1)
	check(b.ui.popup != null and is_instance_valid(b.ui.popup), "the ⚙️ Battle Rules panel opens")
	b.ui.close_top()


# ----------------------------------------------------------------- player
func _player() -> void:
	print("play as a fighter")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "auto")
	var foe: B3Unit = b.spawn_unit("knight", "blue", at(8, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	check(B3Player.active() and me.player and b.fighting, "🎮 Play as me takes control and starts the battle")
	check(b.cam.follow == me, "and the camera follows you")
	var start: Vector3 = me.position
	key(KEY_W, true)
	await sim(1.0)
	key(KEY_W, false)
	await sim(0.2)
	check(me.position.distance_to(start) > 2.0, "W walks the fighter (%.1f m)" % me.position.distance_to(start))
	# aim with the mouse: put the cursor over the enemy
	b.tools._mouse = b.cam.screen_pos(foe.position)
	B3Player.me.jump = true
	await sim(0.1)
	check(me.linear_velocity.y > 2.0 or me.position.y > start.y + 0.3, "Space jumps")
	await sim(1.0)
	b.tools._mouse = b.cam.screen_pos(foe.position)
	B3Player.me.fire = true
	await sim(2.5)
	B3Player.me.fire = false
	check(foe.hp < foe.max_hp or foe.down or foe.dead, "clicking on an enemy shoots it")
	var hp_before: float = foe.hp if is_instance_valid(foe) else 0.0
	b.tools._mouse = b.cam.screen_pos(me.position + Vector3(-10, 0, 0))
	B3Player.me.fire = true
	await sim(1.5)
	B3Player.me.fire = false
	check(not is_instance_valid(foe) or foe.hp == hp_before or foe.dead, "clicking empty ground shoots there instead")
	b.tools.stop_playing()
	check(not B3Player.active() and not me.player and b.cam.follow == null, "Esc gives the fighter back to the computer")
	b.tools.follow(me)
	check(b.cam.follow == me, "🎥 Follow keeps the camera on a fighter")
	b.cam.pan_keys(Vector2(1, 0), 0.1)
	check(b.cam.follow == null, "and moving the camera stops following")
	# getting knocked out while playing hands control back
	b.tools.play_as(me)
	me.hurt(99999.0, Vector3.UP, 1.0)
	await sim(0.2)
	await get_tree().process_frame
	check(not B3Player.active(), "getting knocked out while playing stops it")


# ----------------------------------------------------------- first person
func _first_person() -> void:
	print("first person")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "auto", 0.0)
	var foe: B3Unit = b.spawn_unit("knight", "blue", at(0, 9), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	await get_tree().process_frame
	check(B3Player.me.fp and b.cam.first_person() and b.cam.cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "👀 first person puts the camera in the fighter's eyes")
	var eye: Vector3 = b.cam.cam.global_position
	check(absf(eye.y - (me.position.y + me.tall * 0.9)) < 0.5 and Vector2(eye.x - me.position.x, eye.z - me.position.z).length() < 0.8, "at head height")
	check(b.ui.crosshair.visible and not b.ui.palette.visible, "the crosshair shows and the Toy Box steps aside")
	check(b.cam.hands != null and b.cam.hands.model != null, "you can see your rifle in your hands")
	var hidden := true
	for c in me.rig.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).layers != B3Cam.HIDE_LAYER:
			hidden = false
	check(hidden, "and not the inside of your own head")
	# mouse look: moving the mouse right turns right
	B3Player.me.look_yaw = 0.0
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(120, 0)
	b.tools._unhandled_input(ev)
	check(B3Player.me.look_yaw < -0.1, "moving the mouse turns the view")
	B3Player.me.look_yaw = 0.0
	B3Player.me.look_pitch = 0.0
	await sim(0.2)
	check(absf(angle_difference(me.facing, 0.0)) < 0.05, "and the fighter turns with it")
	# W walks where you look
	var start: Vector3 = me.position
	key(KEY_W, true)
	await sim(1.0)
	key(KEY_W, false)
	await sim(0.2)
	check(me.position.z - start.z > 2.0 and absf(me.position.x - start.x) < 1.0, "W walks the way you're looking (%.1f m)" % (me.position.z - start.z))
	# the crosshair aims: look at the knight and shoot
	var to: Vector3 = foe.center() - b.cam.cam.global_position
	B3Player.me.look_yaw = atan2(to.x, to.z)
	B3Player.me.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	await get_tree().process_frame
	await get_tree().process_frame
	B3Player.me.fire = true
	await sim(2.0)
	B3Player.me.fire = false
	check(foe.hp < foe.max_hp or foe.down or foe.dead, "shots go where the crosshair points")
	# V switches back
	var kv := InputEventKey.new()
	kv.keycode = KEY_V
	kv.pressed = true
	b.tools._unhandled_input(kv)
	await get_tree().process_frame
	check(not B3Player.me.fp and not b.cam.first_person() and b.cam.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "V goes back to the overhead view")
	check(b.ui.palette.visible and not b.ui.crosshair.visible, "and the Toy Box comes back")
	var shown := true
	for c in me.rig.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).layers == B3Cam.HIDE_LAYER:
			shown = false
	check(shown, "and your fighter is drawn again")
	b.tools.set_first_person(true)
	b.tools.stop_playing()
	check(not b.cam.first_person() and not B3Player.me.fp, "stopping while in first person goes back to the overhead view")


# ------------------------------------------------- knocked out in first person
## A hit in the middle of the fight knocks you out inside the physics step, so
## the fighter is freed before the next frame (like in a real battle).
func ko_now(u: B3Unit) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	u.hurt(99999.0, Vector3.UP, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame


func _fp_knockout() -> void:
	print("knocked out in first person")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var near: B3Unit = b.spawn_unit("knight", "red", at(4, 0), "peaceful", 0.0)
	var far: B3Unit = b.spawn_unit("soldier", "red", at(30, 0), "peaceful", 0.0)
	var tk: B3Unit = b.spawn_unit("tank", "red", at(-6, 0), "peaceful", 0.0)
	b.spawn_unit("knight", "blue", at(0, 40), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	await ko_now(me)
	check(B3Player.active() and B3Player.unit == near, "💫 knocked out in first person: you jump into the nearest teammate")
	check(B3Player.me.fp and b.cam.first_person() and b.cam.fp_unit == near and b.ui.crosshair.visible and not b.ui.palette.visible, "and keep looking out of their eyes")
	await ko_now(near)
	check(B3Player.unit == far and b.cam.fp_unit == far, "a fighter takes over before a tank does, even a closer tank")
	await ko_now(far)
	check(B3Player.unit == tk and b.cam.first_person(), "with only the tank left, you jump into the tank")
	await ko_now(tk)
	check(fp_gone(), "💥 with nobody left on your team, you go back to the overhead view")
	check(b.ui.palette.visible and b.ui.dock_holder.visible and not b.ui.crosshair.visible, "with the Toy Box and tools back and no crosshair")
	# overhead play still just goes back to watching
	var a1: B3Unit = b.spawn_unit("soldier", "red", at(0, 6), "peaceful", 0.0)
	b.spawn_unit("soldier", "red", at(2, 6), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(a1, false)
	await ko_now(a1)
	check(not B3Player.playing and not b.cam.first_person(), "playing overhead, a knock-out goes back to watching")
	# a fighter gone some other way (a friend's copy of a knock-out doesn't call on_unit_ko)
	var s2: B3Unit = b.spawn_unit("soldier", "green", at(20, 0), "auto", 0.0)
	await sim(0.3)
	b.tools.play_as(s2, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	s2.dead = true
	b.units.erase(s2)
	s2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(fp_gone(), "and so does your fighter vanishing any other way")


## First person is fully off: not playing, camera overhead, mouse free.
func fp_gone() -> bool:
	return not B3Player.playing and not B3Player.me.fp and not b.cam.first_person() \
		and b.cam.fp_ctl == null and b.cam.cam.projection == Camera3D.PROJECTION_ORTHOGONAL


# ------------------------------------------------------------------ shake
func _shake() -> void:
	print("screen shake")
	await fresh()
	rule("shake", "little")
	b.cam.trauma = 0.0
	b.shake(0.1, b.cam.focus)
	check(b.cam.trauma == 0.0, "small bumps (gunfire, footsteps) don't shake the screen")
	b.shake(0.9, b.cam.focus + Vector3(200, 0, 0))
	check(b.cam.trauma == 0.0, "far-away blasts don't either")
	b.shake(5.0, b.cam.focus)
	check(b.cam.trauma <= 1.0 and b.cam.trauma > 0.3, "big blasts nearby do, but only up to a limit")
	b.cam.apply()
	var a: Vector3 = b.cam.cam.global_position
	var still: Vector3 = b.cam.basis_now() * Vector3(0, 0, b.cam.dist) + b.cam.focus
	check(a.distance_to(still) < 1.0, "a little shake moves the view under a metre (%.2f)" % a.distance_to(still))
	rule("shake", "off")
	b.cam.apply()
	check(b.cam.cam.global_position.distance_to(still) < 0.001, "📳 Screen shake Off keeps it perfectly still")
	B3Rules.reset()
	check(B3Rules.value("shake") == "off", "and ↺ Back to normal doesn't change how you like it")
	rule("shake", "little")
	check(B3Rules.is_default(), "the shake setting doesn't count as a changed rule")


# ------------------------------------------------------------------ saves
func _saves() -> void:
	print("save slots")
	await fresh("snow")
	rule("time", "night")
	for i in 3:
		b.spawn_unit("archer", "red", at(-6, i * 2.0), "defend")
		b.spawn_unit("viking", "blue", at(6, i * 2.0), "berserk")
	b.spawn_unit("trex", "wild", at(0, 8), "auto")
	b.spawn_struct("tower", at(-10, 0), 0.0)
	b.spawn_struct("wall", at(0, -6), 0.5, 8.0)
	b.spawn_hazard("lava", at(0, 0), 3.0)
	b.spawn_prop("xbarrel", at(3, 3))
	b.spawn_prop("c4", at(-3, 3))
	await sim(0.5)
	var n_units: int = b.units.size()
	var n_structs: int = b.structs.size()
	var n_props: int = b.props.size()
	check(B3Saves.save(b, 2), "💾 saving to slot 2 works")
	check(B3Saves.describe(2).begins_with("❄️ Snow · 7 fighters"), "the slot says what's in it (%s)" % B3Saves.describe(2))
	check(B3Saves.describe(3) == "", "empty slots say so")
	rule("time", "day")
	b.load_map("desert")
	check(b.units.is_empty(), "(cleared the field)")
	check(B3Saves.load_slot(b, 2), "📂 loading slot 2 works")
	await sim(0.3)
	check(b.map_id == "snow", "the map comes back")
	check(b.units.size() == n_units, "every fighter comes back (%d of %d)" % [b.units.size(), n_units])
	var vik: Array = b.units.filter(func(u): return u.kind == "viking" and u.team == "blue" and u.pers_choice == "berserk")
	check(vik.size() == 3, "with their team and mood")
	check(b.structs.size() == n_structs, "buildings come back (%d)" % b.structs.size())
	check(b.props.size() == n_props, "barrels and C4 come back (%d)" % b.props.size())
	check(b.hazard_at(at(0, 0)) != null, "the lava pool comes back")
	check(B3Rules.value("time") == "night", "and the rules (night)")
	rule("time", "day")
	b.ui._show_saves()
	await sim(0.1)
	check(b.ui.popup != null and is_instance_valid(b.ui.popup), "the 💾 panel opens")
	b.ui.close_top()


# ------------------------------------------------------------------ reset
func _reset() -> void:
	print("reset to the start")
	await fresh()
	check(b.ui.reset_btn.disabled, "⏮ Reset is off before any fight")
	for i in 5:
		b.spawn_unit("soldier", "red", at(-10, i * 2.0), "attack", PI * 0.5)
		b.spawn_unit("viking", "blue", at(10, i * 2.0), "attack", -PI * 0.5)
	b.spawn_struct("wall", at(0, -6), 0.0, 6.0)
	b.spawn_prop("xbarrel", at(0, 4))
	await sim(0.2)
	b.set_fighting(true)
	b.ui.refresh()
	check(not b.ui.reset_btn.disabled, "pressing Fight! remembers the start")
	await sim(25.0)
	check(b.winner != "" or b.kos > 0, "the battle plays out (%s)" % (b.winner if b.winner != "" else "%d KOs" % b.kos))
	if b.winner != "":
		check(b.ui.again_btn.visible, "the winner banner offers ⏮ Play it again")
	check(B3Saves.save(b, 4), "saving after the fight")
	b.reset_battle()
	await sim(0.3)
	var reds := 0
	var blues := 0
	var spots_ok := true
	for u: B3Unit in b.units:
		if u.dead:
			continue
		if u.team == "red":
			reds += 1
			spots_ok = spots_ok and absf(u.position.x + 10.0) < 0.6
		else:
			blues += 1
			spots_ok = spots_ok and absf(u.position.x - 10.0) < 0.6
	check(reds == 5 and blues == 5 and spots_ok, "⏮ Reset puts everyone back where they started (%d vs %d)" % [reds, blues])
	check(not b.fighting and b.winner == "" and not b.ui.again_btn.visible, "ready to press Fight! again")
	check(b.structs.size() >= 1 and b.props.size() >= 1, "with the wall and barrel back too")
	b.set_fighting(true)
	await sim(3.0)
	check(b.reset_battle() and (b.units as Array).filter(func(u): return not u.dead).size() == 10, "and it works again and again")
	check(not b.ui.reset_btn.disabled, "(the ⏮ button stays on after a Reset)")
	b.clear_units()
	check(B3Saves.load_slot(b, 4), "loading the slot saved after the fight")
	var n := 0
	for u: B3Unit in b.units:
		if not u.dead:
			n += 1
	check(n == 10, "gives the setup from before the fight, not the leftovers (%d fighters)" % n)
	# a History battle: its stakes and earthworks aren't in the Build tab
	b.run_history("agincourt")
	await sim(0.3)
	var custom := 0
	var pieces := 0
	for st: B3Struct in b.structs:
		if not B3Defs.STRUCTS.has(st.kind):
			custom += 1
			pieces += st.pieces.size()
	var fighters: int = b.units.size()
	check(custom > 0 and fighters > 20, "📜 Agincourt sets up (%d fighters, %d special buildings)" % [fighters, custom])
	var looks := {}
	for u: B3Unit in b.units:
		looks[int(u.get_meta("seed", -1))] = true
	b.set_fighting(true)
	await sim(6.0)
	b.reset_battle()
	await sim(0.3)
	var custom2 := 0
	var pieces2 := 0
	for st: B3Struct in b.structs:
		if not B3Defs.STRUCTS.has(st.kind):
			custom2 += 1
			pieces2 += st.pieces.size()
	check(custom2 == custom and pieces2 == pieces, "⏮ Reset brings back the stakes, piece for piece (%d / %d)" % [pieces2, pieces])
	var same_looks := true
	for u: B3Unit in b.units:
		if not looks.has(int(u.get_meta("seed", -2))):
			same_looks = false
	check(b.units.size() == fighters and same_looks, "and every fighter, looking just the same")
	check(B3Saves.save(b, 5), "saving a History battle")
	b.load_map("snow")
	check(B3Saves.load_slot(b, 5), "and loading it")
	var pieces3 := 0
	for st: B3Struct in b.structs:
		if not B3Defs.STRUCTS.has(st.kind):
			pieces3 += st.pieces.size()
	check(pieces3 == pieces and b.map_id == B3History.map_for("agincourt"), "keeps the stakes and the map (%d pieces)" % pieces3)


# --------------------------------------------------------------- surprise
func _surprise() -> void:
	print("surprise battle")
	await fresh()
	var winners := 0
	var mvps := 0
	for s in [11, 22, 33]:
		B3Surprise.run(b, s)
		await sim(0.2)
		var teams := {}
		for u in b.units:
			teams[u.team] = true
		check(b.units.size() >= 6 and teams.size() >= 2, "🎲 Surprise Battle %d sets up armies (%d fighters, %d teams, %s)" % [s, b.units.size(), teams.size(), b.map_id])
		await sim(2.5)
		check(b.fighting, "and the fight starts by itself")
		var t := 0.0
		while b.winner == "" and t < 150.0:
			await sim(1.0)
			t += 1.0
		if b.winner != "":
			winners += 1
		if b.mvp_text() != "":
			mvps += 1
	check(winners >= 2, "Surprise battles end with a winner (%d of 3)" % winners)
	check(mvps >= 1, "and name an MVP (%s)" % b.mvp_text())


# ----------------------------------------------------------- grab a jeep
func _grab_vehicle() -> void:
	print("grab a vehicle")
	await fresh()
	var jeep: B3Unit = b.spawn_unit("jeep", "red", at(0, 0), "peaceful")
	if jeep == null:
		check(false, "a jeep can be placed")
		return
	await sim(0.5)
	var start: Vector3 = jeep.position
	b.tools.set_tool("grab")
	b.tools._mouse = b.cam.screen_pos(jeep.position + Vector3(0, 0.6, 0))
	check(b.tools._grab_start(b.tools._mouse), "✋ Grab picks up a jeep")
	b.tools._mouse = b.cam.screen_pos(at(8, 0))
	await sim(0.6)
	check(jeep.position.y > start.y + 1.0 and jeep.held, "it dangles in the air (%.1f m up)" % (jeep.position.y - start.y))
	b.tools._grab_end(true)
	await sim(3.0)
	check(not jeep.held and jeep.position.distance_to(start) > 4.0, "and lands somewhere else when let go (%.1f m away)" % jeep.position.distance_to(start))


# ------------------------------------------------------------------ sizes
func _sizes() -> void:
	print("fighter sizes")
	await fresh()
	b.tools.choose("knight")
	b.tools.place_size = 2.5
	b.tools._place(at(-4, 0), at(-4, 0), false, false)
	b.tools.place_size = 0.5
	b.tools._place(at(4, 0), at(4, 0), false, false)
	b.tools.place_size = 1.0
	var big: B3Unit = null
	var tiny: B3Unit = null
	for u in b.units:
		if u.size_mult > 2.0:
			big = u
		elif u.size_mult < 0.6:
			tiny = u
	check(big != null and tiny != null, "🦖 Huge and 🐜 Tiny knights can be placed")
	if big == null or tiny == null:
		return
	await sim(0.5)
	check(big.rig.scale.x > tiny.rig.scale.x * 4.0, "Huge is much bigger than Tiny (%.2f vs %.2f)" % [big.rig.scale.x, tiny.rig.scale.x])
	check(big.max_hp > tiny.max_hp * 10.0, "and much tougher (%.0f vs %.0f hp)" % [big.max_hp, tiny.max_hp])
	check(absf(big.position.y - b.world.height_at(big.position.x, big.position.z)) < 0.6, "and stands on the ground")
	big.knock_down(Vector3(0, 6, 0))
	tiny.knock_down(Vector3(0, 6, 0))
	await sim(0.5)
	check(big.ragdoll != null and tiny.ragdoll != null, "both fall over as ragdolls of their size")
	var waited := 0.0
	while big.down and not big.dead and waited < 12.0:
		await sim(0.5)
		waited += 0.5
	check(not big.down and not big.dead, "and the huge one gets back up (after %.1f s)" % waited)
	B3Saves.save(b, 1)
	b.load_map("grassland")
	B3Saves.load_slot(b, 1)
	await sim(0.3)
	var sizes: Array = b.units.map(func(u): return u.size_mult)
	check(sizes.has(2.5) and sizes.has(0.5), "sizes are saved with the battle (%s)" % str(sizes))



# ------------------------------------------------------- playing: the fixes
## Waits (up to `t` seconds of battle time) until `fn` says yes.
func wait_for(fn: Callable, t := 3.0) -> bool:
	var end: float = b.time + t
	var guard := 0
	while not fn.call() and b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1
	return fn.call()


func _play_fixes() -> void:
	print("playing: ghosts, the History tab, wind-ups")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(me)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not b.tools._line.visible, "(the placement ghosts step aside while you play)")
	b.tools.stop_playing()
	await get_tree().process_frame
	await get_tree().process_frame
	check(b.tools._line.visible, "and come back when you stop playing")
	# 📜 History soldiers get a team picker, and don't end up on the wild team
	b.ui.set_cat("dinos")
	var was := String(b.tools.team)
	b.ui.set_cat("history")
	check(b.ui.team_box.visible, "📜 the History tab shows the team, mood and size pickers")
	check(was == "wild" and b.tools.team != "wild", "and after the Dinos tab its soldiers aren't on the wild team (%s)" % b.tools.team)
	b.ui.set_cat("people")
	# a Grenadier you play throws as often as one on its own
	await fresh()
	var gr: B3Unit = b.spawn_unit("grenadier", "red", at(0, 0), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(gr)
	b.tools._mouse = b.cam.screen_pos(at(-6, 0))
	B3Player.me.fire = true
	await wait_for(func(): return gr.act == "throw")
	B3Player.me.fire = false
	check(gr.act == "throw" and gr.cd > float(gr.wpn.cd) * 0.9, "💣 a Grenadier you play waits as long between grenades as one on its own (%.1f s)" % gr.cd)
	b.tools.stop_playing()
	# a Wizard you play waves its staff first, even when you click the ground
	var wz: B3Unit = b.spawn_unit("wizard", "red", at(0, 5), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(wz)
	b.tools._mouse = b.cam.screen_pos(at(-7, 5))
	await get_tree().process_frame
	B3Player.me.fire = true
	await wait_for(func(): return wz.act == "cast")
	B3Player.me.fire = false
	check(wz.act == "cast", "🧙 a Wizard you play casts its spell before the fireball, even at the ground")
	var fireball := func() -> bool:
		for p in b.proj_root.get_children():
			if p is B3Proj and (p as B3Proj).kind == "fireball":
				return true
		return false
	var flew: bool = await wait_for(fireball, 2.0)
	check(flew, "and then the fireball flies")
	b.tools.stop_playing()
	# the sniper keeps aiming at the enemy you clicked, even if the mouse moves off it
	await fresh()
	var sn: B3Unit = b.spawn_unit("sniper", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 10), "peaceful")
	await sim(0.3)
	b.tools.play_as(sn)
	b.tools._mouse = b.cam.screen_pos(foe.position)
	await get_tree().process_frame
	B3Player.me.fire = true
	await wait_for(func(): return sn.act == "aim")
	B3Player.me.fire = false
	check(sn.act == "aim", "(the sniper takes aim at the enemy under the mouse)")
	b.tools._mouse = b.cam.screen_pos(at(-12, -6))
	await sim(1.5)
	check(foe.hp < foe.max_hp or foe.down or foe.dead, "🎯 moving the mouse off it while the sniper aims still takes the shot")
	b.tools.stop_playing()
	# clearing the fighters while you play one isn't a knock-out
	var me2: B3Unit = b.spawn_unit("soldier", "red", at(5, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me2)
	b.clear_units()
	await get_tree().process_frame
	await get_tree().process_frame
	var ko_toast := false
	for c in b.ui.toasts.get_children():
		for l in c.find_children("*", "Label", true, false):
			if "knocked out" in (l as Label).text:
				ko_toast = true
	check(not B3Player.playing and not ko_toast, "🧹 clearing the fighters while you play just stops playing (no knock-out message)")


## Your own body in first person: hidden when you get back up or change
## team, drawn again as a knocked-out ragdoll; teammates in your face fade
## but enemies don't.
func _fp_body() -> void:
	print("first person: your body and the ones near you")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(0.9, 0.5), "peaceful")
	var foe: B3Unit = b.spawn_unit("knight", "blue", at(-0.9, 0.5), "peaceful")
	b.spawn_unit("soldier", "red", at(12, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not mate.rig.visible, "👀 a teammate right in your face fades in first person")
	check(foe.rig.visible, "but an enemy right next to you stays in view")
	me.knock_down(Vector3(0, 3, 0))
	await sim(0.2)
	var up: bool = await wait_for(func(): return not me.down, 14.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(up and own_body_hidden(me), "back on your feet in first person, you still don't see the inside of your own head (%s)" % ("hidden" if own_body_hidden(me) else "up" if up else "still down"))
	me.set_team("green")
	await get_tree().process_frame
	await get_tree().process_frame
	check(own_body_hidden(me) and b.cam.hands.model != null, "nor after changing team (and the rifle is still in your hands)")
	b.tools.stop_playing()
	# knocked out for good: the body you were looking out of stays on the field
	await fresh()
	var ko: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	b.spawn_unit("soldier", "red", at(6, 0), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(ko, true)
	await get_tree().process_frame
	await ko_now(ko)
	var corpse: B3Ragdoll = null
	for rd in b.ragdolls:
		if is_instance_valid(rd) and rd.dead:
			corpse = rd
	var drawn := corpse != null
	if corpse:
		for c in corpse.find_children("*", "VisualInstance3D", true, false):
			if (c as VisualInstance3D).layers == B3Cam.HIDE_LAYER:
				drawn = false
	check(drawn, "💫 knocked out, your old body lies there with X eyes for everyone to see")
	check(B3Player.active() and b.cam.first_person() and own_body_hidden(B3Player.unit), "and the teammate you jump into is hidden instead")
	b.tools.stop_playing()
	# the Robot holds its laser cannon in first person too
	var rb: B3Unit = b.spawn_unit("robot", "red", at(-6, 0), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(rb, true)
	await get_tree().process_frame
	check(b.cam.hands != null and b.cam.hands.model != null, "🤖 the Robot's laser cannon shows in first person")
	b.tools.stop_playing()


## True if every mesh of `u`'s model is on the layer the camera doesn't draw.
func own_body_hidden(u: B3Unit) -> bool:
	if u == null or not is_instance_valid(u) or u.rig == null:
		return false
	for c in u.rig.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).layers != B3Cam.HIDE_LAYER:
			return false
	return true


func _hit_marker() -> void:
	print("first-person hit marker")
	await fresh()
	var me: B3Unit = b.spawn_unit("knight", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("viking", "blue", at(0, 1.3), "peaceful")
	var pal: B3Unit = b.spawn_unit("soldier", "red", at(6, 6), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	await get_tree().process_frame
	var ch = b.ui.crosshair
	ch.hit_t = 0.0
	B3Player.me.look_yaw = 0.0
	B3Player.me.look_pitch = -0.2
	B3Player.me.fire = true
	var marked: bool = await wait_for(func(): return ch.hit_t > 0.0, 2.0)
	B3Player.me.fire = false
	check(marked and (foe.hp < foe.max_hp or foe.down), "✨ your sword hitting an enemy flashes the crosshair's hit marker")
	await sim(0.5)
	ch.hit_t = 0.0
	b.shot_hit({"collider": pal, "position": pal.center()}, B3Defs.weapon("rifle"), Vector3.RIGHT, me)
	check(ch.hit_t == 0.0, "but hitting a teammate doesn't")
	b.shot_hit({"collider": foe, "position": foe.center()}, B3Defs.weapon("rifle"), Vector3.RIGHT, pal)
	check(ch.hit_t == 0.0, "and nor does someone else's shot")
	b.explode(foe.center(), 2.0, 4.0, 5.0, {"by": me})
	check(ch.hit_t > 0.0, "your grenade or rocket hitting an enemy does")
	b.tools.stop_playing()


# ------------------------------------------------------------ blast rules
func _blast_rules() -> void:
	print("blasts and the Battle Rules")
	await fresh()
	rule("friendly", "off")
	var thrower: B3Unit = b.spawn_unit("grenadier", "red", at(-8, 0), "peaceful")
	var lying: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(8, 0), "peaceful")
	await sim(0.3)
	lying.knock_down(Vector3(0, 2, 0))
	await sim(0.6)
	var hp0: float = lying.hp
	b.explode(lying.center() + Vector3(0, 0.3, 0), 3.5, 12.0, 60.0, {"by": thrower})
	await sim(0.1)
	check(lying.down and lying.hp >= hp0 - 0.01, "with friendly fire off, your blast spares a teammate lying on the ground too")
	b.explode(mate.center() + Vector3(0.5, 0, 0), 3.0, 12.0, 60.0, {"team": "red"})
	await sim(0.1)
	check(mate.hp >= mate.max_hp - 0.01 and not mate.down, "and a grenade whose thrower got knocked out since still spares their team")
	rule("friendly", "on")
	# ☄️ MEGA explosions: the nuke's fireball reaches past where its shock
	# wave starts, but nobody gets hit by both
	await fresh()
	rule("booms", "mega")
	var big: B3Unit = b.spawn_unit("elephant", "blue", at(16, 0), "peaceful")
	await sim(0.3)
	big.max_hp = 1000000.0
	big.hp = big.max_hp
	b.nuke_blast(at(0, 0) + Vector3(0, 0.5, 0))
	var after_fireball: float = big.hp
	await sim(2.5)
	check(after_fireball < big.max_hp, "(the nuke's fireball reaches 16 m with MEGA explosions)")
	# the wave only tops it up to the bigger of the two hits (it used to add a whole second hit, ~280 more)
	var fire_dmg: float = big.max_hp - after_fireball
	check(after_fireball - big.hp < 0.4 * fire_dmg, "☢️ and its shock wave doesn't hit the same elephant again in full (%.0f more after %.0f)" % [after_fireball - big.hp, fire_dmg])
	rule("booms", "normal")


# ------------------------------------------------------ reset: the fixes
func _reset_more() -> void:
	print("reset and saves: more")
	await fresh()
	for i in 3:
		b.spawn_unit("soldier", "red", at(-6, i * 2.0), "attack")
		b.spawn_unit("viking", "blue", at(6, i * 2.0), "attack")
	b.set_fighting(true)
	check(not b.start_layout.is_empty() and not b.ui.reset_btn.disabled, "(Fight! remembers the start)")
	b.load_map("desert")
	check(b.start_layout.is_empty() and b.ui.reset_btn.disabled, "⏮ Reset forgets the old battle on a new map")
	for i in 2:
		b.spawn_unit("soldier", "red", at(-6, i * 2.0), "attack")
		b.spawn_unit("viking", "blue", at(6, i * 2.0), "attack")
	b.set_fighting(true)
	b.clear_units()
	check(b.start_layout.is_empty() and b.ui.reset_btn.disabled, "and after 🧹 Clear")
	b.spawn_unit("soldier", "red", at(-6, 0), "attack")
	b.spawn_unit("viking", "blue", at(6, 0), "attack")
	b.set_fighting(true)
	b.run_history("hastings")
	check(b.start_layout.is_empty() and b.ui.reset_btn.disabled, "and after picking a 📜 History battle")
	# a friend's copy of the battle: Reset asks the host, so it works while their fight is on
	b.puppet = true
	b.fighting = true
	check(b.ui.can_reset(), "👥 in a friend's battle, ⏮ Reset works while their fight is on")
	b.puppet = false
	b.fighting = false
	# D-Day: gunners inside the bunkers, French knights stuck in the mud at Agincourt
	b.run_history("dday")
	await sim(0.3)
	var spots := {}
	for u: B3Unit in b.units:
		if u.kind == "gunner":
			spots[u.get_meta("seed")] = u.position.y
	b.set_fighting(true)
	await sim(2.0)
	b.reset_battle()
	await sim(0.3)
	var same := spots.size() > 0
	for u: B3Unit in b.units:
		if spots.has(u.get_meta("seed")) and absf(u.position.y - float(spots[u.get_meta("seed")])) > 0.8:
			same = false
	check(same, "⏮ Reset puts the D-Day gunners back inside their bunkers, not on the roof")
	b.run_history("agincourt")
	await sim(0.3)
	var slow := {}
	var hp := {}
	for u: B3Unit in b.units:
		if u.team == "blue" and u.kind == "knight":
			slow[u.get_meta("seed")] = u.speed
			hp[u.get_meta("seed")] = u.max_hp
	b.set_fighting(true)
	await sim(1.0)
	b.reset_battle()
	await sim(0.3)
	var kept := slow.size() > 0
	var watched := true
	for u: B3Unit in b.units:
		var sd = u.get_meta("seed")
		if slow.has(sd) and (absf(u.speed - float(slow[sd])) > 0.01 or absf(u.max_hp - float(hp[sd])) > 0.5):
			kept = false
		if not u.has_meta("history"):
			watched = false
	check(kept, "📜 and the French knights are still worn out and slow in the mud")
	check(watched, "and the battle is still watched so it can't stall")
	# 💾 loading a battle doesn't change how much the screen shakes
	rule("shake", "off")
	check(B3Saves.save(b, 6), "(saved with Screen shake off)")
	rule("shake", "lots")
	B3Saves.load_slot(b, 6)
	check(B3Rules.value("shake") == "lots", "📳 loading a saved battle keeps your Screen shake setting")
	rule("shake", "little")


# --------------------------------------------------- surprise: more room
func _surprise_room() -> void:
	print("surprise battle: room for everyone")
	await fresh()
	var dinos := 0
	var big := 0
	var ok_ground := true
	var ok_room := true
	var off_ground := ""
	var squashed := ""
	var big_kinds: Array = B3Defs.UNIT_ORDER.get("vehicles", []) + B3Defs.UNIT_ORDER.get("dinos", [])
	for s in range(1, 13):
		B3Surprise.run(b, s * 7)
		for u: B3Unit in b.units:
			if u.flying:
				continue
			if u.team == "wild":
				dinos += 1
				var gy: float = b.surface_y(Vector3(u.position.x, 60.0, u.position.z))
				if absf(u.position.y - gy) > 0.4:
					ok_ground = false
					off_ground = "%s at %.1f m, ground %.1f m (%s)" % [u.kind, u.position.y, gy, b.map_id]
				continue
			if u.kind in big_kinds:
				big += 1
			for o: B3Unit in b.units:
				if o == u or o.flying or o.team != u.team:
					continue
				var d := Vector2(o.position.x - u.position.x, o.position.z - u.position.z).length()
				if d < (u.radius + o.radius) * 0.9:
					ok_room = false
					squashed = "%s and %s %.1f m apart" % [u.kind, o.kind, d]
	check(dinos > 0 and ok_ground, "🎲 Surprise dinosaurs start on the ground, not inside a hill (%d dinos) %s" % [dinos, off_ground])
	check(big > 0 and ok_room, "and nobody in an army starts inside anyone else, even tanks (%d big ones) %s" % [big, squashed])


# --------------------------------------------------------------- the HUD
func _hud() -> void:
	print("the HUD")
	await fresh()
	var w: float = get_viewport().get_visible_rect().size.x
	b.ui._show_map_menu()
	for i in 3:
		await get_tree().process_frame
	var r: Rect2 = b.ui.popup.get_global_rect()
	check(absf(r.get_center().x - w * 0.5) < 2.0, "🗺️ pop-up panels sit in the middle of the screen (%.0f vs %.0f)" % [r.get_center().x, w * 0.5])
	b.ui._show_history()
	for i in 3:
		await get_tree().process_frame
	r = b.ui.popup.get_global_rect()
	check(absf(r.get_center().x - w * 0.5) < 2.0, "even big ones like 📜 History (%.0f)" % r.get_center().x)
	b.ui.close_top()
	# every team on the field, on the map with the longest name
	b.load_map("pass")
	var x := -12.0
	for t in B3Defs.TEAM_ORDER:
		b.spawn_unit("soldier", String(t), at(x, 0), "peaceful")
		x += 5.0
	await sim(0.6)
	check(b.ui.top_bar.get_combined_minimum_size().x <= w - 20.0, "the top bar fits across the screen with all five teams (%.0f of %.0f)" % [b.ui.top_bar.get_combined_minimum_size().x, w - 20.0])
	b.clear_units()
	await sim(0.6)
	check(b.ui.title_lbl.visible, "and the ⚔️ 3D Battle title is back when there's room")
	# messages show under the "You're the ..." lines while you play
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	for i in 3:
		await get_tree().process_frame
	var pl: Rect2 = b.ui.play_lbl.get_global_rect()
	var tr: Rect2 = b.ui.toasts.get_global_rect()
	check(b.ui.play_lbl.visible and b.ui.toasts.get_child_count() > 0 and tr.position.y >= pl.end.y, "🎮 messages don't cover the 'You're the ...' lines (%.0f vs %.0f)" % [tr.position.y, pl.end.y])
	b.tools.stop_playing()
	for i in 2:
		await get_tree().process_frame
	check(b.ui.toasts.position.y == 80.0, "and go back up when you stop")


# ------------------------------------------- your own shots and the Gravity rule
## Arrows and grenades you fire yourself aim for the Gravity rule like the
## computer's do, so they land where you point in Moon gravity too.
func _player_gravity() -> void:
	print("your shots in Moon gravity")
	for kind in ["archer", "grenadier"]:
		await fresh()
		rule("gravity", "moon")
		var me: B3Unit = b.spawn_unit(kind, "red", at(-6, 0), "peaceful", PI * 0.5)
		await sim(0.3)
		b.tools.play_as(me)
		var aim := at(8, 0)
		if kind == "archer":
			B3Player._proj_at(me, me.wpn, aim)
		else:
			B3Player._throw_at(me, me.wpn, aim)
		var p: B3Proj = null
		for c in b.proj_root.get_children():
			if c is B3Proj:
				p = c
		# where it first comes down (a grenade then bounces about until its fuse runs out)
		var last := Vector3(-99, 0, -99)
		var up := true
		for i in 1200:
			if not is_instance_valid(p) or p.stuck:
				break
			last = p.global_position
			if p.vel.y < 0.0:
				up = false
			if kind == "grenadier" and not up and last.y - b.world.height_at(last.x, last.z) < 0.35:
				break
			await get_tree().physics_frame
		if is_instance_valid(p) and p.stuck:
			last = p.global_position
		var miss := Vector2(last.x - aim.x, last.z - aim.z).length()
		check(miss < 1.5, "🌙 your %s comes down where you aimed in Moon gravity (%.1f m off)" % ["arrow" if kind == "archer" else "grenade", miss])
		b.tools.stop_playing()
	rule("gravity", "normal")


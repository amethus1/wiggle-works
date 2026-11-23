extends TestBase
## Headless checks for the right-click powers you get while playing a
## fighter, animal or dinosaur in 3D Battle (B3Player.power), and for ⇥ Tab
## (or N) jumping into the next teammate.
## godot --headless --path . -- --test=b3powers

const SPEED := 4.0


func fresh(map := "grassland") -> void:
	if b and is_instance_valid(b):
		b.tools.stop_playing()
	await drop_battle()
	B3Player.stop()
	B3Player.me.clear_buttons()
	B3Player.me.fp = false
	start_battle(99, {"seed": 777, "map": map})


## A key press as the battle's input handler sees it.
func press(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	b.tools._unhandled_input(ev)


func right_click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = down
		b.tools._unhandled_input(ev)


## Overhead: puts the mouse over a spot on the ground.
func aim(p: Vector3) -> void:
	b.tools._mouse = b.cam.screen_pos(p)


## Overhead: aims this computer's controls exactly at `p`. (The mouse handler
## is switched off, so the camera gliding after you can't move the aim.)
func aim_at(p: Vector3) -> void:
	b.tools.set_process(false)
	B3Player.me.aim = p


## First person: turns the view to look at `p`.
func look_at_point(p: Vector3) -> void:
	var to: Vector3 = p - b.cam.cam.global_position
	B3Player.me.look_yaw = atan2(to.x, to.z)
	B3Player.me.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())


func flat_dist(a: Vector3, c: Vector3) -> float:
	return Vector2(a.x - c.x, a.z - c.z).length()


func hurt_or_down(u: B3Unit) -> bool:
	return not is_instance_valid(u) or u.dead or u.down or u.hp < u.max_hp - 0.01


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	await _which()
	await _shield()
	await _scope()
	await _bayonet()
	await _kick()
	await _charge()
	await _pounce()
	await _heal()
	await _swoop()
	await _gorilla()
	await _roar()
	await _friends()
	await _tab()
	await _shield_rhythm()
	await _gorilla_fp()
	await _scope_down()
	await _tab_skips()
	await _gauges()
	if b and is_instance_valid(b):
		b.tools.stop_playing()
		b.queue_free()
	B3Player.stop()
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	finish()


# ------------------------------------------------------------ who gets what
func _which() -> void:
	print("which power each one gets")
	await fresh()
	var want := {"knight": "shield", "hoplite": "shield", "immortal": "shield", "legionary": "shield", "gaul": "shield",
		"saxon": "shield", "sniper": "scope", "redcoat": "bayonet", "linesman": "bayonet", "union": "bayonet",
		"confed": "bayonet", "bull": "charge", "trike": "charge", "mammoth": "charge", "cavalry": "charge",
		"horseknight": "charge", "raptor": "pounce", "medic": "heal", "dragon": "swoop", "ptero": "swoop",
		"gorilla": "gorilla", "trex": "roar", "elephant": "roar", "soldier": "shove", "stick": "shove",
		"minuteman": "shove", "giant": "shove", "dog": "shove", "tank": "", "heli": "", "plane": ""}
	var wrong: Array = []
	var no_help: Array = []
	var x := -90.0
	for k: String in B3Defs.UNITS:
		var u: B3Unit = b.spawn_unit(k, "red", at(x, 60), "peaceful")
		x += 4.0
		var pw := B3Player.power(u)
		if want.has(k) and pw != String(want[k]):
			wrong.append("%s: %s" % [k, pw])
		if (pw == "") != (u is B3Vehicle):
			wrong.append("%s: %s" % [k, pw])
		var h := B3Player.power_help(u)
		if (h == "") != (u is B3Vehicle) or (h != "" and not "right-click" in h):
			no_help.append(k)
	check(wrong.is_empty(), "every fighter, animal and dino gets its own right-click power, vehicles keep their second gun %s" % str(wrong))
	check(no_help.is_empty(), "and the help line can say what right-click does %s" % str(no_help))
	var kn: B3Unit = b.spawn_unit("knight", "red", at(0, 0), "peaceful")
	var bu: B3Unit = b.spawn_unit("bull", "red", at(4, 0), "peaceful")
	print("        e.g. \"%s\", \"%s\"" % [B3Player.power_help(kn), B3Player.power_help(bu)])
	# (and placing a T-Rex from the Toy Box earns the 🦖 Jurassic sticker, as in 2D; tests never save it)
	var had: bool = Settings.stickers.has("dino")
	Settings.stickers.erase("dino")
	b.tools.place_id = "trex"
	b.tools._place(at(-20, -20), at(-20, -20), false, false)
	check(Settings.stickers.has("dino"), "🦖 placing a T-Rex in 3D Battle earns the Jurassic sticker")
	if not had:
		Settings.stickers.erase("dino")


# ------------------------------------------------------------------ shield
func _shield() -> void:
	print("🛡️ raising the shield")
	await fresh()
	var me: B3Unit = b.spawn_unit("knight", "red", at(0, 0), "peaceful", 0.0)
	b.spawn_unit("soldier", "blue", at(0, 50), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false      # (nobody else moves about)
	aim(me.position + Vector3(0, 0, 8))      # (the mouse: W walks with the camera)
	var dist := {}
	for up: bool in [false, true]:
		B3Player.me.fire2 = up
		await sim(0.3)
		var start: Vector3 = me.position
		key(KEY_W, true)
		await sim(1.0)
		key(KEY_W, false)
		dist[up] = flat_dist(me.position, start)
		await sim(0.3)
	check(me.shield_up, "holding right-click raises the knight's shield")
	check(float(dist[true]) < float(dist[false]) * 0.7, "and it walks slower with it up (%.1f m vs %.1f m)" % [dist[true], dist[false]])
	await frames(2)
	var al: Node3D = me.rig.pv.get("arm_l")
	check(al.rotation.x < -1.2, "you can see it held up in front (arm %.2f)" % al.rotation.x)
	# hits from the front, the side and behind, with the shield down and up
	aim_at(me.position + me.forward() * 8.0)
	await sim(0.3)
	var fwd: Vector3 = me.forward()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var took := func(push: Vector3) -> float:
		var h0: float = me.hp
		me.hurt(20.0, push, 1.0)
		var d: float = h0 - me.hp
		me.hp = me.max_hp
		return d
	B3Player.me.fire2 = false
	await sim(0.1)
	var front_down: float = took.call(-fwd)
	var side_down: float = took.call(-side)
	B3Player.me.fire2 = true
	await sim(0.1)
	me._block_t = 0.0
	var front_up: float = took.call(-fwd)
	check(front_up < front_down * 0.5, "with the shield up, hits from the front hurt much less (%.1f vs %.1f)" % [front_up, front_down])
	check(me._block_t > 0.0, "(and a BLOCK! pops up)")
	var side_up: float = took.call(-side)
	check(side_up < side_down * 0.5, "it covers the sides too (%.1f vs %.1f)" % [side_up, side_down])
	var back_up: float = took.call(fwd)
	check(back_up >= side_down * 0.99, "but not your back (%.1f)" % back_up)
	# first person: the shield comes up on the left of the view
	b.tools.set_first_person(true)
	B3Player.me.fire2 = true
	var hands: B3FPView = b.cam.hands
	var raised: bool = await wait_for(func(): return hands.shield != null and hands.shield.visible and hands._guard > 0.95, 2.0)
	check(raised, "👀 in first person you see your shield come up")
	B3Player.me.fire2 = false
	var lowered: bool = await wait_for(func(): return not hands.shield.visible, 2.0)
	check(lowered and not me.shield_up, "and go back down when you let go")
	b.tools.stop_playing()
	check(not me.shield_up, "the computer never keeps it up for you")


# ------------------------------------------------------------------- scope
func _scope() -> void:
	print("🎯 the sniper's scope")
	await fresh()
	var me: B3Unit = b.spawn_unit("sniper", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("knight", "blue", at(0, 30), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	b.fighting = false
	await frames(3)
	check(absf(b.cam.cam.fov - 72.0) < 0.5, "(first person starts with the normal view, %.0f°)" % b.cam.cam.fov)
	var turn := func() -> float:
		B3Player.me.look_yaw = 0.0
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(100, 0)
		b.tools._unhandled_input(ev)
		return absf(B3Player.me.look_yaw)
	var t_out: float = turn.call()
	right_click()
	var zoomed: bool = await wait_for(func(): return b.cam.cam.fov < 26.0, 2.0)
	check(B3Player.me.fire2 and zoomed, "🔭 right-click puts the scope in (%.0f°)" % b.cam.cam.fov)
	check(b.cam._scope != null and b.cam._scope.visible, "with a round black edge around the view")
	check(not b.cam.hands.model.visible, "and the rifle out of the way")
	var t_in: float = turn.call()
	check(t_in < t_out * 0.5, "the mouse turns the view slower through the scope (%.2f vs %.2f)" % [t_in, t_out])
	look_at_point(foe.center())
	await frames(3)
	B3Player.me.fire = true
	var hit: bool = await wait_for(func(): return hurt_or_down(foe), 2.0)
	B3Player.me.fire = false
	check(hit, "a shot through the scope hits what the crosshair is on, 30 m away")
	right_click()
	var back: bool = await wait_for(func(): return b.cam.cam.fov > 71.5, 2.0)
	check(not B3Player.me.fire2 and back and not b.cam._scope.visible and b.cam.hands.model.visible, "right-click again takes the scope out")
	right_click()
	b.tools.set_first_person(false)
	await frames(2)
	check(not B3Player.me.fire2 and b.cam.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "and V back to overhead takes it out too")
	# overhead: hold right-click for a steady aim
	me.cd = 0.0
	aim_at(foe.position)
	B3Player.me.fire2 = true
	await sim(0.2)
	await frames(2)
	check(me.laser != null and me.laser.visible, "overhead, holding right-click steadies the aim, with a red laser")
	B3Player.me.fire = true
	await wait_for(func(): return me.act == "aim", 1.0)
	B3Player.me.fire = false
	check(me.act == "aim" and me.act_len < 0.6, "and the sniper takes aim twice as fast (%.2f s)" % me.act_len)
	B3Player.me.fire2 = false
	await sim(1.0)
	await frames(2)
	check(not me.laser.visible, "letting go puts the laser away")
	b.tools.stop_playing()


# ----------------------------------------------------------------- bayonet
func _bayonet() -> void:
	print("🗡️ bayonet")
	await fresh()
	var me: B3Unit = b.spawn_unit("redcoat", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 1.7), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position)
	await sim(0.2)
	me.cd = 99.0       # still reloading the musket
	B3Player.me.fire2 = true
	var stab: bool = await wait_for(func(): return me.act == "thrust", 1.0)
	check(stab, "right-click: the redcoat stabs with its bayonet, even while its musket reloads")
	var hit: bool = await wait_for(func(): return hurt_or_down(foe), 1.0)
	B3Player.me.fire2 = false
	check(hit, "and it hurts the enemy in front (%.0f hp left)" % foe.hp)
	check(me.power_cd > 0.0, "then it waits a moment before the next stab")
	b.tools.stop_playing()


# ------------------------------------------------------------ kick, shove
## Counts the times `u` starts its power act while right-click is held for `t` seconds.
func count_uses(u: B3Unit, act: String, t: float) -> int:
	var n := 0
	var was := ""
	var end: float = b.time + t
	B3Player.me.fire2 = true
	while b.time < end:
		if u.act == act and was != act:
			n += 1
		was = u.act
		await get_tree().physics_frame
	B3Player.me.fire2 = false
	return n


func _kick() -> void:
	print("👟 kick and shove (everyone else)")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 1.4), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position + Vector3(0, 0, 4))
	me.cd = 99.0
	await sim(0.2)
	B3Player.me.fire2 = true
	var kicked: bool = await wait_for(func(): return foe.hp < foe.max_hp, 1.0)
	B3Player.me.fire2 = false
	var away: Vector3 = foe.position - me.position
	away.y = 0.0
	var push: float = foe.linear_velocity.dot(away.normalized())
	check(kicked and foe.max_hp - foe.hp < 15.0, "right-click: a soldier kicks the enemy in front (%.0f damage)" % (foe.max_hp - foe.hp))
	check(push > 2.5 and not foe.down, "which pushes it back a little (%.1f m/s) without knocking it over" % push)
	await sim(1.5)
	var n: int = await count_uses(me, "kick", 2.0)
	check(n >= 1 and n <= 2, "holding right-click can't spam it: %d kicks in 2 s" % n)
	b.tools.stop_playing()
	# a giant's kick sends people flying
	await fresh()
	var gi: B3Unit = b.spawn_unit("giant", "red", at(0, 0), "peaceful", 0.0)
	var f2: B3Unit = b.spawn_unit("soldier", "blue", at(0, 2.2), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(gi)
	b.fighting = false
	aim_at(f2.position + Vector3(0, 0, 4))
	gi.cd = 99.0
	await sim(0.2)
	B3Player.me.fire2 = true
	var flew: bool = await wait_for(func(): return not is_instance_valid(f2) or f2.down, 1.5)
	B3Player.me.fire2 = false
	check(flew, "🧌 a giant's kick knocks a soldier right over")
	b.tools.stop_playing()
	# animals shove with their heads
	var dog: B3Unit = b.spawn_unit("dog", "red", at(10, 0), "peaceful", 0.0)
	var f3: B3Unit = b.spawn_unit("soldier", "blue", at(10, 1.2), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(dog)
	b.fighting = false
	aim_at(f3.position + Vector3(0, 0, 4))
	dog.cd = 99.0
	await sim(0.2)
	B3Player.me.fire2 = true
	var shoved: bool = await wait_for(func(): return dog.act == "kick", 1.0)
	var hit: bool = await wait_for(func(): return hurt_or_down(f3), 1.0)
	B3Player.me.fire2 = false
	check(shoved and hit, "🐕 a dog shoves the enemy in front with its head")
	b.tools.stop_playing()


# ------------------------------------------------------------------ charge
func _charge() -> void:
	print("🐂 charge")
	await fresh()
	var me: B3Unit = b.spawn_unit("bull", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 11), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position)
	await sim(0.2)
	B3Player.me.fire2 = true
	var went: bool = await wait_for(func(): return me.charge_t > 0.0, 1.0)
	B3Player.me.fire2 = false
	check(went and me.act == "charge", "right-click: the bull charges where you aim")
	var hit: bool = await wait_for(func(): return hurt_or_down(foe), 3.0)
	check(hit, "and bowls over the enemy in its way")
	await wait_for(func(): return me.charge_t <= 0.0, 3.0)
	check(me.power_cd > 0.5, "then it needs a rest (%.1f s)" % me.power_cd)
	B3Player.me.fire2 = true
	await sim(0.3)
	B3Player.me.fire2 = false
	check(me.charge_t <= 0.0, "and right-click does nothing until then")
	b.tools.stop_playing()
	# first person: the mouse steers the charge
	var cav: B3Unit = b.spawn_unit("cavalry", "red", at(-30, -30), "peaceful", 0.0)
	await sim(0.3)
	b.tools.play_as(cav, true)
	b.fighting = false
	B3Player.me.look_yaw = 0.0
	await sim(0.2)
	B3Player.me.fire2 = true
	await wait_for(func(): return cav.charge_t > 0.0, 1.0)
	B3Player.me.fire2 = false
	B3Player.me.look_yaw = PI * 0.5
	await sim(0.6)
	check(cav.charge_t > 0.0 and cav.charge_dir.x > 0.4, "🐎 in first person the cavalry's charge turns where you look (%.2f)" % cav.charge_dir.x)
	b.tools.stop_playing()


# ------------------------------------------------------------------ pounce
func _pounce() -> void:
	print("🦎 pounce")
	await fresh()
	var me: B3Unit = b.spawn_unit("raptor", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 5), "peaceful", PI)
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position)
	me.cd = 0.0
	await sim(0.2)
	var y0: float = me.position.y
	B3Player.me.fire2 = true
	var leapt: bool = await wait_for(func(): return me.act == "pounce", 1.0)
	B3Player.me.fire2 = false
	await sim(0.1)
	check(leapt and me.position.y > y0 + 0.15, "right-click: the raptor leaps at where you aim")
	var hit: bool = await wait_for(func(): return hurt_or_down(foe), 2.0)
	check(hit, "and claws the enemy it lands on")
	b.tools.stop_playing()


# ------------------------------------------------------------------ medic
func _heal() -> void:
	print("💚 the medic's healing pulse")
	await fresh()
	var me: B3Unit = b.spawn_unit("medic", "red", at(0, 0), "peaceful", 0.0)
	var n1: B3Unit = b.spawn_unit("soldier", "red", at(3, 0), "peaceful")
	var n2: B3Unit = b.spawn_unit("knight", "red", at(-2, 3), "peaceful")
	var far: B3Unit = b.spawn_unit("soldier", "red", at(25, 0), "peaceful")
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 4), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	for u: B3Unit in [me, n1, n2, far, foe]:
		u.hp = u.max_hp * 0.3
	B3Player.me.fire2 = true
	var pulsed: bool = await wait_for(func(): return me.act == "pulse", 1.0)
	B3Player.me.fire2 = false
	check(pulsed and n1.hp > n1.max_hp * 0.3 + 30.0 and n2.hp > n2.max_hp * 0.3 + 30.0, "right-click: the medic's pulse heals the teammates around it")
	check(absf(far.hp - far.max_hp * 0.3) < 0.01, "but not ones far away")
	check(absf(foe.hp - foe.max_hp * 0.3) < 0.01, "or enemies")
	check(me.hp > me.max_hp * 0.3 + 5.0, "and the medic a little")
	var h: float = n1.hp
	B3Player.me.fire2 = true
	await sim(2.0)
	B3Player.me.fire2 = false
	check(absf(n1.hp - h) < 0.01, "it can't heal again straight away (%.1f s to wait)" % me.power_cd)
	b.tools.stop_playing()


# ------------------------------------------------------------------- swoop
func _swoop() -> void:
	for kind: String in ["dragon", "ptero"]:
		print("%s swoop" % ("🐉" if kind == "dragon" else "🦅"))
		await fresh()
		var me: B3Unit = b.spawn_unit(kind, "red", at(0, 0), "peaceful", 0.0)
		var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 10), "peaceful", PI)
		await sim(1.0)
		b.tools.play_as(me)
		b.fighting = false
		aim_at(foe.position)
		await sim(0.3)
		var ground := func() -> float: return me.position.y - b.world.height_at(me.position.x, me.position.z)
		var high: float = ground.call()
		B3Player.me.fire2 = true
		var dove: bool = await wait_for(func(): return me._swoop, 1.0)
		B3Player.me.fire2 = false
		check(dove, "right-click: the %s swoops down at where you aim (from %.1f m up)" % [kind, high])
		var bit: bool = await wait_for(func(): return hurt_or_down(foe), 4.0)
		check(bit, "and bites the enemy there")
		await wait_for(func(): return not me._swoop, 3.0)
		await sim(2.0)
		check(float(ground.call()) > 2.5, "then flies back up (%.1f m)" % float(ground.call()))
		b.tools.stop_playing()


# ----------------------------------------------------------------- gorilla
func _gorilla() -> void:
	print("🦍 ground pound and boulder")
	await fresh()
	var me: B3Unit = b.spawn_unit("gorilla", "red", at(0, 0), "peaceful", 0.0)
	var n1: B3Unit = b.spawn_unit("soldier", "blue", at(0, 2.2), "peaceful")
	var n2: B3Unit = b.spawn_unit("soldier", "blue", at(1.4, 1.8), "peaceful")
	var far: B3Unit = b.spawn_unit("knight", "blue", at(0, 15), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(n1.position)
	me.cd = 99.0
	await sim(0.2)
	B3Player.me.fire2 = true
	var pounded: bool = await wait_for(func(): return me.act == "pound", 1.0)
	B3Player.me.fire2 = false
	check(pounded, "right-click close by: the gorilla ground-pounds")
	var hit: bool = await wait_for(func(): return hurt_or_down(n1) and hurt_or_down(n2), 2.0)
	check(hit, "knocking about the enemies around it")
	await wait_for(func(): return me.power_cd <= 0.0 and me.act == "", 6.0)
	aim_at(far.position)
	await sim(0.3)
	B3Player.me.fire2 = true
	var hurled: bool = await wait_for(func(): return me.act == "hurl", 1.0)
	B3Player.me.fire2 = false
	check(hurled, "aimed far away, it throws a boulder instead")
	var rock := func() -> B3Proj:
		for p in b.proj_root.get_children():
			if p is B3Proj and (p as B3Proj).kind == "boulder":
				return p
		return null
	var flew: bool = await wait_for(func(): return rock.call() != null, 2.0)
	var last := Vector3.ZERO
	var p: B3Proj = rock.call()
	for i in 1200:
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			break
		last = p.global_position
		await get_tree().physics_frame
	check(flew and flat_dist(last, far.position) < 3.0, "which lands where you aimed (%.1f m off)" % flat_dist(last, far.position))
	b.tools.stop_playing()


# -------------------------------------------------------------------- roar
func _roar() -> void:
	print("🦖 roar")
	await fresh()
	var me: B3Unit = b.spawn_unit("trex", "red", at(0, 0), "peaceful", 0.0)
	var a1: B3Unit = b.spawn_unit("soldier", "blue", at(0, 6), "peaceful")
	var a2: B3Unit = b.spawn_unit("stick", "blue", at(4, 3), "peaceful")
	var far: B3Unit = b.spawn_unit("soldier", "blue", at(0, 35), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	me.cd = 99.0
	var p1: Vector3 = a1.position
	B3Player.me.fire2 = true
	var roared: bool = await wait_for(func(): return me.act == "roar", 1.0)
	B3Player.me.fire2 = false
	check(roared, "right-click: the T-Rex roars")
	check(a1.stun_t > 0.3 and (a2.stun_t > 0.3 or a2.down), "enemies close by stand stunned")
	await sim(0.4)
	check(flat_dist(a1.position, p1) > 0.3 or a1.down, "and get pushed back (%.1f m)" % flat_dist(a1.position, p1))
	check(a1.hp == a1.max_hp and a2.hp == a2.max_hp, "but nobody gets hurt")
	check(far.stun_t <= 0.0 and far.position.distance_to(at(0, 35)) < 0.5, "ones far away don't notice")
	b.tools.stop_playing()


# ----------------------------------------------------------------- friends
## A friend's right-click arrives in their controls (B3Ctl.pack) and the
## host's copy of their fighter uses the power.
func _friends() -> void:
	print("👥 powers for friends")
	await fresh()
	var kn: B3Unit = b.spawn_unit("knight", "red", at(0, 0), "peaceful", 0.0)
	var bu: B3Unit = b.spawn_unit("bull", "red", at(10, 0), "peaceful", 0.0)
	b.spawn_unit("soldier", "blue", at(0, 40), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	var c1 := B3Ctl.new()
	c1.peer = 2
	B3Player.attach(kn, c1)
	var sent := B3Ctl.new()
	sent.fire2 = true
	sent.aim = kn.position + Vector3(0, 0, 5)
	c1.unpack(sent.pack())
	await sim(0.2)
	check(c1.fire2 and kn.shield_up, "a friend's right-click comes over in their controls and raises their knight's shield")
	sent.fire2 = false
	c1.unpack(sent.pack())
	await sim(0.2)
	check(not kn.shield_up, "and lowers it")
	var c2 := B3Ctl.new()
	c2.peer = 3
	B3Player.attach(bu, c2)
	sent.fire2 = true
	sent.aim = bu.position + Vector3(0, 0, 12)
	c2.unpack(sent.pack())
	var went: bool = await wait_for(func(): return bu.charge_t > 0.0, 1.0)
	check(went, "a friend's bull charges")
	B3Player.detach(kn)
	B3Player.detach(bu)


# --------------------------------------------------------------- ⇥ Tab / N
func _tab() -> void:
	print("⇥ Tab: the next teammate")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var m1: B3Unit = b.spawn_unit("knight", "red", at(3, 0), "peaceful", 0.0)
	var m2: B3Unit = b.spawn_unit("archer", "red", at(8, 0), "peaceful", 0.0)
	var tk: B3Unit = b.spawn_unit("tank", "red", at(15, 0), "peaceful", 0.0)
	var taken: B3Unit = b.spawn_unit("soldier", "red", at(1, 1), "peaceful", 0.0)
	b.spawn_unit("soldier", "blue", at(0, 50), "peaceful")
	await sim(0.3)
	var friend := B3Ctl.new()
	friend.peer = 2
	B3Player.attach(taken, friend)      # a friend is playing this one
	var shown: bool = b.ui.palette.visible
	press(KEY_TAB)
	check(b.ui.palette.visible != shown, "not playing, Tab still shows or hides the Toy Box")
	press(KEY_TAB)
	b.tools.play_as(me, true)
	await frames(2)
	press(KEY_TAB)
	await frames(2)
	check(B3Player.unit == m1 and B3Player.me.fp and b.cam.fp_unit == m1, "⇥ Tab in first person jumps into the nearest teammate (not one a friend is playing)")
	check(not me.player and me.ctl == null, "and the computer takes over the one you left")
	press(KEY_TAB)
	await frames(2)
	check(B3Player.unit == m2 and b.cam.fp_unit == m2, "Tab again: the next nearest")
	press(KEY_N)
	await frames(2)
	check(B3Player.unit == tk and b.cam.first_person(), "N does it too, and a tank is fair game")
	press(KEY_TAB)
	await frames(2)
	check(B3Player.active() and B3Player.unit != tk and B3Player.unit != taken, "after everyone, round again (now the %s)" % B3Player.unit.kind)
	check(b.ui.palette.visible == false, "(the Toy Box stays out of the way in first person)")
	# overhead too
	b.tools.set_first_person(false)
	var cur: B3Unit = B3Player.unit
	press(KEY_TAB)
	await frames(2)
	check(B3Player.active() and B3Player.unit != cur and not B3Player.me.fp and b.cam.follow == B3Player.unit, "overhead, Tab jumps too and the camera follows your new fighter")
	B3Player.detach(taken)
	b.tools.stop_playing()
	# nobody else on your side
	await fresh()
	var solo: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	b.spawn_unit("soldier", "blue", at(0, 30), "peaceful")
	await sim(0.3)
	b.tools.play_as(solo)
	press(KEY_TAB)
	await frames(2)
	check(B3Player.unit == solo, "with nobody else on your team, Tab leaves you where you are")
	b.tools.stop_playing()


# ------------------------------------------------------- 🛡️ block or swing
## Holding up the shield and swinging at the same time was 90% off every hit
## while swinging at full speed. Now it's one or the other.
func _shield_rhythm() -> void:
	print("🛡️ block or swing, not both")
	await fresh()
	var me: B3Unit = b.spawn_unit("knight", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("viking", "blue", at(0, 1.6), "peaceful", PI)
	foe.max_hp = 5000.0
	foe.hp = 5000.0
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position)
	await sim(0.2)
	me.cd = 0.0
	B3Player.me.fire2 = true
	B3Player.me.fire = true
	var swung := false
	var end: float = b.time + 1.5
	while b.time < end:
		swung = swung or me.act == "attack"
		await get_tree().physics_frame
	check(me.shield_up and not swung and foe.hp == foe.max_hp, "holding both buttons: the shield stays up and the knight can't swing")
	check(B3Player.power_help(me).contains("let go to swing"), "(the help line says so: \"%s\")" % B3Player.power_help(me))
	var up_hit := func() -> float:
		var h0: float = me.hp
		me._block_t = 0.0
		me.hurt(20.0, -me.forward(), 1.0)
		var d: float = h0 - me.hp
		me.hp = me.max_hp
		return d
	var blocked: float = up_hit.call()
	B3Player.me.fire2 = false
	var went: bool = await wait_for(func(): return me.act == "attack", 1.0)
	check(went and not me.shield_up, "let go of right-click: it swings, with the shield down")
	B3Player.me.fire2 = true      # right-click again, mid-swing
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mid_swing: bool = me.act == "attack" and not me.shield_up
	var open_hit: float = up_hit.call()
	check(mid_swing, "right-click mid-swing: the shield stays down until the swing is over")
	check(open_hit > blocked * 2.5, "so a hit from the front mid-swing gets through (%.1f vs %.1f blocked)" % [open_hit, blocked])
	B3Player.me.fire = false
	var back_up: bool = await wait_for(func(): return me.act == "" and me.shield_up, 2.0)
	check(back_up, "and it comes back up once the swing is done")
	b.tools.set_first_person(true)
	B3Player.me.fire2 = false
	await frames(2)
	B3Player.me.fire = true
	await wait_for(func(): return me.act == "attack", 1.0)
	B3Player.me.fire2 = true
	await frames(3)
	var hands: B3FPView = b.cam.hands
	check(me.act != "attack" or (hands.shield != null and hands._guard < 0.99), "👀 in first person you don't see it up while you swing either")
	B3Player.me.fire = false
	B3Player.me.fire2 = false
	b.tools.stop_playing()


# ------------------------------------------------- 🦍 first person, mid-air
func _gorilla_fp() -> void:
	print("🦍 first person: it pounds whoever's close")
	await fresh()
	var me: B3Unit = b.spawn_unit("gorilla", "red", at(0, 0), "peaceful", 0.0)
	var n1: B3Unit = b.spawn_unit("soldier", "blue", at(0.6, 2.6), "peaceful")
	b.spawn_unit("knight", "blue", at(0, 80), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	b.fighting = false
	me.cd = 99.0
	B3Player.me.look_yaw = 0.0
	B3Player.me.look_pitch = 0.05      # looking ahead: the crosshair is far away
	await frames(4)
	var far_aim: float = flat_dist(B3Player.me.aim, me.position)
	B3Player.me.fire2 = true
	var acted: bool = await wait_for(func(): return me.act == "pound" or me.act == "hurl", 1.0)
	var what: String = me.act
	B3Player.me.fire2 = false
	check(far_aim > 6.5 and acted and what == "pound", "looking ahead, an enemy close in front: a ground pound, not a boulder (crosshair %.0f m away: %s)" % [far_aim, what])
	await wait_for(func(): return me.power_cd <= 0.0 and me.act == "", 6.0)
	b.remove_unit(n1, false)
	await sim(0.2)
	B3Player.me.fire2 = true
	acted = await wait_for(func(): return me.act == "pound" or me.act == "hurl", 1.0)
	what = me.act
	B3Player.me.fire2 = false
	check(acted and what == "hurl", "nobody close: a boulder where you look (%s)" % what)
	await wait_for(func(): return me.power_cd <= 0.0 and me.act == "", 7.0)
	b.tools.stop_playing()
	# in mid-air: nothing until its feet are back on the ground
	for k in ["gorilla", "trex"]:
		await fresh()
		var u: B3Unit = b.spawn_unit(k, "red", at(0, 0), "peaceful", 0.0)
		b.spawn_unit("soldier", "blue", at(0, 3.5), "peaceful")
		await sim(0.4)
		b.tools.play_as(u)
		b.fighting = false
		aim_at(u.position + Vector3(0, 0, 3))
		u.cd = 99.0
		await sim(0.2)
		u.linear_velocity.y = 8.0
		var up: bool = await wait_for(func(): return not u._grounded and u.position.y > b.world.height_at(u.position.x, u.position.z) + 0.4, 0.6)
		B3Player.me.fire2 = true
		var in_air := false
		var guard := 0
		while not u._grounded and guard < 2000:
			in_air = in_air or u.act in ["pound", "hurl", "roar"]
			await get_tree().physics_frame
			guard += 1
		var landed: bool = await wait_for(func(): return u.act in ["pound", "hurl", "roar"], 1.0)
		B3Player.me.fire2 = false
		check(up and not in_air, "%s: right-click in mid-jump does nothing" % k)
		check(landed, "%s: it goes off once it lands" % k)
		b.tools.stop_playing()


# ---------------------------------------------------- 🔭 knocked down
func _scope_down() -> void:
	print("🔭 knocked down, the scope comes out")
	await fresh()
	var me: B3Unit = b.spawn_unit("sniper", "red", at(0, 0), "peaceful", 0.0)
	b.spawn_unit("knight", "blue", at(0, 40), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	b.fighting = false
	await frames(2)
	right_click()
	var zoomed: bool = await wait_for(func(): return b.cam.cam.fov < 26.0, 2.0)
	check(zoomed and B3Player.scoped(me, B3Player.me), "(looking through the scope)")
	me.knock_down(Vector3(0, 3, -3))
	check(me.down and not B3Player.scoped(me, B3Player.me), "knocked down: not looking through the scope any more")
	var out: bool = await wait_for(func(): return b.cam.cam.fov > 71.5 and not b.cam._scope.visible, 2.0)
	check(out and not B3Player.me.fire2, "the view zooms back out (%.0f°) and the scope stays out" % b.cam.cam.fov)
	b.tools.stop_playing()


# ------------------------------------------------ ⇥ Tab: who's skipped
func _tab_skips() -> void:
	print("⇥ Tab skips teammates lying down and planes going down")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var lying: B3Unit = b.spawn_unit("knight", "red", at(2, 0), "peaceful", 0.0)
	var pl: B3Unit = b.spawn_unit("plane", "red", at(4, 0), "peaceful", 0.0)
	var mate: B3Unit = b.spawn_unit("archer", "red", at(14, 0), "peaceful", 0.0)
	b.spawn_unit("soldier", "blue", at(0, 70), "peaceful")
	await sim(0.5)
	lying.knock_down(Vector3(0, 2, 0))
	pl.hurt(99999.0, Vector3.UP, 1.0, null, "blast")
	await sim(0.1)
	check(lying.down and pl is B3Aircraft and (pl as B3Aircraft).falling and not pl.dead, "(a knight lies knocked down, and the plane's going down)")
	b.tools.play_as(me, true)
	await frames(2)
	press(KEY_TAB)
	await frames(2)
	check(B3Player.unit == mate, "Tab jumps past both of them to the archer farther away (%s)" % (B3Player.unit.kind if B3Player.active() else "nobody"))
	press(KEY_TAB)
	await frames(2)
	check(B3Player.unit == me, "and round again: never into either of them")
	# knocked out: into the teammate lying down (who'll get up), not the crashing plane
	b.remove_unit(mate, false)
	await sim(0.05)
	me.hurt(99999.0, Vector3.UP, 1.0, null, "blast")
	await frames(3)
	check(B3Player.active() and B3Player.unit == lying, "knocked out, you'd still rather jump into a teammate lying down than a crashing plane (%s)" % (B3Player.unit.kind if B3Player.active() else "nobody"))
	b.tools.stop_playing()


# ------------------------------------------- ⏳ the power's cooldown gauges
func _gauges() -> void:
	print("⏳ the power's cooldown: a pill overhead, a ring in first person")
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful", 0.0)
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(0, 1.4), "peaceful", PI)
	foe.max_hp = 5000.0
	foe.hp = 5000.0
	await sim(0.3)
	b.tools.play_as(me)
	b.fighting = false
	aim_at(foe.position + Vector3(0, 0, 4))
	me.cd = 99.0
	await frames(3)
	var pill = b.ui.power_pill
	check(pill.visible and B3Player.power_ready(me) == 1.0 and String(pill.lbl.text).contains("ready"), "overhead, a pill says the kick is ready (\"%s\")" % pill.lbl.text)
	var pr: Rect2 = pill.get_global_rect()
	var lr: Rect2 = b.ui.play_lbl.get_global_rect()
	check(pr.position.y >= lr.end.y - 1.0 and b.ui.toasts.position.y >= pr.end.y and absf(pr.get_center().x - lr.get_center().x) < 2.0,
		"right under the help line, with messages under it (%.0f, %.0f)" % [pr.position.y, b.ui.toasts.position.y])
	B3Player.me.fire2 = true
	await wait_for(func(): return me.act == "kick", 1.0)
	B3Player.me.fire2 = false
	await frames(2)
	var k0: float = B3Player.power_ready(me)
	check(k0 < 0.3 and pill.k < 0.3 and not String(pill.lbl.text).contains("ready"), "kicking empties it (%.2f)" % k0)
	await sim(0.6)
	await frames(2)
	var k1: float = B3Player.power_ready(me)
	check(k1 > k0 + 0.2 and k1 < 1.0 and absf(pill.k - k1) < 0.15, "it fills up as the kick recharges (%.2f)" % k1)
	await wait_for(func(): return B3Player.power_ready(me) >= 1.0, 3.0)
	await frames(2)
	check(pill.k >= 1.0 and String(pill.lbl.text).contains("ready") and pill.glow_t > 0.0, "until it's ready again, with a glow")
	# first person: a ring round the crosshair instead
	b.tools.set_first_person(true)
	B3Player.me.look_yaw = me.facing
	B3Player.me.look_pitch = -0.1
	await frames(3)
	var ch = b.ui.crosshair
	check(not pill.visible and ch.visible and ch.power_k >= 1.0, "👀 first person: no pill, the ring round the crosshair shows it")
	B3Player.me.fire2 = true
	await wait_for(func(): return me.act == "kick", 1.0)
	B3Player.me.fire2 = false
	await frames(2)
	check(ch.power_k < 0.3, "the ring empties when you kick (%.2f)" % ch.power_k)
	await wait_for(func(): return B3Player.power_ready(me) >= 1.0, 3.0)
	await frames(2)
	check(ch.power_k >= 1.0 and ch.ping_t > 0.0, "and pings when it's ready again")
	b.tools.stop_playing()
	# a knight's shield is held, not used up: no pill or ring
	var kn: B3Unit = b.spawn_unit("knight", "red", at(-8, 0), "peaceful", 0.0)
	await sim(0.2)
	b.tools.play_as(kn)
	await frames(3)
	check(not pill.visible and not B3Player.power_has_cd(kn), "🛡️ a shield has no cooldown: no pill")
	b.tools.stop_playing()
	# ⏳ the reload bar: a musket takes a while
	var rc: B3Unit = b.spawn_unit("redcoat", "red", at(8, 0), "peaceful", 0.0)
	var tgt: B3Unit = b.spawn_unit("knight", "blue", at(8, 14), "peaceful", PI)
	tgt.max_hp = 5000.0
	tgt.hp = 5000.0
	await sim(0.3)
	b.tools.play_as(rc, true)
	await frames(2)
	check(ch.reload_k >= 1.0, "(loaded)")
	look_at_point(tgt.center())
	await frames(2)
	B3Player.me.fire = true
	var shot: bool = await wait_for(func(): return rc.cd > 1.0, 1.0)
	B3Player.me.fire = false
	await frames(2)
	var r0: float = ch.reload_k
	await sim(1.5)
	await frames(2)
	check(shot and r0 < 0.2 and ch.reload_k > r0 + 0.2 and ch.reload_k < 1.0, "🔄 firing the musket shows a reload bar under the crosshair, filling up (%.2f → %.2f)" % [r0, ch.reload_k])
	await wait_for(func(): return rc.cd <= 0.0, 4.0)
	await frames(2)
	check(ch.reload_k >= 1.0, "gone once it's loaded again")
	b.tools.stop_playing()
	# 👥 a friend's copy only knows what the host sends
	var g: PackedFloat32Array = B3Player.net_gauges(me)
	check(g.size() == 2 and g[0] >= 1.0 and absf(g[1] - B3Player.reload_ready(me)) < 0.01, "the host sends two numbers for a friend's fighter: power and reload (%s)" % str(g))
	b.puppet = true
	check(B3Player.power_ready(me) == 1.0, "a friend's copy reads ready until told otherwise")
	B3Player.set_net_gauges(me, PackedFloat32Array([0.25, 0.5]))
	var got := [B3Player.power_ready(me), B3Player.reload_ready(me)]
	B3Player.set_net_gauges(me, [NAN, "junk", 7.0])
	var junk := [B3Player.power_ready(me), B3Player.reload_ready(me)]
	b.puppet = false
	check(got == [0.25, 0.5], "then shows what the host sent (%s)" % str(got))
	check(junk == [1.0, 1.0], "and junk reads as ready (%s)" % str(junk))

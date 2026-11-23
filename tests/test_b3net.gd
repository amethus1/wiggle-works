extends Node
## 👥 3D Battle together: a host battle and a friend's battle talk over this
## computer's network. The friend's battle lives in its own SubViewport (its
## own 3D world and physics), like a second computer would.
## godot --headless --path . -- --test=b3net

var fails := 0
var host = null
var friend = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func wait_for(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func at(b, x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


## True if the friend is playing a red fighter on the host (other than the one with id `but`).
func friend_plays_red(but: int) -> bool:
	for u: B3Unit in host.units:
		if u.get_instance_id() != but and not u.dead and u.team == "red" and u.ctl != null and u.ctl.peer != 0:
			return true
	return false


func alive(b) -> int:
	var n := 0
	for u: B3Unit in b.units:
		if not u.dead:
			n += 1
	return n


## Numbers of the trees and rocks still standing in a battle.
func standing(b) -> Dictionary:
	var out := {}
	for n in b.world.scenery.get_children():
		if n.has_meta("sid") and not n.has_meta("gone") and not n.is_queued_for_deletion():
			out[int(n.get_meta("sid"))] = true
	return out


## The friend's airstrike plane copy, if one is flying.
func friend_plane() -> Node3D:
	for n in friend.net.puppets.values():
		if is_instance_valid(n) and (n as Node).has_meta("plane"):
			return n
	return null


## What the 💣 Detonate button says.
func c4_text(b) -> String:
	if b.ui == null or b.ui.c4_btn == null:
		return ""
	return String((b.ui.c4_btn.get_child(0).get_node("Name") as Label).text)


func c4_props(b) -> Array:
	return b.props.filter(func(p): return is_instance_valid(p) and p.kind == "c4")


## True if a message with `txt` in it is showing at the top of `b`'s screen.
func toast_has(b, txt: String) -> bool:
	for c in b.ui.toasts.get_children():
		for l in (c as Node).find_children("*", "Label", true, false):
			if String((l as Label).text).contains(txt):
				return true
	return false


## How many 👑 Kings with a crown on their head there are in `b`.
func crowned_kings(b) -> int:
	var n := 0
	for u: B3Unit in b.units:
		if is_instance_valid(u) and not u.dead and u.king and u.rig and u.rig.pv.get("head") and (u.rig.pv.head as Node).get_node_or_null("Crown"):
			n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	host = load("res://battle3d/battle3d.gd").new()
	add_child(host)
	host.begin({"seed": 5, "map": "grassland"})
	check(host.start_hosting() and host.net.is_host(), "👥 the host starts sharing the battle")
	for i in 4:
		host.spawn_unit("soldier", "red", at(host, -8, i * 2.0 - 3.0), "peaceful", PI * 0.5)
		host.spawn_unit("knight", "blue", at(host, 8, i * 2.0 - 3.0), "peaceful", -PI * 0.5)
	var tank: B3Unit = host.spawn_unit("tank", "red", at(host, -14, 8), "peaceful", 2.0)
	var wall: B3Struct = host.spawn_struct("wall", at(host, 0, -10), 0.0, 8.0)
	host.spawn_prop("xbarrel", at(host, 3, 6))
	host.spawn_hazard("lava", at(host, 0, 14), 3.0)
	# a blast knocked some trees over before the friend came
	var knocked: Array = []
	for n in host.world.scenery.get_children():
		if n.has_meta("sid") and knocked.size() < 3:
			knocked.append(int(n.get_meta("sid")))
			host.world.uproot(n, Vector3(0, 3, 0), host)

	# the friend's computer
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(640, 360)
	add_child(vp)
	friend = load("res://battle3d/battle3d.gd").new()
	vp.add_child(friend)
	friend.begin({"seed": 9, "map": "desert", "net": "client", "ip": "127.0.0.1"})
	check(friend.puppet and friend.net and friend.net.is_client(), "a friend starts joining")
	check(await wait_for(func(): return friend.net.connected and host.net.friends.size() == 1, 5.0), "the friend connects and the host sees them")
	check(await wait_for(func(): return friend.map_id == "grassland", 3.0), "the friend's battle switches to the host's map")
	check(await wait_for(func(): return alive(friend) == alive(host), 3.0), "the friend sees every fighter and vehicle (%d vs %d)" % [alive(friend), alive(host)])
	check(await wait_for(func(): return friend.structs.size() == 1 and friend.props.size() == 1, 2.0), "and the wall and the barrel")
	check(await wait_for(func(): return friend.hazards.size() == host.hazards.size(), 2.0), "and the lava pool")
	var match_ok := true
	for u: B3Unit in host.units:
		var p = friend.net.puppets.get(u.get_instance_id())
		if not (p is B3Unit) or (p as B3Unit).global_position.distance_to(u.global_position) > 0.6 or (p as B3Unit).kind != u.kind:
			match_ok = false
	check(match_ok, "each in the same place on both screens")
	var ws: B3Struct = friend.structs[0]
	check(ws.pieces.size() == wall.pieces.size(), "the wall is built the same, brick for brick (%d)" % ws.pieces.size())
	await wait_for(func(): return false, 0.1)
	var hs_trees := standing(host)
	var fs_trees := standing(friend)
	var gone_ok := knocked.size() == 3 and fs_trees.size() == hs_trees.size()
	for sid in knocked:
		if fs_trees.has(sid):
			gone_ok = false
	check(gone_ok, "🌳 trees knocked over before the friend joined are gone on their screen too (%d standing on both)" % fs_trees.size())
	var ft0: B3Unit = friend.net.puppets.get(tank.get_instance_id())
	check(ft0 != null and absf(angle_difference(ft0.facing, tank.facing)) < 0.1 and absf(tank.facing - 2.0) < 0.1,
		"a vehicle faces the same way on the friend's screen (%.2f vs %.2f)" % [ft0.facing if ft0 else 0.0, tank.facing])
	check(friend.ui.map_btn.disabled and friend.ui.rules_btn.disabled and not friend.ui.play_btn.disabled, "the friend can't change the map or rules, but can press Fight!")

	# the friend places a fighter from their Toy Box
	var before: int = alive(host)
	friend.tools.place_id = "viking"
	friend.tools.team = "green"
	friend.tools._place(at(friend, 0, 0), at(friend, 0, 0), false, false)
	check(await wait_for(func(): return alive(host) == before + 1, 3.0), "a friend's placed viking appears in the host's battle")
	check(await wait_for(func(): return alive(friend) == before + 1, 3.0), "and on the friend's screen")

	# the friend plays a soldier
	var hs: B3Unit = host.units[0]
	var fs: B3Unit = friend.net.puppets.get(hs.get_instance_id())
	friend.tools.play_as(fs)
	check(await wait_for(func(): return hs.ctl != null and hs.ctl.peer != 0, 3.0), "🎮 the friend takes control of a soldier")
	check(host.fighting, "which starts the battle")
	check(await wait_for(func(): return friend.fighting, 2.0), "on both screens")
	# (both battles share this computer's keyboard; on real computers each has its own)
	host.tools.set_process(false)
	var start: Vector3 = hs.global_position
	var kw := InputEventKey.new()
	kw.keycode = KEY_W
	kw.physical_keycode = KEY_W
	kw.pressed = true
	Input.parse_input_event(kw)
	await wait_for(func(): return false, 1.2)
	var ku := kw.duplicate() as InputEventKey
	ku.pressed = false
	Input.parse_input_event(ku)
	var moved := Vector2(hs.global_position.x - start.x, hs.global_position.z - start.z).length()
	check(moved > 2.0, "the friend's W key walks the host's soldier (%.1f m)" % moved)
	check(await wait_for(func(): return fs.global_position.distance_to(hs.global_position) < 0.8, 2.0), "and the friend sees it move")
	check(host.net._tags.size() == 1, "the host sees the friend's name over that soldier")

	# the friend drives the tank
	friend.tools.stop_playing()
	await wait_for(func(): return hs.ctl == null, 2.0)
	var ft: B3Unit = friend.net.puppets.get(tank.get_instance_id())
	friend.tools.play_as(ft)
	check(await wait_for(func(): return tank.ctl != null and tank.ctl.peer != 0, 3.0), "🚜 the friend climbs into the tank")
	var tstart: Vector3 = tank.global_position
	Input.parse_input_event(kw)
	await wait_for(func(): return false, 2.0)
	Input.parse_input_event(ku)
	var tmoved := Vector2(tank.global_position.x - tstart.x, tank.global_position.z - tstart.z).length()
	check(tmoved > 1.5, "and drives it with W (%.1f m)" % tmoved)
	check(await wait_for(func(): return ft.global_position.distance_to(tank.global_position) < 1.0, 2.0), "the tank moves on the friend's screen too")
	friend.tools.stop_playing()
	await wait_for(func(): return tank.ctl == null, 2.0)
	await wait_for(func(): return absf(angle_difference(ft.facing, tank.facing)) < 0.05, 1.0)
	var tank_yaw: float = tank.facing
	var body_z: Vector3 = ft.global_basis.z
	friend.tools.play_as(ft, true)
	var look_yaw: float = B3Player.me.look_yaw
	# (it may still be turning a little, and the friend's copy is a moment behind)
	check(absf(angle_difference(look_yaw, atan2(body_z.x, body_z.z))) < 0.05 and absf(angle_difference(look_yaw, tank_yaw)) < 0.4
		and absf(angle_difference(tank_yaw, 2.0)) > 0.5,
		"👀 in first person, the friend looks out the way the tank faces (%.2f vs %.2f)" % [look_yaw, tank_yaw])
	await wait_for(func(): return tank.ctl != null and tank.ctl.peer != 0, 3.0)
	friend.tools.stop_playing()

	# knocked out in first person: the friend jumps into a teammate
	var hv: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "red" and u.kind == "soldier" and not u.dead:
			hv = u
			break
	friend.tools.play_as(friend.net.puppets.get(hv.get_instance_id()), true)
	check(await wait_for(func(): return hv.ctl != null and hv.ctl.peer != 0, 3.0), "👀 the friend plays a soldier in first person")
	var hv_id := hv.get_instance_id()
	hv.hurt(99999.0, Vector3.UP, 1.0)
	check(await wait_for(func(): return friend_plays_red(hv_id), 4.0), "💫 when it's knocked out, the friend jumps into a teammate")
	check(B3Player.active() and B3Player.me.fp and friend.cam.first_person(), "and is still in first person")
	friend.tools.stop_playing()
	await wait_for(func(): return not friend_plays_red(0), 2.0)

	# right-click powers and ⇥ Tab work for friends too
	var hk: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "blue" and u.kind == "knight" and not u.dead and not u.down:
			hk = u
			break
	var fk: B3Unit = friend.net.puppets.get(hk.get_instance_id())
	friend.tools.play_as(fk)
	check(await wait_for(func(): return hk.ctl != null and hk.ctl.peer != 0, 3.0), "🛡️ the friend plays a knight")
	B3Player.me.fire2 = true
	check(await wait_for(func(): return hk.shield_up, 2.0), "holding right-click raises its shield in the host's battle")
	check(await wait_for(func(): return fk.shield_up, 2.0), "and the friend sees it up")
	B3Player.me.fire2 = false
	check(await wait_for(func(): return not hk.shield_up and not fk.shield_up, 2.0), "letting go lowers it on both screens")
	var hk_id := hk.get_instance_id()
	friend.tools.switch_teammate()
	var next_knight := func() -> bool:
		for u: B3Unit in host.units:
			if u.get_instance_id() != hk_id and u.team == "blue" and not u.dead and u.ctl != null and u.ctl.peer != 0:
				return hk.ctl == null
		return false
	check(await wait_for(next_knight, 3.0), "⇥ Tab on the friend's screen asks the host, and they jump into the next knight")
	check(B3Player.active() and B3Player.unit != fk, "(and the friend's camera goes with them)")
	friend.tools.stop_playing()
	await wait_for(func(): return not next_knight.call() and hk.ctl == null, 2.0)

	# ⇥ Tab into a teammate someone else has just taken: the host says no, and
	# the friend looks out of the one they really steer again (not a stranger's)
	var ka: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "blue" and not u.dead and not u.down and u.ctl == null:
			ka = u
			break
	var fa: B3Unit = friend.net.puppets.get(ka.get_instance_id())
	friend.tools.play_as(fa)
	check(await wait_for(func(): return ka.ctl != null and ka.ctl.peer != 0, 3.0), "the friend plays a blue knight")
	friend.tools._round.clear()
	B3Player.last_pos = fa.global_position
	var fnext: B3Unit = friend.tools.next_teammate([fa.get_instance_id()], false)
	var hnext: B3Unit = host.unit_by_id(int(fnext.get_meta("nid", 0))) if fnext else null
	var stranger := B3Ctl.new()
	stranger.peer = 999
	if hnext:
		B3Player.attach(hnext, stranger)      # (someone else got there first)
	friend.tools.switch_teammate()
	check(B3Player.unit == fnext, "⇥ Tab on the friend's screen jumps to the next knight straight away")
	check(await wait_for(func(): return B3Player.unit == fa and friend.cam.follow == fa and toast_has(friend, "already playing"), 3.0),
		"⇥ that one was taken: the host says so, and the friend's camera goes back to the knight they steer")
	check(ka.ctl != null and ka.ctl.peer != 0 and hnext != null and hnext.ctl == stranger, "(still theirs on the host, and the other one still the other player's)")
	if hnext:
		B3Player.detach(hnext)
	friend.tools.stop_playing()
	await wait_for(func(): return ka.ctl == null, 2.0)

	# presses that happen once are counted: a jump whose packet got lost, or a
	# right-click let go before the next packet, still happen on the host
	var tf := {}
	var tc := B3Ctl.new()
	B3Net._count_taps(tf, tc, 0)
	B3Net._count_taps(tf, tc, 0)
	var calm := not tc.jump and not tc.fire and not tc.fire2
	B3Net._count_taps(tf, tc, 1 | (1 << 16))
	check(calm and tc.jump and tc.fire2 and not tc.fire, "⏫ a jump (and a right-click) in a lost controls packet: the next one's count brings it")
	tc.jump = false
	B3Net._count_taps(tf, tc, 1 | (1 << 16))
	B3Net._count_taps(tf, tc, 255 | (1 << 16))
	var once := not tc.jump
	B3Net._count_taps(tf, tc, 0 | (1 << 16))
	check(once and tc.jump, "and only once, even when the count goes round past 255")
	var hs3: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "red" and u.kind == "soldier" and not u.dead and not u.down and u.ctl == null:
			hs3 = u
			break
	var fs3: B3Unit = friend.net.puppets.get(hs3.get_instance_id())
	friend.tools.play_as(fs3)
	check(await wait_for(func(): return hs3.ctl != null and hs3.ctl.peer != 0, 3.0), "the friend plays a soldier")
	await wait_for(func(): return hs3._grounded and hs3.act == "", 2.0)
	var y0: float = hs3.global_position.y
	friend.net._ctl_t = 10.0          # (hold the next controls packet)
	B3Player.me.jump = true
	await get_tree().process_frame
	await get_tree().process_frame
	friend.net._jumped = false        # (as if the packet saying "jump" was lost: only the count gets there)
	friend.net._ctl_t = 0.0
	var top := [y0]
	check(await wait_for(func():
		top[0] = maxf(top[0], hs3.global_position.y)
		return top[0] > y0 + 0.25, 2.0), "⏫ the jump still happens on the host (up %.2f m)" % (top[0] - y0))
	await wait_for(func(): return hs3._grounded and hs3.act == "" and hs3.power_cd <= 0.0, 3.0)
	friend.net._ctl_t = 10.0
	B3Player.me.fire2 = true
	await get_tree().process_frame
	await get_tree().process_frame
	B3Player.me.fire2 = false         # let go before a packet went
	friend.net._ctl_t = 0.0
	check(await wait_for(func(): return hs3.power_cd > 0.1, 2.0), "👟 a right-click tap quicker than a packet still kicks on the host")
	check(await wait_for(func(): return B3Player.power_ready(fs3) < 0.95, 2.0),
		"⏳ and the friend's power meter shows it recharging (%.2f)" % B3Player.power_ready(fs3))
	check(await wait_for(func(): return B3Player.power_ready(fs3) > 0.99, 8.0), "then ready again")
	# 📒 a knock-out by the fighter a friend plays earns the friend the sticker count
	var kos0 := int(Settings.counters.get("b3_hero_kos", 0))
	var vic: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "blue" and not u.dead:
			vic = u
			break
	vic.hurt(99999.0, Vector3.RIGHT, 1.0, hs3)
	check(await wait_for(func(): return int(Settings.counters.get("b3_hero_kos", 0)) == kos0 + 1, 2.0),
		"📒 the friend's soldier knocks someone out: the friend gets it for 🦸 Hero")
	friend.tools.stop_playing()
	await wait_for(func(): return hs3.ctl == null, 2.0)

	# 🐢 G on a friend's screen is the host's slow motion, for everyone
	var kg := InputEventKey.new()
	kg.keycode = KEY_G
	kg.pressed = true
	friend.tools._key(kg)
	check(await wait_for(func(): return host.slowmo and friend.slowmo, 2.0), "🐢 the friend's G slows the host's battle down, on both screens")
	await wait_for(func(): return false, 0.3)
	check(host.slowmo and friend.slowmo, "and it stays slow (it's the host's)")
	friend.tools._key(kg)
	check(await wait_for(func(): return not host.slowmo and not friend.slowmo, 2.0), "G again: normal speed on both")

	# 🔒 the host can stop friends changing the battle (the 👥 panel's checkbox)
	host.ui._show_net()
	var lock_box = host.ui.get_meta("net_lock", null)
	check(lock_box is CheckBox and is_instance_valid(lock_box) and (lock_box as CheckBox).button_pressed, "the host's 👥 panel has the 🔒 checkbox, ticked")
	if lock_box is CheckBox and is_instance_valid(lock_box):
		(lock_box as CheckBox).button_pressed = false
	check(not host.net.allow_changes, "unticking it locks the battle")
	host.ui.close_top()
	host.net.allow_changes = false
	var n_lock: int = alive(host)
	friend.tools.place_id = "viking"
	friend.tools.team = "green"
	friend.tools._place(at(friend, 2, 2), at(friend, 2, 2), false, false)
	check(await wait_for(func(): return toast_has(friend, "locked"), 2.0) and alive(host) == n_lock, "🔒 locked: a friend's placing is turned away, and they're told why")
	check(await wait_for(func(): return friend.net.host_locked, 1.0), "and the friend's game knows")
	host.net.allow_changes = true
	await wait_for(func(): return not friend.net.host_locked, 1.0)

	# 🟩 a Shift-drag block can be 144 fighters: each one counts against a friend's placing
	await wait_for(func(): return false, 1.0)
	var n_box: int = alive(host)
	for i in 4:
		friend.net.send_cmd({"c": "place", "id": "soldier", "team": "yellow", "pers": "peaceful", "size": 1.0, "a": at(host, -70, -70),
			"b": at(host, -40, -40), "dragged": true, "box": true, "yaw": 0.0})
	await wait_for(func(): return false, 0.8)
	var boxed: int = alive(host) - n_box
	check(boxed >= 100 and boxed <= 2 * 144 + 2, "🟩 four blocks of fighters at once from a friend: only two get made (%d fighters)" % boxed)
	for u: B3Unit in host.units.duplicate():
		if is_instance_valid(u) and u.team == "yellow":
			host.remove_unit(u, false)
	check(await wait_for(func(): return alive(friend) == alive(host), 3.0), "(and they go away again on both screens)")

	# knock-outs and broken walls show up too
	var victim: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "blue":
			victim = u
			break
	var vid: int = victim.get_instance_id()
	victim.hurt(9999.0, Vector3(1, 0, 0), 10.0)
	check(await wait_for(func(): return friend.net.corpses.has(vid), 3.0), "a knocked-out knight becomes a ragdoll with X eyes on the friend's screen")
	var pieces_before: int = ws.pieces.size()
	host.explode(wall.global_position + Vector3(0, 1.0, 0), 4.0, 20.0, 200.0)
	check(await wait_for(func(): return ws.pieces.size() < pieces_before, 3.0), "a blast breaks the same wall on both screens (%d → %d)" % [pieces_before, ws.pieces.size()])
	check(friend.net.fx_played > 0, "explosions, shots and sounds play on the friend's screen (%d)" % friend.net.fx_played)
	host.remove_unit(tank)
	check(await wait_for(func(): return friend.units.filter(func(u): return u.kind == "tank" and not u.dead).is_empty(), 2.0), "erasing on the host erases on the friend's screen")

	# 🔥 a wooden tower catching fire burns on the friend's screen too, and 🪂 parachutes float down there
	var htw: B3Struct = host.spawn_struct("tower", at(host, -30, -30), 0.0)
	check(await wait_for(func(): return friend.structs.size() == host.structs.size(), 3.0), "(the friend gets a wooden tower)")
	await wait_for(func(): return false, 1.2)      # (a friend's new building is left alone for its first second)
	var fire_ok: bool = host.fighting and B3Fire.of(host).ignite(htw.pieces[0])
	check(fire_ok and await wait_for(func(): return B3Fire.of(friend).burning.size() == 1, 2.0), "🔥 a tower catching fire burns on the friend's screen too")
	host.fx.chute(at(host, -30, 30) + Vector3(0, 20, 0), Vector3(0, 8, 0), Color.RED)
	check(await wait_for(func(): return friend.fx.get_children().any(func(c): return c is B3Chute), 2.0), "🪂 a pilot's parachute floats down on the friend's screen")
	B3Fire.of(host).put_out()
	host.remove_struct(htw, false)

	# ✈️ an airstrike's plane flies over on the friend's screen too
	host.airstrike(at(host, 0, 70), Vector3.RIGHT)
	var hplane: Node3D = (host.planes[0] as Dictionary).node
	check(await wait_for(func(): return friend_plane() != null and friend_plane().global_position.distance_to(hplane.global_position) < 8.0, 2.0),
		"✈️ the friend sees the airstrike plane, where the host's is")

	# 📟 C4: the Detonate button counts the same
	host.spawn_prop("c4", at(host, 40, -40))
	host.spawn_prop("c4", at(host, 42, -40))
	check(await wait_for(func(): return c4_text(friend) == "Boom! (2)", 2.0), "📟 the friend's Detonate button counts the host's C4 (%s)" % c4_text(friend))
	for p in c4_props(host):
		p.trigger(30.0)
	check(await wait_for(func(): return c4_text(friend) == "Detonate", 2.0), "and goes back once they're lit (%s)" % c4_text(friend))
	for p in c4_props(host):
		host.remove_prop(p, false)

	# ☢️ a nuke flashes and shakes the friend's screen like the host's
	friend.cam.trauma = 0.0
	friend.net._play_fx(["nuke", at(friend, 90, 90)])
	check(friend.ui._flash > 0.5 and friend.cam.trauma > 0.5, "☢️ a nuke flashes and shakes the friend's screen too")
	friend.ui._flash = 0.0
	host.net.rec_fx(["nuke", at(host, 90, 90)])
	check(await wait_for(func(): return friend.ui._flash > 0.5, 2.0) and not host.net.snapshot().has("fx"),
		"☢️ the host's nuke flash comes over on its own reliable channel (not in a snapshot that could get lost)")

	# effects the friend's copy already made itself aren't played twice
	var skipped: int = friend.net.fx_skipped
	var played: int = friend.net.fx_played
	friend.snd("boing", at(friend, 5, 5), 0.5)
	friend.net._play_fx(["snd", "boing", at(friend, 5.5, 5), 0.5, 1.2])
	check(friend.net.fx_skipped == skipped + 1 and friend.net.fx_played == played, "🔁 a sound the friend's screen just made isn't played again when the host's arrives")
	friend.net._play_fx(["snd", "boing", at(friend, 5.5, 5), 0.5, 1.2])
	friend.net._play_fx(["dust", at(friend, 5, 5), 1.0])
	check(friend.net.fx_played == played + 2, "but the next one (and other effects) still are")

	# only real effects, with sensible values, are played from the host
	played = friend.net.fx_played
	for e in [["queue_free"], ["_fx_nuke", Vector3.ZERO], ["set_script", null], ["clear"], ["explosion", "boom", 1.0, 0],
			["explosion", Vector3(NAN, 0, 0), 1.0, 0], ["poof", Vector3.ZERO], ["word", Vector3.ZERO, 5, Color.WHITE],
			["snd", 5, null, 1.0, 1.0], ["snd", "boom", "here", 1.0, 1.0], ["shake", INF, null], [42], []]:
		friend.net._play_fx(e)
	check(friend.net.fx_played == played and is_instance_valid(friend.fx) and not friend.fx.is_queued_for_deletion(),
		"🛡️ unknown or broken effects from the host are ignored")
	friend.net._play_fx(["poof", at(friend, 3, 3), 1.0])
	check(friend.net.fx_played == played + 1, "and real ones still play")

	# the host's rules come over, but your own Screen shake stays yours
	B3Rules.values["shake"] = "off"
	var hr: Dictionary = B3Net._host_rules({"gravity": "moon", "shake": "lots", "booms": "kaboom", "weird": "x"})
	check(hr.get("shake") == "off" and hr.get("gravity") == "moon" and hr.get("booms") == "normal" and not hr.has("weird"),
		"📳 a friend keeps their own Screen shake; made-up rules are ignored")
	B3Rules.values["shake"] = "little"

	# 🛡️ a broken (or naughty) copy of the game sends junk: the host ignores it
	var fid: int = host.net.friends.keys()[0]
	var n_alive: int = alive(host)
	var a_red: B3Unit = null
	for u: B3Unit in host.units:
		if u.team == "red" and not u.dead:
			a_red = u
			break
	var fp_u: B3Unit = friend.net.puppets.get(a_red.get_instance_id())
	var junk: Array = [
		{"c": "erase", "nid": fp_u.get_instance_id()}, {"c": "erase", "nid": host.get_instance_id()}, {"c": "erase", "nid": "lots"},
		{"c": "erase", "nid": friend.get_instance_id()}, {"c": "play", "nid": fp_u.get_instance_id()},
		{"c": "place", "id": "viking", "team": "purple", "pers": "auto", "a": at(host, 0, 0), "b": at(host, 0, 0)},
		{"c": "place", "id": "laser_shark", "team": "red", "pers": "auto", "a": at(host, 0, 0), "b": at(host, 0, 0)},
		{"c": "place", "id": "viking", "team": "red", "pers": "auto", "a": Vector3(NAN, 0, 0), "b": at(host, 0, 0)},
		{"c": "place", "id": "viking", "team": "red", "pers": "auto", "a": "here", "b": at(host, 0, 0), "yaw": INF},
		{"c": "drop", "id": "grenade", "pos": "here"}, {"c": "drop", "id": "blackhole", "pos": at(host, 0, 0)},
		{"c": "drop", "id": "grenade", "pos": Vector3(0, INF, 0)},
		{"c": "team", "nid": a_red.get_instance_id(), "t": "purple"}, {"c": "mood", "nid": a_red.get_instance_id(), "p": "evil"},
		{"c": "wave"}, {"c": "wave", "n": 99}, {"c": 5}, {"c": ["fight"]}, {}]
	for c in junk:
		friend.net._send({"m": "cmd", "c": c}, true)
	friend.net._send({"m": "cmd", "c": "erase"}, true)
	for a in [[NAN, 0, 0, 0, 0, Vector3.ZERO, 0.0, 0.0, 0], [0, 0, 0, 0, 0, Vector3(INF, 0, 0), 0.0, 0.0, 0],
			[0, 0, 0, 0, 0, Vector3.ZERO, "left", 0.0, 0], [1, 2, 3], "go"]:
		friend.net._send({"m": "ctl", "a": a}, false)
	friend.net._send({"m": "hello", "v": B3Net.VERSION, "name": ["x"]}, true)
	for pkt in [PackedByteArray([9, 9, 9]), PackedByteArray([0, 1, 2]), PackedByteArray([1, 0, 0, 0, 2, 7, 7])]:
		friend.net.mp.send_bytes(pkt, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)
	await wait_for(func(): return false, 0.6)
	var ctl: B3Ctl = host.net.friends[fid].ctl
	check(alive(host) == n_alive and is_instance_valid(fp_u) and not fp_u.dead and a_red.team == "red" and a_red.pers_choice != "evil",
		"🛡️ junk commands from a friend don't change the host's battle (or reach into anyone else's)")
	check(ctl.move.is_finite() and ctl.aim.is_finite() and is_finite(ctl.look_yaw), "and NaN controls are ignored")
	# too many booms at once: some are turned away (and only one nuke)
	var props0: int = host.props.size()
	for i in 5:
		friend.net.send_cmd({"c": "drop", "id": "nuke", "pos": at(host, 60, 60), "dir": Vector3.RIGHT})
	for i in 60:
		friend.net.send_cmd({"c": "drop", "id": "c4", "pos": at(host, -40 + i * 0.5, 40), "dir": Vector3.RIGHT})
	await wait_for(func(): return false, 0.6)
	var c4_made: int = host.props.size() - props0
	var nukes: Array = host.proj_root.get_children().filter(func(p): return p is B3Proj and p.kind == "nuke")
	for p in nukes:
		p.queue_free()
	check(nukes.size() == 1, "☢️ five nukes in a row from one friend: just one falls")
	check(c4_made >= 5 and c4_made <= 24, "a flood of drops from one friend is slowed down (%d of 60 C4 made)" % c4_made)
	for p in c4_props(host):
		host.remove_prop(p, false)

	# 🏆 the winner banner and the scoreboard under it come over as data
	for u: B3Unit in host.units.duplicate():
		if is_instance_valid(u) and not u.dead and u.team != "red":
			u.hurt(99999.0, Vector3.UP, 1.0, null, "blast")
	check(await wait_for(func(): return host.winner == "red" and friend.ui.banner_lbl.visible and friend.ui.score_card.visible, 4.0),
		"🏆 the friend sees the winner banner and the scoreboard")
	check(await wait_for(func(): return B3Battle.read_score(friend.net._sb) == B3Battle.read_score(host.scoreboard()) and not friend.net._sb.is_empty(), 2.0),
		"with the same numbers as the host's (%d lines)" % friend.net._sb.size())
	check(String(friend.ui.banner_lbl.text).get_slice("\n", 0) == String(host.ui.banner_lbl.text).get_slice("\n", 0), "and the same headline")

	# 👥 snapshots only carry what changed since the last one the friend got
	var keys0: int = host.net._tx.keyframes
	await wait_for(func(): return false, 0.5)
	check(host.net._tx.keyframes == keys0 and friend.net._rx.got > 50, "📦 the friend gets just the changes, not whole snapshots (%d whole ones since joining)" % keys0)
	friend.net._rx.hist.clear()      # (as if every snapshot it had got lost)
	var mover: B3Unit = null
	for u: B3Unit in host.units:
		if not u.dead and not u.down and not (u is B3Vehicle):
			mover = u
			break
	mover.global_position += Vector3(6, 0, 0)
	check(await wait_for(func(): return host.net._tx.keyframes > keys0, 2.0), "📦 a friend that's lost track asks, and gets a whole snapshot")
	var fm: B3Unit = friend.net.puppets.get(mover.get_instance_id())
	check(await wait_for(func(): return fm != null and fm.global_position.distance_to(mover.global_position) < 0.8, 2.0), "and is right again")
	var full_snap: PackedByteArray = host.net._tx.packet(-1)
	var change_snap: PackedByteArray = host.net._tx.packet(host.net._tx.n - 1)
	print("        3D snapshot: %d bytes whole, %d bytes of changes (%d fighters)" % [full_snap.size(), change_snap.size(), alive(host)])
	check(change_snap.size() < full_snap.size(), "a snapshot of changes is smaller than a whole one")

	# a copy of the game that isn't the same version is told, kindly, on both sides
	var odd := ENetMultiplayerPeer.new()
	odd.create_client("127.0.0.1", B3Net.PORT)
	var omp := SceneMultiplayer.new()
	omp.root_path = get_path()
	omp.multiplayer_peer = odd
	var said := [""]
	omp.peer_packet.connect(func(_id: int, pkt: PackedByteArray):
		var why: Variant = NetCommon.decode(pkt).get("why")
		if why is String:
			said[0] = why)
	omp.connected_to_server.connect(func():
		omp.send_bytes(NetCommon.encode({"m": "hello", "v": B3Net.VERSION - 1, "name": "Old"}), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0))
	check(await wait_for(func():
		omp.poll()
		return said[0] != "", 3.0) and said[0] == NetCommon.WRONG_VERSION, "🔢 a friend with another version is told: %s" % said[0])
	check(toast_has(host, "different version"), "and so is the host")
	odd.close()

	# the host sets up a History battle
	host.run_history("agincourt")
	var hp_count := func(bt) -> int:
		var n := 0
		for st: B3Struct in bt.structs:
			if is_instance_valid(st) and not B3Defs.STRUCTS.has(st.kind):
				n += st.pieces.size()
		return n
	var want_pieces: int = hp_count.call(host)
	check(await wait_for(func(): return alive(friend) == alive(host) and friend.map_id == host.map_id, 4.0), "📜 the friend sees the host's History battle (%d fighters)" % alive(friend))
	check(await wait_for(func(): return hp_count.call(friend) == want_pieces, 4.0), "with its sharpened stakes (%d pieces)" % hp_count.call(friend))
	var same_look := true
	for u: B3Unit in host.units:
		var p = friend.net.puppets.get(u.get_instance_id())
		if p is B3Unit and int((p as B3Unit).get_meta("seed", -1)) != int(u.get_meta("seed", -2)):
			same_look = false
	check(same_look, "and every fighter looks the same on both screens")
	var keep_n: int = host.net._snap_n
	host.net._snap_n = 1     # (the snapshot that carries the stakes' whole shape)
	var snap_bytes := var_to_bytes(host.net.snapshot()).size()
	host.net._snap_n = keep_n
	check(snap_bytes < NetCommon.MAX_UNPACKED / 8, "a big battle's snapshot unpacks well under the size limit (%.0f KB)" % (snap_bytes / 1024.0))

	# Fight! and Pause from the friend
	friend.toggle_play()
	check(await wait_for(func(): return host.fighting, 2.0), "the friend's Fight! starts the host's battle")
	friend.toggle_play()
	check(await wait_for(func(): return host.paused, 2.0), "the friend's Pause pauses the host's battle")
	check(await wait_for(func(): return friend.paused, 2.0), "and their own")
	friend.toggle_play()
	await wait_for(func(): return not host.paused, 2.0)

	# 🌊 Wave Defense: the friend sees the points, the fort and the waves, and helps
	host.run_ready("waves")
	check(await wait_for(func(): return friend.budget == B3Modes.START_POINTS and friend.build_zone == B3Modes.FORT and friend.zone_vis != null, 4.0),
		"🌊 the friend sees the host's 🪙 points and the glowing fort")
	check(await wait_for(func(): return friend.modes.kind == "waves" and friend.modes.phase == "build" and friend.ui.mode_hud.visible and friend.ui.coin_lbl.visible, 2.0), "with the coins at the top and the 🌊 Wave Defense panel")
	var spent0: int = host.spent
	friend.tools.place_id = "soldier"
	friend.tools.team = "green"
	friend.tools._place(at(friend, 0, 10), at(friend, 0, 10), false, false)
	check(await wait_for(func(): return host.spent == spent0 + 2, 3.0), "a friend's soldier in the fort is paid from the host's points")
	# ("🪙 left / budget", or just "🪙 left" when the top bar is squeezed up: B3UI._compact_top)
	check(await wait_for(func(): return friend.ui.coin_lbl.text.trim_prefix("🪙 ").split(" ")[0] == str(host.points_left()), 2.0),
		"and the friend's coins go down too (%s)" % friend.ui.coin_lbl.text)
	friend.tools._place(at(friend, 0, -30), at(friend, 0, -30), false, false)
	check(await wait_for(func(): return toast_has(friend, "🚧"), 2.0) and host.spent == spent0 + 2, "outside the fort, the friend is told why and nothing's placed")
	friend.drop("mine", at(friend, 3, 30))
	check(await wait_for(func(): return toast_has(friend, "glowing"), 2.0) and host.spent == spent0 + 2, "same for a mine")
	friend.ui.mode_hud.press_next()
	check(await wait_for(func(): return host.fighting and host.modes.wave == 1, 3.0), "the friend's ▶ Start wave 1 starts the host's wave")
	check(await wait_for(func(): return friend.modes.wave == 1 and friend.modes.phase == "wave" and friend.modes.left == 6 and String(friend.ui.mode_hud.title.text).contains("Wave 1"), 3.0), "the friend sees 🌊 Wave 1 and its 6 attackers")
	for u: B3Unit in host.units.duplicate():
		if is_instance_valid(u) and u.team == "blue" and not u.dead:
			u.hurt(99999.0, Vector3.UP, 1.0, null, "blast")
	check(await wait_for(func(): return friend.modes.phase == "break" and friend.modes.break_t > 1.0 and friend.budget == host.budget and host.budget > B3Modes.START_POINTS, 4.0), "then the break, its countdown and the bonus points (%d)" % friend.budget)
	check(await wait_for(func(): return String(friend.ui.mode_hud.title.text).contains("Wave 2 is coming") and friend.ui.mode_hud.next_btn.visible, 2.0),
		"🌊 Wave 2 is coming! with ▶ Next wave")
	# 👑 the Kings and their crowns
	host.run_ready("skirmish")
	check(await wait_for(func(): return friend.budget < 0 and friend.zone_vis == null and not friend.ui.coin_lbl.visible, 4.0),
		"another battle: the friend's coins and glowing fort go away")
	B3Rules.set_value("goal", "king")
	host.toggle_play()
	check(await wait_for(func(): return crowned_kings(host) == 2 and crowned_kings(friend) == 2, 4.0), "👑 the friend sees both Kings, with their crowns")
	check(await wait_for(func(): return friend.modes.kind == "king" and friend.modes.king_view.size() == 2 and friend.ui.mode_hud._bars.size() == 2, 2.0),
		"and the Kings' health in the panel")
	# 🚩 the hill
	B3Rules.set_value("goal", "hill")
	check(await wait_for(func(): return friend.modes.kind == "hill" and friend.modes.hill_node != null and host.modes.hill_on and friend.modes.hill_pos.distance_to(host.modes.hill_pos) < 0.3, 3.0), "🚩 the friend sees the glowing circle where the host's is")
	host.modes.scores["blue"] = 42.0
	check(await wait_for(func(): return absf(float(friend.modes.scores.get("blue", 0.0)) - float(host.modes.scores.get("blue", 0.0))) < 1.0 and float(friend.modes.scores.get("blue", 0.0)) >= 42.0, 2.0), "and the score bars (%.0f)" % float(friend.modes.scores.get("blue", 0.0)))
	# junk mode or budget state from a "host" is ignored
	var keep_pos: Vector3 = friend.modes.hill_pos
	for md in [["hill", true, Vector3(NAN, 0, 0), 5.0, "red", {}, ""], ["hill", true, Vector3.ZERO, INF, "red", {}, ""], ["boss"], [5], "hill",
			["waves", "lots", "wave", 0.0, 1, 1], ["waves", 1, "party", 0.0, 1, 1], ["king", "everyone"]]:
		friend.modes.apply_net(md)
	check(friend.modes.hill_pos == keep_pos and friend.modes.king_view.is_empty(), "🛡️ broken battle-goal state from the host is ignored")
	var keep_b: int = friend.budget
	for bg in [[5, 0, Rect2(Vector2(NAN, 0), Vector2.ONE), "red"], ["lots", 0, Rect2(), ""], [5, 0, "zone", "red"], [1, 2]]:
		friend.net._budget(bg)
	check(friend.budget == keep_b, "and so are broken points")
	B3Rules.set_value("goal", "last")
	await wait_for(func(): return friend.modes.kind == "", 2.0)

	# 🧩 a puzzle: the friend sees its goal and glowing area, laid on each new map
	var st0: Dictionary = B3Puzzles.STAGES[0]
	var st1: Dictionary = B3Puzzles.STAGES[1]
	B3Puzzles.start(host, String(st0.id))
	check(await wait_for(func(): return (friend.puzzle != null and friend.puzzle.id == st0.id and friend.zone_vis != null
		and friend.ui.puzzle_box != null and friend.ui.puzzle_box.visible), 4.0), "🧩 the friend sees the host's puzzle, its goal and the glowing area")
	# (its id, not the node: the old area gets freed, and a lambda holding a freed node makes Godot complain)
	var zv0_id: int = friend.zone_vis.get_instance_id()
	B3Puzzles.start(host, String(st1.id))
	check(Rect2(st0.zone) == Rect2(st1.zone) and String(st0.map) != String(st1.map), "(the next puzzle has the same area on another map)")
	check(await wait_for(func(): return (friend.map_id == String(st1.map) and friend.puzzle != null and friend.puzzle.id == st1.id
		and friend.zone_vis != null and friend.zone_vis.get_instance_id() != zv0_id and friend.net._zone_map == friend.map_id), 4.0),
		"🧩 the next puzzle: the friend's glowing area is laid on the new map, not left from the old one")
	check(String(friend.ui.puzzle_lbl.text).contains(String(st1.name)), "with the new goal (%s)" % String(friend.ui.puzzle_lbl.text).get_slice("\n", 0))
	host.puzzle.over = true
	host.puzzle.won = 2
	check(await wait_for(func(): return friend.ui.puzzle_card != null and friend.ui.puzzle_card.visible, 3.0), "⭐ when the puzzle's fight is over, the friend gets the stars card too")
	var lit := 0
	var stars_row: Node = friend.ui.puzzle_card.find_child("Stars", true, false) if friend.ui.puzzle_card else null
	if stars_row:
		for c in stars_row.get_children():
			if (c as CanvasItem).modulate.a > 0.9:
				lit += 1
	check(lit == 2 and B3Puzzles.stars(String(st1.id)) >= 2, "with the host's ⭐⭐ (and the friend keeps them)")
	host.puzzle.over = false
	host.puzzle.won = 0
	check(await wait_for(func(): return not friend.ui.puzzle_card.visible, 2.0), "⏮ trying again takes the card away")
	host.clear_all()
	check(await wait_for(func(): return friend.puzzle == null and friend.budget < 0 and friend.zone_vis == null, 3.0), "and when the puzzle's over, it's gone on the friend's screen")

	# leaving
	friend.stop_net()
	check(await wait_for(func(): return host.net.friends.is_empty(), 3.0), "👋 when the friend leaves, the host notices")
	check(not friend.puppet and friend.net == null, "and the friend is back in their own battle")
	var nobody := true
	for u: B3Unit in host.units:
		if u.ctl != null:
			nobody = false
	check(nobody, "nobody's fighter is still steered by the friend")
	host.stop_net()
	check(host.net == null, "the host can stop sharing")

	B3Player.stop()
	B3Rules.reset()
	host.queue_free()
	vp.queue_free()
	for i in 3:
		await get_tree().process_frame
	print("test_b3net: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

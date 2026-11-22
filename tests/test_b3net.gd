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
		{"c": 5}, {"c": ["fight"]}, {}]
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

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
	var tank: B3Unit = host.spawn_unit("tank", "red", at(host, -14, 8), "peaceful", 0.0)
	var wall: B3Struct = host.spawn_struct("wall", at(host, 0, -10), 0.0, 8.0)
	host.spawn_prop("xbarrel", at(host, 3, 6))
	host.spawn_hazard("lava", at(host, 0, 14), 3.0)

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

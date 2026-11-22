extends Node
## Two copies of the game talk over this computer's network: a host and a
## friend. Checks joining, mirroring, friend commands, players and snapshots.
## godot --headless --path . -- --test=net

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


## Toy, Wiggly and fighter nodes in a world (to catch copies left behind).
func thing_nodes(w: World) -> int:
	var n := 0
	for layer: Node in [w.bodies, w.wiggly_layer, w.fighter_layer]:
		for c in layer.get_children():
			if (c is Toy or c is Wiggly or c is Fighter) and not c.is_queued_for_deletion():
				n += 1
	return n


## True if a label under `n` says `text`.
func says(n: Node, text: String) -> bool:
	for c in n.get_children():
		if c is Label and not c.is_queued_for_deletion() and (c as Label).text.contains(text):
			return true
	return false


func _ready() -> void:
	await get_tree().process_frame
	var host := Game.new()
	add_child(host)
	host.begin({"world": "canvas", "mode": "host"})
	check(host.net != null and host.mode == "host", "the host starts hosting")
	for i in 12:
		host.world.spawn_toy("wood_block", Vector2(-300 + i * 50, 200))
	Builders.ride(host.world, "go_kart", Vector2(300, 150))
	var bat := host.world.spawn_toy("battery", Vector2(-500, 250))
	var lamp := host.world.spawn_toy("lamp", Vector2(-420, 250))
	host.world.add_link("wire", bat, lamp, bat.global_position, lamp.global_position)

	host.world.spawn_fighter("soldier", Vector2(-200, 150), "red", "peaceful")
	host.world.spawn_fighter("trex", Vector2(200, 100), "wild", "peaceful")
	host.world.apply_command(0, {"cmd": "platform", "x0": -100, "y0": 0, "x1": 100, "y1": 20})

	var friend := Game.new()
	add_child(friend)
	friend.begin({"world": "meadow", "mode": "client", "ip": "127.0.0.1"})
	check(await wait_for(func(): return friend.net.connected and friend.net.my_id > 0, 5.0), "a friend connects and is welcomed")
	check(await wait_for(func(): return friend.world.world_id == "canvas", 3.0), "the friend switches to the host's world")
	check(await wait_for(func(): return friend.world.things.size() == host.world.things.size(), 3.0),
		"the friend sees every toy and Wiggly (%d vs %d)" % [friend.world.things.size(), host.world.things.size()])
	check(await wait_for(func(): return friend.world.link_view.remote_links.size() == host.world.links.size(), 2.0), "and every link and wire")
	check(await wait_for(func(): return friend.world.fighters().size() == host.world.fighters().size(), 2.0), "and the people and dinosaurs (%d)" % host.world.fighters().size())
	check(await wait_for(func(): return friend.world.platforms.size() == host.world.platforms.size(), 2.0), "and the platforms")
	await wait_for(func(): return false, 0.3)
	check(thing_nodes(friend.world) == friend.world.things.size(),
		"no frozen leftover copies on the friend's screen (%d drawn, %d real)" % [thing_nodes(friend.world), friend.world.things.size()])
	var soldier: Fighter = host.world.fighters().filter(func(f): return f.type == "soldier")[0]
	var fs = friend.world.things.get(soldier.uid)
	check(fs is Fighter and fs.pers == "peaceful" and fs.weapon_id == soldier.weapon_id and soldier.weapon_id != "",
		"the friend sees a fighter's personality and weapon (%s, %s)" % [fs.pers if fs is Fighter else "?", fs.weapon_id if fs is Fighter else "?"])
	soldier.hp = 42.0
	check(await wait_for(func(): return fs is Fighter and absf(fs.hp - 42.0) < 0.5 and fs.max_hp == soldier.max_hp, 2.0), "and its health")
	check(NetClient.needs_reliable({"cmd": "input", "move": 1.0, "jump": true}) and NetClient.needs_reliable({"cmd": "input", "move": 0.0, "special": true})
		and NetClient.needs_reliable({"cmd": "input", "move": 0.0, "attack": false}) and NetClient.needs_reliable({"cmd": "spawn", "id": "beach_ball"}),
		"jumps, specials and attacks are sent so they can't get lost")
	check(not NetClient.needs_reliable({"cmd": "input", "move": 1.0, "ax": 0.0, "ay": 0.0}) and not NetClient.needs_reliable({"cmd": "drag", "x": 0, "y": 0}),
		"but walking and dragging stay quick")

	var before := host.world.things.size()
	friend.send({"cmd": "spawn", "id": "beach_ball", "x": 0, "y": 0})
	check(await wait_for(func(): return host.world.things.size() == before + 1, 3.0), "a friend's spawn appears on the host")
	check(await wait_for(func(): return friend.world.things.size() == before + 1, 3.0), "and on the friend's screen")

	var block: Toy = host.world.toys().filter(func(t): return t.id == "wood_block")[0]
	var start := block.global_position
	friend.send({"cmd": "grab", "uid": block.uid, "x": start.x, "y": start.y})
	for i in 40:
		friend.send({"cmd": "drag", "x": start.x, "y": start.y - 250.0})
		await get_tree().physics_frame
	check(block.global_position.y < start.y - 120.0, "a friend can grab and lift a toy (moved %.0f)" % (start.y - block.global_position.y))
	friend.send({"cmd": "release"})
	var puppet = friend.world.things.get(block.uid)
	await wait_for(func(): return puppet != null and puppet.global_position.distance_to(block.global_position) < 30.0, 2.0)
	check(puppet != null and puppet.global_position.distance_to(block.global_position) < 30.0, "the friend sees it where the host has it")

	check(await wait_for(func(): return friend.net.players.size() == 2, 2.0), "both players show in the player list")

	# a broken (or naughty) copy of the game sends junk: the host ignores it
	var my_id: int = friend.net.my_id
	var n_things := host.world.things.size()
	var n_plats := host.world.platforms.size()
	var junk: Array = [
		{"cmd": "spawn"}, {"cmd": "spawn", "id": 5, "x": 0, "y": 0}, {"cmd": "spawn", "id": "beach_ball", "x": NAN, "y": 0},
		{"cmd": "spawn", "id": "f:soldier", "x": 0, "y": 0, "team": "purple"}, {"cmd": "platform"},
		{"cmd": "platform", "x0": INF, "y0": 0, "x1": 10, "y1": 10}, {"cmd": "paint", "uid": block.uid, "color": "not a colour"},
		{"cmd": "gravity", "id": "sideways"}, {"cmd": "world", "id": "nowhere"}, {"cmd": "team", "uid": soldier.uid, "team": "purple"},
		{"cmd": "pers", "uid": soldier.uid, "pers": "evil"}, {"cmd": "input", "move": NAN}, {"cmd": "input", "move": 0.0, "ax": 5.0},
		{"cmd": "input", "move": 0.0, "jump": "yes"}, {"cmd": "link", "kind": "laser", "a": 1, "b": 2, "ax": 0, "ay": 0, "bx": 1, "by": 1},
		{"cmd": "resize", "uid": block.uid, "s": 1e12}, {"cmd": "queue_free"}, {"cmd": ["spawn"]}, {}]
	for c in junk:
		friend.net._send({"m": "cmd", "c": c}, true)
	friend.net._send({"m": "cmd", "c": "spawn"}, true)
	friend.net._send({"m": "emote", "id": 999}, true)
	friend.net._send({"m": "cur", "p": "over there"}, true)
	friend.net._send({"m": "hello", "v": NetCommon.VERSION, "name": ["not", "a", "name"], "color": "red"}, true)
	for pkt in [PackedByteArray([9, 9, 9]), PackedByteArray([0, 1, 2]), PackedByteArray([1, 0, 0, 0, 1, 7, 7])]:
		friend.net.mp.send_bytes(pkt, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)
	await wait_for(func(): return false, 0.5)
	check(host.world.things.size() == n_things and host.world.platforms.size() == n_plats, "junk commands from a friend don't make anything")
	check(host.world.gravity_id == "normal" and host.world.world_id == "canvas" and soldier.team == "red" and soldier.pers == "peaceful" and block.size_scale <= 3.0,
		"or change anything")
	check(host.net.friends.has(my_id) and String(host.net.friends[my_id].name) == "Friend" and host.net.friends[my_id].color is Color
		and int(host.net.friends[my_id].get("emote", -1)) == -1 and typeof(host.net.friends[my_id].get("cursor")) in [TYPE_NIL, TYPE_VECTOR2],
		"a strange name, colour, emote or cursor is tidied up")
	check(NetCommon.decode(PackedByteArray()).is_empty() and NetCommon.decode(PackedByteArray([1, 4, 0, 0, 0])).is_empty()
		and NetCommon.decode(PackedByteArray([0, 1, 2])).is_empty(), "empty and cut-short packets are ignored")
	# too many spawns at once: some are turned away
	var n_before := host.world.things.size()
	for i in 60:
		friend.send({"cmd": "spawn", "id": "beach_ball", "x": -400 + i * 12, "y": -200})
	await wait_for(func(): return false, 0.6)
	var added := host.world.things.size() - n_before
	check(added >= 5 and added <= 22, "a flood of spawns from one friend is slowed down (%d of 60 made)" % added)
	await wait_for(func(): return false, 0.4)
	friend.send({"cmd": "spawn", "id": "beach_ball", "x": 0, "y": -100})
	check(await wait_for(func(): return host.world.things.size() == n_before + added + 1, 1.5), "and a moment later spawning works again")

	host.world.allow_world_actions = false
	friend.send({"cmd": "clear"})
	await get_tree().create_timer(0.5).timeout
	check(host.world.things.size() > 5, "when the host locks it, a friend can't clear the world")

	var snap := NetCommon.encode(NetCommon.snapshot(host))
	print("        snapshot: %d bytes for %d things (%.0f KB/s at %d Hz)" % [snap.size(), host.world.things.size(), snap.size() * NetCommon.SNAP_HZ / 1024.0, int(NetCommon.SNAP_HZ)])
	check(snap.size() < 24000, "snapshots stay small enough for Wi-Fi")
	check(NetCommon.decode(snap).get("m", "") == "snap", "and decode back")
	check(NetCommon.decode(PackedByteArray([1, 255, 255, 255, 127, 9, 9])).is_empty(), "junk packets are ignored")

	friend.send({"cmd": "play", "uid": soldier.uid})
	check(await wait_for(func(): return soldier.player_id == my_id, 2.0), "a friend can play a fighter")
	friend.leave()
	await get_tree().create_timer(0.6).timeout
	check(host.net.player_count() == 0, "the host notices when the friend leaves")
	check(soldier.player_id == -1, "and the fighter they were playing gets its own brain back")
	host.leave()

	# the Play Together panel when another copy of the game is already listening for games
	var blocker := PacketPeerUDP.new()
	blocker.bind(NetCommon.BEACON_PORT)
	var panel := Together.new()
	add_child(panel)
	panel.build()
	if panel.finder.listening:
		panel.finder.stop()      # (this computer let both listen: pretend it couldn't)
		panel._refresh_list()
	await get_tree().process_frame
	check(says(panel._list, "Couldn't listen"), "if it can't listen for games on the Wi-Fi, the panel says so")
	panel.queue_free()
	blocker.close()
	print("test_net: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

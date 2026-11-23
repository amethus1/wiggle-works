extends TestBase
## Two copies of the game talk over this computer's network: a host and a
## friend. Checks joining, mirroring, friend commands, players and snapshots.
## godot --headless --path . -- --test=net


func wait_for(cond: Callable, secs := 3.0) -> bool:
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

	# 💫 knocked out on the host: knocked out on the friend's screen too, and the friend's 💖 Revive works
	soldier.hurt(99999.0, Vector2(0, -50))
	check(await wait_for(func(): return fs is Fighter and not fs.alive() and fs.state == soldier.state, 3.0),
		"a fighter knocked out on the host is knocked out on the friend's screen (%s)" % (fs.state if fs is Fighter else "?"))
	friend.select(soldier.uid)
	friend.hud.refresh_selection()
	check(not soldier.alive() and String(friend.hud.sel_name.text).contains("KO'd"), "and the friend's info bar says KO'd (%s)" % friend.hud.sel_name.text)
	friend.send({"cmd": "revive", "uid": soldier.uid})
	check(await wait_for(func(): return soldier.alive(), 2.0), "💖 a friend's Revive gets the host's fighter back up")
	check(await wait_for(func(): return fs.alive() and String(fs.state) == "stand", 3.0), "and it's back up on the friend's screen too")
	friend.select(-1)

	# 👥 snapshots only carry what changed since the last one the friend got
	var tx: NetDelta.Sender = host.net._tx
	var rx: NetDelta.Receiver = friend.net._rx
	var keys0: int = tx.keyframes
	await wait_for(func(): return false, 0.5)
	check(tx.keyframes == keys0 and rx.got > 5, "after joining, the friend gets just the changes (%d whole snapshots so far)" % tx.keyframes)
	# all the friend's snapshots are lost: it can't use the next one, asks for a whole one and is right again
	rx.hist.clear()
	var moved_block: Toy = host.world.toys().filter(func(t): return t.id == "wood_block")[3]
	moved_block.global_position += Vector2(0, -150)
	check(await wait_for(func(): return tx.keyframes > keys0, 2.0), "when the friend loses track, the host sends a whole snapshot")
	var pb = friend.world.things.get(moved_block.uid)
	check(await wait_for(func(): return pb != null and pb.global_position.distance_to(moved_block.global_position) < 20.0, 2.0),
		"and the friend's screen is right again (%.0f px off)" % (pb.global_position.distance_to(moved_block.global_position) if pb else -1.0))
	check(_delta_recovers(), "NetDelta: lost snapshots are made up for by the next one, junk is thrown away")

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
	# a ready-made contraption is many toys: each one counts against the friend's spawning
	await wait_for(func(): return false, 3.0)
	var n_toys := host.world.things.size()
	for i in 8:
		friend.send({"cmd": "spawn", "id": "build:domino", "x": -600 + i * 20, "y": -400})
	await wait_for(func(): return false, 0.6)
	var dominos := host.world.things.size() - n_toys
	check(dominos >= 12 and dominos <= 30, "🁢 eight Domino Runs at once from a friend: each domino counts, so only one or two are made (%d toys)" % dominos)

	# a copy of the game that isn't the same version is told, kindly, on both sides
	var odd := ENetMultiplayerPeer.new()
	odd.create_client("127.0.0.1", NetCommon.PORT)
	var omp := SceneMultiplayer.new()
	omp.root_path = get_path()
	omp.multiplayer_peer = odd
	var said := [""]
	omp.peer_packet.connect(func(_id: int, pkt: PackedByteArray):
		var why: Variant = NetCommon.decode(pkt).get("why")
		if why is String:
			said[0] = why)
	omp.connected_to_server.connect(func():
		omp.send_bytes(NetCommon.encode({"m": "hello", "v": NetCommon.VERSION - 1, "name": "Old"}), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0))
	check(await wait_for(func():
		omp.poll()
		return said[0] != "", 3.0) and said[0] == NetCommon.WRONG_VERSION, "a friend with another version is told: %s" % said[0])
	check(await wait_for(func(): return _toast_said(host, "different version"), 1.0), "and so is the host")
	odd.close()

	host.world.allow_world_actions = false
	friend.send({"cmd": "clear"})
	await get_tree().create_timer(0.5).timeout
	check(host.world.things.size() > 5, "when the host locks it, a friend can't clear the world")

	var snap: PackedByteArray = host.net._tx.packet(-1)
	var change: PackedByteArray = host.net._tx.packet(host.net._tx.n - 1)
	print("        snapshot: %d bytes whole, %d bytes of changes, for %d things" % [snap.size(), change.size(), host.world.things.size()])
	check(snap.size() < 24000 and change.size() < snap.size(), "snapshots stay small enough for Wi-Fi")
	check(NetCommon.decode(snap).get("m", "") == "snap", "and decode back")
	check(NetCommon.decode(PackedByteArray([1, 255, 255, 255, 127, 9, 9])).is_empty(), "junk packets are ignored")

	friend.send({"cmd": "play", "uid": soldier.uid})
	check(await wait_for(func(): return soldier.player_id == my_id, 2.0), "a friend can play a fighter")
	friend.leave()
	await get_tree().create_timer(0.6).timeout
	check(host.net.player_count() == 0, "the host notices when the friend leaves")
	check(soldier.player_id == -1, "and the fighter they were playing gets its own brain back")
	host.leave()

	# 📡 the list of games on the Wi-Fi changes when a game's world or players do (and junk is tidied)
	var lf := LanFinder.new()
	var beacon := {"game": NetCommon.GAME_ID, "v": NetCommon.VERSION, "name": "Sam", "world": "canvas", "players": 1, "port": NetCommon.PORT}
	check(lf.heard("10.0.0.5", beacon) and not lf.heard("10.0.0.5", beacon.duplicate()), "📡 a new game shows in the list (and the same one again changes nothing)")
	var b2 := beacon.duplicate()
	b2.players = 2
	var b3 := b2.duplicate()
	b3.world = "meadow"
	check(lf.heard("10.0.0.5", b2) and lf.heard("10.0.0.5", b3) and int(lf.games["10.0.0.5"].players) == 2 and lf.games["10.0.0.5"].world == "meadow",
		"and changes when a friend joins it or its world changes")
	lf.heard("10.0.0.6", {"game": NetCommon.GAME_ID, "name": ["x"], "world": {}, "players": "lots"})
	check(lf.games["10.0.0.6"].name == "Friend" and lf.games["10.0.0.6"].world == "" and int(lf.games["10.0.0.6"].players) == 1
		and not lf.heard("10.0.0.7", "junk") and not lf.heard("10.0.0.7", {"game": "other-game"}), "📡 odd beacons are tidied up or ignored")
	lf.free()

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
	finish()


## True if a message with `txt` in it has popped up on `g`'s screen.
func _toast_said(g, txt: String) -> bool:
	for l in g.hud.find_children("*", "Label", true, false):
		if String((l as Label).text).contains(txt):
			return true
	return false


## NetDelta on its own: a whole snapshot, then just changes; lost ones made
## up for by the next; one measured against a snapshot the friend never got
## (or junk) is thrown away and a whole one asked for.
func _delta_recovers() -> bool:
	var tables := [["t", PackedInt32Array([NetDelta.STR | NetDelta.ONCE, NetDelta.V2, NetDelta.FIX16])]]
	var tx := NetDelta.Sender.new(tables)
	var rx := NetDelta.Receiver.new(tables)
	var rows := func(xs: Array) -> Dictionary:
		var l: Array = []
		for i in xs.size():
			l.append([i + 1, "ball", Vector2(xs[i], 0.0), 0.5])
		return {"t": l}
	tx.push(rows.call([0.0, 10.0, 20.0]), {"st": [1]})
	var ok := rx.take(NetCommon.decode(tx.packet(-1)))
	tx.push(rows.call([1.0, 10.0, 20.0]), {"st": [1]})
	var small := tx.packet(rx.last)
	ok = ok and rx.take(NetCommon.decode(small))
	# two snapshots lost on the way (the friend never acks them)...
	tx.push(rows.call([2.0, 10.0]), {"st": [2]})
	tx.packet(rx.last)
	tx.push(rows.call([3.0, 10.0, 25.0, 40.0]), {"st": [3]})
	tx.packet(rx.last)
	tx.push(rows.call([4.0, 11.0, 25.0, 40.0]), {"st": [3]})
	ok = ok and rx.take(NetCommon.decode(tx.packet(rx.last)))
	var snap := rx.snapshot()
	var xs := {}
	for e: Array in snap.t:
		xs[int(e[0])] = (e[2] as Vector2).x
	ok = ok and xs == {1: 4.0, 2: 11.0, 3: 25.0, 4: 40.0} and snap.st == [3]
	# one measured against a snapshot the friend doesn't have, and junk: thrown away, a whole one asked for
	tx.push(rows.call([5.0]), {"st": [4]})
	var bad := NetCommon.decode(tx.packet(rx.last))
	bad.b = 999
	ok = ok and not rx.take(bad) and rx.need_full
	ok = ok and not rx.take({"n": 50, "b": -1, "g": {}, "t": PackedByteArray([255, 255, 255, 255, 1])}) and rx.need_full
	ok = ok and rx.take(NetCommon.decode(tx.packet(-1))) and not rx.need_full and rx.snapshot().t.size() == 1
	return ok

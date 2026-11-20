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
	host.world.allow_world_actions = false
	friend.send({"cmd": "clear"})
	await get_tree().create_timer(0.5).timeout
	check(host.world.things.size() > 5, "when the host locks it, a friend can't clear the world")

	var snap := NetCommon.encode(NetCommon.snapshot(host))
	print("        snapshot: %d bytes for %d things (%.0f KB/s at %d Hz)" % [snap.size(), host.world.things.size(), snap.size() * NetCommon.SNAP_HZ / 1024.0, int(NetCommon.SNAP_HZ)])
	check(snap.size() < 24000, "snapshots stay small enough for Wi-Fi")
	check(NetCommon.decode(snap).get("m", "") == "snap", "and decode back")
	check(NetCommon.decode(PackedByteArray([1, 255, 255, 255, 127, 9, 9])).is_empty(), "junk packets are ignored")

	friend.leave()
	await get_tree().create_timer(0.6).timeout
	check(host.net.player_count() == 0, "the host notices when the friend leaves")
	host.leave()
	print("test_net: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

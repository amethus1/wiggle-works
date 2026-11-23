extends Node
## 👥 How many bytes a second the host sends a friend over Wi-Fi, in a big
## 3D battle (the 150-fighter Huge Battle) and a big 2D one (120 fighters).
## It counts what ENet really sends (headers, pieces of big packets and
## resends too), and also works it out for the full 20 snapshots a second
## (a busy computer makes fewer). --prof times each step of a snapshot and
## says what's in one. Not part of the suite.
##   godot --headless --path . -- --test=netbench [--secs=10] [--only=3d|2d] [--prof]

var secs := 10.0


func wait(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func wait_for(cond: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## Bytes (and packets) the host's ENet connection sent since the last call.
func sent(conn: ENetConnection) -> Array:
	return [conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA), conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)]


func _ready() -> void:
	await get_tree().process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--only="):
			only = a.substr(7)
	if only != "2d":
		await _bench3d()
	if only != "3d":
		await _bench2d()
	print("test_netbench: 0 failure(s)")
	get_tree().quit(0)


var snaps := 0      # snapshots the friend got


## Counts the snapshots reaching the friend (whatever the game does with them).
func count_snaps(mp: SceneMultiplayer) -> void:
	mp.peer_packet.connect(func(_id: int, pkt: PackedByteArray):
		if String(NetCommon.decode(pkt).get("m", "")) == "snap":
			snaps += 1)


## What the host sends in `t` seconds: bytes a second as it went, and as it
## would be at the full 20 snapshots a second (a busy computer makes fewer).
func _report(what: String, conn: ENetConnection, t: float, extra := "") -> void:
	var t0 := Time.get_ticks_msec()
	sent(conn)
	snaps = 0
	await wait(t)
	var s := sent(conn)
	var real := (Time.get_ticks_msec() - t0) / 1000.0
	var rate := snaps / real
	print("  %-26s %7.1f KB/s at %4.1f snapshots/s = %6.1f KB/s at 20/s  (%4.0f packets/s, %d fps)%s" % [what, s[0] / 1024.0 / real,
		rate, s[0] / 1024.0 / maxf(1.0, snaps) * 20.0, s[1] / real, Engine.get_frames_per_second(), extra])


func _bench3d() -> void:
	B3Rules.reset()
	var host = load("res://battle3d/battle3d.gd").new()
	add_child(host)
	host.begin({"seed": 5, "map": "grassland"})
	host.run_ready("big")
	host.start_hosting()
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, 180)
	add_child(vp)
	var friend = load("res://battle3d/battle3d.gd").new()
	vp.add_child(friend)
	friend.begin({"seed": 9, "map": "desert", "net": "client", "ip": "127.0.0.1"})
	var n: int = host.units.size()
	await wait_for(func(): return friend.net.mp != null, 5.0)
	count_snaps(friend.net.mp)
	await wait_for(func(): return friend.units.size() == host.units.size(), 10.0)
	print("3D: %d fighters and vehicles (the friend sees %d)" % [n, friend.units.size()])
	var conn: ENetConnection = host.net.peer.host
	await _report("3D waiting for Fight!", conn, secs * 0.5)
	host.toggle_play()
	await wait(1.0)
	await _report("3D fighting", conn, secs, "  %d left" % host.units.size())
	if OS.get_cmdline_user_args().has("--prof"):
		await _prof("3D", func() -> Array: return B3Net.delta_state(host.net.snapshot()), B3Net.TABLES,
			func(rx: NetDelta.Receiver) -> void: friend.net._apply_snapshot(rx.snapshot()))
	friend.stop_net()
	host.stop_net()
	host.queue_free()
	vp.queue_free()
	B3Player.stop()
	await wait(0.3)


func _bench2d() -> void:
	var host := Game.new()
	add_child(host)
	host.begin({"world": "battle", "mode": "host"})
	var w := host.world
	var people := ["soldier", "knight", "viking", "archer", "gunner", "rocketeer", "grenadier", "ninja", "medic", "stick", "sniper", "soldier"]
	for i in 60:
		for side in [-1.0, 1.0]:
			w.spawn_fighter(people[i % people.size()], Vector2(side * (320.0 + (i % 20) * 55.0 + (i / 20) * 18.0), 120.0 - (i / 20) * 70.0), "red" if side < 0 else "blue", "")
	var friend := Game.new()
	add_child(friend)
	friend.begin({"world": "meadow", "mode": "client", "ip": "127.0.0.1"})
	await wait_for(func(): return friend.net.mp != null, 5.0)
	count_snaps(friend.net.mp)
	await wait_for(func(): return friend.world.fighters().size() == w.fighters().size(), 10.0)
	print("2D: %d fighters (the friend sees %d)" % [w.fighters().size(), friend.world.fighters().size()])
	var conn: ENetConnection = host.net.peer.host
	await _report("2D waiting", conn, secs * 0.5)
	w.apply_command(0, {"cmd": "fight", "on": true})
	await wait(1.0)
	await _report("2D fighting", conn, secs)
	if OS.get_cmdline_user_args().has("--prof"):
		var states := {}
		for f in w.fighters():
			states[f.state] = int(states.get(f.state, 0)) + 1
		print("  2D fighters: %s" % states)
		await _prof("2D", func() -> Array: return NetCommon.delta_state(NetCommon.snapshot(host)), NetCommon.TABLES,
			func(rx: NetDelta.Receiver) -> void: NetCommon.apply_snapshot(friend, NetCommon.from_delta(rx)))
	friend.leave()
	host.leave()
	await wait(0.3)


## How long each step of a snapshot takes (milliseconds): a whole one, then
## the next ones, which only carry what changed.
func _prof(what: String, make: Callable, tables: Array, apply: Callable) -> void:
	var tx := NetDelta.Sender.new(tables)
	var rx := NetDelta.Receiver.new(tables)
	for i in 4:
		var t0 := Time.get_ticks_usec()
		var ds: Array = make.call()
		var t1 := Time.get_ticks_usec()
		tx.push(ds[0], ds[1])
		var t2 := Time.get_ticks_usec()
		var pkt := tx.packet(rx.last if i > 0 else -1)
		var t3 := Time.get_ticks_usec()
		rx.take(NetCommon.decode(pkt))
		var t4 := Time.get_ticks_usec()
		apply.call(rx)
		var t5 := Time.get_ticks_usec()
		print("  %s ms (%s): snapshot %.2f  round %.2f  pack %.2f  unpack %.2f  apply %.2f  = host %.2f, friend %.2f  (%d bytes)" % [
			what, "whole" if i == 0 else "change", (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0,
			(t5 - t4) / 1000.0, (t3 - t0) / 1000.0, (t5 - t3) / 1000.0, pkt.size()])
		if i == 3:
			# what's in a snapshot of changes: bytes per table, and how often each field changes
			var cur: Dictionary = tx.hist[tx.n]
			var base: Dictionary = tx.hist[tx.n - 1]
			for tp: Array in tables:
				var o := StreamPeerBuffer.new()
				NetDelta.put_table(o, tp[1], (base.t as Dictionary).get(tp[0], {}), (cur.t as Dictionary).get(tp[0], {}))
				var counts := PackedInt32Array()
				counts.resize((tp[1] as PackedInt32Array).size())
				var ct: Dictionary = (cur.t as Dictionary).get(tp[0], {})
				var bt: Dictionary = (base.t as Dictionary).get(tp[0], {})
				for id in ct:
					if bt.has(id):
						for f in counts.size():
							if ct[id][f] != bt[id][f]:
								counts[f] += 1
				print("      %s: %d rows, %d bytes, changed per field %s" % [tp[0], ct.size(), o.data_array.size(), counts])
			print("      fx/events since: %d bytes" % NetCommon.encode({"g": (cur.g as Dictionary)}).size())
		await wait(0.05)

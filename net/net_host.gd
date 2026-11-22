class_name NetHost
extends Node
## Hosting: runs the real world and shares it with up to 7 friends over ENet.
## Channel 0 is reliable (commands, events); channel 1 carries snapshots and
## cursor moves. A UDP beacon lets friends find the game on the Wi-Fi.

var game = null
var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var friends := {}            # peer id -> {name, color, cursor, emote, emo_t, ctrl}
var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _snap_t := 0.0
var _fx: Array = []
var my_cursor := Vector2.ZERO
var my_emote := -1
var my_emote_t := 0.0


func open(bind := "") -> bool:
	peer = ENetMultiplayerPeer.new()
	if bind != "":
		peer.set_bind_ip(bind)
	if peer.create_server(NetCommon.PORT, NetCommon.MAX_FRIENDS) != OK:
		return false
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.peer_connected.connect(_on_connected)
	mp.peer_disconnected.connect(_on_disconnected)
	mp.peer_packet.connect(_on_packet)
	_beacon.set_broadcast_enabled(true)
	return true


func close() -> void:
	if mp and peer:
		_send_all({"m": "bye"}, true)
		peer.close()
	peer = null
	mp = null
	_beacon.close()
	friends.clear()


func player_count() -> int:
	return friends.size()


func address_text() -> String:
	var a := NetCommon.local_addresses()
	return ", ".join(a) if not a.is_empty() else "(no Wi-Fi address found)"


func queue_fx(name: String, args: Dictionary) -> void:
	if friends.is_empty():
		return
	_fx.append([name, args])
	if _fx.size() > 120:
		_fx.pop_front()


func send_hello() -> void:
	pass  # the host's name and color go out with every snapshot


func emote(id: int) -> void:
	my_emote = id
	my_emote_t = Time.get_ticks_msec() / 1000.0


func players_snapshot() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var out: Array = [{"id": 1, "name": Settings.player_name, "col": Settings.player_color, "cur": my_cursor,
		"emo": my_emote if now - my_emote_t < 3.0 else -1, "age": now - my_emote_t, "ctrl": game.playing_uid}]
	for id in friends:
		var f: Dictionary = friends[id]
		out.append({"id": id, "name": f.name, "col": f.color, "cur": f.get("cursor", null),
			"emo": int(f.get("emote", -1)) if now - float(f.get("emo_t", 0.0)) < 3.0 else -1,
			"age": now - float(f.get("emo_t", 0.0)), "ctrl": int(f.get("ctrl", -1))})
	return out


func _process(dt: float) -> void:
	if mp == null:
		return
	mp.poll()
	my_cursor = game.local_pos()
	_beacon_t -= dt
	if _beacon_t <= 0.0:
		_beacon_t = 1.0
		var b := JSON.stringify({"game": NetCommon.GAME_ID, "v": NetCommon.VERSION, "name": Settings.player_name,
			"world": game.world.world_id, "players": friends.size() + 1, "port": NetCommon.PORT})
		_beacon.set_dest_address("255.255.255.255", NetCommon.BEACON_PORT)
		_beacon.put_packet(b.to_utf8_buffer())
	if friends.is_empty():
		return
	if not _fx.is_empty():
		_send_all({"m": "fx", "list": _fx}, true)
		_fx = []
	_snap_t -= dt
	if _snap_t <= 0.0:
		_snap_t = 1.0 / NetCommon.SNAP_HZ
		_send_all(NetCommon.snapshot(game), false)


func _send_all(d: Dictionary, reliable: bool) -> void:
	if mp == null:
		return
	var pkt := NetCommon.encode(d)
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	mp.send_bytes(pkt, 0, mode, 0 if reliable else 1)


func _send_to(id: int, d: Dictionary) -> void:
	mp.send_bytes(NetCommon.encode(d), id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)


func _on_connected(_id: int) -> void:
	pass  # wait for their hello


func _on_disconnected(id: int) -> void:
	if not friends.has(id):
		return
	var f: Dictionary = friends[id]
	friends.erase(id)
	game.world.grab_end(id)
	# whatever they were playing goes back to doing its own thing
	for w in game.world.wigglies():
		if w.player_id == id:
			w.player_id = -1
			w.move_input = 0.0
	for fi in game.world.fighters():
		if fi.player_id == id:
			fi.player_id = -1
			fi.move_input = 0.0
			fi.want_attack = false
	game.effects.handle("poof", {"p": game.cam.center()})
	if game.hud:
		game.hud.toast("%s left" % f.name)
		game.hud.refresh()


func _on_packet(id: int, pkt: PackedByteArray) -> void:
	var d := NetCommon.decode(pkt)
	match String(d.get("m", "")):
		"hello":
			if not (d.get("v") is int) or int(d.v) != NetCommon.VERSION:
				_send_to(id, {"m": "bye", "why": "Different game version. Update Wiggle Works on both computers."})
				return
			var first := not friends.has(id)
			if first:
				friends[id] = {}
			friends[id].name = NetCommon.clean_name(d.get("name"))
			friends[id].color = d.color if d.get("color") is Color else Color.WHITE
			if first:
				_send_to(id, {"m": "welcome", "id": id, "world": game.world.world_id})
				Settings.award("friends")
				if game.hud:
					game.hud.toast("%s joined! 👋" % friends[id].name)
					game.hud.refresh()
				Sfx.play("merge", null, 0.8)
		"cmd":
			if friends.has(id) and typeof(d.get("c")) == TYPE_DICTIONARY:
				var c: Dictionary = d.c
				if not cmd_ok(c):
					return
				if String(c.cmd) in ["world", "clear", "undo"] and not game.world.allow_world_actions:
					return
				if String(c.cmd) in SPAWNY and not NetCommon.allow(friends[id], "spawn", 6.0, 15.0):
					return
				game.world.apply_command(id, c)
				if String(c.cmd) == "play":
					friends[id].ctrl = int(c.get("uid", -1))
		"cur":
			if friends.has(id):
				friends[id].cursor = d.p if NetCommon.vec2_ok(d.get("p")) else null
		"emote":
			if friends.has(id) and d.get("id") is int and int(d.id) >= 0 and int(d.id) < NetCommon.EMOJI.size():
				friends[id].emote = int(d.id)
				friends[id].emo_t = Time.get_ticks_msec() / 1000.0
				Sfx.play("pop", null, 0.4, 1.4)


# ------------------------------------------------------- checking friends
## What friends may ask for. Anything else, a missing piece or something of
## the wrong kind (text where a number goes, NaN, a made-up team) is ignored,
## so a broken or hacked copy of the game can't crash the host.
const CMDS := ["spawn", "grab", "drag", "release", "use", "team", "pers", "give", "drop", "fight", "platform",
	"unplatform", "detonate", "link", "unlink", "paint", "erase", "clone", "resize", "flip", "nail", "rotate",
	"play", "input", "magic", "gravity", "night", "pause", "speed", "world", "clear", "undo"]
const NUMS := {"x": 1.0e5, "y": 1.0e5, "x0": 1.0e5, "y0": 1.0e5, "x1": 1.0e5, "y1": 1.0e5, "ax": 1.0e5, "ay": 1.0e5,
	"bx": 1.0e5, "by": 1.0e5, "uid": 2.0e9, "a": 2.0e9, "ai": 2.0e9, "b": 2.0e9, "bi": 2.0e9,
	"s": 20.0, "d": 10.0, "v": 10.0, "move": 10.0}
const TEXTS := ["id", "team", "pers", "kind", "style", "color"]
const FLAGS := ["on", "whole", "jump", "special", "attack"]
const SPAWNY := ["spawn", "clone", "platform", "link", "magic"]     # make new things: rate-limited


static func cmd_ok(c: Dictionary) -> bool:
	var cmd: Variant = c.get("cmd")
	if not (cmd is String) or not CMDS.has(cmd):
		return false
	for k in NUMS:
		if c.has(k) and not NetCommon.num_ok(c[k], float(NUMS[k])):
			return false
	for k in TEXTS:
		if c.has(k) and not (c[k] is String and (c[k] as String).length() <= 40):
			return false
	for k in FLAGS:
		if c.has(k) and not (c[k] is bool):
			return false
	var has_all := func(keys: Array) -> bool:
		for k in keys:
			if not c.has(k):
				return false
		return true
	match String(cmd):
		"spawn":
			return c.has("id") and _known_team(String(c.get("team", "")), true) and _known_pers(String(c.get("pers", "")), true)
		"team":
			return _known_team(String(c.get("team", "")), false)
		"pers":
			return _known_pers(String(c.get("pers", "")), false)
		"platform":
			return has_all.call(["x0", "y0", "x1", "y1"])
		"link":
			return has_all.call(["ax", "ay", "bx", "by"]) and Game.LINK_TOOLS.has(String(c.get("kind", "")))
		"input":
			return c.has("ax") == c.has("ay")
		"paint":
			return Color.html_is_valid(String(c.get("color", "ffffff")))
		"resize":
			return float(c.get("s", 1.0)) >= 0.1
		"gravity":
			return Catalog.GRAVITIES.any(func(g): return g.id == String(c.get("id", "normal")))
		"world":
			return Catalog.WORLDS.any(func(w): return w.id == String(c.get("id", "meadow")))
	return true


static func _known_team(t: String, blank_ok: bool) -> bool:
	return (blank_ok and t == "") or Catalog.TEAM_ORDER.has(t)


static func _known_pers(p: String, blank_ok: bool) -> bool:
	return (blank_ok and p == "") or Catalog.PERSONALITIES.any(func(x): return x.id == p)

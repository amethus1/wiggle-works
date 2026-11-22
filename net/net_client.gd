class_name NetClient
extends Node
## Joining a friend: sends your commands to the host and draws the snapshots
## it sends back.

var game = null
var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var my_id := 0
var connected := false
var players: Array = []
var _cur_t := 0.0
var _hello_t := 0.0
var _gave_up := false


func connect_to(ip: String) -> void:
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, NetCommon.PORT) != OK:
		_fail("Couldn't reach %s." % ip)
		return
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.connected_to_server.connect(func():
		connected = true
		send_hello())
	mp.connection_failed.connect(func(): _fail("Couldn't connect to %s. Is the host still hosting?" % ip))
	mp.server_disconnected.connect(func(): _fail("The host stopped the game."))
	mp.peer_packet.connect(_on_packet)
	Settings.last_join = ip
	Settings.save()
	if game.hud:
		game.hud.toast("Joining %s…" % ip)


func close() -> void:
	if peer:
		peer.close()
	peer = null
	mp = null
	connected = false


func player_count() -> int:
	return players.size()


func send_hello() -> void:
	_send({"m": "hello", "v": NetCommon.VERSION, "name": Settings.player_name, "color": Settings.player_color}, true)


func send_cmd(c: Dictionary) -> void:
	_send({"m": "cmd", "c": c}, needs_reliable(c))


## Steady streams (dragging, walking, turning) can lose a packet: the next one
## is right behind. A jump, special move or pressing/letting go of attack
## happens once, so it must arrive.
static func needs_reliable(c: Dictionary) -> bool:
	if not String(c.get("cmd", "")) in ["drag", "input", "rotate"]:
		return true
	return c.has("jump") or c.has("special") or c.has("attack")


func emote(id: int) -> void:
	_send({"m": "emote", "id": id}, true)


func _send(d: Dictionary, reliable: bool) -> void:
	if mp == null or not connected:
		return
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	mp.send_bytes(NetCommon.encode(d), 1, mode, 0 if reliable else 1)


func _fail(msg: String) -> void:
	if _gave_up:
		return
	_gave_up = true
	connected = false
	if game and game.hud:
		game.hud.toast(msg, 4.0)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(game):
		game.leave()


func _process(dt: float) -> void:
	if mp == null:
		return
	mp.poll()
	NetCommon.interpolate(game.world, dt)
	if not connected:
		return
	_cur_t -= dt
	if _cur_t <= 0.0:
		_cur_t = 1.0 / 15.0
		_send({"m": "cur", "p": game.local_pos()}, false)


func _on_packet(_id: int, pkt: PackedByteArray) -> void:
	var d := NetCommon.decode(pkt)
	match String(d.get("m", "")):
		"welcome":
			my_id = int(d.get("id", 0))
			if String(d.get("world", "")) != game.world.world_id:
				game.world.load_world(String(d.world), false)
				game.cam.fit(game.world.view_rect, game.get_viewport_rect().size)
			Settings.award("friends")
			if game.hud:
				game.hud.toast("You joined! Everyone shares this playground. 🎉")
				game.hud.refresh()
		"snap":
			players = d.get("players", [])
			NetCommon.apply_snapshot(game, d)
		"fx":
			for e in d.get("list", []):
				game.effects.handle(String(e[0]), e[1])
		"bye":
			_fail(String(d.get("why", "The host stopped the game.")))

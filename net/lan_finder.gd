class_name LanFinder
extends Node
## Listens for games being hosted on the same Wi-Fi.

signal games_changed

const STALE := 4.0

var want := NetCommon.GAME_ID   # which game's beacons to list (3D Battle uses B3Net.GAME_ID)
var udp := PacketPeerUDP.new()
var games := {}   # ip -> {name, world, players, seen}
var listening := false
var _t := 0.0


func start() -> bool:
	stop()
	listening = udp.bind(NetCommon.BEACON_PORT) == OK
	return listening


func stop() -> void:
	if listening:
		udp.close()
	listening = false
	games.clear()


func _exit_tree() -> void:
	stop()


func _process(dt: float) -> void:
	if not listening:
		return
	_t += dt
	var changed := false
	var n := 0
	while udp.get_available_packet_count() > 0 and n < 64:
		n += 1
		var pkt := udp.get_packet()
		var ip := udp.get_packet_ip()
		if pkt.size() > 2048:
			continue
		if heard(ip, JSON.parse_string(pkt.get_string_from_utf8())):
			changed = true
	for ip in games.keys():
		if _t - float(games[ip].seen) > STALE:
			games.erase(ip)
			changed = true
	if changed:
		games_changed.emit()


## A beacon `d` from `ip`. Only the parts a game list shows, tidied up (it
## could come from anything on the Wi-Fi). True if the list should change:
## a new game, or one whose name, world, players or version changed.
func heard(ip: String, d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).get("game", "") != want:
		return false
	var g := {"game": want, "name": NetCommon.clean_name((d as Dictionary).get("name")),
		"world": String((d as Dictionary).get("world")).left(40) if (d as Dictionary).get("world") is String else "",
		"players": clampi(int((d as Dictionary).get("players")), 1, 99) if NetCommon.num_ok((d as Dictionary).get("players"), 1000.0) else 1,
		"v": int((d as Dictionary).get("v")) if NetCommon.num_ok((d as Dictionary).get("v"), 1.0e6) else 0,
		"port": int((d as Dictionary).get("port")) if NetCommon.num_ok((d as Dictionary).get("port"), 65535.0) else 0,
		"seen": _t}
	var old: Variant = games.get(ip)
	games[ip] = g
	if old == null:
		return true
	for k in ["name", "world", "players", "v"]:
		if (old as Dictionary).get(k) != g[k]:
			return true
	return false

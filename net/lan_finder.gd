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
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		var ip := udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY or d.get("game", "") != want:
			continue
		if not games.has(ip):
			changed = true
		d.seen = _t
		games[ip] = d
	for ip in games.keys():
		if _t - float(games[ip].seen) > STALE:
			games.erase(ip)
			changed = true
	if changed:
		games_changed.emit()

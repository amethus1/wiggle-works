class_name B3Net
extends Node
## 👥 Playing 3D Battle together on the same Wi-Fi.
##
## The host's computer runs the real battle. About 20 times a second it sends
## friends a snapshot: every fighter and vehicle (where, which way, what it's
## doing, health), barrels and crates, flying rockets, pools, buildings, the
## knocked-out, the battle state and who's playing what, the 🏁 battle goal
## (Kings, the hill, 🌊 waves), the 🧩 puzzle, the 🪙 points to spend and the
## 🏆 scoreboard. Each one only carries what changed since the last snapshot
## that friend got (NetDelta: the friend says which one with an "ak"); a
## friend who has just joined, or lost too many, gets a whole one. Things
## that must not get lost go on reliable channels: a fighter knocked out, a
## wall piece breaking (channel 0), and the effects and sounds (channel 2).
##
## A friend's computer shows "puppets": the same fighters, built the same way,
## but with their physics and brains switched off, glided smoothly to where the
## host says they are. Knocked-out ragdolls and flying wall chunks are
## simulated on each computer (they only need to look right).
##
## Friends can place things from the Toy Box, erase, press Fight/Pause/Reset,
## and play any fighter or vehicle: their keys and mouse go to the host ~30
## times a second (B3Ctl.pack) and the host's copy of that fighter obeys them.
## Presses that happen once (a jump, a quick click or right-click) are
## counted, and every controls packet carries the counts so far, so a lost
## packet can't lose one. The host can stop friends changing the battle
## (allow_changes): then they can only play.

const PORT := 24710
const GAME_ID := "wiggle-works-3d"
const VERSION := 2      # 2: small snapshots (NetDelta), effects on their own channel, counted presses
const CH_SNAP := 1      # snapshots (unreliable) and acks
const CH_FX := 2        # effects and sounds (reliable, so a lost packet can't lose the nuke's flash)
const MAX_FRIENDS := 7
const SNAP_HZ := 20.0
const CTL_HZ := 30.0
const GONE_GRACE := 0.6        # seconds something can be missing from snapshots before it's removed
const ECHO_TIME := 1.0         # an effect we just made ourselves stops the host's copy for this long...
const ECHO_DIST := 3.0         # ...if it's this close

## The effects a host may show on a friend's screen (B3Fx's shared ones, see
## "shared with friends" there) and what each one takes. Anything else in a
## packet is ignored.
const FX_ARGS := {
	"explosion": [TYPE_VECTOR3, TYPE_FLOAT, TYPE_INT],
	"flame": [TYPE_VECTOR3],
	"trail": [TYPE_VECTOR3, TYPE_FLOAT],
	"light": [TYPE_VECTOR3, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_COLOR],
	"scorch": [TYPE_VECTOR3, TYPE_FLOAT],
	"ring": [TYPE_VECTOR3, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_COLOR],
	"tracer": [TYPE_VECTOR3, TYPE_VECTOR3, TYPE_COLOR, TYPE_FLOAT],
	"beam": [TYPE_VECTOR3, TYPE_VECTOR3, TYPE_COLOR, TYPE_FLOAT, TYPE_FLOAT],
	"breath": [TYPE_VECTOR3, TYPE_VECTOR3, TYPE_FLOAT, TYPE_FLOAT],
	"hit_puff": [TYPE_VECTOR3, TYPE_VECTOR3],
	"muzzle": [TYPE_VECTOR3, TYPE_VECTOR3, TYPE_FLOAT],
	"sparks": [TYPE_VECTOR3, TYPE_INT],
	"poof": [TYPE_VECTOR3, TYPE_FLOAT],
	"dust": [TYPE_VECTOR3, TYPE_FLOAT],
	"steam": [TYPE_VECTOR3, TYPE_FLOAT],
	"heal": [TYPE_VECTOR3],
	"number": [TYPE_VECTOR3, TYPE_FLOAT],
	"word": [TYPE_VECTOR3, TYPE_STRING, TYPE_COLOR],
	"splash": [TYPE_VECTOR3, TYPE_BOOL],
	"nuke": [TYPE_VECTOR3],
	"chute": [TYPE_VECTOR3, TYPE_VECTOR3, TYPE_COLOR],      # 🪂 a pilot bailing out (B3Chute)
}

## The tables of a snapshot (see NetDelta), field by field after the id:
## fighters and vehicles: kind, team, size, where, facing (or the whole body's
## turn), flags (see _unit_entry), health, action, how far through it, speed,
## mood, velocity (knocked down only), a vehicle's own state, look (seed), and
## for whoever plays it, how ready its right-click power and its weapon are
## (B3Player.net_gauges: the meters).
const UNITS := [NetDelta.STR | NetDelta.ONCE, NetDelta.STR, NetDelta.FIX16, NetDelta.POS, NetDelta.ROT, NetDelta.U32, NetDelta.FRAC,
	NetDelta.STR, NetDelta.FRAC, NetDelta.FIX16, NetDelta.STR, NetDelta.VEL, NetDelta.NUMS, NetDelta.I64 | NetDelta.ONCE,
	NetDelta.FRAC, NetDelta.FRAC]
const PROPS := [NetDelta.STR | NetDelta.ONCE, NetDelta.POS, NetDelta.QUAT, NetDelta.U8]          # kind, where, turn, lit
const PROJS := [NetDelta.STR | NetDelta.ONCE, NetDelta.POS, NetDelta.VEL]                       # kind, where, velocity
const POOLS := [NetDelta.STR | NetDelta.ONCE, NetDelta.POS, NetDelta.FIX32, NetDelta.BOOL]       # kind, where, size, the puzzle's own
## buildings: kind, where, yaw, length, look (seed), the pieces still standing,
## a History building's whole shape (new ones only), the puzzle's own
const STRUCTS := [NetDelta.STR | NetDelta.ONCE, NetDelta.POS, NetDelta.F32, NetDelta.F32, NetDelta.I64 | NetDelta.ONCE, NetDelta.VAR,
	NetDelta.VAR | NetDelta.ONCE, NetDelta.BOOL]
const PLANES := [NetDelta.POS, NetDelta.VEL]                                                     # ✈️ airstrike planes
const CORPSES := [NetDelta.STR | NetDelta.ONCE, NetDelta.STR | NetDelta.ONCE, NetDelta.POSC]     # kind, team, where (roughly)
static var TABLES: Array = [["u", PackedInt32Array(UNITS)], ["p", PackedInt32Array(PROPS)], ["j", PackedInt32Array(PROJS)],
	["h", PackedInt32Array(POOLS)], ["s", PackedInt32Array(STRUCTS)], ["a", PackedInt32Array(PLANES)], ["c", PackedInt32Array(CORPSES)]]
## ...and the single values, sent only when they change: the battle state,
## the 🏆 scoreboard, rules, 🏁 battle goal, 🪙 points, players, 🧩 puzzle and the lock.
const SINGLES := ["st", "sb", "r", "md", "bg", "pl", "pz", "lk"]
## What a friend can't do when the host has locked the battle (allow_changes).
const LOCKED := ["place", "drop", "erase", "erase_corpse", "reset", "c4", "launch", "heal", "team", "mood"]
## Stickers a friend earns in the host's battle (knock-outs by the fighter they play).
const FRIEND_STICKERS := ["ace", "hero", "tankbuster"]
## flags (_unit_entry) bits past the ones B3Unit has
const F_PUZZLE := 1024     # 🧩 the puzzle's own army
const F_WAVE := 2048       # 🌊 a Wave Defense attacker
const F_ROUTED := 4096     # 🏳️ its King fell: running off home, arms waving (B3Modes)

var battle = null
var mode := ""                 # "host" or "client"
var peer: ENetMultiplayerPeer = null
var mp: SceneMultiplayer = null
var friends := {}              # host: peer id -> {name, color, ctl: B3Ctl, uid: int, ack: int, taps, kills}
var players: Array = []        # everyone: [{id, name, col, uid}] (the client gets it from the host)
var my_id := 1
var host_name := ""
var connected := false
var status := ""
# host
var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _snap_t := 0.0
var _snap_n := 0
var _fx: Array = []            # effects and sounds since the last snapshot
var _ev: Array = []            # reliable events
var _last_us := 0
var _tx := NetDelta.Sender.new(TABLES)
var _beacon_said := ""
var _strangers := {}           # rate limits for copies of the game that aren't friends yet
var allow_changes := true      # 🔒 friends may place, erase, blow things up and ⏮ reset (false: only play)
var bytes_out := 0             # bytes sent to friends (for tests)
# client
var puppets := {}              # host instance id -> our node (unit, prop, projectile, hazard, structure)
var corpses := {}              # host unit id -> our knocked-out ragdoll
var _seen := {}                # host id -> time last seen in a snapshot
var _clock := 0.0
var _play_asked := -10.0     # when we last asked the host to play a fighter
var _ctl_t := 0.0
var _banner := ""
var _tags := {}                # unit -> Label3D name tag over fighters people are playing
var fx_played := 0             # effects and sounds shown from the host (for tests)
var fx_skipped := 0            # ...and ones not shown because we'd just made them ourselves
var _made: Array = []          # client: [what, where, when] of effects this copy just made itself
var _replaying := false        # client: showing the host's effects right now
var _trees := PackedInt32Array()   # client: trees and rocks still standing in the host's battle when we joined
var _trees_map := ""
var _c4_shown := -1
var _rx := NetDelta.Receiver.new(TABLES)   # client: rebuilds whole snapshots from the host's changes
var _sb := PackedStringArray()             # client: the 🏆 scoreboard under the banner
var _taps := PackedInt32Array([0, 0, 0])   # client: jumps, clicks and right-clicks so far (see _client_tick)
var _held := [false, false]                # client: attack / right-click held last frame
var _jumped := false                       # client: a jump since the last controls packet
var _zone_map := ""                        # client: the map the glowing build area was laid on
var _pz_over := false                      # client: the 🧩 puzzle's ⭐ card is showing
var host_locked := false                   # client: the host has stopped friends changing the battle


func is_host() -> bool:
	return mode == "host"


func is_client() -> bool:
	return mode == "client"


func player_count() -> int:
	return players.size()


# ---------------------------------------------------------------- starting
func host() -> bool:
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_FRIENDS) != OK:
		peer = null
		return false
	_setup_mp()
	mode = "host"
	connected = true
	_beacon.set_broadcast_enabled(true)
	_last_us = Time.get_ticks_usec()
	_refresh_players()
	status = "Hosting on " + address_text()
	return true


func join(ip: String) -> bool:
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		peer = null
		return false
	_setup_mp()
	mode = "client"
	status = "Joining %s..." % ip
	_last_us = Time.get_ticks_usec()
	mp.connected_to_server.connect(func():
		connected = true
		my_id = mp.get_unique_id()
		_send({"m": "hello", "v": VERSION, "name": Settings.player_name, "color": Settings.player_color}, true))
	mp.connection_failed.connect(func(): _lost("Couldn't reach that game. Check the address and that it's on the same Wi-Fi."))
	mp.server_disconnected.connect(func(): _lost("The host left the battle."))
	return true


func _setup_mp() -> void:
	mp = SceneMultiplayer.new()
	mp.root_path = get_path()
	mp.multiplayer_peer = peer
	mp.peer_packet.connect(_on_packet)
	mp.peer_connected.connect(func(_id: int): pass)
	mp.peer_disconnected.connect(_on_peer_left)


func close() -> void:
	if is_client() and battle and is_instance_valid(battle) and not battle.is_queued_for_deletion():
		# the host's 🪙 points, glowing area and battle goal were for their battle
		if int(battle.budget) >= 0:
			battle.clear_budget()
		if battle.modes:
			battle.modes.apply_net([""])
		_puzzle([""])
	if mp and peer:
		if is_host():
			_send({"m": "bye", "why": "The host stopped sharing the battle."}, true)
		peer.close()
	if is_host():
		for id in friends:
			var f: Dictionary = friends[id]
			_unplay(f)
	peer = null
	mp = null
	_beacon.close()
	friends.clear()
	connected = false
	for t in _tags.values():
		if is_instance_valid(t):
			(t as Node).queue_free()
	_tags.clear()
	mode = ""


func _exit_tree() -> void:
	close()


static func address_text() -> String:
	var a := NetCommon.local_addresses()
	return ", ".join(a) if not a.is_empty() else "(no Wi-Fi address found)"


# --------------------------------------------------------------- recording
## Host: an effect or sound to show on friends' screens too.
## Friend: one this copy made itself (a puppet getting up, a wall piece
## breaking, a click's "pop"). The host makes the same one and sends it over,
## so when that arrives it isn't played a second time (see _echo).
func rec_fx(e: Array) -> void:
	if is_host() and not friends.is_empty():
		_fx.append(e)
		if _fx.size() > 400:
			_fx.pop_front()
	elif is_client() and not _replaying and not e.is_empty():
		_made.append([_fx_what(e), _fx_where(e), _clock])
		if _made.size() > 64:
			_made.pop_front()


## Host: something friends must not miss.
func rec_event(e: Array) -> void:
	if is_host() and not friends.is_empty():
		_ev.append(e)
		if e.size() > 1 and e[0] is String and String(e[0]) == "ko":
			_friend_ko(int(e[1]))


## Host: fighter `vid` was just knocked out. If the fighter or vehicle a
## friend is playing did it (its knock-outs just went up), that friend earns
## the 📒 stickers the host would for its own (B3Battle._ko_stickers).
func _friend_ko(vid: int) -> void:
	var o: Object = instance_from_id(vid) if vid != 0 else null
	var victim: B3Unit = o as B3Unit if o is B3Unit and is_instance_valid(o) else null
	for id in friends:
		var f: Dictionary = friends[id]
		var by: Object = instance_from_id(int(f.get("uid", 0))) if int(f.get("uid", 0)) != 0 else null
		if not (by is B3Unit) or not is_instance_valid(by) or (by as B3Unit).ctl != f.ctl:
			continue
		var bu := by as B3Unit
		if bu.kills <= int(f.get("kills", 0)):
			continue
		f.kills = bu.kills
		var got := B3Battle.ko_stickers_for(bu, victim, true)
		if not got.is_empty():
			_send({"m": "stk", "l": Array(got)}, true, id)


# ------------------------------------------------------------------- tick
func _process(_d: float) -> void:
	if mp == null:
		return
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.25)
	_last_us = now
	mp.poll()
	if mp == null:
		return
	if is_host():
		_host_tick(dt)
	else:
		_client_tick(dt)
	_update_tags()


func _host_tick(dt: float) -> void:
	# the beacon: once a second, and straight away when the map or the number of players changes
	_beacon_t -= dt
	var md: Dictionary = B3Defs.MAPS.get(battle.map_id, {})
	var bc := JSON.stringify({"game": GAME_ID, "v": VERSION, "name": Settings.player_name,
		"world": "%s %s" % [md.get("icon", ""), md.get("name", "")], "players": friends.size() + 1, "port": PORT})
	if _beacon_t <= 0.0 or bc != _beacon_said:
		_beacon_t = 1.0
		_beacon_said = bc
		_beacon.set_dest_address("255.255.255.255", NetCommon.BEACON_PORT)
		_beacon.put_packet(bc.to_utf8_buffer())
	# friends' fighters: drop control if the fighter is gone
	for id in friends:
		var f: Dictionary = friends[id]
		var u := _unit(int(f.get("uid", 0)))
		if int(f.get("uid", 0)) != 0 and (u == null or u.ctl != f.ctl):
			f.uid = 0
	if friends.is_empty():
		return
	if not _ev.is_empty():
		_send({"m": "ev", "list": _ev}, true)
		_ev = []
	_snap_t -= dt
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		_snap_n += 1
		_refresh_players()
		var st := delta_state(snapshot())
		_tx.push(st[0], st[1])
		for id in friends:
			# just what's changed since the last snapshot this friend got (all of it if none)
			var pkt := _tx.packet(int(friends[id].get("ack", -1)))
			bytes_out += pkt.size()
			mp.send_bytes(pkt, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, CH_SNAP)
		if not _fx.is_empty():
			_send({"m": "fx", "l": _fx}, true, 0, CH_FX)
			_fx = []


func _send(d: Dictionary, reliable: bool, to := 0, ch := -1) -> void:
	if mp == null or peer == null:
		return
	var pkt := NetCommon.encode(d)
	var m := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var c := ch if ch >= 0 else (0 if reliable else CH_SNAP)
	if to == 0 and is_host():
		# everyone who has said hello (not a copy of the game that's still saying it, or can't)
		for id in friends:
			bytes_out += pkt.size()
			mp.send_bytes(pkt, id, m, c)
		return
	bytes_out += pkt.size()
	mp.send_bytes(pkt, to, m, c)


## snapshot() split for NetDelta.Sender.push: [each table's entries, the single values].
static func delta_state(s: Dictionary) -> Array:
	var t := {}
	for tp: Array in TABLES:
		t[tp[0]] = s.get(tp[0], [])
	var g := {}
	for k: String in SINGLES:
		g[k] = s.get(k)
	return [t, g]


# ----------------------------------------------------------- host: friends
func _on_peer_left(id: int) -> void:
	if not is_host() or not friends.has(id):
		return
	var f: Dictionary = friends[id]
	_unplay(f)
	friends.erase(id)
	_refresh_players()
	if battle.ui:
		battle.ui.toast("%s left the battle" % f.name)
		battle.ui.refresh_net()


func _on_packet(id: int, pkt: PackedByteArray) -> void:
	var d := NetCommon.decode(pkt)
	var m := String(d.get("m", ""))
	if is_host():
		_host_packet(id, m, d)
	else:
		_client_packet(m, d)


func _host_packet(id: int, m: String, d: Dictionary) -> void:
	match m:
		"hello":
			if not (d.get("v") is int) or int(d.v) != VERSION:
				_send({"m": "bye", "why": NetCommon.WRONG_VERSION}, true, id)
				if battle.ui and NetCommon.allow(_strangers, "version", 0.2, 1.0):
					battle.ui.toast("👋 " + NetCommon.WRONG_VERSION, false)      # (just here: it's not about the friends already in)
				return
			if friends.has(id):
				return      # already said hello
			var c := B3Ctl.new()
			c.peer = id
			c.who = NetCommon.clean_name(d.get("name"))
			c.color = d.color if d.get("color") is Color else Color.WHITE
			friends[id] = {"name": c.who, "color": c.color, "ctl": c, "uid": 0, "ack": -1}
			var hi := {"m": "welcome", "id": id, "host": Settings.player_name}
			if battle.world and battle.world.scenery:
				hi["map"] = battle.map_id
				hi["trees"] = _standing_scenery()
			_send(hi, true, id)
			_refresh_players()
			Settings.award("friends")
			if battle.ui:
				battle.ui.toast("%s joined the battle! 👋" % c.who)
				battle.ui.refresh_net()
			battle.snd("pop", null, 0.7)
		"ctl":
			if friends.has(id) and d.get("a") is Array and ctl_ok(d.a):
				var ctl: B3Ctl = friends[id].ctl
				ctl.unpack(d.a)
				if (d.a as Array).size() > 9:
					_count_taps(friends[id], ctl, int(d.a[9]))
		"ak":
			# the last snapshot this friend got: the next ones only say what's changed since
			if friends.has(id) and d.get("n") is int:
				friends[id].ack = int(d.n)
		"cmd":
			if friends.has(id) and d.get("c") is Dictionary:
				_command(id, d.c)


## A friend's controls (B3Ctl.pack, then the counted presses): only real,
## sensible numbers get through (NaN or infinity would send their fighter
## flying off the map).
static func ctl_ok(a: Array) -> bool:
	if (a.size() != 9 and a.size() != 10) or not (a[8] is int):
		return false
	if a.size() == 10 and not (a[9] is int and int(a[9]) >= 0 and int(a[9]) < (1 << 24)):
		return false
	for i in [0, 1, 2, 3, 4, 6, 7]:
		if not NetCommon.num_ok(a[i], 1000.0):
			return false
	return NetCommon.vec3_ok(a[5])


## The friend's counts of jumps, clicks and right-clicks so far (8 bits
## each). Any that went up since their last packet happen now, even if the
## packet with the press in it got lost, or the button was let go before a
## packet went: a jump, one attack, one power.
static func _count_taps(f: Dictionary, ctl: B3Ctl, t: int) -> void:
	var last: Variant = f.get("taps")
	f["taps"] = t
	if not (last is int):
		return      # the first one: just where the counts start
	for k in 3:
		var n := ((t >> (8 * k)) - (int(last) >> (8 * k))) & 255
		if n == 0 or n > 64:
			continue
		match k:
			0:
				ctl.jump = true
			1:
				ctl.fire = true       # (the next packet says whether it's still held)
			2:
				ctl.fire2 = true


## The number a friend sent for something in the battle (0 if it isn't one).
static func _nid(c: Dictionary) -> int:
	var v: Variant = c.get("nid", 0)
	return int(v) if v is int else 0


## A friend pressed something: do it here, on the real battle. What they send
## is checked first: made-up names, NaN positions or things that aren't in
## this battle are ignored, and placing, dropping and the big buttons are
## rate-limited (a whole block of fighters counts one each). The puzzle's
## army and Wave Defense's attackers are hands off for friends too, and
## when the host has locked the battle (allow_changes) friends can only play.
func _command(id: int, c: Dictionary) -> void:
	var f: Dictionary = friends[id]
	var cmd: Variant = c.get("c", "")
	var cs := String(cmd) if cmd is String else ""
	if not allow_changes and LOCKED.has(cs):
		_tell(id, "🔒 %s has locked the battle: you can play fighters, but not change things." % Settings.player_name)
		return
	match cs:
		"place":
			var pc := _clean_place(c)
			if battle.tools and not pc.is_empty() and NetCommon.allow(f, "spawn", 8.0, 20.0):
				var what := String(pc.id)
				if not _can_place(id, what, pc.a, 0 if B3Defs.HAZARDS.has(what) else 1):
					return
				if B3Defs.HAZARDS.has(what) and int(battle.budget) >= 0 and battle.tools.has_method("_pool_r"):
					# 🪙 a pool costs what it is once it's dragged out: a Pool, or a Lake past 5 m
					var hd: Dictionary = B3Defs.HAZARDS[what]
					var r: float = battle.pool_room(pc.a, float(battle.tools.call("_pool_r", hd, pc.a, pc.b, pc.dragged)))
					if not _can_place(id, B3Battle.pool_id(String(hd.kind), r), pc.a):
						return
				if not NetCommon.allow(f, "units", 40.0, 160.0):
					_tell(id, "✋ Whoa, that's a lot! Wait a moment before placing more.")
					return
				var before: int = _things() + battle.props.size()
				battle.tools.place_for(pc)
				var made: int = _things() + battle.props.size() - before
				# a Shift-drag block can be 144 fighters: each one counts
				NetCommon.charge(f, "units", 40.0, 160.0, float(made - 1))
				if made == 0 and B3Defs.STRUCTS.has(what) and int(battle.budget) >= 0:
					_tell(id, "🚧 That sticks out past your side. Build it inside the glowing area!")
		"drop":
			var bid: Variant = c.get("id")
			var pos: Variant = c.get("pos")
			var dir: Variant = c.get("dir", Vector3.RIGHT)
			if not (bid is String and B3Defs.BOOMS.has(bid) and NetCommon.vec3_ok(pos) and NetCommon.vec3_ok(dir)):
				return
			if not NetCommon.allow(f, "spawn", 8.0, 20.0):
				return
			if bid == "nuke" and not NetCommon.allow(f, "nuke", 0.25, 1.0):
				return      # one nuke every few seconds is plenty
			if battle.puzzle != null and String(bid) in B3Puzzles.BIG_BOOMS:
				var bd: Dictionary = B3Defs.BOOMS[bid]
				_tell(id, "🚫 The %s %s is too big for a puzzle: it would blow up the whole thing! Try mines, barrels or C4." % [bd.icon, bd.name])
				return
			var at: Vector3 = pos
			var way: Vector3 = dir
			if not _can_place(id, String(bid), at):
				return
			battle.drop(String(bid), at, way, false)      # (the friend's boom: no stickers for the host)
		"erase":
			var o = _thing(_nid(c))
			if o != null and not _hands_ok(id, o as Node, "erase"):
				return
			if o is B3Unit:
				battle.remove_unit(o)
			elif o is B3Prop:
				battle.remove_prop(o)
			elif o is B3Struct:
				battle.remove_struct(o)
			elif o is B3Hazard:
				battle.remove_hazard(o, true)
		"erase_corpse":
			var cn := _nid(c)
			for rd: B3Ragdoll in battle.ragdolls:
				if is_instance_valid(rd) and cn != 0 and int(rd.get_meta("nid", 0)) == cn:
					battle.remove_ragdoll(rd)
					break
		"play":
			var u := _unit(_nid(c))
			if u == null or (u.ctl != null and u.ctl != f.ctl):
				_send({"m": "toast", "t": "Someone is already playing that one!"}, true, id)
				return
			if not _hands_ok(id, u, "play"):
				return
			_unplay(f)
			var ctl: B3Ctl = f.ctl
			ctl.clear_buttons()
			ctl.look_yaw = u.facing
			B3Player.attach(u, ctl)
			f.uid = u.get_instance_id()
			f.kills = u.kills      # (its knock-outs from now on are this friend's: _friend_ko)
			if not battle.fighting:
				battle.set_fighting(true)
			if battle.paused:
				battle.set_paused(false)
		"unplay":
			_unplay(f)
		"fight":
			if NetCommon.allow(f, "toggle", 4.0, 6.0):
				battle.toggle_play()
		"slowmo":
			# 🐢 G or the button on a friend's screen: the host's slow motion, for everyone
			if NetCommon.allow(f, "toggle", 4.0, 6.0):
				var on: Variant = c.get("on")
				battle.set_slowmo(bool(on) if on is bool else not battle.slowmo)
		"reset":
			if NetCommon.allow(f, "reset", 0.5, 2.0):
				battle.reset_battle()
		"c4":
			if NetCommon.allow(f, "toggle", 4.0, 6.0):
				battle.detonate_c4(false)
		"wave":
			# 🌊 ▶ Next wave (or start wave 1)
			# (only counted when there's a wave to start, so pressing it at other times costs nothing)
			if battle.modes and String(battle.modes.kind) == "waves" and String(battle.modes.phase) in ["build", "break"] \
					and NetCommon.allow(f, "wave", 0.5, 2.0):
				battle.modes.next_wave()
		"launch":
			var ul := _unit(_nid(c))
			if ul and _hands_ok(id, ul, "launch"):
				ul.knock_down(Vector3(randf_range(-4, 4), 18.0, randf_range(-4, 4)))
		"heal":
			var uh := _unit(_nid(c))
			if uh and _hands_ok(id, uh, "heal"):
				uh.hp = uh.max_hp
				battle.fx.heal(uh.center() + Vector3(0, 0.6, 0))
				battle.snd("heal", uh.position, 0.8)
		"team":
			var u2 := _unit(_nid(c))
			var t: Variant = c.get("t")
			if u2 and t is String and B3Defs.TEAM.has(t) and _hands_ok(id, u2, "team"):
				u2.set_team(String(t))
		"mood":
			var u3 := _unit(_nid(c))
			var p: Variant = c.get("p")
			if u3 and p is String and B3Defs.PERS.has(p) and _hands_ok(id, u3, "mood"):
				u3.set_personality(String(p))


## Fighters, buildings and pools in the battle (to count what a placing made).
func _things() -> int:
	return battle.units.size() + battle.structs.size() + battle.hazards.size()


## True if a friend may do `what` to `n` (B3Battle.hands_off: the 🧩
## puzzle's army, 🌊 the attackers...); if not, they're told why.
func _hands_ok(id: int, n: Node, what: String) -> bool:
	if not battle.has_method("hands_off"):
		return true
	var why := String(battle.call("hands_off", n, what))
	if why == "":
		return true
	_tell(id, why)
	return false


## A message at the top of friend `id`'s screen (not too many of them).
func _tell(id: int, txt: String) -> void:
	if friends.has(id) and NetCommon.allow(friends[id], "tell", 1.0, 3.0):
		_send({"m": "toast", "t": txt}, true, id)


## 🪙 Budget battles (🌊 Wave Defense, 🧩 puzzles): a friend can only place
## what there are points for, in the glowing area. If not, they're told why.
func _can_place(id: int, what: String, at: Vector3, count := 1) -> bool:
	if int(battle.budget) < 0:
		return true
	var why: String = battle.can_place(what, at, count)
	if why == "":
		return true
	_send({"m": "toast", "t": why}, true, id)
	return false


## A friend's Toy Box placement, rebuilt from only what makes sense
## (empty if anything is missing, made up or not a real number).
static func _clean_place(c: Dictionary) -> Dictionary:
	var id: Variant = c.get("id")
	var team: Variant = c.get("team", "red")
	var pers: Variant = c.get("pers", "auto")
	if not (id is String and (B3Defs.UNITS.has(id) or B3Defs.HAZARDS.has(id) or B3Defs.STRUCTS.has(id))):
		return {}
	if not (team is String and B3Defs.TEAM.has(team)) or not (pers is String and B3Defs.PERS.has(pers)):
		return {}
	var a: Variant = c.get("a")
	var b: Variant = c.get("b")
	if not NetCommon.vec3_ok(a) or not NetCommon.vec3_ok(b):
		return {}
	var size: Variant = c.get("size", 1.0)
	var yaw: Variant = c.get("yaw", 0.0)
	if not NetCommon.num_ok(size, 100.0) or not NetCommon.num_ok(yaw, 1000.0):
		return {}
	return {"id": id, "team": team, "pers": pers, "size": float(size), "a": a, "b": b, "yaw": float(yaw),
		"dragged": c.get("dragged") is bool and bool(c.dragged), "box": c.get("box") is bool and bool(c.box)}


func _unplay(f: Dictionary) -> void:
	var u := _unit(int(f.get("uid", 0)))
	if u and u.ctl == f.ctl:
		B3Player.detach(u)
	f.uid = 0


## The fighter or vehicle with this instance id, if it's still in this battle.
func _unit(id: int) -> B3Unit:
	if id == 0:
		return null
	var o: Object = instance_from_id(id)
	if o is B3Unit and is_instance_valid(o) and not (o as B3Unit).dead and (o as B3Unit).battle == battle:
		return o as B3Unit
	return null


## A fighter, barrel, building or pool of this battle by instance id (a friend
## names things this way), or null for anything else.
func _thing(id: int) -> Object:
	if id == 0:
		return null
	var o: Object = instance_from_id(id)
	if o == null or not is_instance_valid(o):
		return null
	if (o is B3Unit and battle.units.has(o)) or (o is B3Prop and battle.props.has(o)) \
			or (o is B3Struct and battle.structs.has(o)) or (o is B3Hazard and battle.hazards.has(o)):
		return o
	return null


func _refresh_players() -> void:
	var me_uid := 0
	if B3Player.active():
		me_uid = B3Player.unit.get_instance_id()
	players = [{"id": 1, "name": Settings.player_name, "col": Settings.player_color, "uid": me_uid}]
	for id in friends:
		var f: Dictionary = friends[id]
		players.append({"id": id, "name": f.name, "col": f.color, "uid": int(f.get("uid", 0))})


# --------------------------------------------------------- host: snapshot
func snapshot() -> Dictionary:
	var b = battle
	var us: Array = []
	for u: B3Unit in b.units:
		if not is_instance_valid(u) or u.dead:
			continue
		us.append(_unit_entry(u))
	var ps: Array = []
	for p: B3Prop in b.props:
		if is_instance_valid(p) and p.is_inside_tree():
			ps.append([p.get_instance_id(), p.kind, p.global_position, p.global_basis.get_rotation_quaternion(), int(p.lit)])
	var js: Array = []
	for c in b.proj_root.get_children():
		var pj := c as B3Proj
		if pj and not pj.is_queued_for_deletion():
			js.append([pj.get_instance_id(), pj.kind, pj.global_position, pj.vel])
	var hs: Array = []
	for h: B3Hazard in b.hazards:
		if is_instance_valid(h):
			hs.append([h.get_instance_id(), h.kind, h.position, h.radius, h.has_meta("puzzle")])
	var ss: Array = []
	for s: B3Struct in b.structs:
		if is_instance_valid(s) and not s.pieces.is_empty():
			s.number_pieces()
			var alive := PackedInt32Array()
			for pc in s.pieces:
				if is_instance_valid(pc):
					alive.append(int(pc.get_meta("pi", 0)))
			var shape: Variant = null
			if not B3Defs.STRUCTS.has(s.kind):
				# History battles' own pieces: the whole shape (only sent to friends
				# who haven't got this building yet; worked out again once a second)
				if not s.has_meta("net_shape") or _snap_n % 20 == 1:
					s.set_meta("net_shape", s.piece_data())
				shape = s.get_meta("net_shape")
			ss.append([s.get_instance_id(), s.kind, s.position, s.rotation.y, s.length, int(s.get_meta("seed", 0)), alive, shape, s.has_meta("puzzle")])
	var ap: Array = []
	for pl: Dictionary in b.planes:      # ✈️ airstrike planes
		var pn = pl.node
		if is_instance_valid(pn):
			var pv: Vector3 = pl.dir
			ap.append([(pn as Node3D).get_instance_id(), (pn as Node3D).global_position, pv * float(pl.speed)])
	var cs: Array = []
	for rd: B3Ragdoll in b.ragdolls:
		if is_instance_valid(rd) and rd.dead and rd.has_meta("nid"):
			cs.append([int(rd.get_meta("nid")), rd.kind, rd.team, rd.center()])
	# the winner banner's headline, and the 🏆 scoreboard under it as data (B3Battle.scoreboard)
	var head := ""
	if b.ui and b.ui.banner_lbl.visible:
		head = String(b.ui.banner_lbl.text).get_slice("\n", 0)
	var sb := PackedStringArray()
	if head != "" and String(b.winner) != "":
		sb = b.scoreboard()
	var pz: Array = [""]
	if b.puzzle != null and is_instance_valid(b.puzzle):
		pz = [String(b.puzzle.id), bool(b.puzzle.over), int(b.puzzle.won)]
	return {"m": "snap", "u": us, "p": ps, "j": js, "h": hs, "s": ss, "a": ap, "c": cs, "pl": players,
		"st": [b.map_id, b.fighting, b.paused, b.slowmo, head,
			b.ui.banner_lbl.get_theme_color("font_color") if b.ui else Color.WHITE, b.c4_count()],
		"sb": sb,
		"r": B3Rules.values.duplicate(),
		"md": b.modes.net_state() if b.modes else [""],
		"bg": [int(b.budget), int(b.spent), b.build_zone, String(b.build_team)],
		"pz": pz,
		"lk": not allow_changes}


## flags: 1 down, 2 aiming, 4 cheering, 8 on fire, 16 scared, 32 swooping, 64 played by someone, 128 held,
## 256 shield up (right-click, B3Player), 512 a 👑 King (B3Modes), 1024 the 🧩 puzzle's own (F_PUZZLE),
## 2048 a 🌊 Wave Defense attacker (F_WAVE), 4096 running away, its King fallen (F_ROUTED)
func _unit_entry(u: B3Unit) -> Array:
	var aiming: bool = (u.target != null or (u.player and B3Player.steady(u, u.ctl))) and b_fighting()
	var flags := int(u.down) | (int(aiming) << 1) | (int(u.cheer) << 2) | (int(u.burn_t > 0.0) << 3) \
		| (int(u.fleeing) << 4) | (int(u._swoop) << 5) | (int(u.player) << 6) | (int(u.held) << 7) | (int(u.shield_up) << 8) \
		| (int(u.king) << 9) | (F_PUZZLE if u.has_meta("puzzle") else 0) | (F_WAVE if u.has_meta("wave") else 0) \
		| (F_ROUTED if u.routed else 0)
	var pos: Vector3 = u.global_position
	var vel := Vector3.ZERO      # (only needed for knocking a friend's copy down the same way)
	if u.down and u.ragdoll and is_instance_valid(u.ragdoll):
		pos = u.ragdoll.center()
		u.ragdoll.set_meta("nid", u.get_instance_id())
		if is_instance_valid(u.ragdoll.root_body):
			vel = u.ragdoll.root_body.linear_velocity
	var rot: Variant = u.global_basis.get_rotation_quaternion() if u is B3Vehicle else u.facing
	var ns: Variant = u.call("net_state") if u.has_method("net_state") else null
	# how ready the power and the weapon are, for whoever plays it (their meters)
	var gauges := B3Player.net_gauges(u) if u.player else PackedFloat32Array([1.0, 1.0])
	return [u.get_instance_id(), u.kind, u.team, u.size_mult, pos, rot, flags, u.hp / maxf(1.0, u.max_hp),
		u.act, u.act_t / maxf(u.act_len, 0.01), u._spd, u.pers, vel, ns, int(u.get_meta("seed", -1)),
		gauges[0], gauges[1]]


func b_fighting() -> bool:
	return battle.fighting


## The numbers of the trees and rocks still standing here (B3World.scenery_index),
## so a friend who joins late can take away the ones blasts have knocked over.
func _standing_scenery() -> PackedInt32Array:
	var out := PackedInt32Array()
	var sc: Node = battle.world.scenery
	for n in sc.get_children():
		if n.has_meta("sid") and not n.has_meta("gone") and not n.is_queued_for_deletion():
			out.append(int(n.get_meta("sid")))
	return out


# ------------------------------------------------------------------ client
func _client_packet(m: String, d: Dictionary) -> void:
	match m:
		"welcome":
			my_id = int(d.get("id", my_id))
			host_name = String(d.get("host", "your friend"))
			status = "In %s's battle" % host_name
			battle.puppet = true
			if d.get("trees") is PackedInt32Array and d.get("map") is String:
				_trees = d.trees       # taken away once we're on the host's map (_apply_snapshot)
				_trees_map = d.map
			Settings.award("friends")      # 📒 played together (the host gets it too)
			if battle.ui:
				battle.ui.toast("👋 You joined %s's battle!" % host_name)
				battle.ui.refresh_net()
		"bye":
			var why: Variant = d.get("why")
			_lost(String(why).left(200) if why is String else "The host left the battle.")
		"toast":
			if battle.ui and d.get("t") is String:
				battle.ui.toast(String(d.t).left(200))
		"ev":
			if d.get("list") is Array:
				for e in d.list:
					if e is Array:
						_apply_event(e)
		"fx":
			# the host's effects and sounds (reliable: the nuke's flash can't get lost)
			if d.get("l") is Array and battle.puppet:
				for e in (d.l as Array).slice(0, 800):
					if e is Array:
						_play_fx(e)
		"stk":
			# 📒 the fighter we play knocked someone out (see _friend_ko)
			if d.get("l") is Array:
				for k in (d.l as Array).slice(0, 4):
					if k is String and FRIEND_STICKERS.has(k):
						B3Battle.give_ko_sticker(String(k))
		"snap":
			if not _rx.take(d):
				if _rx.need_full:
					_send({"m": "ak", "n": -1}, false)      # one we can't use: ask for all of it
				return
			_send({"m": "ak", "n": _rx.last}, false)
			_apply_snapshot(_rx.snapshot())


func _lost(why: String) -> void:
	var b = battle
	close()
	if b and b.has_method("net_lost"):
		b.net_lost(why)


func send_cmd(c: Dictionary) -> void:
	if String(c.get("c", "")) == "play":
		_play_asked = _clock
	_send({"m": "cmd", "c": c}, true)


func _client_tick(dt: float) -> void:
	_clock += dt
	if not connected:
		return
	# my controls go to the host. Presses that happen once are counted every
	# frame, and each packet says the counts so far (see _count_taps): a packet that
	# gets lost, or a click let go before the next packet, can't lose one.
	var me := B3Player.me
	if B3Player.unit != null:
		if me.jump:
			_taps[0] = (_taps[0] + 1) & 255
			_jumped = true
			me.jump = false
		if me.fire and not _held[0]:
			_taps[1] = (_taps[1] + 1) & 255
		if me.fire2 and not _held[1]:
			_taps[2] = (_taps[2] + 1) & 255
		_held = [me.fire, me.fire2]
	_ctl_t -= dt
	if B3Player.unit != null and _ctl_t <= 0.0:
		_ctl_t = 1.0 / CTL_HZ
		var a := me.pack()
		if _jumped:
			a[8] = int(a[8]) | 4
			_jumped = false
		a.append(_taps[0] | (_taps[1] << 8) | (_taps[2] << 16))
		_send({"m": "ctl", "a": a}, false)
	# glide puppets toward where the host says they are
	var k := minf(1.0, dt * 14.0)
	for id in puppets.keys():
		var n = puppets[id]
		if not is_instance_valid(n):
			puppets.erase(id)
			continue
		var node := n as Node3D
		if not node.has_meta("np"):
			continue
		var to: Vector3 = node.get_meta("np")
		if n is B3Proj:
			var pj := n as B3Proj
			to += pj.vel * (_clock - float(node.get_meta("nt", _clock)))
			node.global_position = node.global_position.lerp(to, k)
			pj._orient()
			continue
		if n is B3Unit:
			var u := n as B3Unit
			u.hurt_t += dt
			if u.down:
				continue
			node.global_position = node.global_position.lerp(to, k) if node.global_position.distance_to(to) < 6.0 else to
			var r: Variant = node.get_meta("nr")
			if r is Quaternion:
				node.global_basis = Basis(node.global_basis.get_rotation_quaternion().slerp(r as Quaternion, k))
				_face_body(u)
			elif r is float:
				u.facing = lerp_angle(u.facing, float(r), k)
				if u.rig:
					u.rig.rotation.y = u.facing
			continue
		if node.has_meta("nv"):
			# airstrike planes fly on between snapshots
			var nv: Vector3 = node.get_meta("nv")
			to += nv * (_clock - float(node.get_meta("nt", _clock)))
		node.global_position = node.global_position.lerp(to, k) if node.global_position.distance_to(to) < 6.0 else to
		var q: Variant = node.get_meta("nr") if node.has_meta("nr") else null
		if q is Quaternion:
			node.global_basis = Basis(node.global_basis.get_rotation_quaternion().slerp(q as Quaternion, k))
	# our own effects that the host's copy never came back for
	while not _made.is_empty() and _clock - float(_made[0][2]) > ECHO_TIME:
		_made.pop_front()
	# things gone from the host's battle
	for id in _seen.keys():
		if _clock - float(_seen[id]) > GONE_GRACE:
			_seen.erase(id)
			var n2 = puppets.get(id)
			puppets.erase(id)
			if n2 != null and is_instance_valid(n2):
				_remove_puppet(n2)


func _remove_puppet(n: Node) -> void:
	var b = battle
	if n is B3Unit:
		b.remove_unit(n as B3Unit, false)
	elif n is B3Prop:
		b.remove_prop(n as B3Prop, false)
	elif n is B3Hazard:
		b.remove_hazard(n as B3Hazard, false)
	elif n is B3Struct:
		b.remove_struct(n as B3Struct, false)
	else:
		n.queue_free()


func _apply_snapshot(s: Dictionary) -> void:
	var b = battle
	if not b.puppet:
		return
	var st: Array = s.get("st", [])
	if st.size() >= 7:
		var map_s := String(st[0])
		if map_s != b.map_id:
			_wipe()
			b.load_map(map_s)
		if bool(st[1]) != b.fighting:
			b.fighting = bool(st[1])
			if b.ui:
				b.ui.refresh()
		if bool(st[2]) != b.paused:
			b.set_paused(bool(st[2]))
		if bool(st[3]) != b.slowmo:
			b.set_slowmo(bool(st[3]))      # 🐢 the host's slow motion (and time) for everyone
		# the winner banner, with the 🏆 scoreboard under it (sent as data: "sb")
		var bt := String(st[4]).get_slice("\n", 0).left(200)
		var sbv: Variant = s.get("sb")
		var sb: PackedStringArray = PackedStringArray((sbv as PackedStringArray).slice(0, 24)) if sbv is PackedStringArray else PackedStringArray()
		if (bt != _banner or sb != _sb) and b.ui:
			_banner = bt
			_sb = sb
			if bt == "":
				b.ui.hide_banner()
			else:
				b.ui.banner(bt, st[5] if st[5] is Color else Color.WHITE, sb)
	host_locked = s.get("lk") is bool and bool(s.lk)
	if _trees_map != "":
		if _trees_map == b.map_id:
			_take_away_scenery()
		else:
			_trees_map = ""      # the host has moved to another map since (with all its trees)
	var rules: Dictionary = _host_rules(s.get("r") if s.get("r") is Dictionary else {})
	if not rules.is_empty() and rules.hash() != B3Rules.values.hash():
		B3Rules.values = rules     # just for this battle; not saved over your own rules
		b.apply_rules()
		if b.ui:
			b.ui.refresh()
	if b.modes:
		b.modes.apply_net(s.get("md"))     # 🏁 the hill, the Kings' health, 🌊 the wave
	_puzzle(s.get("pz"))
	_budget(s.get("bg"))
	var pl: Variant = s.get("pl", [])
	players = []
	if pl is Array:
		for p in (pl as Array).slice(0, MAX_FRIENDS + 1):
			if p is Dictionary:
				players.append(p)
	for p: Dictionary in players:
		if int(p.get("id", 0)) != my_id or not B3Player.playing or _clock - _play_asked <= 1.0:
			continue      # (not just after asking to play one, while the answer is on its way)
		var uid := int(p.get("uid", 0)) if p.get("uid") is int else 0
		var mine := B3Player.unit
		var mine_id := int(mine.get_meta("nid", 0)) if mine != null and is_instance_valid(mine) else 0
		if uid == 0:
			# the host says we're not playing anything (our fighter got knocked out)
			if b.tools:
				b.tools.player_lost()
		elif uid != mine_id:
			# the host kept us on another one (⇥ Tab's pick was taken or knocked
			# out on the way): look out of the one we really steer
			var u = puppets.get(uid)
			if u is B3Unit and is_instance_valid(u) and not (u as B3Unit).dead:
				_play_here(u as B3Unit)
			elif b.tools:
				b.tools.player_lost()
	for e in s.get("s", []):
		_struct(e)
	for e in s.get("h", []):
		_hazard(e)
	for e in s.get("p", []):
		_prop(e)
	if st.size() >= 7 and int(st[6]) != _c4_shown and b.ui:
		_c4_shown = int(st[6])     # C4 lit or placed: the Detonate button shows how many are left
		b.ui.refresh_c4()
	for e in s.get("u", []):
		_unit_apply(e)
	for e in s.get("j", []):
		_proj(e)
	for e in s.get("a", []):
		_plane(e)
	if s.has("c"):
		var live := {}
		for e in s.c:
			live[int(e[0])] = true
			_corpse(e)
		for nid in corpses.keys():
			var rd = corpses[nid]
			if live.has(nid) or (is_instance_valid(rd) and _clock - float((rd as Node).get_meta("net_born", -10.0)) < 1.0):
				continue      # (a knock-out's reliable "ko" can come before the snapshot that has it)
			corpses.erase(nid)
			if is_instance_valid(rd):
				b.remove_ragdoll(rd, false)
	if b.ui:
		b.ui.counts_dirty = true


## Look out of `u`, the one the host says we're playing (without asking it again).
func _play_here(u: B3Unit) -> void:
	var fp := B3Player.me.fp
	B3Player.start(u)
	battle.cam.follow = u
	if battle.tools:
		battle.tools.set_first_person(fp)


## 🧩 The host's puzzle: its goal at the top of the Toy Box, and the ⭐ card
## (or Try again) when the fight's over. A friend's copy has the puzzle's
## goal but none of its own rules (the host runs those); a win gives the
## friend the stars too.
func _puzzle(pz: Variant) -> void:
	var b = battle
	if not (pz is Array) or (pz as Array).is_empty() or not ((pz as Array)[0] is String):
		return
	var a: Array = pz
	var pid := String(a[0])
	if pid != "" and (a.size() < 3 or B3Puzzles.info(pid).is_empty() or not (a[1] is bool) or not (a[2] is int)):
		return
	var cur = b.puzzle
	if pid == "":
		if cur != null:
			b.puzzle = null
			if is_instance_valid(cur):
				(cur as Node).queue_free()
			_pz_over = false
			if b.ui:
				b.ui.show_puzzle()
		return
	if cur == null or not is_instance_valid(cur) or String(cur.id) != pid:
		if cur != null and is_instance_valid(cur):
			(cur as Node).queue_free()
		var p := B3Puzzles.new()
		p.name = "NetPuzzle"
		p.b = b
		p.id = pid
		p.stage = B3Puzzles.info(pid)
		b.add_child(p)
		p.set_physics_process(false)      # (its guards and the ⭐ are the host's job)
		b.puzzle = p
		_pz_over = false
		cur = p
		if b.ui:
			b.ui.show_puzzle()
	var over := bool(a[1])
	var won := clampi(int(a[2]), 0, 3)
	cur.over = over
	cur.won = won
	if over and not _pz_over:
		_pz_over = true
		var best := B3Puzzles.stars(pid)
		if won > best:
			Settings.puzzle_won(pid, won)
		if b.ui:
			b.ui.puzzle_result(won, best, "")      # (only the host can go on to the next one)
	elif not over and _pz_over:
		_pz_over = false
		if b.ui:
			b.ui.show_puzzle()


## 🪙 The host's points to spend and the glowing area to build in (a budget
## battle): the coins at the top and the glowing area show here too.
func _budget(bg: Variant) -> void:
	if not (bg is Array) or (bg as Array).size() != 4:
		return
	var a: Array = bg
	if not (a[0] is int) or not (a[1] is int) or not (a[2] is Rect2) or not (a[3] is String):
		return
	var zone: Rect2 = a[2]
	if not (NetCommon.vec2_ok(zone.position) and NetCommon.vec2_ok(zone.size)):
		return
	var b = battle
	var pts := clampi(int(a[0]), -1, 999999)
	var team := String(a[3]) if B3Defs.TEAM.has(String(a[3])) else ""
	# (the same area on another map, like 🧩 puzzles 1 to 4, is laid on new ground)
	var moved: bool = pts >= 0 and zone.size != Vector2.ZERO and (_zone_map != b.map_id or b.zone_vis == null or not is_instance_valid(b.zone_vis))
	if zone != b.build_zone or team != b.build_team or (pts < 0) != (int(b.budget) < 0) or moved:
		if pts < 0:
			b.clear_budget()
		else:
			b.set_budget(pts, zone, team)
		_zone_map = b.map_id
	var sp := clampi(int(a[1]), 0, 999999)
	if pts != int(b.budget) or sp != int(b.spent):
		b.budget = pts
		b.spent = sp
		b.budget_changed.emit()


func _seen_now(id: int) -> void:
	_seen[id] = _clock


func _unit_apply(e: Array) -> void:
	if e.size() < 14:
		return
	var b = battle
	var id := int(e[0])
	_seen_now(id)
	var pos: Vector3 = e[4]
	var u: B3Unit = puppets.get(id)
	if u != null and not is_instance_valid(u):
		u = null
	if u == null:
		var yaw: float = float(e[5]) if e[5] is float else 0.0
		u = b.spawn_unit(String(e[1]), String(e[2]), pos, String(e[11]), yaw, float(e[3]), int(e[14]) if e.size() > 14 else -1)
		if u == null:
			return
		_make_puppet(u, id)
		u.global_position = pos
		if e[5] is Quaternion:
			u.global_basis = Basis(e[5] as Quaternion)
			_face_body(u)
		puppets[id] = u
	if u.team != String(e[2]):
		u.set_team(String(e[2]))
	u.set_meta("np", pos)
	u.set_meta("nr", e[5])
	var flags := int(e[6])
	var hpk := float(e[7])
	if hpk * u.max_hp < u.hp - 0.5:
		u.hurt_t = 0.0
	u.hp = hpk * u.max_hp
	u.act = String(e[8])
	u.act_len = 1.0
	u.act_t = float(e[9])
	u._spd = float(e[10])
	u.pers = String(e[11])
	u.target = u if flags & 2 != 0 else null
	u.cheer = flags & 4 != 0
	u.burn_t = 1.0 if flags & 8 != 0 else 0.0
	u.fleeing = flags & 16 != 0
	u._swoop = flags & 32 != 0
	u.shield_up = flags & 256 != 0
	if flags & 512 != 0 and not u.king:
		u.make_king()       # 👑 just the crown: its health comes from the host
	u.routed = flags & F_ROUTED != 0      # 🏳️ arms waving as it runs off
	# hands off (B3Battle.protected): the 🧩 puzzle's army, 🌊 the attackers
	for fm: Array in [[F_PUZZLE, "puzzle"], [F_WAVE, "wave"]]:
		if flags & int(fm[0]) != 0:
			u.set_meta(String(fm[1]), true)
		elif u.has_meta(String(fm[1])):
			u.remove_meta(String(fm[1]))
	if e.size() > 16 and flags & 64 != 0:
		B3Player.set_net_gauges(u, [e[15], e[16]])      # the power and reload meters of whoever plays it
	elif u.has_meta("net_gauges"):
		u.remove_meta("net_gauges")
	var down := flags & 1 != 0
	if down and not u.down:
		u.knock_down(e[12] if e[12] is Vector3 else Vector3.ZERO)
		u.freeze = true
	elif not down and u.down:
		u.get_up()
		_make_puppet(u, id)
		u.global_position = pos
	elif down and u.ragdoll and is_instance_valid(u.ragdoll):
		_nudge(u.ragdoll, pos)
	if e[13] != null and u.has_method("apply_net_state"):
		u.call("apply_net_state", e[13])


## Vehicles come over as a whole turned body; keep `facing` (which way first
## person looks when you climb in) pointing the way the body does.
func _face_body(u: B3Unit) -> void:
	var fz := u.global_basis.z
	if Vector2(fz.x, fz.z).length() > 0.1:
		u.facing = atan2(fz.x, fz.z)


## Turns a freshly made fighter into a puppet: no physics or brain of its own.
func _make_puppet(n: Node, id: int) -> void:
	n.set_meta("nid", id)
	n.set_physics_process(false)
	if n is RigidBody3D:
		var rb := n as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
	if n is Node3D:
		(n as Node3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Moves our ragdoll to where the host's is if they've drifted far apart.
func _nudge(rd: B3Ragdoll, to: Vector3) -> void:
	var off := to - rd.center()
	if off.length() < 2.5:
		return
	for body in rd.bodies:
		if is_instance_valid(body):
			body.global_position += off


func _corpse(e: Array) -> void:
	var nid := int(e[0])
	var at: Vector3 = e[3]
	var rd = corpses.get(nid)
	if rd != null and is_instance_valid(rd):
		_nudge(rd, at)
		return
	# someone knocked out before we joined (or we missed it): make one
	var u: B3Unit = puppets.get(nid)
	if u == null or not is_instance_valid(u):
		u = battle.spawn_unit(String(e[1]), String(e[2]), at, "peaceful", 0.0)
		if u == null:
			return
		_make_puppet(u, nid)
	_knock_out(u, nid, Vector3.ZERO)


## A puppet fighter goes down for good: ragdoll with X eyes (vehicles break apart).
func _knock_out(u: B3Unit, nid: int, vel: Vector3) -> void:
	var b = battle
	puppets.erase(nid)
	_seen.erase(nid)
	if u is B3Vehicle and u.has_method("_wreck"):
		u.freeze = false
		u.call("_wreck", vel, null)
		return
	if not u.down:
		u.knock_down(vel)
	if u.ragdoll and is_instance_valid(u.ragdoll):
		var rd := u.ragdoll
		rd.set_meta("nid", nid)
		rd.set_meta("net_born", _clock)
		rd.set_dead()
		corpses[nid] = rd
		u.dead = true
		b.units.erase(u)
		if b.ui:
			b.ui.counts_dirty = true
	else:
		b.remove_unit(u, false)


func _apply_event(e: Array) -> void:
	if e.is_empty():
		return
	var b = battle
	match String(e[0]):
		"ko":
			var nid := int(e[1])
			var u: B3Unit = puppets.get(nid)
			if u != null and is_instance_valid(u):
				_knock_out(u, nid, e[2] if e.size() > 2 and e[2] is Vector3 else Vector3.ZERO)
		"rm":
			var n = puppets.get(int(e[1]))
			puppets.erase(int(e[1]))
			if n != null and is_instance_valid(n):
				_remove_puppet(n)
		"brk":
			var s = puppets.get(int(e[1]))
			if s is B3Struct and is_instance_valid(s):
				for pc in (s as B3Struct).pieces:
					if is_instance_valid(pc) and int(pc.get_meta("pi", -1)) == int(e[2]):
						b.break_piece(pc, e[3] if e[3] is Vector3 else Vector3.ZERO, bool(e[4]))
						break
		"uproot":
			if b.world.has_method("uproot_index"):
				b.world.call("uproot_index", int(e[1]), e[2] if e[2] is Vector3 else Vector3.UP, b)
		"burn":
			_burn(e)
		"toast":
			if b.ui:
				b.ui.toast(String(e[1]))


## 🔥 The host says a wooden building piece (["burn", "p", building, piece
## number]) or a tree (["burn", "t", scenery number]) caught fire (B3Fire).
func _burn(e: Array) -> void:
	if e.size() < 3 or not (e[1] is String) or not (e[2] is int):
		return      # (a building's number is a big one: B3Net ids are instance ids)
	var b = battle
	var n: Node = null
	if String(e[1]) == "t":
		var bs: Variant = b.world.get("_by_sid")
		if bs is Dictionary:
			var o: Variant = (bs as Dictionary).get(int(e[2]))
			if o is Node and is_instance_valid(o):
				n = o as Node
	elif String(e[1]) == "p" and e.size() > 3 and e[3] is int:
		var s = puppets.get(int(e[2]))
		if s is B3Struct and is_instance_valid(s):
			for pc in (s as B3Struct).pieces:
				if is_instance_valid(pc) and int(pc.get_meta("pi", -1)) == int(e[3]):
					n = pc
					break
	if n != null:
		B3Fire.of(b).net_ignite(n)


func _struct(e: Array) -> void:
	var id := int(e[0])
	_seen_now(id)
	var s: B3Struct = puppets.get(id)
	if s == null or not is_instance_valid(s):
		if B3Defs.STRUCTS.has(String(e[1])):
			s = battle.spawn_struct(String(e[1]), e[2], float(e[3]), float(e[4]), int(e[5]))
		elif e.size() > 7 and e[7] is Array:
			s = battle.spawn_custom_struct(String(e[1]), e[2], float(e[3]), e[7])
		if s == null:
			return
		s.set_meta("nid", id)
		s.set_meta("born", _clock)
		puppets[id] = s
	if e.size() > 8 and bool(e[8]) != s.has_meta("puzzle"):
		if bool(e[8]):
			s.set_meta("puzzle", true)       # 🧩 the puzzle's own building: hands off
		else:
			s.remove_meta("puzzle")
	if _clock - float(s.get_meta("born", 0.0)) < 1.0:
		return
	# pieces the host has lost (broken while we weren't looking)
	var alive := {}
	for i in e[6]:
		alive[int(i)] = true
	for pc in s.pieces.duplicate():
		if is_instance_valid(pc) and not alive.has(int(pc.get_meta("pi", -1))):
			battle.break_piece(pc, Vector3.ZERO, true)


func _hazard(e: Array) -> void:
	var id := int(e[0])
	_seen_now(id)
	var h: B3Hazard = puppets.get(id)
	if h == null or not is_instance_valid(h):
		# the volcano's own pools come with the map
		for o: B3Hazard in battle.hazards:
			if is_instance_valid(o) and not o.has_meta("nid") and o.kind == String(e[1]) and o.position.distance_to(e[2]) < 0.6:
				h = o
				break
		if h == null:
			h = battle.spawn_hazard(String(e[1]), e[2], float(e[3]), -1.0)
		h.set_meta("nid", id)
		puppets[id] = h
	if e.size() > 4 and bool(e[4]) != h.has_meta("puzzle"):
		if bool(e[4]):
			h.set_meta("puzzle", true)       # 🧩 the puzzle's own pool: hands off
		else:
			h.remove_meta("puzzle")


func _prop(e: Array) -> void:
	var id := int(e[0])
	_seen_now(id)
	var p: B3Prop = puppets.get(id)
	if p == null or not is_instance_valid(p):
		p = battle.spawn_prop(String(e[1]), e[2], 0.0)
		_make_puppet(p, id)
		p.global_position = e[2]
		puppets[id] = p
	p.set_meta("np", e[2])
	p.set_meta("nr", e[3])
	p.lit = int(e[4]) != 0


func _proj(e: Array) -> void:
	var id := int(e[0])
	_seen_now(id)
	var pj: B3Proj = puppets.get(id)
	if pj == null or not is_instance_valid(pj):
		pj = battle.spawn_proj(String(e[1]), e[2], e[3], null, {})
		_make_puppet(pj, id)
		puppets[id] = pj
	pj.vel = e[3]
	pj.set_meta("np", e[2])
	pj.set_meta("nt", _clock)


## Shows one of the host's effects or sounds here. Only the ones in FX_ARGS
## (plus sounds and shakes), and only with the right kinds of values.
func _play_fx(e: Array) -> void:
	if e.is_empty() or not (e[0] is String):
		return
	var b = battle
	var name_s := String(e[0])
	var args: Array = []
	match name_s:
		"snd":
			if e.size() != 5 or not (e[1] is String) or not _at_ok(e[2]) or not NetCommon.num_ok(e[3]) or not NetCommon.num_ok(e[4]):
				return
		"shake":
			if e.size() != 3 or not NetCommon.num_ok(e[1]) or not _at_ok(e[2]):
				return
		_:
			args = _fx_args(name_s, e)
			if args.is_empty():
				return      # not an effect we know, or junk in it
	if _echo(e):
		fx_skipped += 1
		return
	fx_played += 1
	_replaying = true
	match name_s:
		"snd":
			b.snd(String(e[1]), e[2], clampf(float(e[3]), 0.0, 2.0), clampf(float(e[4]), 0.25, 4.0))
		"shake":
			b.shake(clampf(float(e[1]), 0.0, 2.0), e[2])
		_:
			b.fx.callv(name_s, args)
			if name_s == "nuke":
				# the host's own screen flashes white and shakes hard too (battle3d.gd nuke_blast)
				if b.ui:
					b.ui.flash(1.0)
				b.cam.shake(1.6)
	_replaying = false


## A sound's place: somewhere real, or nowhere (null: heard everywhere).
static func _at_ok(at: Variant) -> bool:
	return typeof(at) == TYPE_NIL or NetCommon.vec3_ok(at)


## The arguments for B3Fx effect `name_s` from packet entry `e`, checked
## against FX_ARGS ([] if the name isn't allowed or anything is the wrong kind).
static func _fx_args(name_s: String, e: Array) -> Array:
	if not FX_ARGS.has(name_s):
		return []
	var want: Array = FX_ARGS[name_s]
	if e.size() != want.size() + 1:
		return []
	var out: Array = []
	for i in want.size():
		var v: Variant = e[i + 1]
		match int(want[i]):
			TYPE_VECTOR3:
				if not NetCommon.vec3_ok(v):
					return []
				out.append(v)
			TYPE_FLOAT:
				if not NetCommon.num_ok(v):
					return []
				out.append(float(v))
			TYPE_INT:
				if not NetCommon.num_ok(v):
					return []
				out.append(int(v))
			TYPE_COLOR:
				if not (v is Color):
					return []
				out.append(v)
			TYPE_STRING:
				if not (v is String) or (v as String).length() > 40:
					return []
				out.append(v)
			TYPE_BOOL:
				if not (v is bool):
					return []
				out.append(v)
	return out


## What an effect is, for matching our own copy of it ("snd:boing", "dust"...).
static func _fx_what(e: Array) -> String:
	var n := String(e[0]) if e[0] is String else ""
	if n == "snd" and e.size() > 1:
		return "snd:" + String(e[1]) if e[1] is String else "snd"
	return n


## Where an effect is (null for sounds heard everywhere).
static func _fx_where(e: Array) -> Variant:
	var i := 2 if String(e[0]) in ["snd", "shake"] else 1
	return e[i] if e.size() > i and e[i] is Vector3 else null


## True if this copy just made the same effect itself, in about the same
## place (see rec_fx): then the host's one is an echo and isn't shown again.
func _echo(e: Array) -> bool:
	var what := _fx_what(e)
	var at: Variant = _fx_where(e)
	for i in _made.size():
		var m: Array = _made[i]
		if String(m[0]) != what or _clock - float(m[2]) > ECHO_TIME:
			continue
		var mat: Variant = m[1]
		if (at is Vector3) != (mat is Vector3):
			continue
		if at is Vector3 and (at as Vector3).distance_to(mat as Vector3) > ECHO_DIST:
			continue
		_made.remove_at(i)
		return true
	return false


## The host's rules for this battle, but your own ⚙️ Screen shake (that's how
## you like to watch, not a rule). Only known rules with known choices.
static func _host_rules(r: Dictionary) -> Dictionary:
	if r.is_empty():
		return {}
	var out := {}
	for o: Dictionary in B3Rules.OPTIONS:
		var id: String = o.id
		var v: Variant = r.get(id)
		var ok := false
		for ch: Array in o.choices:
			if v is String and String(ch[0]) == v:
				ok = true
		out[id] = String(v) if ok else String(B3Rules.DEFAULTS[id])
	out["shake"] = B3Rules.value("shake")
	return out


## Trees and rocks the host's blasts knocked over before we joined: gone here too.
func _take_away_scenery() -> void:
	var b = battle
	var keep := {}
	for i in _trees:
		keep[i] = true
	_trees = PackedInt32Array()
	_trees_map = ""
	var gone: Array = []
	for n in b.world.scenery.get_children():
		if n.has_meta("sid") and not n.has_meta("gone") and not n.is_queued_for_deletion() and not keep.has(int(n.get_meta("sid"))):
			gone.append(n)      # (the old map's scenery is still here until the end of this frame)
	for n in gone:
		var before: int = b.chunks.size()
		b.world.uproot(n, Vector3.ZERO, b)
		if b.chunks.size() > before:
			b.remove_chunk(b.chunks[b.chunks.size() - 1], false)


## An airstrike plane flying over (the host's drops the bombs).
func _plane(e: Array) -> void:
	if e.size() < 3 or not NetCommon.vec3_ok(e[1]) or not NetCommon.vec3_ok(e[2]):
		return
	var id := int(e[0])
	_seen_now(id)
	var vel: Vector3 = e[2]
	var n = puppets.get(id)
	if n == null or not is_instance_valid(n):
		var pl := _plane_model()
		battle.proj_root.add_child(pl)
		_make_puppet(pl, id)
		pl.global_position = e[1]
		if Vector2(vel.x, vel.z).length() > 0.1:
			pl.global_basis = Basis.looking_at(vel.normalized(), Vector3.UP, true)
		puppets[id] = pl
		n = pl
	(n as Node3D).set_meta("np", e[1])
	(n as Node3D).set_meta("nv", vel)
	(n as Node3D).set_meta("nt", _clock)


## The airstrike plane, built like the host's (battle3d.gd airstrike()).
static func _plane_model() -> Node3D:
	var plane := Node3D.new()
	plane.set_meta("plane", true)
	var body := B3Mats.mat(Color("8a96a8"), 0.5)
	B3Mats.add(plane, B3Mats.capsule(0.6, 6.0), body, Vector3.ZERO, Vector3(90, 0, 0))
	B3Mats.add(plane, B3Mats.box(Vector3(9.0, 0.15, 1.6)), body, Vector3(0, 0, 0.2))
	B3Mats.add(plane, B3Mats.box(Vector3(3.2, 0.12, 0.9)), body, Vector3(0, 0.1, -2.6))
	B3Mats.add(plane, B3Mats.box(Vector3(0.12, 1.4, 1.0)), body, Vector3(0, 0.7, -2.6))
	B3Mats.add(plane, B3Mats.sphere(0.45, 10), B3Mats.mat(Color("6fd3ff"), 0.1), Vector3(0, 0.35, 1.6), Vector3.ZERO, Vector3(0.8, 0.6, 1.4))
	for sx in [-1.0, 1.0]:
		B3Mats.add(plane, B3Mats.box(Vector3(0.6, 0.16, 1.2)), B3Mats.mat(Color("ff4646")), Vector3(4.2 * sx, 0.02, 0.2), Vector3.ZERO, Vector3.ONE, false)
	return plane


## Clears every puppet (the host changed the map).
func _wipe() -> void:
	puppets.clear()
	corpses.clear()
	_seen.clear()


# ---------------------------------------------------------------- name tags
func _update_tags() -> void:
	var want := {}
	for p in players:
		var pid := int(p.get("id", 0))
		var uid := int(p.get("uid", 0))
		if uid == 0:
			continue
		var u: B3Unit = null
		if is_host():
			u = _unit(uid)
		else:
			var n = puppets.get(uid)
			u = n if n is B3Unit and is_instance_valid(n) else null
		if u == null or (pid == my_id):
			continue
		want[u] = p
	for u in _tags.keys():
		if not want.has(u) or not is_instance_valid(u):
			var t = _tags[u]
			if is_instance_valid(t):
				(t as Node).queue_free()
			_tags.erase(u)
	for u in want:
		var p: Dictionary = want[u]
		var t: Label3D = _tags.get(u)
		if t == null:
			t = Label3D.new()
			t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			t.no_depth_test = true
			t.fixed_size = true
			t.pixel_size = 0.0022
			t.font_size = 40
			t.outline_size = 14
			t.modulate = p.get("col", Color.WHITE) if p.get("col") is Color else Color.WHITE
			t.outline_modulate = Color("1d1b2a")
			t.text = "🎮 " + String(p.get("name", "Friend"))
			add_child(t)
			_tags[u] = t
		var uu := u as B3Unit
		t.global_position = uu.center() + Vector3(0, uu.tall * 0.6 + 0.9, 0)

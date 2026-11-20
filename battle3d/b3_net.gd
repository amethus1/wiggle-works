class_name B3Net
extends Node
## 👥 Playing 3D Battle together on the same Wi-Fi.
##
## The host's computer runs the real battle. About 20 times a second it sends
## friends a snapshot: every fighter and vehicle (where, which way, what it's
## doing, health), barrels and crates, flying rockets, pools, buildings, the
## knocked-out, the battle state and who's playing what. Effects and sounds
## that happened since the last snapshot ride along. Things that must not get
## lost (a fighter knocked out, a wall piece breaking) go on a reliable channel.
##
## A friend's computer shows "puppets": the same fighters, built the same way,
## but with their physics and brains switched off, glided smoothly to where the
## host says they are. Knocked-out ragdolls and flying wall chunks are
## simulated on each computer (they only need to look right).
##
## Friends can place things from the Toy Box, erase, press Fight/Pause/Reset,
## and play any fighter or vehicle: their keys and mouse go to the host ~30
## times a second (B3Ctl.pack) and the host's copy of that fighter obeys them.

const PORT := 24710
const GAME_ID := "wiggle-works-3d"
const VERSION := 1
const MAX_FRIENDS := 7
const SNAP_HZ := 20.0
const CTL_HZ := 30.0
const GONE_GRACE := 0.6        # seconds something can be missing from snapshots before it's removed

var battle = null
var mode := ""                 # "host" or "client"
var peer: ENetMultiplayerPeer = null
var mp: SceneMultiplayer = null
var friends := {}              # host: peer id -> {name, color, ctl: B3Ctl, uid: int}
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
var _fx: Array = []            # effects and sounds for the next snapshot
var _ev: Array = []            # reliable events
var _last_us := 0
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
func rec_fx(e: Array) -> void:
	if is_host() and not friends.is_empty():
		_fx.append(e)
		if _fx.size() > 400:
			_fx.pop_front()


## Host: something friends must not miss.
func rec_event(e: Array) -> void:
	if is_host() and not friends.is_empty():
		_ev.append(e)


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
	_beacon_t -= dt
	if _beacon_t <= 0.0:
		_beacon_t = 1.0
		var md: Dictionary = B3Defs.MAPS.get(battle.map_id, {})
		var b := JSON.stringify({"game": GAME_ID, "v": VERSION, "name": Settings.player_name,
			"world": "%s %s" % [md.get("icon", ""), md.get("name", "")], "players": friends.size() + 1, "port": PORT})
		_beacon.set_dest_address("255.255.255.255", NetCommon.BEACON_PORT)
		_beacon.put_packet(b.to_utf8_buffer())
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
		_send(snapshot(), false)
		_fx = []


func _send(d: Dictionary, reliable: bool, to := 0) -> void:
	if mp == null or peer == null:
		return
	var pkt := NetCommon.encode(d)
	var m := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	mp.send_bytes(pkt, to, m, 0 if reliable else 1)


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
			if int(d.get("v", 0)) != VERSION:
				_send({"m": "bye", "why": "Different game version. Update Wiggle Works on both computers."}, true, id)
				return
			var nm := String(d.get("name", "Friend")).strip_edges().substr(0, 16)
			var c := B3Ctl.new()
			c.peer = id
			c.who = nm if nm != "" else "Friend"
			c.color = d.get("color", Color.WHITE) if d.get("color") is Color else Color.WHITE
			friends[id] = {"name": c.who, "color": c.color, "ctl": c, "uid": 0}
			_send({"m": "welcome", "id": id, "host": Settings.player_name}, true, id)
			_refresh_players()
			Settings.award("friends")
			if battle.ui:
				battle.ui.toast("%s joined the battle! 👋" % c.who)
				battle.ui.refresh_net()
			battle.snd("pop", null, 0.7)
		"ctl":
			if friends.has(id) and d.get("a") is Array:
				(friends[id].ctl as B3Ctl).unpack(d.a)
		"cmd":
			if friends.has(id) and d.get("c") is Dictionary:
				_command(id, d.c)


## A friend pressed something: do it here, on the real battle.
func _command(id: int, c: Dictionary) -> void:
	var f: Dictionary = friends[id]
	match String(c.get("c", "")):
		"place":
			if battle.tools:
				battle.tools.place_for(c)
		"drop":
			battle.drop(String(c.get("id", "")), c.get("pos", Vector3.ZERO), c.get("dir", Vector3.RIGHT))
		"erase":
			var o = instance_from_id(int(c.get("nid", 0))) if int(c.get("nid", 0)) != 0 else null
			if o == null or not is_instance_valid(o):
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
			for rd: B3Ragdoll in battle.ragdolls:
				if is_instance_valid(rd) and int(rd.get_meta("nid", 0)) == int(c.get("nid", 0)):
					battle.remove_ragdoll(rd)
					break
		"play":
			var u := _unit(int(c.get("nid", 0)))
			if u == null or (u.ctl != null and u.ctl != f.ctl):
				_send({"m": "toast", "t": "Someone is already playing that one!"}, true, id)
				return
			_unplay(f)
			var ctl: B3Ctl = f.ctl
			ctl.clear_buttons()
			ctl.look_yaw = u.facing
			B3Player.attach(u, ctl)
			f.uid = u.get_instance_id()
			if not battle.fighting:
				battle.set_fighting(true)
			if battle.paused:
				battle.set_paused(false)
		"unplay":
			_unplay(f)
		"fight":
			battle.toggle_play()
		"slowmo":
			battle.set_slowmo(not battle.slowmo)
		"reset":
			battle.reset_battle()
		"c4":
			battle.detonate_c4()
		"launch":
			var ul := _unit(int(c.get("nid", 0)))
			if ul:
				ul.knock_down(Vector3(randf_range(-4, 4), 18.0, randf_range(-4, 4)))
		"heal":
			var uh := _unit(int(c.get("nid", 0)))
			if uh:
				uh.hp = uh.max_hp
				battle.fx.heal(uh.center() + Vector3(0, 0.6, 0))
				battle.snd("heal", uh.position, 0.8)
		"team":
			var u2 := _unit(int(c.get("nid", 0)))
			if u2:
				u2.set_team(String(c.get("t", u2.team)))
		"mood":
			var u3 := _unit(int(c.get("nid", 0)))
			if u3:
				u3.set_personality(String(c.get("p", u3.pers_choice)))


func _unplay(f: Dictionary) -> void:
	var u := _unit(int(f.get("uid", 0)))
	if u and u.ctl == f.ctl:
		B3Player.detach(u)
	f.uid = 0


func _unit(id: int) -> B3Unit:
	if id == 0:
		return null
	var o = instance_from_id(id)
	if o is B3Unit and is_instance_valid(o) and not (o as B3Unit).dead:
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
			hs.append([h.get_instance_id(), h.kind, h.position, h.radius])
	var ss: Array = []
	for s: B3Struct in b.structs:
		if is_instance_valid(s) and not s.pieces.is_empty():
			s.number_pieces()
			var alive := PackedInt32Array()
			for pc in s.pieces:
				if is_instance_valid(pc):
					alive.append(int(pc.get_meta("pi", 0)))
			var se := [s.get_instance_id(), s.kind, s.position, s.rotation.y, s.length, int(s.get_meta("seed", 0)), alive]
			if not B3Defs.STRUCTS.has(s.kind):
				# History battles' own pieces: the whole shape, once a second
				se.append(s.piece_data() if _snap_n % 20 == 1 else null)
			ss.append(se)
	var out := {"m": "snap", "u": us, "p": ps, "j": js, "h": hs, "s": ss, "fx": _fx, "pl": players,
		"st": [b.map_id, b.fighting, b.paused, b.slowmo, b.ui.banner_lbl.text if b.ui and b.ui.banner_lbl.visible else "",
			b.ui.banner_lbl.get_theme_color("font_color") if b.ui else Color.WHITE, b.c4_count()],
		"r": B3Rules.values}
	if _snap_n % 5 == 0:
		var cs: Array = []
		for rd: B3Ragdoll in b.ragdolls:
			if is_instance_valid(rd) and rd.dead and rd.has_meta("nid"):
				cs.append([int(rd.get_meta("nid")), rd.kind, rd.team, rd.center()])
		out["c"] = cs
	return out


## flags: 1 down, 2 aiming, 4 cheering, 8 on fire, 16 scared, 32 swooping, 64 played by someone, 128 held
func _unit_entry(u: B3Unit) -> Array:
	var aiming: bool = u.target != null and b_fighting()
	var flags := int(u.down) | (int(aiming) << 1) | (int(u.cheer) << 2) | (int(u.burn_t > 0.0) << 3) \
		| (int(u.fleeing) << 4) | (int(u._swoop) << 5) | (int(u.player) << 6) | (int(u.held) << 7)
	var pos: Vector3 = u.global_position
	var vel: Vector3 = u.linear_velocity
	if u.down and u.ragdoll and is_instance_valid(u.ragdoll):
		pos = u.ragdoll.center()
		u.ragdoll.set_meta("nid", u.get_instance_id())
		if is_instance_valid(u.ragdoll.root_body):
			vel = u.ragdoll.root_body.linear_velocity
	var rot: Variant = u.global_basis.get_rotation_quaternion() if u is B3Vehicle else u.facing
	var ns: Variant = u.call("net_state") if u.has_method("net_state") else null
	return [u.get_instance_id(), u.kind, u.team, u.size_mult, pos, rot, flags, u.hp / maxf(1.0, u.max_hp),
		u.act, u.act_t / maxf(u.act_len, 0.01), u._spd, u.pers, vel, ns, int(u.get_meta("seed", -1))]


func b_fighting() -> bool:
	return battle.fighting


# ------------------------------------------------------------------ client
func _client_packet(m: String, d: Dictionary) -> void:
	match m:
		"welcome":
			my_id = int(d.get("id", my_id))
			host_name = String(d.get("host", "your friend"))
			status = "In %s's battle" % host_name
			battle.puppet = true
			if battle.ui:
				battle.ui.toast("👋 You joined %s's battle!" % host_name)
				battle.ui.refresh_net()
		"bye":
			_lost(String(d.get("why", "The host left the battle.")))
		"toast":
			if battle.ui:
				battle.ui.toast(String(d.get("t", "")))
		"ev":
			for e in d.get("list", []):
				_apply_event(e)
		"snap":
			_apply_snapshot(d)


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
	# my controls go to the host
	_ctl_t -= dt
	if B3Player.unit != null and _ctl_t <= 0.0:
		_ctl_t = 1.0 / CTL_HZ
		var me := B3Player.me
		_send({"m": "ctl", "a": me.pack()}, false)
		me.jump = false
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
			elif r is float:
				u.facing = lerp_angle(u.facing, float(r), k)
				if u.rig:
					u.rig.rotation.y = u.facing
			continue
		node.global_position = node.global_position.lerp(to, k) if node.global_position.distance_to(to) < 6.0 else to
		var q: Variant = node.get_meta("nr", null)
		if q is Quaternion:
			node.global_basis = Basis(node.global_basis.get_rotation_quaternion().slerp(q as Quaternion, k))
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
			b.set_slowmo(bool(st[3]))
		var bt := String(st[4])
		if bt != _banner and b.ui:
			_banner = bt
			if bt == "":
				b.ui.hide_banner()
			else:
				b.ui.banner(bt, st[5] if st[5] is Color else Color.WHITE)
	var rules: Dictionary = s.get("r", {})
	if not rules.is_empty() and rules.hash() != B3Rules.values.hash():
		B3Rules.values = rules.duplicate()     # just for this battle; not saved over your own rules
		b.apply_rules()
		if b.ui:
			b.ui.refresh()
	players = s.get("pl", [])
	for p in players:
		# the host says we're not playing anything (our fighter got knocked out);
		# not just after asking to play one, while the answer is on its way
		if int(p.get("id", 0)) == my_id and B3Player.playing and int(p.get("uid", 0)) == 0 \
				and _clock - _play_asked > 1.0:
			if b.tools:
				b.tools.player_lost()
	for e in s.get("s", []):
		_struct(e)
	for e in s.get("h", []):
		_hazard(e)
	for e in s.get("p", []):
		_prop(e)
	for e in s.get("u", []):
		_unit_apply(e)
	for e in s.get("j", []):
		_proj(e)
	if s.has("c"):
		var live := {}
		for e in s.c:
			live[int(e[0])] = true
			_corpse(e)
		for nid in corpses.keys():
			if not live.has(nid):
				var rd = corpses[nid]
				corpses.erase(nid)
				if is_instance_valid(rd):
					b.remove_ragdoll(rd, false)
	for e in s.get("fx", []):
		_play_fx(e)
	if b.ui:
		b.ui.counts_dirty = true


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
		"toast":
			if b.ui:
				b.ui.toast(String(e[1]))


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
		return
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


func _play_fx(e: Array) -> void:
	if e.is_empty():
		return
	fx_played += 1
	var b = battle
	var name_s := String(e[0])
	match name_s:
		"snd":
			b.snd(String(e[1]), e[2], float(e[3]), float(e[4]))
		"shake":
			b.shake(float(e[1]), e[2])
		_:
			if b.fx.has_method(name_s):
				b.fx.callv(name_s, e.slice(1))


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

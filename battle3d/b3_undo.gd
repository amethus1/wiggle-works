class_name B3Undo
extends RefCounted
## ↶ Undo / ↷ Redo in 3D Battle (Ctrl+Z / Ctrl+Y, and ↶ ↷ in the tool dock):
## placing, erasing, moving with ✋ Grab, and changing a team or a mood
## (one fighter or a whole box of them). B3Tools records what you do here.
##  - Only what you did yourself on this computer goes in. Friends' changes
##    (👥) never do, and in a friend's battle ↶ ↷ are off: only the host can
##    undo (a friend's undo would take back the host's things too).
##  - Nothing you can't touch is ever changed: a 🧩 puzzle's army, 🌊 the
##    attackers, or your own army once a puzzle's fight is on (see
##    B3Battle.hands_off): those parts of an undo are skipped, and it says so.
##  - 🪙 Points: undoing a buy is erasing it, so it gives back exactly what
##    erasing would (the price kept in meta "cost"); bringing something back
##    costs exactly what taking it away gave back, and if you can't pay, it
##    stays away and says so.
##  - Clearing, a new map, ⏮ Reset and loading a battle start afresh (B3Battle.clear_units).
## Things are found again by a number kept on them (meta "uh"), which a
## fighter or building brought back by Undo gets back too.

const MAX := 50

var battle = null
var _done: Array = []         # records, newest last: {"do", "items", "what", "refund"}
var _undone: Array = []
var _next_h := 1
var _open: Dictionary = {}    # an Eraser drag still going on (begin_erase / end_erase)


# ----------------------------------------------------------------- asking
func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


func next_undo_text() -> String:
	return _text(_done.back()) if can_undo() else ""


func next_redo_text() -> String:
	return _text(_undone.back()) if can_redo() else ""


static func _text(r: Dictionary) -> String:
	var what := String(r.get("what", ""))
	match String(r.do):
		"place":
			return "placing " + what
		"erase":
			return "erasing " + what
		"move":
			return "moving " + what
		"team":
			return "the team change"
		"mood":
			return "the mood change"
	return what


func clear() -> void:
	_done.clear()
	_undone.clear()
	_open = {}
	_changed()


# --------------------------------------------------------------- recording
## You just placed `nodes` (fighters, a building, a pool, crates, a mine...).
## `refund`: what erasing them would give back is worked out when undoing.
func did_place(nodes: Array, what: String) -> void:
	var items: Array = []
	for n in nodes:
		if n is Node and is_instance_valid(n):
			items.append({"h": _handle(n as Node), "e": {}})
	if not items.is_empty():
		_push({"do": "place", "items": items, "what": what, "refund": 0})


## About to erase `n` (call before removing it): keeps what it was, so Undo
## can bring it back. With an Eraser drag going (begin_erase) it joins that.
func will_erase(n: Node) -> void:
	if n == null or not is_instance_valid(n) or (n is B3Unit and (n as B3Unit).dead):
		return
	var nodes: Array = [n]
	if n is B3Prop and n.has_meta("stack"):
		# crates bought as one stack are erased (and come back) as one
		var sid := int(n.get_meta("stack"))
		for o: B3Prop in battle.props:
			if is_instance_valid(o) and o != n and int(o.get_meta("stack", -1)) == sid:
				nodes.append(o)
	var items: Array = []
	for o: Node in nodes:
		items.append({"h": _handle(o), "e": _entry(o)})
	if _open.is_empty():
		_push({"do": "erase", "items": items, "what": _what(nodes), "refund": 0, "spent0": int(battle.spent)}, true)
		return
	(_open.items as Array).append_array(items)


## An Eraser drag starts: everything it erases is one Undo.
func begin_erase() -> void:
	if not _open.is_empty():
		end_erase()      # (a drag whose button-up never came: it's done)
	_open = {"do": "erase", "items": [], "what": "", "refund": 0, "spent0": int(battle.spent)}


func end_erase() -> void:
	var r := _open
	_open = {}
	if r.is_empty() or (r.items as Array).is_empty():
		return
	r.what = "%d thing%s" % [(r.items as Array).size(), "" if (r.items as Array).size() == 1 else "s"]
	_push(r, true)


## The last erase is done: what it gave back is known now.
func _settle_erase(r: Dictionary) -> void:
	if r.has("spent0"):
		r.refund = maxi(0, int(r.spent0) - int(battle.spent))
		r.erase("spent0")


## ✋ You moved `n` from `from` to `to`.
func did_move(n: Node, from: Vector3, to: Vector3) -> void:
	if n == null or not is_instance_valid(n) or from.distance_to(to) < 1.0:
		return
	_push({"do": "move", "items": [{"h": _handle(n), "from": from, "to": to}], "what": _what([n])})


## You changed the team ("team") or mood ("mood") of some fighters to
## `now`: `olds` is [[fighter, what it was], ...].
func did(kind: String, olds: Array, now: String) -> void:
	var items: Array = []
	for o: Array in olds:
		if o[0] is Node and is_instance_valid(o[0]):
			items.append({"h": _handle(o[0] as Node), "old": String(o[1]), "new": now})
	if not items.is_empty():
		_push({"do": kind, "items": items, "what": "%d fighter%s" % [items.size(), "" if items.size() == 1 else "s"]})


func _push(r: Dictionary, erase := false) -> void:
	if erase:
		_settle_erase.call_deferred(r)      # (after the erasing has paid back what it does)
	_done.append(r)
	if _done.size() > MAX:
		_done.pop_front()
	_undone.clear()
	_changed()


# ------------------------------------------------------------ undo / redo
## Ctrl+Z / ↶: takes back the last thing you did.
func undo() -> bool:
	return _step(true)


## Ctrl+Y / ↷: does it again.
func redo() -> bool:
	return _step(false)


func _step(back: bool) -> bool:
	if not _allowed():
		return false
	var from: Array = _done if back else _undone
	if from.is_empty():
		_say("↶ Nothing to undo!" if back else "↷ Nothing to redo!", true)
		return false
	var r: Dictionary = from.back()
	if r.has("spent0"):
		_settle_erase(r)
	var why := ""
	match String(r.do):
		"place":
			why = _take_away(r) if back else _bring_back(r)
		"erase":
			why = _bring_back(r) if back else _take_away(r)
		"move":
			why = _move(r, back)
		"team", "mood":
			why = _change(r, back)
	if why != "":
		_say(why, true)
		if why.begins_with("🪙"):
			return false      # (it stays where it is: you can try again with more points)
	from.pop_back()
	(_undone if back else _done).append(r)
	if why == "":
		_say(("↶ Undo: " if back else "↷ Redo: ") + _text(r), false)
		battle.snd("pop" if back else "tick", null, 0.6)
	_changed()
	return true


## Only the host can undo in a shared battle (it would undo the host's things too).
func _allowed() -> bool:
	if battle.puppet:
		_say("↶ Only the host can undo in a shared battle.", true)
		return false
	return true


## Erases what record `r` placed (or brings back nothing if it's all gone).
## Erasing pays back what erasing always does; that's kept for bringing it back.
func _take_away(r: Dictionary) -> String:
	var spent0 := int(battle.spent)
	var gone := 0
	var kept := ""
	for it: Dictionary in r.items:
		var n := _find(int(it.h))
		if n == null:
			continue
		var why: String = battle.hands_off(n, "erase")
		if why != "":
			kept = why
			continue
		it.e = _entry(n)
		_remove(n)
		gone += 1
	r.refund = maxi(0, spent0 - int(battle.spent))
	if gone == 0:
		return kept if kept != "" else "Those are gone already!"
	return ""


## Puts back what record `r` took away, paying what taking it away gave back.
func _bring_back(r: Dictionary) -> String:
	var pay := int(r.get("refund", 0))
	if int(battle.budget) >= 0 and pay > battle.points_left():
		return "🪙 Not enough points to bring that back! You have %d left." % battle.points_left()
	var stacks := {}
	var made := 0
	for it: Dictionary in r.items:
		var e: Dictionary = it.get("e", {})
		if e.is_empty() or _find(int(it.h)) != null:
			continue
		var n := _spawn(e)
		if n == null:
			continue
		n.set_meta("uh", int(it.h))
		if e.has("c") and int(battle.budget) >= 0:
			n.set_meta("cost", int(e.c))
		if e.has("g") and int(battle.budget) >= 0:
			if not stacks.has(int(e.g)):
				stacks[int(e.g)] = n.get_instance_id()
			n.set_meta("stack", int(stacks[int(e.g)]))
		made += 1
	if made > 0 and int(battle.budget) >= 0 and pay > 0:
		battle.spent += pay
		battle.budget_changed.emit()
	if battle.ui:
		battle.ui.counts_dirty = true
		battle.ui.refresh_c4()
	return "" if made > 0 else "There's nothing to bring back."


func _move(r: Dictionary, back: bool) -> String:
	var it: Dictionary = r.items[0]
	var n := _find(int(it.h))
	if n == null:
		return "That's gone now!"
	var why: String = battle.hands_off(n, "grab")
	if why != "":
		return why
	if n == B3Player.unit:
		return "🎮 You're playing that one!"
	put(n, it.from if back else it.to)
	return ""


func _change(r: Dictionary, back: bool) -> String:
	var did_n := 0
	var kept := ""
	for it: Dictionary in r.items:
		var n := _find(int(it.h))
		if not n is B3Unit:
			continue
		var why: String = battle.hands_off(n, String(r.do))
		if why != "":
			kept = why
			continue
		var v := String(it.old if back else it.new)
		if r.do == "team":
			(n as B3Unit).set_team(v)
		else:
			(n as B3Unit).set_personality(v)
		did_n += 1
	if battle.ui:
		battle.ui.counts_dirty = true
		if battle.tools and battle.tools.selected:
			battle.ui.show_inspect(battle.tools.selected)
	if did_n == 0:
		return kept if kept != "" else "Those fighters are gone now!"
	return ""


# ------------------------------------------------------------------ helpers
func _handle(n: Node) -> int:
	if not n.has_meta("uh"):
		n.set_meta("uh", _next_h)
		_next_h += 1
	return int(n.get_meta("uh"))


## The fighter, building, pool or prop with handle `h` that's still there (or null).
func _find(h: int) -> Node:
	for arr: Array in [battle.units, battle.structs, battle.hazards, battle.props]:
		for o in arr:
			if is_instance_valid(o) and int((o as Node).get_meta("uh", 0)) == h:
				if o is B3Unit and (o as B3Unit).dead:
					return null
				if o is B3Prop and ((o as B3Prop).lit or (o as B3Prop).sinking > 0.0):
					return null
				return o as Node
	return null


## What `n` is, enough to make it again (like a B3Saves snapshot).
func _entry(n: Node) -> Dictionary:
	var e := {}
	if n is B3Unit:
		var u := n as B3Unit
		var p: Vector3 = u.center() if u.down else u.position
		e = {"t": "u", "k": u.kind, "team": u.team, "p": u.pers_choice, "pos": p, "f": u.facing,
			"hp": u.hp / maxf(1.0, u.max_hp), "mh": u.max_hp, "sp": u.speed, "s": u.size_mult, "sd": int(u.get_meta("seed", -1))}
		if u is B3Aircraft:
			e["alt"] = (u as B3Aircraft).alt
			e["pk"] = (u as B3Aircraft).parked
		if u.has_meta("history"):
			e["hist"] = true
	elif n is B3Struct:
		var s := n as B3Struct
		e = {"t": "s", "k": s.kind, "pos": s.position, "yaw": s.rotation.y, "len": s.length, "sd": int(s.get_meta("seed", -1))}
		if not B3Defs.STRUCTS.has(s.kind):
			e["pcs"] = s.piece_data()
	elif n is B3Hazard:
		var h := n as B3Hazard
		e = {"t": "h", "k": h.kind, "pos": h.position, "r": h.radius}
	elif n is B3Prop:
		var pr := n as B3Prop
		e = {"t": "p", "k": pr.kind, "pos": pr.global_position, "yaw": pr.rotation.y}
		if pr.has_meta("stack"):
			e["g"] = int(pr.get_meta("stack"))
	if n.has_meta("cost"):
		e["c"] = int(n.get_meta("cost"))
	return e


func _spawn(e: Dictionary) -> Node:
	var at: Vector3 = e.pos
	match String(e.t):
		"u":
			var u: B3Unit = battle.spawn_unit(String(e.k), String(e.team), Vector3(at.x, battle.surface_y(Vector3(at.x, at.y + 0.6, at.z)), at.z),
				String(e.p), float(e.f), float(e.s), int(e.sd))
			if u:
				u.max_hp = float(e.mh)
				u.speed = float(e.sp)
				u.hp = u.max_hp * clampf(float(e.hp), 0.05, 1.0)
				if u is B3Aircraft:
					(u as B3Aircraft).alt = float(e.get("alt", (u as B3Aircraft).alt))
					(u as B3Aircraft).parked = bool(e.get("pk", false))
				if bool(e.get("hist", false)):
					u.set_meta("history", true)
			return u
		"s":
			if e.has("pcs"):
				return battle.spawn_custom_struct(String(e.k), at, float(e.yaw), e.pcs)
			return battle.spawn_struct(String(e.k), Vector3(at.x, 0, at.z), float(e.yaw), float(e.len), int(e.sd))
		"h":
			return battle.spawn_hazard(String(e.k), Vector3(at.x, 0, at.z), float(e.r))
		"p":
			var p: B3Prop = battle.spawn_prop(String(e.k), at, float(e.yaw))
			if p:
				p.global_position = at
				p.reset_physics_interpolation()
			return p
	return null


func _remove(n: Node) -> void:
	if n is B3Unit:
		battle.remove_unit(n as B3Unit)
	elif n is B3Struct:
		battle.remove_struct(n as B3Struct)
	elif n is B3Hazard:
		battle.remove_hazard(n as B3Hazard, true)
	elif n is B3Prop:
		battle.remove_prop(n as B3Prop)


## Puts `n` at `p` and stops it moving (a fighter lying knocked down is moved
## as it lies, and gets up there).
func put(n: Node, p: Vector3) -> void:
	if n is B3Unit:
		var u := n as B3Unit
		if u.down and u.ragdoll and is_instance_valid(u.ragdoll):
			var d := p - u.ragdoll.center()
			for rb: RigidBody3D in u.ragdoll.bodies:
				if is_instance_valid(rb):
					rb.global_position += d
					rb.linear_velocity = Vector3.ZERO
					rb.angular_velocity = Vector3.ZERO
					rb.reset_physics_interpolation()
			return
		var y: float = p.y if u.flying else battle.surface_y(Vector3(p.x, p.y + 0.6, p.z)) + 0.05
		u.global_position = Vector3(p.x, y, p.z)
		u.linear_velocity = Vector3.ZERO
		u.angular_velocity = Vector3.ZERO
		u.reset_physics_interpolation()
	elif n is RigidBody3D:
		var rb2 := n as RigidBody3D
		rb2.global_position = p
		rb2.linear_velocity = Vector3.ZERO
		rb2.angular_velocity = Vector3.ZERO
		rb2.reset_physics_interpolation()


## "3 Soldiers", "a Wall"...
static func _what(nodes: Array) -> String:
	var kinds := {}
	for n in nodes:
		var k := ""
		if n is B3Unit:
			k = (n as B3Unit).kind
		elif n is B3Struct:
			k = (n as B3Struct).kind
		elif n is B3Hazard:
			k = (n as B3Hazard).kind
		elif n is B3Prop:
			k = (n as B3Prop).kind
		kinds[k] = int(kinds.get(k, 0)) + 1
	if kinds.size() != 1:
		return "%d things" % nodes.size()
	var k1 := String(kinds.keys()[0])
	var d := {}
	for table in [B3Defs.UNITS, B3Defs.STRUCTS, B3Defs.HAZARDS, B3Defs.BOOMS]:
		if table.has(k1):
			d = table[k1]
	var nm := String(d.get("name", k1.capitalize()))
	return ("a " + nm) if nodes.size() == 1 else "%d %ss" % [nodes.size(), nm]


func _say(txt: String, nope: bool) -> void:
	if battle.ui:
		battle.ui.toast(txt, false)
	if nope:
		battle.snd("nope", null, 0.5)


func _changed() -> void:
	if battle and battle.ui:
		battle.ui.refresh_undo()

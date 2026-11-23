extends Node
## Mouse and keys → battle actions. Tools: Place (click, or drag a line of
## units / a wall / a ramp / a bigger pool; Shift-drag a block lined up with
## the camera), Select (click a unit, Shift-click to add one, or drag a box
## round lots of them: the Inspector then changes them all), Grab (pick up
## anything and fling it), Eraser. ↶ Undo / ↷ Redo (Ctrl+Z / Ctrl+Y, see
## B3Undo). Also camera keys and the little 3D cursor ghosts that show what
## will happen.

const MAX_UNITS := 400
const LINE_MAX := 144           # the most placement dots shown at once (a 12 x 12 Shift-drag block)

var battle = null
var tool := "place"
var place_id := "soldier"
var team := "red"
var team_by_cat := {"people": "red", "animals": "wild", "dinos": "wild", "history": "red"}
var pers := "auto"
var place_size := 1.0      # Toy Box size for new fighters
var struct_yaw := 0.0
var selected: B3Unit = null
var group: Array[B3Unit] = []   # 🔍 everyone selected (a box drag or Shift-clicks); `selected` is the first
var undo: B3Undo = null         # ↶ ↷ (B3Undo)
var drag := {}
var grab_body: RigidBody3D = null
var grab_unit: B3Unit = null
var grab_h := 3.0
var _mouse := Vector2.ZERO
var _grab_prev := Vector3.ZERO
var _grab_vel := Vector3.ZERO
var _right_from := Vector2.ZERO
var _ghost_ring: MeshInstance3D
var _ghost_box: MeshInstance3D
var _line: MultiMeshInstance3D
var _sel_ring: MeshInstance3D
var _grp_rings: MultiMeshInstance3D   # rings under every fighter in `group`
var _grab_from := Vector3.ZERO        # ✋ where the grabbed thing was (↶ puts it back)
var _recording := true                # false while placing for a friend (👥): that isn't yours to undo
var _t := 0.0
var _veh_yaw := INF             # a friend's battle: the car we drive, last frame's heading
var _round: Array = []          # ⇥ Tab: ids of the teammates played this round (switch_teammate)
var _round_ms := -100000
const ROUND_MS := 6000          # ...a new round starts after this long without a press


func _ready() -> void:
	undo = B3Undo.new()
	undo.battle = battle
	_ghost_ring = MeshInstance3D.new()
	_ghost_ring.mesh = B3Mats.torus(0.9, 1.0)
	_ghost_ring.material_override = B3Mats.flat(Color(1.0, 0.85, 0.3, 0.8))
	_ghost_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	battle.add_child.call_deferred(_ghost_ring)
	_ghost_box = MeshInstance3D.new()
	_ghost_box.mesh = B3Mats.box(Vector3.ONE)
	_ghost_box.material_override = B3Mats.flat(Color(1.0, 1.0, 1.0, 0.3))
	_ghost_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_box.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	battle.add_child.call_deferred(_ghost_box)
	_line = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = B3Mats.cyl(0.35, 0.35, 0.05, 16)
	mm.instance_count = LINE_MAX
	mm.visible_instance_count = 0
	_line.multimesh = mm
	_line.material_override = B3Mats.vcol(true, true)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	battle.add_child.call_deferred(_line)
	_sel_ring = MeshInstance3D.new()
	_sel_ring.mesh = B3Mats.torus(0.85, 1.0)
	_sel_ring.material_override = B3Mats.glow(Color(1.0, 0.85, 0.25), 2.0)
	_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sel_ring.visible = false
	battle.add_child.call_deferred(_sel_ring)
	_grp_rings = MultiMeshInstance3D.new()
	var gm := MultiMesh.new()
	gm.transform_format = MultiMesh.TRANSFORM_3D
	gm.mesh = B3Mats.torus(0.85, 1.0)
	gm.instance_count = MAX_UNITS
	gm.visible_instance_count = 0
	_grp_rings.multimesh = gm
	_grp_rings.material_override = _sel_ring.material_override
	_grp_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grp_rings.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_grp_rings.visible = false
	battle.add_child.call_deferred(_grp_rings)


# --------------------------------------------------------------- choosing
func set_tool(t: String) -> void:
	tool = t
	drag = {}
	if t != "grab":
		_grab_end(false)
	if battle.ui:
		battle.ui.refresh_tools()


func choose(id: String) -> void:
	place_id = id
	tool = "place"
	var c := B3Defs.item_cat(id)
	if team_by_cat.has(c):
		team = String(team_by_cat[c])
	if battle.ui:
		battle.ui.refresh_tools()
		battle.ui.refresh_palette()


func set_team(t: String) -> void:
	team = t
	var c := B3Defs.item_cat(place_id)
	if team_by_cat.has(c):
		team_by_cat[c] = t
	if battle.ui:
		battle.ui.refresh_palette()


# --------------------------------------------------------- playing a fighter
## Take control of `u` (see B3Player). Starts the battle if it hasn't begun.
## `jumped`: you came straight from another fighter (knocked out, or ⇥ Tab),
## so just a short `msg` (the knock-out one if empty) instead of the full help.
func play_as(u: B3Unit, fp := false, jumped := false, msg := "") -> void:
	if u == null or not is_instance_valid(u) or u.dead:
		return
	var why: String = battle.hands_off(u, "play")      # 🧩 not the puzzle's army (or 🌊 the attackers)
	if why != "":
		_nope(why, u.position)
		return
	if u.ctl != null and u.ctl != B3Player.me:
		if battle.ui:
			battle.ui.toast("Someone is already playing that one!", false)
		return
	if battle.net and battle.net.is_client():
		# in a friend's battle: ask the host, and steer our copy's camera here
		var nid := int(u.get_meta("nid", 0))
		for p in battle.net.players:
			if int(p.get("uid", 0)) == nid and int(p.get("id", 0)) != battle.net.my_id:
				if battle.ui:
					battle.ui.toast("%s is already playing that one!" % p.get("name", "Someone"), false)
				return
		battle.net.send_cmd({"c": "play", "nid": nid})
	B3Player.start(u)
	_veh_yaw = INF
	battle.cam.follow = u
	set_first_person(fp)
	if not battle.fighting:
		battle.set_fighting(true)
	if battle.paused:
		battle.set_paused(false)
	select(null)
	if jumped:
		battle.snd("boing", null, 0.5, 1.3)
		if battle.ui:
			if msg == "":
				msg = "💫 Knocked out! Now you're the %s %s. Keep going!" % [u.def.icon, u.def.name]
			battle.ui.toast(msg, false)
		return
	battle.snd("battle_start", null, 0.5)
	if battle.ui:
		battle.ui.toast("🎮 You're the %s %s! Your keys are at the top of the screen." % [u.def.icon, u.def.name], false)


## The fighter or vehicle you were playing is gone (knocked out, wrecked).
## In first person you jump straight into the nearest teammate and keep going;
## overhead (or with nobody left on your side) you go back to watching.
func player_lost() -> void:
	var msg := B3Player.lost_msg()
	if B3Player.me.fp:
		var next := next_teammate()
		if next:
			play_as(next, true, true)
			return
		msg = "💫 You got knocked out, and there's nobody left on your team!" if not B3Player.was_vehicle \
			else "💥 Your %s got wrecked, and there's nobody left on your team!" % B3Player.what
	stop_playing(msg)


## The teammate closest to where you were: standing fighters first, and the
## same sort as before (a fighter for a fighter, a vehicle for a vehicle).
## ⇥ Tab passes `same_sort` false (a tank or plane is fair game) and the ids
## of the teammates it has already been round (`skip`). A plane that's been
## shot down (on its way to crash) is never picked, and with `standing` (⇥
## Tab) nor is a teammate lying knocked down. (Knocked out, you'd still
## rather jump into a downed teammate, who'll get back up, than stop playing.)
func next_teammate(skip: Array = [], same_sort := true, standing := false) -> B3Unit:
	var best: B3Unit = null
	var bd := INF
	for o: B3Unit in battle.units:
		if not is_instance_valid(o) or o.dead or o == B3Player.unit or o.team != B3Player.team or taken(o):
			continue
		if o.team == "wild" and o.kind != B3Player.kind:
			continue      # wild animals and monsters are each on their own side
		if skip.has(o.get_instance_id()) or (standing and o.down) or o.going_down():
			continue
		var d := o.global_position.distance_to(B3Player.last_pos)
		if o.down:
			d += 500.0
		if same_sort and o.is_vehicle() != B3Player.was_vehicle:
			d += 250.0
		if d < bd:
			bd = d
			best = o
	return best


## ⇥ Tab (or N) while playing: jump into the nearest teammate you're not
## playing, in first person or overhead. Pressing it again moves on to the
## nearest one you haven't been yet, round and round. In a friend's battle
## play_as asks the host.
func switch_teammate() -> void:
	if not B3Player.active():
		return
	var u := B3Player.unit
	var now := Time.get_ticks_msec()
	if now - _round_ms > ROUND_MS:
		_round.clear()      # a while since the last press: start a new round from here
	_round_ms = now
	if not _round.has(u.get_instance_id()):
		_round.append(u.get_instance_id())
	B3Player.last_pos = u.global_position
	var next := next_teammate(_round, false, true)
	if next == null and _round.size() > 1:
		_round = [u.get_instance_id()]       # been round everyone: start again
		next = next_teammate(_round, false, true)
	if next == null:
		battle.snd("nope", null, 0.5)
		if battle.ui:
			battle.ui.toast("Nobody else on your team to jump into!", false)
		return
	_round.append(next.get_instance_id())
	play_as(next, B3Player.me.fp, true, "⇥ Now you're the %s %s!" % [next.def.icon, next.def.name])


## True if someone else (a friend 👥) is already playing `u`.
func taken(u: B3Unit) -> bool:
	if u.ctl != null and u.ctl != B3Player.me:
		return true
	if battle.net and battle.net.is_client():
		var nid := int(u.get_meta("nid", 0))
		for p in battle.net.players:
			if int(p.get("uid", 0)) == nid and int(p.get("id", 0)) != battle.net.my_id:
				return true
	return false


## 👀 Looks out of the played fighter's eyes (or back to the overhead view).
func set_first_person(on: bool) -> void:
	var u := B3Player.unit
	if on and (u == null or not is_instance_valid(u)):
		on = false
	if u != null and is_instance_valid(u) and B3Player.power(u) == "scope":
		B3Player.me.fire2 = false      # the sniper's scope comes out when you switch views
	B3Player.me.fp = on
	if on:
		B3Player.me.look_yaw = u.facing
		B3Player.me.look_pitch = 0.0
		battle.cam.set_first_person(u, B3Player.me)
	else:
		battle.cam.set_first_person(null, null)
	_capture_mouse(on)
	if battle.ui:
		battle.ui.refresh_play()


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func stop_playing(msg := "") -> void:
	if not B3Player.playing and not B3Player.me.fp and battle.cam.fp_ctl == null:
		return
	if B3Player.me.fp or battle.cam.fp_ctl != null:
		set_first_person(false)      # camera back overhead, mouse back, Toy Box back
	if battle.net and battle.net.is_client():
		battle.net.send_cmd({"c": "unplay"})
	B3Player.stop()
	battle.cam.follow = null
	if battle.ui and msg != "":
		battle.ui.toast(msg, false)


func follow(u: B3Unit) -> void:
	battle.cam.follow = u
	if battle.ui:
		battle.ui.toast("🎥 Following the %s. Move the camera to stop." % u.def.name, false)


func select(u: B3Unit) -> void:
	selected = u
	group.clear()
	if u != null and is_instance_valid(u):
		group.append(u)
	if battle.ui:
		battle.ui.show_inspect(u)


## 🔍 Selects all of `us` at once (a box drag): the Inspector changes them all.
func select_many(us: Array) -> void:
	var keep: Array[B3Unit] = []
	for u in us:
		if u is B3Unit and is_instance_valid(u) and not (u as B3Unit).dead and not keep.has(u):
			keep.append(u)
	selected = keep[0] if not keep.is_empty() else null
	group = keep
	if battle.ui:
		battle.ui.show_inspect(selected)


## Shift-click: adds `u` to what's selected, or takes it out.
func toggle_select(u: B3Unit) -> void:
	var now: Array = group.duplicate()
	if now.has(u):
		now.erase(u)
	else:
		now.append(u)
	select_many(now)


## The fighters (not knocked out) whose middles are inside `r` on the screen.
func units_in_rect(r: Rect2) -> Array[B3Unit]:
	var out: Array[B3Unit] = []
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead:
			continue
		var c := u.center()
		if battle.cam.cam.is_position_behind(c):
			continue
		if r.has_point(battle.cam.screen_pos(c)):
			out.append(u)
	return out


## 🗑️ Erases these fighters (the Inspector's 🗑️, or Delete): one ↶ Undo
## brings them all back. In a friend's battle the host does it.
func erase_units(us: Array) -> void:
	if us.is_empty():
		return
	if battle.net and battle.net.is_client():
		for u in us:
			if is_instance_valid(u) and (u as Node).has_meta("nid"):
				battle.net.send_cmd({"c": "erase", "nid": int((u as Node).get_meta("nid"))})
		return
	undo.begin_erase()
	for u in us:
		if is_instance_valid(u) and battle.hands_off(u, "erase") == "":
			undo.will_erase(u)
			battle.remove_unit(u)
	undo.end_erase()


# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if B3Player.active() and _player_input(e):
		return
	if e is InputEventMouseButton:
		_mouse_button(e as InputEventMouseButton)
	elif e is InputEventMouseMotion:
		var m := e as InputEventMouseMotion
		_mouse = m.position
		match String(drag.get("mode", "")):
			"pan":
				battle.cam.pan_screen(m.position - m.relative, m.position)
			"erase":
				_erase_at(m.position)
			"box":
				_show_box(drag.sp, m.position)
	elif e is InputEventMagnifyGesture:
		var g := e as InputEventMagnifyGesture
		battle.cam.zoom_at(g.position, g.factor)
	elif e is InputEventPanGesture:
		var pg := e as InputEventPanGesture
		battle.cam.pan_screen(pg.position + pg.delta * 10.0, pg.position)
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e as InputEventKey)


func _mouse_button(e: InputEventMouseButton) -> void:
	_mouse = e.position
	if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		battle.cam.zoom_at(e.position, 1.12)
		return
	if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		battle.cam.zoom_at(e.position, 1.0 / 1.12)
		return
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		drag = {"mode": "pan"} if e.pressed else {}
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if e.pressed:
			_right_from = e.position
			if drag.get("mode", "") == "place":
				drag = {}
				return
			drag = {"mode": "pan"}
		else:
			if e.position.distance_to(_right_from) < 6.0 and selected:
				select(null)
			drag = {}
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_left_down(e)
	else:
		_left_up(e)


func _left_down(e: InputEventMouseButton) -> void:
	match tool:
		"place":
			if place_id == "":
				return
			var hit := pick(e.position)
			if B3Defs.BOOMS.has(place_id):
				var right: Vector3 = battle.cam.basis_now().x
				var np0: int = battle.props.size()
				battle.drop(place_id, hit.pos, right)
				battle.snd("click", null, 0.4)
				if battle.props.size() > np0:
					undo.did_place(battle.props.slice(np0), String(B3Defs.BOOMS[place_id].name))      # (C4, mines, barrels stay: ↶ takes them back)
				return
			drag = {"mode": "place", "start": hit.pos, "sp": e.position}
		"select":
			var u := unit_at(e.position)
			if u and e.shift_pressed:
				toggle_select(u)      # Shift-click: add it (or take it out)
				battle.snd("click", null, 0.5)
			elif u:
				select(u)
				battle.snd("click", null, 0.5)
			else:
				# drag a box round lots of them (Shift keeps the ones you have)
				drag = {"mode": "box", "sp": e.position, "add": e.shift_pressed}
		"grab":
			if not _grab_start(e.position):
				drag = {"mode": "pan"}
			else:
				drag = {"mode": "grab"}
		"erase":
			if not (battle.net and battle.net.is_client()):
				undo.begin_erase()      # everything this drag erases is one ↶ Undo
			drag = {"mode": "erase"}
			_erase_at(e.position)


func _left_up(e: InputEventMouseButton) -> void:
	var mode := String(drag.get("mode", ""))
	if mode == "place":
		var a: Vector3 = drag.start
		var b: Vector3 = pick(e.position).pos
		var dragged := (e.position - (drag.sp as Vector2)).length() > 12.0
		_place(a, b, dragged, e.shift_pressed)
	elif mode == "grab":
		_grab_end(true)
	elif mode == "erase":
		undo.end_erase()
	elif mode == "box":
		_end_box(drag.sp, e.position, bool(drag.get("add", false)))
	drag = {}


## 🔍 The box you're dragging round fighters, on the screen.
func _show_box(a: Vector2, b: Vector2) -> void:
	if battle.ui and battle.ui.box_rect:
		var r := Rect2(a, Vector2.ZERO).expand(b)
		battle.ui.box_rect.position = r.position
		battle.ui.box_rect.size = r.size
		battle.ui.box_rect.visible = r.size.length() > 8.0


## Let go of the box: everyone in it is selected (with Shift, added). A
## click with no drag on empty ground lets go of what was selected.
func _end_box(a: Vector2, b: Vector2, add: bool) -> void:
	if battle.ui and battle.ui.box_rect:
		battle.ui.box_rect.visible = false
	var r := Rect2(a, Vector2.ZERO).expand(b)
	if r.size.length() < 8.0:
		if not add:
			select(null)
		return
	var got: Array = units_in_rect(r)
	if add:
		got = group.duplicate() + got
	if got.is_empty():
		select(null)
		return
	select_many(got)
	battle.snd("click", null, 0.5, 1.2)
	if battle.ui and group.size() > 1:
		battle.ui.toast("👥 %d fighters picked! Change their team or mood in the Inspector." % group.size(), false)


## Input while playing a fighter. Returns true when it used the event.
func _player_input(e: InputEvent) -> bool:
	var me := B3Player.me
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		_mouse = mm.position
		if me.fp:
			var k: float = 0.0032 * Settings.b3_mouse_k * battle.cam.look_k()     # slower through a sniper's scope
			me.look_yaw = wrapf(me.look_yaw - mm.relative.x * k, -PI, PI)
			me.look_pitch = clampf(me.look_pitch - mm.relative.y * k, -1.35, 1.35)
		return true
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		_mouse = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			me.fire = mb.pressed
			if me.fp and mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_capture_mouse(true)     # clicking back into the game grabs the mouse again
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if me.fp and B3Player.power(B3Player.unit) == "scope":
				# a sniper in first person: each right-click puts the scope in or takes it out
				if mb.pressed:
					me.fire2 = not me.fire2
					Sfx.play("click", null, 0.5, 1.5 if me.fire2 else 1.1)
			else:
				me.fire2 = mb.pressed      # a power (B3Player.power) or a vehicle's second gun
			return true
		if me.fp and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return true
		return false
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_SPACE:
				me.jump = true
				return true
			KEY_ESCAPE, KEY_P:
				stop_playing("🎮 Back to watching.")
				return true
			KEY_V, KEY_C:
				set_first_person(not me.fp)
				return true
			KEY_TAB, KEY_N:
				switch_teammate()      # (not playing, Tab shows or hides the Toy Box: _key)
				return true
			KEY_F:
				me.fire = true
				return true
			KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT:
				return true
	if e is InputEventKey and not e.pressed and (e as InputEventKey).keycode == KEY_F:
		me.fire = false
		return true
	return false


func _key(e: InputEventKey) -> void:
	if _typing():
		return
	if (e.ctrl_pressed or e.meta_pressed) and e.keycode in [KEY_Z, KEY_Y]:
		# ↶ Ctrl+Z / ↷ Ctrl+Y (or Ctrl+Shift+Z)
		if e.keycode == KEY_Y or e.shift_pressed:
			undo.redo()
		else:
			undo.undo()
		return
	match e.keycode:
		KEY_P:
			if selected and is_instance_valid(selected) and not selected.dead:
				play_as(selected)
		KEY_F:
			if selected and is_instance_valid(selected) and not selected.dead:
				follow(selected)
		KEY_SPACE:
			battle.toggle_play()
		KEY_G, KEY_T:
			if battle.puppet and battle.net:
				# 🐢 in a friend's battle the host's slow motion is everyone's: ask the host
				battle.net.send_cmd({"c": "slowmo", "on": not battle.slowmo})
			else:
				battle.set_slowmo(not battle.slowmo)
		KEY_Q:
			battle.cam.rotate_view(-1.0)
		KEY_E:
			battle.cam.rotate_view(1.0)
		KEY_R:
			struct_yaw += PI * 0.5
		KEY_B:
			battle.detonate_c4()
		KEY_1:
			set_tool("place")
		KEY_2:
			set_tool("select")
		KEY_3:
			set_tool("grab")
		KEY_4:
			set_tool("erase")
		KEY_ESCAPE:
			if battle.ui and battle.ui.close_top():
				pass
			elif not drag.is_empty():
				drag = {}
			elif selected:
				select(null)
			elif tool == "place":
				set_tool("select")
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			if selected and is_instance_valid(selected):
				var all: Array = group.duplicate() if group.size() > 1 else [selected]
				var friend: bool = battle.net != null and battle.net.is_client()
				var mine: Array = []
				for u in all:
					if is_instance_valid(u) and battle.hands_off(u, "erase") == "":
						mine.append(u)
				if mine.is_empty() and not friend:
					_nope(battle.hands_off(selected, "erase"), selected.position)      # 🧩 / 🌊 not theirs to remove
				else:
					# (in a friend's battle erase_units asks the host, like the Eraser does)
					erase_units(all if friend else mine)
				select(null)
		KEY_EQUAL, KEY_KP_ADD:
			battle.cam.zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.2)
		KEY_MINUS, KEY_KP_SUBTRACT:
			battle.cam.zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 / 1.2)
		KEY_H, KEY_SLASH:
			if battle.ui:
				battle.ui.toggle_help()
		KEY_TAB:
			if battle.ui:
				battle.ui.toggle_palette()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


# ------------------------------------------------------------------ picks
## Where the mouse points on the ground or a building.
func pick(sp: Vector2) -> Dictionary:
	var r: Array = battle.cam.ray(sp)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var hit: Dictionary = battle.raycast(o, o + d * 500.0, B3Defs.L_TERRAIN | B3Defs.L_STRUCT)
	if hit.is_empty():
		var g: Vector3 = battle.cam.screen_to_ground(sp, 0.0)
		return {"pos": Vector3(g.x, battle.world.height_at(g.x, g.z), g.z), "collider": null}
	return {"pos": hit.position, "collider": hit.collider}


func unit_at(sp: Vector2, px := 30.0) -> B3Unit:
	var best: B3Unit = null
	var bd := 1e9
	var ppm: float = get_viewport().get_visible_rect().size.y / maxf(1.0, battle.cam.size)
	for u: B3Unit in battle.units:
		var c := u.center()
		if battle.cam.cam.is_position_behind(c):
			continue
		var s: Vector2 = battle.cam.screen_pos(c)
		var d := s.distance_to(sp)
		var tol := px + u.radius * ppm * 0.8
		if d < tol and d - tol < bd:
			bd = d - tol
			best = u
	return best


func body_at(sp: Vector2, mask: int) -> Object:
	var r: Array = battle.cam.ray(sp)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var hit: Dictionary = battle.raycast(o, o + d * 500.0, mask)
	if hit.is_empty():
		return null
	return hit.collider


# ------------------------------------------------------------------ place
## A friend placed something in our battle (👥): place it as they would have.
func place_for(c: Dictionary) -> void:
	var keep := [place_id, team, pers, place_size, struct_yaw]
	place_id = String(c.get("id", ""))
	team = String(c.get("team", "red"))
	pers = String(c.get("pers", "auto"))
	place_size = clampf(float(c.get("size", 1.0)), 0.5, 2.5)
	struct_yaw = float(c.get("yaw", 0.0)) - deg_to_rad(battle.cam.yaw)
	if B3Defs.UNITS.has(place_id) or B3Defs.HAZARDS.has(place_id) or B3Defs.STRUCTS.has(place_id):
		_recording = false      # (a friend's: not ours to undo)
		_place(c.get("a", Vector3.ZERO), c.get("b", Vector3.ZERO), bool(c.get("dragged", false)), bool(c.get("box", false)))
		_recording = true
	place_id = keep[0]
	team = keep[1]
	pers = keep[2]
	place_size = keep[3]
	struct_yaw = keep[4]


func _place(a: Vector3, b: Vector3, dragged: bool, box: bool) -> void:
	var counts := [battle.units.size(), battle.structs.size(), battle.hazards.size(), battle.props.size()]
	_place_now(a, b, dragged, box)
	if not _recording or (battle.net and battle.net.is_client()):
		return
	# ↶ what that just made can be taken back
	var made: Array = []
	var arrs: Array = [battle.units, battle.structs, battle.hazards, battle.props]
	for i in arrs.size():
		var arr: Array = arrs[i]
		if arr.size() > int(counts[i]):
			made.append_array(arr.slice(int(counts[i])))
	if not made.is_empty():
		undo.did_place(made, B3Undo._what(made))


func _place_now(a: Vector3, b: Vector3, dragged: bool, box: bool) -> void:
	var id := place_id
	if battle.net and battle.net.is_client():
		battle.net.send_cmd({"c": "place", "id": id, "team": team, "pers": pers, "size": place_size, "a": a, "b": b,
			"dragged": dragged, "box": box, "yaw": deg_to_rad(battle.cam.yaw) + struct_yaw})
		battle.snd("spawn", b, 0.5)
		return
	# 🪙 budget battles: only on your side, only what you can pay for (a
	# pool's price depends on how big you drag it: checked below)
	var tm := place_team()
	var why: String = battle.can_place(id, a, 0 if B3Defs.HAZARDS.has(id) else 1)
	if why != "":
		_nope(why, a)
		return
	if B3Defs.UNITS.has(id):
		if battle.budget >= 0:
			place_size = 1.0      # 🪙 budget battles: Normal size only (a Huge knight costs the same)
		var spots := _line_spots(a, b, dragged, box)
		var room: int = MAX_UNITS - battle.units.size()
		if room <= 0:
			if battle.ui:
				battle.ui.toast("That's a LOT of fighters! Clear some first. 🧹", false)
			return
		var n := 0
		for p in spots:
			if n >= room:
				break
			var sp: Vector3 = p
			if battle.can_place(id, sp) != "":
				continue       # outside your side, or out of points
			var nu: B3Unit = battle.spawn_unit(id, tm, sp, pers, INF, place_size)
			battle.buy(nu, id)
			n += 1
		if id == "trex" and n > 0:
			Settings.award("dino")      # 🦖 the Jurassic sticker, like a T-Rex in the 2D playground
		battle.fx.poof(b + Vector3(0, 0.5, 0), 0.6)
		battle.snd("spawn", b, 0.7)
		if battle.ui:
			battle.ui.counts_dirty = true
	elif B3Defs.HAZARDS.has(id):
		var d: Dictionary = B3Defs.HAZARDS[id]
		var kind := String(d.kind)
		var r: float = battle.pool_room(a, _pool_r(d, a, b, dragged))
		# 🪙 priced by how big it really is (a Pool, or a Lake past 5 m)
		var pid := B3Battle.pool_id(kind, r) if battle.budget >= 0 else id
		why = battle.can_place(pid, a)
		if why != "":
			_nope(why, a)
			return
		battle.buy(battle.spawn_hazard(kind, a, r), pid)
		battle.snd("splash", a, 0.8)
	elif B3Defs.STRUCTS.has(id):
		var pl := _struct_spot(id, a, b, dragged)
		var at: Vector3 = pl[0]
		var rot: float = pl[1]
		var len_: float = pl[2]
		# 🚧 budget battles: the whole building has to stand on your side
		if not battle.fits_zone(id, at, rot, len_):
			_nope("🚧 That sticks out past your side. Build it inside the glowing area!", a)
			return
		if id == "crates":
			# a stack of 6 crates (props, not a building): bought as one
			var n0: int = battle.props.size()
			battle.spawn_struct(id, at, rot)
			battle.buy_stack(battle.props.slice(n0), id)
			return
		battle.buy(battle.spawn_struct(id, at, rot, len_), id)


## No! (a message and a "nope" sound)
func _nope(why: String, at: Vector3) -> void:
	if battle.ui:
		battle.ui.toast(why, false)
	battle.snd("nope", at, 0.6)


## The team what you place joins: the Toy Box's, or in a budget battle
## always yours (B3Battle.build_team; 🧩 puzzles: red, even on the Animals
## and Dinos tabs, whose own team is wild).
func place_team() -> String:
	return String(battle.build_team) if String(battle.build_team) != "" else team


## Which way a Shift-drag block of fighters lines up: with the camera (and
## R's quarter turns). A friend's block comes with their camera's turn in
## struct_yaw (place_for), so it lines up with their screen.
func grid_yaw() -> float:
	return deg_to_rad(battle.cam.yaw) + struct_yaw


## A pool's radius: its own, or as far as you dragged it.
func _pool_r(d: Dictionary, a: Vector3, b: Vector3, dragged: bool) -> float:
	if dragged:
		return clampf(Vector2(b.x - a.x, b.z - a.z).length(), 1.5, 12.0)
	return float(d.radius)


## Where building `id` goes when placed from `a` (and dragged to `b`):
## [middle, yaw, length (walls)]. In a budget battle a drag stops at the
## edge of your side.
func _struct_spot(id: String, a: Vector3, b: Vector3, dragged: bool) -> Array:
	if dragged:
		b = battle.zone_clamp(b)
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var len_ := flat.length()
	var yaw: float = deg_to_rad(battle.cam.yaw) + struct_yaw
	match id:
		"wall":
			if dragged and len_ > 1.5:
				return [(a + b) * 0.5, atan2(-flat.z, flat.x), len_]
			return [a, yaw, 6.0]
		"ramp":
			if dragged and len_ > 1.0:
				var dir := flat / len_
				return [a + dir * 3.0, atan2(dir.x, dir.z), 0.0]
			return [a, yaw + PI, 0.0]
		"bridge":
			if dragged and len_ > 1.0:
				return [(a + b) * 0.5, atan2(flat.x, flat.z), 0.0]
			return [a, yaw + PI * 0.5, 0.0]
	return [a, yaw, 0.0]


func _line_spots(a: Vector3, b: Vector3, dragged: bool, box: bool) -> Array:
	var out := []
	if not dragged:
		out.append(a)
		return out
	var def := B3Defs.unit_def(place_id)
	var rig_r := 0.35 * float(def.size)
	match String(def.body):
		"quad":
			var q: Dictionary = B3Rig.QUAD.get(String(def.style), {"bw": 1.0, "bl": 1.0})
			rig_r = maxf(float(q.bw) * 0.6, float(q.bl) * 0.35)
		"biped":
			var q2: Dictionary = B3Rig.BIPED[String(def.style)]
			rig_r = float(q2.bl) * 0.38
		"bird":
			rig_r = 0.3 if String(def.style) == "chicken" else 0.8
		"rider":
			rig_r = 0.75      # a horse is long
	var spacing := maxf(1.1, rig_r * 2.4) * (place_size if not String(def.body) in ["vehicle"] else 1.0)
	if box:
		# the block's rows run across the screen and its columns up it, however
		# the camera is turned (R turns it a quarter more, like a building)
		var yaw := grid_yaw()
		var ax := Vector3(cos(yaw), 0, -sin(yaw))       # across
		var az := Vector3(sin(yaw), 0, cos(yaw))        # up / down the screen
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		var dx := d.dot(ax)
		var dz := d.dot(az)
		var nx := clampi(int(absf(dx) / spacing) + 1, 1, 12)
		var nz := clampi(int(absf(dz) / spacing) + 1, 1, 12)
		for ix in nx:
			for iz in nz:
				var p := a + ax * (dx * ix / maxf(1.0, nx - 1.0)) + az * (dz * iz / maxf(1.0, nz - 1.0))
				p.y = battle.surface_y(Vector3(p.x, 60.0, p.z))
				out.append(p)
		return out
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var n := clampi(int(flat.length() / spacing) + 1, 1, 40)
	for i in n:
		var t := 0.0 if n == 1 else float(i) / (n - 1)
		var p := a.lerp(b, t)
		p.y = battle.surface_y(Vector3(p.x, 60.0, p.z))
		out.append(p)
	return out


# ------------------------------------------------------------------- grab
func _grab_start(sp: Vector2) -> bool:
	if battle.puppet:
		if battle.ui:
			battle.ui.toast("✋ Only the host can grab things in a shared battle.", false)
		return false
	var u := unit_at(sp, 24.0)
	# 🧩 / 🌊 some things can't be grabbed (B3Battle.hands_off): the puzzle's
	# army, or anything once a puzzle's fight is on
	var who: Node = u if u and not u.dead else null
	if who == null:
		var c0 := body_at(sp, B3Defs.L_RAGDOLL | B3Defs.L_PROP)
		if c0 is RigidBody3D:
			who = c0 as Node
			if who.has_meta("ragdoll"):
				var rd0 = who.get_meta("ragdoll")
				if is_instance_valid(rd0) and rd0.unit and is_instance_valid(rd0.unit):
					who = rd0.unit
	if who:
		var why: String = battle.hands_off(who, "grab")
		if why != "":
			_nope(why, pick(sp).pos)
			return false
	if u and u.is_vehicle() and not u.dead:
		# vehicles are picked up whole: they dangle, then land back on their wheels
		grab_body = u
		grab_unit = u
		u.held = true
	elif u and not u.dead:
		if not u.down:
			u.knock_down(Vector3(0, 3.0, 0))
		if u.ragdoll and is_instance_valid(u.ragdoll):
			u.ragdoll.unfreeze()
			grab_body = u.ragdoll.root_body
			grab_unit = u
			u.held = true
	else:
		var c := body_at(sp, B3Defs.L_RAGDOLL | B3Defs.L_PROP)
		if c is RigidBody3D:
			grab_body = c as RigidBody3D
			if grab_body.has_meta("ragdoll"):
				var rd = grab_body.get_meta("ragdoll")
				rd.unfreeze()
				if rd.unit and is_instance_valid(rd.unit):
					grab_unit = rd.unit
					grab_unit.held = true
			elif grab_body.freeze:
				grab_body.freeze = false
	if grab_body == null:
		return false
	_grab_prev = grab_body.global_position
	_grab_from = grab_unit.center() if grab_unit and is_instance_valid(grab_unit) else grab_body.global_position
	_grab_vel = Vector3.ZERO
	grab_h = clampf(2.5 + grab_body.mass * 0.0, 2.5, 4.0)
	battle.snd("grab", grab_body.global_position, 0.8)
	return true


func _grab_end(fling: bool) -> void:
	if grab_body and is_instance_valid(grab_body):
		if _zone_held():
			# 🧩 before a puzzle's fight you can move your army about your side, not throw it
			fling = false
			grab_body.linear_velocity = Vector3.ZERO
		if fling:
			var v := _grab_vel * 1.3
			if v.length() > 45.0:
				v = v.normalized() * 45.0
			grab_body.linear_velocity = v
			if v.length() > 8.0:
				battle.snd("whoosh", grab_body.global_position, 0.8)
	# ↶ puts it back where it was
	var moved: Node = grab_unit if grab_unit and is_instance_valid(grab_unit) else (grab_body if grab_body is B3Prop else null)
	if moved and is_instance_valid(moved) and not (moved is B3Unit and (moved as B3Unit).dead):
		var to: Vector3 = (moved as B3Unit).center() if moved is B3Unit else (moved as Node3D).global_position
		undo.did_move(moved, _grab_from, to)
	if grab_unit and is_instance_valid(grab_unit):
		grab_unit.held = false
	grab_body = null
	grab_unit = null


func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	if grab_body:
		if not is_instance_valid(grab_body):
			grab_body = null
			grab_unit = null
			return
		var target: Vector3 = pick(_mouse).pos + Vector3(0, grab_h, 0)
		if _zone_held():
			var inner: Rect2 = battle.build_zone.grow(-0.5)
			target.x = clampf(target.x, inner.position.x, inner.end.x)      # 🧩 it stays on your side
			target.z = clampf(target.z, inner.position.y, inner.end.y)
		var to := target - grab_body.global_position
		var v := to * 14.0
		if v.length() > 40.0:
			v = v.normalized() * 40.0
		grab_body.linear_velocity = grab_body.linear_velocity.lerp(v, 0.6)
		grab_body.angular_velocity *= 0.9
		var mv := (target - _grab_prev) / dt
		_grab_vel = _grab_vel.lerp(mv, 0.3)
		_grab_prev = target
		if grab_unit and is_instance_valid(grab_unit):
			grab_unit.down_t = 0.0


## 🧩 In a puzzle, before ▶ Fight!, what you grab stays on your side (the
## glowing area) and is put down, not thrown.
func _zone_held() -> bool:
	return battle.puzzle != null and not battle.fighting and battle.build_zone.size != Vector2.ZERO


# ------------------------------------------------------------------ erase
func _erase_at(sp: Vector2) -> void:
	if battle.net and battle.net.is_client():
		_erase_remote(sp)
		return
	var u := unit_at(sp, 22.0)
	if u:
		if _kept(u):
			return
		if u == selected:
			select(null)
		undo.will_erase(u)      # (↶ brings it back)
		battle.remove_unit(u)
		return
	var c := body_at(sp, B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_STRUCT)
	if c:
		if c is RigidBody3D and (c as Node).has_meta("ragdoll"):
			var rd = (c as Node).get_meta("ragdoll")
			if is_instance_valid(rd) and rd.unit and is_instance_valid(rd.unit) and not rd.unit.dead:
				undo.will_erase(rd.unit)      # a fighter lying knocked down (not a knocked-out one)
			battle.remove_ragdoll(rd)
			return
		if c is B3Prop:
			undo.will_erase(c as B3Prop)
			battle.remove_prop(c as B3Prop)
			return
		if c is RigidBody3D and (c as Node).has_meta("debris"):
			battle.remove_chunk(c as RigidBody3D)
			return
		if c is B3Piece:
			if not _kept((c as B3Piece).structure):
				undo.will_erase((c as B3Piece).structure)
				battle.remove_struct((c as B3Piece).structure)
			return
	var g: Vector3 = pick(sp).pos
	var h: B3Hazard = battle.hazard_at(g + Vector3(0, 0.2, 0), 0.0)
	if h and not _kept(h):
		undo.will_erase(h)
		battle.remove_hazard(h, true)


## True (and, on a click, says why) if the Eraser has to leave `n` alone:
## 🧩 the puzzle's army, buildings and pools, 🌊 the attackers.
func _kept(n: Node) -> bool:
	var why: String = battle.hands_off(n, "erase")
	if why == "":
		return false
	if drag.get("mode", "") != "erase":      # (not again for every wiggle of a drag)
		_nope(why, (n as Node3D).global_position if n is Node3D else Vector3.ZERO)
	return true


## In a friend's battle: tell the host what to erase.
func _erase_remote(sp: Vector2) -> void:
	var u := unit_at(sp, 22.0)
	if u and u.has_meta("nid"):
		battle.net.send_cmd({"c": "erase", "nid": int(u.get_meta("nid"))})
		return
	var c := body_at(sp, B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_STRUCT)
	if c:
		if c is RigidBody3D and (c as Node).has_meta("ragdoll"):
			var rd = (c as Node).get_meta("ragdoll")
			if is_instance_valid(rd) and (rd as Node).has_meta("nid"):
				battle.net.send_cmd({"c": "erase_corpse", "nid": int((rd as Node).get_meta("nid"))})
			return
		if c is B3Prop and (c as Node).has_meta("nid"):
			battle.net.send_cmd({"c": "erase", "nid": int((c as Node).get_meta("nid"))})
			return
		if c is B3Piece and (c as B3Piece).structure and ((c as B3Piece).structure as Node).has_meta("nid"):
			battle.net.send_cmd({"c": "erase", "nid": int(((c as B3Piece).structure as Node).get_meta("nid"))})
			return
	var g: Vector3 = pick(sp).pos
	var h: B3Hazard = battle.hazard_at(g + Vector3(0, 0.2, 0), 0.0)
	if h and h.has_meta("nid"):
		battle.net.send_cmd({"c": "erase", "nid": int(h.get_meta("nid"))})


# ------------------------------------------------------------- per frame
func _process(_d: float) -> void:
	var dt: float = 1.0 / maxf(1.0, Engine.get_frames_per_second())
	_t += dt
	if not _typing():
		var v := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
		if B3Player.playing:
			_player_tick(v)
		elif v != Vector2.ZERO:
			battle.cam.pan_keys(v.normalized(), minf(dt, 0.05))
	_update_ghost()
	if B3Player.active():
		# a spinning ring marks the fighter you're playing
		var me := B3Player.unit
		_sel_ring.visible = not B3Player.me.fp
		var mp := me.position if not me.down else me.center()
		var mr := me.radius * 1.7 + 0.35
		_sel_ring.global_transform = Transform3D(Basis(Vector3.UP, _t * 3.0).scaled(Vector3(mr, 0.5, mr)), Vector3(mp.x, mp.y + 0.08, mp.z))
	elif selected and is_instance_valid(selected) and not selected.dead:
		_sel_ring.visible = true
		var p := selected.position if not selected.down else selected.center()
		var r := selected.radius * 1.5 + 0.25
		_sel_ring.global_transform = Transform3D(Basis(Vector3.UP, _t * 2.0).scaled(Vector3(r, 0.5, r)), Vector3(p.x, p.y + 0.08, p.z))
	else:
		_sel_ring.visible = false
		if selected != null:
			if group.size() > 1:
				select_many(group)      # (the first one's gone: the others stay picked)
			else:
				select(null)
	_group_rings()


## 👥 A ring under every other fighter picked with a box (the first has its own).
func _group_rings() -> void:
	if _grp_rings == null or not is_instance_valid(_grp_rings):
		return
	var mm := _grp_rings.multimesh
	if group.size() < 2 or B3Player.active():
		if _grp_rings.visible:
			_grp_rings.visible = false
			mm.visible_instance_count = 0
		return
	var n := 0
	var gone := false
	for u in group:
		if not is_instance_valid(u) or u.dead:
			gone = true
			continue
		if u == selected or n >= mm.instance_count:
			continue
		var p := u.position if not u.down else u.center()
		var r := u.radius * 1.5 + 0.25
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, _t * 2.0).scaled(Vector3(r, 0.5, r)), Vector3(p.x, p.y + 0.08, p.z)))
		n += 1
	mm.visible_instance_count = n
	_grp_rings.visible = n > 0
	if gone:
		select_many(group)      # (knocked out or erased: they drop out of the group)


func _player_tick(v: Vector2) -> void:
	var u := B3Player.unit
	if not B3Player.active():
		player_lost()
		return
	B3Player.last_pos = u.global_position
	var me := B3Player.me
	me.steer = Vector2(v.x, -v.y)
	me.lift = (1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0) - (1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0)
	if me.fp:
		if battle.puppet and u.is_vehicle() and (u.style_is("car") or u.style_is("jeep")):
			# in a friend's battle our copy of the car turns, so the view turns with it here
			var yaw := atan2(u.global_basis.z.x, u.global_basis.z.z)
			if _veh_yaw != INF:
				me.look_yaw = wrapf(me.look_yaw + angle_difference(_veh_yaw, yaw), -PI, PI)
			_veh_yaw = yaw
		# W walks where you're looking; the crosshair is what you aim at
		var fwd := Vector3(sin(me.look_yaw), 0, cos(me.look_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var m := fwd * -v.y + right * v.x
		me.move = m.normalized() if m.length() > 0.01 else Vector3.ZERO
		me.aim = crosshair_point(u)
		return
	# overhead: WASD is relative to the camera, W goes "up the screen"
	var b: Basis = battle.cam.basis_now()
	var right2 := Vector3(b.x.x, 0, b.x.z).normalized()
	var fwd2 := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var m2 := right2 * v.x - fwd2 * v.y
	me.move = m2.normalized() if m2.length() > 0.01 else Vector3.ZERO
	me.aim = pick(_mouse).pos
	if battle.cam.follow == null:
		battle.cam.follow = u


## The first thing the middle of the first-person view points at (up to 400 m away).
func crosshair_point(u: B3Unit) -> Vector3:
	var c: Camera3D = battle.cam.cam
	var xf := c.global_transform
	var from := xf.origin
	var dir := -xf.basis.z
	var ex: Array = [u.get_rid()]
	if u.ragdoll and is_instance_valid(u.ragdoll):
		for rb: RigidBody3D in u.ragdoll.bodies:
			ex.append(rb.get_rid())
	var hit: Dictionary = battle.raycast(from + dir * 0.3, from + dir * 400.0, B3Player.MASK, ex)
	return hit.position if not hit.is_empty() else from + dir * 400.0


func _update_ghost() -> void:
	if B3Player.unit != null:
		_ghost_ring.visible = false
		_ghost_box.visible = false
		_line.visible = false
		return
	if not is_instance_valid(_ghost_ring):
		return
	_ghost_ring.visible = false
	_ghost_box.visible = false
	_line.visible = true      # (hidden while playing a fighter)
	var mm := _line.multimesh
	mm.visible_instance_count = 0
	if get_viewport().gui_get_hovered_control() != null and drag.is_empty():
		return
	var mp := get_viewport().get_mouse_position()
	if tool == "erase":
		var g: Vector3 = pick(mp).pos
		_ring_at(g, 0.8, Color(1.0, 0.4, 0.4, 0.9))
		return
	if tool != "place" or place_id == "":
		return
	var hit := pick(mp)
	var p: Vector3 = hit.pos
	var tc := B3Defs.team_col(place_team())
	if B3Defs.UNITS.has(place_id):
		if drag.get("mode", "") == "place":
			var a: Vector3 = drag.start
			var dragged := (mp - (drag.sp as Vector2)).length() > 12.0
			var spots := _line_spots(a, p, dragged, Input.is_key_pressed(KEY_SHIFT))
			var n := mini(spots.size(), mm.instance_count)
			for i in n:
				var s: Vector3 = spots[i]
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, s + Vector3(0, 0.06, 0)))
				mm.set_instance_color(i, Color(tc, 0.75))
			mm.visible_instance_count = n
		else:
			mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.06, 0)))
			mm.set_instance_color(0, Color(tc, 0.6))
			mm.visible_instance_count = 1
	elif B3Defs.BOOMS.has(place_id):
		var d: Dictionary = B3Defs.BOOMS[place_id]
		var r := float(d.radius)
		if place_id == "nuke":
			r = 26.0
		elif place_id == "airstrike":
			r = 10.0
		elif place_id == "artillery":
			r = 8.0
		_ring_at(p, r, Color(1.0, 0.35, 0.25, 0.85))
	elif B3Defs.HAZARDS.has(place_id):
		var d2: Dictionary = B3Defs.HAZARDS[place_id]
		var r2 := float(d2.radius)
		var c := p
		if drag.get("mode", "") == "place":
			c = drag.start
			if (mp - (drag.sp as Vector2)).length() > 12.0:
				r2 = clampf(Vector2(p.x - c.x, p.z - c.z).length(), 1.5, 12.0)
		r2 = battle.pool_room(c, r2)      # (as big as it'll really be: see _place)
		_ring_at(c, r2, Color(1.0, 0.5, 0.1, 0.9) if String(d2.kind) == "lava" else Color(0.4, 1.0, 0.3, 0.9))
	elif B3Defs.STRUCTS.has(place_id):
		var size := Vector3(3, 1.2, 3)
		var yaw: float = deg_to_rad(battle.cam.yaw) + struct_yaw
		var c2 := p
		match place_id:
			"wall":
				size = Vector3(6, 2.8, 0.6)
				if drag.get("mode", "") == "place":
					var a2: Vector3 = drag.start
					p = battle.zone_clamp(p)      # (a drag stops at the edge of your side, see _struct_spot)
					var f := Vector3(p.x - a2.x, 0, p.z - a2.z)
					if f.length() > 1.5:
						size.x = clampf(f.length(), 2.0, 24.0)
						yaw = atan2(-f.z, f.x)
						c2 = (a2 + p) * 0.5
			"ramp":
				size = Vector3(2.6, 2.2, 6.0)
			"tower":
				size = Vector3(4, 5.3, 4)
			"bunker":
				size = Vector3(5.6, 2.7, 5.6)
			"bridge":
				size = Vector3(3, 3.2, 19)
				yaw += PI * 0.5
			"sandbags":
				size = Vector3(4.5, 0.9, 1.5)
			"crates":
				size = Vector3(3.2, 3, 1.1)
		var gy: float = battle.world.height_at(c2.x, c2.z)
		_ghost_box.visible = true
		_ghost_box.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(size), Vector3(c2.x, gy + size.y * 0.5, c2.z))


func _ring_at(p: Vector3, r: float, c: Color) -> void:
	_ghost_ring.visible = true
	_ghost_ring.material_override = B3Mats.flat(c)
	_ghost_ring.global_transform = Transform3D(Basis(Vector3.UP, _t * 0.8).scaled(Vector3(r, 0.4, r)), p + Vector3(0, 0.12, 0))

class_name Game
extends Node2D
## One play session: the world, effects, camera, HUD, network, and your
## mouse/keyboard turned into commands. Commands go to the world directly
## (solo or hosting) or to the host (when you joined someone).

const TOOLS := [
	{"id": "grab", "icon": "✋", "name": "Grab", "key": "1", "tip": "Drag and throw things. Double-click to use them."},
	{"id": "glue", "icon": "🧴", "name": "Glue", "key": "2", "tip": "Drag from one thing to another to stick them together."},
	{"id": "hinge", "icon": "📍", "name": "Hinge", "key": "3", "tip": "Drag between two things: they stay joined but can spin."},
	{"id": "rope", "icon": "🪢", "name": "Rope", "key": "4", "tip": "Drag between two things to tie a rope."},
	{"id": "spring", "icon": "🌀", "name": "Spring", "key": "5", "tip": "Drag between two things to add a bouncy spring."},
	{"id": "wire", "icon": "🔌", "name": "Wire", "key": "6", "tip": "Drag from a battery, switch, button or timer to a machine."},
	{"id": "paint", "icon": "🎨", "name": "Paint", "key": "7", "tip": "Click things to paint them."},
	{"id": "resize", "icon": "🔍", "name": "Resize", "key": "8", "tip": "Click to grow. Shift-click (or right-click) to shrink."},
	{"id": "nail", "icon": "📌", "name": "Nail", "key": "9", "tip": "Click a toy to nail it in place (click again to unnail)."},
	{"id": "erase", "icon": "🧽", "name": "Eraser", "key": "0", "tip": "Click or drag over things (or platforms) to remove them."},
	{"id": "platform", "icon": "🏗️", "name": "Platform", "key": "P", "tip": "Drag to draw a solid platform anywhere."},
]
const LINK_TOOLS := ["glue", "hinge", "rope", "spring", "wire"]

var main: Node = null
var world: World
var effects: Effects
var cam: Cam
var hud = null
var net = null
var mode := "solo"
var tool := "grab"
var placing := ""
var keep_placing := false
var selected_uid := -1
var paint_color: Color = Catalog.PAINT[0]
var spawn_team := "red"
var spawn_pers := ""          # "" = each fighter's usual personality
var platform_style := "wood"
var playing_uid := -1
var drag := {}
var _last_click := {"uid": -1, "t": 0}
var _move_sent := 0.0
var _input_t := 0.0
var _grab_t := 0.0
var _rotate_t := 0.0
var _env: WorldEnvironment


func begin(opts: Dictionary) -> void:
	mode = String(opts.get("mode", "solo"))
	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, i >= 1 and i <= 4)
	_env.environment = env
	add_child(_env)

	world = World.new()
	world.puppet = mode == "client"
	add_child(world)
	effects = Effects.new()
	effects.world = world
	add_child(effects)
	world.fx.connect(_on_fx)
	cam = Cam.new()
	cam.effects = effects
	add_child(cam)
	cam.make_current()
	z_index = 50

	hud = HUD.new()
	hud.game = self
	add_child(hud)
	Settings.sticker_earned.connect(func(id): if hud: hud.show_sticker(id))

	var wid := String(opts.get("world", Settings.last_world))
	if mode == "client":
		world.load_world(wid, false)
		net = NetClient.new()
		net.game = self
		add_child(net)
		net.connect_to(String(opts.get("ip", "")))
	else:
		world.load_world(wid)
		if mode == "host":
			start_hosting()
	Settings.last_world = wid
	Settings.save()
	world.world_changed.connect(_on_world_changed)
	cam.fit(world.view_rect, get_viewport_rect().size)
	var sc := String(opts.get("scenario", ""))
	if sc != "":
		Scenarios.run(self, sc)
	if hud:
		hud.refresh()
		var open_what := String(opts.get("open", "")).split(":")
		if open_what.size() > 1:
			hud.cat = open_what[1]
		match open_what[0]:
			"toybox", "worlds", "magic":
				hud.toggle_drawer(open_what[0])
			"help":
				hud.toggle_help()
			"stickers":
				hud.show_stickers()
			"together":
				hud.show_together()
			"settings":
				hud.show_settings()


func start_hosting() -> bool:
	if net != null:
		return true
	var h := NetHost.new()
	h.game = self
	add_child(h)
	if not h.open():
		h.queue_free()
		if hud:
			hud.toast("Couldn't start hosting. Is another game already hosting on this computer?")
		return false
	net = h
	mode = "host"
	if hud:
		hud.refresh()
	return true


func stop_hosting() -> void:
	if net and mode == "host":
		net.close()
		net.queue_free()
		net = null
		mode = "solo"
		world.allow_world_actions = true
		if hud:
			hud.refresh()


func leave() -> void:
	if net:
		net.close()
	world.set_paused(false)
	world.set_speed(1.0)
	Engine.time_scale = 1.0
	PhysicsServer2D.set_active(true)
	if main:
		main.show_menu()


# ---------------------------------------------------------------- commands
func send(c: Dictionary) -> void:
	if mode == "client":
		if net:
			net.send_cmd(c)
	else:
		world.apply_command(0, c)


func _on_fx(name: String, args: Dictionary) -> void:
	effects.handle(name, args)
	if mode == "host" and net:
		net.queue_fx(name, args)


func _on_world_changed(rebuilt: bool) -> void:
	# only a new, undone or cleared playground wipes the effects (not ⚔️, pause or night)
	if rebuilt:
		effects.clear()
	if hud:
		hud.refresh()


func local_pos() -> Vector2:
	return cam.screen_to_world(get_viewport().get_mouse_position())


func selected():
	return world.things.get(selected_uid)


func select(uid: int) -> void:
	selected_uid = uid
	if hud:
		hud.refresh_selection()


func set_tool(id: String) -> void:
	tool = id
	placing = ""
	if hud:
		hud.refresh_tools()
		for t in TOOLS:
			if t.id == id and id != "grab":
				hud.toast(t.tip)


func start_placing(id: String) -> void:
	placing = id
	tool = "grab"
	if hud:
		hud.refresh_tools()
		hud.toast("Click anywhere to drop: " + Catalog.spawn_name(id))


func play_as(uid: int) -> void:
	var t = world.things.get(uid)
	if not (t is Wiggly or t is Fighter):
		return
	playing_uid = uid
	send({"cmd": "play", "uid": uid})
	cam.follow = t
	if hud:
		hud.refresh_selection()
		if t is Fighter:
			hud.toast("You're playing as the %s! A/D to walk, W to jump, aim with the mouse, click (or hold F) to attack. Esc to stop." % t.display_name(), 4.0)
		else:
			hud.toast("You're playing as %s! A/D to roll, W to jump, F for %s. Esc to stop." % [t.display_name(), t.def.special])


func stop_playing() -> void:
	if playing_uid < 0:
		return
	send({"cmd": "input", "move": 0.0})
	send({"cmd": "play", "uid": -1})
	playing_uid = -1
	cam.follow = null
	if hud:
		hud.refresh_selection()


# ------------------------------------------------------------------- input
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		_mouse_button(e)
	elif e is InputEventMouseMotion:
		_mouse_motion(e)
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e)
	elif e is InputEventKey and not e.pressed:
		_key_up(e)
	elif e is InputEventMagnifyGesture:
		cam.zoom_at(e.position, e.factor)
	elif e is InputEventPanGesture:
		cam.pan(-e.delta * 12.0)


func _mouse_button(e: InputEventMouseButton) -> void:
	var wp := cam.screen_to_world(e.position)
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		cam.zoom_at(e.position, 1.12)
		return
	if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		cam.zoom_at(e.position, 1.0 / 1.12)
		return
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		drag = {"mode": "pan"} if e.pressed else {}
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if e.pressed:
			if placing != "":
				placing = ""
				if hud:
					hud.refresh_tools()
				return
			var th = world.thing_at(wp)
			if th and tool == "resize":
				_resize(th, false)
			elif th:
				select(th.uid)
			else:
				drag = {"mode": "pan"}
		else:
			drag = {}
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_left_down(wp, e)
	else:
		_left_up(wp, e)


func _playing_fighter() -> bool:
	return playing_uid >= 0 and world.things.get(playing_uid) is Fighter


func _left_down(wp: Vector2, e: InputEventMouseButton) -> void:
	if _playing_fighter() and placing == "":
		send({"cmd": "input", "move": _move_dir(), "attack": true, "ax": wp.x, "ay": wp.y})
		drag = {"mode": "attack"}
		return
	if placing != "":
		send({"cmd": "spawn", "id": placing, "x": wp.x, "y": wp.y, "team": spawn_team, "pers": spawn_pers})
		Settings.add_recent(placing)
		if not (keep_placing or e.shift_pressed):
			placing = ""
		if hud:
			hud.refresh_tools()
			hud.refresh_toybox_recent()
		return
	var th = world.thing_at(wp)
	match tool:
		"grab":
			if th == null:
				select(-1)
				drag = {"mode": "pan"}
				return
			select(th.uid)
			var now := Time.get_ticks_msec()
			if _last_click.uid == th.uid and now - int(_last_click.t) < 350:
				send({"cmd": "use", "uid": th.uid})
			_last_click = {"uid": th.uid, "t": now}
			send({"cmd": "grab", "uid": th.uid, "x": wp.x, "y": wp.y})
			drag = {"mode": "grab", "uid": th.uid}
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		"glue", "hinge", "rope", "spring", "wire":
			if th == null:
				drag = {"mode": "pan"}
				return
			var ai: int = th.nearest_point(wp) if th is Wiggly else -1
			drag = {"mode": "link", "a": th.uid, "ai": ai, "from": wp}
		"paint":
			if th:
				send({"cmd": "paint", "uid": th.uid, "color": paint_color.to_html()})
			drag = {"mode": "paint"}
		"resize":
			if th:
				_resize(th, not e.shift_pressed)
		"nail":
			if th is Toy:
				send({"cmd": "nail", "uid": th.uid})
		"erase":
			if th:
				send({"cmd": "erase", "uid": th.uid})
				if th.uid == selected_uid:
					select(-1)
			else:
				send({"cmd": "unplatform", "x": wp.x, "y": wp.y})
			drag = {"mode": "erase", "done": {}}
		"platform":
			drag = {"mode": "platform", "from": wp}


func _left_up(wp: Vector2, _e: InputEventMouseButton) -> void:
	match String(drag.get("mode", "")):
		"attack":
			send({"cmd": "input", "move": _move_dir(), "attack": false, "ax": wp.x, "ay": wp.y})
		"platform":
			var a: Vector2 = drag.from
			if a.distance_to(wp) > 8.0:
				send({"cmd": "platform", "x0": a.x, "y0": a.y, "x1": wp.x, "y1": wp.y, "style": platform_style})
		"grab":
			send({"cmd": "release"})
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		"link":
			var th = world.thing_at(wp)
			if th and th.uid != int(drag.a):
				var bi: int = th.nearest_point(wp) if th is Wiggly else -1
				var from: Vector2 = drag.from
				send({"cmd": "link", "kind": tool, "a": int(drag.a), "ai": int(drag.ai), "b": th.uid, "bi": bi,
					"ax": from.x, "ay": from.y, "bx": wp.x, "by": wp.y})
			elif hud:
				hud.toast("Let go on a different thing to connect them.")
	drag = {}


func _mouse_motion(e: InputEventMouseMotion) -> void:
	var wp := cam.screen_to_world(e.position)
	match String(drag.get("mode", "")):
		"pan":
			cam.pan(e.relative)
		"grab":
			_send_drag(wp, Input.is_key_pressed(KEY_SHIFT))
		"paint":
			var th = world.thing_at(wp)
			if th and th.get("paint") != paint_color:
				send({"cmd": "paint", "uid": th.uid, "color": paint_color.to_html()})
		"erase":
			var th = world.thing_at(wp)
			if th and not drag.done.has(th.uid):
				drag.done[th.uid] = true
				send({"cmd": "erase", "uid": th.uid})


func _send_drag(wp: Vector2, whole: bool) -> void:
	var now := Time.get_ticks_msec()
	if mode == "client" and now - _grab_t < 30:
		return
	_grab_t = now
	send({"cmd": "drag", "x": wp.x, "y": wp.y, "whole": whole})


func _resize(th, grow: bool) -> void:
	var s: float = th.size if th is Wiggly or th is Fighter else th.size_scale
	s = s * (1.18 if grow else 1.0 / 1.18)
	send({"cmd": "resize", "uid": th.uid, "s": s})


func _key(e: InputEventKey) -> void:
	var k := e.keycode
	if (e.ctrl_pressed or e.meta_pressed) and k == KEY_Z:
		send({"cmd": "undo"})
		return
	if playing_uid >= 0:
		match k:
			KEY_ESCAPE, KEY_C:
				stop_playing()
				return
			KEY_W, KEY_UP, KEY_SPACE:
				send({"cmd": "input", "move": _move_dir(), "jump": true})
				return
			KEY_F:
				if _playing_fighter():
					var mp := local_pos()
					send({"cmd": "input", "move": _move_dir(), "attack": true, "ax": mp.x, "ay": mp.y})
				else:
					send({"cmd": "input", "move": _move_dir(), "special": true})
				return
			KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT:
				send({"cmd": "input", "move": _move_dir()})
				return
	match k:
		KEY_SPACE:
			send({"cmd": "pause", "on": not world.paused})
		KEY_TAB:
			if hud:
				hud.toggle_drawer("toybox")
		KEY_ESCAPE:
			if placing != "":
				placing = ""
				if hud:
					hud.refresh_tools()
			elif hud and hud.close_top():
				pass
			elif tool != "grab":
				set_tool("grab")
			else:
				select(-1)
		KEY_G:
			send({"cmd": "speed", "v": 1.0 if world.time_scale < 0.9 else 0.3})
		KEY_F:
			if selected_uid >= 0:
				send({"cmd": "use", "uid": selected_uid})
		KEY_C:
			var s = selected()
			if s is Wiggly or (s is Fighter and s.alive()):
				play_as(selected_uid)
		KEY_R:
			if selected_uid >= 0:
				send({"cmd": "flip", "uid": selected_uid})
		KEY_N:
			if selected() is Toy:
				send({"cmd": "nail", "uid": selected_uid})
		KEY_P:
			set_tool("platform")
		KEY_DELETE, KEY_BACKSPACE:
			if selected_uid >= 0:
				send({"cmd": "erase", "uid": selected_uid})
				select(-1)
		KEY_EQUAL, KEY_KP_ADD:
			cam.zoom_at(get_viewport_rect().size * 0.5, 1.2)
		KEY_MINUS, KEY_KP_SUBTRACT:
			cam.zoom_at(get_viewport_rect().size * 0.5, 1.0 / 1.2)
		KEY_H, KEY_SLASH:
			if hud:
				hud.toggle_help()
		_:
			if k >= KEY_0 and k <= KEY_9 and not _playing_fighter():
				var idx := (int(k - KEY_0) + 9) % 10
				set_tool(TOOLS[idx].id)


func _key_up(e: InputEventKey) -> void:
	if playing_uid >= 0 and e.keycode in [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]:
		send({"cmd": "input", "move": _move_dir()})
	if _playing_fighter() and e.keycode == KEY_F:
		send({"cmd": "input", "move": _move_dir(), "attack": false})


func _move_dir() -> float:
	var m := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		m -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		m += 1.0
	if hud:
		m = clampf(m + hud.pad_move, -1.0, 1.0)
	return m


func _process(dt: float) -> void:
	effects.view_rect = cam.view_rect()
	world.view_rect = world.view_rect  # (the host keeps its own spawn area)
	if world.backdrop:
		world.backdrop.cam_pos = cam.center()
		world.backdrop.cam_zoom = cam.zoom.x
	# camera keys (not while playing as a Wiggly)
	if playing_uid < 0 and not _typing():
		var v := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
		if v != Vector2.ZERO:
			cam.move_world(v * 620.0 * dt / maxf(0.3, cam.zoom.x) / maxf(0.1, Engine.time_scale))
	# keep a held grab alive and moving even when the mouse is still
	if drag.get("mode", "") == "grab":
		_grab_hold_t(dt)
	# rotate the selected toy with Q / E
	if selected_uid >= 0 and not _typing() and playing_uid < 0:
		var d := (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
		_rotate_t -= dt
		if d != 0.0 and _rotate_t <= 0.0:
			_rotate_t = 0.05
			send({"cmd": "rotate", "uid": selected_uid, "d": d})
	# playing: keep sending the walk direction to the host
	if playing_uid >= 0:
		if not world.things.has(playing_uid):
			stop_playing()
		elif _playing_fighter():
			# fighters aim at the mouse, so keep telling the host where it is
			_input_t -= dt
			if _input_t <= 0.0:
				_input_t = 0.06 if mode == "client" else 0.03
				var mp := local_pos()
				send({"cmd": "input", "move": _move_dir(), "ax": mp.x, "ay": mp.y})
		elif mode == "client":
			_input_t -= dt
			var m := _move_dir()
			if m != _move_sent or (_input_t <= 0.0 and m != 0.0):
				_input_t = 0.15
				_move_sent = m
				send({"cmd": "input", "move": m})
		elif hud and hud.pad_move != 0.0:
			send({"cmd": "input", "move": _move_dir()})
	if selected_uid >= 0 and not world.things.has(selected_uid):
		select(-1)
	queue_redraw()


var _hold_t := 0.0
func _grab_hold_t(dt: float) -> void:
	_hold_t -= dt
	if _hold_t <= 0.0:
		_hold_t = 0.1
		_send_drag(local_pos(), Input.is_key_pressed(KEY_SHIFT))


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


# ----------------------------------------------------------- tool overlay
func _draw() -> void:
	var mp := local_pos()
	if placing != "":
		modulate = Color(1, 1, 1, 1)
		Preview.draw_ghost(self, placing, mp)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if drag.get("mode", "") == "link":
		var from: Vector2 = drag.from
		var col: Color = {"glue": Color("fdcb6e"), "hinge": Color("dfe6e9"), "rope": Color("c8914f"), "spring": Color("74b9ff"), "wire": Color("5ad66a")}.get(tool, Color.WHITE)
		_dashed(from, mp, col)
		draw_circle(from, 6.0, col, true, -1.0, true)
	if tool == "erase":
		draw_arc(mp, 18.0 / cam.zoom.x, 0, TAU, 24, Color(1, 0.4, 0.4, 0.9), 2.0, true)
	elif tool == "paint":
		draw_circle(mp + Vector2(14, 14) / cam.zoom.x, 7.0 / cam.zoom.x, paint_color, true, -1.0, true)
	# selection ring
	if drag.get("mode", "") == "platform":
		var a: Vector2 = drag.from
		var r2 := Rect2(a, Vector2.ZERO).expand(mp)
		draw_rect(r2, Color(1.0, 0.85, 0.4, 0.35))
		draw_rect(r2, Color(1.0, 0.85, 0.4, 0.95), false, 2.0 / maxf(0.4, cam.zoom.x))
	elif tool == "platform":
		draw_rect(Rect2(mp - Vector2(6, 6) / cam.zoom.x, Vector2(12, 12) / cam.zoom.x), Color(1.0, 0.85, 0.4, 0.9))
	var s = selected()
	if s:
		var c: Vector2 = s.com if s is Wiggly else (s.center() if s is Fighter else s.global_position)
		var r: float = (s.radius() * 1.35) if s is Wiggly else ((s.radius() + 12.0) if s is Fighter else (s.bound_radius() + 10.0))
		var tm := Time.get_ticks_msec() / 1000.0
		for i in 12:
			var a := tm * 1.2 + TAU * i / 12.0
			draw_arc(c, r, a, a + 0.3, 6, Color(1.0, 0.85, 0.3, 0.95), 3.0 / maxf(0.4, cam.zoom.x), true)


	if net:
		_draw_friends()


## Friends' cursors, names, emotes, and name tags over Wigglies they play as.
func _draw_friends() -> void:
	var list: Array = net.players_snapshot() if mode == "host" else net.players
	var me: int = 1 if mode == "host" else int(net.my_id)
	var inv := 1.0 / maxf(0.2, cam.zoom.x)
	for p in list:
		var pid := int(p.get("id", 0))
		var col: Color = p.get("col", Color.WHITE)
		var nm := String(p.get("name", "?"))
		var ctrl := int(p.get("ctrl", -1))
		if ctrl >= 0 and pid != me:
			var wg = world.things.get(ctrl)
			if wg is Wiggly:
				_tag(wg.com + Vector2(0, -wg.radius() - 34.0), nm, col, inv, true)
		var cur = p.get("cur")
		var emo := int(p.get("emo", -1))
		if pid == me:
			cur = local_pos()
		elif cur == null:
			continue
		var c: Vector2 = cur
		if pid != me:
			draw_set_transform(c, 0.0, Vector2(inv, inv))
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(0, 22), Vector2(6, 16), Vector2(15, 16)]), col)
			draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(0, 22), Vector2(6, 16), Vector2(15, 16), Vector2.ZERO]), Color(0, 0, 0, 0.7), 1.5, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_tag(c + Vector2(14, 34) * inv, nm, col, inv, false)
		if emo >= 0 and emo < NetCommon.EMOJI.size():
			var age := float(p.get("age", 0.0))
			draw_set_transform(c + Vector2(10, -24 - age * 28.0) * inv, sin(age * 6.0) * 0.15, Vector2(inv, inv) * (1.0 + 0.3 * maxf(0.0, 0.3 - age) / 0.3))
			draw_string(Art.font, Vector2(-18, 12), NetCommon.EMOJI[emo], HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1, 1, 1, clampf((3.0 - age) / 0.6, 0.0, 1.0)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tag(at: Vector2, txt: String, col: Color, inv: float, centered: bool) -> void:
	var fs := 15
	var w := Art.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
	draw_set_transform(at, 0.0, Vector2(inv, inv))
	var x := -w * 0.5 if centered else 0.0
	draw_colored_polygon(Art.rr(Rect2(x, -12, w, 24), 12.0), col)
	draw_string(Art.font, Vector2(x + 8, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("1d1b3a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var n := int(d.length() / 14.0)
	for i in n:
		if i % 2 == 0:
			draw_line(a + d * (float(i) / n), a + d * (float(i + 1) / n), col, 3.0 / maxf(0.4, cam.zoom.x), true)

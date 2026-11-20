extends CanvasLayer
## The 3D Battle HUD, built with the game's UI kit: top bar (home, Fight /
## Pause, slow-mo, clear, maps, team counts, help), left palette (tabs, team
## and personality pickers, item buttons), tool dock, unit inspector,
## winner banner, toasts and the nuke's white flash.

const TOOLS := [
	{"id": "place", "icon": "➕", "name": "Place", "key": "1", "tip": "Click the ground to place. Drag for a line. Shift-drag for a block."},
	{"id": "select", "icon": "🔍", "name": "Select", "key": "2", "tip": "Click a fighter to see it and change its team or mood."},
	{"id": "grab", "icon": "✋", "name": "Grab", "key": "3", "tip": "Grab anything and fling it!"},
	{"id": "erase", "icon": "🧽", "name": "Eraser", "key": "4", "tip": "Click or drag over things to remove them."},
]

var battle = null
var root: Control
var play_btn: Button
var slow_btn: Button
var map_btn: Button
var c4_btn: Button
var counts_box: HBoxContainer
var counts_dirty := true
var cat := "people"
var cat_btns := {}
var grid: GridContainer
var palette: Control
var box_btn: Button
var rules_btn: Button
var play_lbl: Label
var crosshair: Control
var reset_btn: Button
var net_btn: Button
var hist_btn: Button
var surprise_btn: Button
var saves_btn: Button
var clear_btn: Button
var net_lbl: Label
var _finder: LanFinder = null
var again_btn: Button
var dock_holder: Control
var _fp_hidden := false
var _fp_palette := false
var item_btns := {}
var team_btns := {}
var team_box: VBoxContainer
var pers_btns := {}
var size_btns := {}
const SIZES := [[0.5, "🐜 Tiny"], [1.0, "Normal"], [1.6, "Big"], [2.5, "🦖 Huge"]]
var pers_label: Label
var hint_label: Label
var tool_btns := {}
var inspect: PanelContainer
var insp_title: Label
var insp_info: Label
var insp_hp: ProgressBar
var insp_team := {}
var insp_pers := {}
var banner_lbl: Label
var toasts: VBoxContainer
var flash_rect: ColorRect
var popup: Control = null
var help: PanelContainer = null
var _last_us := 0
var _banner_t := -1.0
var _flash := 0.0
var _count_t := 0.0
var _insp_t := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_build_top()
	_build_palette()
	_build_dock()
	_build_inspect()
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-330, 80)
	toasts.custom_minimum_size = Vector2(660, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)
	banner_lbl = Label.new()
	banner_lbl.add_theme_font_size_override("font_size", 64)
	banner_lbl.add_theme_color_override("font_color", UI.ACCENT)
	banner_lbl.add_theme_constant_override("outline_size", 24)
	banner_lbl.add_theme_color_override("font_outline_color", Color("2a1f5a"))
	banner_lbl.add_theme_constant_override("shadow_offset_y", 6)
	banner_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_lbl.position = Vector2(-500, 120)
	banner_lbl.custom_minimum_size = Vector2(1000, 0)
	banner_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_lbl.visible = false
	banner_lbl.pivot_offset = Vector2(500, 40)
	again_btn = UI.button("⏮  Play it again", Color("2f9e4f"), 22, 260)
	again_btn.tooltip_text = "Everyone goes back to where they started"
	again_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	again_btn.position = Vector2(-130, 215)
	again_btn.visible = false
	again_btn.pressed.connect(func(): battle.reset_battle())
	root.add_child(banner_lbl)
	root.add_child(again_btn)
	play_lbl = UI.label("", 17)
	play_lbl.add_theme_constant_override("outline_size", 10)
	play_lbl.add_theme_color_override("font_outline_color", Color("2a1f5a"))
	play_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	play_lbl.position = Vector2(-300, 80)
	play_lbl.custom_minimum_size = Vector2(600, 0)
	play_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_lbl.visible = false
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	root.add_child(crosshair)
	root.add_child(play_lbl)
	_last_us = Time.get_ticks_usec()
	refresh_palette()
	refresh_tools()


# ------------------------------------------------------------------- top
func _pill(parent: Control) -> HBoxContainer:
	var p := UI.panel(18)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	parent.add_child(p)
	return h


func _btn(parent: Control, txt: String, tip: String, fn: Callable, w := 0.0, col := UI.PANEL2, fs := 18) -> Button:
	var b := UI.button(txt, col, fs, w)
	b.tooltip_text = tip
	b.pressed.connect(func():
		battle.snd("click", null, 0.4)
		fn.call())
	parent.add_child(b)
	return b


func _build_top() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var g1 := _pill(top)
	_btn(g1, "🏠", "Back to the title screen", func(): battle.leave(), 52)
	var title := UI.title("⚔️ 3D Battle", 22)
	title.custom_minimum_size.x = 150
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g1.add_child(title)
	box_btn = _btn(g1, "🧸", "Show or hide the Toy Box [Tab]", toggle_palette, 52)
	var g2 := _pill(top)
	play_btn = _btn(g2, "▶  Fight!", "Start the battle / pause it [Space]", func(): battle.toggle_play(), 150, Color("2f9e4f"), 20)
	reset_btn = _btn(g2, "⏮", "Reset: put everyone back where they were when you pressed Fight!, to play the same battle again", func(): battle.reset_battle(), 52)
	slow_btn = _btn(g2, "🐢", "Slow motion [G]", toggle_slowmo, 52)
	clear_btn = _btn(g2, "🧹 Clear", "Clear the battlefield", _show_clear_menu)
	map_btn = _btn(g2, "🗺️ Map", "Pick a battlefield", _show_map_menu)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var g3 := _pill(top)
	net_lbl = UI.label("", 16)
	net_lbl.visible = false
	g3.add_child(net_lbl)
	counts_box = HBoxContainer.new()
	counts_box.add_theme_constant_override("separation", 6)
	g3.add_child(counts_box)
	var g4 := _pill(top)
	net_btn = _btn(g4, "👥", "Play together with friends on the same Wi-Fi", _show_net, 52)
	hist_btn = _btn(g4, "📜", "History: set up a famous battle from long ago", _show_history, 52)
	surprise_btn = _btn(g4, "🎲", "Surprise Battle! A random battlefield and armies", func(): B3Surprise.run(battle), 52)
	saves_btn = _btn(g4, "💾", "Save or load a battle", _show_saves, 52)
	rules_btn = _btn(g4, "⚙️", "Battle Rules: gravity, explosions, night, weather and more", _show_rules, 52)
	_btn(g4, "❓", "How to play [H]", toggle_help, 52)


func refresh() -> void:
	if battle == null:
		return
	if not battle.fighting:
		play_btn.text = "▶  Fight!"
		_style(play_btn, Color("2f9e4f"))
	elif battle.paused:
		play_btn.text = "▶  Resume"
		_style(play_btn, Color("2f9e4f"))
	else:
		play_btn.text = "⏸  Pause"
		_style(play_btn, UI.PANEL2)
	UI.set_on(slow_btn, battle.slowmo)
	reset_btn.disabled = (battle.start_layout as Dictionary).is_empty()
	var md: Dictionary = B3Defs.MAPS[battle.map_id]
	map_btn.text = "%s %s" % [md.icon, md.name]
	counts_dirty = true
	refresh_c4()
	_refresh_rules_btn()


# ------------------------------------------------------------ 👥 together
## Lights the 👥 button, shows who's playing, and greys out what only the host can do.
func refresh_net() -> void:
	var n = battle.net
	var on: bool = n != null and n.mode != ""
	UI.set_on(net_btn, on)
	var friend: bool = battle.puppet
	for b in [map_btn, clear_btn, hist_btn, surprise_btn, saves_btn, rules_btn]:
		(b as Button).disabled = friend
		(b as Button).tooltip_text = (b as Button).tooltip_text.split("\n")[0] + ("\n(Only the host can do this)" if friend else "")
	net_lbl.visible = on
	if on:
		net_lbl.text = "👥 %d" % maxi(1, n.player_count())
		var names: Array = []
		for p in n.players:
			names.append(String(p.get("name", "?")))
		net_lbl.tooltip_text = "Playing together: " + ", ".join(names)
	if popup and is_instance_valid(popup) and popup.has_meta("net"):
		_show_net()


func _show_net() -> void:
	var v := _popup_panel("👥 Play together")
	popup.set_meta("net", true)
	popup.custom_minimum_size = Vector2(520, 0)     # grows evenly both ways, so it stays centred
	var n = battle.net
	var mode: String = n.mode if n else ""
	if mode == "host" or mode == "client":
		var head := ("👥 You're sharing this battle! Friends join from their own 3D Battle: 👥 → pick your name."
			if mode == "host" else "👥 You're in %s's battle. Place things, press Fight!, and pick a fighter to play." % n.host_name)
		var hl := UI.label(head, 16)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size.x = 480
		v.add_child(hl)
		if mode == "host":
			v.add_child(UI.label("Your address: " + B3Net.address_text(), 15, UI.MUTED))
		elif not n.connected:
			v.add_child(UI.label(n.status, 15, UI.MUTED))
		v.add_child(UI.title("Players", 18))
		for p in n.players:
			var pd: Dictionary = p
			var who := String(pd.get("name", "?"))
			var what := ""
			var uid := int(pd.get("uid", 0))
			if uid != 0:
				var u = n._unit(uid) if mode == "host" else n.puppets.get(uid)
				if u is B3Unit and is_instance_valid(u):
					what = "  🎮 playing the %s %s" % [(u as B3Unit).def.icon, (u as B3Unit).def.name]
			var l := UI.label(("🏠 " if int(pd.get("id", 0)) == 1 else "🙂 ") + who + what, 17)
			l.add_theme_color_override("font_color", pd.get("col", UI.TEXT) if pd.get("col") is Color else UI.TEXT)
			v.add_child(l)
		var stop := UI.button("Stop sharing" if mode == "host" else "👋 Leave the battle", UI.PANEL2, 17, 240)
		stop.pressed.connect(func():
			close_top()
			battle.stop_net())
		v.add_child(stop)
		return
	var intro := UI.label("Play the same battle with friends on the same Wi-Fi. Everyone needs Wiggle Works on their computer.", 16, UI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 480
	v.add_child(intro)
	var hb := UI.button("🏠  Host: friends join my battle", Color("2f9e4f"), 19)
	hb.pressed.connect(func():
		if battle.start_hosting():
			_show_net())
	v.add_child(hb)
	v.add_child(UI.title("Join a friend", 18))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	if _finder == null:
		_finder = LanFinder.new()
		_finder.want = B3Net.GAME_ID
		add_child(_finder)
		_finder.games_changed.connect(func():
			if popup and is_instance_valid(popup) and popup.has_meta("net") and (battle.net == null or battle.net.mode == ""):
				_show_net())
	if not _finder.listening:
		_finder.start()
	if _finder.games.is_empty():
		list.add_child(UI.label("Looking for battles on this Wi-Fi...", 15, UI.MUTED))
	for ip in _finder.games:
		var g: Dictionary = _finder.games[ip]
		var addr := String(ip)
		var jb := UI.button("⚔️  %s's battle  ·  %s  ·  👥 %d" % [g.get("name", "?"), g.get("world", ""), int(g.get("players", 1))], UI.PANEL2, 17)
		jb.pressed.connect(func():
			close_top()
			battle.join_game(addr))
		list.add_child(jb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var ip_box := LineEdit.new()
	ip_box.placeholder_text = "or type their address, like 192.168.1.20"
	ip_box.custom_minimum_size = Vector2(360, 40)
	row.add_child(ip_box)
	var go := UI.button("Join", Color("2f9e4f"), 17, 90)
	go.pressed.connect(func():
		var ip := ip_box.text.strip_edges()
		if ip != "":
			close_top()
			battle.join_game(ip))
	row.add_child(go)


func toggle_slowmo() -> void:
	if battle.puppet and battle.net:
		battle.net.send_cmd({"c": "slowmo"})
	else:
		battle.set_slowmo(not battle.slowmo)


func _style(b: Button, col: Color) -> void:
	b.add_theme_stylebox_override("normal", UI.box(col, 14, 2, col.lightened(0.18), 12))
	b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.12), 14, 2, col.lightened(0.35), 12))


func _refresh_counts() -> void:
	for c in counts_box.get_children():
		c.queue_free()
	var counts: Dictionary = battle.team_counts()
	if counts.is_empty():
		var l := UI.label("Nobody left!" if battle.kos > 0 else "No fighters yet", 16, UI.MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size.y = 40
		counts_box.add_child(l)
		return
	for t in B3Defs.TEAM_ORDER:
		if not counts.has(t):
			continue
		var col := B3Defs.team_col(t)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.box(col.darkened(0.15), 12, 2, col.lightened(0.3), 10))
		var l := UI.label("%s %d" % ["🐾" if t == "wild" else "", int(counts[t])], 19, Color.WHITE)
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
		l.custom_minimum_size = Vector2(46, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(l)
		pc.tooltip_text = "%s team" % String(B3Defs.TEAM[t].name)
		counts_box.add_child(pc)


# --------------------------------------------------------------- palette
func _build_palette() -> void:
	var p := UI.panel(20)
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 10
	p.offset_top = 76
	p.offset_bottom = -10
	p.offset_right = 10 + 292
	root.add_child(p)
	palette = p
	if box_btn:
		UI.set_on(box_btn, true)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var tabs := GridContainer.new()
	tabs.columns = 3
	tabs.add_theme_constant_override("h_separation", 5)
	tabs.add_theme_constant_override("v_separation", 5)
	v.add_child(tabs)
	for c in B3Defs.CATS:
		var id := String(c.id)
		var b := UI.button("%s %s" % [c.icon, c.name], UI.PANEL2, 15, 86)
		b.custom_minimum_size.y = 40
		b.pressed.connect(func():
			battle.snd("tick", null, 0.4)
			set_cat(id))
		tabs.add_child(b)
		cat_btns[id] = b
	team_box = VBoxContainer.new()
	team_box.add_theme_constant_override("separation", 4)
	v.add_child(team_box)
	var tl := UI.label("Team", 14, UI.MUTED)
	team_box.add_child(tl)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 5)
	team_box.add_child(tr)
	for t in B3Defs.TEAM_ORDER:
		var tid := String(t)
		var col := B3Defs.team_col(tid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.text = "🐾" if tid == "wild" else ""
		b.add_theme_font_size_override("font_size", 18)
		b.tooltip_text = "%s team%s" % [B3Defs.TEAM[tid].name, " (fights everyone!)" if tid == "wild" else ""]
		b.pressed.connect(func():
			battle.snd("tick", null, 0.4)
			battle.tools.set_team(tid))
		tr.add_child(b)
		team_btns[tid] = b
	var pl := HBoxContainer.new()
	team_box.add_child(pl)
	pl.add_child(UI.label("Mood", 14, UI.MUTED))
	pers_label = UI.label("", 14, UI.ACCENT)
	pers_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.add_child(pers_label)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 3)
	team_box.add_child(pr)
	for pid in B3Defs.PERS_ORDER:
		var ps := String(pid)
		var d: Dictionary = B3Defs.PERS[ps]
		var b := UI.button(String(d.icon), UI.PANEL2, 17, 36)
		b.custom_minimum_size.y = 38
		b.tooltip_text = "%s: %s" % [d.name, d.tip]
		b.pressed.connect(func():
			battle.snd("tick", null, 0.4)
			battle.tools.pers = ps
			refresh_palette())
		pr.add_child(b)
		pers_btns[ps] = b
	var zr := HBoxContainer.new()
	zr.add_theme_constant_override("separation", 3)
	team_box.add_child(zr)
	var zl := UI.label("Size", 14, UI.MUTED)
	zl.custom_minimum_size.x = 34
	zr.add_child(zl)
	for sz in SIZES:
		var k := float(sz[0])
		var b := UI.button(String(sz[1]), UI.PANEL2, 13)
		b.custom_minimum_size = Vector2(56, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Place fighters at this size (vehicles stay normal)"
		b.pressed.connect(func():
			battle.snd("tick", null, 0.4)
			battle.tools.place_size = k
			refresh_palette())
		zr.add_child(b)
		size_btns[k] = b
	hint_label = UI.label("", 14, UI.MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size.x = 260
	v.add_child(hint_label)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	set_cat("people")


func set_cat(c: String) -> void:
	cat = c
	for ch in grid.get_children():
		ch.queue_free()
	item_btns.clear()
	var ids: Array = []
	match c:
		"people", "animals", "dinos", "vehicles", "history":
			ids = B3Defs.UNIT_ORDER[c]
		"booms":
			ids = B3Defs.BOOM_ORDER
		"hazards":
			ids = B3Defs.HAZARD_ORDER
		"build":
			ids = B3Defs.STRUCT_ORDER
	for id in ids:
		var sid := String(id)
		var d: Dictionary = {}
		for table in [B3Defs.UNITS, B3Defs.BOOMS, B3Defs.HAZARDS, B3Defs.STRUCTS]:
			if table.has(sid):
				d = table[sid]
		var b := UI.button("", UI.PANEL2, 14, 132)
		b.custom_minimum_size.y = 70
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", -2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var ic := UI.label(String(d.icon), 28)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ic)
		var nm := UI.label(String(d.name), 14)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.name = "Name"
		col.add_child(nm)
		var tip := String(d.get("tip", ""))
		if B3Defs.UNITS.has(sid):
			var w := B3Defs.weapon(String(d.weapon))
			tip = "%s  •  ❤️ %d  •  %s %s" % [d.name, int(d.hp), B3Defs.PERS[String(d.pers)].icon, B3Defs.PERS[String(d.pers)].name]
			if String(w.type) != "melee":
				tip += "  •  🎯 range %d" % int(float(w.range))
		b.tooltip_text = tip
		b.pressed.connect(func():
			battle.snd("tick", null, 0.5)
			battle.tools.choose(sid))
		grid.add_child(b)
		item_btns[sid] = b
	if battle and battle.tools:
		if c == "vehicles" and not battle.tools.team_by_cat.has(c):
			battle.tools.team_by_cat[c] = "red"     # vehicles remember their own team
		var first := String(ids[0]) if not ids.is_empty() else ""
		if B3Defs.item_cat(battle.tools.place_id) != c and first != "":
			battle.tools.choose(first)
	refresh_palette()


func refresh_palette() -> void:
	if battle == null or battle.tools == null:
		return
	var tl = battle.tools
	for id in cat_btns:
		UI.set_on(cat_btns[id], id == cat)
	for id in item_btns:
		var on: bool = id == tl.place_id and tl.tool == "place"
		UI.set_on(item_btns[id], on)
		var nm: Label = item_btns[id].get_child(0).get_node("Name")
		nm.add_theme_color_override("font_color", Color("1d1b3a") if on else UI.TEXT)
	var units := cat == "people" or cat == "animals" or cat == "dinos" or cat == "vehicles"
	team_box.visible = units
	for t in team_btns:
		var col := B3Defs.team_col(t)
		var on: bool = t == tl.team
		var b: Button = team_btns[t]
		b.add_theme_stylebox_override("normal", UI.box(col, 20, 4 if on else 2, Color.WHITE if on else col.darkened(0.35), 0))
		b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.15), 20, 4 if on else 2, Color.WHITE, 0))
		b.add_theme_stylebox_override("pressed", UI.box(col, 20, 4, Color.WHITE, 0))
		b.scale = Vector2.ONE
	for p in pers_btns:
		UI.set_on(pers_btns[p], p == tl.pers)
	for k in size_btns:
		UI.set_on(size_btns[k], absf(float(k) - float(tl.place_size)) < 0.01)
	var pd: Dictionary = B3Defs.PERS[String(tl.pers)]
	pers_label.text = "%s %s" % [pd.icon, pd.name]
	match cat:
		"booms":
			hint_label.text = "Click the ground to drop it! Press 💥 Detonate (B) to set off all the C4."
		"hazards":
			hint_label.text = "Click to pour a pool. Drag to make it bigger. Fighters steer around it… mostly!"
		"build":
			hint_label.text = "Click to build. Drag to aim walls, ramps and bridges. R turns it."
		_:
			hint_label.text = "Click to place one, drag for a line, Shift-drag for a big block."


# ------------------------------------------------------------------ dock
func _build_dock() -> void:
	var holder := HBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_bottom = -10
	holder.offset_left = 150
	holder.offset_right = 150
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(holder)
	dock_holder = holder
	var dp := UI.panel(20)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 6)
	dp.add_child(dock)
	holder.add_child(dp)
	for t in TOOLS:
		var tid := String(t.id)
		var b := _dock_btn(dock, String(t.icon), String(t.name), "%s [%s]\n%s" % [t.name, t.key, t.tip])
		b.pressed.connect(func():
			battle.snd("click", null, 0.4)
			battle.tools.set_tool(tid))
		tool_btns[tid] = b
	var sep := VSeparator.new()
	dock.add_child(sep)
	c4_btn = _dock_btn(dock, "💥", "Detonate", "Detonate all C4 [B]")
	c4_btn.pressed.connect(func(): battle.detonate_c4())
	var turn := _dock_btn(dock, "🔄", "Turn", "Turn the camera [Q / E]")
	turn.pressed.connect(func(): battle.cam.rotate_view(1.0))


func _dock_btn(dock: HBoxContainer, icon: String, nm_s: String, tip: String) -> Button:
	var b := UI.button("", UI.PANEL2, 15, 78)
	b.custom_minimum_size.y = 70
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var ic := UI.label(icon, 28)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ic)
	var nm := UI.label(nm_s, 13)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.name = "Name"
	col.add_child(nm)
	b.tooltip_text = tip
	dock.add_child(b)
	return b


func refresh_tools() -> void:
	if battle == null or battle.tools == null:
		return
	for id in tool_btns:
		var on: bool = id == battle.tools.tool
		UI.set_on(tool_btns[id], on)
		var nm: Label = tool_btns[id].get_child(0).get_node("Name")
		nm.add_theme_color_override("font_color", Color("1d1b3a") if on else UI.TEXT)
	refresh_palette()


func refresh_c4() -> void:
	if c4_btn == null or battle == null:
		return
	var n: int = battle.c4_count()
	var nm: Label = c4_btn.get_child(0).get_node("Name")
	nm.text = "Detonate" if n == 0 else "Boom! (%d)" % n
	c4_btn.modulate = Color(1, 1, 1, 1) if n > 0 else Color(1, 1, 1, 0.6)


# --------------------------------------------------------------- inspect
func _build_inspect() -> void:
	inspect = UI.panel(20)
	inspect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	inspect.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspect.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inspect.offset_right = -10
	inspect.offset_bottom = -96
	inspect.custom_minimum_size = Vector2(300, 0)
	inspect.visible = false
	root.add_child(inspect)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	inspect.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	insp_title = UI.title("", 22)
	insp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(insp_title)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.pressed.connect(func(): battle.tools.select(null))
	h.add_child(x)
	insp_hp = ProgressBar.new()
	insp_hp.custom_minimum_size = Vector2(270, 20)
	insp_hp.show_percentage = false
	insp_hp.add_theme_stylebox_override("background", UI.box(Color("1d1b3a"), 10, 0, UI.LINE, 0))
	insp_hp.add_theme_stylebox_override("fill", UI.box(UI.GOOD, 10, 0, UI.LINE, 0))
	v.add_child(insp_hp)
	insp_info = UI.label("", 15, UI.MUTED)
	v.add_child(insp_info)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 4)
	v.add_child(tr)
	for t in B3Defs.TEAM_ORDER:
		var tid := String(t)
		var col := B3Defs.team_col(tid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.text = "🐾" if tid == "wild" else ""
		b.tooltip_text = "Join the %s team" % B3Defs.TEAM[tid].name
		b.add_theme_stylebox_override("normal", UI.box(col, 16, 2, col.darkened(0.35), 0))
		b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.15), 16, 3, Color.WHITE, 0))
		b.add_theme_stylebox_override("pressed", UI.box(col, 16, 3, Color.WHITE, 0))
		b.pressed.connect(func():
			var u: B3Unit = battle.tools.selected
			if u and is_instance_valid(u):
				if not _for_host(u, {"c": "team", "t": tid}):
					u.set_team(tid)
				battle.snd("tick", null, 0.5)
				counts_dirty = true
				show_inspect(u))
		tr.add_child(b)
		insp_team[tid] = b
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 3)
	v.add_child(pr)
	for pid in B3Defs.PERS_ORDER:
		var ps := String(pid)
		var d: Dictionary = B3Defs.PERS[ps]
		var b := UI.button(String(d.icon), UI.PANEL2, 16, 36)
		b.tooltip_text = "%s: %s" % [d.name, d.tip]
		b.pressed.connect(func():
			var u: B3Unit = battle.tools.selected
			if u and is_instance_valid(u):
				if not _for_host(u, {"c": "mood", "p": ps}):
					u.set_personality(ps)
				battle.snd("tick", null, 0.5)
				show_inspect(u))
		pr.add_child(b)
		insp_pers[ps] = b
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	v.add_child(ar)
	var launch := UI.button("🚀 Launch!", Color("c0392b").darkened(0.1), 16)
	launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			battle.snd("whoosh", u.position, 1.0)
			if not _for_host(u, {"c": "launch"}):
				u.knock_down(Vector3(randf_range(-4, 4), 18.0, randf_range(-4, 4))))
	ar.add_child(launch)
	var heal := UI.button("💚 Heal", Color("2f9e4f"), 16)
	heal.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			if _for_host(u, {"c": "heal"}):
				return
			u.hp = u.max_hp
			battle.fx.heal(u.center() + Vector3(0, 0.6, 0))
			battle.snd("heal", u.position, 0.8))
	ar.add_child(heal)
	var rm := UI.button("🗑️", UI.PANEL2, 16, 44)
	rm.tooltip_text = "Remove [Delete]"
	rm.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not _for_host(u, {"c": "erase"}):
			battle.remove_unit(u)
		battle.tools.select(null))
	ar.add_child(rm)
	var pl := HBoxContainer.new()
	pl.add_theme_constant_override("separation", 6)
	v.add_child(pl)
	var play := UI.button("🎮 Play as me!", Color("8e44ad"), 17)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.tooltip_text = "Control this fighter yourself [P]"
	play.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			battle.tools.play_as(u))
	pl.add_child(play)
	var fol := UI.button("🎥 Follow", UI.PANEL2, 17)
	fol.tooltip_text = "Keep the camera on this fighter [F]"
	fol.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			battle.tools.follow(u))
	pl.add_child(fol)


## In a friend's battle, buttons that change a fighter ask the host to do it.
func _for_host(u: Node, c: Dictionary) -> bool:
	if not battle.puppet or battle.net == null:
		return false
	c["nid"] = int(u.get_meta("nid", 0))
	battle.net.send_cmd(c)
	return true


func show_inspect(u: B3Unit) -> void:
	if u == null or not is_instance_valid(u):
		inspect.visible = false
		return
	inspect.visible = true
	var d := u.def
	insp_title.text = "%s %s" % [d.icon, d.name]
	_update_inspect(u)
	for t in insp_team:
		var col := B3Defs.team_col(t)
		var on: bool = t == u.team
		insp_team[t].add_theme_stylebox_override("normal", UI.box(col, 16, 4 if on else 2, Color.WHITE if on else col.darkened(0.35), 0))
	for p in insp_pers:
		UI.set_on(insp_pers[p], p == u.pers_choice)


func _update_inspect(u: B3Unit) -> void:
	insp_hp.max_value = u.max_hp
	insp_hp.value = maxf(0.0, u.hp)
	var pd: Dictionary = B3Defs.PERS[u.pers]
	var state := "😵 Knocked down!" if u.down else ("🏃 Running away!" if u.fleeing else ("🎉 Cheering!" if u.cheer else ""))
	var w := u.wpn
	var wtxt := "melee" if String(w.type) == "melee" else "range %d" % int(float(w.range))
	insp_info.text = "❤️ %d / %d   •   %s %s\n⚔️ %s   •   KOs: %d   %s" % [int(maxf(0.0, u.hp)), int(u.max_hp), pd.icon, pd.name, wtxt, u.kills, state]


# ------------------------------------------------------------- popups
func _popup_panel(title: String) -> VBoxContainer:
	close_top()
	var p := UI.panel(22)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.position = Vector2(-200, 80)
	p.custom_minimum_size = Vector2(400, 0)
	root.add_child(p)
	popup = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := UI.title(title, 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.pressed.connect(close_top)
	h.add_child(x)
	return v


func _show_map_menu() -> void:
	var v := _popup_panel("🗺️ Pick a battlefield")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	for id in B3Defs.MAP_ORDER:
		var mid := String(id)
		var d: Dictionary = B3Defs.MAPS[mid]
		var b := UI.button("%s  %s" % [d.icon, d.name], (d.ground as Color).darkened(0.35), 20, 180)
		b.custom_minimum_size.y = 58
		if mid == battle.map_id:
			UI.set_on(b, true)
		b.pressed.connect(func():
			close_top()
			battle.snd("whoosh", null, 0.6)
			battle.load_map(mid))
		g.add_child(b)
	v.add_child(UI.label("Changing the map clears the battlefield.", 14, UI.MUTED))


## The 📜 History battles, oldest first (ones needing a missing unit left out).
static func history_list() -> Array:
	return B3History.available()


static func year_text(y: int) -> String:
	return B3History.year_text(y)


func _show_history() -> void:
	var v := _popup_panel("📜 Battles from history")
	popup.custom_minimum_size = Vector2(760, 0)     # grows evenly both ways, so it stays centred
	v.add_child(UI.label("Real battles from long ago, set up and ready. Press Fight! to watch, or play as one of the soldiers.", 15, UI.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(740, minf(560.0, get_viewport().get_visible_rect().size.y - 230.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var items := history_list()
	if items.is_empty():
		list.add_child(UI.label("(No history battles yet.)", 16, UI.MUTED))
	for e in items:
		var d: Dictionary = e
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(UI.PANEL2, 14, 0, Color.TRANSPARENT, 10))
		list.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		var ic := UI.label(String(d.get("icon", "📜")), 44)
		ic.custom_minimum_size.x = 60
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(ic)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		h.add_child(col)
		col.add_child(UI.label("%s  ·  %s%s" % [d.get("name", "?"), year_text(int(d.get("year", 0))),
			("  ·  " + String(d.place)) if d.has("place") else ""], 19, UI.ACCENT))
		col.add_child(UI.label(String(d.get("sides", "")), 16))
		var bl := UI.label(String(d.get("blurb", "")), 14, UI.MUTED)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size.x = 480
		col.add_child(bl)
		var go := UI.button("▶ Set it up", Color("2f9e4f"), 17, 130)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var hid := String(d.get("id", ""))
		go.pressed.connect(func():
			close_top()
			battle.snd("whoosh", null, 0.6)
			battle.run_history(hid)
			refresh())
		h.add_child(go)


## ⚙️ Battle Rules: one row of choices per rule (see B3Rules).
func _show_rules() -> void:
	var v := _popup_panel("⚙️ Battle Rules")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	for o in B3Rules.OPTIONS:
		var oid := String(o.id)
		var l := UI.label("%s %s" % [o.icon, o.name], 17)
		l.tooltip_text = String(B3Rules.TIPS.get(oid, ""))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.custom_minimum_size.x = 200
		g.add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		g.add_child(row)
		for ch in o.choices:
			var cid := String(ch[0])
			var b := UI.button(String(ch[1]), UI.PANEL2, 15)
			b.custom_minimum_size = Vector2(96, 38)
			b.tooltip_text = String(B3Rules.TIPS.get(oid, ""))
			UI.set_on(b, B3Rules.value(oid) == cid)
			b.pressed.connect(func():
				B3Rules.set_value(oid, cid)
				battle.apply_rules()
				battle.snd("tick", null, 0.6)
				_refresh_rules_btn()
				close_top()
				_show_rules())
			row.add_child(b)
	var reset := UI.button("↺ Back to normal", UI.PANEL2, 16, 220)
	reset.pressed.connect(func():
		B3Rules.reset()
		battle.apply_rules()
		battle.snd("poof", null, 0.5)
		_refresh_rules_btn()
		close_top()
		_show_rules())
	v.add_child(reset)


func _refresh_rules_btn() -> void:
	if rules_btn:
		UI.set_on(rules_btn, not B3Rules.is_default())


## 💾 Three save slots for whole battles (see B3Saves).
func _show_saves() -> void:
	var v := _popup_panel("💾 Saved battles")
	for i in B3Saves.SLOTS:
		var slot := i + 1
		var info := B3Saves.describe(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var l := UI.label("%d.  %s" % [slot, info if info != "" else "(empty)"], 17, UI.TEXT if info != "" else UI.MUTED)
		l.custom_minimum_size.x = 330
		row.add_child(l)
		var sv := UI.button("💾 Save", Color("2f9e4f"), 16, 100)
		sv.pressed.connect(func():
			if B3Saves.save(battle, slot):
				battle.snd("pop", null, 0.7)
				toast("💾 Saved in slot %d!" % slot, false)
			close_top())
		row.add_child(sv)
		var ld := UI.button("📂 Load", UI.PANEL2, 16, 100)
		ld.disabled = info == ""
		ld.pressed.connect(func():
			close_top()
			if B3Saves.load_slot(battle, slot):
				battle.snd("whoosh", null, 0.7)
				toast("📂 Loaded slot %d. Press Fight! to start." % slot, false))
		row.add_child(ld)
	v.add_child(UI.label("Saves where every fighter, building and hazard is, plus the map and rules.\nSaving after Fight! keeps the setup from before the fight, so you can play it again.", 14, UI.MUTED))
	if not (battle.start_layout as Dictionary).is_empty():
		var rs := UI.button("⏮ Reset this battle to the start", UI.PANEL2, 16, 330)
		rs.pressed.connect(func():
			close_top()
			battle.reset_battle())
		v.add_child(rs)


func _show_clear_menu() -> void:
	var v := _popup_panel("🧹 Clear")
	var items := [
		["💤 KO'd fighters & rubble", "Tidy up knocked-out fighters and broken bits", func(): battle.clear_debris()],
		["🧍 All fighters", "Remove every fighter", func(): battle.clear_units()],
		["💥 Everything", "Start over with an empty battlefield", func(): battle.clear_all()],
	]
	for it in items:
		var b := UI.button(String(it[0]), UI.PANEL2, 18, 360)
		b.custom_minimum_size.y = 48
		b.tooltip_text = String(it[1])
		var fn: Callable = it[2]
		b.pressed.connect(func():
			close_top()
			battle.snd("poof", null, 0.7)
			fn.call())
		v.add_child(b)


## Tab: hide the Toy Box to see the whole battlefield, or bring it back.
func toggle_palette() -> void:
	if palette:
		palette.visible = not palette.visible
		if box_btn:
			UI.set_on(box_btn, palette.visible)
		battle.cam.offset_k = 0.17 if palette.visible else 0.0


func toggle_help() -> void:
	if help and is_instance_valid(help):
		help.get_parent().queue_free()
		help = null
		return
	# centred on screen however tall it gets
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	help = UI.panel(22)
	help.custom_minimum_size = Vector2(680, 0)
	cc.add_child(help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	help.add_child(v)
	v.add_child(UI.title("⚔️ How to play 3D Battle", 26))
	for line in [
		"🧍 Pick fighters on the left, choose a team color, click the ground.",
		"↔️ Drag to place a whole line. Shift-drag for a big block.",
		"▶  Press Fight! (Space) and watch them go. 🐢 G for slow motion.",
		"💣 Booms: click to drop. Place C4, then press 💥 Detonate (B).",
		"🌋 Lava and acid: drag to make big pools. 🧱 Build towers and walls.",
		"✋ Grab (3) anything and fling it! 🔍 Select (2) to change a fighter's team or mood.",
		"🎥 Move: WASD / arrows / right-drag.  Zoom: wheel or pinch.  Turn: Q / E.",
		"🧸 Tab hides the Toy Box so you can see the whole battlefield.",
		"🎮 Select a fighter or vehicle and press Play as me (P): WASD, mouse to aim, click to attack, Space to jump.",
		"👀 Press V while playing to look through its eyes (first person). The mouse looks around; Esc stops.",
		"🚁 Drive tanks, jeeps and cars, and fly helicopters and planes the same way.",
		"⏮ Reset puts everyone back where they started, so you can play the same battle again.",
		"📜 History sets up famous battles from long ago.  🎲 Surprise Battle makes a random one.",
		"👥 Play together with friends on the same Wi-Fi: one hosts, the others join.",
		"🎥 Follow (F) keeps the camera on a fighter.  💾 Save your battles.",
		"⚙️ Battle Rules: moon gravity, MEGA explosions, night, rain, snow, screen shake and more.",
		"Moods: ⚔️ Attack  🛡️ Defend  🏹 Ranged  😡 Berserk  😱 Coward  🌼 Peaceful",
	]:
		var l := UI.label(String(line), 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 640
		v.add_child(l)
	var ok := UI.button("Let's go!", Color("2f9e4f"), 20)
	ok.pressed.connect(toggle_help)
	v.add_child(ok)


func close_top() -> bool:
	if popup and is_instance_valid(popup):
		popup.queue_free()
		popup = null
		return true
	if help and is_instance_valid(help):
		help.get_parent().queue_free()
		help = null
		return true
	return false


# --------------------------------------------------------------- feedback
## Shows a message at the top. Shared ones also show on friends' screens
## when you're hosting (👥).
func toast(txt: String, share := true) -> void:
	if share and battle and battle.net and battle.net.is_host():
		battle.net.rec_event(["toast", txt])
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.09, 0.22, 0.88), 16, 2, UI.LINE, 14))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(txt, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_meta("t", 3.5)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		var c := toasts.get_child(0)
		toasts.remove_child(c)
		c.queue_free()


func banner(txt: String, col: Color) -> void:
	banner_lbl.text = txt
	banner_lbl.add_theme_color_override("font_color", col)
	banner_lbl.visible = true
	_banner_t = 0.0
	again_btn.visible = not (battle.start_layout as Dictionary).is_empty()
	refresh()


func hide_banner() -> void:
	banner_lbl.visible = false
	again_btn.visible = false
	_banner_t = -1.0


## The keys line under "You're the ...". Vehicles can describe their own (controls_help(fp)).
func controls_help(u: B3Unit) -> String:
	var fp := B3Player.me.fp
	if u.has_method("controls_help"):
		return String(u.call("controls_help", fp)) + " · V %s · Esc stop" % ("overhead view" if fp else "👀 first person")
	if fp:
		return "WASD move · mouse look · click attack · Space jump · V overhead view · Esc stop"
	return "WASD move · mouse aim · click attack · Space jump · V 👀 first person · Esc stop"


## Shows the crosshair and the right help line for how you're playing.
func refresh_play() -> void:
	var fp := B3Player.active() and B3Player.me.fp
	if crosshair:
		crosshair.visible = fp
	# first person: the Toy Box, tools and fighter card step out of the way
	if fp and not _fp_hidden:
		_fp_hidden = true
		_fp_palette = palette != null and palette.visible
		if _fp_palette:
			toggle_palette()
		if dock_holder:
			dock_holder.visible = false
		if inspect:
			inspect.visible = false
	elif not fp and _fp_hidden:
		_fp_hidden = false
		if _fp_palette and palette and not palette.visible:
			toggle_palette()
		if dock_holder:
			dock_holder.visible = true


func flash(a: float) -> void:
	_flash = maxf(_flash, a)


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	if play_lbl:
		var pu := B3Player.unit
		play_lbl.visible = B3Player.active()
		if play_lbl.visible:
			var hpk := clampf(pu.hp / maxf(1.0, pu.max_hp), 0.0, 1.0)
			play_lbl.text = "🎮 You're the %s %s   ❤️ %d%%%s\n%s" % [pu.def.icon, pu.def.name,
				int(round(hpk * 100.0)), "   💫 Knocked down!" if pu.down else "", controls_help(pu)]
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 0.7)
		flash_rect.color = Color(1, 1, 0.95, clampf(_flash * 1.3, 0.0, 1.0))
	elif flash_rect.color.a > 0.0:
		flash_rect.color.a = 0.0
	if _banner_t >= 0.0:
		_banner_t += dt
		var s := 1.0 + 0.35 * exp(-_banner_t * 5.0) * sin(_banner_t * 18.0)
		banner_lbl.scale = Vector2(s, s)
		banner_lbl.rotation = sin(_banner_t * 2.0) * 0.02
	for c in toasts.get_children():
		var t: float = c.get_meta("t", 3.0)
		t -= dt
		c.set_meta("t", t)
		(c as Control).modulate.a = clampf(t / 0.5, 0.0, 1.0)
		if t <= 0.0:
			c.queue_free()
	_count_t -= dt
	if counts_dirty and _count_t <= 0.0:
		_count_t = 0.3
		counts_dirty = false
		_refresh_counts()
	_insp_t -= dt
	if inspect.visible and _insp_t <= 0.0:
		_insp_t = 0.15
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			_update_inspect(u)
		else:
			inspect.visible = false


## The first-person crosshair: a small ring with a dot, white with a dark edge.
class Crosshair extends Control:
	var hit_t := 0.0

	func _process(dt: float) -> void:
		if hit_t > 0.0:
			hit_t = maxf(0.0, hit_t - dt)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := 11.0
		draw_arc(c, r, 0, TAU, 32, Color(0, 0, 0, 0.55), 4.0, true)
		draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.0, true)
		draw_circle(c, 2.6, Color(0, 0, 0, 0.6))
		draw_circle(c, 1.8, Color.WHITE)
		if hit_t > 0.0:
			var a := clampf(hit_t / 0.15, 0.0, 1.0)
			for k in 4:
				var d := Vector2.from_angle(PI * 0.25 + k * PI * 0.5)
				draw_line(c + d * 14.0, c + d * 22.0, Color(1, 0.9, 0.3, a), 3.0, true)

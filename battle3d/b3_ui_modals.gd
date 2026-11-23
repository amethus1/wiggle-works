class_name B3UIModals
extends RefCounted
## The 3D Battle HUD's pop-ups (for B3UI, its `modals`): 👥 Play together,
## 🗺️ the map menu, 📜 Pick a battle (History, 🎯 Ready-made and 🧩
## Puzzles), the 🧩 ⭐ card, ⚙️ Battle Rules, 💾 saves, 🧹 Clear, "Are you
## sure?", ❓ How to play, 🔧 Settings and the 🏆 scoreboard card. B3UI
## passes its _show_history, confirm, close_top... on to these. The widgets
## they leave on screen (popup, help, score_card, puzzle_card...) stay on
## B3UI, where the rest of the HUD and the tests look at them.

var ui = null                     # the HUD (b3_ui.gd)
var battle:
	get:
		return ui.battle
var _finder: LanFinder = null     # 👥 looks for battles on this Wi-Fi


func _init(hud) -> void:
	ui = hud


# ------------------------------------------------------------ 👥 together
func show_net() -> void:
	var v := popup_panel("👥 Play together")
	ui.popup.set_meta("net", true)
	ui.popup.custom_minimum_size = Vector2(520, 0)     # grows evenly both ways, so it stays centred
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
			# 🔒 the host decides whether friends may change the battle (B3Net.allow_changes)
			var lock := CheckBox.new()
			lock.text = "Friends can place, erase, blow things up and ⏮ reset"
			lock.button_pressed = n.allow_changes
			lock.focus_mode = Control.FOCUS_NONE
			lock.add_theme_font_size_override("font_size", 15)
			lock.toggled.connect(func(on: bool): n.allow_changes = on)
			v.add_child(lock)
			ui.set_meta("net_lock", lock)
		elif not n.connected:
			v.add_child(UI.label(n.status, 15, UI.MUTED))
		elif n.host_locked:
			v.add_child(UI.label("🔒 The host has locked the battle: you can still pick a fighter and play.", 15, UI.MUTED))
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
			show_net())
	v.add_child(hb)
	v.add_child(UI.title("Join a friend", 18))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	if _finder == null:
		_finder = LanFinder.new()
		_finder.want = B3Net.GAME_ID
		ui.add_child(_finder)
		_finder.games_changed.connect(func():
			if ui.popup and is_instance_valid(ui.popup) and ui.popup.has_meta("net") and (battle.net == null or battle.net.mode == ""):
				show_net())
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


# ------------------------------------------------------------- popups
func popup_panel(title: String) -> VBoxContainer:
	close_top()
	var shade := _shade()
	var p := UI.panel(22)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# no width of its own at the middle of the screen: it grows evenly both
	# ways to fit what's inside, so it's always centred
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = 80
	p.custom_minimum_size = Vector2(400, 0)
	shade.add_child(p)
	ui.popup = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := UI.title(title, 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.tooltip_text = "Close [Esc]"
	x.set_meta("no_first", true)
	x.pressed.connect(close_top)
	h.add_child(x)
	return v


## The dimmed backdrop behind a pop-up: the battlefield can't be clicked
## through it (no fighters placed by accident), and a click on it closes the
## pop-up. Keys and a gamepad work on the pop-up's buttons.
func _shade() -> ColorRect:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_meta("shade", true)      # (its name can change while an old one is on its way out)
	shade.color = Color(0.05, 0.04, 0.12, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.focus_on(shade)
	shade.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			close_top())
	ui.root.add_child(shade)      # (on top of everything, bars too)
	return shade


## "Are you sure?" before something you can't take back. `yes_txt` does
## `fn`; the other button (or a click outside) keeps everything as it is.
func confirm(title: String, msg: String, yes_txt: String, fn: Callable) -> void:
	var v := popup_panel(title)
	ui.popup.set_meta("confirm", true)
	var l := UI.label(msg, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var yes := UI.button(yes_txt, UI.BAD.darkened(0.25), 19, 190)
	yes.name = "Yes"
	yes.custom_minimum_size.y = 50
	yes.pressed.connect(func():
		close_top()
		fn.call())
	row.add_child(yes)
	var no := UI.button("✋ No, keep it", Color("2f9e4f"), 19, 190)
	no.name = "No"
	no.custom_minimum_size.y = 50
	no.pressed.connect(close_top)
	row.add_child(no)


## True if there's an army (or anything you built) on the field to lose.
func _field_busy() -> bool:
	for u: B3Unit in battle.units:
		if is_instance_valid(u) and not u.dead:
			return true
	return not (battle.structs as Array).is_empty()


func show_map_menu() -> void:
	var v := popup_panel("🗺️ Pick a battlefield")
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
		var go := func():
			battle.snd("whoosh", null, 0.6)
			battle.load_map(mid)
		b.pressed.connect(func():
			close_top()
			if _field_busy():
				confirm("🗺️ %s %s?" % [d.icon, d.name], "A new map clears the battlefield: your army and buildings will be gone!", "🗺️ Yes, new map", go)
			else:
				go.call())
		g.add_child(b)
	v.add_child(UI.label("Changing the map clears the battlefield.", 14, UI.MUTED))


## The 📜 History battles, oldest first (ones needing a missing unit left out).
static func history_list() -> Array:
	return B3History.available()


static func year_text(y: int) -> String:
	return B3History.year_text(y)


## 📜 Pick a battle: two tabs, 📜 History (real battles from long ago) and
## 🎯 Ready-made (B3Scenarios.MENU). `tab` "" opens the one used last.
func show_history(tab := "") -> void:
	if tab == "history" or tab == "ready" or tab == "puzzles":
		ui.hist_tab = tab
	var hist_tab: String = ui.hist_tab
	var v := popup_panel("📜 Pick a battle")
	ui.popup.custom_minimum_size = Vector2(760, 0)     # grows evenly both ways, so it stays centred
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for tb in [["history", "📜 History", "Real battles from long ago"], ["ready", "🎯 Ready-made", "Ready-made battles to try"],
			["puzzles", "🧩 Puzzles", "Beat an army with the points you have"]]:
		var tid := String(tb[0])
		var b := UI.button(String(tb[1]), UI.PANEL2, 18, 190)
		b.custom_minimum_size.y = 44
		b.tooltip_text = String(tb[2])
		b.name = "Tab_" + tid
		UI.set_on(b, tid == hist_tab)
		b.pressed.connect(func():
			if tid != ui.hist_tab:
				battle.snd("tick", null, 0.5)
				show_history(tid))
		tabs.add_child(b)
	var ready_tab := hist_tab == "ready"
	var intro := UI.label("Ready-made battles to try. Set one up, then press ▶ Fight! to watch, or pick a fighter and play as it." if ready_tab
		else "Real battles from long ago, set up and ready. Press Fight! to watch, or play as one of the soldiers.", 15, UI.MUTED)
	if hist_tab == "puzzles":
		intro.text = _puzzle_intro()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 740
	v.add_child(intro)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(740, minf(520.0, ui.get_viewport().get_visible_rect().size.y - 290.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.name = "Cards"
	sc.add_child(list)
	if hist_tab == "puzzles":
		_puzzle_cards(list)
		return
	if ready_tab:
		for e in B3Scenarios.MENU:
			var d: Dictionary = e
			var rid := String(d.id)
			var md: Dictionary = B3Defs.MAPS[B3Scenarios.map_for(rid)]
			var pick := func():
				close_top()
				battle.snd("whoosh", null, 0.6)
				battle.run_ready(rid)
				ui.refresh()
			_battle_card(list, String(d.icon), "%s  ·  %s %s" % [d.name, md.icon, md.name], String(d.sides), String(d.desc), pick)
		return
	var items := history_list()
	if items.is_empty():
		list.add_child(UI.label("(No history battles yet.)", 16, UI.MUTED))
	for e in items:
		var d: Dictionary = e
		var hid := String(d.get("id", ""))
		var pick := func():
			close_top()
			battle.snd("whoosh", null, 0.6)
			battle.run_history(hid)
			ui.refresh()
		var head := "%s  ·  %s%s" % [d.get("name", "?"), year_text(int(d.get("year", 0))), ("  ·  " + String(d.place)) if d.has("place") else ""]
		_battle_card(list, String(d.get("icon", "📜")), head, String(d.get("sides", "")), String(d.get("blurb", "")), pick, _history_stars(hid))


## One battle in the 📜 pop-up: a big picture, its name, who's fighting, a
## few words about it, and ▶ Set it up (`go_txt`). `extra` goes under the
## words (the ⭐ stars). Returns the ▶ button.
func _battle_card(list: Control, icon: String, head: String, sides: String, blurb: String, go_fn: Callable, extra: Control = null, go_txt := "▶ Set it up") -> Button:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(UI.PANEL2, 14, 0, Color.TRANSPARENT, 10))
	list.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var ic := UI.label(icon, 44)
	ic.custom_minimum_size.x = 60
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	h.add_child(col)
	col.add_child(UI.label(head, 19, UI.ACCENT))
	var sl := UI.label(sides, 16)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size.x = 480
	col.add_child(sl)
	var bl := UI.label(blurb, 14, UI.MUTED)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size.x = 480
	col.add_child(bl)
	if extra:
		col.add_child(extra)
	var go := UI.button(go_txt, Color("2f9e4f"), 17, 130)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.name = "Go"
	go.pressed.connect(go_fn)
	h.add_child(go)
	return go


## 📜 A History card's three ⭐ (the ones you have light up; hover for how to get each).
func _history_stars(hid: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.name = "Stars"
	var got := B3History.stars_of(hid)
	for s in B3History.STARS:
		var sid := String(s[0])
		var on := got.has(sid)
		var l := UI.label("⭐ " + String(s[1]), 15, UI.ACCENT if on else UI.MUTED)
		l.modulate.a = 1.0 if on else 0.45
		l.tooltip_text = ("Got it! " if on else "") + String(s[2])
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.name = sid + ("_on" if on else "_off")
		row.add_child(l)
	return row


# ------------------------------------------------------- 🧩 Army Puzzles
func _puzzle_intro() -> String:
	var total := 0
	for st in B3Puzzles.STAGES:
		total += B3Puzzles.stars(String((st as Dictionary).id))
	return "Beat the blue army with the 🪙 points you have! Buy your army from the Toy Box, put it in the glowing area, then press ▶ Fight!.  Spend less for more stars.   ⭐ %d of %d" % [total, B3Puzzles.STAGES.size() * 3]


## The 🧩 tab: a card for each stage, with its goal, points, the star rule
## and the stars you've got. Locked ones open when you win the one before.
func _puzzle_cards(list: Control) -> void:
	for i in B3Puzzles.STAGES.size():
		var st: Dictionary = B3Puzzles.STAGES[i]
		var pid := String(st.id)
		var md: Dictionary = B3Defs.MAPS[String(st.map)]
		var open := B3Puzzles.unlocked(pid)
		var pick := func():
			close_top()
			battle.snd("whoosh", null, 0.6)
			B3Puzzles.start(battle, pid)
			ui.refresh()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.name = "Stars"
		var bits := B3Puzzles.star_bits(B3Puzzles.stars(pid))
		var lit := UI.label(bits[0], 22)
		row.add_child(lit)
		var dim := UI.label(bits[1], 22)
		dim.modulate.a = 0.25
		row.add_child(dim)
		var rule := UI.label(B3Puzzles.rule_text(st), 14, UI.MUTED)
		rule.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rule.size_flags_vertical = Control.SIZE_FILL
		row.add_child(rule)
		var head := "%d. %s  ·  %s %s  ·  🪙 %d" % [i + 1, st.name, md.icon, md.name, int(st.budget)]
		var go := _battle_card(list, String(st.icon) if open else "🔒", head, String(st.goal),
			String(st.hint) if open else "Win the puzzle before this one to open it.", pick, row, "▶ Play" if open else "🔒")
		go.disabled = not open
		go.tooltip_text = "" if open else "Win puzzle %d first!" % i
		if not open:
			go.add_theme_stylebox_override("disabled", UI.box(UI.PANEL2.darkened(0.25), 14, 0, UI.LINE, 12))
			go.text = "🔒 Locked"
		(go.get_parent().get_parent() as Control).name = "Puzzle_" + pid


## 🧩 The fight's over: ⭐ for a win (and how to get more), or Try again.
## Takes the 🏆 scoreboard's place under the banner.
func puzzle_result(won: int, best: int, next: String) -> void:
	var pz = battle.puzzle
	if pz == null:
		return
	ui._score_shut = true
	if ui.score_card:
		ui.score_card.visible = false
	ui.again_btn.text = "⏮  Try again" if won == 0 else ("⏮  Play it again" if won == 3 else "⏮  Try for more ⭐")
	if ui.puzzle_card == null:
		var pc := PanelContainer.new()
		pc.name = "PuzzleCard"
		pc.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 20, 3, UI.ACCENT, 16))
		pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pc.offset_left = 0      # grows evenly both ways, so it stays centred
		pc.offset_right = 0
		pc.offset_top = 278
		pc.custom_minimum_size = Vector2(470, 0)
		ui.root.add_child(pc)
		ui.puzzle_card = pc
	var puzzle_card: PanelContainer = ui.puzzle_card
	for c in puzzle_card.get_children():
		puzzle_card.remove_child(c)
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	puzzle_card.add_child(v)
	var st: Dictionary = pz.stage
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UI.title("🧩 Puzzle solved!" if won > 0 else "😵 Not this time!", 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.pressed.connect(func(): ui.puzzle_card.visible = false)
	hb.add_child(x)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.name = "Stars"
	v.add_child(sr)
	for i in 3:
		var s := UI.label("⭐", 46)
		s.modulate.a = 1.0 if i < won else 0.2
		sr.add_child(s)
	var c := B3Puzzles.star_costs(st)
	var lines: Array[String] = []
	if won > 0:
		lines.append("You spent 🪙 %d of %d.%s" % [int(battle.spent), int(st.budget), "  New best! 🎉" if won > best else ""])
		if B3Puzzles.next_id(pz.id) == "":
			lines.append("🏆 That was the last one. You beat every puzzle!")
		if won < 3:
			lines.append("Spend %d or less for ⭐⭐⭐ (%d or less for ⭐⭐)." % [c[1], c[0]] if won == 1 else "Spend %d or less for ⭐⭐⭐." % c[1])
	else:
		lines.append("The blue army won this time.")
		lines.append("⏮ Try again puts them back and keeps your army, so you can change it.")
		lines.append("💡 " + String(st.hint))
	for ln in lines:
		var l := UI.label(ln, 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 440
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 10)
	v.add_child(br)
	if next != "":
		var nb := UI.button("▶ Next puzzle", Color("2f9e4f"), 19, 190)
		nb.name = "Next"
		nb.pressed.connect(func():
			battle.snd("whoosh", null, 0.6)
			B3Puzzles.start(battle, next)
			ui.refresh())
		br.add_child(nb)
	var lb := UI.button("🧩 All puzzles", UI.PANEL2, 19, 190)
	lb.pressed.connect(func(): show_history("puzzles"))
	br.add_child(lb)
	puzzle_card.visible = true


## 🧩 A puzzle that's already won stays won on screen: if its last red
## fighter burns out afterwards (a draw, as far as the battle goes), the
## winner banner (`head`, `col`) and the ⭐ card stay, not the 🏆 scoreboard.
func keep_puzzle_win(head: String, col: Color) -> void:
	ui._score_shut = true
	if ui.score_card:
		ui.score_card.visible = false
	if head != "":
		var banner_lbl: Label = ui.banner_lbl
		banner_lbl.text = head
		banner_lbl.visible_characters = head.length()
		banner_lbl.add_theme_color_override("font_color", col)
		banner_lbl.visible = true
	if ui.puzzle_card:
		ui.puzzle_card.visible = true


# ------------------------------------------------------------ ⚙️ rules & 💾 saves
## ⚙️ Battle Rules: one row of choices per rule (see B3Rules).
func show_rules() -> void:
	var v := popup_panel("⚙️ Battle Rules")
	var pz: bool = battle.puzzle != null
	if pz:
		# 🧩 a puzzle plays by the normal rules (B3Puzzles.neutral_rules); yours come back after
		var note := UI.label("🧩 Puzzles always use the normal rules, so the ⭐ stars are fair. Yours come back when you leave the puzzle.", 16, UI.ACCENT)
		note.name = "PuzzleRules"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 560
		v.add_child(note)
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
			b.disabled = pz and oid != "shake"
			b.pressed.connect(func():
				if battle.puzzle != null:
					# (only Screen shake changes in a puzzle, and your saved rules stay as they are)
					B3Rules.values[oid] = cid
					Settings.b3_rules[oid] = cid
					Settings.save()
				else:
					B3Rules.set_value(oid, cid)
				battle.apply_rules()
				battle.snd("tick", null, 0.6)
				ui._refresh_rules_btn()
				close_top()
				show_rules())
			row.add_child(b)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 10)
	v.add_child(low)
	var reset := UI.button("↺ Back to normal", UI.PANEL2, 16, 220)
	reset.disabled = pz
	reset.pressed.connect(func():
		B3Rules.reset()
		battle.apply_rules()
		battle.snd("poof", null, 0.5)
		ui._refresh_rules_btn()
		close_top()
		show_rules())
	low.add_child(reset)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	low.add_child(sp)
	# 🔊 the game's own settings live here too (the same pop-up as the title screen's)
	var settings_btn := UI.button("🔧 Settings: sound, name, screen", Color("6c4fb3"), 16)
	ui.settings_btn = settings_btn
	settings_btn.name = "Settings"
	settings_btn.tooltip_text = "Sound and music, your name and color, full screen, button size, smooth edges"
	settings_btn.pressed.connect(func():
		battle.snd("click", null, 0.4)
		show_settings())
	low.add_child(settings_btn)


## 💾 Three save slots for whole battles (see B3Saves).
func show_saves() -> void:
	var v := popup_panel("💾 Saved battles")
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
				ui.toast("💾 Saved in slot %d!" % slot, false)
			close_top())
		row.add_child(sv)
		var ld := UI.button("📂 Load", UI.PANEL2, 16, 100)
		ld.disabled = info == ""
		ld.pressed.connect(func():
			close_top()
			if B3Saves.load_slot(battle, slot):
				battle.snd("whoosh", null, 0.7)
				ui.toast("📂 Loaded slot %d. Press Fight! to start." % slot, false))
		row.add_child(ld)
	v.add_child(UI.label("Saves where every fighter, building and hazard is, plus the map and rules.\nSaving after Fight! keeps the setup from before the fight, so you can play it again.", 14, UI.MUTED))
	if not (battle.start_layout as Dictionary).is_empty():
		var rs := UI.button("⏮ Reset this battle to the start", UI.PANEL2, 16, 330)
		rs.pressed.connect(func():
			close_top()
			battle.reset_battle())
		v.add_child(rs)


func show_clear_menu() -> void:
	var v := popup_panel("🧹 Clear")
	var items := [
		["💤 KO'd fighters & rubble", "Tidy up knocked-out fighters and broken bits", func(): battle.clear_debris()],
		["🧍 All fighters", "Remove every fighter", func(): battle.clear_units()],
		["💥 Everything", "Start over with an empty battlefield", func(): battle.clear_all()],
	]
	for i in items.size():
		var it: Array = items[i]
		var b := UI.button(String(it[0]), UI.PANEL2, 18, 360)
		b.custom_minimum_size.y = 48
		b.tooltip_text = String(it[1])
		var fn: Callable = it[2]
		var go := func():
			battle.snd("poof", null, 0.7)
			fn.call()
		var big := i > 0      # (tidying up knocked-out fighters doesn't need asking)
		var what := String(it[0])
		b.pressed.connect(func():
			close_top()
			if big and _field_busy():
				confirm("🧹 Clear %s?" % what.substr(what.find(" ") + 1).to_lower(), "You can't get them back, not even with ↶ Undo!", "🧹 Yes, clear it", go)
			else:
				go.call())
		v.add_child(b)


# ------------------------------------------------------------ ❓ help & 🔧 settings
## ❓ How to play, in short sections (it scrolls if the window is short).
const HELP := [
	["🧸 Build your battle", [
		"Pick something in the Toy Box on the left (🔍 finds things by name), choose a team colour and a mood, then click the ground.",
		"Drag to place a whole line. Shift-drag for a big block. R turns buildings.",
		"↶ Undo and ↷ Redo (Ctrl+Z, Ctrl+Y) take back what you placed, erased, moved or changed.",
		"🔍 Select (2): click a fighter, or drag a box round lots of them, then change their team or mood all at once.",
		"✋ Grab (3) anything and fling it! 🧽 Eraser (4) takes things away.",
	]],
	["⚔️ Fight!", [
		"▶ Fight! (Space) and watch them go. 🐢 G is slow motion. ⏮ puts everyone back to play it again.",
		"💣 Booms: click to drop. Place C4, then press 💥 Detonate (B).",
		"🌋 Lava and acid: drag to make big pools. 🧱 Build towers, walls and bridges.",
		"⚙️ Battle Rules: moon gravity, MEGA explosions, night, rain, snow, and the 🏁 goal: 👑 Defend the King or 🚩 King of the Hill. Its 🔧 Settings button has sound, music, your name and the screen.",
	]],
	["🔥 What happens in a battle", [
		"🧠 Fighters are clever: they chop the legs off archer towers, take cover behind walls, and sneak round the ends of them.",
		"🔥 Wooden towers, bridges and trees catch fire and burn down.",
		"🪖 Tanks crush crates and small trees as they roll, but a mine under their treads goes BOOM!",
		"🪂 When a plane is shot down, its pilot jumps out and floats down on a parachute.",
	]],
	["🎮 Be a fighter", [
		"Select a fighter or vehicle and press 🎮 Play as me! (P). WASD moves, the mouse aims, click attacks, Space jumps.",
		"🖱️ Right-click is your power: a shield, a scope, a charge, a kick... It needs a moment to fill up again.",
		"👀 V looks through its eyes. ⇥ Tab (or N) jumps into the next teammate. Esc stops.",
		"🚁 Drive tanks, jeeps and cars, and fly helicopters and planes too.",
	]],
	["🏆 Things to try", [
		"📜 History battles (win ⭐ stars), 🎯 Ready-made battles and 🎲 Surprise Battles.",
		"🧩 Army Puzzles: buy an army with your 🪙 points, put it in the glowing area and win. Spend less for more ⭐!",
		"🌊 Wave Defense: the attackers go for your 🚩 keep, a stone tower with a flag and a health bar. Keep it standing, wave after wave!",
		"💾 Save your battles. 👥 Play together with friends on the same Wi-Fi.",
	]],
	["🎥 Camera", [
		"Move: WASD, arrows or right-drag. Zoom: wheel or pinch. Turn: Q / E. 🎥 F follows a fighter. Tab hides the Toy Box.",
		"Moods: ⚔️ Attack  🛡️ Defend  🎯 Ranged  😡 Berserk  😱 Coward  🌼 Peaceful",
	]],
]


func toggle_help() -> void:
	if ui.help and is_instance_valid(ui.help):
		close_top()
		return
	close_top()
	var shade := _shade()
	# centred on screen however tall it gets
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(cc)
	var help := UI.panel(22)
	ui.help = help
	help.custom_minimum_size = Vector2(720, 0)
	cc.add_child(help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	help.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := UI.title("⚔️ How to play 3D Battle", 26)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.tooltip_text = "Close [Esc]"
	x.set_meta("no_first", true)
	x.pressed.connect(close_top)
	h.add_child(x)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(690, clampf(ui.get_viewport().get_visible_rect().size.y - 230.0, 220.0, 640.0))
	v.add_child(sc)
	var col := VBoxContainer.new()
	col.name = "Help"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	sc.add_child(col)
	for sec in HELP:
		col.add_child(UI.title(String(sec[0]), 20))
		for line in sec[1]:
			var l := UI.label("•  " + String(line), 16)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 660
			col.add_child(l)
	var ok := UI.button("Let's go!", Color("2f9e4f"), 20)
	ok.pressed.connect(close_top)
	v.add_child(ok)


## 🔧 Settings: the same pop-up as the title screen's (SettingsPanel):
## sound, music, your name and color, the screen and updates.
func show_settings() -> void:
	var v := popup_panel("🔧 Settings")
	ui.popup.set_meta("settings", true)
	var sp := SettingsPanel.new()
	v.add_child(sp)
	sp.build()


func close_top() -> bool:
	var popup = ui.popup      # (untyped: it may have been freed already)
	if popup and is_instance_valid(popup):
		_drop(popup.get_parent() if popup.get_parent().has_meta("shade") else popup)      # (the dimmed backdrop goes with it)
		ui.popup = null
		return true
	var help = ui.help
	if help and is_instance_valid(help):
		var cc: Node = help.get_parent()
		_drop(cc.get_parent() if cc.get_parent().has_meta("shade") else cc)
		ui.help = null
		return true
	return false


## Takes `n` off the screen right away (and frees it).
func _drop(n: Node) -> void:
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.queue_free()


# ------------------------------------------------------------ 🏆 scoreboard
func build_score() -> void:
	var score_card := PanelContainer.new()
	ui.score_card = score_card
	score_card.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 20, 3, UI.ACCENT, 16))
	score_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_card.offset_left = 0      # grows evenly both ways, so it stays centred
	score_card.offset_right = 0
	score_card.offset_top = 278
	score_card.custom_minimum_size = Vector2(470, 0)
	score_card.visible = false
	ui.root.add_child(score_card)
	var score_box := VBoxContainer.new()
	ui.score_box = score_box
	score_box.add_theme_constant_override("separation", 8)
	score_card.add_child(score_box)


## Fills in the 🏆 scoreboard card from B3Battle.read_score() (hidden if {}).
func show_score(sc: Dictionary) -> void:
	var score_card: PanelContainer = ui.score_card
	var score_box: VBoxContainer = ui.score_box
	for c in score_box.get_children():
		score_box.remove_child(c)
		c.queue_free()
	if sc.is_empty():
		score_card.visible = false
		return
	var head := HBoxContainer.new()
	score_box.add_child(head)
	var t := UI.title("🏆 Scoreboard", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.tooltip_text = "Hide the scoreboard"
	x.pressed.connect(func():
		ui._score_shut = true
		ui.score_card.visible = false)
	head.add_child(x)
	if int(sc.secs) >= 0:
		score_box.add_child(UI.label("⏱️ The battle took %s." % B3Battle.time_text(int(sc.secs)), 16, UI.MUTED))
	var win := String(sc.win)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 6)
	score_box.add_child(g)
	for te: Dictionary in sc.teams:
		var tid := String(te.team)
		var col := B3Defs.team_col(tid)
		var won := win == tid or (tid == "wild" and win.begins_with("wild:"))
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.box(col.darkened(0.15), 12, 3 if won else 2, Color.WHITE if won else col.lightened(0.3), 8))
		var nl := UI.label("%s%s%s" % ["🐾 " if tid == "wild" else "", B3Defs.TEAM[tid].name, "  🏆" if won else ""], 17, Color.WHITE)
		nl.add_theme_constant_override("outline_size", 5)
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
		nl.custom_minimum_size.x = 104
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc.add_child(nl)
		g.add_child(pc)
		var brought := int(te.brought)
		var left := int(te.left)
		var ll := UI.label("🧍 %d of %d left" % [left, brought] if brought >= left and brought > 0 else "🧍 %d left" % left, 17)
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ll.size_flags_vertical = Control.SIZE_FILL
		g.add_child(ll)
		var kl := UI.label("💥 %s" % _kos_text(int(te.kos)), 17)
		kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kl.size_flags_vertical = Control.SIZE_FILL
		g.add_child(kl)
	if int(sc.others) > 0:
		score_box.add_child(UI.label("💣 Booms, lava and falls: %s" % _kos_text(int(sc.others)), 16, UI.MUTED))
	var top: Array = sc.top
	if not top.is_empty():
		score_box.add_child(UI.label("⭐ Top fighters", 18, UI.ACCENT))
		var g2 := GridContainer.new()
		g2.columns = 3
		g2.add_theme_constant_override("h_separation", 12)
		g2.add_theme_constant_override("v_separation", 2)
		score_box.add_child(g2)
		var medals := ["🥇", "🥈", "🥉"]
		for i in top.size():
			var e: Dictionary = top[i]
			var tid := String(e.team)
			var d := B3Defs.unit_def(String(e.kind))
			g2.add_child(UI.label(String(medals[i]), 20))
			var who := UI.label("%s %s %s" % [d.icon, "Wild" if tid == "wild" else String(B3Defs.TEAM[tid].name), d.name], 17,
				B3Defs.team_col(tid).lightened(0.35))
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			g2.add_child(who)
			var kl := UI.label(_kos_text(int(e.kos)), 16, UI.MUTED)
			kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			g2.add_child(kl)
	score_card.visible = not ui._score_shut


static func _kos_text(n: int) -> String:
	return "%d knock-out%s" % [n, "" if n == 1 else "s"]

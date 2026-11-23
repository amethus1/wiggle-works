extends CanvasLayer
## The 3D Battle HUD, built with the game's UI kit: top bar (home, Fight /
## Pause, slow-mo, clear, maps, team counts, help), left palette (tabs, team
## and personality pickers, item buttons), tool dock, unit inspector,
## winner banner and 🏆 scoreboard, toasts, sticker pops and the nuke's
## white flash. Pop-ups sit on a dimmed backdrop that blocks clicks (a click
## on it closes them); the bars never take keyboard focus, so Space and Enter
## stay game keys, but pop-ups do (arrows, Tab or a gamepad).
## The pop-ups and the 🏆 scoreboard card are made by B3UIModals, and the
## Inspector by B3UIInspector; their widgets stay here.

const TOOLS := [
	{"id": "place", "icon": "➕", "name": "Place", "key": "1", "tip": "Click the ground to place. Drag for a line. Shift-drag for a block."},
	{"id": "select", "icon": "🔍", "name": "Select", "key": "2", "tip": "Click a fighter to see it and change its team or mood."},
	{"id": "grab", "icon": "✋", "name": "Grab", "key": "3", "tip": "Grab anything and fling it!"},
	{"id": "erase", "icon": "🧽", "name": "Eraser", "key": "4", "tip": "Click or drag over things to remove them."},
]

var battle = null
var root: Control
var top_bar: HBoxContainer
var title_lbl: Label
var play_btn: Button
var slow_btn: Button
var map_btn: Button
var c4_btn: Button
var counts_box: HBoxContainer
var coin_lbl: Label           # 🪙 points left in a budget battle (🧩 Puzzles, 🌊 Wave Defense)
var counts_dirty := true
var cat := "people"
var cat_btns := {}
var grid: GridContainer
var palette: Control
var box_btn: Button
var rules_btn: Button
var play_lbl: Label
var power_pill: PowerPill         # 🖱️ overhead: the power's cooldown, under "You're the ..."
var crosshair: Control
var reset_btn: Button
var net_btn: Button
var hist_btn: Button
var surprise_btn: Button
var saves_btn: Button
var clear_btn: Button
var net_lbl: Label
var again_btn: Button
var dock_holder: Control
var _fp_hidden := false
var _fp_palette := false
var mouse_freed := false          # the winner banner let the mouse go in first person (_free_mouse_fp)
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
var insp_acts := {}      # the Inspector's action buttons: "launch", "heal", "erase", "play" -> Button
var banner_lbl: Label
var score_card: PanelContainer     # 🏆 the scoreboard under the winner banner
var score_box: VBoxContainer
var _score_shut := false           # ✖ was pressed: keep the card away until the next banner
var hist_tab := "history"          # the 📜 pop-up's tab: "history" or "ready" (🎯 Ready-made)
var toasts: VBoxContainer
var sticker_box: VBoxContainer     # 📒 new-sticker messages, top right (clear of the winner banner)
var mode_hud: B3ModeHud = null     # 🏁 the battle goal's panel (B3ModeHud)
var flash_rect: ColorRect
var popup: Control = null
var help: PanelContainer = null
var settings_btn: Button           # 🔧 Settings, in the ⚙️ pop-up
var undo_btn: Button               # ↶ ↷ in the tool dock (B3Undo)
var redo_btn: Button
var search: LineEdit               # 🔍 find something in every Toy Box tab
var box_rect: Panel                # 🔍 Select: the rectangle you drag round fighters
var _toast_hold := false           # the winner banner is up: messages go under it
var _last_us := 0
var _banner_t := -1.0
var _flash := 0.0
var _count_t := 0.0
var _insp_t := 0.0
var _lay_t := 0.0
var modals: B3UIModals             # the pop-ups and the 🏆 scoreboard card (B3UIModals)
var inspector: B3UIInspector       # the Inspector's buttons and numbers (B3UIInspector)


func _init() -> void:
	modals = B3UIModals.new(self)
	inspector = B3UIInspector.new(self)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.no_focus(root)      # Space / Enter are Fight! and Next wave (pop-ups turn focus back on)
	add_child(root)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_build_top()
	_build_palette()
	_build_dock()
	inspector.build()
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-330, 80)
	toasts.custom_minimum_size = Vector2(660, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)
	sticker_box = VBoxContainer.new()
	sticker_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sticker_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sticker_box.offset_right = -10
	sticker_box.offset_left = -10
	sticker_box.offset_top = 80
	sticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sticker_box.add_theme_constant_override("separation", 6)
	root.add_child(sticker_box)
	mode_hud = B3ModeHud.new()       # 🏁 Kings' health, hill scores, 🌊 waves (top right; stickers go under it)
	mode_hud.ui = self
	root.add_child(mode_hud)
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
	# the scoreboard rides along after the headline (see banner()): only the headline shows
	banner_lbl.visible_characters_behavior = TextServer.VC_CHARS_BEFORE_SHAPING
	again_btn = UI.button("⏮  Play it again", Color("2f9e4f"), 22, 260)
	again_btn.tooltip_text = "Everyone goes back to where they started"
	again_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	again_btn.position = Vector2(-130, 215)
	again_btn.visible = false
	again_btn.pressed.connect(func(): battle.reset_battle())
	root.add_child(banner_lbl)
	root.add_child(again_btn)
	modals.build_score()
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
	power_pill = PowerPill.new()
	power_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	power_pill.position = Vector2(-PowerPill.W * 0.5, 130)
	power_pill.visible = false
	root.add_child(power_pill)
	box_rect = Panel.new()
	box_rect.add_theme_stylebox_override("panel", UI.box(Color(1.0, 0.85, 0.3, 0.12), 6, 2, Color(1.0, 0.85, 0.3, 0.9), 0))
	box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_rect.visible = false
	root.add_child(box_rect)
	_last_us = Time.get_ticks_usec()
	refresh_palette()
	refresh_tools()
	refresh_undo()
	get_viewport().size_changed.connect(_on_resize)


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
	b.set_meta("w", w)      # (the top bar narrows them on a small screen: _fit_top)
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
	top_bar = top
	var g1 := _pill(top)
	_btn(g1, "🏠", "Back to the title screen", func(): battle.leave(), 52)
	var title := UI.title("⚔️ 3D Battle", 22)
	title.custom_minimum_size.x = 150
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g1.add_child(title)
	title_lbl = title
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
	coin_lbl = UI.label("", 19, Color("ffcf4a"))
	coin_lbl.tooltip_text = "Points left to spend"
	coin_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	coin_lbl.visible = false
	g3.add_child(coin_lbl)
	battle.budget_changed.connect(refresh_coins)
	counts_box = HBoxContainer.new()
	counts_box.add_theme_constant_override("separation", 6)
	g3.add_child(counts_box)
	var g4 := _pill(top)
	net_btn = _btn(g4, "👥", "Play together with friends on the same Wi-Fi", _show_net, 52)
	hist_btn = _btn(g4, "📜", "Pick a battle: a famous one from history, or a 🎯 ready-made one", _show_history, 52)
	surprise_btn = _btn(g4, "🎲", "Surprise Battle! A random battlefield and armies", func(): B3Surprise.run(battle), 52)
	saves_btn = _btn(g4, "💾", "Save or load a battle", _show_saves, 52)
	rules_btn = _btn(g4, "⚙️", "Battle Rules: gravity, explosions, night, weather and more.\nAnd 🔧 Settings: sound, music, your name and color, the screen", _show_rules, 52)
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
	reset_btn.disabled = not can_reset()
	counts_dirty = true
	refresh_c4()
	_refresh_rules_btn()
	_fit_top()


## The top bar has to fit across the screen, even with all five teams on the
## field, points to spend and friends playing: if it's too wide, the "⚔️ 3D
## Battle" title steps out first, then the map button shows just the map's
## picture, then 🧹 Clear just its broom, then the team counts get smaller.
func _fit_top() -> void:
	if top_bar == null or battle == null or not is_inside_tree():
		return
	var room := get_viewport().get_visible_rect().size.x - 20.0
	var md: Dictionary = B3Defs.MAPS[battle.map_id]
	title_lbl.visible = true
	map_btn.text = "%s %s" % [md.icon, md.name]
	clear_btn.text = "🧹 Clear"
	_compact_top(false)
	if top_bar.get_combined_minimum_size().x > room:
		title_lbl.visible = false
	if top_bar.get_combined_minimum_size().x > room:
		map_btn.text = String(md.icon)
	if top_bar.get_combined_minimum_size().x > room:
		clear_btn.text = "🧹"
	if top_bar.get_combined_minimum_size().x > room:
		_compact_top(true)


## The top bar squeezed up (a small screen, or ⚙️ Huge buttons): smaller
## team counts, just "🪙 12" for the points, and narrower buttons.
func _compact_top(on: bool) -> void:
	for pc in counts_box.get_children():
		var l := (pc as Control).get_child(0) as Label if (pc as Control).get_child_count() > 0 else null
		if l and l.has_meta("team"):
			l.custom_minimum_size.x = 30.0 if on else 46.0
			l.add_theme_font_size_override("font_size", 16 if on else 19)
			var col := B3Defs.team_col(String(l.get_meta("team")))
			(pc as PanelContainer).add_theme_stylebox_override("panel", UI.box(col.darkened(0.15), 12, 2, col.lightened(0.3), 4 if on else 10))
	if coin_lbl.visible and battle.budget >= 0:
		coin_lbl.text = ("🪙 %d" % battle.points_left()) if on else ("🪙 %d / %d" % [battle.points_left(), battle.budget])
	for g in top_bar.get_children():
		for b in g.find_children("*", "Button", true, false):
			var w := float(b.get_meta("w", 0.0))
			if w > 0.0:
				(b as Control).custom_minimum_size.x = minf(w, 44.0) if on else w


## The window changed size: everything that's placed by hand is placed again.
func _on_resize() -> void:
	_fit_top()
	_layout()


## ⏮ Reset works once Fight! has been pressed. In a friend's battle (👥) the
## host remembers the start, so it works while their fight is on.
func can_reset() -> bool:
	if battle.puppet:
		return battle.fighting or banner_lbl.visible
	return not (battle.start_layout as Dictionary).is_empty()


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
	_fit_top()
	refresh_undo()      # (↶ ↷ are the host's in a shared battle)
	if popup and is_instance_valid(popup) and popup.has_meta("net"):
		_show_net()


## 👥 Play together (B3UIModals.show_net).
func _show_net() -> void:
	modals.show_net()


func toggle_slowmo() -> void:
	if battle.puppet and battle.net:
		battle.net.send_cmd({"c": "slowmo"})
	else:
		battle.set_slowmo(not battle.slowmo)


func _style(b: Button, col: Color) -> void:
	b.add_theme_stylebox_override("normal", UI.box(col, 14, 2, col.lightened(0.18), 12))
	b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.12), 14, 2, col.lightened(0.35), 12))


## 🪙 "12 / 20": points left in a budget battle (hidden when things are free).
func refresh_coins() -> void:
	if coin_lbl == null:
		return
	var on: bool = battle.budget >= 0
	coin_lbl.visible = on
	if on:
		coin_lbl.text = "🪙 %d / %d" % [battle.points_left(), battle.budget]
	_price_tags()
	_fit_top()      # (the points take room in the top bar)


func _refresh_counts() -> void:
	for c in counts_box.get_children():
		counts_box.remove_child(c)      # gone now, so _fit_top measures only the new ones
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
		var l := UI.label("%s %d" % [UI.team_mark(t), int(counts[t])], 19, Color.WHITE)
		l.set_meta("team", t)
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
	# 🔍 find something by name in every tab
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "🔍 Find..."
	search.tooltip_text = "Type a name to find it in every tab"
	search.clear_button_enabled = true
	search.add_theme_font_size_override("font_size", 16)
	UI.focus_on(search)      # (the rest of the bars never take focus)
	search.text_changed.connect(func(_t: String): _fill_items())
	search.text_submitted.connect(func(_t: String): search.release_focus())
	v.add_child(search)
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
		UI.mark_swatch(b, tid, 18)      # a letter on each colour (🐾 for wild)
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
	if search and search.text != "":
		search.text = ""      # (picking a tab stops searching)
	_fill_items()


## The tab's things (or, while you search, everything whose name has what
## you typed), in the Toy Box's order.
func _item_ids() -> Array:
	var q := search.text.strip_edges().to_lower() if search else ""
	if q == "":
		return _cat_ids(cat)
	var out: Array = []
	for c in B3Defs.CATS:
		for id in _cat_ids(String(c.id)):
			var d := _item_def(String(id))
			if not out.has(id) and (String(d.get("name", "")).to_lower().contains(q) or String(id).contains(q)):
				out.append(id)
	return out


static func _cat_ids(c: String) -> Array:
	match c:
		"people", "animals", "dinos", "vehicles", "history":
			return B3Defs.UNIT_ORDER[c]
		"booms":
			return B3Defs.BOOM_ORDER
		"hazards":
			return B3Defs.HAZARD_ORDER
		"build":
			return B3Defs.STRUCT_ORDER
	return []


static func _item_def(sid: String) -> Dictionary:
	for table in [B3Defs.UNITS, B3Defs.BOOMS, B3Defs.HAZARDS, B3Defs.STRUCTS]:
		if table.has(sid):
			return table[sid]
	return {}


## True while the 🔍 box has something in it.
func searching() -> bool:
	return search != null and search.text.strip_edges() != ""


## Fills the Toy Box's grid with the tab's things (or what the search found).
func _fill_items() -> void:
	var c := cat
	for ch in grid.get_children():
		ch.queue_free()
	item_btns.clear()
	var ids: Array = _item_ids()
	if searching() and ids.is_empty():
		var nl := UI.label("🔍 Nothing called that.", 15, UI.MUTED)
		grid.add_child(nl)
	for id in ids:
		var sid := String(id)
		var d: Dictionary = _item_def(sid)
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
		if B3Defs.item_cat(battle.tools.place_id) != c and first != "" and not searching():
			battle.tools.choose(first)
	_price_tags()      # 🪙 prices while there's a budget
	refresh_palette()


func refresh_palette() -> void:
	if battle == null or battle.tools == null:
		return
	var tl = battle.tools
	for id in cat_btns:
		UI.set_on(cat_btns[id], id == cat and not searching())
	for id in item_btns:
		var on: bool = id == tl.place_id and tl.tool == "place"
		UI.set_on(item_btns[id], on)
		var nm: Label = item_btns[id].get_child(0).get_node("Name")
		UI.ink(nm, on)
	var units := cat in ["people", "animals", "dinos", "vehicles", "history"]
	if searching():
		units = false
		for id in item_btns:
			units = units or B3Defs.UNITS.has(String(id))
	team_box.visible = units
	for t in team_btns:
		var col := B3Defs.team_col(t)
		var on: bool = t == tl.place_team()      # (a budget battle's team, whatever the tab)
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
	dock.add_child(VSeparator.new())
	undo_btn = _dock_btn(dock, "↶", "Undo", "Undo [Ctrl+Z]: take back what you placed, erased, moved or changed")
	undo_btn.pressed.connect(func(): battle.tools.undo.undo())
	redo_btn = _dock_btn(dock, "↷", "Redo", "Redo [Ctrl+Y]: put it back again")
	redo_btn.pressed.connect(func(): battle.tools.undo.redo())
	_center_dock()


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
		UI.ink(nm, on)
	refresh_palette()


## ↶ ↷ look dim when there's nothing to undo or redo (and for friends: only
## the host can undo in a shared battle).
func refresh_undo() -> void:
	if undo_btn == null or battle == null or battle.tools == null or battle.tools.undo == null:
		return
	var un = battle.tools.undo
	var friend: bool = battle.puppet
	undo_btn.modulate.a = 1.0 if un.can_undo() and not friend else 0.45
	redo_btn.modulate.a = 1.0 if un.can_redo() and not friend else 0.45
	undo_btn.tooltip_text = ("Only the host can undo in a shared battle" if friend
		else "Undo [Ctrl+Z]: " + (un.next_undo_text() if un.can_undo() else "nothing to undo yet"))
	redo_btn.tooltip_text = ("Only the host can redo in a shared battle" if friend
		else "Redo [Ctrl+Y]: " + (un.next_redo_text() if un.can_redo() else "nothing to redo"))


func refresh_c4() -> void:
	if c4_btn == null or battle == null:
		return
	var n: int = battle.c4_count()
	var nm: Label = c4_btn.get_child(0).get_node("Name")
	nm.text = "Detonate" if n == 0 else "Boom! (%d)" % n
	c4_btn.modulate = Color(1, 1, 1, 1) if n > 0 else Color(1, 1, 1, 0.6)


# --------------------------------------------------------------- inspect
## The Inspector (bottom right: the selected fighters' health, team, mood and
## buttons) is built and run by B3UIInspector (`inspector`).
func show_inspect(u: B3Unit) -> void:
	inspector.show_for(u)


# ------------------------------------------------------------- popups
## The pop-ups (👥, 🗺️, 📜 battles, ⚙️ rules, 💾 saves, 🧹 Clear, ❓ help,
## 🔧 Settings and "Are you sure?") and the 🏆 scoreboard card are made by
## B3UIModals (`modals`): these pass the calls on.
func confirm(title: String, msg: String, yes_txt: String, fn: Callable) -> void:
	modals.confirm(title, msg, yes_txt, fn)


func _show_map_menu() -> void:
	modals.show_map_menu()


## 📜 Pick a battle: 📜 History, 🎯 Ready-made and 🧩 Puzzles. `tab` "" opens
## the one used last.
func _show_history(tab := "") -> void:
	modals.show_history(tab)


# ------------------------------------------------------- 🧩 Army Puzzles
var puzzle_box: PanelContainer = null     # the puzzle's goal and hint, at the top of the Toy Box
var puzzle_lbl: Label = null
var puzzle_card: PanelContainer = null    # ⭐ (or Try again) under the winner banner


## Shows the 🧩 puzzle that's on (its goal at the top of the Toy Box), or
## hides it all when there isn't one. The ⭐ card hides until the fight ends.
func show_puzzle() -> void:
	var pz = battle.puzzle if battle else null
	if puzzle_card and (pz == null or not pz.over):
		puzzle_card.visible = false
	if pz == null:
		if puzzle_box:
			puzzle_box.visible = false
		again_btn.text = "⏮  Play it again"
		return
	if puzzle_box == null and palette and palette.get_child_count() > 0:
		puzzle_box = PanelContainer.new()
		puzzle_box.name = "PuzzleBox"
		puzzle_box.add_theme_stylebox_override("panel", UI.box(Color("3a2f12"), 12, 2, UI.ACCENT, 8))
		puzzle_lbl = UI.label("", 14)
		puzzle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		puzzle_lbl.custom_minimum_size.x = 250
		puzzle_box.add_child(puzzle_lbl)
		var v: Node = palette.get_child(0)
		v.add_child(puzzle_box)
		v.move_child(puzzle_box, 0)
	if puzzle_box:
		var st: Dictionary = pz.stage
		var c := B3Puzzles.star_costs(st)
		puzzle_lbl.text = "🧩 %d. %s\n%s\n💡 %s\n⭐⭐ spend %d or less · ⭐⭐⭐ %d or less" % [B3Puzzles.index_of(pz.id) + 1, st.name, st.goal, st.hint, c[0], c[1]]
		puzzle_box.visible = true


## 🧩 The fight's over: ⭐ for a win, or Try again (B3UIModals.puzzle_result).
func puzzle_result(won: int, best: int, next: String) -> void:
	modals.puzzle_result(won, best, next)


## 🧩 A puzzle that's already won stays won on screen (B3UIModals.keep_puzzle_win).
func keep_puzzle_win(head: String, col: Color) -> void:
	modals.keep_puzzle_win(head, col)


## 🪙 While there's a budget: each Toy Box card shows its price (dimmed if
## you can't pay for it), and fighters are Normal size on your team (a Huge
## knight would cost the same as a normal one).
func _price_tags() -> void:
	if battle == null:
		return
	var on: bool = battle.budget >= 0
	var left: int = battle.points_left()
	for id in item_btns:
		var bt: Button = item_btns[id]
		var tag: Label = bt.get_node_or_null("Price")
		if on and tag == null:
			tag = UI.label("", 14, UI.ACCENT)
			tag.name = "Price"
			tag.add_theme_constant_override("outline_size", 6)
			tag.add_theme_color_override("font_outline_color", Color("1d1b3a"))
			tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			tag.offset_left = -60
			tag.offset_right = -6
			tag.offset_top = 2
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bt.add_child(tag)
		var price := B3Defs.cost(String(id))
		var banned: bool = on and battle.puzzle != null and String(id) in B3Puzzles.BIG_BOOMS
		if tag:
			tag.visible = on
			tag.text = "🚫" if banned else "🪙 %d" % price
		bt.modulate = Color(1, 1, 1, 0.45) if on and (price > left or banned) else Color.WHITE
	var team_lock: String = battle.build_team if on else ""
	for t in team_btns:
		(team_btns[t] as Control).visible = team_lock == "" or t == team_lock
	for k in size_btns:
		var sb: Button = size_btns[k]
		sb.disabled = on and absf(float(k) - 1.0) > 0.01
		sb.tooltip_text = "Fighters are Normal size when you have points to spend" if on else "Place fighters at this size (vehicles stay normal)"
	if on and battle.tools and float(battle.tools.place_size) != 1.0:
		battle.tools.place_size = 1.0
		refresh_palette()


## ⚙️ Battle Rules (B3UIModals.show_rules).
func _show_rules() -> void:
	modals.show_rules()


func _refresh_rules_btn() -> void:
	if rules_btn:
		UI.set_on(rules_btn, not B3Rules.is_default())


## 💾 Three save slots for whole battles (B3UIModals.show_saves).
func _show_saves() -> void:
	modals.show_saves()


func _show_clear_menu() -> void:
	modals.show_clear_menu()


## Tab: hide the Toy Box to see the whole battlefield, or bring it back.
## The tool dock moves back to the middle while it's hidden.
func toggle_palette() -> void:
	if palette:
		palette.visible = not palette.visible
		if box_btn:
			UI.set_on(box_btn, palette.visible)
		battle.cam.offset_k = 0.17 if palette.visible else 0.0
		_center_dock()


## The tool dock sits in the middle of what's left of the screen: a little to
## the right while the Toy Box is out, in the very middle when it's hidden.
func _center_dock() -> void:
	if dock_holder == null:
		return
	var k := 150.0 if palette and palette.visible else 0.0
	dock_holder.offset_left = k
	dock_holder.offset_right = k


## ❓ How to play (B3UIModals.HELP).
func toggle_help() -> void:
	modals.toggle_help()


## 🔧 Settings: the same pop-up as the title screen's (B3UIModals.show_settings).
func show_settings() -> void:
	modals.show_settings()


## Closes the pop-up or ❓ help on top, if there is one (true if it did).
func close_top() -> bool:
	return modals.close_top()


## With a pop-up open, arrows, Tab or a gamepad wake up the keyboard ring on
## its buttons; the 🔍 box lets go of the keys when you click somewhere else.
func _input(e: InputEvent) -> void:
	if search and search.has_focus():
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and not search.get_global_rect().has_point(mb.position):
			search.release_focus()
		var k := e as InputEventKey
		if k and k.pressed and k.keycode == KEY_ESCAPE:
			if search.text != "":
				search.text = ""
				_fill_items()
			search.release_focus()
			get_viewport().set_input_as_handled()
		return
	var top: Node = null
	if popup and is_instance_valid(popup):
		top = popup
	elif help and is_instance_valid(help):
		top = help
	if top:
		UI.wake_focus(e, top)


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


## The winner banner, with the 🏆 scoreboard under it. `score` is
## B3Battle.scoreboard(): its lines go into the label's text after the
## headline, and only the headline shows. A friend's copy gets the banner's
## text from the host (B3Net), so it shows the same scoreboard.
func banner(txt: String, col: Color, score := PackedStringArray()) -> void:
	var lines := txt.split("\n")
	var head := lines[0]
	var rest := lines.slice(1)
	rest.append_array(score)
	if not (banner_lbl.visible and banner_lbl.text.split("\n")[0] == head):
		_banner_t = 0.0        # a new banner bounces in (just a new scoreboard doesn't)
		_score_shut = false
		_free_mouse_fp()
		clear_toasts()         # (old messages would sit right behind the big headline)
	banner_lbl.text = head if rest.is_empty() else head + "\n" + "\n".join(rest)
	banner_lbl.visible_characters = head.length()
	_fit_banner()
	banner_lbl.add_theme_color_override("font_color", col)
	banner_lbl.visible = true
	again_btn.visible = can_reset()
	var info := B3Battle.read_score(rest)
	modals.show_score(info)
	if battle.puppet:
		battle.victory_stickers(info)
	refresh()


## The battle's over but the 🏆 scoreboard changed (a winner still burning
## got knocked out...): same banner, new numbers.
func update_score(score: PackedStringArray) -> void:
	if not banner_lbl.visible or banner_lbl.text.split("\n").slice(1) == score:
		return
	var col: Color = banner_lbl.get_theme_color("font_color")
	banner(banner_lbl.text.split("\n")[0], col, score)


## Takes away every message at the top (the winner banner is coming).
func clear_toasts() -> void:
	for c in toasts.get_children():
		toasts.remove_child(c)
		c.queue_free()


func hide_banner() -> void:
	banner_lbl.visible = false
	again_btn.visible = false
	if score_card:
		score_card.visible = false
	if puzzle_card:
		puzzle_card.visible = false
	_banner_t = -1.0


## 📒 A sticker was just earned (on this computer): a golden message at the top right.
func sticker_pop(id: String) -> void:
	var s: Dictionary = {}
	for x in Catalog.STICKERS:
		var d: Dictionary = x
		if String(d.id) == id:
			s = d
	if s.is_empty():
		return
	Sfx.play("sticker", null, 1.0)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.09, 0.22, 0.92), 16, 3, UI.ACCENT, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var em := UI.label(String(s.emoji), 40)
	em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(em)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	col.add_child(UI.label("📒 New sticker!", 15, UI.ACCENT))
	col.add_child(UI.label(String(s.name), 21))
	col.add_child(UI.label(String(s.desc), 14, UI.MUTED))
	p.set_meta("t", 5.0)
	p.set_meta("sticker", id)
	sticker_box.add_child(p)
	while sticker_box.get_child_count() > 3:
		var c := sticker_box.get_child(0)
		sticker_box.remove_child(c)
		c.queue_free()


## The keys line under "You're the ...". Vehicles can describe their own (controls_help(fp)).
## Two lines: moving and attacking, then the right-click power and the keys
## for switching (Tab), the view (V) and stopping (Esc).
func controls_help(u: B3Unit) -> String:
	var fp := B3Player.me.fp
	var pw := B3Player.power_help(u)
	var keys := ("%s · " % pw if pw != "" else "") + "Tab next teammate · V %s · Esc stop" % ("overhead view" if fp else "👀 first person")
	if u.has_method("controls_help"):
		return String(u.call("controls_help", fp)) + "\n" + keys
	if fp:
		return "WASD move · mouse look · click attack · Space jump\n" + keys
	return "WASD move · mouse aim · click attack · Space jump\n" + keys


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


## 🖱️ The power's pill under "You're the ..." (overhead; first person has
## the ring round the crosshair instead). Only for powers that need to
## recharge: holding up a shield or a sniper's scope doesn't.
func _pill_tick(pu: B3Unit, dt: float) -> void:
	var on := pu != null and not B3Player.me.fp and B3Player.power_has_cd(pu)
	if power_pill.visible != on:
		power_pill.visible = on
	if not on:
		return
	power_pill.position.y = play_lbl.position.y + play_lbl.size.y + 4.0
	power_pill.show_power(B3Player.power_name(pu), B3Player.power_ready(pu), dt)


## The winner banner just came up while you look out of a fighter's eyes:
## the mouse is let go so you can click ⏮ Play it again or the scoreboard's
## ✖ (clicking back in the battle grabs it again).
func _free_mouse_fp() -> void:
	if not (B3Player.me.fp and battle.cam.first_person()):
		return
	mouse_freed = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Your shot or swing just hit someone: the first-person crosshair flashes.
func hit_marker() -> void:
	if crosshair:
		(crosshair as Crosshair).hit_t = 0.15


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
		_pill_tick(pu if play_lbl.visible else null, dt)
		# messages go just under the "You're the ..." lines (and the power's pill), not on top of them
		var ty := (play_lbl.position.y + play_lbl.size.y + 8.0) if play_lbl.visible else 80.0
		if power_pill.visible:
			ty = power_pill.position.y + PowerPill.H + 8.0
		if banner_lbl.visible:
			ty = _under_banner()      # (not behind the big headline)
		if toasts.position.y != ty:
			toasts.position.y = ty
	# a pop-up (📜, 💾, ⚙️…) sits right where messages go: they wait behind it
	var pop_open := popup != null and is_instance_valid(popup) and popup.visible
	if toasts.visible == pop_open:
		toasts.visible = not pop_open
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
	for c in toasts.get_children() + sticker_box.get_children():
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
		_fit_top()
	_lay_t -= dt
	if _lay_t <= 0.0:
		_lay_t = 0.15
		_layout()
	_insp_t -= dt
	if inspect.visible and _insp_t <= 0.0:
		_insp_t = 0.15
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			inspector.update_info(u)
		else:
			inspect.visible = false


## Keeps the panels that share the screen apart, at any window size (and
## any ⚙️ button size): the Inspector stays above the tool dock and moves
## left of the 🏁 goal's panel if they'd touch; the winner banner fits across
## the screen, and the 🏆 scoreboard (or the 🧩 ⭐ card) shrinks to fit
## between ⏮ Play it again and the dock.
func _layout() -> void:
	if inspect == null or battle == null or not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var dock_top := vp.y - 10.0
	if dock_holder and dock_holder.visible:
		dock_top = dock_holder.get_global_rect().position.y
	var ob := -(vp.y - dock_top + 8.0)
	if inspect.offset_bottom != ob:
		inspect.offset_bottom = ob
	var right := -10.0
	if inspect.visible and mode_hud and mode_hud.visible:
		var isz := inspect.get_combined_minimum_size()
		var ir := Rect2(Vector2(vp.x - 10.0 - isz.x, dock_top - 8.0 - isz.y), isz)
		if ir.intersects(mode_hud.get_global_rect().grow(6.0)):
			right = -(20.0 + mode_hud.size.x)
	if inspect.offset_right != right:
		inspect.offset_right = right
	# the banner's headline: as wide as there's room for (smaller letters on a narrow screen)
	var bw := minf(1000.0, vp.x - 40.0)
	if banner_lbl.custom_minimum_size.x != bw:
		banner_lbl.custom_minimum_size.x = bw
		banner_lbl.size.x = bw
		banner_lbl.position.x = -bw * 0.5
		banner_lbl.pivot_offset.x = bw * 0.5
		_fit_banner()
	for card: Control in [score_card, puzzle_card]:
		if card == null or not card.visible:
			continue
		var h := card.get_combined_minimum_size().y
		var room := dock_top - 10.0 - card.offset_top
		var k := clampf(room / maxf(1.0, h), 0.6, 1.0)
		card.pivot_offset = Vector2(card.size.x * 0.5, 0.0)
		if absf(card.scale.x - k) > 0.005:
			card.scale = Vector2(k, k)


## The headline's letters shrink if it's wider than the screen.
func _fit_banner() -> void:
	var head := banner_lbl.text.split("\n")[0]
	var font := banner_lbl.get_theme_font("font")
	var w := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x + 48.0
	var fs := clampi(int(64.0 * minf(1.0, banner_lbl.custom_minimum_size.x / maxf(1.0, w))), 34, 64)
	banner_lbl.add_theme_font_size_override("font_size", fs)


## Where messages go while the winner banner is up: under ⏮ Play it again
## and the 🏆 card, but not down on the tool dock.
func _under_banner() -> float:
	var y := again_btn.position.y + again_btn.size.y + 8.0
	for card: Control in [score_card, puzzle_card]:
		if card and card.visible:
			var r := card.get_global_rect()
			y = maxf(y, r.end.y + 8.0)      # (the rect is already as small as the card's drawn)
	var floor_y := get_viewport().get_visible_rect().size.y - 110.0
	if dock_holder and dock_holder.visible:
		floor_y = dock_holder.get_global_rect().position.y - 8.0
	return minf(y, floor_y - toasts.size.y)


## The first-person crosshair: a small ring with a dot, white with a dark
## edge, and the gauges round it (the first-person HUD):
##  - the right-click power's cooldown: a glowing arc round the crosshair that
##    fills up clockwise, with a ping when it's ready again (B3Player.power_ready);
##  - the weapon's reload: a small bar under it (B3Player.reload_ready);
##  - in a helicopter or fighter plane, bottom left: the throttle, the height
##    over the ground and whether the bomb is loaded.
class Crosshair extends Control:
	var hit_t := 0.0
	var power_k := 1.0        # what the gauges showed last (tests read them)
	var reload_k := 1.0
	var ping_t := 0.0         # the power just got ready: a ring pops out
	var air_shown := false
	var _air_box: StyleBoxFlat = null
	const RING_R := 26.0      # (outside the hit marker's ticks)
	const PING := 0.45

	func _process(dt: float) -> void:
		if hit_t > 0.0:
			hit_t = maxf(0.0, hit_t - dt)
		if ping_t > 0.0:
			ping_t = maxf(0.0, ping_t - dt)
		if not visible:
			return
		var u: B3Unit = B3Player.unit if B3Player.active() else null
		var pk := 1.0
		if u != null and B3Player.power_has_cd(u):
			pk = B3Player.power_ready(u)
		if pk >= 1.0 and power_k < 1.0:
			ping_t = PING
		power_k = pk
		reload_k = B3Player.reload_ready(u) if u != null else 1.0
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
		var u: B3Unit = B3Player.unit if B3Player.active() else null
		if u == null:
			return
		_power_ring(c, u)
		if reload_k < 1.0:
			_reload_bar(c)
		air_shown = u is B3Aircraft
		if air_shown:
			_air_gauges(u as B3Aircraft)

	## The power's cooldown: a soft blue arc filling up clockwise from the top
	## (with a glow), a green ring popping out when it's ready, then a thin
	## green ring while it stays ready.
	func _power_ring(c: Vector2, u: B3Unit) -> void:
		if not B3Player.power_has_cd(u):
			return
		var top := -PI * 0.5
		if power_k < 1.0:
			draw_arc(c, RING_R, 0, TAU, 48, Color(0, 0, 0, 0.35), 5.0, true)
			var end := top + TAU * power_k
			if power_k > 0.01:
				draw_arc(c, RING_R, top, end, 48, Color(0.45, 0.78, 1.0, 0.35), 10.0, true)
				draw_arc(c, RING_R, top, end, 48, Color(0.66, 0.9, 1.0, 1.0), 4.0, true)
			return
		var ready := Color(0.55, 1.0, 0.65, 0.5)
		draw_arc(c, RING_R, 0, TAU, 48, ready, 1.5, true)
		if ping_t > 0.0:
			var k := 1.0 - ping_t / PING
			draw_arc(c, RING_R + 14.0 * k, 0, TAU, 48, Color(0.55, 1.0, 0.65, 0.9 * (1.0 - k)), 3.0 + 4.0 * (1.0 - k), true)

	## The weapon reloading: a small bar under the crosshair.
	func _reload_bar(c: Vector2) -> void:
		var w := 54.0
		var rect := Rect2(c + Vector2(-w * 0.5, RING_R + 12.0), Vector2(w, 6.0))
		draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(rect.position, Vector2(w * reload_k, rect.size.y)), Color(1.0, 0.86, 0.45, 0.95))

	## ✈️ Bottom left in a helicopter or fighter plane: THR (the plane's
	## throttle, W/S), ALT (metres over the ground) and the plane's bomb.
	func _air_gauges(a: B3Aircraft) -> void:
		var font := get_theme_default_font()
		var cols := 3 if a.plane else 1
		var box := Rect2(Vector2(24.0, size.y - 24.0 - 168.0), Vector2(18.0 + cols * 64.0, 168.0))
		if _air_box == null:
			_air_box = UI.box(Color(0.13, 0.12, 0.27, 0.85), 14, 2, UI.LINE)
		draw_style_box(_air_box, box)
		var x := box.position.x + 9.0
		if a.plane:
			_bar_gauge(font, Vector2(x, box.position.y), "THR", B3Player.throttle_of(a), "%d%%" % roundi(B3Player.throttle_of(a) * 100.0), UI.ACCENT)
			x += 64.0
		var alt := B3Player.altitude_of(a)
		_bar_gauge(font, Vector2(x, box.position.y), "ALT", alt / B3Aircraft.CEILING, "%d m" % roundi(alt), Color(0.5, 0.82, 1.0))
		x += 64.0
		if a.plane:
			var ready := B3Player.bomb_ready(a)
			var mid := Vector2(x + 32.0, box.position.y + 84.0)
			draw_string(font, Vector2(x, box.position.y + 24.0), "BOMB", HORIZONTAL_ALIGNMENT_CENTER, 64.0, 15, UI.MUTED)
			# a little bomb like the one under the plane, nose down: grey body,
			# yellow band, fins on top; glowing orange when it's loaded
			var fade := 1.0 if ready else 0.35
			if ready:
				draw_circle(mid, 30.0, Color(1.0, 0.5, 0.2, 0.3))
				draw_circle(mid, 22.0, Color(1.0, 0.55, 0.2, 0.3))
			var body := Color(0.32, 0.34, 0.38, fade)
			draw_colored_polygon(PackedVector2Array([mid + Vector2(-11, -30), mid + Vector2(11, -30), mid + Vector2(4, -16), mid + Vector2(-4, -16)]), Color(0.2, 0.21, 0.24, fade))
			draw_rect(Rect2(mid + Vector2(-9, -16), Vector2(18, 24)), body)
			draw_circle(mid + Vector2(0, -16), 9.0, body)
			draw_circle(mid + Vector2(0, 8), 9.0, body)
			draw_rect(Rect2(mid + Vector2(-9, -12), Vector2(18, 5)), Color(1.0, 0.81, 0.29, fade))
			draw_rect(Rect2(mid + Vector2(-5, -6), Vector2(3, 14)), Color(1, 1, 1, 0.3 * fade))
			draw_string(font, Vector2(x, box.position.y + 150.0), "READY" if ready else "...", HORIZONTAL_ALIGNMENT_CENTER, 64.0, 15, UI.GOOD if ready else UI.MUTED)

	## One upright gauge: its name on top, a bar filling up from the bottom,
	## and the number under it.
	func _bar_gauge(font: Font, at: Vector2, title: String, k: float, txt: String, col: Color) -> void:
		draw_string(font, at + Vector2(0, 24.0), title, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 15, UI.MUTED)
		var bar := Rect2(at + Vector2(24.0, 34.0), Vector2(16.0, 98.0))
		draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.55))
		var f := clampf(k, 0.0, 1.0) * bar.size.y
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y - f), Vector2(bar.size.x, f)), col)
		draw_string(font, at + Vector2(0, 150.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 15, UI.TEXT)


## 🖱️ Overhead, under "You're the ...": a pill showing the right-click
## power's cooldown. It fills up as it recharges and says it's ready (and
## glows a moment) once it is (B3Player.power_ready).
class PowerPill extends Control:
	var k := 1.0
	var glow_t := 0.0
	var lbl: Label
	var _back: StyleBoxFlat = null
	var _fills := {}
	const W := 260.0
	const H := 32.0

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl = UI.label("", 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.add_theme_color_override("font_outline_color", Color("2a1f5a"))
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)

	## `name_s`: the power, as the help line says it ("👟 kick").
	func show_power(name_s: String, ready_k: float, dt: float) -> void:
		if ready_k >= 1.0 and k < 1.0:
			glow_t = 0.6
		k = ready_k
		glow_t = maxf(0.0, glow_t - dt)
		var t := ("%s: ready!" % name_s) if k >= 1.0 else ("%s..." % name_s)
		if lbl.text != t:
			lbl.text = t
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if glow_t > 0.0:
			draw_style_box(UI.box(Color(0.45, 1.0, 0.55, 0.45 * glow_t / 0.6), int(H * 0.5 + 6.0)), r.grow(5.0 * glow_t / 0.6 + 1.0))
		if _back == null:
			_back = UI.box(Color(0.1, 0.09, 0.22, 0.85), int(H * 0.5), 2, UI.LINE)
			_fills[true] = UI.box(Color(0.35, 0.8, 0.45, 0.9), int(H * 0.5) - 3)
			_fills[false] = UI.box(Color(0.35, 0.62, 0.95, 0.85), int(H * 0.5) - 3)
		draw_style_box(_back, r)
		var fill := Rect2(r.position + Vector2(3, 3), Vector2((r.size.x - 6.0) * k, r.size.y - 6.0))
		if fill.size.x > 4.0:
			draw_style_box(_fills[k >= 1.0], fill)

class_name HUD
extends CanvasLayer
## Everything on screen during play: top bar, tool dock, toy box (picture
## tabs, Wigglies first, 🔍 search), worlds, magic, the selected-thing bar,
## 💾 save slots, stickers, play-together, settings, help, toasts and sticker
## celebrations (one at a time). The bars never take keyboard focus (Space
## is pause); pop-ups do, so arrows, Tab and a gamepad work in them.

var game: Game = null
var pad_move := 0.0

var root: Control
var top: HBoxContainer
var dock: HBoxContainer
var palette: HBoxContainer
var selbar: PanelContainer
var holder: VBoxContainer
var sel_box: HBoxContainer
var sel_name: Label
var drawers := {}
var toasts: VBoxContainer
var paused_label: Label
var tool_buttons := {}
var top_buttons := {}
var cat := "Recent"
var cat_buttons := {}
var grid: GridContainer
var trap_head: PanelContainer   # "🔌 Battle Traps" over the Builds tab's traps
var trap_grid: GridContainer    # ...and their cards
## The Builds that are 🔌 Battle Traps (ready-wired, with a pressure plate):
## they get their own heading in the Builds tab and a 🔌 badge everywhere.
const TRAPS := ["build:trap_minefield", "build:disarm_gate", "build:ufo_abductor"]
var modal: Control = null
var together: Together = null
var styles: HBoxContainer
var team_row: HBoxContainer
var pers_row: HFlowContainer
var team_buttons := {}
var pers_buttons := {}
var pers_name: Label            # the mood picked, next to the team swatches
var cat_label: Label            # the tab's name (or what the 🔍 search found)
var search: LineEdit            # 🔍 find a toy by name, in every tab
var _sel_sig := ""
var _sticker_queue: Array = []  # 📒 stickers waiting for the one on screen to finish (show_sticker)
var _sticker_on := false
## The Toy Box tabs, Wigglies first.
const TABS := ["Wigglies", "Recent", "People", "Animals", "Dinos", "Weapons", "Armor", "Booms", "Hazards", "Platforms",
	"Balls", "Blocks", "Machines", "Rides", "Builds"]


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.no_focus(root)      # Space and Enter are game keys here (pop-ups turn focus back on)
	add_child(root)
	_build_top()
	_build_dock()
	_build_selbar()
	_build_toybox()
	_build_worlds()
	_build_magic()
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-300, 76)
	toasts.custom_minimum_size = Vector2(600, 0)
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)
	paused_label = UI.title("⏸  Paused — press Space to play", 26)
	paused_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	paused_label.position = Vector2(-220, -210)
	paused_label.visible = false
	root.add_child(paused_label)
	if not Settings.seen_help and not Settings.testing:
		Settings.seen_help = true
		Settings.save()
		toggle_help.call_deferred()


# ---------------------------------------------------------------- top bar
func _pill() -> HBoxContainer:
	var p := UI.panel(18)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	top.add_child(p)
	return h


func _tb(group: HBoxContainer, id: String, txt: String, tip: String, fn: Callable, w := 0.0) -> Button:
	var b := UI.button(txt, UI.PANEL2, 18, w)
	b.tooltip_text = tip
	b.pressed.connect(fn)
	group.add_child(b)
	top_buttons[id] = b
	return b


func _build_top() -> void:
	top = HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var g1 := _pill()
	_tb(g1, "toybox", "🧸 Toy Box", "Spawn Wigglies and toys [Tab]", func(): toggle_drawer("toybox"))
	_tb(g1, "worlds", "🌍 Worlds", "Visit another world", func(): toggle_drawer("worlds"))
	_tb(g1, "magic", "✨ Magic", "Weather, party time and gravity", func(): toggle_drawer("magic"))
	var g2 := _pill()
	_tb(g2, "pause", "⏸", "Pause / play [Space]", func(): game.send({"cmd": "pause", "on": not game.world.paused}), 52)
	_tb(g2, "slow", "🐢", "Slow motion [G]", func(): game.send({"cmd": "speed", "v": 1.0 if game.world.time_scale < 0.9 else 0.3}), 52)
	_tb(g2, "night", "🌙", "Day / night", func(): game.send({"cmd": "night", "on": not game.world.night}), 52)
	_tb(g2, "fight", "⚔️", "Fighting on/off: everyone stops (or starts) fighting", func(): game.send({"cmd": "fight", "on": not game.world.battle_on}), 52)
	_tb(g2, "detonate", "💣", "Detonate every C4", func(): game.send({"cmd": "detonate"}), 52)
	_tb(g2, "undo", "↶ Undo", "Undo [Ctrl+Z]", func(): game.send({"cmd": "undo"}))
	_tb(g2, "clear", "🧹 Clear", "Remove everything", func(): game.send({"cmd": "clear"}))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var g3 := _pill()
	_tb(g3, "saves", "💾", "Save or load your playground (6 slots)", show_saves, 52)
	_tb(g3, "stickers", "📒", "Sticker book", show_stickers, 52)
	_tb(g3, "together", "👥 Play Together", "Play with friends on the same Wi-Fi", show_together)
	_tb(g3, "settings", "⚙️", "Settings: your name and color, sound, the screen", show_settings, 52)
	_tb(g3, "help", "❓", "How to play [H]", toggle_help, 52)
	_tb(g3, "menu", "🏠", "Back to the title screen", func(): game.leave(), 52)


# ------------------------------------------------------------------- dock
func _build_dock() -> void:
	holder = VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_bottom = -10
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 8)
	root.add_child(holder)
	palette = HBoxContainer.new()
	palette.alignment = BoxContainer.ALIGNMENT_CENTER
	var pp := UI.panel(16)
	pp.visible = false
	pp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pp.add_child(palette)
	holder.add_child(pp)
	for c in Catalog.PAINT:
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.box(c, 18, 3, c.darkened(0.3), 0))
		b.add_theme_stylebox_override("hover", UI.box(c.lightened(0.15), 18, 3, Color.WHITE, 0))
		b.add_theme_stylebox_override("pressed", UI.box(c, 18, 4, Color.WHITE, 0))
		b.pressed.connect(func():
			game.paint_color = c
			refresh_tools())
		palette.add_child(b)
	styles = HBoxContainer.new()
	styles.alignment = BoxContainer.ALIGNMENT_CENTER
	var sp2 := UI.panel(16)
	sp2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp2.visible = false
	sp2.add_child(styles)
	holder.add_child(sp2)
	for st in [["wood", "🪵 Wood"], ["metal", "🔩 Metal"], ["stone", "🪨 Stone"], ["concrete", "🧱 Concrete"]]:
		var b := UI.button(st[1], UI.PANEL2, 15)
		b.set_meta("style", st[0])
		b.pressed.connect(func():
			game.platform_style = st[0]
			refresh_tools())
		styles.add_child(b)
	var dp := UI.panel(20)
	dp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dock = HBoxContainer.new()
	dock.add_theme_constant_override("separation", 6)
	dp.add_child(dock)
	holder.add_child(dp)
	for t in Game.TOOLS:
		var b := UI.button("", UI.PANEL2, 15, 76)
		b.custom_minimum_size.y = 72
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var ic := UI.label(t.icon, 28)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ic)
		var nm := UI.label(t.name, 13)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.name = "Name"
		col.add_child(nm)
		b.tooltip_text = "%s [%s]\n%s" % [t.name, t.key, t.tip]
		b.pressed.connect(func(): game.set_tool(t.id))
		dock.add_child(b)
		tool_buttons[t.id] = b
	refresh_tools.call_deferred()


func refresh_tools() -> void:
	if game == null:
		return
	for id in tool_buttons:
		var on: bool = id == game.tool and game.placing == ""
		UI.set_on(tool_buttons[id], on)
		var nm: Label = tool_buttons[id].get_child(0).get_node("Name")
		UI.ink(nm, on)
	if grid:
		for c in grid.get_children() + trap_grid.get_children():
			(c as CanvasItem).queue_redraw()      # the card you're placing lights up (Card)
	palette.get_parent().visible = game.tool == "paint"
	styles.get_parent().visible = game.tool == "platform"
	for b in styles.get_children():
		UI.set_on(b, b.get_meta("style") == game.platform_style)
	for i in palette.get_child_count():
		var c: Color = Catalog.PAINT[i]
		var on: bool = c == game.paint_color
		palette.get_child(i).add_theme_stylebox_override("normal", UI.box(c, 18, 4 if on else 3, Color.WHITE if on else c.darkened(0.3), 0))


# ------------------------------------------------------------ selection bar
func _build_selbar() -> void:
	selbar = UI.panel(18)
	selbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	selbar.visible = false
	holder.add_child(selbar)
	holder.move_child(selbar, 0)   # stacks above the paint palette and the tool dock
	sel_box = HBoxContainer.new()
	sel_box.add_theme_constant_override("separation", 6)
	selbar.add_child(sel_box)


func refresh_selection() -> void:
	if game == null:
		return
	var t = game.selected()
	if t == null:
		selbar.visible = false
		_sel_sig = ""
		return
	var sig := "%d|%d|%s|%s|%s|%s|%s" % [t.uid, game.playing_uid, str(t.get("nailed")), str(t.get("team")), str(t.get("pers")), str(t.get("weapon_id")), str(t.get("state"))]
	if sig == _sel_sig and selbar.visible:
		if t is Fighter and sel_name:
			sel_name.text = _fighter_info(t)   # health changes all the time: keep it live
		return
	_sel_sig = sig
	selbar.visible = true
	for c in sel_box.get_children():
		c.queue_free()
	var name := UI.title(t.display_name(), 20)
	name.custom_minimum_size.x = 120
	sel_box.add_child(name)
	sel_name = name
	var uid: int = t.uid
	var add := func(txt: String, tip: String, fn: Callable, col := UI.PANEL2) -> void:
		var b := UI.button(txt, col, 16)
		b.tooltip_text = tip
		b.pressed.connect(fn)
		sel_box.add_child(b)
	if t is Fighter:
		_fighter_bar(t)
		return
	if t is Wiggly:
		if game.playing_uid == uid:
			add.call("⏹ Stop", "Stop playing [Esc]", func(): game.stop_playing(), UI.BAD.darkened(0.2))
		else:
			add.call("🎮 Play", "Play as this Wiggly [C]", func(): game.play_as(uid), UI.GOOD.darkened(0.25))
		add.call("✨ " + String(t.def.special), "Special move [F]", func(): game.send({"cmd": "use", "uid": uid}))
	else:
		if t.def.has("weapon") or t.def.has("armor"):
			add.call("🤝 Give", "Give it to the nearest person (or drop it on them)", func(): game.send({"cmd": "give", "uid": uid}), UI.GOOD.darkened(0.25))
		var use_txt := String(t.def.get("use", ""))
		if use_txt != "":
			add.call("⚡ " + use_txt, "Use it [F] (or double-click)", func(): game.send({"cmd": "use", "uid": uid}), UI.GOOD.darkened(0.25))
		add.call("↔", "Flip [R]", func(): game.send({"cmd": "flip", "uid": uid}))
		add.call("📌" if not t.nailed else "📌 Unnail", "Nail in place [N]", func(): game.send({"cmd": "nail", "uid": uid}))
	add.call("➖", "Smaller", func(): game._resize(game.world.things.get(uid), false))
	add.call("➕", "Bigger", func(): game._resize(game.world.things.get(uid), true))
	add.call("⧉", "Make a copy", func(): game.send({"cmd": "clone", "uid": uid}))
	add.call("✂️", "Cut its glue, ropes and wires", func(): game.send({"cmd": "unlink", "uid": uid}))
	add.call("🗑", "Delete [Del]", func():
		game.send({"cmd": "erase", "uid": uid})
		game.select(-1), UI.BAD.darkened(0.35))


func _fighter_info(t: Fighter) -> String:
	var info := "%s  ·  %s" % [t.display_name(), "KO'd" if not t.alive() else ("%d/%d ❤️" % [int(t.hp), int(t.max_hp)])]
	if t.weapon_id != "":
		info += "  ·  " + String(Catalog.toy(t.weapon_id).get("name", ""))
	# what toys and Wiggly powers are doing to it right now
	for e in [["ice", "🧊"], ["bubble", "🫧"], ["zap", "⚡"], ["goo", "🍬"], ["wet", "💧"]]:
		if t.shows(String(e[0])):
			info += " " + String(e[1])
	if t.burning > 0.0 and t.alive():
		info += " 🔥"
	return info


func _fighter_bar(t: Fighter) -> void:
	var uid := t.uid
	# (the old buttons are still children until the end of the frame, so not get_child(0))
	sel_name.text = _fighter_info(t)
	var add := func(txt: String, tip: String, fn: Callable, col := UI.PANEL2) -> Button:
		var b := UI.button(txt, col, 15)
		b.tooltip_text = tip
		b.pressed.connect(fn)
		sel_box.add_child(b)
		return b
	if t.alive():
		if game.playing_uid == uid:
			add.call("⏹ Stop", "Stop playing [Esc]", func(): game.stop_playing(), UI.BAD.darkened(0.2))
		else:
			add.call("🎮 Play", "Control this one [C]", func(): game.play_as(uid), UI.GOOD.darkened(0.25))
		add.call("⚔️ Attack", "Attack now [F]", func(): game.send({"cmd": "use", "uid": uid}))
	else:
		add.call("💖 Revive", "Get back up", func(): game.send({"cmd": "revive", "uid": uid}), UI.GOOD.darkened(0.25))
	var tb: Button = add.call("  Team  ", "Change team", func():
		var i := Catalog.TEAM_ORDER.find(t.team)
		game.send({"cmd": "team", "uid": uid, "team": Catalog.TEAM_ORDER[(i + 1) % Catalog.TEAM_ORDER.size()]}))
	var tc := Catalog.team_color(t.team)
	tb.add_theme_stylebox_override("normal", UI.box(tc, 14, 2, tc.lightened(0.3), 12))
	var pd := Catalog.personality(t.pers)
	add.call("%s %s" % [pd.emoji, pd.name], "Change personality: " + String(pd.desc), func():
		var ids: Array = Catalog.PERS_ORDER
		var i := ids.find(t.pers)
		game.send({"cmd": "pers", "uid": uid, "pers": ids[(i + 1) % ids.size()]}))
	if t.weapon_id != "":
		add.call("🫳 Drop", "Drop its weapon", func(): game.send({"cmd": "drop", "uid": uid}))
	add.call("➖", "Smaller", func(): game._resize(game.world.things.get(uid), false))
	add.call("➕", "Bigger", func(): game._resize(game.world.things.get(uid), true))
	add.call("⧉", "Make a copy", func(): game.send({"cmd": "clone", "uid": uid}))
	add.call("🗑", "Delete [Del]", func():
		game.send({"cmd": "erase", "uid": uid})
		game.select(-1), UI.BAD.darkened(0.35))


# ---------------------------------------------------------------- drawers
func _drawer(id: String, left: bool, width := 360.0) -> VBoxContainer:
	var p := UI.panel(20)
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE if left else Control.PRESET_RIGHT_WIDE)
	p.offset_top = 76
	p.offset_bottom = -104
	if left:
		p.offset_left = 10
		p.offset_right = 10 + width
	else:
		p.offset_left = -10 - width
		p.offset_right = -10
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	drawers[id] = p
	return v


func toggle_drawer(id: String, force = null) -> void:
	var p: Control = drawers[id]
	var show: bool = (not p.visible) if force == null else bool(force)
	# only one drawer per side
	if show:
		for other in drawers:
			if other != id and (other == "toybox") == (id == "toybox"):
				drawers[other].visible = false
	p.visible = show
	for k in ["toybox", "worlds", "magic"]:
		UI.set_on(top_buttons[k], drawers[k].visible)
	if id == "toybox" and show:
		_fill_grid()


func _build_toybox() -> void:
	var v := _drawer("toybox", true, 384.0)
	# 🧸 Toy Box  [🔍 Find...]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UI.title("🧸 Toy Box"))
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "🔍 Find..."
	search.tooltip_text = "Type a name to find it in every tab"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 16)
	UI.focus_on(search)      # (the rest of the bar never takes focus)
	search.text_changed.connect(func(_t: String): _fill_grid())
	search.text_submitted.connect(func(_t: String): search.release_focus())
	head.add_child(search)
	# the tabs: one picture each (hover for the name), the Wigglies first
	var tabs := GridContainer.new()
	tabs.name = "Tabs"
	tabs.columns = 8
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	v.add_child(tabs)
	for c in TABS:
		var b := UI.button(String(Catalog.CATEGORY_EMOJI.get(c, "")), UI.PANEL2, 20)
		b.custom_minimum_size = Vector2(41, 40)
		b.tooltip_text = c
		b.name = "Tab_" + c
		b.pressed.connect(func():
			cat = c
			if search.text != "":
				search.text = ""      # (picking a tab stops searching)
			_fill_grid())
		tabs.add_child(b)
		cat_buttons[c] = b
	# the tab's name, and Keep placing
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 6)
	v.add_child(nr)
	cat_label = UI.label("", 17, UI.ACCENT)
	cat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(cat_label)
	var keep := CheckBox.new()
	keep.text = "Keep placing"
	keep.tooltip_text = "Keep placing the same thing (or hold Shift)"
	keep.add_theme_font_size_override("font_size", 14)
	keep.add_theme_color_override("font_color", UI.MUTED)
	keep.toggled.connect(func(on): game.keep_placing = on)
	nr.add_child(keep)
	# fighters: team (with a letter on each colour) and mood, one picture each
	team_row = HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 4)
	var tl := UI.label("Team", 14, UI.MUTED)
	tl.custom_minimum_size.x = 42
	team_row.add_child(tl)
	for tid in Catalog.TEAM_ORDER:
		var tb := Button.new()
		tb.custom_minimum_size = Vector2(40, 34)
		tb.tooltip_text = "%s team%s" % [Catalog.TEAMS[tid].name, " (fights everyone!)" if tid == "wild" else ""]
		UI.mark_swatch(tb, tid, 16)
		var col: Color = Catalog.TEAMS[tid].color
		tb.add_theme_stylebox_override("normal", UI.box(col, 12, 2, col.darkened(0.3), 0))
		tb.add_theme_stylebox_override("hover", UI.box(col.lightened(0.15), 12, 2, Color.WHITE, 0))
		tb.pressed.connect(func():
			game.spawn_team = tid
			refresh_pickers())
		team_row.add_child(tb)
		team_buttons[tid] = tb
	pers_name = UI.label("", 14, UI.ACCENT)
	pers_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pers_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	team_row.add_child(pers_name)
	v.add_child(team_row)
	pers_row = HFlowContainer.new()
	pers_row.add_theme_constant_override("h_separation", 4)
	pers_row.add_theme_constant_override("v_separation", 4)
	var ml := UI.label("Mood", 14, UI.MUTED)
	ml.custom_minimum_size = Vector2(42, 34)
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pers_row.add_child(ml)
	var auto_b := UI.button("✨", UI.PANEL2, 17, 40)
	auto_b.custom_minimum_size.y = 34
	auto_b.tooltip_text = "Usual: each one uses its normal personality"
	auto_b.pressed.connect(func():
		game.spawn_pers = ""
		refresh_pickers())
	pers_row.add_child(auto_b)
	pers_buttons[""] = auto_b
	for pers_id: String in Catalog.PERS_ORDER:
		var pd: Dictionary = Catalog.PERS[pers_id]
		var pb := UI.button(String(pd.emoji), UI.PANEL2, 17, 40)
		pb.custom_minimum_size.y = 34
		pb.tooltip_text = "%s: %s" % [pd.name, pd.desc]
		var pid: String = pd.id
		pb.pressed.connect(func():
			game.spawn_pers = pid
			refresh_pickers())
		pers_row.add_child(pb)
		pers_buttons[pid] = pb
	v.add_child(pers_row)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var gb := VBoxContainer.new()
	gb.name = "Cards"
	gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gb.add_theme_constant_override("separation", 8)
	sc.add_child(gb)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	gb.add_child(grid)
	# 🔌 Battle Traps get a heading of their own in the Builds tab
	trap_head = PanelContainer.new()
	trap_head.name = "TrapHead"
	trap_head.add_theme_stylebox_override("panel", UI.box(Color("3a2f12"), 12, 2, UI.ACCENT, 8))
	var th := VBoxContainer.new()
	th.add_theme_constant_override("separation", 0)
	trap_head.add_child(th)
	th.add_child(UI.title("🔌 Battle Traps", 18))
	var tt := UI.label("Ready-wired traps. Step on the plate and it goes off!", 13, UI.TEXT)
	tt.autowrap_mode = TextServer.AUTOWRAP_WORD
	tt.custom_minimum_size.x = 320
	th.add_child(tt)
	trap_head.visible = false
	gb.add_child(trap_head)
	trap_grid = GridContainer.new()
	trap_grid.name = "Traps"
	trap_grid.columns = 3
	trap_grid.add_theme_constant_override("h_separation", 8)
	trap_grid.add_theme_constant_override("v_separation", 8)
	trap_grid.visible = false
	gb.add_child(trap_grid)
	var hint := UI.label("Click one, then click the world. Or drag it in!", 13, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
	if Settings.recent.is_empty():
		cat = "People"


func refresh_toybox_recent() -> void:
	if cat == "Recent" and drawers.toybox.visible and (search == null or search.text == ""):
		_fill_grid()


## What the 🔍 box is looking for ("" when it's empty).
func _query() -> String:
	return search.text.strip_edges().to_lower() if search else ""


## The ids the grid shows: the tab's, or everything whose name (or words)
## has what you typed, from every tab.
func _grid_ids() -> Array:
	var q := _query()
	if q == "":
		return Settings.recent.duplicate() if cat == "Recent" else Catalog.ids_in(cat)
	var out: Array = []
	for c in Catalog.CATEGORY_ORDER:
		for id in Catalog.ids_in(c):
			if out.has(id):
				continue
			if Catalog.spawn_name(String(id)).to_lower().contains(q) or (q.length() >= 3 and Catalog.spawn_desc(String(id)).to_lower().contains(q)):
				out.append(id)
	return out


func refresh_pickers() -> void:
	if game == null:
		return
	var show_f: bool = cat in Catalog.FIGHTER_CATS
	if _query() != "":
		show_f = false
		for id in _grid_ids():
			if String(id).begins_with("f:"):
				show_f = true
	team_row.visible = show_f
	pers_row.visible = show_f
	for tid in team_buttons:
		var col: Color = Catalog.TEAMS[tid].color
		var on: bool = tid == game.spawn_team
		team_buttons[tid].add_theme_stylebox_override("normal", UI.box(col, 12, 4 if on else 2, Color.WHITE if on else col.darkened(0.3), 0))
	for pid in pers_buttons:
		UI.set_on(pers_buttons[pid], pid == game.spawn_pers)
	if pers_name:
		if game.spawn_pers == "":
			pers_name.text = "✨ Usual"
		else:
			var pd := Catalog.personality(game.spawn_pers)
			pers_name.text = "%s %s" % [pd.emoji, pd.name]


func _fill_grid() -> void:
	refresh_pickers()
	var q := _query()
	for c in cat_buttons:
		UI.set_on(cat_buttons[c], c == cat and q == "")
	for c in grid.get_children() + trap_grid.get_children():
		c.queue_free()
	var ids := _grid_ids()
	if q != "":
		cat_label.text = "🔍 %d found" % ids.size() if not ids.is_empty() else "🔍 Nothing called that"
	else:
		cat_label.text = "%s %s" % [Catalog.CATEGORY_EMOJI.get(cat, ""), cat]
	if ids.is_empty() and q == "":
		var l := UI.label("Things you spawn show up here.", 14, UI.MUTED)
		grid.add_child(l)
	# the Builds tab: the 🔌 Battle Traps go under their own heading
	var split := q == "" and cat == "Builds"
	trap_head.visible = split
	trap_grid.visible = split
	for id in ids:
		(trap_grid if split and TRAPS.has(id) else grid).add_child(_card(String(id)))


func _card(id: String) -> Control:
	var card := Card.new()
	card.id = id
	card.hud = self
	card.custom_minimum_size = Vector2(110, 108)
	card.tooltip_text = "%s\n%s" % [Catalog.spawn_name(id), Catalog.spawn_desc(id)]
	if TRAPS.has(id):
		# a 🔌 badge in the corner: it's a Battle Trap (in Recent and searches too)
		var bd := PanelContainer.new()
		bd.name = "TrapBadge"
		bd.add_theme_stylebox_override("panel", UI.box(UI.ACCENT, 12, 2, Color.WHITE, 4))
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bd.position = Vector2(4, 4)
		var bl := UI.label("🔌", 15)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bd.add_child(bl)
		card.add_child(bd)
		card.tooltip_text = "🔌 Battle Trap: " + card.tooltip_text
	return card


## A toy-box card was clicked (place by clicking) or dragged into the world.
func card_released(id: String, dragged_out: bool) -> void:
	if dragged_out:
		var wp := game.local_pos()
		# fighters dragged in get the team and personality picked above, like clicked ones
		game.send({"cmd": "spawn", "id": id, "x": wp.x, "y": wp.y, "team": game.spawn_team, "pers": game.spawn_pers})
		Settings.add_recent(id)
		refresh_toybox_recent()
	else:
		game.start_placing(id)
		if get_viewport().get_visible_rect().size.x < 1100:
			toggle_drawer("toybox", false)


func _build_worlds() -> void:
	var v := _drawer("worlds", false, 340.0)
	v.add_child(UI.title("🌍 Worlds"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for w in Catalog.WORLDS:
		var b := UI.button("%s  %s" % [w.emoji, w.name], UI.PANEL2, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = w.desc
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			game.send({"cmd": "world", "id": w.id})
			Settings.last_world = w.id
			Settings.save()
			toggle_drawer("worlds", false))
		list.add_child(b)
		var d := UI.label(w.desc, 13, UI.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		list.add_child(d)


func _build_magic() -> void:
	var v := _drawer("magic", false, 340.0)
	v.add_child(UI.title("✨ Magic"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	for m in Catalog.MAGIC:
		var b := UI.button("%s %s" % [m.emoji, m.name], UI.PANEL2, 15)
		b.tooltip_text = m.desc
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): game.send({"cmd": "magic", "id": m.id}))
		g.add_child(b)
	v.add_child(UI.title("🪐 Gravity", 18))
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 6)
	g2.add_theme_constant_override("v_separation", 6)
	v.add_child(g2)
	for gr in Catalog.GRAVITIES:
		var b := UI.button(gr.name, UI.PANEL2, 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): game.send({"cmd": "gravity", "id": gr.id}))
		b.set_meta("g", gr.id)
		g2.add_child(b)
	v.set_meta("grav", g2)


func refresh() -> void:
	if game == null:
		return
	var w := game.world
	top_buttons.pause.text = "▶" if w.paused else "⏸"
	UI.set_on(top_buttons.pause, w.paused)
	UI.set_on(top_buttons.slow, w.time_scale < 0.9)
	UI.set_on(top_buttons.fight, w.battle_on)
	top_buttons.night.text = "☀️" if w.night else "🌙"
	var locked := game.mode == "client" and not w.allow_world_actions
	for k in ["undo", "clear"]:
		top_buttons[k].disabled = locked
	paused_label.visible = w.paused
	var g2: GridContainer = drawers.magic.get_child(0).get_meta("grav")
	for b in g2.get_children():
		UI.set_on(b, b.get_meta("g") == w.gravity_id)
	var together_txt := "👥 Play Together"
	if game.net and game.mode == "host":
		together_txt = "👥 Hosting (%d)" % (game.net.player_count() + 1)
	elif game.mode == "client":
		together_txt = "👥 Joined"
	top_buttons.together.text = together_txt
	UI.set_on(top_buttons.together, game.mode != "solo")


func _process(_d: float) -> void:
	if game:
		refresh_selection()


# ------------------------------------------------------------------ toasts
func toast(txt: String, secs := 2.6) -> void:
	var p := UI.panel(14)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(txt, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = minf(560.0, 9.0 * txt.length() + 30.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## 📒 A new sticker pops up in the middle of the screen. Two at once (a big
## boom can earn a couple) wait their turn instead of landing on each other.
func show_sticker(id: String) -> void:
	if _sticker_on:
		if not _sticker_queue.has(id):
			_sticker_queue.append(id)
		return
	var s: Dictionary = {}
	for x in Catalog.STICKERS:
		if x.id == id:
			s = x
	if s.is_empty():
		_next_sticker()
		return
	_sticker_on = true
	Sfx.play("sticker", null, 1.0)
	var p := UI.panel(24)
	p.name = "StickerPop"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_CENTER)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var e := UI.label(s.emoji, 64)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(e)
	var t1 := UI.title("New sticker!", 18)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t2 := UI.label(s.name, 24)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t2)
	var t3 := UI.label(s.desc, 14, UI.MUTED)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t3)
	root.add_child(p)
	p.position = (root.size - p.get_combined_minimum_size()) * 0.5 + Vector2(0, -120)
	p.pivot_offset = p.get_combined_minimum_size() * 0.5
	p.scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6 if _sticker_queue.is_empty() else 1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
	tw.tween_callback(_next_sticker)
	if game:
		game.effects.burst(game.cam.center() + Vector2(0, -60) / game.cam.zoom.x, 40, Vector2(100, 400), Vector2(0.6, 1.2), Vector2(3, 6), Color(1.8, 1.6, 0.6), "star", 0.2, true, 0.5)


func _next_sticker() -> void:
	_sticker_on = false
	if not _sticker_queue.is_empty():
		show_sticker(String(_sticker_queue.pop_front()))


# ----------------------------------------------------------------- modals
func close_top() -> bool:
	if modal and is_instance_valid(modal):
		modal.queue_free()
		modal = null
		return true
	for id in drawers:
		if drawers[id].visible:
			toggle_drawer(id, false)
			return true
	return false


func _open_modal(title_txt: String, width := 620.0) -> VBoxContainer:
	if modal and is_instance_valid(modal):
		modal.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close_top())
	UI.focus_on(shade)      # arrows, Tab and a gamepad move between its buttons
	root.add_child(shade)
	modal = shade
	var p := UI.panel(24)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(width, 0)
	shade.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UI.title(title_txt, 26))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := UI.button("✕", UI.PANEL2, 18, 44)
	x.tooltip_text = "Close [Esc]"
	x.set_meta("no_first", true)
	x.pressed.connect(close_top)
	head.add_child(x)
	v.add_child(head)
	return v


## The 🔍 box lets go of the keys when you click anywhere else (or press Esc),
## and with a pop-up open, arrows or a gamepad wake up the keyboard ring on
## its buttons.
func _input(e: InputEvent) -> void:
	if search and search.has_focus():
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and not search.get_global_rect().has_point(mb.position):
			search.release_focus()
		var k := e as InputEventKey
		if k and k.pressed and k.keycode == KEY_ESCAPE:
			if search.text != "":
				search.text = ""
				_fill_grid()
			search.release_focus()
			get_viewport().set_input_as_handled()
		return
	if modal and is_instance_valid(modal):
		UI.wake_focus(e, modal)


## ❓ How to play: short sections (it scrolls if the window is short).
const HELP := [
	["🫧 Wigglies and toys", [
		["🧸 Toy Box", "Pick a Wiggly or a toy (Tab opens it, 🔍 finds things by name), then click the world. Or drag it straight in!"],
		["✋ Grab", "Drag things and throw them. Pull a Wiggly hard and it pops in two! Drop it on its twin to make one big Wiggly."],
		["⚡ Use", "Double-click a toy (or press F) to switch it on, fire it or light its fuse."],
		["🎮 Play", "Select a Wiggly and press Play (C). A / D roll, W jumps, F does its special move."],
		["🧴📍🪢🌀", "Glue, Hinge, Rope and Spring: drag from one thing to another to join them."],
		["🔌 Wire", "Join a Battery, Switch, Button or Timer to lamps, fans, motors, rockets and booms."],
	]],
	["⚔️ Fighters", [
		["🧍🐻🦖", "People, Animals and Dinos are in the Toy Box. Pick a team color and a mood first."],
		["⚔️ Fight", "The ⚔️ button at the top starts the fighting (or stops it). The last team standing wins!"],
		["🗡️ Arm them", "Drag a weapon or armor onto a person, or select it and press Give."],
		["🎮 Be one", "Select a fighter and press Play (C): A / D walk, W jumps, aim with the mouse, click or F attacks. Big hits stop the game for a blink: BAM!"],
		["💣 Booms", "Grenades, C4, mines and the ☢️ Nuke! 💣 at the top sets off every C4."],
		["🏗️ Build", "The Platform tool (P): drag a box to build. Hit it hard and it cracks; big booms break it. Forts, towers and bridges are in the Toy Box."],
		["🦖 Dinos", "A Pterodactyl swoops down and snatches people. Hurt a gentle Brachiosaurus and it stomps back, mad!"],
		["🗡️ Laser", "The laser sword glows in the dark and can bat bullets away."],
	]],
	["🔌 Traps and combos", [
		["🔌 Traps", "Builds has 🔌 Battle Traps: a Minefield, a Disarm Gate and a UFO Abductor. Step on the plate and it goes off!"],
		["🔘 Plates", "A Big Button is a pressure plate: wire it to booms, and whoever steps on it sets them off."],
		["⚡ Zap", "A zap runs right through a pond full of fighters, and along metal things that touch."],
		["🔵 Bloop", "Fighters landing on a Bloop bounce right off: it's a living trampoline!"],
		["🟣 Twinkle", "Twinkle's warp flings fighters up into the air."],
		["🚚 Truck", "A monster truck smashes frozen fighters out of their ice."],
	]],
	["🌍 More to do", [
		["🌍 ✨ 🌙", "Visit 12 worlds, cast ✨ Magic (rain, airstrikes, gravity...) and switch day and night."],
		["💾 Save", "💾 keeps up to 6 playgrounds, each with a picture. Load them here or from the title screen."],
		["📒 👥", "Collect stickers, and play together with friends on the same Wi-Fi."],
		["⚔️ 3D Battle", "On the title screen: armies, tanks and dinosaurs on a big 3D battlefield!"],
	]],
	["⌨️ Keys", [
		["🖱️ Camera", "Drag empty space or use WASD to move. Scroll to zoom. Right-click selects."],
		["⌨️ Keys", "Space pause · G slow-mo · Q / E turn · R flip · N nail · Del delete · Esc close"],
		["↶ Undo", "Ctrl+Z takes back almost anything: placing, moving, paint, resizing, switches, magic, a team or a mood."],
	]],
]


func toggle_help() -> void:
	if modal and is_instance_valid(modal) and modal.has_meta("help"):
		close_top()
		return
	var v := _open_modal("❓ How to play", 760)
	modal.set_meta("help", true)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = clampf(get_viewport().get_visible_rect().size.y - 260.0, 240.0, 600.0)
	v.add_child(sc)
	var col := VBoxContainer.new()
	col.name = "Help"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	sc.add_child(col)
	for sec in HELP:
		col.add_child(UI.title(String(sec[0]), 20))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 6)
		for r in sec[1]:
			var k := UI.label(String(r[0]), 16, UI.ACCENT)
			k.custom_minimum_size.x = 130
			g.add_child(k)
			var d := UI.label(String(r[1]), 16)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 560
			g.add_child(d)
		col.add_child(g)
	var go := UI.button("Let's play! 🎉", UI.GOOD.darkened(0.2), 20)
	go.pressed.connect(close_top)
	v.add_child(go)


func show_stickers() -> void:
	var v := _open_modal(StickerBook.title(), 760)
	modal.set_meta("stickers", true)
	StickerBook.build(v, get_viewport().get_visible_rect().size.y)


## ⚙️ Settings: the same pop-up as the title screen's and 3D Battle's (SettingsPanel).
func show_settings() -> void:
	var v := _open_modal("⚙️ Settings", 700)
	modal.set_meta("settings", true)
	var sp := SettingsPanel.new()
	sp.on_name = func():
		if game and game.net:
			game.net.send_hello()
	v.add_child(sp)
	sp.build()


## 💾 Six slots for playgrounds, each with a picture (SavesPanel).
func show_saves() -> void:
	var v := _open_modal("💾 Your playgrounds", 720)
	modal.set_meta("saves", true)
	var sp := SavesPanel.new()
	sp.name = "SavesPanel"
	sp.can_save = true
	sp.on_save = func(slot: int): _save_to(slot, sp)
	sp.on_load = func(slot: int):
		if game.mode == "client":
			toast("Only the host can load a playground.")
			return
		if Saves.load_slot(game.world, slot):
			close_top()
			toast("📂 Here's your playground!")
	v.add_child(sp)
	sp.build()


## Saves the playground in `slot` with a little picture of it (taken with the
## buttons and pop-ups out of the way), then shows it in the slot.
func _save_to(slot: int, sp: SavesPanel) -> void:
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		img = get_viewport().get_texture().get_image()
		visible = true
		if img and ProjectSettings.get_setting("rendering/viewport/hdr_2d", false):
			img.convert(Image.FORMAT_RGBA8)      # (an HDR picture is in linear half-floats)
			img.linear_to_srgb()
	if Saves.save_slot(game.world, slot, "", img):
		toast("💾 Saved in slot %d!" % slot)
	else:
		toast("😕 Couldn't save there.")
	if is_instance_valid(sp):
		sp.refresh()


func show_together() -> void:
	var v := _open_modal("👥 Play Together", 640)
	together = Together.new()
	together.hud = self
	together.game = game
	v.add_child(together)
	together.build()

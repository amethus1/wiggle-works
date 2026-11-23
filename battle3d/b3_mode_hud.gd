class_name B3ModeHud
extends PanelContainer
## The 🏁 battle goal's little panel, top right under the top bar (B3UI adds
## it): the 👑 Kings' health, the 🚩 hill's score bars, or the 🌊 wave, the
## 🚩 Fort Keep's health, how many attackers are left, the countdown to the
## next wave, 👀 what's coming in it, and ▶ Next wave.
## It reads B3Modes, so friends (👥) see the host's numbers. Hidden for
## ⚔️ Last team standing and while the winner banner is up; the 📒 sticker
## messages move down below it.

const W := 268.0

var ui = null                  # B3UI
var box: VBoxContainer
var title: Label
var rows: VBoxContainer
var info: Label
var next_btn: Button
var preview: PanelContainer    # 🌊 👀 the next wave: what's coming and how many
var prev_title: Label
var prev_line: Label
var _shape := ""               # what the rows were built for (rebuilt when it changes)
var _bars := {}                # team -> ProgressBar
var _nums := {}                # team -> Label
var _names := {}               # team -> Label
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -10
	offset_left = -10
	offset_top = 76
	custom_minimum_size = Vector2(W, 0)
	# clicks on the panel stop here (they don't place a fighter or drop a boom underneath it)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.09, 0.22, 0.86), 16, 2, UI.LINE, 12))
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	title = UI.title("", 19)
	box.add_child(title)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rows)
	preview = PanelContainer.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", UI.box(Color(0.27, 0.2, 0.08, 0.92), 12, 2, Color("ffd84a"), 8))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(pv)
	prev_title = UI.label("", 15, Color("ffe9a8"))
	prev_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prev_title.custom_minimum_size.x = W - 44.0
	pv.add_child(prev_title)
	prev_line = UI.label("", 20)
	prev_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prev_line.custom_minimum_size.x = W - 44.0
	pv.add_child(prev_line)
	preview.visible = false
	box.add_child(preview)
	info = UI.label("", 15, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = W - 24.0
	box.add_child(info)
	next_btn = UI.button("▶ Next wave", Color("2f9e4f"), 17)
	next_btn.tooltip_text = "Don't wait: bring on the next wave now! [Enter]"
	next_btn.pressed.connect(press_next)
	box.add_child(next_btn)
	visible = false


func modes():
	if ui == null or ui.battle == null:
		return null
	return ui.battle.modes


## ▶ Next wave (or ▶ Start wave 1). In a friend's battle, the host does it.
func press_next() -> void:
	var b = ui.battle
	if b == null or b.modes == null:
		return
	b.snd("click", null, 0.4)
	if b.puppet and b.net:
		b.net.send_cmd({"c": "wave"})
	else:
		b.modes.next_wave()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo or not (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		return
	if visible and next_btn.visible:
		press_next()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.15
	refresh()


## Shows what the battle goal is up to right now.
func refresh() -> void:
	var m = modes()
	var k: String = m.kind if m else ""
	var show: bool = k != "" and not (ui.banner_lbl and ui.banner_lbl.visible)
	visible = show
	if show:
		preview.visible = false
		match k:
			"king":
				_kings(m)
			"hill":
				_hill(m)
			"waves":
				_waves(m)
		reset_size()
	if ui.sticker_box:
		# 📒 new-sticker messages go under this panel, not on top of it: measured
		# after it's been filled in (its height right now, not last time's)
		var top: float = offset_top + get_combined_minimum_size().y + 8.0 if show else 80.0
		if ui.sticker_box.offset_top != top:
			ui.sticker_box.offset_top = top


func _kings(m) -> void:
	title.text = "👑 Defend the King"
	var view: Array = m.king_view
	var teams: Array = []
	for e: Array in view:
		teams.append(String(e[0]))
	_build_bars("king:" + ",".join(teams), teams)
	next_btn.visible = false
	if view.is_empty():
		info.text = "Press ▶ Fight! and each team gets a King. Keep yours safe!"
		info.visible = true
		return
	info.visible = false
	for e: Array in view:
		var t := String(e[0])
		var up := bool(e[2])
		var bar: ProgressBar = _bars[t]
		bar.value = float(e[1]) * 100.0
		bar.visible = up
		(_nums[t] as Label).text = "%d%%" % roundi(float(e[1]) * 100.0) if up else "💫 Out!"
		(_names[t] as Label).text = "👑 " + String(B3Defs.TEAM[t].name)


func _hill(m) -> void:
	var sc: Dictionary = m.scores
	var teams: Array = []
	var on_field: Dictionary = ui.battle.team_counts()
	for t in B3Defs.TEAM_ORDER:
		if t != "wild" and (sc.has(t) or on_field.has(t)):
			teams.append(t)
	for t in sc:
		if String(t).begins_with("wild:"):
			teams.append(String(t))
	title.text = "🚩 King of the Hill"
	_build_bars("hill:" + ",".join(teams), teams)
	next_btn.visible = false
	var h: String = m.holder
	for t: String in teams:
		var v := float(sc.get(t, 0.0))
		(_bars[t] as ProgressBar).value = v
		(_nums[t] as Label).text = str(floori(v))
		(_names[t] as Label).text = ("🚩 " if h == t else "") + B3Modes.team_name(t)
	info.visible = true
	if String(m.hill_won) != "":
		info.text = "🏆 %s held the hill!" % B3Modes.team_name(m.hill_won)
	elif not ui.battle.fighting:
		info.text = "Stand in the glowing circle to score. First to 100 wins!"
	elif h == "+":
		info.text = "⚔️ Two teams on the hill: nobody scores!"
	elif h != "":
		info.text = "%s is on the hill!" % B3Modes.team_name(h)
	else:
		info.text = "Nobody is on the hill. Get there first!"


func _waves(m) -> void:
	var has_keep: bool = m.keep_node != null
	_build_bars("waves:keep" if has_keep else "waves", ["red"] if has_keep else [])
	if has_keep:
		# 🚩 the keep's health
		var f: float = clampf(float(m.keep_hp) / maxf(1.0, float(m.keep_max)), 0.0, 1.0)
		var up: bool = m.keep_up
		(_names["red"] as Label).text = "🚩 Keep"
		(_bars["red"] as ProgressBar).value = f * 100.0 if up else 0.0
		(_nums["red"] as Label).text = "%d%%" % ceili(f * 100.0) if up else "💥"
	var ph: String = m.phase
	var w: int = m.wave
	var best: int = m.shown_best()
	var best_s := "\n⭐ Best: wave %d" % best if best > 0 else ""
	info.visible = true
	match ph:
		"build", "":
			title.text = "🌊 Wave Defense"
			info.text = "Spend your 🪙 points in the glowing fort, then start wave %d! Keep the 🚩 keep standing.%s" % [w + 1, best_s]
			next_btn.text = "▶ Start wave %d" % (w + 1)
			next_btn.visible = true
			_preview(w + 1)
		"wave":
			title.text = "🌊 Wave %d" % w
			var n: int = m.left
			info.text = "⚔️ %d attacker%s left%s" % [n, "" if n == 1 else "s", best_s]
			next_btn.visible = false
		"break":
			title.text = "🌊 Wave %d is coming!" % (w + 1)
			info.text = "⏱️ %d…  Buy more with your 🪙 points!%s" % [ceili(float(m.break_t)), best_s]
			next_btn.text = "▶ Next wave"
			next_btn.visible = true
			_preview(w + 1)
		"lost":
			title.text = "💥 The keep fell!"
			info.text = "You held out until wave %d.%s" % [w, best_s]
			next_btn.visible = false


## 👀 What's coming in wave `n`: its name, then each kind's icon and how many
## (and the boss), e.g. "🧍×6  🪖×3".
func _preview(n: int) -> void:
	var d := B3Modes.wave_def(n)
	var parts: PackedStringArray = []
	var boss := ""
	for e: Array in B3Modes.wave_preview(n):
		if e[1] is String:
			boss = "👹 %s HUGE %s!" % [String(e[0]), String(e[1])]
		else:
			parts.append("%s×%d" % [String(e[0]), int(e[1])])
	prev_title.text = "👀 Next: %s" % String(d.name)
	prev_line.text = "  ".join(parts) + ("\n" + boss if boss != "" else "")
	preview.visible = true


## A row per team: its name, a bar in its colour and a number.
func _build_bars(shape: String, teams: Array) -> void:
	if shape == _shape:
		return
	_shape = shape
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	_bars = {}
	_nums = {}
	_names = {}
	rows.visible = not teams.is_empty()
	for t: String in teams:
		var col := B3Defs.team_col(t if not t.begins_with("wild:") else "wild")
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(h)
		var nl := UI.label("", 15, col.lightened(0.35))
		nl.custom_minimum_size.x = 86
		nl.clip_text = true
		h.add_child(nl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(112, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", UI.box(Color("1d1b3a"), 9, 1, col.darkened(0.3), 0))
		bar.add_theme_stylebox_override("fill", UI.box(col, 9, 0, col, 0))
		h.add_child(bar)
		var num := UI.label("", 15)
		num.custom_minimum_size.x = 44
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(num)
		_bars[t] = bar
		_nums[t] = num
		_names[t] = nl

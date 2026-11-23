class_name SettingsPanel
extends HBoxContainer
## ⚙️ Settings: the same pop-up on the title screen, in the 2D playground and
## in ⚔️ 3D Battle. Two columns: 🙂 you (name, color, 🔊 sound, 🎵 music) and
## 🖥️ the screen (full screen, how big the buttons are, 📳 the 2D playground's
## screen shake, ✨ 3D Battle's smooth edges), then 🔄 updates.
## Everything is saved the moment you change it.

var on_name := Callable()        # your name or color changed (2D tells friends on Wi-Fi)
var on_newer := Callable()       # 🔄 a newer version was found: (info) (the title screen shows its pop-up)
var _swatches := {}              # Color -> Button
var _upd_lbl: Label = null


func build() -> void:
	add_theme_constant_override("separation", 22)
	var left := _column()
	var right := _column()
	# ------------------------------------------------------------ 🙂 you
	left.add_child(_head("🙂 Your name"))
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 6)
	left.add_child(nr)
	var name_edit := LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.text = Settings.player_name
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.tooltip_text = "Friends see it when you play together over Wi-Fi"
	name_edit.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			Settings.player_name = t.strip_edges()
			Settings.save()
			_told())
	name_edit.text_submitted.connect(func(_t: String): name_edit.release_focus())
	nr.add_child(name_edit)
	var dice := UI.button("🎲", UI.PANEL2, 20, 48)
	dice.tooltip_text = "A silly name"
	dice.pressed.connect(func():
		Settings.player_name = "%s %s" % [Settings.ADJ[randi() % Settings.ADJ.size()], Settings.NOUN[randi() % Settings.NOUN.size()]]
		name_edit.text = Settings.player_name
		Settings.save()
		_told())
	nr.add_child(dice)
	left.add_child(_head("🎨 Your color"))
	var cg := GridContainer.new()
	cg.columns = 8
	cg.add_theme_constant_override("h_separation", 4)
	left.add_child(cg)
	for c: Color in Settings.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.add_theme_stylebox_override("hover", UI.box(c.lightened(0.15), 18, 3, Color.WHITE, 0))
		b.add_theme_stylebox_override("pressed", UI.box(c, 18, 4, Color.WHITE, 0))
		b.add_theme_stylebox_override("focus", UI.focus_ring(18))
		b.pressed.connect(func():
			Settings.player_color = c
			Settings.save()
			_paint_swatches()
			_told())
		cg.add_child(b)
		_swatches[c] = b
	_paint_swatches()
	for pair in [["🔊 Sound", "volume"], ["🎵 Music", "music"]]:
		left.add_child(_head(String(pair[0])))
		var sl := HSlider.new()
		sl.name = "Slider_" + String(pair[1])
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Settings.get(String(pair[1])))
		sl.custom_minimum_size = Vector2(300, 28)
		var key: String = pair[1]
		sl.value_changed.connect(func(val: float):
			Settings.set(key, val)
			Settings.save()
			if key == "volume":
				Sfx.set_volume(val)
			else:
				Sfx.set_music(val))
		left.add_child(sl)
	# ------------------------------------------------------------ 🖥️ the screen
	right.add_child(_head("🖥️ Screen"))
	var full := _check("🖥️ Full screen", Settings.fullscreen, func(on: bool): Settings.set_fullscreen(on))
	full.name = "Fullscreen"
	right.add_child(full)
	right.add_child(_sub("🔍 Button size"))
	right.add_child(_choices("Size", Settings.UI_SCALES, Settings.ui_scale, func(k: float): Settings.set_ui_scale(k)))
	right.add_child(_sub("📳 Screen shake (playground)"))
	right.add_child(_choices("Shake", Settings.SHAKES, Settings.shake_2d, func(k: float):
		Settings.shake_2d = k
		Settings.save()))
	var smooth := _check("✨ Smooth edges (3D)", Settings.smooth_3d, func(on: bool): Settings.set_smooth_3d(on))
	smooth.name = "Smooth3D"
	smooth.tooltip_text = "Smooth, round edges in 3D Battle. Turn it off if 3D Battle is slow on this computer."
	right.add_child(smooth)
	right.add_child(_sub("Turn it off if 3D Battle is slow."))
	# ------------------------------------------------------------ 🔄 updates
	right.add_child(_head("🔄 Updates"))
	_upd_lbl = UI.label("You have version %s." % Updater.current(), 15, UI.MUTED)
	_upd_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_upd_lbl.custom_minimum_size.x = 300
	right.add_child(_upd_lbl)
	right.add_child(_check("Look for a new version when the game starts", Settings.auto_update, func(on: bool):
		Settings.auto_update = on
		Settings.save()))
	var chk := UI.button("🔄 Check for updates now", UI.PANEL2, 16)
	chk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chk.pressed.connect(func():
		chk.disabled = true
		_upd_lbl.text = "Asking GitHub..."
		var info: Dictionary = await Updater.check()
		if not is_instance_valid(_upd_lbl):
			return
		chk.disabled = false
		if not info.get("ok", false):
			_upd_lbl.text = "😕 " + String(info.get("error", "Couldn't check."))
		elif info.get("newer", false):
			if on_newer.is_valid():
				on_newer.call(info)
			else:
				_upd_lbl.text = "✨ Version %s is ready! Go back to the 🏠 title screen and press ⚙️ to get it." % String(info.get("version", "?"))
		else:
			_upd_lbl.text = "✅ You have the newest version (%s)." % Updater.current())
	right.add_child(chk)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 320
	add_child(v)
	return v


func _head(txt: String) -> Label:
	var l := UI.label(txt, 18, UI.ACCENT)
	return l


func _sub(txt: String) -> Label:
	return UI.label(txt, 15, UI.MUTED)


## An on / off switch: a big button with ✅ or ⬜ that lights up when it's on
## (button_pressed says which, like a CheckBox).
func _check(txt: String, on: bool, fn: Callable) -> Button:
	var b := UI.button("", UI.PANEL2, 16)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 300
	b.set_meta("on", on)
	var show := func(now: bool):
		b.set_meta("on", now)
		b.text = ("✅  " if now else "⬜  ") + txt
		UI.set_on(b, now)
	show.call(on)
	b.pressed.connect(func():
		var now := not bool(b.get_meta("on"))
		show.call(now)
		fn.call(now))
	return b


## A row of buttons, one lit: `choices` are [value, name] pairs.
func _choices(id: String, choices: Array, now: float, fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = id
	row.add_theme_constant_override("separation", 4)
	var btns: Array[Button] = []
	for c in choices:
		var k := float(c[0])
		var b := UI.button(String(c[1]), UI.PANEL2, 15)
		b.custom_minimum_size = Vector2(74, 36)
		b.set_meta("k", k)
		UI.set_on(b, absf(k - now) < 0.01)
		b.pressed.connect(func():
			fn.call(k)
			for o in btns:
				UI.set_on(o, absf(float(o.get_meta("k")) - k) < 0.01))
		row.add_child(b)
		btns.append(b)
	return row


func _paint_swatches() -> void:
	for c: Color in _swatches:
		var on: bool = c == Settings.player_color
		(_swatches[c] as Button).add_theme_stylebox_override("normal", UI.box(c, 18, 4 if on else 2, Color.WHITE if on else c.darkened(0.3), 0))


func _told() -> void:
	if on_name.is_valid():
		on_name.call()

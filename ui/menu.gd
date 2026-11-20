extends Node
## Title screen: a live playground behind a bouncy logo, Play, world picker,
## Play Together, stickers, settings.

var main = null
var world: World
var effects: Effects
var cam: Cam
var layer: CanvasLayer
var logo: Label
var hello: Label
var modal: Control = null
var _t := 0.0
var _hop_t := 1.0


func _ready() -> void:
	world = World.new()
	add_child(world)
	effects = Effects.new()
	effects.world = world
	add_child(effects)
	world.fx.connect(effects.handle)
	cam = Cam.new()
	cam.effects = effects
	add_child(cam)
	cam.make_current()
	world.load_world("meadow")
	for k in ["zappy", "twinkle", "blaze"]:
		world.spawn_wiggly(k, Vector2(randf_range(-300, 300), 0))
	cam.fit(Rect2(-700, -330, 1400, 760), get_viewport().get_visible_rect().size)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.glow_enabled = true
	e.glow_hdr_threshold = 1.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.environment = e
	add_child(env)
	_build_ui()


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	logo = Label.new()
	logo.text = "Wiggle Works"
	logo.add_theme_font_size_override("font_size", 96)
	logo.add_theme_color_override("font_color", Color("ffcf4a"))
	logo.add_theme_constant_override("outline_size", 22)
	logo.add_theme_color_override("font_outline_color", Color("3b2a8f"))
	logo.add_theme_constant_override("shadow_offset_y", 8)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var sub := UI.label("a squishy physics playground", 24, Color.WHITE)
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color("3b2a8f"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var p := UI.panel(28)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	hello = UI.label("", 20)
	hello.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hello)
	_hello()
	var play := UI.button("▶   Play", UI.GOOD.darkened(0.15), 34, 440)
	play.custom_minimum_size.y = 76
	play.pressed.connect(func(): main.start_game({"world": Settings.last_world}))
	v.add_child(play)
	var battle := UI.button("⚔️   3D Battle", Color("c0392b").darkened(0.15), 26, 440)
	battle.custom_minimum_size.y = 60
	battle.tooltip_text = "Place armies, animals and dinosaurs on a 3D battlefield and watch them fight"
	battle.pressed.connect(func(): main.start_battle3d({}))
	v.add_child(battle)
	var worlds := HFlowContainer.new()
	worlds.alignment = FlowContainer.ALIGNMENT_CENTER
	worlds.custom_minimum_size.x = 440
	worlds.add_theme_constant_override("h_separation", 6)
	worlds.add_theme_constant_override("v_separation", 6)
	for w in Catalog.WORLDS:
		var b := UI.button(w.emoji, UI.PANEL2, 26, 50)
		b.tooltip_text = "%s\n%s" % [w.name, w.desc]
		b.pressed.connect(func():
			Settings.last_world = w.id
			Settings.save()
			main.start_game({"world": w.id}))
		worlds.add_child(b)
	v.add_child(worlds)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var tog := UI.button("👥 Play Together", UI.PANEL2, 20)
	tog.pressed.connect(_together)
	row.add_child(tog)
	var st := UI.button("📒 Stickers %d/%d" % [Settings.stickers.size(), Catalog.STICKERS.size()], UI.PANEL2, 20)
	st.pressed.connect(_stickers)
	row.add_child(st)
	var me := UI.button("⚙️ Me", UI.PANEL2, 20)
	me.pressed.connect(_settings)
	row.add_child(me)
	v.add_child(row)
	var quit := UI.button("Quit", UI.PANEL2.darkened(0.2), 16)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)
	var ver := UI.label("v" + Updater.current(), 14, Color(1, 1, 1, 0.7))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -12
	ver.offset_bottom = -8
	ver.add_theme_constant_override("outline_size", 6)
	ver.add_theme_color_override("font_outline_color", Color("3b2a8f"))
	root.add_child(ver)
	if Updater.auto_check_wanted() and not Updater.prompted:
		_auto_update_check()


## 🔄 When the game starts: is there a newer version on GitHub?
func _auto_update_check() -> void:
	var info: Dictionary = await Updater.check()
	if not is_inside_tree() or Updater.prompted:
		return
	if info.get("ok", false) and info.get("newer", false) and modal == null:
		Updater.prompted = true
		_update_modal(info)


## "✨ A new version is ready!" with Update now / Later.
func _update_modal(info: Dictionary) -> void:
	var v := _modal("✨ New version!", 580)
	var msg := UI.label("Wiggle Works %s is ready. You have %s." % [info.version, Updater.current()], 20)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(msg)
	var notes := String(info.get("notes", "")).strip_edges()
	if notes != "":
		var n := UI.label(notes.left(500) + ("…" if notes.length() > 500 else ""), 15, UI.MUTED)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD
		n.custom_minimum_size.x = 520
		v.add_child(n)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(520, 26)
	bar.visible = false
	v.add_child(bar)
	var status := UI.label("", 16, UI.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 520
	v.add_child(status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var go := UI.button("⬇️ Update now" if Updater.can_install() else "🌐 Get it", UI.GOOD.darkened(0.15), 22, 240)
	var later := UI.button("Later", UI.PANEL2, 20, 140)
	row.add_child(go)
	row.add_child(later)
	v.add_child(row)
	later.pressed.connect(func():
		modal.queue_free()
		modal = null)
	var on_progress := func(done: int, total: int) -> void:
		if is_instance_valid(bar) and total > 0:
			bar.value = 100.0 * done / total
			status.text = "Downloading... %d of %d MB" % [done >> 20, total >> 20]
	go.pressed.connect(func():
		if not Updater.can_install():
			Updater.install(info)
			status.text = "The download page opened in your web browser."
			return
		go.disabled = true
		later.disabled = true
		bar.visible = true
		status.text = "Downloading..."
		Updater.progress.connect(on_progress)
		var problem: String = await Updater.install(info)
		if Updater.progress.is_connected(on_progress):
			Updater.progress.disconnect(on_progress)
		if problem != "" and is_instance_valid(status):
			status.text = "😕 " + problem
			go.disabled = false
			later.disabled = false
			bar.visible = false
		elif is_instance_valid(status):
			status.text = "✅ Restarting with the new version...")


func _hello() -> void:
	hello.text = "Hi, %s!" % Settings.player_name
	hello.add_theme_color_override("font_color", Settings.player_color)


func _process(dt: float) -> void:
	_t += dt
	logo.pivot_offset = logo.size * 0.5
	logo.rotation = sin(_t * 1.6) * 0.03
	logo.scale = Vector2.ONE * (1.0 + 0.025 * sin(_t * 3.2))
	effects.view_rect = cam.view_rect()
	world.backdrop.cam_pos = cam.center()
	_hop_t -= dt
	if _hop_t <= 0.0:
		_hop_t = randf_range(0.6, 1.4)
		var ws := world.wigglies()
		if not ws.is_empty():
			var w: Wiggly = ws[randi() % ws.size()]
			if w.grounded:
				w.hop(randf_range(-0.8, 0.8), randf_range(0.8, 1.3))


func _modal(title_txt: String, width := 600.0) -> VBoxContainer:
	if modal:
		modal.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
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
	x.pressed.connect(func():
		modal.queue_free()
		modal = null
		_hello())
	head.add_child(x)
	v.add_child(head)
	return v


func _together() -> void:
	var v := _modal("👥 Play Together", 640)
	var t := Together.new()
	t.main = main
	v.add_child(t)
	t.build()


func _stickers() -> void:
	var v := _modal("📒 Sticker Book", 760)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	for s in Catalog.STICKERS:
		var got: bool = Settings.stickers.has(s.id)
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(170, 100)
		var e := UI.label(s.emoji if got else "❔", 36)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(e)
		var n := UI.label(s.name, 14, UI.TEXT if got else UI.MUTED)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(n)
		var d := UI.label(s.desc, 12, UI.MUTED)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		d.custom_minimum_size.x = 160
		cell.add_child(d)
		g.add_child(cell)


func _settings() -> void:
	var v := _modal("⚙️ Me", 560)
	v.add_child(UI.label("Your name:", 16, UI.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text_changed.connect(func(t):
		if String(t).strip_edges() != "":
			Settings.player_name = String(t).strip_edges()
			Settings.save())
	v.add_child(name_edit)
	var dice := UI.button("🎲 Silly name", UI.PANEL2, 16)
	dice.pressed.connect(func():
		Settings.player_name = "%s %s" % [Settings.ADJ[randi() % Settings.ADJ.size()], Settings.NOUN[randi() % Settings.NOUN.size()]]
		name_edit.text = Settings.player_name
		Settings.save())
	v.add_child(dice)
	v.add_child(UI.label("Your color:", 16, UI.MUTED))
	var row := HBoxContainer.new()
	for c in Settings.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.box(c, 24, 4 if c == Settings.player_color else 2, Color.WHITE if c == Settings.player_color else c.darkened(0.3), 0))
		b.add_theme_stylebox_override("hover", UI.box(c.lightened(0.15), 24, 3, Color.WHITE, 0))
		b.pressed.connect(func():
			Settings.player_color = c
			Settings.save()
			_settings())
		row.add_child(b)
	v.add_child(row)
	for pair in [["🔊 Sound", "volume"], ["🎵 Music", "music"]]:
		var h := HBoxContainer.new()
		h.add_child(UI.label(pair[0], 18))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Settings.get(pair[1])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size.x = 300
		var key: String = pair[1]
		sl.value_changed.connect(func(val):
			Settings.set(key, val)
			Settings.save()
			if key == "volume":
				Sfx.set_volume(val)
			else:
				Sfx.set_music(val))
		h.add_child(sl)
		v.add_child(h)
	# 🔄 updates
	v.add_child(UI.label("🔄 Updates", 18))
	var ulbl := UI.label("You have version %s." % Updater.current(), 16, UI.MUTED)
	ulbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(ulbl)
	var auto := CheckBox.new()
	auto.text = "Look for a new version when the game starts"
	auto.button_pressed = Settings.auto_update
	auto.focus_mode = Control.FOCUS_NONE
	auto.add_theme_font_size_override("font_size", 16)
	auto.toggled.connect(func(on: bool):
		Settings.auto_update = on
		Settings.save())
	v.add_child(auto)
	var chk := UI.button("🔄 Check for updates now", UI.PANEL2, 16)
	chk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chk.pressed.connect(func():
		chk.disabled = true
		ulbl.text = "Asking GitHub..."
		var info: Dictionary = await Updater.check()
		if not is_instance_valid(ulbl):
			return
		chk.disabled = false
		if not info.get("ok", false):
			ulbl.text = "😕 " + String(info.get("error", "Couldn't check."))
		elif info.get("newer", false):
			_update_modal(info)
		else:
			ulbl.text = "✅ You have the newest version (%s)." % Updater.current())
	v.add_child(chk)

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
var modal_x: Button = null     # the open pop-up's ✕
var play_btn: Button = null    # ▶ Play (it says which world)
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
	# centred, and it scrolls if the window is too short for all of it
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(scroll)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cc)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	cc.add_child(col)
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
	# two cards side by side: 🫧 the 2D playground (and its 12 worlds), and ⚔️ 3D Battle
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	v.add_child(cards)
	var pg := _card(cards, "🫧 Playground", UI.PANEL2)
	var wd: Dictionary = Catalog.world_def(Settings.last_world)
	play_btn = UI.button("▶   Play", UI.GOOD.darkened(0.15), 34, 420)
	play_btn.custom_minimum_size.y = 92
	play_btn.tooltip_text = "Play in %s %s" % [wd.emoji, wd.name]
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := play_btn.get_theme_stylebox(st)
		if sb:
			sb.content_margin_bottom = 30      # the world's name goes under ▶ Play
	var where := UI.label("in %s %s" % [wd.emoji, wd.name], 18, Color(1, 1, 1, 0.92))
	where.name = "World"
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	where.offset_top = -34
	where.offset_bottom = -8
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_btn.add_child(where)
	play_btn.pressed.connect(func(): main.start_game({"world": Settings.last_world}))
	pg.add_child(play_btn)
	pg.add_child(UI.label("or pick a world:", 15, UI.MUTED))
	var worlds := GridContainer.new()
	worlds.name = "Worlds"
	worlds.columns = 6
	worlds.add_theme_constant_override("h_separation", 6)
	worlds.add_theme_constant_override("v_separation", 6)
	for w in Catalog.WORLDS:
		var b := UI.button(w.emoji, UI.PANEL2, 26, 64)
		b.custom_minimum_size.y = 52
		b.tooltip_text = "%s\n%s" % [w.name, w.desc]
		UI.set_on(b, w.id == Settings.last_world)
		b.pressed.connect(func():
			Settings.last_world = w.id
			Settings.save()
			main.start_game({"world": w.id}))
		worlds.add_child(b)
	pg.add_child(worlds)
	var b3 := _card(cards, "⚔️ 3D Battle", Color("4a1f2a"))
	var battle := UI.button("⚔️   3D Battle", Color("c0392b").darkened(0.15), 28, 260)
	battle.custom_minimum_size.y = 92
	battle.tooltip_text = "Place armies, animals and dinosaurs on a 3D battlefield and watch them fight"
	battle.pressed.connect(func(): main.start_battle3d({}))
	b3.add_child(battle)
	var blurb := UI.label("Armies, dinosaurs, tanks and planes on a big 3D battlefield. History battles, 🧩 puzzles and 🌊 wave defense too!", 15, UI.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 260
	b3.add_child(blurb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var tog := UI.button("👥 Play Together", UI.PANEL2, 20)
	tog.pressed.connect(_together)
	row.add_child(tog)
	var ld := UI.button("📂 Load", UI.PANEL2, 20)
	ld.tooltip_text = "Carry on with a playground you saved"
	ld.disabled = not Saves.has_slot()
	ld.pressed.connect(_saves)
	row.add_child(ld)
	var st := UI.button("📒 Stickers %d/%d" % [Settings.stickers.size(), Catalog.STICKERS.size()], UI.PANEL2, 20)
	st.pressed.connect(_stickers)
	row.add_child(st)
	var me := UI.button("⚙️ Me", UI.PANEL2, 20)
	me.tooltip_text = "Your name and color, sound, the screen and updates"
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
	# --menu --open=stickers|settings|saves (screenshots)
	match String(main.args.get("open", "")) if main else "":
		"stickers":
			_stickers()
		"settings":
			_settings()
		"saves":
			_saves()


## One of the two big cards on the title screen: a heading over its buttons.
func _card(parent: Control, title_txt: String, col: Color) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(col.darkened(0.15), 20, 2, col.lightened(0.25), 12))
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	v.add_child(UI.title(title_txt, 22))
	return v


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
	var close := modal_x
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
	later.pressed.connect(close_modal)
	var on_progress := func(done: int, total: int) -> void:
		if is_instance_valid(bar) and total > 0:
			bar.value = 100.0 * done / total
			status.text = "Downloading... %d of %d MB" % [done >> 20, total >> 20]
	go.pressed.connect(func():
		if not Updater.can_install():
			Updater.install(info)
			status.text = "The download page opened in your web browser."
			return
		# while it downloads and swaps, the pop-up stays open (✕ is off too)
		go.disabled = true
		later.disabled = true
		close.disabled = true
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
			close.disabled = false
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
		if modal != null and is_instance_valid(modal):
			return      # a pop-up is open: the Wigglies behind it keep still (and quiet)
		var ws := world.wigglies()
		if not ws.is_empty():
			var w: Wiggly = ws[randi() % ws.size()]
			if w.grounded:
				w.hop(randf_range(-0.8, 0.8), randf_range(0.8, 1.3))


## Esc closes the pop-up; arrows, Tab or a gamepad wake up the keyboard ring
## (on the pop-up's buttons if one is open, otherwise the title screen's).
func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and modal != null and is_instance_valid(modal):
		close_modal()
		get_viewport().set_input_as_handled()
		return
	UI.wake_focus(e, modal if modal != null and is_instance_valid(modal) else layer.get_child(0))


## Closes the open pop-up (not while an update is downloading: its pop-up shows how it went).
func close_modal() -> bool:
	if modal == null or not is_instance_valid(modal):
		return false
	if Updater.installing:
		return false
	modal.queue_free()
	modal = null
	_hello()
	return true


func _modal(title_txt: String, width := 600.0) -> VBoxContainer:
	if modal:
		modal.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# clicking the dark part around it closes it
	shade.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_modal())
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
	x.tooltip_text = "Close [Esc]"
	x.set_meta("no_first", true)
	x.pressed.connect(close_modal)
	head.add_child(x)
	modal_x = x
	v.add_child(head)
	return v


func _together() -> void:
	var v := _modal("👥 Play Together", 640)
	var t := Together.new()
	t.main = main
	v.add_child(t)
	t.build()


func _stickers() -> void:
	var v := _modal(StickerBook.title(), 760)
	modal.set_meta("stickers", true)
	StickerBook.build(v, get_viewport().get_visible_rect().size.y)


## 📂 Carry on with a saved playground (Saves): it opens in its world.
func _saves() -> void:
	var v := _modal("📂 Your playgrounds", 720)
	modal.set_meta("saves", true)
	var sp := SavesPanel.new()
	sp.can_save = false
	sp.on_load = func(slot: int):
		var d := Saves.read(slot)
		if d.is_empty():
			return
		main.start_game({"world": String(d.get("world", Settings.last_world)), "load": slot})
	v.add_child(sp)
	sp.build()


func _settings() -> void:
	var v := _modal("⚙️ Me", 700)
	modal.set_meta("settings", true)
	var sp := SettingsPanel.new()
	sp.on_name = _hello
	sp.on_newer = func(info: Dictionary): _update_modal(info)
	v.add_child(sp)
	sp.build()

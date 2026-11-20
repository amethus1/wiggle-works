class_name Together
extends VBoxContainer
## The "Play Together" panel: host your playground, find and join a friend's
## game on the same Wi-Fi, see who's playing, send emotes.

var hud = null
var game = null      # null on the title screen
var main = null      # title screen: used to start a game
var finder: LanFinder
var _list: VBoxContainer


func build() -> void:
	add_theme_constant_override("separation", 10)
	for c in get_children():
		c.queue_free()
	var mode := "solo" if game == null else String(game.mode)
	match mode:
		"host":
			_hosting()
		"client":
			_joined()
		_:
			_choose()


func _choose() -> void:
	add_child(UI.label("Play in the same playground as friends on the same Wi-Fi. Everyone needs Wiggle Works on their computer.", 16, UI.MUTED))
	(get_child(get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
	var tip3d := UI.label("For ⚔️ 3D Battle, open it and press 👥 there.", 15, UI.MUTED)
	add_child(tip3d)
	var host := UI.button("🏠  Host — friends join my playground", UI.GOOD.darkened(0.3), 20)
	host.pressed.connect(func():
		if game:
			if game.start_hosting():
				build()
		elif main:
			main.start_game({"mode": "host", "world": Settings.last_world}))
	add_child(host)
	add_child(UI.title("Join a friend", 20))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	finder = LanFinder.new()
	add_child(finder)
	if not finder.start():
		_list.add_child(UI.label("Couldn't listen for games (is another copy of the game open?). You can still type an address below.", 14, UI.MUTED))
	finder.games_changed.connect(_refresh_list)
	_refresh_list()
	var row := HBoxContainer.new()
	var ip := LineEdit.new()
	ip.placeholder_text = "or type their address, like 192.168.1.23"
	ip.text = Settings.last_join
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.add_theme_font_size_override("font_size", 18)
	row.add_child(ip)
	var join := UI.button("Join", UI.PANEL2, 18)
	join.pressed.connect(func(): _join(ip.text.strip_edges()))
	ip.text_submitted.connect(func(t): _join(String(t).strip_edges()))
	row.add_child(join)
	add_child(row)


func _refresh_list() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	if finder.games.is_empty():
		_list.add_child(UI.label("Looking for games on your Wi-Fi…", 15, UI.MUTED))
		return
	for ipaddr in finder.games:
		var g: Dictionary = finder.games[ipaddr]
		var w := Catalog.world_def(String(g.get("world", "meadow")))
		var b := UI.button("%s  %s's playground — %s %s (%d playing)" % ["🎮", g.get("name", "Friend"), w.emoji, w.name, int(g.get("players", 1))], UI.PANEL2, 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var addr := String(ipaddr)
		b.pressed.connect(func(): _join(addr))
		_list.add_child(b)


func _join(ip: String) -> void:
	if ip == "":
		return
	Settings.last_join = ip
	Settings.save()
	var m = main if main else (game.main if game else null)
	if m:
		m.start_game({"mode": "client", "ip": ip, "world": "meadow"})


func _hosting() -> void:
	var t := UI.label("You're hosting! 🎉 Friends press Play Together and pick \"%s's playground\". Or they can type: %s" % [Settings.player_name, game.net.address_text()], 17)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(t)
	_players(game.net.players_snapshot())
	var lock := CheckBox.new()
	lock.text = "Friends can change the world, clear everything and undo"
	lock.button_pressed = game.world.allow_world_actions
	lock.focus_mode = Control.FOCUS_NONE
	lock.toggled.connect(func(on): game.world.allow_world_actions = on)
	add_child(lock)
	_emotes()
	var stop := UI.button("Stop hosting", UI.BAD.darkened(0.3), 16)
	stop.pressed.connect(func():
		game.stop_hosting()
		build())
	add_child(stop)


func _joined() -> void:
	add_child(UI.label("You're in a friend's playground. Everything you do, they see!", 17))
	_players(game.net.players)
	_emotes()
	var leave := UI.button("Leave", UI.BAD.darkened(0.3), 16)
	leave.pressed.connect(func(): game.leave())
	add_child(leave)


func _players(list: Array) -> void:
	add_child(UI.title("Playing now", 18))
	for p in list:
		var h := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.color = p.get("col", Color.WHITE)
		h.add_child(dot)
		h.add_child(UI.label("  " + String(p.get("name", "?")) + ("  (host)" if int(p.get("id", 0)) == 1 else ""), 17))
		add_child(h)


func _emotes() -> void:
	add_child(UI.title("Say hi!", 18))
	var row := HBoxContainer.new()
	for i in NetCommon.EMOJI.size():
		var b := UI.button(NetCommon.EMOJI[i], UI.PANEL2, 24, 52)
		var id := i
		b.pressed.connect(func():
			if game and game.net:
				game.net.emote(id)
				Sfx.play("pop", null, 0.5, 1.3))
		row.add_child(b)
	add_child(row)

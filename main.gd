extends Node
## Entry point: shows the title screen, starts games (solo, hosting, joining).
## Developer flags (after `--`):
##   --world=meadow       jump straight into a world
##   --shot=path.png      save a screenshot and quit (with --shot-delay=seconds)
##   --scenario=name      set up a test scene (see Scenarios)
##   --host / --join=ip   start a network game directly
##   --battle3d           3D Battle (with --scenario, --surprise=seed, --history=id, --map, --rules=k:v,...,
##                        --play[=kind] to play a fighter, --fp for first person, --open=rules|saves|help|history,
##                        --host3d to share it, --join3d=ip to join one)

var game: Node = null
var menu: Node = null
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_window().title = "Wiggle Works"
	if args.has("sfx-check"):
		# packaging check: are the sounds inside the exported app?
		print("sfx loaded: %d, music: %s" % [Sfx._streams.size(), Sfx._music.stream != null if Sfx._music else false])
		get_tree().quit()
		return
	if args.has("test"):
		# headless test suites run inside the real game so autoloads exist
		add_child(load("res://tests/test_%s.gd" % args.test).new())
		return
	if args.has("battle3d"):
		start_battle3d({"scenario": String(args.get("scenario", "")), "rules": String(args.get("rules", "")),
			"open": String(args.get("open", "")), "surprise": int(args.get("surprise", "0")), "map": String(args.get("map", "")),
			"play": String(args.get("play", "")), "fp": args.has("fp"), "history": String(args.get("history", "")),
			"net": "host" if args.has("host3d") else ("client" if args.has("join3d") else ""), "ip": String(args.get("join3d", ""))})
	elif not args.has("menu") and (args.has("world") or args.has("shot") or args.has("host") or args.has("join")):
		start_game({"world": String(args.get("world", Settings.last_world)),
			"mode": "host" if args.has("host") else ("client" if args.has("join") else "solo"),
			"ip": String(args.get("join", "")), "scenario": String(args.get("scenario", "")),
			"open": String(args.get("open", ""))})
	else:
		show_menu()
	if args.has("shot"):
		_shoot(String(args.shot), float(args.get("shot-delay", "2.5")))


func _exit_tree() -> void:
	Preview.clear()


func show_menu() -> void:
	if game:
		game.queue_free()
		game = null
	Engine.time_scale = 1.0
	PhysicsServer2D.set_active(true)
	menu = load("res://ui/menu.gd").new()
	menu.main = self
	add_child(menu)


## The 3D isometric battle mode (battle3d/). Its root script has `main` and `begin(opts)`.
func start_battle3d(opts: Dictionary) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if game:
		game.queue_free()
	Engine.time_scale = 1.0
	PhysicsServer2D.set_active(true)
	game = load("res://battle3d/battle3d.gd").new()
	game.main = self
	add_child(game)
	game.begin(opts)


func start_game(opts: Dictionary) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if game:
		game.queue_free()
	game = Game.new()
	game.main = self
	add_child(game)
	game.begin(opts)


func _shoot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if ProjectSettings.get_setting("rendering/viewport/hdr_2d", false):
		# HDR viewports hand back linear, half-float colors
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	img.save_png(path)
	print("saved screenshot ", path)
	get_tree().quit()

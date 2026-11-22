extends Node
## Switching between the title menu, the 3D battle and the 2D sandbox, the way
## a player does it: the 3D mode changes physics settings while it's open, and
## the 2D game must get them back. Then what carries on across every mode:
## the sound and music levels, the music loop, and sticker progress being saved.
## godot --headless --path . -- --test=modes

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find_button(n: Node, text: String) -> Button:
	if n is Button and text in (n as Button).text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


func _ready() -> void:
	await get_tree().process_frame
	var main := get_parent()
	var tps := Engine.physics_ticks_per_second
	var interp := get_tree().physics_interpolation

	print("menu → 3D battle")
	main.show_menu()
	await frames(5)
	var btn := _find_button(main.menu, "3D Battle")
	check(btn != null, "the title menu has a 3D Battle button")
	if btn == null:
		_done()
		return
	btn.pressed.emit()
	await frames(30)
	check(main.game is B3Battle, "it opens the 3D battle")
	check(main.menu == null or not is_instance_valid(main.menu) or main.menu.is_queued_for_deletion(), "and closes the menu")
	var b: B3Battle = main.game
	b.spawn_unit("soldier", "red", Vector3(-6, 0, 0))
	b.spawn_unit("knight", "blue", Vector3(6, 0, 0))
	b.toggle_play()
	await frames(120)
	b.set_slowmo(true)
	b.set_paused(true)

	print("3D → menu (while paused and in slow motion)")
	b.leave()
	await frames(10)
	check(main.menu != null and is_instance_valid(main.menu), "🏠 goes back to the title menu")
	check(main.game == null or not is_instance_valid(main.game), "and closes the 3D battle")
	check(Engine.time_scale == 1.0, "time runs normally again")
	check(Engine.physics_ticks_per_second == tps, "physics speed is back to %d per second (%d)" % [tps, Engine.physics_ticks_per_second])
	check(get_tree().physics_interpolation == interp, "and smoothing is put back")

	print("menu → 2D sandbox")
	var play := _find_button(main.menu, "Play")
	check(play != null, "the menu's Play button is there")
	main.start_game({"world": "battle", "mode": "solo"})
	await frames(240)
	var w: World = main.game.world
	var fs := w.fighters()
	var ok := fs.size() > 0
	for f in fs:
		if not f.center().is_finite() or not w.bounds.has_point(f.center()):
			ok = false
	check(ok, "Battle Valley loads with its two armies (%d fighters)" % fs.size())
	w.battle_on = true
	var t := 0
	while w.last_winner == "" and t < 120 * 60:
		await get_tree().physics_frame
		t += 1
	check(w.last_winner != "", "and the 2D battle still plays out (%s won after %.0f s)" % [w.last_winner, t / float(Engine.physics_ticks_per_second)])

	print("2D → 3D → 2D again")
	main.start_battle3d({"scenario": "skirmish"})
	await frames(60)
	check(main.game is B3Battle and main.game.units.size() > 4, "a 3D scenario starts from inside the 2D game (%d fighters)" % main.game.units.size())
	main.game.leave()
	await frames(10)
	main.start_game({"world": "canvas", "mode": "solo"})
	await frames(30)
	check(Engine.physics_ticks_per_second == tps and Engine.time_scale == 1.0, "and leaving puts the settings back again")
	await _sound_and_settings()
	_done()


func _sound_and_settings() -> void:
	print("sound, music and saved progress")
	var sfx_bus := AudioServer.get_bus_index(Sfx.SFX_BUS)
	var music_bus := AudioServer.get_bus_index(Sfx.MUSIC_BUS)
	check(sfx_bus > 0 and music_bus > 0 and AudioServer.get_bus_send(sfx_bus) == &"Master" and AudioServer.get_bus_send(music_bus) == &"Master",
		"sound effects and music each have their own bus")
	Sfx.set_volume(1.0)
	Sfx.set_music(1.0)
	var music_db := AudioServer.get_bus_volume_db(music_bus)
	Sfx.set_volume(0.1)
	check(AudioServer.get_bus_volume_db(sfx_bus) < -15.0 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_db) and is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0),
		"turning 🔊 Sound down leaves the music as loud as it was")
	Sfx.set_music(0.1)
	check(AudioServer.get_bus_volume_db(music_bus) < music_db - 15.0 and AudioServer.get_bus_volume_db(sfx_bus) < -15.0 and AudioServer.get_bus_volume_db(sfx_bus) > -25.0,
		"and turning 🎵 Music down leaves the sound effects alone")
	Sfx.set_volume(Settings.volume)
	Sfx.set_music(Settings.music)
	var m: AudioStreamWAV = load("res://audio/music/wiggle_loop.wav")
	Sfx.loop_whole(m)
	var loop_sec := (m.loop_end - m.loop_begin) / float(m.mix_rate)
	check(m.loop_mode == AudioStreamWAV.LOOP_FORWARD and m.get_length() > 30.0 and absf(loop_sec - m.get_length()) < 0.01,
		"the music loops all the way through (%.1f s of %.1f s)" % [loop_sec, m.get_length()])
	check(not Sfx.too_soon("thud", 100000) and Sfx.too_soon("thud", 100010) and not Sfx.too_soon("thud", 100050) and not Sfx.too_soon("clink", 100051),
		"a bumping pile plays each thud at most every 35 ms (other bumps aren't held up)")
	check(not Sfx.too_soon("boom", 100000) and not Sfx.too_soon("boom", 100001), "other sounds aren't held back")

	# a sticker half-way done is still half-way done next time
	var keep_testing := Settings.testing
	var keep_counter = Settings.counters.get("test_jumps")
	var path := "user://test_settings.cfg"
	Settings.file = path
	Settings.testing = false
	Settings.count("test_jumps", "test_sticker", 10)
	check(Settings.unsaved(), "counting toward a sticker asks for a save")
	await get_tree().create_timer(Settings.SAVE_DELAY + 0.5).timeout
	var c := ConfigFile.new()
	var saved: Dictionary = c.get_value("play", "counters", {}) if c.load(path) == OK else {}
	check(not Settings.unsaved() and int(saved.get("test_jumps", 0)) == int(Settings.counters.test_jumps),
		"and the count is saved a moment later, before the sticker is earned (%s)" % saved.get("test_jumps", "not saved"))
	Settings.count("test_jumps", "test_sticker", 10)
	Settings._exit_tree()    # as if the game closed right away
	c = ConfigFile.new()
	saved = c.get_value("play", "counters", {}) if c.load(path) == OK else {}
	check(not Settings.unsaved() and int(saved.get("test_jumps", 0)) == int(Settings.counters.test_jumps),
		"and when the game closes before that, it's saved on the way out")
	Settings.testing = keep_testing
	Settings.file = Settings.PATH
	if keep_counter == null:
		Settings.counters.erase("test_jumps")
	else:
		Settings.counters.test_jumps = keep_counter
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _done() -> void:
	print("test_modes: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

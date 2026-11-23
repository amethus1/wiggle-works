extends TestBase
## Switching between the title menu, the 3D battle and the 2D sandbox, the way
## a player does it: the 3D mode changes physics settings while it's open, and
## the 2D game must get them back. Then what carries on across every mode:
## the sound and music levels, the music loop, and sticker progress being saved.
## godot --headless --path . -- --test=modes


## (frames() waits physics steps here: the playground's clock)
func _init() -> void:
	frames_are_steps = true


## Waits `sec` real seconds (slow motion or not).
func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


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
	await _title_screen(main)
	await wait(0.6)
	check(Sfx.mood == "title" and Sfx.track() == "wiggle_loop", "🎵 the title menu has the title tune (%s)" % Sfx.track())
	var btn := _find_button(main.menu, "3D Battle")
	check(btn != null, "the title menu has a 3D Battle button")
	if btn == null:
		finish()
		return
	btn.pressed.emit()
	await frames(30)
	check(main.game is B3Battle, "it opens the 3D battle")
	check(main.menu == null or not is_instance_valid(main.menu) or main.menu.is_queued_for_deletion(), "and closes the menu")
	var b: B3Battle = main.game
	var me: B3Unit = b.spawn_unit("soldier", "red", Vector3(-6, 0, 0))
	b.spawn_unit("knight", "blue", Vector3(6, 0, 0))
	await wait(0.6)
	check(Sfx.mood == "build" and Sfx.track() == "ready_loop", "🎵 setting up a 3D battle has the getting-ready tune (%s)" % Sfx.track())
	await _hearing_3d(b, me)
	b.toggle_play()
	await frames(120)
	await wait(0.4)
	check(Sfx.mood == "battle" and Sfx.track() == "battle_loop", "🎵 and Fight! changes it to the battle tune (%s)" % Sfx.track())
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
	check(Sfx.mood == "sandbox" and Sfx.track() == "calm_loop", "🎵 the 2D sandbox has the calm tune (%s)" % Sfx.track())
	# fair ground: the left (red) and right (blue) sides are mirror images
	var space := w.get_world_2d().direct_space_state
	var worst := 0.0
	var found := 0
	for x in [300.0, 420.0, 600.0, 760.0, 1300.0, 1600.0]:
		var ys := []
		for sx in [-x, x]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(sx, -800), Vector2(sx, 1400)))
			if not hit.is_empty() and hit.collider is StaticBody2D:
				ys.append(hit.position.y)
		if ys.size() == 2:
			found += 1
			worst = maxf(worst, absf(ys[0] - ys[1]))
	check(found == 6 and worst < 3.0, "and its ground is the same height on both sides (%d spots, %.1f px apart at most)" % [found, worst])
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
	await _wave_music()
	main.start_game({"world": "canvas", "mode": "solo"})
	await frames(30)
	check(Engine.physics_ticks_per_second == tps and Engine.time_scale == 1.0, "and leaving puts the settings back again")
	# a new 3D battle started while the old one is still closing (both alive
	# for a moment): leaving still gives the game its own physics speed back
	main.start_battle3d({"scenario": "skirmish"})
	await frames(5)
	main.start_battle3d({"scenario": "skirmish"})
	await frames(10)
	main.start_game({"world": "canvas", "mode": "solo"})
	await frames(30)
	check(Engine.physics_ticks_per_second == tps and get_tree().physics_interpolation == interp,
		"one 3D battle straight after another, then back to 2D: physics speed and smoothing are put back (%d per second)" % Engine.physics_ticks_per_second)
	await _hud_2d(main)
	await _sound_and_settings()
	await _music_fades(main)
	finish()


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
	for f: String in Sfx.MOODS.values():
		var path := "res://audio/music/%s.wav" % f
		var m: AudioStreamWAV = load(path)
		Sfx.loop_whole(m)
		var loop_sec := (m.loop_end - m.loop_begin) / float(m.mix_rate)
		var seam := _seam(path)
		check(m.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop_sec > 24.0 and m.get_length() - loop_sec < 0.1
			and seam.size() == 7 and seam[4] == m.loop_begin and seam[5] == m.loop_end,
			"the music loops all the way through: %s (%.1f s of %.1f s, the loop points are in the file)" % [f, loop_sec, m.get_length()])
		check(seam.size() == 7 and seam[0] <= seam[1] and seam[2] <= seam[3] and seam[6],
			"   ...and its samples run on smoothly from the end back to the start (step %d, normal up to %d; slope change %d, normal up to %d)"
			% (seam.slice(0, 4) if seam.size() == 7 else [-1, -1, -1, -1]))
		var mixed := await _mixed_seam(m, path)
		check(mixed.size() == 2 and mixed[0] <= maxf(mixed[1], 0.02),
			"   ...and Godot plays it across the seam with no click (off by %.4f there, %.4f elsewhere)" % (mixed if mixed.size() == 2 else [-1.0, -1.0]))
	check(not Sfx.too_soon("thud", 100000) and Sfx.too_soon("thud", 100010) and not Sfx.too_soon("thud", 100050) and not Sfx.too_soon("clink", 100051),
		"a bumping pile plays each thud at most every 35 ms (other bumps aren't held up)")
	check(not Sfx.too_soon("victory", 100000) and not Sfx.too_soon("victory", 100001) and not Sfx.too_soon("click", 100001),
		"jingles and clicks are never held back")
	check(not Sfx.too_soon("gun_mg", 300000) and Sfx.too_soon("gun_mg", 300010) and not Sfx.too_soon("gun_mg", 300040)
		and not Sfx.too_soon("boom", 300000) and Sfx.too_soon("boom", 300040) and not Sfx.too_soon("boom", 300100)
		and not Sfx.too_soon("gun_rifle", 300041),
		"gunfire and booms have a gap too (machine gun %d ms, boom %d ms), each its own" % [Sfx.gap_ms("gun_mg"), Sfx.gap_ms("boom")])
	check(not Sfx.too_soon("thud", 200000, 0.15) and not Sfx.too_soon("thud", 200010, 0.9) and Sfx.too_soon("thud", 200020, 0.9),
		"a far-away thud doesn't hold up one right next to you (the gap goes by how loud they are here)")
	_buses()
	_panning()
	await _voices()

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
	# settings are saved safely: into a .tmp file first, then moved over the old one
	check(not FileAccess.file_exists(path + ".tmp"), "a save leaves nothing half-written behind")
	# 🌊 the best wave used to have a file of its own: it moves in, once
	var keep_best := Settings.b3_wave_best
	var old := "user://test_old_waves.cfg"
	var oc := ConfigFile.new()
	oc.set_value("waves", "best", 7)
	oc.save(old)
	Settings.b3_wave_best = 3
	Settings._migrate_waves(old)
	c = ConfigFile.new()
	check(Settings.b3_wave_best == 7 and c.load(path) == OK and int(c.get_value("battle3d", "wave_best", 0)) == 7
		and not FileAccess.file_exists(old) and FileAccess.file_exists(old + ".old"),
		"🌊 the best wave moves in from its old file and is saved (the old file is kept as .old)")
	DirAccess.rename_absolute(path, path + ".tmp")   # (as if the game stopped half-way through moving the new file in)
	Settings.b3_wave_best = 0
	Settings.load_settings()
	check(Settings.b3_wave_best == 7 and FileAccess.file_exists(path), "and settings cut off half-way through a save still load")
	Settings.b3_wave_best = keep_best
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old + ".old"))
	Settings.testing = keep_testing
	Settings.file = Settings.PATH
	if keep_counter == null:
		Settings.counters.erase("test_jumps")
	else:
		Settings.counters.test_jumps = keep_counter
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The 16-bit samples and loop points ('smpl' chunk) of WAV file `path`
## (a loop's own file, as tools/gen_audio.py wrote it): [samples, begin, end].
func _wav(path: String) -> Array:
	var f := FileAccess.get_file_as_bytes(path)
	var off := 12
	var x := PackedInt32Array()
	var begin := -1
	var end := -1
	while off + 8 <= f.size():
		var id := f.slice(off, off + 4).get_string_from_ascii()
		var sz := f.decode_u32(off + 4)
		if id == "data":
			x.resize(mini(sz, f.size() - off - 8) / 2)
			for i in x.size():
				x[i] = f.decode_s16(off + 8 + 2 * i)
		elif id == "smpl" and sz >= 60:
			begin = f.decode_u32(off + 8 + 44)
			end = f.decode_u32(off + 8 + 48)
		off += 8 + sz + (sz & 1)
	return [x, begin, end]


## [step from the loop's last sample to its first, 99.9th percentile of all
## steps, slope change there, 99.9th percentile of those, loop begin, loop
## end, the bits before and after the loop are copies of its other end].
func _seam(path: String) -> Array:
	var w := _wav(path)
	var x: PackedInt32Array = w[0]
	var b: int = w[1]
	var e: int = w[2]
	if b < 0 or e <= b + 1000 or e > x.size():
		return []
	var steps := PackedInt32Array()
	var bends := PackedInt32Array()
	for i in range(b + 1, e - 1, 7):
		steps.append(absi(x[i + 1] - x[i]))
		bends.append(absi(x[i + 1] - 2 * x[i] + x[i - 1]))
	steps.sort()
	bends.sort()
	var copies := x.slice(0, b) == x.slice(e - b, e) and x.slice(e) == x.slice(b, b + x.size() - e)
	return [absi(x[b] - x[e - 1]), steps[int(steps.size() * 0.999)], absi(x[b] - 2 * x[e - 1] + x[e - 2]),
		bends[int(bends.size() * 0.999)], b, e, copies]


## Plays loop `m` through Godot's mixer from just before its end, across the
## seam, and compares what comes out with the loop's own samples (`path`,
## stepped through at the mixer's rate). [biggest difference near the seam,
## biggest difference elsewhere]: a click at the seam would stand out.
func _mixed_seam(m: AudioStreamWAV, path: String) -> Array:
	var w := _wav(path)
	var x: PackedInt32Array = w[0]
	var b := m.loop_begin
	var e := m.loop_end
	var bus_name := "Test seam"
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(AudioServer.bus_count - 1, cap)
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	p.stream = m
	add_child(p)
	await get_tree().process_frame
	var rate := AudioServer.get_mix_rate()
	var step := m.mix_rate / rate
	var s0 := e - 2205                         # 0.1 s before the loop's end
	cap.clear_buffer()
	p.play(s0 / float(m.mix_rate))
	await wait(0.35)
	var frames := cap.get_buffer(cap.get_frames_available())
	p.stop()
	p.queue_free()
	await get_tree().process_frame
	AudioServer.remove_bus(AudioServer.get_bus_index(bus_name))
	var y := PackedFloat32Array()
	for fr in frames:
		y.append(fr.x)
	var start := 0
	while start < y.size() and absf(y[start]) < 1e-5:
		start += 1
	var n := mini(int(0.25 * rate), y.size() - start - 40)
	if n < int(0.15 * rate):
		return []
	var ref := PackedFloat32Array()
	ref.resize(n)
	for k in n:
		var pos := s0 + k * step
		if pos >= e:
			pos -= e - b
		var i := int(pos)
		var t := pos - i
		ref[k] = (x[i] * (1.0 - t) + x[i + 1] * t) / 32767.0
	var best := INF
	var shift := 0
	for d in range(-30, 31):
		var err := 0.0
		for k in range(100, 2100):
			var j := start + d + k
			err += INF if j < 0 or j >= y.size() else pow(y[j] - ref[k], 2)
		if err < best:
			best = err
			shift = d
	var seam_k := int((e - s0) / step)
	var near := 0.0
	var far := 0.0
	for k in range(100, n):
		var j := start + shift + k
		if j >= y.size():
			break
		var diff := absf(y[j] - ref[k])
		if absi(k - seam_k) < 60:
			near = maxf(near, diff)
		else:
			far = maxf(far, diff)
	return [near, far]


## Master's limiter, the separate buses and the panning buses.
func _buses() -> void:
	var lim: AudioEffectHardLimiter = null
	for i in AudioServer.get_bus_effect_count(0):
		var fx := AudioServer.get_bus_effect(0, i)
		if fx is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(0, i):
			lim = fx as AudioEffectHardLimiter
	check(lim != null and lim.ceiling_db <= -0.5, "Master has a limiter, so a 24-voice battle can't clip (ceiling %.1f dB)" % (lim.ceiling_db if lim else 0.0))
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	check(layout != null and layout.get("bus/0/effect/0/effect") is AudioEffectHardLimiter and String(layout.get("bus/1/name")) == Sfx.SFX_BUS
		and String(layout.get("bus/2/name")) == Sfx.MUSIC_BUS, "default_bus_layout.tres has the limiter and the Sound and Music buses")
	var sfx_bus := AudioServer.get_bus_index(Sfx.SFX_BUS)
	var pans := 0
	for side in [-1, 1]:
		for k in range(1, Sfx.PAN_STEPS + 1):
			var i := AudioServer.get_bus_index(Sfx.pan_bus(side * k * Sfx.PAN_MAX / Sfx.PAN_STEPS))
			if i > sfx_bus and AudioServer.get_bus_send(i) == StringName(Sfx.SFX_BUS) and AudioServer.get_bus_effect_count(i) > 0:
				var pn := AudioServer.get_bus_effect(i, 0) as AudioEffectPanner
				if pn != null and signf(pn.pan) == side:
					pans += 1
	check(pans == 2 * Sfx.PAN_STEPS and Sfx.pan_bus(0.0) == Sfx.SFX_BUS,
		"panned sounds go left or right through little buses into SFX (%d), so 🔊 Sound still turns them all down" % pans)


## Panning: 2D by where it is across the screen.
func _panning() -> void:
	var w := 1440.0
	var mid := Sfx.hear2d(Vector2(0, 200), Vector2.ZERO, 1.0, w)
	var r := Sfx.hear2d(Vector2(600, 0), Vector2.ZERO, 1.0, w)
	var l := Sfx.hear2d(Vector2(-600, 0), Vector2.ZERO, 1.0, w)
	var r_out := Sfx.hear2d(Vector2(600, 0), Vector2.ZERO, 0.4, w)
	var far := Sfx.hear2d(Vector2(6000, 0), Vector2.ZERO, 1.0, w)
	check(absf(mid.y) < 0.01 and r.y > 0.3 and l.y < -0.3 and r_out.y > 0.0 and r_out.y < r.y * 0.6,
		"2D: a sound on the right of the screen is in the right speaker, on the left in the left (%.2f / %.2f; zoomed out %.2f)" % [r.y, l.y, r_out.y])
	check(mid.x > 0.99 and far.x < 0.2 and absf(far.y - Sfx.PAN_MAX) < 0.01, "and far away it's quieter (%.2f)" % far.x)


func _busy() -> int:
	var n := 0
	for i in Sfx.POOL:
		if Sfx.voice_sound(i) != "":
			n += 1
	return n


func _quiet() -> void:
	for p in Sfx._players:
		p.stop()


## The voice pool, played for real (headless runs make no sound, but the voices still play).
func _voices() -> void:
	print("voices")
	var was := Sfx.enabled
	Sfx.wake()
	check(Sfx.has("defeat") and Sfx.has("nuke") and Sfx._players.size() == Sfx.POOL,
		"every sound loads (the new 🥺 defeat one too), with %d voices" % Sfx._players.size())
	var missing: Array[String] = []
	for n: String in Sfx.PRIORITY.keys() + Sfx.FALLBACK.keys() + Sfx.GAP_MS.keys():
		if not Sfx.has(n):
			missing.append(n)
	for n: String in Sfx.FALLBACK:
		if not Sfx.has(String(Sfx.FALLBACK[n][0])):
			missing.append("%s's stand-in" % n)
	check(missing.is_empty(), "every sound named in Sfx has its own file, and a stand-in in case it goes missing %s" % [missing])
	# a sound whose file is missing plays its stand-in (as it did before it had its own)
	var own: AudioStream = Sfx._streams.get("chute_open")
	Sfx._streams.erase("chute_open")
	Sfx._played_this_frame.clear()
	var fb := Sfx.play_timed("chute_open", null, 1.0, 1.0, 0.0, 400000)
	check(fb >= 0 and Sfx.voice_sound(fb) == "whoosh" and absf(Sfx._players[fb].pitch_scale / 1.6 - 1.0) <= Sfx.JITTER + 0.001,
		"a sound with no file plays its stand-in (chute_open: %s)" % (Sfx.voice_sound(fb) if fb >= 0 else "nothing"))
	Sfx._streams["chute_open"] = own
	_quiet()
	var some: Array[bool] = [true, false, true]
	var all: Array[bool] = [true, true, true]
	check(Sfx.pick_voice(some, PackedInt32Array([3, 0, 0]), PackedInt64Array([5, 5, 5]), 0) == 1, "a free voice is used first")
	check(Sfx.pick_voice(all, PackedInt32Array([3, 1, 1]), PackedInt64Array([5, 9, 4]), 1) == 2
		and Sfx.pick_voice(all, PackedInt32Array([3, 1, 0]), PackedInt64Array([5, 1, 9]), 1) == 2
		and Sfx.pick_voice(all, PackedInt32Array([3, 2, 1]), PackedInt64Array([5, 9, 9]), 0) == -1
		and Sfx.pick_voice(all, PackedInt32Array([3, 3, 3]), PackedInt64Array([5, 2, 9]), 3) == 1,
		"all busy: the least important one, ending soonest, gives way (never a more important one)")
	_quiet()
	Sfx._cooldown.clear()
	Sfx._cool_vol.clear()
	Sfx._played_this_frame.clear()
	var t := 500000
	var top := {}
	for n in ["nuke", "victory", "defeat", "roar", "sticker"]:
		top[n] = Sfx.play_timed(n, null, 1.0, 1.0, 0.0, t)
	var storm := ["gun_mg", "gun_rifle", "gun_pistol", "gun_shotgun", "gun_laser", "gun_sniper", "bow", "punch", "stomp", "thud", "hop"]
	var most := 0
	for k in 40:
		t += 45
		Sfx._played_this_frame.clear()
		for n: String in storm:
			Sfx.play_timed(n, null, 1.0, 1.0, 0.0, t)
		most = maxi(most, _busy())
	var kept := func() -> bool:
		for n: String in top:
			if int(top[n]) < 0 or Sfx.voice_sound(int(top[n])) != n:
				return false
		return true
	check(most == Sfx.POOL and kept.call(),
		"🔫 gunfire and footsteps on all %d voices never cut off the nuke, victory, 🥺 defeat, roar or sticker" % most)
	t += 45
	Sfx._played_this_frame.clear()
	for n: String in storm:
		Sfx.play_timed(n, null, 1.0, 1.0, 0.0, t)
	var full := _busy() == Sfx.POOL
	var hop := Sfx.play_timed("hop", null, 1.0, 1.0, 0.0, t + 1)
	check(full and hop == -1, "with every voice busy with more important sounds, a little hop just doesn't play")
	var was_on := Sfx.voice_sound(Sfx.pick_voice(_busy_list(), Sfx._prio, Sfx._ends, Sfx.P_TOP))
	var click := Sfx.play_timed("click", null, 0.4, 1.3, 0.0, t + 1)
	check(click >= 0 and Sfx.priority(was_on) < Sfx.P_TOP and kept.call(), "...but a click takes a gunshot's voice (%s), not the nuke's" % was_on)
	# the UI and jingles keep their pitch; bumps wobble
	var steady := true
	for k in 4:
		_quiet()
		t += 50
		Sfx._played_this_frame.clear()      # (as if a frame went by)
		for n in ["click", "ding", "sticker", "victory", "defeat", "battle_start"]:
			var i := Sfx.play_timed(n, null, 0.5, 1.3, 0.0, t)
			if i < 0 or not is_equal_approx(Sfx._players[i].pitch_scale, 1.3):
				steady = false
	check(steady, "clicks and jingles keep the pitch they're asked for (a wobble would put them out of tune)")
	var pitches := {}
	for k in 8:
		_quiet()
		t += 50
		Sfx._played_this_frame.clear()
		var i := Sfx.play_timed("thud", null, 0.5, 1.0, 0.0, t)
		if i >= 0:
			pitches[snappedf(Sfx._players[i].pitch_scale, 0.0001)] = true
	check(pitches.size() >= 3, "bumps still wobble a little each time (%d different pitches)" % pitches.size())
	# where a 2D sound plays from (by screen x) and how loud
	_quiet()
	Sfx.listener_pos = Vector2.ZERO
	Sfx.listener_zoom = 1.0
	Sfx._played_this_frame.clear()
	var r := Sfx.play_timed("pop", Vector2(600, 0), 1.0, 1.0, 0.0, t)
	var l := Sfx.play_timed("pop", Vector2(-600, 0), 1.0, 1.0, 0.0, t)
	var c := Sfx.play_timed("poof", Vector2(0, 100), 1.0, 1.0, 0.0, t)
	check(r >= 0 and l >= 0 and c >= 0 and String(Sfx._players[r].bus).begins_with("SFX R") and String(Sfx._players[l].bus).begins_with("SFX L")
		and String(Sfx._players[c].bus) == Sfx.SFX_BUS, "and a pop on the right plays on the right (%s), one on the left on the left (%s)"
		% [Sfx._players[r].bus if r >= 0 else "-", Sfx._players[l].bus if l >= 0 else "-"])
	_quiet()
	Sfx.enabled = was


func _busy_list() -> Array[bool]:
	var out: Array[bool] = []
	for p in Sfx._players:
		out.append(p.playing)
	return out


## 🎵 The music crossfades from one tune to the next as you go about.
func _music_fades(main: Node) -> void:
	print("music crossfades")
	var was := Sfx.enabled
	Sfx.wake()        # (makes the music players in a headless run: they play, silently)
	Sfx.set_music(0.45)
	await wait(Sfx.XFADE + 0.5)
	var calm: AudioStreamPlayer = Sfx._music
	check(Sfx.mood == "sandbox" and calm.playing and calm.stream == Sfx._loops.get("calm_loop") and Sfx.music_gain(Sfx._cur) > 0.99,
		"🎵 the calm tune is playing in the sandbox")
	main.show_menu()
	await wait(Sfx.MOOD_HOLD + 0.55)
	var g_new := Sfx.music_gain(Sfx._cur)
	var g_old := Sfx.music_gain(1 - Sfx._cur)
	check(Sfx._music != calm and Sfx._music.stream == Sfx._loops.get("wiggle_loop") and calm.playing and g_new > 0.05 and g_new < 0.95 and g_old > 0.05 and g_old < 0.95,
		"🏠 back to the title: its tune fades in while the calm one fades out (%.2f in, %.2f out)" % [g_new, g_old])
	check(absf(Sfx._fade_db(0.5) - linear_to_db(sqrt(0.5))) < 0.1, "(halfway, both at 71%%: the loudness stays even)")
	await wait(Sfx.XFADE + 0.3)
	check(not calm.playing and Sfx._music.playing and Sfx.music_gain(Sfx._cur) > 0.99, "and then only the title tune plays")
	Sfx.set_music(0.0)
	check(not Sfx._mus[0].playing and not Sfx._mus[1].playing, "🎵 Music all the way down stops it")
	Sfx.set_music(0.45)
	check(Sfx._music.playing and Sfx._music.stream == Sfx._loops.get("wiggle_loop"), "and turning it up again starts the tune for where you are")
	# quiet again before the run ends (sounds still playing at exit count as leaks)
	Sfx.set_music(0.0)
	_quiet()
	Sfx.enabled = was
	await wait(0.3)


## 🌊 Wave Defense: the battle tune while a wave comes, the getting-ready one in the break.
func _wave_music() -> void:
	var main := get_parent()
	main.start_battle3d({"scenario": "waves"})
	await frames(60)
	var b: B3Battle = main.game
	await wait(0.6)
	var phase := String(b.modes.phase) if b.modes else "-"
	check(b.modes != null and b.modes.kind == "waves" and phase == "wave" and Sfx.mood == "battle",
		"🌊 Wave Defense: a wave coming has the battle tune (%s, %s)" % [phase, Sfx.mood])
	for u: B3Unit in b.units.duplicate():
		if is_instance_valid(u) and not u.dead and u.team == "blue":
			u.hurt(99999.0, Vector3.UP, 1.0, null, "blast")
	var guard := 0
	while b.modes.phase != "break" and guard < 600:
		await get_tree().physics_frame
		guard += 1
	await wait(0.6)
	check(b.modes.phase == "break" and Sfx.mood == "build", "and the break between waves has the getting-ready tune (%s, %s)" % [b.modes.phase, Sfx.mood])
	b.leave()
	await frames(10)


## Hearing in 3D: overhead from the middle of the view, first person from your eyes.
func _hearing_3d(b: B3Battle, me: B3Unit) -> void:
	print("hearing in 3D")
	var ear := b.cam.focus
	ear.y = b.world.height_at(ear.x, ear.z)
	var right := b.cam.basis_now().x
	var here := b.hear(ear)
	var r := b.hear(ear + right * 15.0)
	var l := b.hear(ear - right * 15.0)
	var up := b.hear(ear + Vector3(0, 40, 0))
	var over20 := b.hear(ear + Vector3(20, 0, 0)).x
	check(here.x > 0.99 and absf(here.y) < 0.01 and r.y > 0.2 and l.y < -0.2,
		"overhead: the middle of the view is loud, a sound on the right is panned right and on the left left (%.2f / %.2f)" % [r.y, l.y])
	check(up.x < here.x - 0.2, "and a plane 40 m up is quieter than on the ground below it (%.2f): height counts" % up.x)
	b.tools.play_as(me, true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(b.cam.first_person(), "👀 playing in first person")
	if not b.cam.first_person():
		return
	var eye := b.cam.cam.global_position
	var bs := b.cam.cam.global_transform.basis
	var fwd := -bs.z
	var near := b.hear(eye + fwd * 2.0)
	var rt := b.hear(eye + bs.x * 4.0)
	var lt := b.hear(eye - bs.x * 4.0)
	var behind := b.hear(eye - fwd * 4.0)
	var far := b.hear(eye + fwd * 40.0)
	var high := b.hear(eye + Vector3.UP * 40.0)
	var fp20 := b.hear(eye + fwd * 20.0).x
	check(near.x > 0.99 and absf(near.y) < 0.05, "first person: a shot right in front of your eyes is full volume, in the middle (%.2f, %.2f)" % [near.x, near.y])
	check(rt.y > 0.3 and lt.y < -0.3 and absf(behind.y) < 0.1,
		"on your right it's in the right ear, on your left the left, behind you both (%.2f / %.2f / %.2f)" % [rt.y, lt.y, behind.y])
	check(far.x < 0.35 and absf(far.x - high.x) < 0.02, "40 m away it's much quieter, and 40 m straight up just the same (%.2f / %.2f)" % [far.x, high.x])
	check(fp20 < over20 - 0.3, "you hear from your eyes: 20 m away is quieter than from the overhead view (%.2f vs %.2f)" % [fp20, over20])
	b.tools.stop_playing()
	await get_tree().process_frame
	check(not b.cam.first_person(), "and back overhead")


# --------------------------------------------------------- title screen and 2D HUD
func _key_ev(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	return ev


func _nav(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


## The title screen: ▶ Play says where, the 2D worlds and ⚔️ 3D Battle are
## apart, 📂 Load, it scrolls, pop-ups close with Esc or a click outside, the
## Wigglies keep still behind them, keys and a gamepad work, and ⚙️ is the
## shared Settings pop-up.
func _title_screen(main: Node) -> void:
	print("the title screen")
	var m = main.menu
	var wd: Dictionary = Catalog.world_def(Settings.last_world)
	var where: Label = m.play_btn.find_child("World", true, false) if m.play_btn else null
	check(where != null and where.text.contains(String(wd.name)), "▶ Play says which world it goes to (%s)" % (where.text if where else "?"))
	var worlds: Node = m.layer.find_child("Worlds", true, false)
	var b3 := _find_button(m, "3D Battle")
	check(worlds != null and worlds.get_child_count() == Catalog.WORLDS.size() and b3 != null and not worlds.is_ancestor_of(b3)
		and b3.get_parent() != m.play_btn.get_parent(), "the %d worlds sit with ▶ Play, and ⚔️ 3D Battle has its own card" % Catalog.WORLDS.size())
	check(_find_button(m, "Load") != null, "📂 Load is on the title screen")
	check(m.layer.find_child("Scroll", true, false) is ScrollContainer, "it all scrolls if the window is short")
	# keys and a gamepad: the first arrow press lights up ▶ Play
	check(get_viewport().gui_get_focus_owner() == null, "(nothing has focus to start with)")
	m._input(_nav("ui_down"))
	check(get_viewport().gui_get_focus_owner() == m.play_btn, "an arrow key (or the gamepad) puts the ring on ▶ Play")
	get_viewport().gui_release_focus()
	# pop-ups: Esc and a click outside close them; the Wigglies keep still behind
	m._settings()
	await frames(2)
	for w: Wiggly in m.world.wigglies():
		w.squash_t = 0.0
	m._hop_t = -1.0
	m._process(0.016)
	var still := true
	for w: Wiggly in m.world.wigglies():
		still = still and w.squash_t <= 0.0
	check(still, "the Wigglies behind a pop-up keep still (and quiet)")
	var sp: Node = null
	for c in m.modal.find_children("*", "HBoxContainer", true, false):
		if c is SettingsPanel:
			sp = c
	check(sp != null and sp.find_child("Fullscreen", true, false) != null and sp.find_child("Size", true, false) != null
		and sp.find_child("Shake", true, false) != null and sp.find_child("Smooth3D", true, false) != null and sp.find_child("Slider_music", true, false) != null
		and _all_text(sp).contains("Check for updates"), "⚙️ Me is the shared Settings: sound, music, name, color, full screen, size, shake, smooth edges, updates")
	if sp:
		var huge: Button = null
		var normal: Button = null
		for c in sp.find_child("Size", true, false).get_children():
			if (c as Button).text == "Huge":
				huge = c
			if (c as Button).text == "Normal":
				normal = c
		huge.pressed.emit()
		check(is_equal_approx(Settings.ui_scale, 1.3) and is_equal_approx(get_tree().root.content_scale_factor, 1.3), "🔍 Huge makes everything bigger")
		normal.pressed.emit()
		check(is_equal_approx(get_tree().root.content_scale_factor, 1.0), "and Normal puts it back")
		for c in sp.find_child("Shake", true, false).get_children():
			if (c as Button).text == "Off":
				(c as Button).pressed.emit()
		check(Settings.shake_2d == 0.0, "📳 screen shake can be turned off")
		Settings.shake_2d = 1.0
	m._input(_key_ev(KEY_ESCAPE))
	await frames(2)
	check(m.modal == null, "Esc closes the pop-up")
	m._stickers()
	await frames(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(4, 4)
	(m.modal as Control).gui_input.emit(ev)
	await frames(2)
	check(m.modal == null, "a click outside it closes it too")


## The 2D HUD: the Toy Box (Wigglies first, compact tabs, room for cards,
## 🔍 search, the card you're placing lit up, team letters), the bars never
## taking focus, sticker pop-ups taking turns, ❓ Help and ⚙️ / 💾.
func _hud_2d(main: Node) -> void:
	print("the 2D HUD")
	var g: Game = main.game
	var hud: HUD = g.hud
	hud.toggle_drawer("toybox", true)
	await frames(3)
	var tabs: Node = hud.drawers.toybox.find_child("Tabs", true, false)
	check(tabs != null and tabs.get_child(0).name == "Tab_Wigglies", "🫧 Wigglies is the first Toy Box tab")
	check(tabs != null and (tabs as Control).size.y < 100.0, "all %d tabs fit in two short rows (%.0f px)" % [HUD.TABS.size(), (tabs as Control).size.y if tabs else -1.0])
	hud.cat = "People"
	hud._fill_grid()
	await frames(3)
	var sc: Control = hud.grid.get_parent().get_parent()
	check(sc is ScrollContainer and sc.size.y >= 2.0 * 116.0, "with a fighter tab open there's room for at least 2 rows of cards (%.0f px)" % sc.size.y)
	# 🔌 Battle Traps get their own heading in Builds, and a badge anywhere
	hud.cat = "Builds"
	hud._fill_grid()
	await frames(2)
	var traps: Array = []
	for c in hud.trap_grid.get_children():
		if c is Card and not c.is_queued_for_deletion():
			traps.append((c as Card).id)
	var plain_trap := false
	for c in hud.grid.get_children():
		if c is Card and not c.is_queued_for_deletion() and HUD.TRAPS.has((c as Card).id):
			plain_trap = true
	check(hud.trap_head.visible and traps.size() == HUD.TRAPS.size() and not plain_trap and _all_text(hud.trap_head).contains("Battle Traps"),
		"🔌 Builds shows the Battle Traps under their own heading (%s)" % ", ".join(traps))
	var tc: Node = hud.trap_grid.get_child(hud.trap_grid.get_child_count() - 1)
	check(tc.find_child("TrapBadge", true, false) != null, "each trap card has a 🔌 badge")
	hud.cat = "Balls"
	hud._fill_grid()
	await frames(2)
	check(not hud.trap_head.visible and not hud.trap_grid.visible, "(no traps heading in other tabs)")
	check((hud.team_buttons.red as Button).text == "R" and (hud.team_buttons.wild as Button).text == "🐾", "team colours have a letter on them")
	check((hud.top_buttons.pause as Control).get_focus_mode_with_override() == Control.FOCUS_NONE
		and (hud.tool_buttons.values()[0] as Control).get_focus_mode_with_override() == Control.FOCUS_NONE
		and hud.search.get_focus_mode_with_override() == Control.FOCUS_ALL, "the bars never take focus (Space stays pause); the 🔍 box does")
	# 🔍 search
	hud.search.text = "rex"
	hud.search.text_changed.emit("rex")
	await frames(2)
	var ids: Array = []
	for c in hud.grid.get_children():
		if c is Card:
			ids.append((c as Card).id)
	check(ids.has("f:trex") and ids.size() <= 3 and hud.team_row.visible, "🔍 'rex' finds the T-Rex, with the team picker (%s)" % ", ".join(ids))
	hud.search.text = "ball"
	hud.search.text_changed.emit("ball")
	await frames(2)
	var balls := 0
	for c in hud.grid.get_children():
		if c is Card and Catalog.spawn_name((c as Card).id).to_lower().contains("ball"):
			balls += 1
	check(balls >= 4 and not hud.team_row.visible, "'ball' finds balls from every tab (%d)" % balls)
	(hud.cat_buttons.Wigglies as Button).pressed.emit()
	await frames(2)
	check(hud.search.text == "" and hud.cat == "Wigglies" and hud.grid.get_child_count() == Catalog.WIGGLY_ORDER.size(), "picking a tab stops searching")
	# the card you're placing lights up
	var first: Card = hud.grid.get_child(0)
	g.start_placing(first.id)
	check(first.placing() and not (hud.grid.get_child(1) as Card).placing(), "the card you're placing lights up")
	g.placing = ""
	hud.refresh_tools()
	# 📒 two stickers at once take turns
	hud._sticker_queue.clear()
	hud._sticker_on = false
	hud.show_sticker("hello")
	hud.show_sticker("pop")
	var pops := 0
	for c in hud.root.get_children():
		if c.name.begins_with("StickerPop"):
			pops += 1
	check(pops == 1 and hud._sticker_queue == ["pop"], "📒 two new stickers at once take turns (not on top of each other)")
	hud._next_sticker()
	check(hud._sticker_queue.is_empty(), "...and the second shows next")
	# ❓ Help
	hud.toggle_help()
	await frames(2)
	var ht := _all_text(hud.modal)
	var all_in := true
	for w in ["Fighters", "weapon", "Platform", "3D Battle", "Save", "🔍", "Battle Traps", "pressure plate", "cracks", "pond", "trampoline",
			"warp", "ice", "Pterodactyl", "Brachiosaurus", "laser sword", "paint", "blink"]:
		if not ht.contains(w):
			all_in = false
			print("    (2D help is missing '%s')" % w)
	check(all_in, "❓ Help tells about fighters, weapons, platforms, traps, combos, dinos, undo, saving and 3D Battle")
	check(hud.modal.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_ENABLED, "pop-ups take keys and a gamepad")
	hud.close_top()
	hud.show_settings()
	await frames(2)
	check(hud.modal.find_child("Smooth3D", true, false) != null, "⚙️ in the playground is the same Settings pop-up")
	hud.close_top()
	hud.show_saves()
	await frames(2)
	var slots: Node = hud.modal.find_child("Slots", true, false)
	check(slots != null and slots.get_child_count() == Saves.SLOTS, "💾 has %d slots" % Saves.SLOTS)
	hud.close_top()
	hud.toggle_drawer("toybox", false)


extends Node
## Switching between the title menu, the 3D battle and the 2D sandbox, the way
## a player does it: the 3D mode changes physics settings while it's open, and
## the 2D game must get them back.
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
	_done()


func _done() -> void:
	print("test_modes: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

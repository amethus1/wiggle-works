extends Node
## Screenshots of the menus, the Toy Boxes and the pop-ups, to check the UI
## by eye at different window sizes. Not part of the suite (it needs a window):
## godot --path . --resolution 1280x720 -- --test=uishots --out=/some/dir [--only=title,help3d]

var out := "user://uishots"
var only: PackedStringArray = []
var main: Node = null
var _n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	main = get_parent()
	await get_tree().process_frame
	Saves.delete_all_test_saves()
	# ---------------------------------------------------------------- 2D
	main.start_game({"world": "meadow", "scenario": "showcase"})
	await _wait(3.0)
	var hud: HUD = main.game.hud
	hud.toggle_drawer("toybox", true)
	hud.cat = "People"
	hud._fill_grid()
	await _shot("toybox2d")
	hud.cat = "Wigglies"
	hud._fill_grid()
	main.game.start_placing("w:zappy")
	await _shot("toybox2d_placing")
	main.game.placing = ""
	hud.search.text = "ball"
	hud._fill_grid()
	await _shot("toybox2d_search")
	hud.search.text = ""
	hud.toggle_drawer("toybox", false)
	hud.toggle_help()
	await _shot("help2d")
	hud.close_top()
	hud.show_settings()
	await _shot("settings2d")
	hud.close_top()
	hud.show_saves()
	await _wait(0.3)
	var sp: SavesPanel = hud.modal.find_child("SavesPanel", true, false)
	await hud._save_to(1, sp)
	main.game.world.load_world("candy")
	await _wait(1.5)
	await hud._save_to(2, sp)
	Saves.rename(2, "Bouncy Castle")
	sp.refresh()
	await _shot("saves2d")
	hud.close_top()
	Settings.counters["booms"] = 4
	Settings.counters["worlds"] = {"meadow": true, "candy": true, "moon": true}
	Settings.stickers = {"hello": true, "pop": true, "dino": true}
	hud.show_stickers()
	await _shot("stickers2d")
	hud.close_top()
	hud.show_sticker("splash")
	hud.show_sticker("sky")
	await _wait(0.6)
	await _shot("sticker_pop2d")
	# ------------------------------------------------------------- the menu
	main.show_menu()
	await _wait(1.5)
	await _shot("title")
	main.menu._settings()
	await _shot("settings_menu")
	main.menu.close_modal()
	main.menu._saves()
	await _shot("saves_menu")
	main.menu.close_modal()
	main.menu._stickers()
	await _shot("stickers_menu")
	main.menu.close_modal()
	# ----------------------------------------------------------------- 3D
	main.start_battle3d({"scenario": "skirmish"})
	await _wait(6.0)
	var b: B3Battle = main.game
	await _shot("toybox3d")
	b.ui.search.text = "rex"
	b.ui._fill_items()
	await _shot("toybox3d_search")
	b.ui.set_cat("people")
	b.set_paused(true)
	var reds: Array = []
	for u: B3Unit in b.units:
		if u.team == "red" and not u.dead and reds.size() < 8:
			reds.append(u)
	b.tools.set_tool("select")
	b.tools.select_many(reds)
	if not reds.is_empty():
		var r := Rect2(b.cam.screen_pos((reds[0] as B3Unit).center()), Vector2.ZERO)
		for u in reds:
			r = r.expand(b.cam.screen_pos((u as B3Unit).center()))
		b.tools._show_box(r.position - Vector2(30, 30), r.end + Vector2(30, 30))
	await _shot("multiselect3d")
	b.ui.box_rect.visible = false
	b.ui.toggle_help()
	await _shot("help3d")
	b.ui.close_top()
	b.ui._show_rules()
	await _shot("rules3d")
	b.ui.show_settings()
	await _shot("settings3d")
	b.ui.close_top()
	b.ui._show_clear_menu()
	for c in b.ui.popup.find_children("*", "Button", true, false):
		if (c as Button).text.contains("Everything"):
			(c as Button).pressed.emit()
	await _shot("confirm3d")
	b.ui.close_top()
	b.ui._show_saves()
	await _shot("saves3d")
	b.ui.close_top()
	b.ui.toggle_palette()
	await _shot("nopalette3d")
	b.ui.toggle_palette()
	# 🌊 the keep falls: the banner over the messages
	main.start_battle3d({"scenario": "waves"})
	await _wait(5.0)
	b = main.game
	b.tools.select(b.units[0] if not b.units.is_empty() else null)
	await _shot("waves3d")
	b.ui.toast("🌊 Wave 2: Stick figures and soldiers!")
	b.ui.toast("The attackers are at the keep!")
	b.ui.toast("💥 The keep fell! ⭐ Your best: wave 1")
	await _wait(0.3)
	b.ui.banner("💥 The keep fell on wave 2!", Color("ff9f43"), b.scoreboard())
	b.ui.toast("⭐ New best: wave 2!")
	await _wait(1.5)
	await _shot("defeat3d")
	Saves.delete_all_test_saves()
	print("uishots: %d saved in %s" % [_n, out])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await _wait(0.4)
	if not only.is_empty() and not only.has(name):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img = UI.srgb_image(img)      # (HDR viewports hand back linear half-floats)
	img.save_png("%s/%s.png" % [out, name])
	_n += 1
	print("  shot ", name)

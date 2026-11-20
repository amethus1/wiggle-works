extends Node
## 🔄 Updater checks that don't need the internet: comparing versions, picking
## the right download, checking a download arrived whole, swapping the game
## file (and putting it back if that fails), cleaning up, and the pop-ups.
## godot --headless --path . -- --test=update
## (tests/test_update_live.gd checks the real GitHub release, online.)

var fails := 0
const DIR := "user://update_test"


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func write(path: String, txt: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


func sha(txt: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(txt.to_utf8_buffer())
	return c.finish().hex_encode()


func _ready() -> void:
	await get_tree().process_frame
	# versions
	check(RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$").search(Updater.current()) != null, "the game knows its version (%s)" % Updater.current())
	check(Updater.newer("1.0.1", "1.0.0") and Updater.newer("v1.10.0", "1.9.2") and Updater.newer("2", "1.9.9"), "newer versions count as newer (1.10 is after 1.9)")
	check(not Updater.newer("1.0.0", "1.0.0") and not Updater.newer("v1.0", "1.0.0") and not Updater.newer("0.9.9", "1.0.0"), "the same or older versions don't")
	# GitHub's answer
	var assets := [
		{"name": "WiggleWorks-Mac.zip", "size": 10, "browser_download_url": "https://x/mac"},
		{"name": "WiggleWorks-Windows.exe", "size": 20, "browser_download_url": "https://x/win"},
	]
	check(String(Updater.pick_asset(assets, "Windows").name).ends_with(".exe"), "Windows gets the .exe")
	check(String(Updater.pick_asset(assets, "macOS").name).ends_with("Mac.zip"), "a Mac gets the Mac zip")
	check(Updater.pick_asset(assets, "Linux").is_empty(), "other computers get nothing to install")
	var r := Updater.parse_release({"tag_name": "v9.0.0", "body": "New dinosaurs!", "html_url": "https://page", "assets": assets}, "Windows")
	check(r.version == "9.0.0" and r.newer and r.notes == "New dinosaurs!" and r.page == "https://page" and r.asset.size == 20, "a newer release is spotted, with its notes and download")
	var same := Updater.parse_release({"tag_name": "v1.0.0", "body": null, "assets": null}, "Windows")
	check(not same.newer and same.notes == "" and same.asset.is_empty(), "the same version isn't offered (and missing bits don't break it)")
	check(not Updater.can_install(), "running from the source code, Update now opens the page instead")
	check(not Updater.auto_check_wanted(), "tests never ask GitHub by themselves")

	# a download arrived whole?
	DirAccess.make_dir_recursive_absolute(DIR)
	var dl := DIR + "/download.bin"
	write(dl, "the new game")
	check(Updater.verify(dl, 12, "sha256:" + sha("the new game")) == "", "a complete download with the right fingerprint passes")
	check(Updater.verify(dl, 12, "sha256:" + sha("something else")) != "", "a scrambled one doesn't")
	check(Updater.verify(dl, 99, "") != "", "nor a half-finished one")
	check(Updater.verify(DIR + "/nope.bin", 1, "") != "", "nor a missing one")

	# swapping the game file
	var exe := ProjectSettings.globalize_path(DIR + "/Wiggle Works.exe")
	write(exe, "old game")
	write(exe + ".new", "new game")
	check(Updater.swap(exe + ".new", exe) == OK and read(exe) == "new game" and read(exe + ".old") == "old game", "the new version takes the old one's place, and the old one steps aside")
	write(exe + ".new", "newer game")
	check(Updater.swap(exe + ".new", exe) == OK and read(exe) == "newer game", "and again, even with an old copy still lying there")
	check(Updater.swap(exe + ".missing", exe) != OK and read(exe) == "newer game", "if the new file isn't there, the game is put back as it was")
	Updater.clean_up(exe, true)
	var left := Array(DirAccess.get_files_at(DIR)).filter(func(f): return String(f).ends_with(".old"))
	check(left.is_empty() and read(exe) == "newer game", "old copies are cleaned up next time, and the game stays")

	# the pop-ups
	var m = load("res://ui/menu.gd").new()
	add_child(m)
	await get_tree().process_frame
	check(m.layer.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == "v" + Updater.current()), "the title screen shows the version")
	m._update_modal({"version": "9.0.0", "notes": "New dinosaurs!", "page": "https://page", "asset": {}, "newer": true, "ok": true})
	var btns: Array = m.modal.find_children("*", "Button", true, false)
	check(btns.any(func(b): return (b as Button).text == "🌐 Get it") and btns.any(func(b): return (b as Button).text == "Later"), "✨ a new version pops up with Get it and Later")
	for b: Button in btns:
		if b.text == "Later":
			b.pressed.emit()
	await get_tree().process_frame
	check(m.modal == null, "Later closes it")
	m._settings()
	var boxes: Array = m.modal.find_children("*", "CheckBox", true, false)
	check(boxes.size() == 1 and (boxes[0] as CheckBox).button_pressed == Settings.auto_update, "⚙️ Me has the 'look for a new version' switch")
	check(m.modal.find_children("*", "Button", true, false).any(func(b): return (b as Button).text.begins_with("🔄 Check")), "and a Check for updates button")
	m.queue_free()

	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	await get_tree().process_frame
	print("test_update: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

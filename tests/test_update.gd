extends Node
## 🔄 Updater checks that don't need the internet: comparing versions, picking
## the right download, only downloading from this game's GitHub releases,
## downloading (from a tiny web server on this computer, including one that
## stops answering), checking a download arrived whole, swapping the game file
## (and putting it back if that fails), cleaning up, and the pop-ups.
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


## A tiny web server for one download: answers the first request with `body`.
func _serve(srv: TCPServer, body: String) -> void:
	var until := Time.get_ticks_msec() + 5000
	while not srv.is_connection_available():
		if Time.get_ticks_msec() > until:
			return
		await get_tree().process_frame
	var c := srv.take_connection()
	var req := ""
	while not req.contains("\r\n\r\n") and Time.get_ticks_msec() < until:
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			req += c.get_utf8_string(n)
		else:
			await get_tree().process_frame
	c.put_data(("HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.length(), body]).to_utf8_buffer())
	await get_tree().create_timer(1.0).timeout
	c.disconnect_from_host()


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
	var rel_page := "https://github.com/" + Updater.REPO + "/releases/tag/v9.0.0"
	var r := Updater.parse_release({"tag_name": "v9.0.0", "body": "New dinosaurs!", "html_url": rel_page, "assets": assets}, "Windows")
	check(r.version == "9.0.0" and r.newer and r.notes == "New dinosaurs!" and r.page == rel_page and r.asset.size == 20, "a newer release is spotted, with its notes and download")
	# the page "Update now" opens on a Mac: only this game's own GitHub pages
	check(Updater.parse_release({"tag_name": "v9.0.0", "html_url": "https://evil.example/wiggle", "assets": assets}, "macOS").page == Updater.PAGE
		and Updater.safe_page("https://github.com/someone-else/wiggle-works/releases") == Updater.PAGE
		and Updater.safe_page("https://github.com/" + Updater.REPO + "/../x") == Updater.PAGE
		and Updater.safe_page("https://github.com/" + Updater.REPO + "@evil.example/") == Updater.PAGE
		and Updater.safe_page(rel_page) == rel_page, "a release page from anywhere else opens the game's usual releases page instead")
	# no fingerprint from GitHub: the release's SHA256SUMS.txt has it
	var with_sums: Array = assets.duplicate()
	with_sums.append({"name": "SHA256SUMS.txt", "size": 200, "browser_download_url": "https://github.com/" + Updater.REPO + "/releases/download/v9.0.0/SHA256SUMS.txt"})
	check(String(Updater.parse_release({"tag_name": "v9.0.0", "assets": with_sums}, "Windows").sums.get("name", "")) == "SHA256SUMS.txt"
		and Updater.parse_release({"tag_name": "v9.0.0", "assets": assets}, "Windows").sums.is_empty(), "the release's SHA256SUMS.txt is found (when there is one)")
	var hex_w := sha("the windows game")
	var sums_txt := "%s  WiggleWorks-Windows.exe\n%s  WiggleWorks-Mac.zip\n" % [hex_w, sha("the mac game")]
	check(Updater.sum_for(sums_txt, "WiggleWorks-Windows.exe") == "sha256:" + hex_w
		and Updater.sum_for(sums_txt, "Other.exe") == ""
		and Updater.sum_for("nothex  WiggleWorks-Windows.exe", "WiggleWorks-Windows.exe") == ""
		and Updater.sum_for("", "WiggleWorks-Windows.exe") == "", "and the right line is read out of it (junk and missing lines give nothing)")
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
	check(Updater.verify(dl, 99, "sha256:" + sha("the new game")) != "", "nor a half-finished one")
	check(Updater.verify(DIR + "/nope.bin", 1, "") != "", "nor a missing one")
	check(Updater.verify(dl, 12, "") != "" and Updater.verify(dl, 12, str(null)) != "", "nor one GitHub gave no fingerprint for (nothing to check it against)")

	# only from this game's GitHub releases
	var gh := "https://github.com/" + Updater.REPO + "/releases/download/"
	check(Updater.trusted(gh + "v1.0.1/WiggleWorks-Windows.exe"), "updates download from this game's GitHub releases")
	check(not Updater.trusted("http://github.com/" + Updater.REPO + "/releases/download/v1.0.1/WiggleWorks-Windows.exe")
		and not Updater.trusted("https://github.com.evil.example/" + Updater.REPO + "/releases/download/v1/x.exe")
		and not Updater.trusted("https://evil.example/?" + gh + "v1/x.exe")
		and not Updater.trusted("https://github.com/someone/else/releases/download/v1/x.exe"), "and from nowhere else (not plain http, look-alike sites or other projects)")
	var dl2 := ProjectSettings.globalize_path(DIR + "/elsewhere.exe")
	var refused: String = await Updater.fetch({"browser_download_url": "https://evil.example/WiggleWorks-Windows.exe", "size": 5, "digest": "sha256:" + sha("hello")}, dl2)
	check(refused != "" and not FileAccess.file_exists(dl2), "a download from anywhere else is refused before it starts")

	# downloading, from a tiny web server on this computer
	var srv := TCPServer.new()
	check(srv.listen(0, "127.0.0.1") == OK, "a test web server starts")
	var url := "http://127.0.0.1:%d/WiggleWorks-Windows.exe" % srv.get_local_port()
	var got := ProjectSettings.globalize_path(DIR + "/got.exe")
	_serve(srv, "the new game")
	var problem: String = await Updater.download(url, got, 12)
	check(problem == "" and read(got) == "the new game", "a download arrives whole (%s)" % (problem if problem != "" else "ok"))
	var keep_stall := Updater.stall_sec
	Updater.stall_sec = 1.0
	var t0 := Time.get_ticks_msec()
	problem = await Updater.download(url, got, 12)    # nobody answers this time
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	check(problem != "" and waited < 6.0, "a download that stops coming gives up instead of waiting forever (%.1f s: %s)" % [waited, problem])
	Updater.stall_sec = keep_stall
	srv.stop()

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
	write(exe + ".new", "half a download")
	Updater.installing = true    # as if Update now were downloading
	Updater.later_clean_up(exe, true)
	check(read(exe + ".new") == "half a download", "the second clean-up (a few seconds after starting) leaves an update that's downloading alone")
	Updater.installing = false
	Updater.later_clean_up(exe, true)
	check(not FileAccess.file_exists(exe + ".new") and read(exe) == "newer game", "and tidies up when no update is running")

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
	Updater.installing = true    # as if Update now were downloading
	m._update_modal({"version": "9.0.0", "notes": "", "page": "https://page", "asset": {}, "newer": true, "ok": true})
	m.modal_x.pressed.emit()
	await get_tree().process_frame
	check(m.modal != null and is_instance_valid(m.modal), "while an update downloads, ✕ doesn't close its pop-up (it shows how it went)")
	Updater.installing = false
	m.modal_x.pressed.emit()
	await get_tree().process_frame
	check(m.modal == null, "afterwards ✕ closes it")
	m._settings()
	# (the shared ⚙️ Settings pop-up: its switches are ✅ / ⬜ buttons with meta "on")
	var switch: Array = m.modal.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.contains("Look for a new version"))
	check(switch.size() == 1 and bool((switch[0] as Button).get_meta("on", null)) == Settings.auto_update, "⚙️ Me has the 'look for a new version' switch")
	if switch.size() == 1:
		var was := Settings.auto_update
		(switch[0] as Button).pressed.emit()
		check(Settings.auto_update == not was, "and it turns looking for updates on and off")
		(switch[0] as Button).pressed.emit()
	check(m.modal.find_children("*", "Button", true, false).any(func(b): return (b as Button).text.begins_with("🔄 Check")), "and a Check for updates button")
	m.queue_free()

	# settings: test runs never write the player's settings file
	check(Settings.test_run(PackedStringArray(["--test=perf"])) and Settings.test_run(PackedStringArray(["--shot=a.png"]))
		and not Settings.test_run(PackedStringArray(["--world=meadow"])), "test suites (even windowed ones like perf) and screenshots never save settings")

	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	await get_tree().process_frame
	print("test_update: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

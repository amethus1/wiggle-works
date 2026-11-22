extends Node
## 🔄 The real thing, online: asks GitHub for the newest release and downloads
## its Windows .exe the way the game's "Update now" does (into a test folder,
## checking the size and fingerprint). Not part of tools/run_tests.sh because
## it needs the internet; run it after tools/release.sh.
## godot --headless --path . -- --test=update_live

var fails := 0
const DIR := "user://update_live"


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	var info: Dictionary = await Updater.check()
	check(info.get("ok", false), "GitHub answers (%s)" % info.get("error", "ok"))
	if info.get("ok", false):
		print("  newest release: %s (this copy: %s)" % [info.version, Updater.current()])
		check(not Updater.newer(Updater.current(), info.version), "this copy isn't newer than the newest release")
		var win := Updater.parse_release(Updater.raw, "Windows")
		var mac := Updater.parse_release(Updater.raw, "macOS")
		check(not win.asset.is_empty() and not mac.asset.is_empty(), "the release has a Windows .exe and a Mac .zip")
		check(String(win.asset.get("digest", "")).begins_with("sha256:"), "GitHub gives the .exe's fingerprint (sha256)")
		check(Updater.trusted(String(win.asset.get("browser_download_url", ""))), "and its download link is one the updater accepts (this game's GitHub releases)")
		DirAccess.make_dir_recursive_absolute(DIR)
		var path := ProjectSettings.globalize_path(DIR + "/WiggleWorks.exe")
		var t0 := Time.get_ticks_msec()
		var problem: String = await Updater.fetch(win.asset, path)
		check(problem == "", "the .exe downloads whole, %d MB in %.0f s (%s)" % [int(win.asset.get("size", 0)) >> 20, (Time.get_ticks_msec() - t0) / 1000.0, problem if problem != "" else "size and fingerprint match"])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(DIR)
	print("test_update_live: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

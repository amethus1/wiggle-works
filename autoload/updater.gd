extends Node
## 🔄 Updates from GitHub. Autoloaded as `Updater`.
##
## New versions are GitHub Releases of REPO (tools/release.sh makes them).
## The title screen asks GitHub for the newest release when the game starts
## (Settings.auto_update) and offers "Update now"; ⚙️ Me has "Check for updates".
##
## On Windows the game updates itself: it downloads the new .exe (only from
## this game's GitHub releases) next to the old one, checks it (size and the
## SHA-256 fingerprint GitHub gives; no fingerprint, no update), swaps the
## files (a running .exe can be renamed but not overwritten, so the old one
## becomes "<name>.old" and is deleted next time) and restarts. Elsewhere, or
## when run from the source code, "Update now" opens the download page instead.

signal progress(done: int, total: int)

const REPO := "amethus1/wiggle-works"
const API := "https://api.github.com/repos/" + REPO + "/releases/latest"
const PAGE := "https://github.com/" + REPO + "/releases/latest"
const UA := "WiggleWorks-Updater"      # GitHub asks every program to name itself
const DOWNLOADS := "https://github.com/" + REPO + "/releases/download/"   # the only place updates come from

var latest := {}          # the newest release we've heard about (see parse_release)
var raw := {}             # GitHub's whole answer about it
var checking := false
var installing := false
var prompted := false     # the title screen already offered this launch's update
var stall_sec := 30.0     # a download that gets no new bytes for this long has stopped (tests make it shorter)


func _ready() -> void:
	clean_up(OS.get_executable_path())
	# the old copy may still be closing right after an update: try once more later
	get_tree().create_timer(6.0).timeout.connect(func(): later_clean_up(OS.get_executable_path()))


## The second clean-up, a few seconds after starting. Skipped if "Update now"
## was clicked by then: its download is the "<exe>.new" file clean_up removes.
func later_clean_up(exe: String, always := false) -> void:
	if not installing:
		clean_up(exe, always)


## This game's version, from project.godot (application/config/version).
static func current() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## True if version `a` is newer than `b` ("v1.10.0" > "1.9.2").
static func newer(a: String, b: String) -> bool:
	var pa := _nums(a)
	var pb := _nums(b)
	for i in maxi(pa.size(), pb.size()):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return x > y
	return false


static func _nums(v: String) -> Array[int]:
	var out: Array[int] = []
	for part in v.strip_edges().trim_prefix("v").trim_prefix("V").split("."):
		out.append(int(part) if part.is_valid_int() else 0)
	return out


## The download for this kind of computer from a release's assets.
static func pick_asset(assets: Array, os_name: String) -> Dictionary:
	var want := ".exe" if os_name == "Windows" else ("mac.zip" if os_name == "macOS" else "")
	if want == "":
		return {}
	for a in assets:
		if a is Dictionary and String(a.get("name", "")).to_lower().ends_with(want):
			return a
	return {}


## What we need from GitHub's answer about the newest release.
static func parse_release(data: Dictionary, os_name: String) -> Dictionary:
	var ver := String(data.get("tag_name", "")).strip_edges().trim_prefix("v")
	return {
		"version": ver,
		"newer": ver != "" and newer(ver, current()),
		"notes": String(data.get("body", "") if data.get("body") != null else ""),
		"page": String(data.get("html_url", PAGE)),
		"asset": pick_asset(data.get("assets", []) if data.get("assets") is Array else [], os_name),
	}


## True when "Update now" can install by itself (the exported Windows game).
func can_install() -> bool:
	return OS.get_name() == "Windows" and OS.has_feature("template")


## The title screen checks by itself only in the real (exported) game.
func auto_check_wanted() -> bool:
	return Settings.auto_update and OS.has_feature("template") and not Settings.testing


## Asks GitHub for the newest release. Returns parse_release()'s dictionary
## plus "ok" (false and "error" if GitHub couldn't be reached).
func check() -> Dictionary:
	while checking:
		await get_tree().process_frame
		if not latest.is_empty():
			return latest
	checking = true
	var h := HTTPRequest.new()
	h.timeout = 15.0
	add_child(h)
	var err := h.request(API, PackedStringArray(["User-Agent: " + UA, "Accept: application/vnd.github+json"]))
	var info := {}
	if err != OK:
		info = {"ok": false, "error": "Couldn't start checking (%s)." % error_string(err)}
	else:
		var r: Array = await h.request_completed
		var code := int(r[1])
		var body: PackedByteArray = r[3]
		var data = JSON.parse_string(body.get_string_from_utf8()) if int(r[0]) == HTTPRequest.RESULT_SUCCESS else null
		if code == 200 and data is Dictionary:
			raw = data
			info = parse_release(data, OS.get_name())
			info["ok"] = true
		elif code == 404:
			info = {"ok": false, "error": "There are no versions on GitHub yet."}
		else:
			info = {"ok": false, "error": "Couldn't reach GitHub. Are you online?"}
	h.queue_free()
	checking = false
	if info.ok:
		latest = info
	return info


## True for downloads from this game's own GitHub releases (https only).
static func trusted(url: String) -> bool:
	return url.to_lower().begins_with(DOWNLOADS.to_lower())


## Downloads `asset` (from a release) to `path` and makes sure it arrived
## whole. Returns "" when it's good, or what went wrong.
func fetch(asset: Dictionary, path: String) -> String:
	var url := String(asset.get("browser_download_url", ""))
	if url == "":
		return "That version has nothing to download for this computer."
	if not trusted(url):
		return "That download isn't from Wiggle Works' GitHub page, so it was skipped."
	var total := int(asset.get("size", 0))
	var problem := await download(url, path, total)
	if problem == "":
		problem = verify(path, total, str(asset.get("digest", "")))
	if problem != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	else:
		progress.emit(total, total)
	return problem


## Saves `url` to `path`, reporting progress. Returns "" when it all arrived,
## or what went wrong. There's no time limit (the game is a big file and Wi-Fi
## can be slow), but it gives up when no new bytes come for stall_sec seconds.
func download(url: String, path: String, total: int) -> String:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var h := HTTPRequest.new()
	# not use_threads: a threaded request stuck on a dead connection can't be
	# stopped (cancelling it freezes the game until the connection closes)
	h.download_file = path
	h.download_chunk_size = 1 << 20
	h.timeout = 0.0
	add_child(h)
	var seen := {"bytes": -1, "at": Time.get_ticks_msec(), "stopped": false}
	var ticker := func() -> void:
		if seen.stopped:
			return
		var got := h.get_downloaded_bytes()
		progress.emit(got, maxi(total, h.get_body_size()))
		if got != int(seen.bytes):
			seen.bytes = got
			seen.at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - int(seen.at) > int(stall_sec * 1000.0):
			# nothing new for a while: stop it and report it like a timeout
			seen.stopped = true
			h.cancel_request()
			h.request_completed.emit(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	var t := Timer.new()
	t.wait_time = 0.2
	t.timeout.connect(ticker)
	add_child(t)
	t.start()
	var err := h.request(url, PackedStringArray(["User-Agent: " + UA]))
	var problem := ""
	if err != OK:
		problem = "Couldn't start the download (%s)." % error_string(err)
	else:
		var r: Array = await h.request_completed
		if int(r[0]) == HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN or int(r[0]) == HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			problem = "Couldn't save the update next to the game. Try moving Wiggle Works to your Documents or Desktop folder."
		elif int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
			problem = "The download stopped. Are you online?"
	seen.stopped = true
	t.stop()
	t.queue_free()
	h.queue_free()
	return problem


## The downloaded file must be the right size and have exactly the bytes of
## GitHub's "sha256:..." digest. Without a digest there's nothing to check it
## against, so it doesn't pass.
static func verify(path: String, size: int, digest: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "The download went missing."
	if size > 0 and f.get_length() != size:
		return "The download didn't finish (%d of %d bytes)." % [f.get_length(), size]
	if not digest.begins_with("sha256:"):
		return "GitHub didn't say what the download should look like, so it wasn't installed."
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	if ctx.finish().hex_encode() != digest.trim_prefix("sha256:").to_lower():
		return "The download came out scrambled. Try again."
	return ""


## Puts `new_file` where `exe` is. The running game can't be overwritten, but
## it can be renamed out of the way first (to "<exe>.old", deleted next time).
static func swap(new_file: String, exe: String) -> Error:
	var old := exe + ".old"
	if FileAccess.file_exists(old) and DirAccess.remove_absolute(old) != OK:
		old = "%s.%d.old" % [exe, int(Time.get_unix_time_from_system())]    # still in use: pick a fresh name
	var e := DirAccess.rename_absolute(exe, old)
	if e != OK:
		return e
	e = DirAccess.rename_absolute(new_file, exe)
	if e != OK:
		DirAccess.rename_absolute(old, exe)      # put the old one back
		return e
	return OK


## Removes "<exe>.old" copies (and a half-finished "<exe>.new") left by an
## update. Only in the exported game (`always` is for tests).
static func clean_up(exe: String, always := false) -> void:
	if exe == "" or not (always or OS.has_feature("template")):
		return
	var dir := exe.get_base_dir()
	var base := exe.get_file()
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with(base + ".") and (f.ends_with(".old") or f == base + ".new"):
			d.remove(f)


## "Update now": downloads, swaps and restarts (Windows), or opens the page.
## Returns "" if the game is restarting, or what went wrong.
func install(info: Dictionary) -> String:
	if not can_install():
		OS.shell_open(String(info.get("page", PAGE)))
		return ""
	if installing:
		return "Already updating."
	installing = true
	var exe := OS.get_executable_path()
	var tmp := exe + ".new"
	var problem := await fetch(info.get("asset", {}), tmp)
	if problem == "" and swap(tmp, exe) != OK:
		problem = "Couldn't swap in the new version. Try moving Wiggle Works to your Documents or Desktop folder."
		DirAccess.remove_absolute(tmp)
	installing = false
	if problem != "":
		return problem
	if OS.create_process(exe, []) == -1:
		# the new version is in place; it just couldn't start it by itself
		return "The new version is ready, but it couldn't start. Close Wiggle Works and open it again."
	get_tree().quit()
	return ""

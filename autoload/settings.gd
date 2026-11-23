extends Node
## Player preferences and sticker progress that survive between games
## (user://settings.cfg), and 3D Battle's progress: 🧩 puzzle stars, 📜 History
## stars and 🌊 the best wave. Autoloaded as `Settings`.

signal sticker_earned(id: String)
signal smooth_3d_changed(on: bool)

const PATH := "user://settings.cfg"
const OLD_WAVES := "user://b3_waves.cfg"   # where 🌊 the best wave used to be kept (see _migrate_waves)
const SAVE_DELAY := 3.0       # counters save this many seconds after they change (see count)
const COLORS := [
	Color8(100, 220, 255), Color8(120, 240, 140), Color8(255, 110, 170), Color8(190, 140, 255),
	Color8(255, 230, 90), Color8(255, 120, 90), Color8(90, 200, 190), Color8(255, 165, 55),
]
const ADJ := ["Turbo", "Sneaky", "Mega", "Silly", "Super", "Cosmic", "Bouncy", "Zippy", "Jumbo", "Wobbly"]
const NOUN := ["Noodle", "Pickle", "Taco", "Robot", "Ninja", "Rocket", "Muffin", "Comet", "Bean", "Waffle"]
const UI_SCALES := [[0.85, "Small"], [1.0, "Normal"], [1.15, "Big"], [1.3, "Huge"]]
const SHAKES := [[0.0, "Off"], [0.5, "A little"], [1.0, "Lots"]]

var player_name := ""
var player_color: Color = COLORS[0]
var volume := 0.8
var music := 0.45
var recent: Array = []        # spawn ids, newest first
var last_world := "meadow"
var last_join := ""
var seen_help := false
var stickers := {}            # id -> true
var counters := {}            # booms, paints, jumps, specials (dict), worlds (dict)
var b3_rules := {}            # 3D Battle rules (see B3Rules)
var b3_mouse_k := 1.0         # first-person mouse speed
var b3_puzzles := {}          # 🧩 Army Puzzles: stage id -> best stars (1-3); a win opens the next one
var b3_hist_stars := {}       # 📜 History battles: id -> {"finish": true, "change": true, "hero": true}
var b3_wave_best := 0         # 🌊 Wave Defense: the best wave held (wave_held)
var auto_update := true       # 🔄 look for a new version on GitHub when the game starts
var smooth_3d := true         # 3D Battle: smooth (2x MSAA) edges; off is quicker on slow graphics cards (set_smooth_3d)
var fullscreen := false       # 🖥️ ⚙️ Settings: the whole screen (set_fullscreen)
var ui_scale := 1.0           # 🔍 ⚙️ Settings: how big buttons and words are (set_ui_scale; UI_SCALES)
var shake_2d := 1.0           # 📳 ⚙️ Settings: how much the 2D playground's screen shakes (0, 0.5 or 1)
var testing := false          # tests and screenshots never write the save file
var file := PATH              # where it's saved (tests point this somewhere else)
var _unsaved := false         # counters changed since the last save


func _ready() -> void:
	testing = DisplayServer.get_name() == "headless" or test_run(OS.get_cmdline_user_args())
	load_settings()
	_migrate_waves()
	if player_name == "":
		randomize()
		player_name = "%s %s" % [ADJ[randi() % ADJ.size()], NOUN[randi() % NOUN.size()]]
		player_color = COLORS[randi() % COLORS.size()]
	apply_screen()


## Screenshots (--shot) and test suites (--test=, even windowed ones like
## perf) start from fresh settings and never write the player's file.
static func test_run(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("--shot") or a.begins_with("--test"):
			return true
	return false


func load_settings() -> void:
	if testing:
		return
	recover(file)
	var c := ConfigFile.new()
	if c.load(file) != OK:
		return
	player_name = String(c.get_value("player", "name", ""))
	player_color = c.get_value("player", "color", COLORS[0])
	volume = float(c.get_value("audio", "volume", 0.8))
	music = float(c.get_value("audio", "music", 0.45))
	recent = c.get_value("play", "recent", [])
	last_world = String(c.get_value("play", "last_world", "meadow"))
	seen_help = bool(c.get_value("play", "seen_help", false))
	stickers = c.get_value("play", "stickers", {})
	counters = c.get_value("play", "counters", {})
	last_join = String(c.get_value("net", "last_join", ""))
	b3_rules = c.get_value("battle3d", "rules", {})
	b3_mouse_k = float(c.get_value("battle3d", "mouse", 1.0))
	b3_puzzles = _dict(c.get_value("battle3d", "puzzles", {}))
	b3_hist_stars = _dict(c.get_value("battle3d", "hist_stars", {}))
	b3_wave_best = maxi(0, int(c.get_value("battle3d", "wave_best", 0)))
	auto_update = bool(c.get_value("update", "auto", true))
	smooth_3d = bool(c.get_value("battle3d", "smooth", true))
	fullscreen = bool(c.get_value("screen", "fullscreen", false))
	ui_scale = _pick(float(c.get_value("screen", "ui_scale", 1.0)), UI_SCALES, 1.0)
	shake_2d = _pick(float(c.get_value("screen", "shake_2d", 1.0)), SHAKES, 1.0)


func save() -> void:
	_unsaved = false
	if testing:
		return
	_write()


## Writes the settings file (safely: see write_config). True if it worked.
func _write() -> bool:
	var c := ConfigFile.new()
	c.set_value("player", "name", player_name)
	c.set_value("player", "color", player_color)
	c.set_value("audio", "volume", volume)
	c.set_value("audio", "music", music)
	c.set_value("play", "recent", recent)
	c.set_value("play", "last_world", last_world)
	c.set_value("play", "seen_help", seen_help)
	c.set_value("play", "stickers", stickers)
	c.set_value("play", "counters", counters)
	c.set_value("net", "last_join", last_join)
	c.set_value("battle3d", "rules", b3_rules)
	c.set_value("battle3d", "mouse", b3_mouse_k)
	c.set_value("battle3d", "puzzles", b3_puzzles)
	c.set_value("battle3d", "hist_stars", b3_hist_stars)
	c.set_value("battle3d", "wave_best", b3_wave_best)
	c.set_value("update", "auto", auto_update)
	c.set_value("battle3d", "smooth", smooth_3d)
	c.set_value("screen", "fullscreen", fullscreen)
	c.set_value("screen", "ui_scale", ui_scale)
	c.set_value("screen", "shake_2d", shake_2d)
	return write_config(c, file)


## Saves `c` to `path` without ever leaving a broken file: it's written to
## path.tmp first and only then moved over the real one, so a crash half-way
## through a save leaves the last good file (or the new one) in place.
## True if it worked.
static func write_config(c: ConfigFile, path: String) -> bool:
	var tmp := path + ".tmp"
	if c.save(tmp) != OK:
		return false
	return DirAccess.rename_absolute(tmp, path) == OK


## Writes `text` to `path` the same safe way (game/saves.gd's slots).
static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var ok := f.get_error() == OK
	f.close()
	return ok and DirAccess.rename_absolute(tmp, path) == OK


## A save that was cut off between taking the old file away and moving the
## new one in (moving over a file can do that on Windows) left only path.tmp,
## and that's the newest: put it back in place.
static func recover(path: String) -> void:
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		DirAccess.rename_absolute(path + ".tmp", path)


## Turns 3D Battle's smooth edges on or off (saved straight away). 3D Battle
## (B3World) follows smooth_3d_changed.
func set_smooth_3d(on: bool) -> void:
	if on == smooth_3d:
		return
	smooth_3d = on
	save()
	smooth_3d_changed.emit(on)


## `v` if it's one of `choices` ([value, name] pairs), otherwise `fallback`
## (a hand-edited settings file can't make the buttons tiny).
static func _pick(v: float, choices: Array, fallback: float) -> float:
	for c in choices:
		if absf(float(c[0]) - v) < 0.01:
			return float(c[0])
	return fallback


## 🖥️ Full screen on or off (saved straight away).
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save()
	apply_screen()


## 🔍 How big the buttons and words are (one of UI_SCALES; saved straight away).
func set_ui_scale(k: float) -> void:
	ui_scale = _pick(k, UI_SCALES, 1.0)
	save()
	apply_screen()


## Puts the window and the size of everything on screen the way they're set.
## (Not in tests or screenshots: they always use a normal window.)
func apply_screen() -> void:
	if not is_inside_tree():
		return
	get_tree().root.content_scale_factor = ui_scale
	if testing or DisplayServer.get_name() == "headless":
		return
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if full != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Saves soon, once, however many counters change in the meantime (a chain of
## booms shouldn't write the file fifty times).
func save_soon() -> void:
	if _unsaved:
		return
	_unsaved = true
	get_tree().create_timer(SAVE_DELAY, true, false, true).timeout.connect(func():
		if _unsaved:
			save())


## True while a change is waiting for save_soon().
func unsaved() -> bool:
	return _unsaved


func _exit_tree() -> void:
	# quitting before save_soon() got to it: keep the progress
	if _unsaved:
		save()


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## 🧩 An Army Puzzle was won with `n` stars: keeps the best. True if it's
## better than before (saved straight away).
func puzzle_won(id: String, n: int) -> bool:
	var best := int(b3_puzzles.get(id, 0))
	if n <= best:
		return false
	b3_puzzles[id] = clampi(n, 1, 3)
	save()
	return true


## 🌊 Wave `n` of Wave Defense was held: keeps the best. True if it's better
## than before (saved straight away).
func wave_held(n: int) -> bool:
	if n <= b3_wave_best:
		return false
	b3_wave_best = n
	save()
	return true


## 🌊 The best wave used to have a file of its own (user://b3_waves.cfg, from
## 3D Battle's B3Modes). The first time, it moves in here (the better of the
## two), and the old file is kept as b3_waves.cfg.old. (`old`: tests use
## another file.)
func _migrate_waves(old := OLD_WAVES) -> void:
	if testing or not FileAccess.file_exists(old):
		return
	var c := ConfigFile.new()
	if c.load(old) != OK:
		return
	b3_wave_best = maxi(b3_wave_best, int(c.get_value("waves", "best", 0)))
	if _write():
		DirAccess.rename_absolute(old, old + ".old")


## 📜 Earns one of a History battle's three stars ("finish", "change" or
## "hero"). True the first time (saved straight away).
func history_star(id: String, which: String) -> bool:
	var got := _dict(b3_hist_stars.get(id, {}))
	if got.has(which):
		return false
	got[which] = true
	b3_hist_stars[id] = got
	save()
	return true


func add_recent(id: String) -> void:
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > 12:
		recent.resize(12)
	save()


## Awards a sticker once; returns true the first time.
func award(id: String) -> bool:
	if stickers.has(id):
		return false
	stickers[id] = true
	save()
	sticker_earned.emit(id)
	return true


## Adds to a named counter and awards `sticker` when it reaches `goal`. The
## count is saved too, so a sticker half-way done is still half-way done
## next time.
func count(name: String, sticker := "", goal := 0, amount := 1) -> int:
	var v := int(counters.get(name, 0)) + amount
	counters[name] = v
	if sticker != "" and v >= goal and award(sticker):
		return v   # award() saved everything
	save_soon()
	return v


## Remembers a member of a set (worlds visited, specials used); awards when the set is complete.
func mark(set_name: String, member: String, sticker := "", goal := 0) -> void:
	var s: Dictionary = counters.get(set_name, {})
	if s.has(member):
		return
	s[member] = true
	counters[set_name] = s
	if sticker != "" and s.size() >= goal:
		award(sticker)
	else:
		save()

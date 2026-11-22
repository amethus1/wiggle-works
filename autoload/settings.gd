extends Node
## Player preferences and sticker progress that survive between games
## (user://settings.cfg). Autoloaded as `Settings`.

signal sticker_earned(id: String)

const PATH := "user://settings.cfg"
const SAVE_DELAY := 3.0       # counters save this many seconds after they change (see count)
const COLORS := [
	Color8(100, 220, 255), Color8(120, 240, 140), Color8(255, 110, 170), Color8(190, 140, 255),
	Color8(255, 230, 90), Color8(255, 120, 90), Color8(90, 200, 190), Color8(255, 165, 55),
]
const ADJ := ["Turbo", "Sneaky", "Mega", "Silly", "Super", "Cosmic", "Bouncy", "Zippy", "Jumbo", "Wobbly"]
const NOUN := ["Noodle", "Pickle", "Taco", "Robot", "Ninja", "Rocket", "Muffin", "Comet", "Bean", "Waffle"]

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
var auto_update := true       # 🔄 look for a new version on GitHub when the game starts
var testing := false          # tests and screenshots never write the save file
var file := PATH              # where it's saved (tests point this somewhere else)
var _unsaved := false         # counters changed since the last save


func _ready() -> void:
	testing = DisplayServer.get_name() == "headless" or test_run(OS.get_cmdline_user_args())
	load_settings()
	if player_name == "":
		randomize()
		player_name = "%s %s" % [ADJ[randi() % ADJ.size()], NOUN[randi() % NOUN.size()]]
		player_color = COLORS[randi() % COLORS.size()]


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
	auto_update = bool(c.get_value("update", "auto", true))


func save() -> void:
	_unsaved = false
	if testing:
		return
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
	c.set_value("update", "auto", auto_update)
	c.save(file)


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

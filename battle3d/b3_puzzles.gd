class_name B3Puzzles
extends Node
## 🧩 Army Puzzles: a blue army is already waiting on the field. You get some
## 🪙 points and your side of the map (the glowing area), and you buy a red
## army from the Toy Box to beat it. Win for ⭐, spend less for ⭐⭐ and ⭐⭐⭐.
## Stars are saved (Settings.b3_puzzles) and each win unlocks the next one.
##   godot --path . -- --battle3d --open=puzzles          the 🧩 tab
##   godot --path . -- --battle3d --open=puzzle:tanks     set one up
##   godot --path . -- --battle3d --open=puzzle:tanks:win  ...and win it (screenshots)
##
## While a puzzle is on, this node sits under the battle (B3Battle.puzzle): it
## keeps the blue army as the puzzle made it (no erasing, grabbing or
## changing its team or mood), charges for booms, and gives out the stars
## when the battle ends. Clearing the field, changing the map or picking
## another battle ends the puzzle and turns the budget off (stop()).

const ENEMY := "blue"
const MINE := "red"
## ⭐⭐ and ⭐⭐⭐: win spending at most this much of the budget.
const TWO_STARS := 0.75
const THREE_STARS := 0.5
const ZONE_COL := Color("ffd34a")     # the glowing build zone (any budget battle)
## Seconds of battle with nobody knocked out before the blue army stops
## waiting and charges (so a puzzle never gets stuck).
const CHARGE_AFTER := 45.0

## The stages, easiest first. The camera looks along +x (your side on the
## left) unless the stage has a "yaw". zone: your side, Rect2(x, z, width,
## depth). enemy: [kind, x, z, cols, rows, gap, mood], a block facing your
## side. build: [kind, x, z, yaw°, length] buildings, ["lava"/"acid", x, z,
## radius] pools, ["top", kind, x, z, mood] a fighter on top of a building.
## (The test army for each is in SOLUTIONS.)
const STAGES := [
	{"id": "sticks", "icon": "🧍", "name": "Stick Fight", "map": "grassland", "budget": 12,
		"goal": "Beat 10 stick figures.",
		"hint": "Lots of little fighters can gang up on you. One big, strong fighter can beat them all!",
		"zone": Rect2(-34, -12, 20, 24),
		"enemy": [["stick", 16, 0, 5, 2, 1.6, "attack"]]},
	{"id": "archers", "icon": "🏹", "name": "Arrow Rain", "map": "farmland", "budget": 10,
		"goal": "Beat 10 archers behind their sandbags.",
		"hint": "Archers shoot far... but snipers shoot even farther! Keep them at the back.",
		"zone": Rect2(-34, -12, 20, 24),
		"enemy": [["archer", 20, 0, 5, 2, 1.8, "defend"]],
		"build": [["sandbags", 16, -4, 90, 0], ["sandbags", 16, 4, 90, 0]]},
	{"id": "wolves", "icon": "🐺", "name": "Wolf Pack", "map": "snow", "budget": 18,
		"goal": "Stop 8 hungry wolves.",
		"hint": "Wolves are fast and bite hard. Knights' shields hold them off, and really big animals just shrug them off!",
		"zone": Rect2(-34, -12, 20, 24),
		"enemy": [["wolf", 18, 0, 4, 2, 2.4, "attack"]]},
	{"id": "knights", "icon": "🛡️", "name": "Shield Wall", "map": "grassland", "budget": 16,
		"goal": "Break the shield wall of 5 knights.",
		"hint": "Shields stop swords and arrows, but rockets blast right past them.",
		"zone": Rect2(-34, -12, 20, 24),
		"enemy": [["knight", 22, 0, 5, 1, 1.4, "attack"]]},
	{"id": "dragon", "icon": "🐉", "name": "Dragon Attack", "map": "snow", "budget": 24,
		"goal": "Beat the dragon and its viking friends.",
		"hint": "Dragons fly! Swords can't reach them, but machine guns and helicopters can.",
		"zone": Rect2(-36, -14, 22, 28),
		"enemy": [["dragon", 24, 0, 1, 1, 2.0, "attack"], ["viking", 18, 0, 3, 2, 1.6, "attack"]]},
	{"id": "towers", "icon": "🗼", "name": "Tower Archers", "map": "farmland", "budget": 24,
		"goal": "Knock out the archers in the towers.",
		"hint": "Cannonballs knock towers down! Put cannons near the front of your side.",
		"zone": Rect2(-36, -14, 22, 28),
		"build": [["tower", 18, -7, 90, 0], ["tower", 18, 7, 90, 0],
			["top", "archer", 18, -7, "defend"], ["top", "archer", 17, -6, "defend"], ["top", "archer", 19, -8, "defend"],
			["top", "archer", 18, 7, "defend"], ["top", "archer", 17, 6, "defend"], ["top", "archer", 19, 8, "defend"]],
		"enemy": [["soldier", 21, 0, 3, 1, 1.6, "defend"]]},
	{"id": "pass", "icon": "⛰️", "name": "Hold the Pass", "map": "pass", "budget": 28,
		"goal": "Hold the mountain pass against 12 vikings.",
		"hint": "The pass is narrow. Big, tough fighters can block the whole way!",
		"zone": Rect2(-38, -9, 22, 18),
		"enemy": [["viking", 18, 0, 4, 3, 1.5, "attack"]]},
	{"id": "stampede", "icon": "🦏", "name": "Dino Stampede", "map": "grassland", "budget": 30,
		"goal": "Stop the dino stampede!",
		"hint": "Dinosaurs run straight at you. Machine-gun turrets never run away!",
		"zone": Rect2(-36, -14, 22, 28),
		"enemy": [["trike", 22, 0, 2, 1, 7.0, "attack"], ["raptor", 18, 0, 4, 1, 2.5, "attack"]]},
	{"id": "town", "icon": "🏘️", "name": "Town Square", "map": "town", "budget": 30,
		"goal": "Take the town square from 8 soldiers and their machine guns.",
		"hint": "Machine guns can't move. Snipers can hit them from far away.",
		"zone": Rect2(-30, -14, 14, 28),
		"enemy": [["mgnest", 16, -6, 1, 1, 2.0, "defend"], ["mgnest", 16, 6, 1, 1, 2.0, "defend"],
			["soldier", 20, 0, 4, 2, 1.8, "defend"]]},
	{"id": "bridge", "icon": "🌉", "name": "Hold the Bridge", "map": "volcano", "budget": 30,
		"goal": "Hold the bridge against 21 wild vikings!",
		"hint": "Big fighters at your end of the bridge can knock vikings into the lava!",
		"zone": Rect2(-30, -8, 22, 16),
		"enemy": [["viking", 14, 0, 3, 7, 1.3, "berserk"]],
		"build": [["lava_wall", 0, 0, 0, 0], ["bridge", 0, 0, 90, 0]]},
	{"id": "tanks", "icon": "🪖", "name": "Tank Trouble", "map": "desert", "budget": 36,
		"goal": "Stop 3 tanks.",
		"hint": "Bullets bounce off tanks. Cannons shoot farther than tanks, and helicopters fly where tanks can't reach!",
		"zone": Rect2(-36, -14, 22, 28),
		"enemy": [["tank", 22, 0, 3, 1, 7.0, "attack"]]},
	{"id": "trex", "icon": "🦖", "name": "T-Rex!", "map": "farmland", "budget": 36,
		"goal": "Beat the T-Rex and its raptor pack.",
		"hint": "It takes someone just as big to stand up to a T-Rex. How about a mammoth, with snipers at the back for the raptors?",
		"zone": Rect2(-36, -14, 22, 28),
		"enemy": [["trex", 24, 0, 1, 1, 2.0, "attack"], ["raptor", 18, 0, 4, 1, 2.2, "attack"]]},
	{"id": "beach", "icon": "🏖️", "name": "Storm the Beach", "map": "beach", "budget": 48,
		"goal": "Land on the beach and beat the guards on the hill.",
		"hint": "Helicopters fly right over the beach. Snipers help from the back.",
		"zone": Rect2(-20, 10, 40, 22),
		"build": [["bunker", -8, -30, 0, 0], ["bunker", 8, -30, 0, 0]],
		"enemy": [["mgnest", 0, -26, 1, 1, 2.0, "defend"],
			["soldier", 0, -28, 3, 2, 1.8, "defend"], ["sniper", 0, -34, 1, 1, 4.0, "defend"]]},
	{"id": "finale", "icon": "🌋", "name": "The Big One", "map": "volcano", "budget": 76,
		"goal": "Everything at once! Beat the biggest army of all.",
		"hint": "Mix it up: helicopters in the air, tough fighters in front, machine guns behind.",
		"zone": Rect2(-40, -12, 22, 22),
		"enemy": [["viking", 22, 0, 4, 2, 1.6, "attack"], ["giant", 26, -5, 1, 1, 2.0, "attack"],
			["robot", 26, 5, 1, 1, 2.0, "ranged"], ["tank", 32, 0, 1, 1, 4.0, "attack"],
			["trex", 34, -8, 1, 1, 2.0, "attack"], ["archer", 30, 0, 4, 1, 2.0, "ranged"]]},
]

## An army that wins each stage with ⭐⭐⭐ (for the tests and
## --open=puzzle:ID:win). [kind, x, z] places one, [kind, x, z, x2, z2] a
## dragged line; "kind:mood" sets the mood.
const SOLUTIONS := {
	"sticks": [["gorilla", -18, 0]],
	"archers": [["sniper", -24, 0]],
	"wolves": [["elephant", -18, 0]],
	"knights": [["rocketeer", -20, -1], ["rocketeer", -20, 1]],
	"dragon": [["heli", -26, 0]],
	"towers": [["cannon", -16, -3], ["cannon", -16, 3]],
	"pass": [["elephant", -22, -2], ["elephant", -22, 2]],
	"stampede": [["mgnest", -20, -4], ["mgnest", -20, 0], ["mgnest", -20, 4]],
	"town": [["sniper", -26, -2], ["sniper", -26, 0], ["sniper", -26, 2]],
	"bridge": [["elephant", -11, -1.5], ["elephant", -11, 1.5]],
	"tanks": [["heli", -34, 0], ["cannon", -22, 0]],
	"trex": [["mammoth", -20, 0], ["sniper", -32, -3], ["sniper", -32, 3]],
	"beach": [["heli", 0, 24], ["sniper", -4, 22], ["sniper", 0, 22], ["sniper", 4, 22]],
	"finale": [["heli", -28, -5], ["heli", -28, 0], ["heli", -28, 5]],
}

var b = null                  # the battle
var id := ""
var stage: Dictionary = {}
var enemies: Array = []       # [{u, kind, pos, yaw, pers}]: the blue army, as the puzzle made it
var won := 0                  # stars from this try (0 until it's won)
var over := false             # this try has ended (won or lost)
var _fought := false
var _guard_t := 0.0
var _said := ""
var _quiet_t := 0.0
var _kos_seen := 0
var _charged := false


# ------------------------------------------------------------------ data
static func info(pid: String) -> Dictionary:
	for d in STAGES:
		var e: Dictionary = d
		if String(e.id) == pid:
			return e
	return {}


static func index_of(pid: String) -> int:
	for i in STAGES.size():
		if String((STAGES[i] as Dictionary).id) == pid:
			return i
	return -1


## The stage after `pid` ("" after the last one).
static func next_id(pid: String) -> String:
	var i := index_of(pid)
	if i < 0 or i + 1 >= STAGES.size():
		return ""
	return String((STAGES[i + 1] as Dictionary).id)


## Best stars so far (0 = not won yet).
static func stars(pid: String) -> int:
	return clampi(int(Settings.b3_puzzles.get(pid, 0)), 0, 3)


## The first stage is always open; each win opens the next one.
static func unlocked(pid: String) -> bool:
	var i := index_of(pid)
	if i <= 0:
		return i == 0
	return stars(String((STAGES[i - 1] as Dictionary).id)) > 0


## [most for ⭐⭐, most for ⭐⭐⭐] in 🪙.
static func star_costs(st: Dictionary) -> Array[int]:
	var bud := int(st.get("budget", 0))
	var out: Array[int] = [floori(bud * TWO_STARS), floori(bud * THREE_STARS)]
	return out


static func stars_for(st: Dictionary, spent: int) -> int:
	var c := star_costs(st)
	if spent <= c[1]:
		return 3
	if spent <= c[0]:
		return 2
	return 1


## "⭐ win · ⭐⭐ use 18 or less · ⭐⭐⭐ use 12 or less" (shown on the card).
static func rule_text(st: Dictionary) -> String:
	var c := star_costs(st)
	return "⭐ win  ·  ⭐⭐ spend %d or less  ·  ⭐⭐⭐ spend %d or less" % [c[0], c[1]]


## "⭐⭐" and the dim rest, as [earned, not yet].
static func star_bits(n: int) -> Array[String]:
	var k := clampi(n, 0, 3)
	var out: Array[String] = ["⭐".repeat(k), "⭐".repeat(3 - k)]
	return out


# ---------------------------------------------------------------- set-up
## Sets up stage `pid`: its map, the blue army and buildings, your 🪙 budget
## and the glowing build zone, then waits for you to buy an army and press
## ▶ Fight!. Only the host (or someone playing alone) can.
static func start(bt, pid: String) -> bool:
	var st := info(pid)
	if st.is_empty() or bt.puppet:
		return false
	if bt.tools:
		bt.tools.stop_playing()
	bt.set_fighting(false)
	if bt.paused:
		bt.set_paused(false)
	bt.load_map(String(st.map))      # (this ends any puzzle that was on)
	bt.apply_rules()
	var zone: Rect2 = st.zone
	var f := B3History.Field.new()
	f.b = bt
	f.ax = Vector3(1, 0, 0)
	f.sd = Vector3(0, 0, 1)
	# trees and rocks out of the way: your side, the enemy's, and in between
	var area := zone
	for e in st.get("enemy", []) + st.get("build", []):
		var ea: Array = e
		var k := 1 if String(ea[0]) != "top" else 2
		area = area.expand(Vector2(float(ea[k]), float(ea[k + 1])))
	area = area.grow(6.0)
	f.clear(area.position.x, area.end.x, area.position.y, area.end.y)
	var p := B3Puzzles.new()
	p.name = "Puzzle"
	p.b = bt
	p.id = pid
	p.stage = st
	bt.add_child(p)
	bt.puzzle = p
	var tops: Array = []
	for e in st.get("build", []):
		var ea: Array = e
		var kind := String(ea[0])
		var at := Vector3(float(ea[1]), 0, float(ea[2]))
		at.y = bt.world.height_at(at.x, at.z)
		match kind:
			"top":
				tops.append(ea)
			"lava", "acid":
				_mark(bt.spawn_hazard(kind, at, float(ea[3])))
			"lava_wall":
				# a river of lava across the field (with a bridge over it, see "bridge")
				for zz in [-21.0, -14.0, -7.0, 0.0, 7.0, 14.0, 21.0]:
					_mark(bt.spawn_hazard("lava", Vector3(at.x, 0, at.z + zz), 4.6))
			_:
				_mark(bt.spawn_struct(kind, at, deg_to_rad(float(ea[3])), float(ea[4]) if ea.size() > 4 else 0.0))
	for e in st.get("enemy", []):
		p._block(e as Array)
	if not tops.is_empty():
		# fighters on top of the buildings once those are solid
		bt.later(0.15, func():
			if not is_instance_valid(p) or bt.puzzle != p:
				return
			for e in tops:
				var ea: Array = e
				var x := float(ea[2])
				var z := float(ea[3])
				var y: float = bt.surface_y(Vector3(x, bt.world.height_at(x, z) + 30.0, z))
				p._enemy(String(ea[1]), Vector3(x, y, z), String(ea[4]) if ea.size() > 4 else "defend"))
	bt.set_budget(int(st.budget), zone, MINE)
	# the camera looks across the battle with your side on the left (or at the bottom)
	var yaw := float(st.get("yaw", 0.0))
	bt.cam.yaw = yaw
	bt.cam.yaw_target = yaw
	_frame(bt, area)
	if bt.tools:
		bt.tools.set_team(MINE)
	if bt.ui:
		bt.ui.toast("🧩 %s  %s  You have 🪙 %d. Build your army in the glowing area, then press ▶ Fight!" % [st.icon, st.goal, int(st.budget)], false)
		bt.ui.show_puzzle()
		bt.ui.refresh()
	return true


## Fits `area` (x/z) on screen, in the room right of the Toy Box (with
## the camera looking along -z, as B3Cam.fit leaves room on the left).
static func _frame(bt, area: Rect2) -> void:
	var cam: B3Cam = bt.cam
	var vs: Vector2 = bt.get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1.0, vs.y)
	var left := 0.0
	if bt.ui and bt.ui.palette and bt.ui.palette.visible:
		left = (bt.ui.palette.get_global_rect().end.x + 10.0) / maxf(1.0, vs.x)
	# where the middle of the area lands across the screen (0..1), and the room either side of it
	var mid := 0.5 + cam.offset_k / aspect
	var half := maxf(0.15, minf(mid - left, 1.0 - mid) - 0.02)
	var across := area.size.x / (2.0 * half * aspect)
	var deep := area.size.y * sin(deg_to_rad(cam.pitch)) / 0.72      # (the top bar and the tool dock take the rest)
	var c := area.get_center()
	cam.fit(Vector3(c.x, 0, c.y), maxf(across, deep))


## The puzzle's over (cleared away, another battle, another map...):
## everything's free again and the glowing area goes.
func stop() -> void:
	if b and b.puzzle == self:
		b.puzzle = null
		b.clear_budget()
		if b.ui:
			b.ui.show_puzzle()
	queue_free()


## A block of the blue army facing your side.
func _block(e: Array) -> void:
	var kind := String(e[0])
	var c := Vector3(float(e[1]), 0, float(e[2]))
	var cols := int(e[3])
	var rows := int(e[4])
	var gap := float(e[5])
	var pers := String(e[6]) if e.size() > 6 else "auto"
	var zc: Vector2 = (stage.zone as Rect2).get_center()
	var face := Vector3(zc.x - c.x, 0, zc.y - c.z).normalized()
	var side := Vector3(-face.z, 0, face.x)
	var deep := gap * (2.0 if B3Defs.is_vehicle(kind) or B3Defs.unit_def(kind).get("body") in ["quad", "biped", "dragon", "rider"] else 1.0)
	for r in rows:
		for k in cols:
			var pos := c + side * (k - (cols - 1) * 0.5) * gap - face * r * deep
			pos.y = b.surface_y(Vector3(pos.x, b.world.height_at(pos.x, pos.z) + 30.0, pos.z))
			_enemy(kind, pos, pers)


func _enemy(kind: String, pos: Vector3, pers: String) -> B3Unit:
	var zc: Vector2 = (stage.zone as Rect2).get_center()
	var yaw := atan2(zc.x - pos.x, zc.y - pos.z)
	var u: B3Unit = b.spawn_unit(kind, ENEMY, pos, pers, yaw)
	if u:
		u.set_meta("puzzle", true)
		enemies.append({"u": u, "kind": kind, "pos": pos, "yaw": yaw, "pers": pers})
	return u


## The puzzle's own buildings and pools: you can't erase them.
static func _mark(n: Node) -> void:
	if n:
		n.set_meta("puzzle", true)


## True for the puzzle's own fighters, buildings and pools (you can't erase
## them; beat them!).
func keeps(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_meta("puzzle")


# ------------------------------------------------------------- the fight
func _ready() -> void:
	b.battle_ended.connect(_on_end, CONNECT_DEFERRED)


func _exit_tree() -> void:
	if b and b.battle_ended.is_connected(_on_end):
		b.battle_ended.disconnect(_on_end)


func _physics_process(dt: float) -> void:
	if b == null or b.puzzle != self:
		return
	if b.fighting and not _fought:
		_fought = true
		over = false
		won = 0
		_quiet_t = 0.0
		_kos_seen = b.kos
		_charged = false
		_said = ""
		if b.ui:
			b.ui.show_puzzle()
			if int(b.team_counts().get(MINE, 0)) == 0:
				b.ui.toast("🧩 Your side is empty! Pick fighters in the Toy Box and put them in the glowing area.", false)
	elif not b.fighting and _fought:
		_fought = false
	if b.fighting and b.winner == "" and not _charged:
		if b.kos != _kos_seen:
			_kos_seen = b.kos
			_quiet_t = 0.0
		else:
			_quiet_t += dt
			if _quiet_t > CHARGE_AFTER:
				_charge()
	_guard_t -= dt
	if _guard_t > 0.0:
		return
	_guard_t = 0.2
	# the blue army stays as the puzzle made it: blue, in its own mood, not grabbed
	for e in enemies:
		var u = e.u
		if not is_instance_valid(u) or (u as B3Unit).dead:
			continue
		var bu := u as B3Unit
		if bu.team != ENEMY:
			bu.set_team(ENEMY)
			_say("🧩 The puzzle's fighters stay blue. Beat them in battle!")
		if bu.pers_choice != String(e.pers) and not b.fighting:
			bu.set_personality(String(e.pers))
			_say("🧩 The puzzle's fighters keep their own mood.")
		if bu.held and b.tools and b.tools.grab_unit == bu:
			b.tools._grab_end(false)
			_say("✋ No grabbing in a puzzle. Beat them in battle!")


## Nobody's been knocked out for a long time (your army can't reach them, or
## theirs is waiting): the blue fighters stop guarding and charge.
func _charge() -> void:
	_charged = true
	var any := false
	for e in enemies:
		var u = e.u
		if is_instance_valid(u) and not (u as B3Unit).dead and (u as B3Unit).speed > 0.0 and (u as B3Unit).pers != "attack":
			(u as B3Unit).set_personality("attack")
			any = true
	if any:
		_say("😤 The blue army is tired of waiting. CHARGE!")


func _say(txt: String) -> void:
	if b.ui and txt != _said:
		b.ui.toast(txt, false)
	_said = txt


## ⏮ Reset just put everything back (Try again!): what you'd bought is
## yours again to erase for a refund, and the blue army is the new one.
func reset_done() -> void:
	over = false
	won = 0
	_fought = false
	_said = ""
	enemies = []
	for u: B3Unit in b.units:
		if u.team == ENEMY:
			u.set_meta("puzzle", true)
			enemies.append({"u": u, "kind": u.kind, "pos": u.position, "yaw": u.facing, "pers": u.pers_choice})
		elif u.team == MINE and not u.has_meta("cost"):
			u.set_meta("cost", B3Defs.cost(u.kind))
	# buildings and pools: yours (on your side) or the puzzle's
	var zone: Rect2 = stage.zone
	for arr: Array in [b.structs, b.hazards]:
		for o in arr:
			var n := o as Node3D
			if not is_instance_valid(n) or n.has_meta("cost"):
				continue
			if zone.has_point(Vector2(n.position.x, n.position.z)):
				var kind := String(n.get("kind"))
				if n is B3Hazard:
					kind = _hazard_id(n as B3Hazard)
				n.set_meta("cost", B3Defs.cost(kind))
			else:
				_mark(n)
	if b.ui:
		b.ui.show_puzzle()


static func _hazard_id(h: B3Hazard) -> String:
	if h.radius > 5.0:
		return "lava_lake" if h.kind == "lava" else "acid_swamp"
	return h.kind


## The battle ended: red won (stars!) or didn't (try again).
func _on_end(winner: String) -> void:
	if b == null or b.puzzle != self or not b.fighting:
		return
	if over and won > 0:
		return      # already won this one (the last red fighter burning out later doesn't undo it)
	over = true
	won = stars_for(stage, b.spent) if winner == MINE else 0
	var best := stars(id)
	if won > 0:
		Settings.puzzle_won(id, won)
		var all_done := true
		for st: Dictionary in STAGES:
			if stars(String(st.id)) <= 0:
				all_done = false
		if all_done:
			Settings.award("puzzles")      # 🧩 every puzzle solved
	if b.ui:
		b.ui.puzzle_result(won, best, next_id(id) if won > 0 else "")


# ------------------------------------------------------------- booms
## 🪙 Booms cost points in a puzzle and go on your side only. False (and a
## message) if this one can't be dropped.
func pay_boom(boom: String, pos: Vector3) -> bool:
	var why: String = b.can_place(boom, pos)
	if why != "":
		if b.ui:
			b.ui.toast(why, false)
		b.snd("nope", pos, 0.6)
		return false
	b.spent += B3Defs.cost(boom)
	b.budget_changed.emit()
	return true


# ------------------------------------------------- the glowing build zone
## The glowing area you can build in (B3Battle.set_budget): a see-through
## sheet over the land inside `zone` with a bright, softly pulsing edge.
static func zone_visual(bt, zone: Rect2, col: Color) -> Node3D:
	var v := ZoneGlow.new()
	v.name = "BuildZone"
	v.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var step := 1.5
	var nx := clampi(ceili(zone.size.x / step), 1, 160)
	var nz := clampi(ceili(zone.size.y / step), 1, 160)
	var dx := zone.size.x / nx
	var dz := zone.size.y / nz
	var x0 := zone.position.x
	var z0 := zone.position.y
	var w = bt.world
	# the sheet
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx:
		for j in nz:
			var xa := x0 + i * dx
			var xb := xa + dx
			var za := z0 + j * dz
			var zb := za + dz
			var p00 := Vector3(xa, float(w.height_at(xa, za)) + 0.16, za)
			var p10 := Vector3(xb, float(w.height_at(xb, za)) + 0.16, za)
			var p11 := Vector3(xb, float(w.height_at(xb, zb)) + 0.16, zb)
			var p01 := Vector3(xa, float(w.height_at(xa, zb)) + 0.16, zb)
			for q in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(q)
	v.fill = StandardMaterial3D.new()
	v.fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v.fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v.fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	v.fill.albedo_color = Color(col, 0.14)
	var sheet := MeshInstance3D.new()
	sheet.mesh = st.commit()
	sheet.material_override = v.fill
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(sheet)
	# the edge: a glowing band standing up all the way round, fading upward
	var pts: Array[Vector2] = []
	for i in nx:
		pts.append(Vector2(x0 + i * dx, z0))
	for j in nz:
		pts.append(Vector2(zone.end.x, z0 + j * dz))
	for i in nx:
		pts.append(Vector2(zone.end.x - i * dx, zone.end.y))
	for j in nz:
		pts.append(Vector2(x0, zone.end.y - j * dz))
	var et := SurfaceTool.new()
	et.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Color(col, 1.0)
	var hi := Color(col, 0.0)
	for i in pts.size():
		var a := pts[i]
		var c := pts[(i + 1) % pts.size()]
		var ya := float(w.height_at(a.x, a.y)) + 0.1
		var yc := float(w.height_at(c.x, c.y)) + 0.1
		var a0 := Vector3(a.x, ya, a.y)
		var a1 := Vector3(a.x, ya + 0.6, a.y)
		var c0 := Vector3(c.x, yc, c.y)
		var c1 := Vector3(c.x, yc + 0.6, c.y)
		for q in [[a0, lo], [c0, lo], [c1, hi], [a0, lo], [c1, hi], [a1, hi]]:
			et.set_color(q[1])
			et.add_vertex(q[0])
	v.edge = StandardMaterial3D.new()
	v.edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v.edge.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v.edge.cull_mode = BaseMaterial3D.CULL_DISABLED
	v.edge.vertex_color_use_as_albedo = true
	v.edge.albedo_color = Color(1.6, 1.6, 1.6, 0.9)
	var band := MeshInstance3D.new()
	band.mesh = et.commit()
	band.material_override = v.edge
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(band)
	# ...and a bright strip on the ground just inside it, seen from any side
	var ft := SurfaceTool.new()
	ft.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := zone.get_center()
	for i in pts.size():
		var a := pts[i]
		var c := pts[(i + 1) % pts.size()]
		var d := (c - a).normalized()
		var n := Vector2(-d.y, d.x)
		if n.dot(mid - a) < 0.0:
			n = -n
		var ai := a + n * 0.8
		var ci := c + n * 0.8
		var q0 := Vector3(a.x, float(w.height_at(a.x, a.y)) + 0.18, a.y)
		var q1 := Vector3(c.x, float(w.height_at(c.x, c.y)) + 0.18, c.y)
		var q2 := Vector3(ci.x, float(w.height_at(ci.x, ci.y)) + 0.18, ci.y)
		var q3 := Vector3(ai.x, float(w.height_at(ai.x, ai.y)) + 0.18, ai.y)
		for q in [[q0, lo], [q1, lo], [q2, hi], [q0, lo], [q2, hi], [q3, hi]]:
			ft.set_color(q[1])
			ft.add_vertex(q[0])
	var strip := MeshInstance3D.new()
	strip.mesh = ft.commit()
	strip.material_override = v.edge
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(strip)
	return v


## Pulses the build zone's glow gently.
class ZoneGlow extends Node3D:
	var fill: StandardMaterial3D
	var edge: StandardMaterial3D
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		var k := 0.5 + 0.5 * sin(_t * 2.4)
		if fill:
			fill.albedo_color.a = 0.10 + 0.07 * k
		if edge:
			edge.albedo_color.a = 0.65 + 0.35 * k


# ------------------------------------------------- tests and screenshots
## Places SOLUTIONS[pid] with the Toy Box (B3Tools._place), like a kid
## would. Returns how many 🪙 it spent.
static func place_solution(bt, pid: String) -> int:
	var t = bt.tools
	if t == null:
		return 0
	var keep := [t.place_id, t.pers, t.place_size]
	for e in SOLUTIONS.get(pid, []):
		var ea: Array = e
		var parts := String(ea[0]).split(":")
		t.place_id = parts[0]
		t.pers = parts[1] if parts.size() > 1 else "auto"
		t.place_size = 1.0
		var a := Vector3(float(ea[1]), 0, float(ea[2]))
		a.y = bt.world.height_at(a.x, a.z)
		if B3Defs.BOOMS.has(parts[0]):
			bt.drop(parts[0], a)
			continue
		var c := a
		if ea.size() >= 5:
			c = Vector3(float(ea[3]), 0, float(ea[4]))
			c.y = bt.world.height_at(c.x, c.z)
		t._place(a, c, ea.size() >= 5, false)
	t.place_id = keep[0]
	t.pers = keep[1]
	t.place_size = keep[2]
	return int(bt.spent)


## --open=puzzles (the tab), puzzle:ID (set one up) or puzzle:ID:win (set it
## up, place the test army and fight).
static func open_arg(bt, arg: String) -> void:
	var parts := arg.split(":")
	if parts[0] == "puzzles":
		if bt.ui:
			bt.ui._show_history("puzzles")
		return
	if parts[0] != "puzzle" or parts.size() < 2 or not start(bt, parts[1]):
		return
	if parts.size() > 2 and parts[2] == "win":
		bt.later(0.5, func():
			place_solution(bt, parts[1])
			bt.later(0.4, func(): bt.set_fighting(true)))

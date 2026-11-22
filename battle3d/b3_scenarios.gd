class_name B3Scenarios
## Ready-made battles. Kids pick them in the 📜 pop-up's 🎯 Ready-made tab
## (setup: everything waits for ▶ Fight!); screenshots and tests use
## `--battle3d --scenario=NAME` (run: the fight starts by itself).
##   skirmish, dinos, nuke, hazards, structures, animals, chaos, big, c4,
##   vehicles, monsters, airshow (planes and helicopters over two armies),
##   roadtrip (race cars bumping soldiers), hangar (every vehicle parked),
##   waves (🌊 Wave Defense; waves:N starts at wave N, waves:0 waits for
##   Fight! like the 🎯 card does; see B3Modes)
##   (lineup / closeup / showcase / garage / firebreath: models only, no fight)

const R := Vector3(0.7071, 0, -0.7071)    # screen-right on the ground (default view)
const F := Vector3(-0.7071, 0, -0.7071)   # screen-up (away from the camera)

## Set up, but nobody fights (close-ups of the models for screenshots).
const STILL := ["hangar", "showcase", "garage", "firebreath", "lineup", "closeup"]

## The 🎯 Ready-made tab, in this order: a card each (icon, name, who's
## fighting, what happens).
const MENU := [
	{"id": "skirmish", "icon": "⚔️", "name": "Skirmish",
		"sides": "🔴 Knights, soldiers and archers vs 🔵 Vikings, ninjas and rocketeers",
		"desc": "Two armies meet in the middle, with sandbags, crates and boom barrels to fight around."},
	{"id": "waves", "icon": "🌊", "name": "Wave Defense",
		"sides": "🔴 You and your fort vs 🔵 wave after wave of attackers",
		"desc": "Spend 🪙 points on defenders, walls, towers and mines, then hold the fort! Every wave is stronger, with a boss every 5th. Jump in and fight too!"},
	{"id": "dinos", "icon": "🦖", "name": "Dino Attack",
		"sides": "🐾 A T-Rex, raptors and more vs 🔵 Soldiers",
		"desc": "A herd of dinosaurs charges at a line of soldiers behind sandbags."},
	{"id": "nuke", "icon": "☢️", "name": "Nuke!",
		"sides": "🔴 Red army vs 🔵 Blue army",
		"desc": "Two big armies, a tower and a bunker... and a nuke falls as soon as you press Fight!"},
	{"id": "hazards", "icon": "🌋", "name": "Lava Bridge",
		"sides": "🔴 Vikings, knights and archers vs 🔵 Soldiers and stick figures",
		"desc": "Fight over a bridge across a lava pool, with acid pools on both sides. Don't fall in!"},
	{"id": "structures", "icon": "🏰", "name": "Storm the Fort",
		"sides": "🔴 Knights, vikings and giants vs 🔵 Archers in towers",
		"desc": "Archers and a sniper hold two towers and a bunker. Can the red army break in?"},
	{"id": "animals", "icon": "🐺", "name": "Wild Animals",
		"sides": "🐾 Wolves, a bear and a bull vs 🟢 An elephant, dogs and soldiers",
		"desc": "A fight in the snow, with chickens running around in the middle."},
	{"id": "chaos", "icon": "🌀", "name": "Total Chaos",
		"sides": "🔴 🔵 🟢 🟡 Every kind of fighter, on four teams",
		"desc": "A big circle of everyone around a lava pool. Which team will be the last one standing?"},
	{"id": "big", "icon": "🎖️", "name": "Huge Battle",
		"sides": "🔴 75 fighters vs 🔵 75 fighters",
		"desc": "150 fighters in two giant armies. It's a big one, so it may be slow on some computers."},
	{"id": "c4", "icon": "📟", "name": "C4 Surprise",
		"sides": "🔴 Soldiers vs 🔵 Soldiers",
		"desc": "Two lines of soldiers with C4 hidden between them. It goes off 2 seconds after you press Fight!"},
	{"id": "vehicles", "icon": "🚜", "name": "Tank Line",
		"sides": "🔴 Tanks, jeeps, a cannon and machine guns vs 🔵 Army",
		"desc": "Red's vehicles hold the line against an army with rockets and a giant."},
	{"id": "monsters", "icon": "🐉", "name": "Monster Mash",
		"sides": "🐾 A dragon · 🟢 Gorillas and mammoths · 🔴 Wizards, robots and knights",
		"desc": "A wild dragon breathes fire on everyone while gorillas and mammoths charge the wizards."},
	{"id": "airshow", "icon": "✈️", "name": "Air Show",
		"sides": "🔴 vs 🔵 Fighter planes, helicopters and two armies",
		"desc": "Planes and helicopters dogfight in the sky over 60 fighters."},
	{"id": "roadtrip", "icon": "🏎️", "name": "Road Trip",
		"sides": "🔴 Race cars and stick figures vs 🔵 Soldiers, knights and jeeps",
		"desc": "Race cars zoom into the soldiers and BONK them sky-high. There are ramps to jump, too!"},
	{"id": "hangar", "icon": "🛩️", "name": "Hangar",
		"sides": "Every vehicle, parked up close",
		"desc": "Pick a tank, car, helicopter or plane and press 🎮 Play as me! to drive or fly it."},
]


## The 🎯 Ready-made card for `sc` ({} if there isn't one).
static func info(sc: String) -> Dictionary:
	for d in MENU:
		var e: Dictionary = d
		if String(e.id) == sc:
			return e
	return {}

static func map_for(sc: String) -> String:
	match sc.get_slice(":", 0):
		"hazards":
			return "volcano"
		"nuke":
			return "desert"
		"animals":
			return "snow"
		"vehicles", "roadtrip":
			return "desert"
	return "grassland"


## Ground point at screen-ish coordinates (x right, y away from camera).
static func at(b, x: float, y: float) -> Vector3:
	var p := R * x + F * y
	p.y = b.world.height_at(p.x, p.z)
	return p


static func line(b, kind: String, team: String, x: float, y0: float, y1: float, n: int, pers := "auto") -> void:
	for i in n:
		var y := lerpf(y0, y1, 0.5 if n == 1 else float(i) / (n - 1))
		b.spawn_unit(kind, team, at(b, x, y), pers)


## Builds `sc` on the map that's loaded and starts the fight a moment
## later (--scenario=NAME for screenshots and tests).
static func run(b, sc: String) -> void:
	if not _build(b, sc) or sc in STILL or sc == "waves:0":
		return
	on_fight(b, sc)
	b.later(0.5, func(): b.set_fighting(true))


## 🎯 Ready-made: loads the right map and sets `sc` up the same way, then
## waits for ▶ Fight! (the nuke or the C4 goes off once it's pressed, see
## on_fight). False if there's no such battle.
static func setup(b, sc: String) -> bool:
	if info(sc).is_empty():
		return false
	if b.tools:
		b.tools.stop_playing()
	b.set_fighting(false)
	if b.paused:
		b.set_paused(false)
	b.load_map(map_for(sc))
	b.apply_rules()
	# the layouts are made for the usual view
	b.cam.yaw = 45.0
	b.cam.yaw_target = 45.0
	_build(b, sc)
	b.ready_id = sc
	b.scenario = sc
	if b.ui:
		var d := info(sc)
		if sc == "waves":
			b.ui.toast("🌊 Wave Defense! Spend your 🪙 points on defenders, walls and mines in the glowing fort, then press ▶ Fight!")
		else:
			b.ui.toast("🎯 %s %s is ready!  Press ▶ Fight! to start, or pick one and play as it!" % [d.icon, d.name])
		b.ui.refresh()
	return true


## What a ready-made battle does once the fight starts.
static func on_fight(b, sc: String) -> void:
	match sc:
		"nuke":
			b.later(0.3, func(): b.drop("nuke", at(b, 0, 0)))
		"c4":
			b.later(2.0, func():
				if b.c4_count() > 0:
					b.detonate_c4())


static func _build(b, sc: String) -> bool:
	if sc == "waves" or sc.begins_with("waves:"):
		_waves(b, maxi(1, sc.get_slice(":", 1).to_int()) if sc.contains(":") else 1)
		return true
	match sc:
		"skirmish":
			_skirmish(b)
		"dinos":
			_dinos(b)
		"nuke":
			_nuke(b)
		"hazards":
			_hazards(b)
		"structures":
			_structures(b)
		"animals":
			_animals(b)
		"chaos":
			_chaos(b)
		"big":
			_big(b)
		"c4":
			_c4(b)
		"vehicles":
			_vehicles(b)
		"monsters":
			_monsters(b)
		"airshow":
			_airshow(b)
		"roadtrip":
			_roadtrip(b)
		"hangar":
			_hangar(b)
		"showcase":
			_showcase(b)
		"garage":
			_garage(b)
		"firebreath":
			_firebreath(b)
		"lineup":
			_lineup(b)
		"closeup":
			_lineup(b)
			b.cam.fit(at(b, -1.5, 6), 9.0)
		_:
			if b.ui:
				b.ui.toast("Unknown scenario: " + sc)
			return false
	return true


## 🌊 Wave Defense: Red's fort (sandbags round a tower and a bunker, with a
## few defenders), the 🪙 points to spend in it, and waves of attackers from
## the far side once Fight! is pressed (B3Modes). Laid out square to the
## map, with the camera turned so the attackers come down the screen.
static func _waves(b, first: int) -> void:
	var f: Rect2 = B3Modes.FORT
	var pts: int = B3Modes.START_POINTS
	for n in range(1, first):
		pts += B3Modes.wave_bonus(n) + 6      # (starting later: what the waves before would have given)
	b.ready_id = "waves"
	b.set_budget(pts, f, "red")
	b.modes.begin_waves(first)
	var g := func(x: float, z: float) -> Vector3:
		return Vector3(x, b.world.height_at(x, z), z)
	# sandbags along the front and the sides (their round side faces out)
	for x in [-7.5, -2.5, 2.5, 7.5]:
		b.spawn_struct("sandbags", g.call(x, 6.5), PI)
	for z in [11.0, 16.5]:
		b.spawn_struct("sandbags", g.call(-12.0, z), -PI * 0.5)
		b.spawn_struct("sandbags", g.call(12.0, z), PI * 0.5)
	b.spawn_struct("tower", g.call(-6.0, 19.0), 0.0)
	b.spawn_struct("bunker", g.call(6.0, 18.0), PI)     # its slits face the attackers
	for x in [-7.5, -2.5, 2.5, 7.5]:
		b.spawn_unit("soldier", "red", g.call(x, 8.6), "defend", PI)
	b.spawn_unit("knight", "red", g.call(-3.5, 12.0), "defend", PI)
	b.spawn_unit("knight", "red", g.call(3.5, 12.0), "defend", PI)
	b.spawn_unit("medic", "red", g.call(0.0, 15.0), "defend", PI)
	b.later(0.15, func():
		var top: Vector3 = g.call(-6.0, 19.0)
		for dx in [-0.8, 0.8]:
			var p := Vector3(top.x + dx, b.surface_y(top + Vector3(dx, 30, 0)), top.z)
			b.spawn_unit("archer", "red", p, "defend", PI))
	b.spawn_prop("xbarrel", g.call(-2.0, 3.5))
	b.spawn_prop("xbarrel", g.call(4.0, 3.0))
	if b.tools:
		b.tools.pers = "defend"       # what you buy guards its spot in the fort
		b.tools.team = "red"
		if b.ui:
			b.ui.refresh_palette()
	b.cam.yaw = 0.0
	b.cam.yaw_target = 0.0
	b.cam.fit(Vector3(0, 0, 5), 40.0)


static func _army(b, team: String, side: float, mix: Array) -> void:
	# mix: [[kind, rows-from-front, count], ...]
	for m in mix:
		var kind := String(m[0])
		var row := float(m[1])
		var n := int(m[2])
		line(b, kind, team, side * (9.0 + row * 2.2), -n * 0.75, n * 0.75, n)


static func _skirmish(b) -> void:
	_army(b, "red", -1.0, [["knight", 0, 5], ["soldier", 1, 6], ["gunner", 2, 2], ["archer", 3, 5], ["medic", 2.5, 1], ["giant", 4, 1]])
	_army(b, "blue", 1.0, [["viking", 0, 5], ["soldier", 1, 6], ["rocketeer", 2, 2], ["grenadier", 3, 3], ["ninja", 0.5, 3], ["sniper", 4.5, 2]])
	b.spawn_struct("sandbags", at(b, -5.0, 4.0), deg_to_rad(45.0) + PI * 0.5)
	b.spawn_struct("sandbags", at(b, 5.0, -4.0), deg_to_rad(45.0) - PI * 0.5)
	for p in [at(b, 0, 7), at(b, 1, -6), at(b, -1.5, -1)]:
		b.spawn_prop("xbarrel", p)
	b.spawn_struct("crates", at(b, 0.5, 2.5), deg_to_rad(45.0))
	b.cam.fit(at(b, 0, 0), 30.0)


static func _dinos(b) -> void:
	b.spawn_unit("trex", "wild", at(b, -14, 0))
	for i in 3:
		b.spawn_unit("raptor", "wild", at(b, -10, -6 + i * 3.0))
	b.spawn_unit("trike", "wild", at(b, -12, 7))
	b.spawn_unit("stego", "wild", at(b, -17, -7), "attack")
	b.spawn_unit("brachio", "wild", at(b, -22, 3), "attack")
	b.spawn_unit("ptero", "wild", at(b, -12, 11))
	b.spawn_unit("ptero", "wild", at(b, -9, -11))
	line(b, "soldier", "blue", 9, -8, 8, 8)
	line(b, "rocketeer", "blue", 12, -6, 6, 3)
	line(b, "gunner", "blue", 11, -10, 10, 2)
	line(b, "sniper", "blue", 15, -4, 4, 2)
	line(b, "knight", "blue", 7, -3, 3, 3)
	b.spawn_struct("sandbags", at(b, 6, 0), deg_to_rad(45.0) - PI * 0.5)
	b.cam.fit(at(b, -2, 0), 36.0)


static func _nuke(b) -> void:
	_army(b, "red", -1.0, [["soldier", 0, 10], ["knight", 1, 8], ["archer", 2, 8], ["giant", 3, 2]])
	_army(b, "blue", 1.0, [["soldier", 0, 10], ["viking", 1, 8], ["rocketeer", 2, 6], ["gunner", 3, 3]])
	b.spawn_struct("tower", at(b, -20, 8), deg_to_rad(45.0))
	b.spawn_struct("bunker", at(b, 20, -8), deg_to_rad(45.0))
	b.spawn_struct("wall", at(b, 0, 12), deg_to_rad(45.0), 10.0)
	for i in 6:
		b.spawn_prop("xbarrel", at(b, -4 + i * 1.6, -10))
	b.spawn_struct("crates", at(b, 4, 8), 0.3)
	b.cam.fit(at(b, 0, 2), 64.0)


static func _hazards(b) -> void:
	b.spawn_hazard("lava", at(b, 0, 0), 4.5)
	b.spawn_hazard("acid", at(b, 0, 9), 3.2)
	b.spawn_hazard("acid", at(b, 1, -9), 3.0)
	b.spawn_struct("bridge", at(b, 0, 0), deg_to_rad(45.0) + PI * 0.5)
	line(b, "viking", "red", -10, -6, 6, 5, "berserk")
	line(b, "knight", "red", -12, -4, 4, 3)
	line(b, "archer", "red", -15, -4, 4, 3)
	line(b, "soldier", "blue", 10, -6, 6, 5)
	line(b, "stick", "blue", 8, -7, 7, 6, "berserk")
	line(b, "grenadier", "blue", 14, -3, 3, 2)
	for i in 3:
		b.spawn_prop("xbarrel", at(b, -2.0 + i * 2.0, 5.5))
	b.cam.fit(at(b, 0, 0), 30.0)


static func _structures(b) -> void:
	var yaw := deg_to_rad(45.0)
	b.spawn_struct("tower", at(b, 9, 6), yaw)
	b.spawn_struct("tower", at(b, 9, -6), yaw)
	b.spawn_struct("bunker", at(b, 13, 0), yaw + PI * 0.5)
	b.spawn_struct("wall", at(b, 5, 0), yaw + PI * 0.5, 8.0)
	b.spawn_struct("sandbags", at(b, 4, 9), yaw - PI * 0.5)
	b.spawn_struct("sandbags", at(b, 4, -9), yaw - PI * 0.5)
	b.spawn_struct("ramp", at(b, -3, 10), yaw)
	b.spawn_struct("block", at(b, -3, 14), yaw)
	b.later(0.15, func():
		for y in [6.0, -6.0]:
			var c: Vector3 = at(b, 9, y)
			for k in 3:
				var off := R * (k - 1) * 1.0
				var top: float = b.surface_y(c + off + Vector3(0, 30, 0))
				b.spawn_unit("archer" if k != 1 else "sniper", "blue", Vector3(c.x + off.x, top, c.z + off.z), "defend")
		line(b, "soldier", "blue", 7, -3, 3, 3, "defend")
		line(b, "gunner", "blue", 11.5, -1.5, 1.5, 2, "defend"))
	line(b, "knight", "red", -12, -6, 6, 5)
	line(b, "viking", "red", -14, -5, 5, 4)
	line(b, "rocketeer", "red", -17, -4, 4, 3)
	line(b, "giant", "red", -19, -3, 3, 2)
	b.cam.fit(at(b, -1, 1), 34.0)


static func _animals(b) -> void:
	for i in 4:
		b.spawn_unit("wolf", "wild", at(b, -10, -6 + i * 4.0))
	b.spawn_unit("bear", "wild", at(b, -14, 2))
	b.spawn_unit("bull", "wild", at(b, -12, -8))
	b.spawn_unit("elephant", "green", at(b, 12, 6), "attack")
	for i in 3:
		b.spawn_unit("dog", "green", at(b, 9, -4 + i * 3.0))
	for i in 5:
		b.spawn_unit("chicken", "wild", at(b, randf_range(-4, 4), randf_range(-8, 8)))
	line(b, "soldier", "green", 13, -5, 3, 4)
	b.cam.fit(at(b, 0, 0), 32.0)


static func _chaos(b) -> void:
	var kinds: Array = B3Defs.UNITS.keys()
	var teams := ["red", "blue", "green", "yellow"]
	for i in 40:
		var k := String(kinds[i % kinds.size()])
		var t := String(teams[i % 4])
		var a := TAU * i / 40.0
		b.spawn_unit(k, t, at(b, cos(a) * 14.0, sin(a) * 14.0))
	b.spawn_hazard("lava", at(b, 0, 0), 3.0)
	b.spawn_struct("tower", at(b, 6, 6), 0.4)
	b.cam.fit(at(b, 0, 0), 40.0)


static func _big(b) -> void:
	_army(b, "red", -1.0, [["soldier", 0, 15], ["knight", 1, 15], ["archer", 2, 15], ["viking", 3, 15], ["gunner", 4, 10], ["medic", 5, 5]])
	_army(b, "blue", 1.0, [["soldier", 0, 15], ["ninja", 1, 15], ["archer", 2, 15], ["stick", 3, 15], ["rocketeer", 4, 10], ["grenadier", 5, 5]])
	b.cam.fit(at(b, 0, 0), 52.0)


static func _c4(b) -> void:
	line(b, "soldier", "red", -3, -6, 6, 8)
	line(b, "soldier", "blue", 3, -6, 6, 8)
	for i in 5:
		b.spawn_prop("c4", at(b, 0, -6 + i * 3.0))
	b.spawn_struct("wall", at(b, 0, 10), deg_to_rad(45.0), 10.0)
	b.cam.fit(at(b, 0, 0), 28.0)


## Every fighter in a row (no fight): for checking the models.
static func _lineup(b) -> void:
	var x := -10.0
	var row := 0
	for cat in ["people", "animals", "dinos", "vehicles"]:
		var ids: Array = B3Defs.UNIT_ORDER[cat]
		var xx := -11.0 if cat != "vehicles" else -8.0
		for id in ids:
			var t: String = ["red", "blue", "wild", "green"][row]
			var gap: float = {"people": 2.0, "vehicles": 6.5}.get(cat, 4.4)
			b.spawn_unit(String(id), t, at(b, xx, 9.0 - row * 7.0), "auto", deg_to_rad(105.0))
			xx += gap
		row += 1
	b.cam.fit(at(b, 3, -2), 30.0)


## Tanks, jeeps, a cannon and MG turrets hold the line against an army.
static func _vehicles(b) -> void:
	var yaw := deg_to_rad(45.0)
	b.spawn_unit("tank", "red", at(b, -9, 4))
	b.spawn_unit("tank", "red", at(b, -10, -5))
	b.spawn_unit("jeep", "red", at(b, -6, 10))
	b.spawn_unit("jeep", "red", at(b, -6, -11))
	b.spawn_unit("cannon", "red", at(b, -17, 0))
	b.spawn_unit("mgnest", "red", at(b, -5, 0))
	b.spawn_unit("mgnest", "red", at(b, -13, 8))
	b.spawn_struct("sandbags", at(b, -3.2, 0), yaw - PI * 0.5)
	_army(b, "blue", 1.0, [["soldier", 0, 8], ["knight", 1, 5], ["rocketeer", 2, 4], ["grenadier", 3, 3], ["gunner", 3.5, 2], ["giant", 4.5, 1]])
	for p in [at(b, 2, 6), at(b, 3, -7)]:
		b.spawn_prop("xbarrel", p)
	b.cam.fit(at(b, 0, 0), 34.0)


## The new monsters: a wild dragon, gorillas and mammoths against wizards,
## robots and knights.
static func _monsters(b) -> void:
	b.spawn_unit("dragon", "wild", at(b, 1, 9))
	b.spawn_unit("mammoth", "green", at(b, 9, 3.5))
	b.spawn_unit("mammoth", "green", at(b, 10, -4.5))
	for i in 3:
		b.spawn_unit("gorilla", "green", at(b, 7, -3.5 + i * 3.5))
	line(b, "wizard", "red", -10, -4, 4, 3)
	line(b, "robot", "red", -8, -3, 3, 2)
	line(b, "knight", "red", -6, -5, 5, 4)
	line(b, "archer", "red", -12, -2, 2, 2)
	b.spawn_hazard("lava", at(b, 0, -8), 2.5)
	b.cam.fit(at(b, 0, 1), 26.0)


## The new fighters (showcase) and vehicles (garage) up close, standing
## still, for screenshots.
static func _showcase(b) -> void:
	var y := deg_to_rad(70.0)
	b.spawn_unit("wizard", "red", at(b, -5.5, 0.5), "auto", y)
	b.spawn_unit("robot", "blue", at(b, -3.3, 0.5), "auto", y)
	b.spawn_unit("gorilla", "green", at(b, -0.6, 0.5), "auto", y)
	b.spawn_unit("mammoth", "wild", at(b, 4.0, 2.0), "auto", y)
	var d = b.spawn_unit("dragon", "red", at(b, 0.5, -7.5), "auto", y)
	d._alt = 3.0
	b.cam.fit(at(b, 0.0, 0.5), 11.0)


## A hovering dragon breathing fire on some (very tough) knights, over and
## over, with no fight going on (for checking the effect in screenshots).
static func _firebreath(b) -> void:
	var d = b.spawn_unit("dragon", "red", at(b, -7, 0), "auto", atan2(R.x, R.z))
	d._alt = 4.5
	var ks := []
	for i in 3:
		var k = b.spawn_unit("knight", "blue", at(b, 1, -2 + i * 2.0), "auto", atan2(-R.x, -R.z))
		k.hp = 99999.0
		k.max_hp = 99999.0
		ks.append(k)
	var r = b.spawn_unit("robot", "red", at(b, -4, -5), "auto", atan2(R.x, R.z))
	var w = b.spawn_unit("wizard", "red", at(b, -8, -7), "auto", atan2(R.x, R.z))
	for i in 40:
		b.later(1.0 + i * 1.6, func():
			if is_instance_valid(d) and not d.dead and d.act == "" and is_instance_valid(ks[1]):
				d.target = ks[1]
				d._start_breath())
	for i in 120:
		b.later(1.0 + i * 0.55, func():
			if is_instance_valid(r) and not r.dead and r.act == "" and is_instance_valid(ks[0]):
				r.target = ks[0]
				r._attack(r.wpn)
			if is_instance_valid(w) and not w.dead and w.act == "" and is_instance_valid(ks[2]) and i % 3 == 0:
				w.target = ks[2]
				w._attack(w.wpn))
	b.cam.fit(at(b, -2, 2.0), 17.0)


static func _garage(b) -> void:
	var y := deg_to_rad(110.0)
	b.spawn_unit("tank", "blue", at(b, -4.5, 1.5), "auto", y)
	b.spawn_unit("jeep", "red", at(b, 0.8, 1.5), "auto", y)
	b.spawn_unit("cannon", "yellow", at(b, -3.0, -3.5), "auto", y)
	b.spawn_unit("mgnest", "green", at(b, 2.5, -3.5), "auto", y)
	b.cam.fit(at(b, -0.8, -0.8), 10.0)


## Fighter planes and helicopters dogfight over two armies (6 planes, 4
## helicopters, 60 fighters).
static func _airshow(b) -> void:
	_army(b, "red", -1.0, [["soldier", 0, 10], ["knight", 0.6, 6], ["gunner", 1.4, 4], ["rocketeer", 2.2, 6], ["archer", 3, 4]])
	_army(b, "blue", 1.0, [["soldier", 0, 10], ["viking", 0.6, 6], ["gunner", 1.4, 4], ["rocketeer", 2.2, 6], ["sniper", 3, 4]])
	for i in 3:
		b.spawn_unit("plane", "red", at(b, -30, -14 + i * 14.0))
		b.spawn_unit("plane", "blue", at(b, 30, -14 + i * 14.0))
	for i in 2:
		b.spawn_unit("heli", "red", at(b, -19, -7 + i * 14.0))
		b.spawn_unit("heli", "blue", at(b, 19, -7 + i * 14.0))
	b.cam.fit(at(b, 0, 4), 48.0)


## Race cars zoom into a line of soldiers and bump them sky-high, with a
## couple of ramps to jump.
static func _roadtrip(b) -> void:
	for i in 4:
		b.spawn_unit("car", "red", at(b, -17, -9 + i * 6.0))
	for i in 3:
		b.spawn_unit("car", "blue", at(b, 17, -6 + i * 6.0))
	b.spawn_unit("jeep", "blue", at(b, 15, -11))
	b.spawn_unit("jeep", "blue", at(b, 15, 11))
	line(b, "soldier", "blue", 8, -8, 8, 8)
	line(b, "knight", "blue", 10, -5, 5, 4)
	line(b, "stick", "red", -9, -8, 8, 8)
	line(b, "gunner", "red", -11, -3, 3, 2)
	b.spawn_struct("ramp", at(b, -4, 3), atan2(R.x, R.z))
	b.spawn_struct("ramp", at(b, 4, -3), atan2(-R.x, -R.z))
	for p in [at(b, 1, 7), at(b, -1, -7)]:
		b.spawn_prop("xbarrel", p)
	b.cam.fit(at(b, 0, 0), 32.0)


## Every vehicle up close, standing still (the plane and helicopter parked
## on the ground), for screenshots.
static func _hangar(b) -> void:
	var y := deg_to_rad(110.0)
	b.spawn_unit("tank", "blue", at(b, -9.0, 4.5), "auto", y)
	b.spawn_unit("jeep", "red", at(b, -3.5, 5.0), "auto", y)
	b.spawn_unit("car", "yellow", at(b, 1.0, 5.0), "auto", y)
	b.spawn_unit("cannon", "green", at(b, -8.0, -1.5), "auto", y)
	b.spawn_unit("mgnest", "red", at(b, -3.5, -1.5), "auto", y)
	var h = b.spawn_unit("heli", "blue", at(b, 3.5, -0.5), "auto", y)
	var p = b.spawn_unit("plane", "red", at(b, 2.0, -10.0), "auto", deg_to_rad(70.0))
	for a in [h, p]:
		if a is B3Aircraft:
			(a as B3Aircraft).parked = true
	b.cam.fit(at(b, -1.5, -1.5), 16.0)

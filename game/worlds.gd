class_name Worlds
## Builds each world: ground shapes, water, decorations, sky style, and the
## Wigglies and toys that are there when you arrive.

const SKY := {
	"meadow": {"top": Color("5fb8ff"), "bottom": Color("c9ecff"), "far": Color("8fd18a"), "far2": Color("6bbf73"), "layer": "hills", "sun": true},
	"toyroom": {"top": Color("ffe3c2"), "bottom": Color("ffd09e"), "far": Color("f3b98a"), "far2": Color("e8a877"), "layer": "room", "sun": false},
	"candy": {"top": Color("ff9ad5"), "bottom": Color("ffe0f2"), "far": Color("ffb3e0"), "far2": Color("c79bff"), "layer": "candy", "sun": true},
	"frosty": {"top": Color("7fb3ff"), "bottom": Color("e6f2ff"), "far": Color("dbe9ff"), "far2": Color("b7cdf2"), "layer": "mountains", "sun": true},
	"lagoon": {"top": Color("33b5ff"), "bottom": Color("bff0ff"), "far": Color("4fd1c5"), "far2": Color("2a9d8f"), "layer": "sea", "sun": true},
	"moon": {"top": Color("0b1030"), "bottom": Color("2b2a6b"), "far": Color("3d3a7a"), "far2": Color("2a2860"), "layer": "craters", "sun": false},
	"clouds": {"top": Color("6ec6ff"), "bottom": Color("ffe9c7"), "far": Color("ffffff"), "far2": Color("ffe9f4"), "layer": "clouds", "sun": true},
	"battle": {"top": Color("74b9ff"), "bottom": Color("dff3ff"), "far": Color("a3cb8f"), "far2": Color("7fae6b"), "layer": "mountains", "sun": true},
	"factory": {"top": Color("5d6d7e"), "bottom": Color("aab7b8"), "far": Color("4d5656"), "far2": Color("3b4444"), "layer": "factory", "sun": false},
	"volcano": {"top": Color("6e2c00"), "bottom": Color("e67e22"), "far": Color("4a2511"), "far2": Color("2e1609"), "layer": "volcano", "sun": false},
	"dino": {"top": Color("48c9b0"), "bottom": Color("f9e79f"), "far": Color("52be80"), "far2": Color("239b56"), "layer": "hills", "sun": true},
	"canvas": {"top": Color("8fc3ef"), "bottom": Color("d6e9f8"), "far": Color("b9d6ef"), "far2": Color("a9cbe9"), "layer": "grid", "sun": false},
}
const NIGHT_SKY := {"top": Color("070b24"), "bottom": Color("23295c")}


## How placed platforms look.
static func platform_style(style: String) -> Dictionary:
	match style:
		"metal":
			return {"fill": Color("8395a7"), "fill2": Color("576574"), "top": Color("c8d6e5"), "top_w": 6.0, "pattern": "grid", "dot": Color(0, 0, 0, 0.15), "fric": 0.7}
		"stone":
			return {"fill": Color("a4a29a"), "fill2": Color("7d7a72"), "top": Color("c8c5bc"), "top_w": 6.0, "pattern": "planks", "dot": Color(0, 0, 0, 0.12), "fric": 0.9}
		"concrete":
			return {"fill": Color("b2bec3"), "fill2": Color("8f9a9e"), "top": Color("dfe6e9"), "top_w": 6.0, "dot": Color(0, 0, 0, 0.1), "fric": 0.9}
		"rock":
			return {"fill": Color("4a3b33"), "fill2": Color("2d221d"), "top": Color("e67e22"), "top_w": 5.0, "dot": Color(1, 0.5, 0.2, 0.25), "fric": 0.9}
		"steel":
			return {"fill": Color("5b7d5b"), "fill2": Color("3e5a3e"), "top": Color("a3e4a3"), "top_w": 5.0, "pattern": "grid", "dot": Color(0, 0, 0, 0.15), "fric": 0.8}
	return {"fill": Color("c98a48"), "fill2": Color("9c6634"), "top": Color("e0a868"), "top_w": 6.0, "pattern": "planks", "dot": Color(0, 0, 0, 0.12), "fric": 0.85}


static func default_gravity(id: String) -> String:
	return "moon" if id == "moon" else "normal"


static func starts_at_night(id: String) -> bool:
	return id == "moon"


## Volcano eruptions and other world happenings.
static func tick(world: World, dt: float) -> void:
	if world.world_id == "volcano":
		var t: float = world.get_meta("erupt_t", 4.0) - dt
		if t <= 0.0:
			t = randf_range(5.0, 9.0)
			world.fx_event("erupt", {"p": Vector2(900, -150)})
			for i in randi_range(3, 6):
				var b := world.spawn_toy("meteor", Vector2(900 + randf_range(-40, 40), -220), 0.0, 1.0, Combat.PROJ.meteor)
				if b:
					b.extra.proj = "bomb"
					b.extra.meteor = true
					b.extra.life = 8.0
					b.linear_velocity = Vector2(randf_range(-700, 500), randf_range(-1100, -700))
		world.set_meta("erupt_t", t)


static func ground_y(id: String) -> float:
	return {"clouds": 200.0, "toyroom": 320.0}.get(id, 300.0)


static func sky(id: String) -> Dictionary:
	return SKY.get(id, SKY.meadow)


static func _ground(world: World, pts: PackedVector2Array, st: Dictionary, s := 1) -> Ground:
	var g := Ground.new()
	g.setup(pts, st, s)
	world.terrain.add_child(g)
	return g


## A ground strip whose top follows `f(x)` from x0 to x1, down to `bottom`.
static func _strip(x0: float, x1: float, bottom: float, f: Callable, step := 30.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := x0
	while x < x1:
		pts.append(Vector2(x, f.call(x)))
		x += step
	pts.append(Vector2(x1, f.call(x1)))
	pts.append(Vector2(x1, bottom))
	pts.append(Vector2(x0, bottom))
	return pts


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _decor(world: World, kind: String, pos: Vector2, s := 1.0, extra := {}) -> void:
	var d := Decor.new()
	d.kind = kind
	d.position = pos
	d.scale_f = s
	d.extra = extra
	world.decor.add_child(d)


static func build(world: World, id: String) -> void:
	world.water.clear()
	match id:
		"meadow":
			var st := {"fill": Color("9c6b3f"), "fill2": Color("6d4526"), "top": Color("5cc94a"), "top_w": 16.0, "tuft": "grass", "dot": Color(0, 0, 0, 0.08)}
			var hill := func(x: float) -> float:
				var y := 300.0 - 70.0 * sin(x * 0.0021) - 40.0 * sin(x * 0.0057 + 1.0)
				# the pond dip
				if x > 380.0 and x < 980.0:
					y += 150.0 * sin((x - 380.0) / 600.0 * PI)
				# tall hills at both ends keep everything in
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1350.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1760, 1760, 1000, hill), st)
			world.water.append(Rect2(420, 330, 520, 300))
			for x in [-1150.0, -650.0, 1150.0]:
				_decor(world, "tree", Vector2(x, hill.call(x) + 6), randf_range(0.9, 1.25))
			for i in 26:
				var x := randf_range(-1300, 1300)
				if x > 360 and x < 1000:
					continue
				_decor(world, "flower", Vector2(x, hill.call(x) + 4), randf_range(0.8, 1.2), {"c": Catalog.PAINT[randi() % 8]})
			for x in [-850.0, 150.0, 1250.0]:
				_decor(world, "bush", Vector2(x, hill.call(x) + 8), 1.0)
			world.view_rect = Rect2(-792, -346, 1584, 792)
			world.spawn_points = [Vector2(-300, 0), Vector2(0, -60), Vector2(300, 0)]
			world.bounds = Rect2(-2300, -2600, 4600, 4000)
		"toyroom":
			var floor_st := {"fill": Color("c8874f"), "fill2": Color("a0663a"), "top": Color("d99a5e"), "top_w": 8.0, "pattern": "planks", "dot": Color(0, 0, 0, 0.12)}
			var wall_st := {"fill": Color("f2c79b"), "fill2": Color("e2ae7e"), "top": Color("fff2df"), "top_w": 8.0, "dot": Color(0, 0, 0, 0.04)}
			var shelf_st := {"fill": Color("9b5d33"), "fill2": Color("7a4523"), "top": Color("c27a45"), "top_w": 6.0, "pattern": "planks", "dot": Color(0, 0, 0, 0.1)}
			_ground(world, _rect(Rect2(-1500, 320, 3000, 400)), floor_st)
			_ground(world, _rect(Rect2(-1500, -1300, 200, 1700)), wall_st, 2)
			_ground(world, _rect(Rect2(1300, -1300, 200, 1700)), wall_st, 3)
			_ground(world, _rect(Rect2(-1300, -120, 420, 26)), shelf_st, 4)
			_ground(world, _rect(Rect2(880, -260, 420, 26)), shelf_st, 5)
			_ground(world, _rect(Rect2(-260, -430, 360, 26)), shelf_st, 6)
			_ground(world, _rect(Rect2(780, 190, 260, 130)), {"fill": Color("4f7cff"), "fill2": Color("3557c9"), "top": Color("ffd43b"), "top_w": 10.0, "dot": Color(1, 1, 1, 0.12)}, 7)
			_decor(world, "rug", Vector2(-200, 322), 1.0)
			_decor(world, "frame", Vector2(-700, -420), 1.0)
			_decor(world, "frame", Vector2(560, -560), 0.8, {"c": Color("4fd1c5")})
			world.view_rect = Rect2(-936, -539, 1872, 828)
			world.spawn_points = [Vector2(-400, 100), Vector2(0, 100), Vector2(400, 100)]
			world.bounds = Rect2(-1700, -2400, 3400, 3400)
		"candy":
			var st := {"fill": Color("ff8fc7"), "fill2": Color("e25aa0"), "top": Color("fff0fa"), "top_w": 18.0, "tuft": "candy", "pattern": "stripes", "dot": Color(1, 1, 1, 0.22), "bounce": 0.7, "fric": 0.8}
			var hill := func(x: float) -> float:
				var y := 300.0 - 90.0 * absf(sin(x * 0.0035)) - 30.0 * sin(x * 0.011)
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1350.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1760, 1760, 1000, hill), st)
			# gumdrop islands
			for c in [Vector2(-500, -60), Vector2(420, -160)]:
				var pts := PackedVector2Array()
				for i in 18:
					var a := PI + PI * float(i) / 17.0
					pts.append(c + Vector2(cos(a) * 110.0, sin(a) * 80.0))
				pts.append(c + Vector2(110, 20))
				pts.append(c + Vector2(-110, 20))
				_ground(world, pts, {"fill": Color("8c6cff"), "fill2": Color("6a4bd9"), "top": Color("e9e2ff"), "top_w": 10.0, "tuft": "candy", "dot": Color(1, 1, 1, 0.2), "bounce": 0.85}, 9)
			for x in [-1100.0, -150.0, 900.0]:
				_decor(world, "lollipop", Vector2(x, hill.call(x) + 6), randf_range(0.9, 1.3), {"c": Catalog.PAINT[randi() % 8]})
			for x in [-800.0, 300.0, 1200.0]:
				_decor(world, "cane", Vector2(x, hill.call(x) + 6), randf_range(0.9, 1.2))
			world.view_rect = Rect2(-792, -406, 1584, 792)
			world.spawn_points = [Vector2(-300, -100), Vector2(150, -150)]
			world.bounds = Rect2(-2300, -2600, 4600, 4000)
		"frosty":
			var st := {"fill": Color("e9f3ff"), "fill2": Color("b9d2f0"), "top": Color("ffffff"), "top_w": 14.0, "tuft": "snow", "dot": Color(0.6, 0.75, 0.95, 0.25), "fric": 0.12}
			var slope := func(x: float) -> float:
				var y := 300.0
				if x < 400.0:
					y = 300.0 - (400.0 - x) * 0.42 + 30.0 * sin(x * 0.01)
				# a ski jump
				if x > 250.0 and x < 470.0:
					y -= 70.0 * sin((x - 250.0) / 220.0 * PI * 0.5)
				y -= 520.0 * pow(maxf(0.0, x - 1350.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1600, 1760, 1100, slope), st)
			_ground(world, _rect(Rect2(-1800, -1400, 200, 2500)), st, 2)
			for x in [-1300.0, -900.0, 900.0, 1250.0]:
				_decor(world, "pine", Vector2(x, slope.call(x) + 6), randf_range(0.9, 1.3))
			_decor(world, "snowman", Vector2(1000, slope.call(1000.0) + 2), 1.0)
			world.view_rect = Rect2(-864, -545, 1728, 900)
			world.spawn_points = [Vector2(-900, -300), Vector2(-600, -200)]
			world.bounds = Rect2(-2300, -2800, 4600, 4200)
		"lagoon":
			var sand := {"fill": Color("f2d48c"), "fill2": Color("d9b36a"), "top": Color("fbe6b0"), "top_w": 10.0, "tuft": "sand", "dot": Color(0.6, 0.45, 0.2, 0.15)}
			var beach := func(x: float) -> float:
				var y := 300.0 + maxf(0.0, x - 100.0) * 0.55
				y = minf(y, 700.0)
				y -= 520.0 * pow(maxf(0.0, -x - 1350.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1760, 1900, 1100, beach), sand)
			_ground(world, _rect(Rect2(1900, -1400, 200, 2500)), sand, 2)
			world.water.append(Rect2(160, 320, 1740, 800))
			# pier
			var pier := {"fill": Color("a8743f"), "fill2": Color("845628"), "top": Color("c48a50"), "top_w": 6.0, "pattern": "planks", "dot": Color(0, 0, 0, 0.12)}
			_ground(world, _rect(Rect2(250, 230, 520, 22)), pier, 3)
			for x in [300.0, 520.0, 740.0]:
				_ground(world, _rect(Rect2(x - 8, 252, 16, 460)), pier, 4)
			# little island
			var isl := PackedVector2Array()
			for i in 16:
				var a := PI + PI * float(i) / 15.0
				isl.append(Vector2(1350, 340) + Vector2(cos(a) * 180.0, sin(a) * 70.0))
			isl.append(Vector2(1530, 420))
			isl.append(Vector2(1170, 420))
			_ground(world, isl, sand, 5)
			_decor(world, "palm", Vector2(1360, 274), 1.0)
			_decor(world, "palm", Vector2(-800, 305), 1.2)
			_decor(world, "umbrella", Vector2(-350, 305), 1.0, {"c": Color("ff5a5a")})
			world.view_rect = Rect2(-636, -379, 1872, 828)
			world.spawn_points = [Vector2(-500, 100), Vector2(-200, 100)]
			world.bounds = Rect2(-2300, -2600, 4600, 4000)
		"moon":
			var st := {"fill": Color("8d8fb3"), "fill2": Color("5b5d86"), "top": Color("b8bbe0"), "top_w": 10.0, "dot": Color(0.25, 0.25, 0.45, 0.35)}
			var land := func(x: float) -> float:
				var y := 300.0 + 25.0 * sin(x * 0.004)
				for c in [-700.0, 150.0, 900.0]:
					var d := absf(x - c)
					if d < 160.0:
						y += 60.0 * (1.0 - d / 160.0) * (1.0 - d / 160.0) - (25.0 if d > 120.0 else 0.0)
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1350.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1760, 1760, 1000, land, 20.0), st)
			for x in [-1100.0, -400.0, 500.0, 1150.0]:
				_decor(world, "glow_plant", Vector2(x, land.call(x) + 4), randf_range(0.8, 1.3), {"c": [Color("6cf2ff"), Color("c08bff"), Color("7dffb0")][randi() % 3]})
			_decor(world, "crystal", Vector2(-950, land.call(-950.0) + 6), 1.2)
			_decor(world, "crystal", Vector2(700, land.call(700.0) + 6), 0.9)
			world.view_rect = Rect2(-792, -406, 1584, 792)
			world.spawn_points = [Vector2(-300, 0), Vector2(300, 0)]
			world.bounds = Rect2(-2300, -3200, 4600, 4600)
		"clouds":
			var st := {"fill": Color("ffffff"), "fill2": Color("dfe9ff"), "top": Color("ffffff"), "top_w": 12.0, "dot": Color(0.75, 0.82, 1.0, 0.4), "fric": 0.8}
			var grass := {"fill": Color("8b5a2b"), "fill2": Color("5e3a1a"), "top": Color("67d35a"), "top_w": 14.0, "tuft": "grass", "dot": Color(0, 0, 0, 0.1)}
			var isles := [[Vector2(-700, 200), 330.0], [Vector2(150, 60), 260.0], [Vector2(900, 240), 300.0], [Vector2(-60, 420), 180.0]]
			var k := 0
			for isle in isles:
				var c: Vector2 = isle[0]
				var wdt: float = isle[1]
				var pts := PackedVector2Array()
				pts.append(c + Vector2(-wdt, 0))
				pts.append(c + Vector2(wdt, 0))
				for i in 12:
					var a := float(i) / 11.0
					pts.append(c + Vector2(wdt * (1.0 - 2.0 * a), 40.0 + 90.0 * sin(a * PI) + 18.0 * sin(a * 23.0)))
				_ground(world, pts, grass, 10 + k)
				_decor(world, "cloud_fluff", c + Vector2(0, 30), wdt / 300.0)
				k += 1
			# rainbow bridge: arches from the left island (top y 200) up onto the middle one (top y 60)
			var bridge := PackedVector2Array()
			for i in 21:
				var a := float(i) / 20.0
				bridge.append(Vector2(lerpf(-380, -100, a), lerpf(200.0, 60.0, a) - 60.0 * sin(a * PI)))
			for i in 21:
				var a := 1.0 - float(i) / 20.0
				bridge.append(Vector2(lerpf(-380, -100, a), lerpf(214.0, 74.0, a) - 60.0 * sin(a * PI)))
			_ground(world, bridge, {"fill": Color("ff6b6b"), "fill2": Color("8c6cff"), "top": Color("ffd43b"), "top_w": 5.0, "dot": Color(0, 0, 0, 0)}, 20)
			_decor(world, "tree", Vector2(-800, 206), 0.9)
			_decor(world, "tree", Vector2(980, 246), 1.0)
			world.view_rect = Rect2(-828, -306, 1656, 792)
			world.spawn_points = [Vector2(-700, 100), Vector2(150, -40), Vector2(900, 140)]
			world.bounds = Rect2(-2400, -2400, 4800, 3800)
		"battle":
			var st := {"fill": Color("8d6e4b"), "fill2": Color("5d4630"), "top": Color("6ab04c"), "top_w": 14.0, "tuft": "grass", "dot": Color(0, 0, 0, 0.08)}
			var land := func(x: float) -> float:
				# the same rolling hills on both sides (a plain sine wave put blue
				# up to 60 px above red, shooting downhill, and blue always won)
				var y := 300.0 - 30.0 * sin(absf(x) * 0.003)
				# river in the middle
				if absf(x) < 160.0:
					y += 90.0 * cos(x / 160.0 * PI * 0.5)
				# behind each fort the ground rises to a high meadow level with
				# the tower's top: there used to be a pit behind the tower that
				# nobody could reach or shoot into, so a fighter thrown there
				# could stall the whole battle
				y = lerpf(y, 10.0, smoothstep(1120.0, 1165.0, absf(x)))
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1500.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1900, 1900, 1000, land), st)
			world.water.append(Rect2(-160, 320, 320, 200))
			# forts: a wall, a tower and a bunker on each side
			# (groups below 0 are part of the world: 🧹 Clear leaves them, the eraser can still take them)
			for side in [-1.0, 1.0]:
				var fx: float = side * 900.0
				# chest-high cover: tall enough to hide behind, low enough to jump over
				var wall_x: float = fx - 20 * side
				var wall_top: float = land.call(wall_x) - 95.0
				world.add_platform(World.rect_poly(Rect2(wall_x - 13, wall_top, 26, 120)), "stone", -1 if side < 0 else -2)
				world.add_platform(World.rect_poly(Rect2(fx + side * 220 - 50, 20, 100, 280)), "stone", -3 if side < 0 else -4)
				world.add_platform(World.rect_poly(Rect2(fx + side * 220 - 70, 6, 140, 18)), "wood", -3 if side < 0 else -4)
			world.add_platform(World.rect_poly(Rect2(-200, 280, 400, 14)), "wood", -5)
			_decor(world, "tree", Vector2(-1350, land.call(-1350.0) + 6), 1.1)
			_decor(world, "tree", Vector2(1350, land.call(1350.0) + 6), 1.0)
			world.view_rect = Rect2(-1300, -500, 2600, 1000)
			world.spawn_points = [Vector2(-900, 100), Vector2(900, 100)]
			world.bounds = Rect2(-2400, -2600, 4800, 4000)
		"factory":
			var st := {"fill": Color("5d6d7e"), "fill2": Color("34495e"), "top": Color("f1c40f"), "top_w": 6.0, "pattern": "grid", "dot": Color(0, 0, 0, 0.18)}
			_ground(world, _rect(Rect2(-1600, 320, 3200, 500)), st)
			_ground(world, _rect(Rect2(-1600, -1300, 140, 1700)), st, 2)
			_ground(world, _rect(Rect2(1460, -1300, 140, 1700)), st, 3)
			# catwalks
			for r in [Rect2(-1300, 40, 500, 18), Rect2(-200, -120, 420, 18), Rect2(700, 60, 500, 18)]:
				world.add_platform(World.rect_poly(r), "metal", -10)
			world.view_rect = Rect2(-1200, -560, 2400, 1000)
			world.spawn_points = [Vector2(-600, 100), Vector2(600, 100)]
			world.bounds = Rect2(-2000, -2400, 4000, 3600)
		"volcano":
			var st := {"fill": Color("4a3b33"), "fill2": Color("2d221d"), "top": Color("6e5a4e"), "top_w": 10.0, "dot": Color(1, 0.45, 0.1, 0.2)}
			var land := func(x: float) -> float:
				var y := 300.0
				# the volcano on the right
				if x > 400.0 and x < 1400.0:
					var k := 1.0 - absf(x - 900.0) / 500.0
					y -= 520.0 * k
					if absf(x - 900.0) < 90.0:
						y += 180.0 * (1.0 - absf(x - 900.0) / 90.0)
				# the lava lake on the left
				if x > -900.0 and x < -300.0:
					y += 160.0 * sin((x + 900.0) / 600.0 * PI)
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1500.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-1900, 1900, 1100, land, 20.0), st)
			world.add_liquid(Rect2(-880, 340, 560, 200), "lava")
			world.add_liquid(Rect2(820, -60, 160, 120), "lava")
			world.view_rect = Rect2(-1300, -600, 2600, 1100)
			world.spawn_points = [Vector2(-1200, 150), Vector2(0, 150)]
			world.bounds = Rect2(-2400, -3000, 4800, 4400)
		"dino":
			var st := {"fill": Color("8d6e4b"), "fill2": Color("5d4630"), "top": Color("58d68d"), "top_w": 16.0, "tuft": "grass", "dot": Color(0, 0, 0, 0.08)}
			var land := func(x: float) -> float:
				var y := 300.0 - 60.0 * sin(x * 0.0018 + 0.5)
				if x > 200.0 and x < 700.0:
					y += 120.0 * sin((x - 200.0) / 500.0 * PI)
				y -= 520.0 * pow(maxf(0.0, absf(x) - 1700.0) / 400.0, 1.6)
				return y
			_ground(world, _strip(-2100, 2100, 1000, land), st)
			world.water.append(Rect2(220, 340, 460, 200))
			for i in 10:
				var x := randf_range(-1600, 1600)
				if x > 180 and x < 720:
					continue
				_decor(world, "palm" if i % 3 == 0 else "fern", Vector2(x, land.call(x) + 4), randf_range(0.8, 1.4))
			world.view_rect = Rect2(-1400, -600, 2800, 1100)
			world.spawn_points = [Vector2(-600, 0), Vector2(600, 0)]
			world.bounds = Rect2(-2600, -2600, 5200, 4000)
		_:
			var st := {"fill": Color("3d6fb6"), "fill2": Color("2c548f"), "top": Color("a9d1ff"), "top_w": 8.0, "pattern": "grid", "dot": Color(1, 1, 1, 0.18)}
			_ground(world, _rect(Rect2(-1700, 300, 3400, 500)), st)
			_ground(world, _rect(Rect2(-1700, -1500, 120, 1800)), st, 2)
			_ground(world, _rect(Rect2(1580, -1500, 120, 1800)), st, 3)
			world.view_rect = Rect2(-792, -386, 1584, 792)
			world.spawn_points = [Vector2(0, 100)]
			world.bounds = Rect2(-2000, -2600, 4000, 3800)


## Who's waiting for you when a world opens.
static func add_starters(world: World, id: String) -> void:
	match id:
		"meadow":
			world.spawn_wiggly("bloop", Vector2(-260, 120))
			world.spawn_wiggly("gummy", Vector2(-80, 120))
			world.spawn_wiggly("puffy", Vector2(120, 100))
			world.spawn_toy("beach_ball", Vector2(260, 100))
			world.spawn_toy("spring_pad", Vector2(-560, 200))
			for i in 4:
				world.spawn_toy("wood_block", Vector2(-860 + (i % 2) * 40, 200 - i / 2 * 40))
		"toyroom":
			world.spawn_wiggly("bloop", Vector2(-420, 250))
			world.spawn_wiggly("zappy", Vector2(-120, 250))
			for i in 6:
				world.spawn_toy("abc_block", Vector2(140 + (i % 3) * 42, 296 - (i / 3) * 42))
			world.spawn_toy("bouncy_ball", Vector2(500, 200))
			var bat := world.spawn_toy("battery", Vector2(-1000, -150))
			var lamp := world.spawn_toy("lamp", Vector2(-930, -160))
			if bat and lamp:
				world.add_link("wire", bat, lamp, bat.global_position, lamp.global_position)
			Builders.ride(world, "go_kart", Vector2(-700, 280))
		"candy":
			world.spawn_wiggly("puffy", Vector2(-200, 120))
			world.spawn_wiggly("twinkle", Vector2(100, 100))
			world.spawn_wiggly("bloop", Vector2(-500, -140))
			for i in 4:
				world.spawn_toy("bouncy_ball", Vector2(200 + i * 40, 50))
		"frosty":
			world.spawn_wiggly("frosty", Vector2(-900, -220))
			world.spawn_wiggly("boulder", Vector2(-700, -120))
			world.spawn_wiggly("bloop", Vector2(-500, -40))
			world.spawn_toy("ice_cube", Vector2(600, 260))
			world.spawn_toy("ice_cube", Vector2(640, 260))
			Builders.ride(world, "go_kart", Vector2(-1100, -330))
		"lagoon":
			world.spawn_wiggly("bloop", Vector2(-500, 220))
			world.spawn_wiggly("blaze", Vector2(-250, 220))
			world.spawn_toy("beach_ball", Vector2(-100, 200))
			Builders.ride(world, "boat", Vector2(1000, 280))
			world.spawn_toy("firework", Vector2(-600, 260))
		"moon":
			world.spawn_wiggly("twinkle", Vector2(-200, 150))
			world.spawn_wiggly("zappy", Vector2(200, 150))
			world.spawn_toy("saucer", Vector2(0, -220))
			for i in 3:
				world.spawn_toy("firework", Vector2(-500 + i * 40, 260))
		"clouds":
			world.spawn_wiggly("puffy", Vector2(-700, 100))
			world.spawn_wiggly("bloop", Vector2(150, -40))
			var b := world.spawn_toy("balloon", Vector2(880, 60))
			if b:
				b.paint = Color("ffd43b")
			Builders.ride(world, "hot_air", Vector2(900, 180))
		"battle":
			for i in 5:
				var ids := ["soldier", "knight", "archer", "soldier", "rocketeer"]
				# just in front of the towers (not inside them)
				world.spawn_fighter(ids[i], Vector2(-1040 + i * 55, 150), "red", "")
				world.spawn_fighter(ids[i], Vector2(1040 - i * 55, 150), "blue", "")
			world.spawn_fighter("sniper", Vector2(-680, -40), "red", "defend")
			world.spawn_fighter("sniper", Vector2(680, -40), "blue", "defend")
			world.spawn_toy("barrel", Vector2(-500, 260))
			world.spawn_toy("barrel", Vector2(500, 260))
			world.battle_on = false
		"factory":
			Builders.tub(world, "acid_vat", Vector2(-600, 320))
			Builders.tub(world, "acid_vat", Vector2(500, 320))
			var c := world.spawn_toy("conveyor", Vector2(-50, 300))
			if c:
				c.set_size(1.6)
			for i in 3:
				world.spawn_fighter("stick", Vector2(-1100 + i * 50, 200), "yellow", "peaceful")
			world.spawn_toy("barrel", Vector2(150, 260))
			world.spawn_toy("barrel", Vector2(200, 260))
		"volcano":
			world.spawn_fighter("viking", Vector2(-1250, 150), "red", "")
			world.spawn_fighter("knight", Vector2(-150, 150), "blue", "")
			world.spawn_fighter("raptor", Vector2(-50, 150), "wild", "")
		"dino":
			world.spawn_fighter("trex", Vector2(900, 0), "wild", "")
			world.spawn_fighter("triceratops", Vector2(-900, 0), "wild", "")
			world.spawn_fighter("brachio", Vector2(-300, -100), "wild", "")
			world.spawn_fighter("ptero", Vector2(0, -400), "wild", "")
			for i in 3:
				world.spawn_fighter("raptor", Vector2(1200 + i * 60, 0), "wild", "")
		_:
			world.spawn_wiggly("bloop", Vector2(0, 200))

class_name Scenarios
## Test setups for screenshots and checks (main.gd --scenario=name).

static func run(game: Game, name: String) -> void:
	var w := game.world
	match name:
		"showcase":
			var x := -900.0
			for id in ["beach_ball", "bouncy_ball", "soccer_ball", "bowling_ball", "marble", "steel_ball"]:
				w.spawn_toy(id, Vector2(x, -150))
				x += 70.0
			x = -900.0
			for id in ["wood_block", "brick", "abc_block", "ice_cube", "glass_pane", "pillow", "metal_beam"]:
				w.spawn_toy(id, Vector2(x, -350))
				x += 90.0
			x = 100.0
			for id in ["battery", "switch", "button", "timer", "lamp", "bell", "fan", "magnet", "motor", "rocket", "propeller", "cannon", "bubbler"]:
				var t := w.spawn_toy(id, Vector2(x, -420))
				if t:
					t.nailed = true
					t.update_freeze()
					t.on = id in ["lamp", "fan", "motor", "rocket", "propeller"]
				x += 75.0
			x = -500.0
			for k in Catalog.WIGGLY_ORDER:
				w.spawn_wiggly(k, Vector2(x, -40))
				x += 90.0
		"booms":
			x_row(w, ["confetti", "firework", "paint_bomb", "bubble_bomb", "glue_bomb", "freeze_bomb", "boom_barrel", "mega_boom"], -500.0, 0.0)
		"rides":
			Builders.ride(w, "go_kart", Vector2(-600, 100))
			Builders.ride(w, "monster_truck", Vector2(-300, 60))
			Builders.ride(w, "hot_air", Vector2(100, 0))
			w.spawn_toy("saucer", Vector2(400, -200))
			w.spawn_toy("balloon", Vector2(600, 0))
		"builds":
			for b in [["seesaw", -800.0], ["catapult", -450.0], ["ferris", 0.0], ["rocket_cart", 450.0], ["lamp_show", 850.0]]:
				Builders.build(w, b[0], Vector2(b[1], 50))
		"boom":
			game.get_tree().create_timer(1.5).timeout.connect(func(): ToyLogic.boom(w, Vector2(0, 250), 300.0, 1600.0, false))
			for k in Catalog.WIGGLY_ORDER:
				w.spawn_wiggly(k, Vector2(randf_range(-300, 300), randf_range(-100, 100)))
		"fireworks":
			w.set_night(true)
			for i in 4:
				var f := w.spawn_toy("firework", Vector2(-300 + i * 200, 250))
				if f:
					ToyLogic.light_fuse(w, f)
		"battle":
			w.battle_on = true
		"army":
			var ids := ["soldier", "knight", "viking", "archer", "gunner", "ninja", "giant", "medic"]
			for i in ids.size():
				w.spawn_fighter(ids[i], Vector2(-700 + i * 55, 150), "red", "")
				w.spawn_fighter(ids[i], Vector2(700 - i * 55, 150), "blue", "")
		"dinos":
			for i in 6:
				w.spawn_fighter(["soldier", "gunner", "rocketeer", "soldier", "knight", "sniper"][i], Vector2(-800 + i * 60, 150), "blue", "")
			w.spawn_fighter("trex", Vector2(500, 100), "wild", "")
			w.spawn_fighter("triceratops", Vector2(800, 100), "wild", "")
			w.spawn_fighter("raptor", Vector2(300, 100), "wild", "")
			w.spawn_fighter("ptero", Vector2(200, -250), "wild", "")
		"zoo":
			var x := -900.0
			for k in ["dog", "wolf", "bear", "bull", "elephant", "chicken", "trex", "raptor", "triceratops", "stego", "brachio", "ptero"]:
				var f := w.spawn_fighter(k, Vector2(x, 100), "wild", "peaceful")
				x += float(Catalog.fighter(k).body.x) + 60.0
			w.battle_on = false
		"people":
			var x2 := -700.0
			for k in ["stick", "soldier", "knight", "viking", "archer", "sniper", "rocketeer", "grenadier", "gunner", "medic", "ninja", "giant"]:
				w.spawn_fighter(k, Vector2(x2, 150), ["red", "blue", "green", "yellow"][int(x2) % 4 if x2 >= 0 else 0], "peaceful")
				x2 += 120.0
			w.battle_on = false
		"nukeit":
			for i in 6:
				w.spawn_fighter("soldier", Vector2(-600 + i * 50, 150), "red", "")
				w.spawn_fighter("knight", Vector2(300 + i * 50, 150), "blue", "")
			var n := w.spawn_toy("nuke", Vector2(0, 200))
			if n:
				n.fuse = 1.2
		"vs_powers", "vs_machines", "vs_traps":
			_toyfight(game, name)
		"trap_builds", "combos", "glow", "juice", "ropes", "breaking", "dino_tricks":
			_juice(game, name)
		"ui":
			var ws := w.wigglies()
			if not ws.is_empty():
				game.select(ws[0].uid)
			game.set_tool("paint")
		"night":
			w.set_night(true)
			var bat := w.spawn_toy("battery", Vector2(-200, 200))
			for i in 3:
				var l := w.spawn_toy("lamp", Vector2(-100 + i * 80, 200))
				if bat and l:
					w.add_link("wire", bat, l, bat.global_position, l.global_position)


static func x_row(w: World, ids: Array, x0: float, y: float) -> void:
	var x := x0
	for id in ids:
		w.spawn_toy(id, Vector2(x, y))
		x += 110.0


## Toys and Wiggly powers against fighters, for screenshots: vs_powers (ice,
## bubbles, a zap through wet soldiers, goo; shoot at about 4 s), vs_machines
## (saucer beam, magnet, fan, Gummy; about 3 s) and vs_traps (a pressure plate
## wired to C4, a monster truck, wired dynamite; about 2 s).
static func _toyfight(game: Game, name: String) -> void:
	var w := game.world
	var later := func(sec: float, fn: Callable) -> void:
		game.get_tree().create_timer(sec).timeout.connect(fn)
	var view := func(r: Rect2) -> void:
		later.call(0.05, func(): game.cam.fit(r, game.get_viewport_rect().size))
	w.battle_on = false
	match name:
		"vs_powers":
			view.call(Rect2(-660, -260, 1420, 620))
			var bull := w.spawn_fighter("bull", Vector2(-560, 150), "wild", "attack")
			var stick := w.spawn_fighter("stick", Vector2(-120, 150), "red", "peaceful")
			for i in 2:
				w.spawn_fighter("knight", Vector2(-330 + i * 50, 150), "red", "peaceful")
			for i in 3:
				w.spawn_fighter("soldier", Vector2(40 + i * 45, 150), "blue", "peaceful")
			for i in 4:
				w.spawn_fighter("soldier", Vector2(450 + i * 55, 150), "green", "peaceful")
			var rex := w.spawn_fighter("raptor", Vector2(-200, 150), "wild", "peaceful")
			w.battle_on = true
			if stick:
				stick.max_hp = 9999.0
				stick.hp = 9999.0
			later.call(1.6, func():
				w.freeze_area(Vector2(-330, 220), 260.0, 4.0)
				if bull:
					bull.set_frozen(4.0))
			later.call(2.4, func():
				for f in w.fighters():
					if f.team == "blue":
						f.set_bubble(5.0))
			later.call(2.6, func():
				for f in w.fighters():
					if f.team == "green":
						f.wet = 1.0
				if rex:
					rex.stick(8.0)
				var z := w.spawn_wiggly("zappy", Vector2(700, 200))
				later.call(1.2, func():
					if z:
						z.use_special()))
		"vs_machines":
			view.call(Rect2(-760, -330, 1520, 680))
			var saucer := w.spawn_toy("saucer", Vector2(-520, -200))
			w.spawn_fighter("raptor", Vector2(-520, 150), "wild", "peaceful")
			if saucer:
				saucer.on = true
			var mag := w.spawn_toy("magnet", Vector2(-120, 270))
			if mag:
				mag.nailed = true
				mag.update_freeze()
			w.spawn_fighter("knight", Vector2(60, 150), "red", "peaceful")
			w.spawn_fighter("soldier", Vector2(-260, 150), "blue", "peaceful")
			w.spawn_fighter("gunner", Vector2(-330, 150), "blue", "peaceful")
			var fan := w.spawn_toy("fan", Vector2(220, 262))
			if fan:
				fan.nailed = true
				fan.update_freeze()
			for i in 3:
				w.spawn_fighter("chicken", Vector2(300 + i * 40, 150), "wild", "peaceful")
			w.spawn_fighter("soldier", Vector2(430, 150), "yellow", "peaceful")
			var gum := w.spawn_wiggly("gummy", Vector2(610, 200))
			var trex := w.spawn_fighter("trex", Vector2(680, 100), "wild", "peaceful")
			later.call(1.0, func():
				if mag:
					mag.on = true
				if fan:
					fan.on = true
				if gum:
					gum.use_special()
				if trex:
					trex.stick(8.0))
		"vs_traps":
			view.call(Rect2(-700, -260, 1400, 620))
			# a pressure plate wired to C4 under some knights, a soldier walking onto it,
			# a monster truck driving into vikings, and dynamite a battery sets off later
			var plate := w.spawn_toy("button", Vector2(-60, 290))
			var c4 := w.spawn_toy("c4", Vector2(120, 285))
			if plate:
				plate.nailed = true
				plate.update_freeze()
			if plate and c4:
				w.add_link("wire", plate, c4, plate.global_position, c4.global_position)
			for i in 5:
				w.spawn_fighter("knight", Vector2(60 + i * 45, 150), "blue", "peaceful")
			var walker := w.spawn_fighter("soldier", Vector2(-260, 150), "red", "peaceful")
			for i in 3:
				w.spawn_fighter("viking", Vector2(-420 + i * 50, 150), "green", "peaceful")
			var truck := Builders.ride(w, "monster_truck", Vector2(-640, 200))
			var bat := w.spawn_toy("battery", Vector2(470, 270))
			var dyn := w.spawn_toy("dynamite", Vector2(540, 270))
			for i in 3:
				w.spawn_fighter("gunner", Vector2(580 + i * 45, 150), "yellow", "peaceful")
			later.call(0.3, func():
				if truck:
					truck.on = true
				if walker:
					walker.player_id = 0   # walk it right, onto the plate
					walker.move_input = 1.0)
			later.call(2.0, func():
				if walker:
					walker.player_id = -1
				if bat and dyn:
					w.add_link("wire", bat, dyn, bat.global_position, dyn.global_position))


## For screenshots of the new bits (with --world=canvas): trap_builds (the three
## 🔌 Battle Trap Builds going off, about 3 s), combos (a zap through a pool and
## along metal beams, a Bloop trampoline, Twinkle's warp, a monster truck
## smashing ice; about 2.5 s), glow (night lights: lava, fire, glowing Wigglies,
## laser swords; about 1.5 s), juice (sword swooshes in a close-up melee;
## about 2 s), ropes (sagging ropes; about 1.5 s), breaking (platforms cracked
## and broken by booms; about 2 s) and dino_tricks (a pterodactyl carrying a
## stick figure off, an angry Brachiosaurus; about 3.5 s).
static func _juice(game: Game, name: String) -> void:
	var w := game.world
	var later := func(sec: float, fn: Callable) -> void:
		game.get_tree().create_timer(sec).timeout.connect(fn)
	var view := func(r: Rect2) -> void:
		later.call(0.05, func(): game.cam.fit(r, game.get_viewport_rect().size))
	w._clear_all()   # (no starter Wigglies getting in the way)
	w.battle_on = false
	match name:
		"trap_builds":
			view.call(Rect2(-860, -300, 1720, 640))
			w.spawn("build:trap_minefield", Vector2(-560, 200))
			w.spawn("build:disarm_gate", Vector2(40, 200))
			w.spawn("build:ufo_abductor", Vector2(560, 200))
			var walker := w.spawn_fighter("soldier", Vector2(-820, 150), "red", "peaceful")
			var knight := w.spawn_fighter("knight", Vector2(-160, 150), "blue", "peaceful")
			var rider := w.spawn_fighter("stick", Vector2(400, 150), "green", "peaceful")
			for f in [walker, knight, rider]:
				if f:
					f.max_hp = 9999.0
					f.hp = 9999.0
			later.call(0.3, func():
				for f in [walker, knight, rider]:
					if f:
						f.player_id = 0
						f.move_input = 1.0)
			later.call(1.6, func():
				if rider:
					rider.move_input = 0.0)
		"combos":
			view.call(Rect2(-900, -380, 1800, 760))
			# a pool of soldiers and a Zappy at its edge
			w.apply_command(0, {"cmd": "platform", "x0": -880, "y0": 280, "x1": -320, "y1": 300, "style": "stone"})
			w.apply_command(0, {"cmd": "platform", "x0": -880, "y0": 150, "x1": -860, "y1": 280, "style": "stone"})
			w.apply_command(0, {"cmd": "platform", "x0": -340, "y0": 150, "x1": -320, "y1": 280, "style": "stone"})
			w.add_liquid(Rect2(-860, 170, 520, 110), "water", w.next_group)
			w._cut_water()
			for i in 4:
				w.spawn_fighter("soldier", Vector2(-800 + i * 130, 120), "red", "peaceful")
			var z := w.spawn_wiggly("zappy", Vector2(-300, 60))
			# metal beams in a row, a knight on the far one
			for i in 3:
				var b := w.spawn_toy("metal_beam", Vector2(-160 + i * 160, 285))
				if b:
					b.nailed = true
					b.update_freeze()
			w.spawn_fighter("knight", Vector2(160, 150), "blue", "peaceful")
			var z2 := w.spawn_wiggly("zappy", Vector2(-250, 200))
			# a Bloop trampoline
			var bl := w.spawn_wiggly("bloop", Vector2(420, 230))
			if bl:
				bl.player_id = 99
			var hopper := w.spawn_fighter("ninja", Vector2(420, -150), "green", "peaceful")
			# a monster truck and a frozen soldier
			var truck := Builders.ride(w, "monster_truck", Vector2(560, 220))
			var ice := w.spawn_fighter("soldier", Vector2(820, 150), "yellow", "peaceful")
			later.call(0.6, func():
				if ice:
					ice.set_frozen(4.0)
				if truck:
					truck.on = true)
			later.call(1.9, func():
				if z:
					z.use_special()
				if z2:
					z2.use_special())
		"glow":
			view.call(Rect2(-760, -300, 1520, 640))
			w.set_night(true)
			Builders.tub(w, "lava_tub", Vector2(-480, 300))
			w.fires.append({"p": Vector2(80, 285), "r": 90.0, "t": 30.0})
			for k in ["zappy", "blaze", "twinkle"]:
				var g := w.spawn_wiggly(k, Vector2(-180 + ["zappy", "blaze", "twinkle"].find(k) * 90, 220))
				if g:
					g.player_id = 99
			for i in 2:
				var jedi := w.spawn_fighter("knight", Vector2(330 + i * 160, 150), ["red", "blue"][i], "peaceful")
				var ls := w.spawn_toy("laser_sword", Vector2(330 + i * 160, 150))
				if jedi and ls:
					jedi.equip(ls)
					jedi.facing = 1.0 if i == 0 else -1.0
			var torch := w.spawn_fighter("soldier", Vector2(160, 150), "green", "peaceful")
			if torch:
				torch.max_hp = 9999.0
				torch.hp = 9999.0
				torch.burning = 30.0
		"juice":
			view.call(Rect2(-420, -120, 840, 400))
			for i in 3:
				w.spawn_fighter(["viking", "knight", "ninja"][i], Vector2(-200 + i * 40, 150), "red", "berserk")
				w.spawn_fighter(["giant", "knight", "viking"][i], Vector2(200 - i * 40, 150), "blue", "berserk")
			var jedi := w.spawn_fighter("knight", Vector2(-60, 150), "red", "berserk")
			var ls := w.spawn_toy("laser_sword", Vector2(-60, 150))
			if jedi and ls:
				jedi.equip(ls)
			for f in w.fighters():
				f.max_hp = 9999.0
				f.hp = 9999.0
			w.battle_on = true
		"ropes":
			view.call(Rect2(-600, -320, 1200, 600))
			var posts: Array = []
			for x in [-450.0, -150.0, 150.0, 450.0]:
				var b := w.spawn_toy("wood_block", Vector2(x, -150))
				if b:
					b.nailed = true
					b.update_freeze()
					posts.append(b)
			for i in posts.size() - 1:
				var l := w.add_link("rope", posts[i], posts[i + 1], posts[i].global_position, posts[i + 1].global_position)
				if l:
					l.rest = 300.0 + i * 120.0
			var bal := w.spawn_toy("balloon", Vector2(-300, 0))
			var box := w.spawn_toy("wood_block", Vector2(-300, 200))
			if bal and box:
				w.add_link("rope", bal, box, bal.global_position, box.global_position)
			var gw := w.spawn_wiggly("gummy", Vector2(300, 200))
			if gw:
				gw.mood = "strain"
				gw.grabbed_by[7] = true
				gw.stretch = 2.2
		"breaking":
			view.call(Rect2(-700, -320, 1400, 640))
			w.apply_command(0, {"cmd": "platform", "x0": -600, "y0": 60, "x1": -320, "y1": 84, "style": "wood"})
			w.apply_command(0, {"cmd": "platform", "x0": -140, "y0": 60, "x1": 140, "y1": 84, "style": "stone"})
			w.apply_command(0, {"cmd": "platform", "x0": 320, "y0": 60, "x1": 600, "y1": 84, "style": "concrete"})
			for x in [-460.0, 0.0, 460.0]:
				w.spawn_fighter("soldier", Vector2(x, 0), "red", "peaceful")
			later.call(0.8, func():
				ToyLogic.boom(w, Vector2(-460, 100), 230.0, 1500.0, false, 65.0)
				ToyLogic.boom(w, Vector2(0, 100), 230.0, 1500.0, false, 65.0)
				ToyLogic.boom(w, Vector2(460, 100), 230.0, 1500.0, false, 65.0))
			later.call(1.1, func():
				ToyLogic.boom(w, Vector2(-460, 100), 230.0, 1500.0, false, 65.0))
		"dino_tricks":
			view.call(Rect2(-800, -420, 1600, 760))
			w.spawn_fighter("ptero", Vector2(-700, -150), "wild", "attack")
			var lunch := w.spawn_fighter("stick", Vector2(-350, 150), "red", "peaceful")
			if lunch:
				lunch.max_hp = 9999.0
				lunch.hp = 9999.0
			var brach := w.spawn_fighter("brachio", Vector2(380, 50), "wild", "")
			var pest := w.spawn_fighter("soldier", Vector2(80, 150), "blue", "attack")
			if pest:
				pest.max_hp = 9999.0
				pest.hp = 9999.0
			w.battle_on = true
			later.call(0.5, func():
				if brach and pest:
					brach.hurt(20.0, Vector2.ZERO, pest))


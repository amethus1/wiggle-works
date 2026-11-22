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

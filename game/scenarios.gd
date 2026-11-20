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

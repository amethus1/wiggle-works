extends Node
## Headless checks for 🧩 Army Puzzles and the 🪙 budget they use, the ⭐
## stars of the 📜 History battles, and 🎲 Surprise Battles' fair prices:
## the budget (prices, your side only, refunds, ⏮ Reset, clearing), the
## glowing build zone, the 🧩 tab (cards, locks, stars), setting a puzzle up
## (blue army, coins, goal, prices on the Toy Box), the puzzle keeping its
## army as it is, booms costing points, every stage won by a test army
## (with its stars saved and the next one opened), losing and trying again,
## leaving a puzzle, History stars (finish, change history, hero) and saving
## them all.
## godot --headless --path . -- --test=b3puzzle

const SPEED := 6.0

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map := "grassland") -> void:
	if b and is_instance_valid(b):
		B3Player.stop()
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(99)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 777, "map": map})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


## Knocks `u` out straight away.
func ko(u: B3Unit) -> void:
	if is_instance_valid(u) and not u.dead:
		u.hurt(99999.0, Vector3.UP, 1.0, null, "blast")


func live(team := "") -> int:
	var n := 0
	for u: B3Unit in b.units:
		if is_instance_valid(u) and not u.dead and (team == "" or u.team == team):
			n += 1
	return n


## Every bit of text shown inside `n`.
func texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += texts(c)
	return out


## Fights until someone wins (or `limit` seconds of battle).
func fight(limit := 150.0) -> void:
	b.set_fighting(true)
	var t0: float = b.time
	while b.winner == "" and b.time - t0 < limit:
		await sim(1.0)
	await frames(2)


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	var keep_stickers: Dictionary = Settings.stickers.duplicate(true)
	var keep_puzzles: Dictionary = Settings.b3_puzzles.duplicate(true)
	var keep_hist: Dictionary = Settings.b3_hist_stars.duplicate(true)
	Settings.b3_puzzles = {}
	Settings.b3_hist_stars = {}
	await _budget()
	await _data()
	await _tab()
	await _setup()
	await _guard()
	await _lose_and_retry()
	await _leave()
	await _solve_all()
	await _history_stars()
	await _surprise()
	await _saved()
	B3Player.stop()
	if b and is_instance_valid(b):
		b.queue_free()
		b = null
	Engine.time_scale = 1.0
	await frames(3)
	Settings.stickers = keep_stickers
	Settings.b3_puzzles = keep_puzzles
	Settings.b3_hist_stars = keep_hist
	B3Rules.reset()
	print("test_b3puzzle: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# --------------------------------------------------------------- 🪙 budget
func _budget() -> void:
	print("the 🪙 budget")
	await fresh()
	await frames()
	b.set_budget(10, Rect2(-30, -30, 30, 60), "red")
	check(b.ui.coin_lbl.visible and b.ui.coin_lbl.text == "🪙 10 / 10", "coins show (%s)" % b.ui.coin_lbl.text)
	check(b.zone_vis != null and is_instance_valid(b.zone_vis) and b.zone_vis.get_child_count() == 3, "the build zone glows on the ground")
	b.tools.place_id = "knight"
	b.tools.team = "blue"
	b.tools._place(at(-10, 0), at(-10, 0), false, false)
	check(b.units.size() == 1 and b.units[0].team == "red" and b.spent == 3, "a knight costs 3 and joins red (%d spent)" % b.spent)
	b.tools._place(at(10, 0), at(10, 0), false, false)
	check(b.units.size() == 1, "can't place outside the zone")
	b.tools._place(at(-10, -10), at(-10, 10), true, false)
	check(b.spent <= 10 and b.units.size() == 3, "a dragged line stops when the points run out (%d units, %d spent)" % [b.units.size(), b.spent])
	b.remove_unit(b.units[0])
	check(b.spent == 6, "erasing before the fight refunds (%d)" % b.spent)
	b.tools.place_id = "wall"
	b.tools._place(at(-12, 4), at(-12, 4), false, false)
	check(b.structs.size() == 1 and b.spent == 8, "walls cost 2 (%d)" % b.spent)
	b.set_fighting(true)
	b.remove_unit(b.units[0])
	check(b.spent == 8, "no refund during the fight")
	b.reset_battle()
	await frames()
	check(b.spent == 8 and b.units.size() == 2, "reset keeps what was paid at Fight! (%d spent, %d units)" % [b.spent, b.units.size()])
	b.clear_battlefield()
	check(b.spent == 0 and b.points_left() == 10, "clearing gives everything back")
	b.clear_budget()
	await frames()
	check(not b.ui.coin_lbl.visible and b.points_left() > 1000, "back to free")
	check(b.zone_vis == null, "and the glowing zone is gone")


# ------------------------------------------------------------------- data
func _data() -> void:
	print("the 🧩 stages")
	var n := B3Puzzles.STAGES.size()
	check(n >= 12 and n <= 15, "%d puzzles" % n)
	var ok := true
	var maps := {}
	var vehicles := false
	var dinos := false
	var biggest := 0
	for st: Dictionary in B3Puzzles.STAGES:
		var id := String(st.get("id", ""))
		for k in ["id", "icon", "name", "map", "budget", "goal", "hint", "zone"]:
			if not st.has(k) or str(st[k]) == "":
				ok = false
				print("    %s is missing %s" % [id, k])
		if not B3Defs.MAPS.has(String(st.get("map", ""))):
			ok = false
			print("    %s: no map %s" % [id, st.get("map")])
		maps[st.get("map")] = true
		var zone: Rect2 = st.get("zone", Rect2())
		if zone.size.x < 10.0 or zone.size.y < 10.0 or absf(zone.position.x) > 60 or absf(zone.end.y) > 60:
			ok = false
			print("    %s: odd zone %s" % [id, zone])
		var army := 0
		for e: Array in st.get("enemy", []):
			if not B3Defs.UNITS.has(String(e[0])):
				ok = false
				print("    %s: no fighter %s" % [id, e[0]])
			if zone.grow(2.0).has_point(Vector2(float(e[1]), float(e[2]))):
				ok = false
				print("    %s: enemies start in your zone" % id)
			army += int(e[3]) * int(e[4])
			vehicles = vehicles or B3Defs.is_vehicle(String(e[0]))
			dinos = dinos or String(B3Defs.unit_def(String(e[0])).cat) == "dinos"
		for e: Array in st.get("build", []):
			if String(e[0]) == "top":
				army += 1
		if army == 0 or not B3Puzzles.SOLUTIONS.has(id):
			ok = false
			print("    %s: no army (%d) or no test army" % [id, army])
		biggest = maxi(biggest, int(st.budget))
	check(ok, "each has a name, map, goal, hint, budget, zone, a blue army outside it and a test army")
	check(maps.size() >= 6 and vehicles and dinos, "on %d different maps, with vehicles and dinosaurs" % maps.size())
	var budgets: Array = B3Puzzles.STAGES.map(func(x): return int(x.budget))
	check(int(budgets[0]) <= 12 and int(budgets[1]) <= 12 and int(budgets[-1]) == biggest, "small to start, the biggest last (🪙 %s)" % ", ".join(budgets.map(func(x): return str(x))))
	var st0: Dictionary = B3Puzzles.STAGES[0]
	var c := B3Puzzles.star_costs({"budget": 20})
	check(c[0] == 15 and c[1] == 10 and B3Puzzles.stars_for({"budget": 20}, 10) == 3 and B3Puzzles.stars_for({"budget": 20}, 11) == 2
		and B3Puzzles.stars_for({"budget": 20}, 15) == 2 and B3Puzzles.stars_for({"budget": 20}, 16) == 1,
		"⭐⭐⭐ for half the points or less, ⭐⭐ for three quarters")
	check("⭐⭐" in B3Puzzles.rule_text(st0) and str(B3Puzzles.star_costs(st0)[1]) in B3Puzzles.rule_text(st0), "the rule reads \"%s\"" % B3Puzzles.rule_text(st0))


# -------------------------------------------------------------------- tab
func _tab() -> void:
	print("the 🧩 Puzzles tab")
	await fresh()
	Settings.b3_puzzles = {}
	b.ui._show_history("puzzles")
	await frames()
	var pop: Control = b.ui.popup
	var cards: Node = pop.find_child("Cards", true, false)
	check(cards != null and cards.get_child_count() == B3Puzzles.STAGES.size(), "a card for each puzzle (%d)" % (cards.get_child_count() if cards else 0))
	var tab: Button = pop.find_child("Tab_puzzles", true, false)
	check(tab != null and pop.find_child("Tab_history", true, false) != null and pop.find_child("Tab_ready", true, false) != null, "next to 📜 History and 🎯 Ready-made")
	var first: Node = cards.get_child(0) if cards else null
	var second: Node = cards.get_child(1) if cards else null
	var go1: Button = first.find_child("Go", true, false) if first else null
	var go2: Button = second.find_child("Go", true, false) if second else null
	var t1 := texts(first) if first else ""
	check(go1 != null and not go1.disabled and go2 != null and go2.disabled, "the first one is open, the next is 🔒 locked")
	check("🪙" in t1 and "⭐⭐⭐" in t1 and String((B3Puzzles.STAGES[0] as Dictionary).goal) in t1, "a card shows the goal, the points and the star rule")
	var vw: float = get_viewport().get_visible_rect().size.x
	var r: Rect2 = pop.get_global_rect()
	check(absf(r.get_center().x - vw * 0.5) < 2.0 and r.end.y <= b.ui.dock_holder.get_global_rect().position.y, "the pop-up fits, clear of the tool dock")
	# winning the first opens the second, and its stars show
	Settings.b3_puzzles = {String((B3Puzzles.STAGES[0] as Dictionary).id): 2}
	b.ui._show_history("puzzles")
	await frames()
	cards = b.ui.popup.find_child("Cards", true, false)
	go2 = cards.get_child(1).find_child("Go", true, false)
	var stars: Node = cards.get_child(0).find_child("Stars", true, false)
	check(not go2.disabled and stars != null and texts(stars).begins_with("⭐⭐\n⭐\n"), "a win opens the next one and shows its stars (%s)" % texts(stars).replace("\n", " "))
	check("⭐ 2 of %d" % (B3Puzzles.STAGES.size() * 3) in texts(b.ui.popup), "and the stars add up at the top")
	check(b.ui.hist_tab == "puzzles", "the pop-up remembers the tab")
	b.ui.close_top()
	# --open=puzzles
	b.ui.hist_tab = "history"
	B3Puzzles.open_arg(b, "puzzles")
	await frames()
	check(b.ui.popup != null and b.ui.popup.find_child("Puzzle_sticks", true, false) != null, "--open=puzzles opens it")
	b.ui.close_top()
	B3Puzzles.open_arg(b, "puzzle:sticks:win")
	await sim(1.5)
	check(b.puzzle != null and b.puzzle.id == "sticks" and live("red") == 1 and b.fighting, "--open=puzzle:sticks:win sets it up, places the test army and fights")
	Settings.b3_puzzles = {}


# ------------------------------------------------------------------ set-up
func _setup() -> void:
	print("setting a puzzle up")
	await fresh()
	var st := B3Puzzles.info("archers")
	check(B3Puzzles.start(b, "archers"), "🏹 Arrow Rain sets up")
	await sim(0.5)
	check(b.map_id == "farmland" and b.puzzle != null and b.puzzle.id == "archers", "on its map, with the puzzle on")
	var blue := live("blue")
	check(blue == 10 and live() == blue, "10 blue archers wait, and nobody else (%d)" % blue)
	check(not b.fighting, "waiting for ▶ Fight!")
	check(b.budget == int(st.budget) and b.spent == 0 and b.build_zone == (st.zone as Rect2) and b.build_team == "red", "🪙 %d to spend on your side, for red" % b.budget)
	check(b.zone_vis != null and is_instance_valid(b.zone_vis), "your side glows")
	check(b.ui.coin_lbl.visible and b.ui.coin_lbl.text == "🪙 %d / %d" % [b.budget, b.budget], "the coins show at the top (%s)" % b.ui.coin_lbl.text)
	var box: Control = b.ui.puzzle_box
	check(box != null and box.visible and String(st.goal) in b.ui.puzzle_lbl.text and String(st.hint) in b.ui.puzzle_lbl.text,
		"the goal and a hint sit at the top of the Toy Box")
	b.ui.set_cat("people")
	await frames()
	var kb: Button = b.ui.item_btns.get("knight")
	var tag: Label = kb.get_node_or_null("Price") if kb else null
	check(tag != null and tag.visible and tag.text == "🪙 3", "Toy Box cards show their price (%s)" % (tag.text if tag else "none"))
	var robot: Button = b.ui.item_btns.get("robot")
	b.spent = b.budget - 2
	b.budget_changed.emit()
	check(robot.modulate.a < 0.9 and kb.modulate.a < 0.9 and (b.ui.item_btns.get("stick") as Button).modulate.a == 1.0, "ones you can't pay for are dimmed")
	b.spent = 0
	b.budget_changed.emit()
	var others := 0
	for t in b.ui.team_btns:
		if (b.ui.team_btns[t] as Control).visible:
			others += 1
	check(others == 1 and (b.ui.team_btns.red as Control).visible, "you're always red")
	check((b.ui.size_btns[2.5] as Button).disabled and not (b.ui.size_btns[1.0] as Button).disabled and float(b.tools.place_size) == 1.0, "and fighters are Normal size")
	# the camera shows both sides, with yours on the left
	var zc: Vector2 = (st.zone as Rect2).get_center()
	var me: Vector2 = b.cam.screen_pos(Vector3(zc.x, 0, zc.y))
	var them: Vector2 = b.cam.screen_pos(b.units[0].position)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	check(me.x < them.x and me.x > 300 and them.x < vs.x and me.y > 0 and me.y < vs.y, "the camera shows your side on the left and the archers on the right (%s, %s)" % [me, them])
	# booms cost points too, and only on your side
	var props0: int = b.props.size()
	b.drop("mine", at(-20, 0))
	check(b.props.size() == props0 + 1 and b.spent == 2, "a landmine costs 2 (%d)" % b.spent)
	b.drop("nuke", at(20, 0))
	await sim(0.2)
	check(b.spent == 2 and b.proj_root.get_child_count() == 0, "no booms on their side")
	b.drop("nuke", at(-20, 4))
	check(b.spent == 2 and b.proj_root.get_child_count() == 0, "and no NUKE when you can't pay for it")
	b.load_map("grassland")
	check(b.puzzle == null and b.budget < 0 and b.zone_vis == null and not b.ui.puzzle_box.visible, "changing the map ends the puzzle")
	check(not (b.ui.size_btns[2.5] as Button).disabled and (b.ui.team_btns.blue as Control).visible and not (kb == null or is_instance_valid(kb) and kb.get_node_or_null("Price") != null and kb.get_node("Price").visible),
		"and the Toy Box is back to normal")


# ---------------------------------------------------------- 🧩 the guard
func _guard() -> void:
	print("the puzzle keeps its army")
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.5)
	var u: B3Unit = b.units[0]
	b.remove_unit(u)
	check(is_instance_valid(u) and not u.dead and live("blue") == 10, "the eraser can't remove the puzzle's fighters")
	u.set_team("red")
	u.set_personality("peaceful")
	await sim(0.5)
	check(u.team == "blue" and u.pers_choice == "attack", "they stay blue and in their own mood (%s, %s)" % [u.team, u.pers_choice])
	B3Puzzles.start(b, "towers")
	await sim(0.6)
	var tower: B3Struct = b.structs[0] if not b.structs.is_empty() else null
	b.remove_struct(tower)
	check(tower != null and is_instance_valid(tower) and b.structs.has(tower), "or its buildings")
	var up := 0
	for o: B3Unit in b.units:
		if o.position.y > b.world.height_at(o.position.x, o.position.z) + 3.0:
			up += 1
	check(up == 6, "6 archers stand on top of the towers (%d)" % up)
	b.tools.place_id = "knight"
	b.tools._place(at(-20, 0), at(-20, 0), false, false)
	var mine: B3Unit = b.units[b.units.size() - 1]
	check(mine.team == "red" and b.spent == 3, "your knight costs 3")
	b.remove_unit(mine)
	check(b.spent == 0, "and erasing it before the fight gives the points back")


# ------------------------------------------------------ 😵 lose and retry
func _lose_and_retry() -> void:
	print("losing, and trying again")
	await fresh()
	Settings.b3_puzzles = {}
	B3Puzzles.start(b, "sticks")
	await sim(0.5)
	b.tools.place_id = "stick"
	b.tools._place(at(-18, 0), at(-18, 0), false, false)
	check(b.spent == 1, "one stick figure (1 🪙)")
	await fight()
	check(b.winner == "blue", "loses to ten (%s)" % b.winner)
	await frames(3)
	var card: Control = b.ui.puzzle_card
	check(card != null and card.visible and "Not this time" in texts(card) and not b.ui.score_card.visible, "😵 Not this time! (instead of the scoreboard)")
	check(b.ui.again_btn.visible and "Try again" in b.ui.again_btn.text, "with ⏮ Try again")
	check(B3Puzzles.stars("sticks") == 0 and not B3Puzzles.unlocked("wolves"), "no stars, nothing new opens")
	b.reset_battle()
	await sim(0.3)
	check(live("blue") == 10 and live("red") == 1 and b.spent == 1 and b.puzzle != null, "Try again: the stick figures are back and your army stays")
	check(not card.visible and b.budget == int(B3Puzzles.info("sticks").budget), "the card goes, the budget stays")
	var mine: B3Unit = null
	for u: B3Unit in b.units:
		if u.team == "red":
			mine = u
	b.remove_unit(mine)
	check(b.spent == 0, "and erasing your fighter gives its point back")
	var enemy: B3Unit = b.units[0]
	b.remove_unit(enemy)
	check(is_instance_valid(enemy) and not enemy.dead, "the stick figures still can't be erased")


# ------------------------------------------------------------- leaving
func _leave() -> void:
	print("leaving a puzzle")
	await fresh()
	for how in ["clear", "everything", "history", "ready", "surprise", "puzzle"]:
		B3Puzzles.start(b, "wolves")
		await sim(0.2)
		match how:
			"clear":
				b.clear_units()
			"everything":
				b.clear_all()
			"history":
				b.run_history("hastings")
			"ready":
				b.run_ready("skirmish")
			"surprise":
				B3Surprise.run(b, 5)
			"puzzle":
				B3Puzzles.start(b, "sticks")
		await frames()
		var off: bool = b.budget < 0 and b.zone_vis == null and not b.ui.coin_lbl.visible
		if how == "puzzle":
			check(b.puzzle != null and b.puzzle.id == "sticks" and b.budget == int(B3Puzzles.info("sticks").budget) and b.get_children().filter(func(n): return n is B3Puzzles and not n.is_queued_for_deletion()).size() == 1,
				"another puzzle takes over")
		else:
			check(off and b.puzzle == null, "%s: the budget's off and everything's free" % how)
	b.ui.toggle_palette()
	b.ui.toggle_palette()


# ---------------------------------------------------- ✅ every stage, won
func _solve_all() -> void:
	print("every puzzle can be won")
	Settings.b3_puzzles = {}
	var all_ok := true
	for st: Dictionary in B3Puzzles.STAGES:
		var id := String(st.id)
		await fresh(String(st.map))
		seed(4242)
		check(B3Puzzles.unlocked(id), "%s is open" % id)
		B3Puzzles.start(b, id)
		await sim(0.6)
		var blue := live("blue")
		var spent := B3Puzzles.place_solution(b, id)
		var red := live("red")
		var bad_spot := 0
		for u: B3Unit in b.units:
			if u.team == "red" and not (st.zone as Rect2).has_point(Vector2(u.position.x, u.position.z)):
				bad_spot += 1
		await sim(0.3)
		await fight()
		var tries := 1
		if b.winner != "red":
			# battles have a little luck in them: ⏮ Try again, like a kid would
			print("    %s: %s won the first try, trying again" % [id, b.winner if b.winner != "" else "nobody"])
			b.reset_battle()
			await sim(0.3)
			tries = 2
			await fight()
		var won: bool = b.winner == "red"
		await frames(3)
		var stars := B3Puzzles.stars(id)
		print("    %s: %d red (🪙 %d of %d) vs %d blue -> %s in %ds, ⭐ %d" % [id, red, spent, int(st.budget), blue, b.winner, roundi(b.fight_end_t - b.fight_t0), stars])
		check(won and red > 0 and bad_spot == 0 and spent <= int(st.budget), "%s %s: won with a test army of %d (🪙 %d of %d)%s" % [st.icon, st.name, red, spent, int(st.budget), " on the second try" if tries > 1 else ""])
		check(spent <= B3Puzzles.star_costs(st)[1], "%s: that army is cheap enough for ⭐⭐⭐" % id)
		check(stars == B3Puzzles.stars_for(st, spent) and stars >= 1, "%s: ⭐ x%d saved" % [id, stars])
		all_ok = all_ok and won
		var card: Control = b.ui.puzzle_card
		if id == "sticks":
			check(card != null and card.visible and "Puzzle solved" in texts(card), "🧩 Puzzle solved! shows")
			var lit := 0
			for s: Control in card.find_child("Stars", true, false).get_children():
				if s.modulate.a > 0.9:
					lit += 1
			check(lit == stars, "with its %d stars lit" % lit)
			check(card.find_child("Next", true, false) != null, "and ▶ Next puzzle")
	check(all_ok, "all %d puzzles won" % B3Puzzles.STAGES.size())
	check(Settings.stickers.has("puzzles"), "🧩 solving every puzzle earns the Puzzle Master sticker")
	# ▶ Next puzzle
	await fresh()
	Settings.b3_puzzles = {"sticks": 3}
	B3Puzzles.start(b, "sticks")
	await sim(0.3)
	b.puzzle.over = true
	b.ui.puzzle_result(3, 0, "wolves")
	var nb: Button = b.ui.puzzle_card.find_child("Next", true, false)
	nb.pressed.emit()
	await sim(0.3)
	check(b.puzzle != null and b.puzzle.id == "wolves" and b.map_id == "snow" and not b.ui.puzzle_card.visible, "▶ Next puzzle sets up the next one")
	# a better try keeps the best; a worse one doesn't lower it
	Settings.b3_puzzles = {}
	check(Settings.puzzle_won("wolves", 1) and Settings.puzzle_won("wolves", 3) and not Settings.puzzle_won("wolves", 2) and B3Puzzles.stars("wolves") == 3, "the best stars are kept")


# ------------------------------------------------------ 📜 History stars
func _history_stars() -> void:
	print("📜 History stars")
	await fresh()
	Settings.b3_hist_stars = {}
	var ok := true
	for d: Dictionary in B3History.LIST:
		var won := String(d.get("won", ""))
		var lost := String(d.get("lost", ""))
		if not B3Defs.TEAM.has(won) or not B3Defs.TEAM.has(lost) or won == lost or not B3Defs.TEAM[lost].icon in String(d.sides):
			ok = false
			print("    %s: won %s lost %s" % [d.id, won, lost])
	check(ok, "every battle knows who really won (and who lost)")
	check(B3History.loser_name("thermopylae") == "🔴 Greeks (Spartans)" and B3History.loser_name("gettysburg") == "🟡 Confederates", "the side that lost: %s" % B3History.loser_name("thermopylae"))
	# Hastings: the Normans (blue) won in 1066. Make the Saxons win instead.
	b.run_history("hastings")
	await sim(0.3)
	b.set_fighting(true)
	await sim(0.2)
	for u: B3Unit in b.units.duplicate():
		if u.team == "blue":
			ko(u)
	await sim(1.0)
	var got := B3History.stars_of("hastings")
	check(b.winner == "red" and got.has("finish") and got.has("change") and not got.has("hero"), "the Saxons win: ⭐ finish it and ⭐ change history (%s)" % ", ".join(got.keys()))
	await sim(2.5)
	var toast := texts(b.ui.toasts)
	check("New stars for Hastings" in toast and "Change history" in toast, "a message says so")
	# Agincourt the way it really went, played in first person
	b.run_history("agincourt")
	await sim(0.3)
	var me: B3Unit = null
	for u: B3Unit in b.units:
		if u.team == "red" and u.kind == "longbow":
			me = u
			break
	b.tools.play_as(me, true)
	await sim(0.3)
	b.set_fighting(true)
	await sim(0.2)
	for u: B3Unit in b.units.duplicate():
		if u.team == "blue":
			ko(u)
	await sim(1.0)
	got = B3History.stars_of("agincourt")
	check(b.winner == "red" and got.has("finish") and got.has("hero") and not got.has("change"), "the English win with you in first person: ⭐ finish it and ⭐ hero (%s)" % ", ".join(got.keys()))
	B3Player.stop()
	# a draw gives nothing
	b.run_history("waterloo")
	await sim(0.3)
	b.set_fighting(true)
	for u: B3Unit in b.units.duplicate():
		ko(u)
	await sim(1.0)
	check(b.winner == "nobody" and B3History.stars_of("waterloo").is_empty(), "nobody winning gives no stars")
	# the cards
	b.ui._show_history("history")
	await frames()
	var cards: Node = b.ui.popup.find_child("Cards", true, false)
	var lit := {}
	for c in cards.get_children():
		var row: Node = c.find_child("Stars", true, false)
		if row == null:
			continue
		for l in row.get_children():
			if String(l.name).ends_with("_on"):
				lit[String(l.name)] = int(lit.get(String(l.name), 0)) + 1
	check(int(lit.get("finish_on", 0)) == 2 and int(lit.get("change_on", 0)) == 1 and int(lit.get("hero_on", 0)) == 1, "the History cards light up the stars you have (%s)" % lit)
	var t := texts(cards)
	check("⭐ Finish it" in t and "⭐ Change history" in t and "⭐ Hero" in t, "each card shows its three stars")
	b.ui.close_top()


# ------------------------------------------------------- 🎲 fair armies
func _surprise() -> void:
	print("🎲 Surprise Battles use the same prices")
	await fresh()
	var fair := true
	var worst := ""
	for s in [3, 8, 21, 34, 55]:
		B3Surprise.run(b, s)
		var pts := {}
		for u: B3Unit in b.units:
			if u.team != "wild":
				pts[u.team] = int(pts.get(u.team, 0)) + B3Defs.cost(u.kind)
		var lo := 9999
		var hi := 0
		for t in pts:
			lo = mini(lo, int(pts[t]))
			hi = maxi(hi, int(pts[t]))
		# every army spends the same points (one pick may go a little over)
		if pts.size() < 2 or hi - lo > 15 or lo < 12 or hi > 51:
			fair = false
			worst = "seed %d: %s" % [s, pts]
	check(fair, "every army costs about the same 🪙 %s" % worst)


# --------------------------------------------------------------- saving
func _saved() -> void:
	print("saving the stars")
	var keep_testing := Settings.testing
	var path := "user://test_puzzle_settings.cfg"
	Settings.file = path
	Settings.testing = false
	Settings.b3_puzzles = {}
	Settings.b3_hist_stars = {}
	Settings.puzzle_won("tanks", 2)
	Settings.history_star("alesia", "change")
	Settings.b3_puzzles = {}
	Settings.b3_hist_stars = {}
	Settings.load_settings()
	check(int(Settings.b3_puzzles.get("tanks", 0)) == 2 and B3History.stars_of("alesia").has("change"), "puzzle and History stars are saved and load back")
	Settings.testing = keep_testing
	Settings.file = Settings.PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

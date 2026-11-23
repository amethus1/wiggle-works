extends TestBase
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
## PUZZLE_SEEDS=10 godot --headless --path . -- --test=b3puzzle
##     only fights every stage's test army with 10 different seeds and checks
##     it wins at least 9 of them (about 15 minutes; see _win_rates). Run it
##     after changing a stage or its test army.

const SPEED := 6.0


## A new battle on `map`. `sd` picks other random numbers (_win_rates).
func fresh(map := "grassland", sd := 0) -> void:
	if b and is_instance_valid(b):
		B3Player.stop()
	await drop_battle()
	start_battle(99 + sd, {"seed": 777 + sd * 104729, "map": map})


## Red's health left, from 0 (nobody standing) to 1 (not a scratch), out of
## the `placed` fighters it started with.
func red_health(placed: int) -> float:
	var h := 0.0
	for u: B3Unit in b.units:
		if is_instance_valid(u) and not u.dead and u.team == "red":
			h += clampf(u.hp / u.max_hp, 0.0, 1.0)
	return h / maxf(1.0, placed)


func live(team := "") -> int:
	var n := 0
	for u: B3Unit in b.units:
		if is_instance_valid(u) and not u.dead and (team == "" or u.team == team):
			n += 1
	return n


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
	var seeds := int(OS.get_environment("PUZZLE_SEEDS"))
	if seeds > 0:
		await _win_rates(seeds)
	else:
		await _all()
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
	finish()


func _all() -> void:
	await _budget()
	await _prices()
	await _data()
	await _tab()
	await _setup()
	await _guard()
	await _fair_play()
	await _zone_build()
	await _booms()
	await _rules()
	await _quick_fight()
	await _won_stays()
	await _lose_and_retry()
	await _leave()
	await _solve_all()
	await _history_stars()
	await _surprise()
	await _saves_keep()
	await _saved()


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


## What's on the field adds up to what's been spent (booms that went off aside).
func paid_for() -> int:
	var n := 0
	for arr: Array in [b.units, b.structs, b.hazards, b.props]:
		for o in arr:
			if is_instance_valid(o) and (o as Node).has_meta("cost"):
				n += int((o as Node).get_meta("cost"))
	return n


func last_pool() -> B3Hazard:
	return b.hazards[b.hazards.size() - 1] if not b.hazards.is_empty() else null


## 🪙 Prices by real size, exact refunds (also after ⏮ Reset), crates and
## booms that cost points and give them back.
func _prices() -> void:
	print("🪙 paying for what you really get")
	await fresh()
	await frames()
	b.set_budget(100, Rect2(-30, -30, 60, 60), "red")
	b.tools.place_id = "lava"
	b.tools._place(at(0, 0), at(10, 0), true, false)
	var h := last_pool()
	check(h != null and absf(h.radius - B3Battle.LAKE_R) < 0.01 and int(h.get_meta("cost", 0)) == B3Defs.cost("lava_lake") and b.spent == 8,
		"a lava pool dragged past a lake's size is a lake: as big as one, and it costs as much (r %.1f, 🪙 %d)" % [h.radius if h else 0.0, b.spent])
	b.tools.place_id = "lava_lake"
	b.tools._place(at(12, 12), at(13.5, 12), true, false)
	h = last_pool()
	check(h != null and absf(h.radius - 1.5) < 0.01 and int(h.get_meta("cost", 0)) == B3Defs.cost("lava") and b.spent == 12,
		"a lava lake dragged small is a pool, at a pool's price (🪙 %d)" % b.spent)
	b.tools.place_id = "acid_swamp"
	b.tools._place(at(-29.5, 0), at(-29.5, 0), false, false)
	h = last_pool()
	check(h != null and h.radius <= 1.5 + 0.01 and h.position.x - h.radius >= -31.01 and int(h.get_meta("cost", 0)) == B3Defs.cost("acid"),
		"a pool at the edge of your side stops at the edge (r %.1f), and costs what it is" % (h.radius if h else 0.0))
	# crates: 6 of them for one price, and they go (and pay back) as one
	b.tools.place_id = "crates"
	var s0: int = b.spent
	var p0: int = b.props.size()
	b.tools._place(at(-10, -10), at(-10, -10), false, false)
	var crates: Array = b.props.slice(p0)
	check(crates.size() == 6 and b.spent == s0 + B3Defs.cost("crates"), "📦 a stack of crates costs %d (%d crates, 🪙 %d)" % [B3Defs.cost("crates"), crates.size(), b.spent - s0])
	b.remove_prop(crates[3] as B3Prop)
	await frames()
	check(b.props.size() == p0 and b.spent == s0, "erasing one crate takes the stack and gives its points back (%d props, 🪙 %d)" % [b.props.size(), b.spent])
	check(b.spent == paid_for(), "what's spent is what's on the field (🪙 %d, %d)" % [b.spent, paid_for()])

	# 🧩 the Lava loop: buy, ▶ Fight!, ⏮ Reset, erase... never makes points
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.4)
	b.tools.place_id = "gorilla"
	b.tools._place(at(-18, 0), at(-18, 0), false, false)
	b.tools.place_id = "lava"
	b.tools._place(at(-24, 6), at(-16, 6), true, false)
	check(b.spent == 6 and b.hazards.filter(func(x: B3Hazard) -> bool: return not x.has_meta("puzzle")).is_empty(), "a lake-sized pool needs a lake's points (🪙 %d of 12)" % b.spent)
	var ok := true
	for i in 3:
		b.tools.place_id = "lava"
		b.tools._place(at(-24, 6), at(-19.5, 6), true, false)
		var paid: int = b.spent
		b.set_fighting(true)
		await sim(0.2)
		b.reset_battle()
		await sim(0.2)
		var mine: B3Hazard = null
		for o: B3Hazard in b.hazards:
			if not o.has_meta("puzzle"):
				mine = o
		var kept: int = int(mine.get_meta("cost", -1)) if mine else -1
		if mine:
			b.remove_hazard(mine, true)
		if paid != 10 or kept != 4 or b.spent != 6:
			ok = false
			print("    loop %d: paid %d, the pool kept %d, then 🪙 %d" % [i, paid, kept, b.spent])
	check(ok, "🌋 buy a pool, Fight!, ⏮ Reset, erase it: you get back what you paid, never more (🪙 %d)" % b.spent)
	# a landmine and C4 give their points back too, before and after ⏮ Reset
	b.drop("mine", at(-20, -6))
	b.drop("c4", at(-20, 6))
	var mn: B3Prop = null
	for pr: B3Prop in b.props:
		if pr.kind == "mine":
			mn = pr
	check(b.spent == 6 + 2 + 3 and mn != null and int(mn.get_meta("cost", 0)) == 2, "🪤 a landmine costs 2 and keeps it (🪙 %d)" % b.spent)
	b.remove_prop(mn)
	check(b.spent == 9, "erasing it gives them back (🪙 %d)" % b.spent)
	b.set_fighting(true)
	await sim(0.2)
	b.reset_battle()
	await sim(0.2)
	var c4: B3Prop = null
	for pr: B3Prop in b.props:
		if pr.kind == "c4":
			c4 = pr
	check(c4 != null and int(c4.get_meta("cost", 0)) == 3 and b.spent == paid_for(), "after ⏮ Reset the C4 still knows its price (🪙 %d, %d on the field)" % [b.spent, paid_for()])
	if c4:
		b.remove_prop(c4)
	check(b.spent == 6, "and erasing it then gives back exactly that (🪙 %d)" % b.spent)


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


# ------------------------------------------------------- 🛡️ fair play
func _blue() -> B3Unit:
	for u: B3Unit in b.units:
		if u.team == "blue" and not u.dead:
			return u
	return null


func _red() -> B3Unit:
	for u: B3Unit in b.units:
		if u.team == "red" and not u.dead:
			return u
	return null


## One rule (B3Battle.protected / hands_off) for the Eraser, the Inspector,
## 🎮 Play as, ✋ Grab and 🚀 Launch, and fair play with your own army.
func _fair_play() -> void:
	print("🛡️ the puzzle's army is hands off, and yours plays fair")
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.4)
	var en := _blue()
	check(b.protected(en) and not b.protected(null), "the puzzle's fighters are protected")
	b.tools.select(en)
	await frames()
	(b.ui.insp_acts.launch as Button).pressed.emit()
	(b.ui.insp_pers.peaceful as Button).pressed.emit()
	(b.ui.insp_team.green as Button).pressed.emit()
	en.hp = 5.0
	(b.ui.insp_acts.heal as Button).pressed.emit()
	(b.ui.insp_acts.erase as Button).pressed.emit()
	check(is_instance_valid(en) and not en.dead and not en.down and en.pers_choice == "attack" and en.team == "blue" and en.hp == 5.0,
		"🔍 the Inspector can't 🚀 launch, 🌼 calm, recolour, 💚 heal or 🗑️ remove them (down %s, %s, %s)" % [en.down, en.pers_choice, en.team])
	b.tools.select(en)
	await frames()
	check((b.ui.insp_acts.launch as Control).modulate.a < 0.5 and (b.ui.insp_pers.attack as Control).modulate.a < 0.5,
		"those buttons are dimmed for them")
	b.tools.play_as(en)
	check(B3Player.unit != en and not b.fighting, "🎮 you can't play as one of them")
	var sp: Vector2 = b.cam.screen_pos(en.center())
	check(not b.tools._grab_start(sp) and not en.held, "✋ or grab one")
	b.tools._erase_at(sp)
	check(is_instance_valid(en) and not en.dead and live("blue") == 10, "🧽 or erase one with the Eraser")
	# your own army
	b.tools.place_id = "knight"
	b.tools._place(at(-20, 0), at(-20, 0), false, false)
	var me := _red()
	check(me != null and not b.protected(me), "your knight isn't protected")
	b.tools.select(me)
	await frames()
	me.hp = 10.0
	(b.ui.insp_acts.heal as Button).pressed.emit()
	(b.ui.insp_acts.launch as Button).pressed.emit()
	(b.ui.insp_team.blue as Button).pressed.emit()
	(b.ui.insp_pers.defend as Button).pressed.emit()
	check(me.hp == 10.0 and not me.down and me.team == "red" and me.pers_choice == "defend" and b.spent == 3,
		"your own: no free 💚 heal or 🚀 launch, it stays red, but you can change its mood (%.0f hp, down %s, %s, %s)" % [me.hp, me.down, me.team, me.pers_choice])
	# ✋ moving it before the fight: only about your side, and it's put down, not thrown
	var msp: Vector2 = b.cam.screen_pos(me.center())
	check(b.tools._grab_start(msp), "✋ you can pick your knight up before the fight")
	b.tools._mouse = b.cam.screen_pos(at(20, 0))
	await sim(1.0)
	b.tools._grab_end(true)
	await sim(2.5)
	var zone: Rect2 = (B3Puzzles.info("sticks").zone as Rect2).grow(1.0)
	var mp: Vector3 = me.center()
	check(zone.has_point(Vector2(mp.x, mp.z)), "...but it stays on your side (at x %.1f)" % mp.x)
	b.tools._erase_at(b.cam.screen_pos(me.center()))
	check(not is_instance_valid(me) or me.dead or not b.units.has(me), "🧽 you can still erase your own")
	check(b.spent == 0, "for your points back (🪙 %d)" % b.spent)
	# during the fight
	b.tools._place(at(-20, 0), at(-20, 0), false, false)
	me = _red()
	b.tools.play_as(me)
	check(B3Player.unit == me and b.fighting, "🎮 you can play your own (and that starts the fight)")
	b.tools.stop_playing()
	B3Player.stop()
	check(not b.tools._grab_start(b.cam.screen_pos(me.center())), "✋ no grabbing once the fight's on")
	en = _blue()
	en.set_personality("peaceful")
	await sim(0.5)
	check(en.pers_choice == "attack", "and the blue army keeps its mood during the fight too (%s)" % en.pers_choice)


## 🚧 Every building you place has to stand on your side, dragged or not.
func _zone_build() -> void:
	print("🚧 buildings stay on your side")
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.4)
	var zone: Rect2 = (B3Puzzles.info("sticks").zone as Rect2).grow(B3Battle.ZONE_SLACK + 0.01)
	var n0: int = b.structs.size()
	b.tools.place_id = "wall"
	b.tools._place(at(-30, 0), at(16, 0), true, false)
	var all_in: bool = b.structs.size() == n0 + 1
	if all_in:
		for pc: B3Piece in (b.structs[n0] as B3Struct).pieces:
			var bb := pc.world_aabb()
			all_in = all_in and zone.has_point(Vector2(bb.position.x, bb.position.z)) and zone.has_point(Vector2(bb.end.x, bb.end.z))
	check(all_in and b.spent == 2, "a wall dragged towards the blue army stops at the edge of your side")
	b.tools.place_id = "bridge"
	b.tools._place(at(-15, 0), at(-15, 0), false, false)
	b.tools.place_id = "tower"
	b.tools._place(at(-14.2, 11.5), at(-14.2, 11.5), false, false)
	check(b.structs.size() == n0 + 1 and b.spent == 2, "a bridge or tower that would stick out past your side isn't built (or paid for)")
	b.tools._place(at(-24, 0), at(-24, 0), false, false)
	check(b.structs.size() == n0 + 2 and b.spent == 7, "one in the middle is")


## 💣 Booms in a puzzle: the big ones are off, and anything that hurts the
## blue army before ▶ Fight! is put right when you press it.
func _booms() -> void:
	print("💣 booms in a puzzle")
	await fresh("volcano")
	B3Puzzles.start(b, "finale")
	await sim(0.4)
	var blue := live("blue")
	for boom in B3Puzzles.BIG_BOOMS:
		b.drop(String(boom), at(-19, 0))
	await sim(0.2)
	check(b.spent == 0 and b.proj_root.get_child_count() == 0 and b.planes.is_empty(), "☢️ no nukes, ✈️ airstrikes or ☄️ artillery in a puzzle")
	b.ui.set_cat("booms")
	await frames()
	var tag: Label = (b.ui.item_btns.nuke as Button).get_node_or_null("Price")
	check(tag != null and tag.text == "🚫" and (b.ui.item_btns.nuke as Control).modulate.a < 0.9 and (b.ui.item_btns.mine.get_node("Price") as Label).text == "🪙 2",
		"their cards say 🚫 (the small ones still have a price)")
	# hurt, moved or knocked out before the fight: all put back at ▶ Fight!
	var es: Array = b.units.filter(func(u: B3Unit) -> bool: return u.team == "blue")
	ko(es[0])
	ko(es[1])
	(es[2] as B3Unit).hp *= 0.3
	(es[3] as B3Unit).knock_down(Vector3(0, 6, 0))
	await sim(0.5)
	b.set_fighting(true)
	await frames()
	var saved: int = (b.start_layout.get("units", []) as Array).filter(func(e: Dictionary) -> bool: return String(e.t) == "blue").size()
	var full := true
	for u: B3Unit in b.units:
		if u.team == "blue" and not u.dead and (u.hp < u.max_hp - 0.5 or u.down):
			full = false
	check(live("blue") == blue and saved == blue and full, "▶ Fight! puts back a blue army hurt before the fight, all %d of them (%d saved for ⏮ Reset)" % [live("blue"), saved])
	# all of them gone before the fight can't leave a puzzle you can't win
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.4)
	b.tools.place_id = "gorilla"
	b.tools._place(at(-18, 0), at(-18, 0), false, false)
	for u: B3Unit in b.units.duplicate():
		if u.team == "blue":
			ko(u)
	await sim(0.5)
	b.set_fighting(true)
	await sim(0.5)
	check(live("blue") == 10 and b.winner == "", "even when every one of them was knocked out first (%d blue, winner '%s')" % [live("blue"), b.winner])


## ⚙️ Your Battle Rules don't leak into a puzzle, and come back after.
func _rules() -> void:
	print("⚙️ puzzles use the normal rules")
	var shake0 := B3Rules.value("shake")
	B3Rules.reset()
	B3Rules.set_value("respawn", "on")
	B3Rules.set_value("booms", "mega")
	B3Rules.set_value("health", "glass")
	B3Rules.set_value("shake", "lots")
	await fresh()
	B3Puzzles.start(b, "sticks")
	await sim(0.3)
	check(not B3Rules.respawn() and B3Rules.boom_r() == 1.0 and B3Rules.toughness() == 1.0 and B3Rules.value("shake") == "lots",
		"♾️ no reinforcements, normal blasts and toughness (screen shake stays how you like it)")
	check(String(Settings.b3_rules.get("respawn", "")) == "on" and String(Settings.b3_rules.get("booms", "")) == "mega", "your own rules are still saved")
	b.ui._show_rules()
	await frames()
	var note: Node = b.ui.popup.find_child("PuzzleRules", true, false)
	var locked := 0
	var open := 0
	for c in b.ui.popup.find_children("*", "Button", true, false):
		if (c as Button).disabled:
			locked += 1
		elif "Lots" in (c as Button).text or "little" in (c as Button).text:
			open += 1
	check(note != null and locked >= 20 and open >= 2, "the ⚙️ panel says so and only Screen shake can change (%d locked)" % locked)
	b.ui.close_top()
	# a kid who loses can't turn MEGA on halfway through
	b.ui._show_rules()
	await frames()
	for c in b.ui.popup.find_children("*", "Button", true, false):
		if "A little" in (c as Button).text:
			(c as Button).pressed.emit()
			break
	await frames()
	check(B3Rules.value("shake") == "little" and String(Settings.b3_rules.get("shake", "")) == "little" and String(Settings.b3_rules.get("booms", "")) == "mega",
		"changing Screen shake in a puzzle keeps the rest of your rules")
	b.ui.close_top()
	b.load_map("grassland")
	check(B3Rules.respawn() and B3Rules.value("booms") == "mega" and B3Rules.value("health") == "glass", "leaving the puzzle brings your rules back")
	B3Rules.reset()
	B3Rules.set_value("shake", shake0)


## 🗼 Fight! straight away on Tower Archers still has the archers up top.
func _quick_fight() -> void:
	print("🗼 a quick ▶ Fight!")
	await fresh("farmland")
	B3Puzzles.start(b, "towers")
	b.set_fighting(true)
	var n: int = (b.start_layout.get("units", []) as Array).size()
	await sim(0.6)
	var up := 0
	for o: B3Unit in b.units:
		if o.team == "blue" and o.position.y > b.world.height_at(o.position.x, o.position.z) + 3.0:
			up += 1
	check(n == 9 and up == 6, "Space right away still remembers all 9 for ⏮ Reset (%d), with 6 archers up the towers (%d)" % [n, up])
	b.reset_battle()
	await sim(0.6)
	up = 0
	for o: B3Unit in b.units:
		if o.team == "blue" and o.position.y > b.world.height_at(o.position.x, o.position.z) + 3.0:
			up += 1
	check(live("blue") == 9 and up == 6, "and ⏮ Try again puts them all back up there (%d)" % up)
	# 🐺 the Animals tab doesn't turn your side brown
	b.ui.set_cat("animals")
	await frames()
	var red_sb: StyleBoxFlat = (b.ui.team_btns.red as Button).get_theme_stylebox("normal") as StyleBoxFlat
	check(b.tools.place_team() == "red" and red_sb != null and red_sb.border_width_left == 4, "on the Animals tab your side is still red (and lit)")


## 🏆 A won puzzle stays won on screen when the last red fighter burns out after.
func _won_stays() -> void:
	print("🏆 a win stays a win")
	await fresh()
	Settings.b3_puzzles = {}
	B3Puzzles.start(b, "sticks")
	await sim(0.4)
	b.tools.place_id = "gorilla"
	b.tools._place(at(-18, 0), at(-18, 0), false, false)
	b.set_fighting(true)
	await sim(0.3)
	for u: B3Unit in b.units.duplicate():
		if u.team == "blue":
			ko(u)
	await sim(1.0)
	await frames(3)
	var head: String = b.ui.banner_lbl.text.split("\n")[0]
	check(b.winner == "red" and b.ui.puzzle_card.visible and not b.ui.score_card.visible, "red wins: the ⭐ card shows")
	ko(_red())
	await sim(1.0)
	await frames(3)
	check(b.winner == "nobody" and b.ui.puzzle_card.visible and not b.ui.score_card.visible and b.ui.banner_lbl.text.split("\n")[0] == head and B3Puzzles.stars("sticks") == 3,
		"the gorilla burning out afterwards leaves the win, its banner and its ⭐ card up (not the scoreboard)")
	Settings.b3_puzzles = {}


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
		print("    %s: %d red (🪙 %d of %d) vs %d blue -> %s in %ds with %.0f%% of red's health left, ⭐ %d" % [id, red, spent, int(st.budget), blue, b.winner, roundi(b.fight_end_t - b.fight_t0), 100.0 * red_health(red), stars])
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


## PUZZLE_SEEDS=N: every stage's test army (B3Puzzles.SOLUTIONS) fights its
## puzzle N times with different random numbers, with no second tries, and
## has to win at least 9 times in 10. A test army that only just wins (and so
## sometimes loses _solve_all's two tries) shows up here first.
func _win_rates(n: int) -> void:
	print("every puzzle's test army, %d seeds each" % n)
	for st: Dictionary in B3Puzzles.STAGES:
		var id := String(st.id)
		var wins := 0
		var health := 0.0
		var line := ""
		for i in n:
			await fresh(String(st.map), i + 1)
			seed(4242 + i + 1)
			B3Puzzles.start(b, id)
			await sim(0.6)
			B3Puzzles.place_solution(b, id)
			var red := live("red")
			await sim(0.3)
			await fight()
			if b.winner == "red":
				wins += 1
			health += red_health(red)
			line += "W" if b.winner == "red" else "L"
		check(wins * 10 >= n * 9, "%s %s: the test army wins %d of %d, with %.0f%% of its health left on average (%s)" % [st.icon, st.name, wins, n, 100.0 * health / n, line])


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


# ------------------------------------------------- 💾 what a save keeps
## A loaded History battle still earns its ⭐ stars; planes keep their
## height and parked ones stay parked.
func _saves_keep() -> void:
	print("💾 saves keep the History battle and flying heights")
	await fresh()
	Settings.b3_hist_stars = {}
	b.run_history("hastings")
	await sim(0.3)
	check(B3Saves.save(b, 6), "saving Hastings")
	b.load_map("grassland")
	check(B3Saves.load_slot(b, 6) and b.history_id == "hastings", "loading it, it's still 📜 Hastings ('%s')" % b.history_id)
	b.set_fighting(true)
	await sim(0.2)
	for u: B3Unit in b.units.duplicate():
		if u.team == "blue":
			ko(u)
	await sim(1.0)
	check(b.winner == "red" and B3History.stars_of("hastings").has("finish") and B3History.stars_of("hastings").has("change"),
		"and winning it earns its ⭐ stars (%s)" % ", ".join(B3History.stars_of("hastings").keys()))
	B3Saves.delete_all_test_saves()
	Settings.b3_hist_stars = {}
	await fresh()
	var heli: B3Aircraft = b.spawn_unit("heli", "red", at(0, 0)) as B3Aircraft
	var plane: B3Aircraft = b.spawn_unit("plane", "blue", at(10, 10)) as B3Aircraft
	heli.parked = true
	plane.alt = 33.5
	await sim(0.3)
	var d: Dictionary = B3Saves.snapshot(b)
	B3Saves.restore(b, JSON.parse_string(JSON.stringify(d)) as Dictionary, false, true)
	await sim(0.3)
	var h2: B3Aircraft = null
	var p2: B3Aircraft = null
	for u: B3Unit in b.units:
		if u.kind == "heli":
			h2 = u as B3Aircraft
		elif u.kind == "plane":
			p2 = u as B3Aircraft
	check(h2 != null and h2.parked and p2 != null and absf(p2.alt - 33.5) < 0.01, "a parked helicopter stays parked and a plane keeps its height")


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

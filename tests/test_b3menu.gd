extends Node
## Headless checks for the 📜 pop-up's 🎯 Ready-made tab, the 🏆 scoreboard
## under the winner banner (and the copy a friend gets), and the 3D Battle
## 📒 stickers, plus the title screen's Sticker Book.
## godot --headless --path . -- --test=b3menu

const SPEED := 4.0
const NEW_STICKERS := ["b3win", "ace", "tankbuster", "historybuff", "fphero"]

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map := "grassland", more := {}) -> void:
	if b and is_instance_valid(b):
		B3Player.stop()
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(99)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	var opts := {"seed": 777, "map": map}
	opts.merge(more, true)
	b.begin(opts)
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


## Knocks `u` out straight away, as if `by` did it.
func ko(u: B3Unit, by: B3Unit = null) -> void:
	if is_instance_valid(u) and not u.dead:
		u.hurt(99999.0, Vector3.UP, 1.0, by, "blast")


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


func live(team := "") -> int:
	var n := 0
	for u: B3Unit in b.units:
		if is_instance_valid(u) and not u.dead and (team == "" or u.team == team):
			n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	var keep_stickers: Dictionary = Settings.stickers.duplicate(true)
	var keep_counters: Dictionary = Settings.counters.duplicate(true)
	await _ready_tab()
	await _ready_setups()
	await _ready_fight()
	await _scoreboard()
	await _scoreboard_real()
	await _sticker_list()
	await _stickers_playing()
	await _stickers_battles()
	await _stickers_history()
	B3Player.stop()
	if b and is_instance_valid(b):
		b.queue_free()
		b = null
	Engine.time_scale = 1.0
	await frames(3)
	await _sticker_book()
	Settings.stickers = keep_stickers
	Settings.counters = keep_counters
	B3Rules.reset()
	for i in 3:
		await get_tree().process_frame
	print("test_b3menu: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------ 🎯 Ready-made
func _ready_tab() -> void:
	print("the 🎯 Ready-made tab")
	await fresh()
	var ids: Array = []
	for e in B3Scenarios.MENU:
		ids.append(String((e as Dictionary).id))
	var want := ["skirmish", "waves", "dinos", "nuke", "hazards", "structures", "animals", "chaos", "big", "c4", "vehicles", "monsters", "airshow", "roadtrip", "hangar"]
	var all_in := true
	for id in want:
		all_in = all_in and id in ids
	check(all_in and ids.size() == want.size(), "all %d ready-made battles are in the list" % ids.size())
	var full := true
	for e in B3Scenarios.MENU:
		var d: Dictionary = e
		full = full and String(d.icon) != "" and String(d.name) != "" and String(d.sides) != "" and String(d.desc) != ""
	check(full, "each one has a picture, a name, who's fighting and a few words")
	var buttons_before: int = b.ui.top_bar.get_child_count()
	b.ui._show_history("ready")
	await frames()
	var pop: Control = b.ui.popup
	var cards: Node = pop.find_child("Cards", true, false)
	check(cards != null and cards.get_child_count() == ids.size(), "📜 opens on the 🎯 Ready-made tab with a card for each (%d)" % (cards.get_child_count() if cards else 0))
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y
	var r: Rect2 = pop.get_global_rect()
	var dock: Rect2 = b.ui.dock_holder.get_global_rect()
	check(absf(r.get_center().x - vw * 0.5) < 2.0 and r.position.y >= 0.0 and r.end.y <= dock.position.y,
		"the pop-up sits in the middle, clear of the tool dock (%.0f to %.0f, dock at %.0f)" % [r.position.y, r.end.y, dock.position.y])
	var sc: ScrollContainer = cards.get_parent() if cards else null
	check(sc != null and cards.get_combined_minimum_size().y > sc.size.y, "and the cards scroll")
	var all_go := true
	for c in cards.get_children():
		all_go = all_go and (c as Node).find_child("Go", true, false) is Button
	check(all_go, "every card has ▶ Set it up")
	check(b.ui.top_bar.get_child_count() == buttons_before, "no new button on the top bar")
	# the tabs
	var tab_h: Button = pop.find_child("Tab_history", true, false)
	var tab_r: Button = pop.find_child("Tab_ready", true, false)
	check(tab_h != null and tab_r != null, "the pop-up has 📜 History and 🎯 Ready-made tabs")
	tab_h.pressed.emit()
	await frames()
	cards = b.ui.popup.find_child("Cards", true, false)
	check(b.ui.hist_tab == "history" and cards and cards.get_child_count() == B3History.available().size(), "📜 History shows the History battles (%d)" % (cards.get_child_count() if cards else 0))
	b.ui.close_top()
	b.ui._show_history()
	await frames()
	check(b.ui.hist_tab == "history" and b.ui.popup.find_child("Cards", true, false).get_child_count() == B3History.available().size(), "📜 opens on the tab you used last")
	(b.ui.popup.find_child("Tab_ready", true, false) as Button).pressed.emit()
	await frames()
	cards = b.ui.popup.find_child("Cards", true, false)
	# pick Skirmish
	var go: Button = cards.get_child(ids.find("skirmish")).find_child("Go", true, false)
	go.pressed.emit()
	await frames()
	check(b.ui.popup == null or not is_instance_valid(b.ui.popup), "picking one closes the pop-up")
	check(b.ready_id == "skirmish" and live() > 30 and b.map_id == B3Scenarios.map_for("skirmish"), "and sets up Skirmish (%d fighters)" % live())
	await sim(1.5)
	check(not b.fighting and b.kos == 0, "ready to press Fight!: nobody fights yet")
	# only the host can pick
	b.puppet = true
	b.ui.refresh_net()
	var n0 := live()
	check(b.ui.hist_btn.disabled and not b.run_ready("dinos") and live() == n0, "in a friend's battle 📜 is off and nothing gets set up")
	b.puppet = false
	b.ui.refresh_net()
	check(not b.ui.hist_btn.disabled, "(and it's back on for the host)")
	# --open=ready
	await fresh("grassland", {"open": "ready"})
	await frames()
	check(b.ui.popup != null and b.ui.hist_tab == "ready" and b.ui.popup.find_child("Cards", true, false).get_child_count() == ids.size(), "--open=ready opens the 🎯 Ready-made tab")


func _ready_setups() -> void:
	print("setting up every ready-made battle")
	await fresh()
	b.cam.rotate_view(1.0)
	var bad: Array = []
	var still: Array = []
	for e in B3Scenarios.MENU:
		var id := String((e as Dictionary).id)
		var ok: bool = b.run_ready(id)
		await sim(1.2)
		if not ok or live() == 0 or b.map_id != B3Scenarios.map_for(id) or b.ready_id != id:
			bad.append(id)
		if b.fighting or b.kos > 0:
			still.append(id)
		if id == "c4" and b.c4_count() != 5:
			bad.append("c4 (%d C4)" % b.c4_count())
		b.kos = 0
	check(bad.is_empty(), "each sets up on its own map %s" % ("" if bad.is_empty() else str(bad)))
	check(still.is_empty(), "and waits for ▶ Fight! %s" % ("" if still.is_empty() else str(still)))
	check(absf(b.cam.yaw_target - 45.0) < 0.01, "with the camera turned the usual way")


func _ready_fight() -> void:
	print("ready-made battles once Fight! is pressed")
	await fresh()
	Settings.stickers.erase("nuke")
	b.run_ready("nuke")
	await sim(2.0)
	var n0 := live()
	check(b.kos == 0 and n0 > 40, "☢️ Nuke!: no nuke before Fight! (%d fighters)" % n0)
	b.toggle_play()
	await sim(7.0)
	check(b.fighting and b.kos > 10, "it falls once Fight! is pressed (%d knocked out)" % b.kos)
	check(Settings.stickers.has("nuke"), "📒 and that earns Big Bada Boom")
	var k1: int = b.kos
	b.reset_battle()
	await sim(0.5)
	check(b.ready_id == "nuke" and live() == n0 and not b.fighting, "⏮ Play it again puts the armies back (%d)" % live())
	b.toggle_play()
	await sim(7.0)
	check(b.kos - k1 > 10, "and the nuke falls again (%d more)" % (b.kos - k1))
	b.run_ready("c4")
	await sim(1.0)
	check(b.c4_count() == 5, "📟 C4 Surprise: 5 C4 waiting")
	b.toggle_play()
	await sim(3.5)
	check(b.c4_count() == 0 and b.kos > 0, "they go off after Fight! (%d knocked out)" % b.kos)
	b.clear_units()
	check(b.ready_id == "", "🧹 clearing the fighters forgets the ready-made battle")
	# --scenario= still starts by itself
	await fresh("", {"scenario": "c4"})
	await sim(3.0)
	check(b.fighting and b.c4_count() == 0, "--scenario=c4 still starts the fight and the C4 by itself")


# --------------------------------------------------------------- 🏆 scoreboard
func _scoreboard() -> void:
	print("the 🏆 scoreboard")
	await fresh()
	var r1: B3Unit = b.spawn_unit("knight", "red", at(-4, 0), "peaceful")
	var r2: B3Unit = b.spawn_unit("knight", "red", at(-4, 3), "peaceful")
	var b1: B3Unit = b.spawn_unit("viking", "blue", at(4, 0), "peaceful")
	var b2: B3Unit = b.spawn_unit("viking", "blue", at(4, 3), "peaceful")
	var b3: B3Unit = b.spawn_unit("viking", "blue", at(4, 6), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	await sim(3.0)
	ko(b1, r1)
	ko(b2, r1)
	ko(r1, b3)       # the red knight with 2 knock-outs is knocked out himself
	await sim(0.5)
	ko(b3, r2)
	await sim(1.0)
	check(b.winner == "red", "red wins (%s)" % b.winner)
	var ui = b.ui
	var head := String(ui.banner_lbl.text).split("\n")[0]
	check(ui.banner_lbl.visible and head.contains("Red wins") and ui.banner_lbl.visible_characters == head.length(), "the banner shows \"%s\"" % head)
	check(ui.banner_lbl.get_minimum_size().y < 130.0 and ui.banner_lbl.get_minimum_size().x <= 1000.0, "just the headline (%.0f tall)" % ui.banner_lbl.get_minimum_size().y)
	check(ui.again_btn.visible and ui.score_card.visible, "with ⏮ Play it again and the scoreboard")
	var sc: Dictionary = B3Battle.read_score(b.scoreboard())
	check(String(sc.get("win", "")) == "red", "the scoreboard knows who won")
	check(int(sc.get("secs", -1)) >= 3 and int(sc.get("secs", -1)) <= 6, "and how long it took (%d s)" % int(sc.get("secs", -1)))
	var rows := {}
	for e: Dictionary in sc.get("teams", []):
		rows[String(e.team)] = [int(e.brought), int(e.left), int(e.kos)]
	check(rows.get("red") == [2, 1, 3] and rows.get("blue") == [3, 0, 1], "fighters, survivors and knock-outs for each team (%s)" % str(rows))
	var top: Array = sc.get("top", [])
	var top_s := ""
	for e: Dictionary in top:
		top_s += "%s %s %d, " % [e.team, e.kind, int(e.kos)]
	check(top.size() == 3 and String(top[0].kind) == "knight" and int(top[0].kos) == 2 and String(top[0].team) == "red",
		"the top fighter, even though he was knocked out (%s)" % top_s)
	check(top.size() == 3 and String(top[1].team) == "blue" and String(top[2].team) == "red", "a tie goes to whoever got there first")
	await frames()
	var t := texts(ui.score_card)
	check(t.contains("Scoreboard") and t.contains("1 of 2 left") and t.contains("0 of 3 left") and t.contains("3 knock-outs")
		and t.contains("🥇") and t.contains("Red Knight") and t.contains("seconds"), "the card shows it all")
	var cr: Rect2 = ui.score_card.get_global_rect()
	var ar: Rect2 = ui.again_btn.get_global_rect()
	var vw: float = get_viewport().get_visible_rect().size.x
	var dock: Rect2 = ui.dock_holder.get_global_rect()
	check(cr.position.y >= ar.end.y and cr.end.y <= dock.position.y and absf(cr.get_center().x - vw * 0.5) < 2.0,
		"under ⏮ Play it again, in the middle, clear of the dock (%.0f to %.0f)" % [cr.position.y, cr.end.y])
	check(b.mvp_text().contains("Knight"), "the ⭐ MVP is still named (%s)" % b.mvp_text())
	# a friend's copy: the banner's text (all the host sends) brings the scoreboard along
	var full := String(ui.banner_lbl.text)
	var shown := t
	ui.hide_banner()
	check(not ui.score_card.visible, "hiding the banner hides the scoreboard")
	b.puppet = true
	Settings.stickers.erase("b3win")
	ui.banner(full, Color.RED)
	await frames()
	check(ui.score_card.visible and texts(ui.score_card) == shown and ui.banner_lbl.visible_characters == head.length(), "👥 a friend's copy shows the same scoreboard from the banner's text")
	check(Settings.stickers.has("b3win"), "📒 friends earn 🏆 Victory! too")
	var junk := "Hi\nt|purple|1|2|3\nf|red|nosuchthing|5\nw|red\nt|red|x|1|1\ns|-5\nt|red|3|2|1\nt|red|9|9|9\n"
	for i in 40:
		junk += "f|red|knight|99999999999\n"
	ui.banner(junk, Color.WHITE)
	await frames()
	var jt := texts(ui.score_card)
	check(ui.score_card.visible and jt.count("left") == 1 and jt.count("knock-outs") <= 4, "made-up lines are left out")
	ui.banner("Just words", Color.WHITE)
	check(not ui.score_card.visible and ui.banner_lbl.visible, "a banner without a scoreboard shows no card")
	b.puppet = false
	ui.banner(full, Color.RED)
	# ✖ and ⏮
	var x: Button = null
	for c in ui.score_card.find_children("*", "Button", true, false):
		if (c as Button).text == "✖":
			x = c
	check(x != null, "the card has a ✖")
	if x:
		x.pressed.emit()
		check(not ui.score_card.visible and ui.banner_lbl.visible, "✖ hides just the card")
	ui.banner(full, Color.RED)
	b.reset_battle()
	await frames()
	check(not ui.banner_lbl.visible and not ui.score_card.visible, "⏮ Play it again puts the banner and card away")
	# a draw
	await fresh()
	var a: B3Unit = b.spawn_unit("soldier", "red", at(-3, 0), "peaceful")
	var c: B3Unit = b.spawn_unit("soldier", "blue", at(3, 0), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	await sim(0.5)
	ko(a)
	ko(c)
	await sim(1.0)
	sc = B3Battle.read_score(b.scoreboard())
	check(b.winner == "nobody" and String(b.ui.banner_lbl.text).begins_with(B3Battle.DRAW_TXT) and b.ui.score_card.visible and String(sc.win) == "nobody",
		"a draw gets a scoreboard too")
	check(int(sc.others) == 2 and texts(b.ui.score_card).contains("Booms, lava and falls: 2 knock-outs"), "knock-outs by booms count on their own line")
	# the winners keep getting knocked out after the banner: the card keeps up
	await fresh()
	var reds: Array = []
	for i in 3:
		reds.append(b.spawn_unit("soldier", "red", at(-4, -3 + i * 3.0), "peaceful"))
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(4, 0), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	await sim(1.0)
	ko(foe, reds[0])
	await sim(1.0)
	var secs0 := int(B3Battle.read_score(b.scoreboard()).secs)
	check(b.winner == "red" and texts(b.ui.score_card).contains("3 of 3 left"), "red wins with 3 of 3 left")
	var bounce: float = b.ui._banner_t
	ko(reds[2])
	await sim(1.5)
	var tx := texts(b.ui.score_card)
	check(tx.contains("2 of 3 left") and tx.contains("Booms, lava and falls: 1 knock-out"), "one of them gets knocked out afterwards: 2 of 3 left")
	check(int(B3Battle.read_score(b.scoreboard()).secs) == secs0 and b.ui._banner_t > bounce, "the time stays when it was won, and the banner doesn't bounce again")
	check(B3Battle.time_text(45) == "45 seconds" and B3Battle.time_text(61) == "1 minute 1 second" and B3Battle.time_text(120) == "2 minutes",
		"times read \"45 seconds\", \"1 minute 1 second\", \"2 minutes\"")


## A real fight to the end.
func _scoreboard_real() -> void:
	print("a real fight's scoreboard")
	await fresh()
	for i in 4:
		b.spawn_unit("giant", "red", at(-4, -3 + i * 2.0), "attack")
	for i in 3:
		b.spawn_unit("stick", "blue", at(4, -2 + i * 2.0), "attack")
	await sim(0.3)
	b.set_fighting(true)
	var t := 0.0
	while b.winner == "" and t < 60.0:
		await sim(1.0)
		t += 1.0
	await sim(0.5)
	var sc: Dictionary = B3Battle.read_score(b.scoreboard())
	check(b.winner != "" and b.ui.score_card.visible, "the fight ends with a scoreboard (%s after %.0f s)" % [b.winner, t])
	var team_sum := 0
	var left_ok := true
	for e: Dictionary in sc.get("teams", []):
		team_sum += int(e.kos)
		left_ok = left_ok and int(e.left) == live(String(e.team))
	var top_sum := 0
	for e: Dictionary in sc.get("top", []):
		top_sum += int(e.kos)
	check(left_ok and team_sum + int(sc.get("others", 0)) == b.kos and top_sum <= team_sum and int(sc.get("secs", 0)) >= int(t) - 2,
		"its numbers add up (%d knock-outs by teams, %d by booms, %d in the top 3, %d in all)" % [team_sum, int(sc.get("others", 0)), top_sum, b.kos])


# ------------------------------------------------------------------ 📒 stickers
func _sticker_list() -> void:
	print("the sticker list")
	var ids := {}
	var ok := true
	for s in Catalog.STICKERS:
		var d: Dictionary = s
		ok = ok and not ids.has(d.id) and String(d.emoji) != "" and String(d.name) != "" and String(d.desc) != "" and String(d.desc).length() <= 60
		ids[d.id] = true
	check(ok, "every sticker has its own id, a picture, a name and a short goal")
	var new_in := true
	for id in NEW_STICKERS:
		new_in = new_in and ids.has(id)
	check(new_in and Catalog.STICKERS.size() >= 26 and Catalog.STICKERS.size() <= 28, "the new 3D Battle stickers are in the book (%d in all)" % Catalog.STICKERS.size())


func _stickers_playing() -> void:
	print("stickers for playing")
	Settings.stickers = {}
	Settings.counters = {}
	# ✈️ Ace Pilot
	await fresh()
	var plane: B3Unit = b.spawn_unit("plane", "red", at(-10, 0), "peaceful")
	var foes: Array = []
	for i in 3:
		foes.append(b.spawn_unit("soldier", "blue", at(10, i * 3.0), "peaceful"))
	await sim(0.3)
	b.tools.play_as(plane)
	await sim(0.3)
	check(plane is B3Aircraft and B3Player.unit == plane, "playing the fighter plane")
	ko(foes[0], plane)
	ko(foes[1], plane)
	check(not Settings.stickers.has("ace"), "two knock-outs from the plane: not yet")
	ko(foes[2], plane)
	check(Settings.stickers.has("ace"), "three: ✈️ Ace Pilot!")
	var popped := false
	for c in b.ui.sticker_box.get_children():
		popped = popped or String((c as Node).get_meta("sticker", "")) == "ace"
	await frames()
	var sr: Rect2 = b.ui.sticker_box.get_global_rect()
	var vw: float = get_viewport().get_visible_rect().size.x
	check(popped and texts(b.ui.sticker_box).contains("Ace Pilot") and sr.end.x <= vw and sr.position.x > vw * 0.5 + 280.0,
		"a 📒 New sticker! message pops up at the top right, clear of the banner (%.0f to %.0f)" % [sr.position.x, sr.end.x])
	# 🦸 Hero: knock-outs while you play a person (not the computer's)
	await fresh()
	var me: B3Unit = b.spawn_unit("soldier", "red", at(-5, 0), "peaceful")
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(-5, 3), "peaceful")
	foes = []
	for i in 6:
		foes.append(b.spawn_unit("stick", "blue", at(6, -6 + i * 2.5), "peaceful"))
	await sim(0.3)
	b.tools.play_as(me)
	await sim(0.3)
	ko(foes[5], mate)
	check(int(Settings.counters.get("b3_hero_kos", 0)) == 0, "a teammate's knock-out doesn't count for you")
	for i in 4:
		ko(foes[i], me)
	check(not Settings.stickers.has("hero"), "four of yours: not yet")
	ko(foes[4], me)
	check(Settings.stickers.has("hero"), "five: 🦸 Hero!")
	# 🧨 Tank Buster
	await fresh()
	var t1: B3Unit = b.spawn_unit("tank", "blue", at(0, 0), "peaceful")
	var t2: B3Unit = b.spawn_unit("tank", "blue", at(0, 12), "peaceful")
	var ai: B3Unit = b.spawn_unit("rocketeer", "red", at(-12, 0), "peaceful")
	await sim(0.3)
	ko(t1, ai)
	await sim(0.2)
	check(b.kos == 1 and not Settings.stickers.has("tankbuster"), "the computer's rocketeer wrecking a tank doesn't count")
	ko(t2)
	await sim(0.2)
	check(b.kos == 2 and Settings.stickers.has("tankbuster"), "a boom wrecking one does: 🧨 Tank Buster!")
	# 👀 First-Person Hero
	await fresh()
	me = b.spawn_unit("soldier", "red", at(-4, 0), "peaceful")
	var foe: B3Unit = b.spawn_unit("stick", "blue", at(4, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me)
	await sim(0.3)
	ko(foe, me)
	await sim(1.0)
	check(b.winner == "red" and Settings.stickers.has("b3win") and not Settings.stickers.has("fphero"), "winning while playing overhead: 🏆 Victory! but not First-Person Hero")
	await fresh()
	me = b.spawn_unit("soldier", "red", at(-4, 0), "peaceful")
	foe = b.spawn_unit("stick", "blue", at(4, 0), "peaceful")
	await sim(0.3)
	b.tools.play_as(me, true)
	await sim(0.3)
	check(B3Player.me.fp, "playing in first person")
	ko(foe, me)
	await sim(1.0)
	check(b.winner == "red" and Settings.stickers.has("fphero"), "your side wins: 👀 First-Person Hero!")
	B3Player.stop()
	# ☢️ and 🎆
	await fresh()
	b.drop("grenade", at(20, 20))
	check(int(Settings.counters.get("booms", 0)) == 1, "a grenade counts toward 🎆 Boom Boom Boom")
	b.drop("nuke", at(40, 40))
	check(Settings.stickers.has("nuke"), "dropping a nuke: ☢️ Big Bada Boom!")
	for i in 8:
		b.drop("dynamite", at(-20 - i * 2.0, 20))
	check(Settings.stickers.has("boom"), "ten booms: 🎆 Boom Boom Boom! (%d)" % int(Settings.counters.get("booms", 0)))
	await sim(4.0)


func _stickers_battles() -> void:
	print("🎖️ General")
	for big in [true, false]:
		Settings.stickers.erase("general")
		await fresh()
		var reds: Array = []
		var blues: Array = []
		for i in (5 if big else 6):
			reds.append(b.spawn_unit("soldier", "red", at(-6, -6 + i * 2.0), "peaceful"))
		for i in (5 if big else 2):
			blues.append(b.spawn_unit("soldier", "blue", at(6, -6 + i * 2.0), "peaceful"))
		await sim(0.3)
		b.set_fighting(true)
		await sim(0.3)
		for u in blues:
			ko(u, reds[0])
		await sim(1.0)
		if big:
			check(b.winner == "red" and Settings.stickers.has("general"), "5 against 5: 🎖️ General")
		else:
			check(b.winner == "red" and not Settings.stickers.has("general"), "6 against 2: not a General's battle")


func _stickers_history() -> void:
	print("📜 History Buff")
	Settings.stickers.erase("historybuff")
	Settings.counters.erase("b3_history")
	await fresh()
	var done := 0
	for id in ["hastings", "hastings", "alesia", "agincourt"]:
		b.run_history(id)
		await sim(0.4)
		check(b.history_id == id, "%s is set up" % id)
		b.set_fighting(true)
		await sim(0.5)
		if id == "alesia":
			b.reset_battle()
			await sim(0.4)
			check(b.history_id == "alesia", "⏮ Play it again: still Alesia")
			b.set_fighting(true)
			await sim(0.5)
		var keep := String(b.units[0].team)
		for u: B3Unit in b.units.duplicate():
			if u.team != keep:
				ko(u)
		var t := 0.0
		while b.winner == "" and t < 5.0:
			await sim(0.5)
			t += 0.5
		done += 1
		var sc: Dictionary = B3Battle.read_score(b.scoreboard())
		if id == "alesia":
			check(String(sc.get("hist", "")) == "alesia", "the scoreboard says it was Alesia")
		if done < 4:
			check(b.winner != "" and not Settings.stickers.has("historybuff"), "finishing %s: %d different so far" % [id, (Settings.counters.get("b3_history", {}) as Dictionary).size()])
	check(Settings.stickers.has("historybuff"), "the third different one: 📜 History Buff!")


# ------------------------------------------------------- 📒 the title screen's book
func _sticker_book() -> void:
	print("the title screen's 📒 Sticker Book")
	Settings.stickers = {"b3win": true, "ace": true, "hello": true}
	var m = load("res://ui/menu.gd").new()
	add_child(m)
	await frames()
	m._stickers()
	await frames(4)
	var shade: Control = m.modal
	var sc: ScrollContainer = shade.find_children("*", "ScrollContainer", true, false)[0] if not shade.find_children("*", "ScrollContainer", true, false).is_empty() else null
	var grid: GridContainer = sc.get_child(0) if sc else null
	var vh: float = get_viewport().get_visible_rect().size.y
	var p: Control = shade.get_child(0)
	var r: Rect2 = p.get_global_rect()
	check(grid != null and grid.get_child_count() == Catalog.STICKERS.size(), "every sticker is in the book (%d)" % (grid.get_child_count() if grid else 0))
	check(r.position.y >= 0.0 and r.end.y <= vh, "the book fits on the screen (%.0f to %.0f of %.0f)" % [r.position.y, r.end.y, vh])
	check(sc != null and grid.get_combined_minimum_size().y > sc.size.y, "and the stickers scroll")
	check(texts(shade).contains("(3 / %d)" % Catalog.STICKERS.size()), "the title counts the ones you have")
	m.queue_free()
	await frames()

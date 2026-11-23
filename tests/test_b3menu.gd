extends TestBase
## Headless checks for the 📜 pop-up's 🎯 Ready-made tab, the 🏆 scoreboard
## under the winner banner (and the copy a friend gets), and the 3D Battle
## 📒 stickers, plus the title screen's Sticker Book. Also the 3D HUD: pop-ups
## on a dimmed backdrop, ❓ Help, 🔧 Settings, 🔍 Toy Box search, "are you
## sure?" before clearing, team letters, and nothing overlapping at 720p.
## godot --headless --path . -- --test=b3menu

const SPEED := 4.0
const NEW_STICKERS := ["b3win", "ace", "tankbuster", "historybuff", "fphero"]


func fresh(map := "grassland", more := {}) -> void:
	if b and is_instance_valid(b):
		B3Player.stop()
	await drop_battle()
	var opts := {"seed": 777, "map": map}
	opts.merge(more, true)
	start_battle(99, opts)


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
	await _score_fixes()
	await _sticker_fixes()
	await _ui_popups()
	await _ui_layout()
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
	finish()


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
	check(not Settings.stickers.has("nuke"), "📒 a nuke the battle drops by itself doesn't earn Big Bada Boom (you didn't drop it)")
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
	var booms0 := int(Settings.counters.get("booms", 0))
	b.toggle_play()
	await sim(3.5)
	check(b.c4_count() == 0 and b.kos > 0, "they go off after Fight! (%d knocked out)" % b.kos)
	check(int(Settings.counters.get("booms", 0)) == booms0, "📒 and count for no stickers either")
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


# ------------------------------------------- 🏆 who gets the knock-outs
func gone(u) -> bool:
	return not is_instance_valid(u) or u.dead


## Knocking out a teammate (🤝 Blasts hurt teammates) or yourself scores
## nothing; finishing off an enemy lying on the ground does.
func _score_fixes() -> void:
	print("🏆 who gets the knock-outs")
	await fresh()
	B3Rules.set_value("friendly", "on")
	b.apply_rules()
	var gr: B3Unit = b.spawn_unit("grenadier", "red", at(-10, 0), "peaceful")
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(0, 0), "peaceful")
	var f1: B3Unit = b.spawn_unit("soldier", "blue", at(0, 1.2), "peaceful")
	var f2: B3Unit = b.spawn_unit("soldier", "blue", at(12, 0), "peaceful")
	var f3: B3Unit = b.spawn_unit("soldier", "blue", at(12, 4), "peaceful")
	b.spawn_unit("soldier", "blue", at(30, 30), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	mate.hp = 1.0
	f1.hp = 1.0
	b.explode(at(0, 0.6) + Vector3(0, 0.5, 0), 3.0, 8.0, 50.0, {"by": gr})
	await sim(0.1)
	check(gone(mate) and gone(f1), "(the grenade knocks out a teammate and an enemy)")
	check(gr.kills == 1 and int(b.team_kos.get("red", 0)) == 1, "only the enemy counts for the grenadier and red (%d, %d)" % [gr.kills, int(b.team_kos.get("red", 0))])
	ko(f2, f2)
	check(int(b.team_kos.get("blue", 0)) == 0 and f2.kills == 0, "knocking yourself out doesn't count for blue either")
	# finishing off an enemy lying on the ground
	f3.knock_down(Vector3(0, 2, 0))
	await sim(0.3)
	f3.hp = 3.0
	var top0 := gr.kills
	b.explode(f3.center(), 2.5, 4.0, 40.0, {"by": gr})
	await sim(0.1)
	check(gone(f3) and gr.kills == top0 + 1 and int(b.team_kos.get("red", 0)) == 2, "finishing off an enemy lying down counts (%d knock-outs)" % gr.kills)
	var tops: Array = []
	for ln: String in b.scoreboard():
		if ln.begins_with("f|"):
			tops.append(ln)
	check(tops == ["f|red|grenadier|2"], "and the 🏆 scoreboard says 2 for the grenadier (%s)" % str(tops))
	var mate2: B3Unit = b.spawn_unit("knight", "red", at(-14, 0), "peaceful")
	await sim(0.2)
	mate2.hp = 1.0
	b.explode(mate2.center(), 2.0, 4.0, 40.0, {"by": gr})
	await sim(0.1)
	check(gone(mate2) and gr.kills == 2 and String(b.mvp.get("kind", "")) == "grenadier" and int(b.mvp.get("kills", 0)) == 2, "another teammate later doesn't make it an ⭐ MVP with 3 (%d)" % int(b.mvp.get("kills", 0)))
	B3Rules.reset()
	b.apply_rules()


## 🦸 Hero on horseback, the sticker rules friends share (B3Net asks
## B3Battle.ko_stickers_for about the fighter a friend plays and sends the
## answer on) and the ⭐ Change history message.
func _sticker_fixes() -> void:
	print("📒 more stickers")
	Settings.counters.erase("b3_hero_kos")
	Settings.stickers.erase("hero")
	await fresh()
	var me: B3Unit = b.spawn_unit("horseknight", "red", at(-6, 0), "peaceful")
	var foes: Array = []
	for i in 5:
		foes.append(b.spawn_unit("stick", "blue", at(6, -6 + i * 3.0), "peaceful"))
	await sim(0.3)
	b.tools.play_as(me)
	await sim(0.2)
	for f in foes:
		ko(f, me)
	check(Settings.stickers.has("hero"), "🏇 five knock-outs on horseback: 🦸 Hero! (a rider's a person too)")
	b.tools.stop_playing()
	var pl: B3Unit = b.spawn_unit("plane", "red", at(-10, 0), "peaceful")
	var cav: B3Unit = b.spawn_unit("cavalry", "red", at(-14, 4), "peaceful")
	var mate: B3Unit = b.spawn_unit("soldier", "red", at(-14, 8), "peaceful")
	var foe: B3Unit = b.spawn_unit("soldier", "blue", at(10, 0), "peaceful")
	var tk: B3Unit = b.spawn_unit("tank", "blue", at(10, 20), "peaceful")
	await sim(0.3)
	var got := func(by: B3Unit, u: B3Unit, mine: bool) -> String:
		return ",".join(B3Battle.ko_stickers_for(by, u, mine))
	check(got.call(pl, foe, true) == "ace" and got.call(cav, foe, true) == "hero" and got.call(pl, tk, true) == "ace,tankbuster",
		"👥 the rules a friend's knock-outs go by: ✈️ from a plane, 🦸 on horseback, 🧨 a tank")
	check(got.call(cav, mate, true) == "" and got.call(cav, foe, false) == "" and got.call(cav, tk, false) == "" and got.call(null, tk, false) == "tankbuster",
		"nothing for knocking out a teammate or someone else's knock-out, but a tank wrecked by a boom counts")
	# the ⭐ Change history star names the side that lost long ago
	var keep: Variant = Settings.b3_hist_stars.duplicate(true)
	Settings.b3_hist_stars.erase("thermopylae")
	for c in b.ui.toasts.get_children():
		c.free()
	B3History.earn_stars(b, "thermopylae", String(B3History.info("thermopylae").get("lost", "")))
	await sim(2.5)
	var said := texts(b.ui.toasts)
	check(said.contains("Change history") and said.contains(B3History.loser_name("thermopylae")), "⭐ Change history says who won this time (%s)" % said.strip_edges())
	Settings.b3_hist_stars = keep


# ------------------------------------------------------------ 3D HUD bits
func _click(c: Control, at := Vector2(5, 5)) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	c.gui_input.emit(ev)


func _ui_popups() -> void:
	print("3D pop-ups, help, settings and the Toy Box search")
	await fresh("grassland")
	var ui = b.ui
	ui._show_rules()
	await frames()
	var shade: Control = ui.popup.get_parent()
	var vp: Rect2 = get_viewport().get_visible_rect()
	check(shade is ColorRect and shade.mouse_filter == Control.MOUSE_FILTER_STOP and shade.get_global_rect().encloses(vp) and (shade as ColorRect).color.a >= 0.4,
		"a pop-up sits on a dimmed backdrop that covers the screen and stops clicks")
	check(shade.get_index() == ui.root.get_child_count() - 1, "...on top of the bars")
	_click(shade)
	await frames()
	check(ui.popup == null and not is_instance_valid(shade), "clicking the backdrop closes it")
	# keys and a gamepad work in pop-ups, but the bars never take focus (Space is Fight!)
	check((ui.play_btn as Control).get_focus_mode_with_override() == Control.FOCUS_NONE
		and (ui.tool_btns.place as Control).get_focus_mode_with_override() == Control.FOCUS_NONE, "the bars' buttons never take keyboard focus")
	ui._show_map_menu()
	await frames()
	var first := UI.first_focus(ui.popup)
	check(first != null and first.get_focus_mode_with_override() == Control.FOCUS_ALL and not first.has_meta("no_first"), "a pop-up's buttons can take focus (arrows, Tab, a gamepad)")
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	ui._input(down)
	await frames()
	check(get_viewport().gui_get_focus_owner() == first, "an arrow key wakes up the ring on its first button")
	ui.close_top()
	await frames()
	# ❓ Help: short sections, with what's new
	ui.toggle_help()
	await frames()
	var ht := texts(ui.help)
	check(ui.help.get_parent().get_parent() is ColorRect, "❓ Help sits on the backdrop too")
	var has_all := true
	for w in ["Puzzle", "Wave Defense", "Right-click", "Tab", "Undo", "drag a box", "King of the Hill", "🔍", "chop", "cover", "burn",
			"crush", "parachute", "treads", "keep"]:
		if not ht.contains(w):
			has_all = false
			print("    (help is missing '%s')" % w)
	check(has_all, "❓ Help tells about puzzles, waves and the keep, right-click powers, Tab, Undo, box-select and what fighters, fire, tanks and planes do")
	ui.toggle_help()
	await frames()
	check(ui.help == null or not is_instance_valid(ui.help), "and closes again")
	# 🔧 Settings: the shared pop-up, with 3D's smooth edges, from the ⚙️ pop-up
	ui._show_rules()
	await frames()
	var sb: Button = ui.popup.find_child("Settings", true, false)
	check(sb != null, "⚙️ Battle Rules has a 🔧 Settings button")
	if sb:
		sb.pressed.emit()
	else:
		ui.show_settings()
	await frames()
	var sp: Node = null
	for c in ui.popup.find_children("*", "HBoxContainer", true, false):
		if c is SettingsPanel:
			sp = c
	check(sp != null and sp.find_child("Smooth3D", true, false) != null and sp.find_child("Slider_volume", true, false) != null
		and sp.find_child("NameEdit", true, false) != null, "🔧 Settings in 3D: sound, music, name and color, smooth edges")
	var sm: Button = sp.find_child("Smooth3D", true, false) if sp else null
	var was: bool = Settings.smooth_3d
	if sm:
		sm.pressed.emit()
		check(Settings.smooth_3d == not was and sm.text.begins_with("✅" if not was else "⬜"), "the ✨ Smooth edges switch changes Settings.smooth_3d")
		sm.pressed.emit()
		check(Settings.smooth_3d == was, "and back")
	ui.close_top()
	# team letters
	check((ui.team_btns.red as Button).text == "R" and (ui.team_btns.wild as Button).text == "🐾" and (ui.insp_team.blue as Button).text == "B",
		"team colours have a letter on them (R, B, G, Y, 🐾)")
	# 🔍 search in the Toy Box
	ui.search.text = "rex"
	ui.search.text_changed.emit("rex")
	await frames()
	check(ui.item_btns.has("trex") and ui.item_btns.size() <= 3, "🔍 'rex' finds the T-Rex from any tab (%s)" % ", ".join(ui.item_btns.keys()))
	check(ui.team_box.visible, "with the team and mood pickers for it")
	ui.search.text = "tank"
	ui.search.text_changed.emit("tank")
	await frames()
	check(ui.item_btns.has("tank") and not ui.cat_btns.vehicles.get_theme_stylebox("normal").bg_color.is_equal_approx(UI.ACCENT), "'tank' finds the tank, and no tab is lit while searching")
	ui.set_cat("booms")
	await frames()
	check(ui.search.text == "" and ui.item_btns.has("nuke") and ui.item_btns.size() == B3Defs.BOOM_ORDER.size(), "picking a tab stops searching")
	ui.set_cat("people")
	# "are you sure?" before clearing or a new map with an army on the field
	b.spawn_unit("soldier", "red", at(0, 0))
	await frames()
	ui._show_clear_menu()
	await frames()
	var every: Button = null
	for c in ui.popup.find_children("*", "Button", true, false):
		if (c as Button).text.contains("Everything"):
			every = c
	every.pressed.emit()
	await frames()
	check(ui.popup != null and ui.popup.has_meta("confirm") and b.units.size() == 1, "🧹 Everything asks first when there's an army")
	(ui.popup.find_child("No", true, false) as Button).pressed.emit()
	await frames()
	check(ui.popup == null and b.units.size() == 1, "✋ No keeps it")
	ui._show_map_menu()
	await frames()
	var snow: Button = null
	for c in ui.popup.find_children("*", "Button", true, false):
		if (c as Button).text.contains("Snow"):
			snow = c
	snow.pressed.emit()
	await frames()
	check(ui.popup != null and ui.popup.has_meta("confirm") and b.map_id == "grassland", "🗺️ a new map asks first too")
	(ui.popup.find_child("Yes", true, false) as Button).pressed.emit()
	await frames()
	check(b.map_id == "snow" and b.units.is_empty(), "and Yes changes it")
	ui._show_map_menu()
	await frames()
	for c in ui.popup.find_children("*", "Button", true, false):
		if (c as Button).text.contains("Desert"):
			(c as Button).pressed.emit()
	await frames()
	check(b.map_id == "desert" and (ui.popup == null or not ui.popup.has_meta("confirm")), "with nothing on the field it doesn't ask")
	# the dock goes back to the middle when the Toy Box is hidden
	var vw: float = get_viewport().get_visible_rect().size.x
	ui.toggle_palette()
	await frames()
	var dr: Rect2 = ui.dock_holder.get_global_rect()
	check(not ui.palette.visible and absf(dr.get_center().x - vw * 0.5) < 2.0, "hiding the Toy Box puts the tool dock back in the middle (%.0f)" % dr.get_center().x)
	ui.toggle_palette()
	await frames()
	dr = ui.dock_holder.get_global_rect()
	check(ui.palette.visible and dr.position.x > ui.palette.get_global_rect().end.x, "and with it out, the dock is clear of it")


## At 720p (and with ⚙️ Huge buttons) the panels that share the screen
## don't land on each other.
func _ui_layout() -> void:
	print("the 3D HUD at 720p")
	await fresh("grassland", {"scenario": "waves"})
	var ui = b.ui
	# a 1280 x 720 screen, one pixel per pixel
	var root_win := get_tree().root
	var keep_size := root_win.size
	var keep_css := root_win.content_scale_size
	root_win.size = Vector2i(1280, 720)
	root_win.content_scale_size = Vector2i(1280, 720)
	await frames(4)
	var vp: Rect2 = get_viewport().get_visible_rect()
	check(vp.size.is_equal_approx(Vector2(1280, 720)), "(the screen is 1280 x 720 now: %s)" % vp.size)
	# 5 teams, points and friends: the top bar still fits
	var x := -20.0
	for t in B3Defs.TEAM_ORDER:
		b.spawn_unit("soldier", String(t), at(x, 30))
		x += 3.0
	ui.counts_dirty = true
	b.budget_changed.emit()
	await sim(0.6)
	check(ui.top_bar.get_combined_minimum_size().x <= vp.size.x - 20.0 + 1.0, "the top bar fits across (%.0f of %.0f)" % [ui.top_bar.get_combined_minimum_size().x, vp.size.x])
	var me: B3Unit = null
	for u: B3Unit in b.units:
		if u.team == "red" and not u.dead and String(u.def.body) == "human":
			me = u
	b.tools.select(me)
	await sim(0.4)
	var mh: Rect2 = ui.mode_hud.get_global_rect()
	var ir: Rect2 = ui.inspect.get_global_rect()
	var dk: Rect2 = ui.dock_holder.get_global_rect()
	check(ui.mode_hud.mouse_filter == Control.MOUSE_FILTER_STOP, "🌊 the wave panel stops clicks (nothing is placed under it)")
	check(ui.mode_hud.visible and ui.inspect.visible and not ir.intersects(mh) and ir.end.y <= dk.position.y and vp.encloses(ir),
		"the Inspector is clear of the wave panel and the tool dock (%s, %s, %s)" % [ir, mh, dk])
	var st: Control = ui.sticker_box
	check(absf(st.offset_top - (ui.mode_hud.offset_top + ui.mode_hud.get_combined_minimum_size().y + 8.0)) < 1.0, "📒 sticker messages go right under the panel as it is now")
	b.tools.play_as(me)
	await sim(0.5)
	var pp: Rect2 = ui.power_pill.get_global_rect()
	check(not ui.power_pill.visible or not pp.intersects(ui.mode_hud.get_global_rect()), "the power pill is clear of the wave panel")
	b.tools.stop_playing()
	# the winner banner: old messages go, new ones go under the scoreboard
	ui.toast("🌊 Wave 2: Stick figures and soldiers!")
	ui.toast("The attackers are at the keep!")
	await frames()
	ui.banner("💥 The keep fell on wave 2!", Color.ORANGE, b.scoreboard())
	await frames(3)
	check(ui.toasts.get_child_count() == 0, "the winner banner clears the old messages behind it")
	ui.toast("⭐ Your best: wave 1")
	await frames(3)
	await get_tree().process_frame
	var br: Rect2 = ui.banner_lbl.get_global_rect()
	var tr: Rect2 = ui.toasts.get_global_rect()
	var ar: Rect2 = ui.again_btn.get_global_rect()
	check(tr.position.y >= ar.end.y and tr.position.y >= br.end.y, "new messages go under the banner and ⏮ Play it again (%.0f, banner ends %.0f)" % [tr.position.y, br.end.y])
	if ui.score_card.visible:
		var cr: Rect2 = ui.score_card.get_global_rect()
		check(cr.end.y <= ui.dock_holder.get_global_rect().position.y + 1.0 and cr.position.y >= ar.end.y, "the 🏆 scoreboard fits between ⏮ and the dock (%s)" % cr)
	check(ui.banner_lbl.size.x <= vp.size.x, "the banner fits across the screen")
	ui.hide_banner()
	# ⚙️ Huge buttons on that screen: the top bar squeezes up and still fits
	root_win.content_scale_size = Vector2i(1440, 880)
	Settings.set_ui_scale(1.3)
	await sim(0.6)
	vp = get_viewport().get_visible_rect()
	check(ui.top_bar.get_combined_minimum_size().x <= vp.size.x - 20.0 + 1.0, "with 🔍 Huge buttons too (%.0f of %.0f)" % [ui.top_bar.get_combined_minimum_size().x, vp.size.x])
	Settings.set_ui_scale(1.0)
	root_win.size = keep_size
	root_win.content_scale_size = keep_css
	await frames(3)


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
	# stickers that count something show how far you've got
	Settings.counters["booms"] = 3
	Settings.counters["worlds"] = {"meadow": true, "candy": true}
	m = load("res://ui/menu.gd").new()
	add_child(m)
	await frames()
	m._stickers()
	await frames(2)
	var boom: Node = m.modal.find_child("Sticker_boom", true, false)
	var exp: Node = m.modal.find_child("Sticker_explorer", true, false)
	var ace: Node = m.modal.find_child("Sticker_ace", true, false)
	var hello: Node = m.modal.find_child("Sticker_hello", true, false)
	check(boom and texts(boom).contains("3 / 10") and exp and texts(exp).contains("2 / %d" % Catalog.WORLDS.size()),
		"locked stickers that count show how far you've got (3 / 10, 2 / %d)" % Catalog.WORLDS.size())
	check(ace and not texts(ace).contains("/") and hello and hello.find_child("Progress", true, false) == null,
		"(not on ones you have, or ones that don't count)")
	m.queue_free()
	await frames()

extends Node
## Headless checks for the 🏁 battle goals (⚙️ Battle Rules: ⚔️ Last team
## standing, 👑 Defend the King, 🚩 King of the Hill), 🌊 Wave Defense (the
## 🎯 Ready-made card) and their panel (B3ModeHud), with the 🏆 scoreboard
## and ⏮ Reset still working.
## godot --headless --path . -- --test=b3modes

const SPEED := 4.0
const TEST_BEST := "user://test_b3waves.cfg"

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


func ko(u: B3Unit, by: B3Unit = null) -> void:
	if is_instance_valid(u) and not u.dead:
		u.hurt(99999.0, Vector3.UP, 1.0, by, "blast")


func live(team := "") -> Array:
	return (b.units as Array).filter(func(u: B3Unit) -> bool:
		return is_instance_valid(u) and not u.dead and (team == "" or u.team == team))


func kings() -> Array:
	return live().filter(func(u: B3Unit) -> bool: return u.king)


func rule(id: String, v: String) -> void:
	B3Rules.set_value(id, v)
	b.apply_rules()


func headline() -> String:
	return String(b.ui.banner_lbl.text).split("\n")[0] if b.ui.banner_lbl.visible else ""


## Holds `u` still at `p` (so it stays in or out of the hill's circle).
func pin(u: B3Unit, p: Vector3) -> void:
	u.freeze = true
	u.set_physics_process(false)
	u.linear_velocity = Vector3.ZERO
	u.global_position = p


## True if `u`'s model has a crown on its head.
func crowned(u: B3Unit) -> bool:
	if u == null or not is_instance_valid(u) or u.rig == null:
		return false
	var head: Node3D = u.rig.pv.get("head")
	return head != null and head.get_node_or_null("Crown") != null


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	var keep_stickers: Dictionary = Settings.stickers.duplicate(true)
	var keep_counters: Dictionary = Settings.counters.duplicate(true)
	B3Modes.best_file = TEST_BEST
	B3Modes.best = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BEST))
	await _rules()
	await _last()
	await _king()
	await _king_draw()
	await _hill()
	await _hill_ai()
	await _waves_setup()
	await _waves_play()
	await _waves_first_person()
	await _waves_list()
	await _waves_start_later()
	await _hud_place()
	B3Player.stop()
	if b and is_instance_valid(b):
		b.queue_free()
		b = null
	Engine.time_scale = 1.0
	B3Rules.reset()
	B3Modes.best_file = B3Modes.BEST_PATH
	B3Modes.best = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BEST))
	Settings.stickers = keep_stickers
	Settings.counters = keep_counters
	for i in 3:
		await get_tree().process_frame
	print("test_b3modes: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ rules
func _rules() -> void:
	print("🏁 the battle goal in ⚙️ Battle Rules")
	var opt: Dictionary = {}
	for o: Dictionary in B3Rules.OPTIONS:
		if String(o.id) == "goal":
			opt = o
	var ids: Array = []
	for ch: Array in opt.get("choices", []):
		ids.append(String(ch[0]))
	check(ids == ["last", "king", "hill"], "the goals are ⚔️ Last team standing, 👑 Defend the King and 🚩 King of the Hill %s" % str(ids))
	check(B3Rules.goal() == "last" and B3Rules.is_default(), "⚔️ Last team standing is the usual one")
	B3Rules.set_value("goal", "king")
	check(not B3Rules.is_default(), "picking another lights up ⚙️")
	B3Rules.reset()
	check(B3Rules.goal() == "last", "↺ Back to normal puts it back")
	await fresh()
	b.ui._show_rules()
	await frames()
	var found := false
	for n in b.ui.popup.find_children("*", "Button", true, false):
		if (n as Button).text == "👑 Defend the King":
			found = true
	check(found, "the ⚙️ panel has a 👑 Defend the King button")
	b.ui.close_top()


func _last() -> void:
	print("⚔️ Last team standing")
	await fresh()
	var r: B3Unit = b.spawn_unit("knight", "red", at(-3, 0), "peaceful")
	var bl: B3Unit = b.spawn_unit("knight", "blue", at(3, 0), "peaceful")
	b.set_fighting(true)
	await sim(0.6)
	check(b.modes.kind == "" and not b.ui.mode_hud.visible and kings().is_empty(), "no Kings, no hill, no panel")
	ko(bl, r)
	await sim(1.0)
	check(b.winner == "red" and headline().begins_with("🔴"), "the last team standing wins, as always (%s)" % headline())


# ------------------------------------------------------------------- 👑
func _king() -> void:
	print("👑 Defend the King")
	await fresh()
	rule("goal", "king")
	for i in 5:
		b.spawn_unit("soldier", "red", at(-14, -6 + i * 3.0), "peaceful", PI * 0.5)
	b.spawn_unit("knight", "red", at(-12, 0), "peaceful", PI * 0.5)
	for i in 4:
		b.spawn_unit("viking", "blue", at(14, -5 + i * 3.0), "peaceful", -PI * 0.5)
	await sim(0.3)
	check(b.ui.mode_hud.visible and String(b.ui.mode_hud.info.text).contains("King"), "before Fight! the panel says each team will get a King")
	var n0: int = live().size()
	b.toggle_play()
	await sim(0.8)
	var ks := kings()
	check(ks.size() == 2 and b.modes.kings.has("red") and b.modes.kings.has("blue"), "Fight!: each team gets a King (%d)" % ks.size())
	var rk: B3Unit = b.modes.kings.get("red")
	var bk: B3Unit = b.modes.kings.get("blue")
	check(rk != null and rk.kind == "soldier" and bk.kind == "viking", "of its most common fighter (%s, %s)" % [rk.kind if rk else "?", bk.kind if bk else "?"])
	check(crowned(rk) and crowned(bk), "👑 both wear a gold crown")
	check(absf(rk.size_mult - B3Modes.KING_SIZE) < 0.01 and rk.max_hp > float(B3Defs.unit_def("soldier").hp) * 10.0,
		"a big King with lots of health (%d ❤️)" % int(rk.max_hp))
	var behind := rk.position.x < -14.0 + 0.5 and bk.position.x > 14.0 - 0.5
	check(behind, "each stands behind its army (%.1f, %.1f)" % [rk.position.x, bk.position.x])
	var guards := live("red").filter(func(u: B3Unit) -> bool: return not u.king and u.pers == "defend")
	check(guards.size() == B3Modes.GUARDS, "%d teammates guard the King" % guards.size())
	check(live().size() == n0 + 2, "nobody else is added (%d)" % live().size())
	# the panel shows both Kings' health
	await sim(0.5)
	var hud = b.ui.mode_hud
	check(hud.visible and hud._bars.has("red") and hud._bars.has("blue"), "the panel shows each King's health")
	bk.hp = bk.max_hp * 0.5
	bk.hurt_t = 0.0
	await sim(0.6)
	check(absf((hud._bars["blue"] as ProgressBar).value - 50.0) < 6.0, "...going down when the King is hurt (%.0f%%)" % (hud._bars["blue"] as ProgressBar).value)
	# knocked down (not out) and back up: the crown comes back
	bk.knock_down(Vector3(0, 8, 0))
	await sim(0.5)
	check(bk.down and bk.rig == null, "(the King gets knocked over)")
	for i in 20:
		if not bk.down:
			break
		await sim(0.5)
	check(not bk.dead and not bk.down and crowned(bk), "and gets back up still wearing the crown")
	# Blue's King falls: Blue loses, with its vikings still standing
	var blue_left: int = live("blue").size()
	var killer: B3Unit = live("red")[0]
	ko(bk, killer)
	await sim(1.0)
	check(blue_left >= 4 and live("blue").size() >= 3, "(Blue still has %d fighters)" % live("blue").size())
	check(b.winner == "red" and headline().begins_with("👑"), "Blue's King falls: Red wins! (%s)" % headline())
	await sim(1.5)
	check(b.winner == "red" and b.ui.banner_lbl.visible, "and stays the winner while Blue's others are still standing")
	check(b.ui.score_card.visible and B3Battle.read_score(b.scoreboard()).get("win", "") == "red", "🏆 the scoreboard shows")
	check(not hud.visible, "the panel steps aside for the winner banner")
	# ⏮ Play it again
	check(b.ui.again_btn.visible, "⏮ Play it again is there")
	b.ui.again_btn.pressed.emit()
	await sim(0.6)
	check(not b.fighting and b.winner == "" and live().size() == n0 and kings().is_empty(), "⏮ everyone back, without Kings (%d)" % live().size())
	b.toggle_play()
	await sim(0.8)
	check(kings().size() == 2 and crowned(b.modes.kings.get("red")), "and Fight! crowns new Kings")
	# a King played by you (Tab and first person work as usual)
	B3Player.stop()
	rule("goal", "last")


func _king_draw() -> void:
	print("👑 both Kings at once")
	await fresh()
	rule("goal", "king")
	b.spawn_unit("knight", "red", at(-6, 0), "peaceful")
	b.spawn_unit("knight", "blue", at(6, 0), "peaceful")
	b.spawn_unit("wolf", "wild", at(0, 30), "peaceful")
	b.toggle_play()
	await sim(0.6)
	check(kings().size() == 2 and not (live().filter(func(u: B3Unit) -> bool: return u.team == "wild" and u.king)).size() > 0,
		"wild animals don't get a King")
	ko(b.modes.kings.red)
	ko(b.modes.kings.blue)
	await sim(1.0)
	check(b.winner.begins_with("wild:"), "both Kings fall at once: the wild wolf is left (%s)" % b.winner)
	rule("goal", "last")


# ------------------------------------------------------------------- 🚩
func _hill() -> void:
	print("🚩 King of the Hill")
	await fresh()
	rule("goal", "hill")
	var r: B3Unit = b.spawn_unit("soldier", "red", at(-12, 0), "peaceful")
	var bl: B3Unit = b.spawn_unit("soldier", "blue", at(12, 0), "peaceful")
	await sim(1.5)
	check(b.modes.hill_node != null and not b.modes.hill_on, "before Fight! the circle shows where it'll be")
	b.toggle_play()
	await sim(0.5)
	var hp: Vector3 = b.modes.hill_pos
	check(b.modes.hill_on and is_instance_valid(b.modes.hill_node) and Vector2(hp.x, hp.z).length() < B3Modes.HILL_LOOK + 0.5,
		"Fight!: a glowing circle in the middle of the fighting (%.1f, %.1f)" % [hp.x, hp.z])
	await sim(1.0)
	check(b.modes.scores.is_empty() or float(b.modes.scores.get("red", 0.0)) == 0.0, "nobody scores while it's empty")
	pin(r, hp + Vector3(1, 0.3, 0))
	await sim(2.0)
	var s1 := float(b.modes.scores.get("red", 0.0))
	check(s1 > 3.0 and b.modes.holder == "red" and float(b.modes.scores.get("blue", 0.0)) == 0.0, "Red alone in it scores (%.1f)" % s1)
	pin(bl, hp + Vector3(-1, 0.3, 0))
	await sim(0.4)
	var s2 := float(b.modes.scores.get("red", 0.0))
	await sim(2.0)
	check(b.modes.holder == "+" and absf(float(b.modes.scores.get("red", 0.0)) - s2) < 0.01 and float(b.modes.scores.get("blue", 0.0)) < 0.7,
		"two teams in it: nobody scores")
	pin(bl, at(12, 0))
	await sim(1.0)
	check(float(b.modes.scores.get("red", 0.0)) > s2 + 1.0, "Red alone again: scoring again")
	var hud = b.ui.mode_hud
	check(hud.visible and hud._bars.has("red") and hud._bars.has("blue") and (hud._bars["red"] as ProgressBar).value > 1.0, "the panel shows each team's score bar")
	b.modes.scores["red"] = 98.0
	await sim(1.5)
	check(b.winner == "red" and headline().begins_with("🚩"), "the first to 100 wins (%s)" % headline())
	check(b.ui.score_card.visible, "🏆 with the scoreboard")
	b.reset_battle()
	await sim(0.5)
	check(b.modes.scores.is_empty() and b.winner == "" and not b.fighting, "⏮ Reset starts the scores again")
	# the circle goes on a hill, if there's one close by
	var c := at(-6, -32)
	var spot: Vector3 = b.modes._hill_spot(c)
	check(spot.y > c.y + 1.0 and Vector2(spot.x - c.x, spot.z - c.z).length() <= B3Modes.HILL_LOOK + 0.1,
		"⛰️ the circle goes on top of a hill near the middle (%.1f m up)" % (spot.y - c.y))
	var flat := at(0, 4)
	var spot2: Vector3 = b.modes._hill_spot(flat)
	check(Vector2(spot2.x - flat.x, spot2.z - flat.z).length() < 0.1, "and stays in the middle on flat ground")
	rule("goal", "last")
	await sim(0.3)
	check(b.modes.hill_node == null and b.modes.kind == "", "back to ⚔️ Last team standing: the circle goes away")


func _hill_ai() -> void:
	print("🚩 fighters go for the hill")
	await fresh()
	rule("goal", "hill")
	var a: B3Unit = b.spawn_unit("knight", "red", at(-16, 0), "attack")
	var d: B3Unit = b.spawn_unit("knight", "red", at(-16, 6), "defend")
	b.spawn_unit("soldier", "blue", at(16, 22), "peaceful")
	b.toggle_play()
	await sim(0.3)
	var hp: Vector3 = b.modes.hill_pos
	var d0 := Vector2(a.position.x - hp.x, a.position.z - hp.z).length()
	var g0 := d.position
	await sim(6.0)
	var d1 := Vector2(a.position.x - hp.x, a.position.z - hp.z).length()
	check(d1 < d0 - 5.0, "with no enemy close by, a fighter heads for the circle (%.1f → %.1f m)" % [d0, d1])
	check(d.position.distance_to(g0) < 3.0, "a 🛡️ Defend fighter stays at its post")
	await sim(6.0)
	check(float(b.modes.scores.get("red", 0.0)) > 0.0, "and scores once it's there")
	rule("goal", "last")


# ------------------------------------------------------------------- 🌊
func _waves_setup() -> void:
	print("🌊 Wave Defense: setting up")
	await fresh()
	var ids: Array = []
	for e in B3Scenarios.MENU:
		ids.append(String((e as Dictionary).id))
	check("waves" in ids, "🌊 Wave Defense is a 🎯 Ready-made card")
	b.ui._show_history("ready")
	await frames()
	var cards: Node = b.ui.popup.find_child("Cards", true, false)
	var go: Button = cards.get_child(ids.find("waves")).find_child("Go", true, false)
	go.pressed.emit()
	await sim(1.0)
	check(b.ready_id == "waves" and b.modes.kind == "waves" and b.modes.phase == "build" and not b.fighting, "▶ Set it up: the fort waits for Fight!")
	check(b.budget == B3Modes.START_POINTS and b.build_zone == B3Modes.FORT and b.build_team == "red", "with 🪙 %d points to spend in the fort" % b.budget)
	check(b.ui.coin_lbl.visible and b.zone_vis != null, "the coins and the glowing fort show")
	var kinds := {}
	for s: B3Struct in b.structs:
		kinds[s.kind] = int(kinds.get(s.kind, 0)) + 1
	check(int(kinds.get("sandbags", 0)) >= 6 and kinds.has("tower") and kinds.has("bunker"), "a starting fort: sandbags round a tower and a bunker %s" % str(kinds))
	var reds := live("red")
	var in_fort := reds.filter(func(u: B3Unit) -> bool: return B3Modes.FORT.has_point(Vector2(u.position.x, u.position.z)))
	check(reds.size() >= 8 and in_fort.size() == reds.size() and live("blue").is_empty(), "and %d defenders in it, no attackers yet" % reds.size())
	var archers_up := reds.filter(func(u: B3Unit) -> bool: return u.kind == "archer" and u.position.y > 3.5)
	check(archers_up.size() == 2, "two archers up the tower")
	var hud = b.ui.mode_hud
	check(hud.visible and hud.next_btn.visible and String(hud.next_btn.text).contains("Start wave 1"), "the panel says ▶ Start wave 1")
	check(absf(b.cam.yaw_target) < 0.01, "the camera looks out over the fort")


func _waves_play() -> void:
	print("🌊 Wave Defense: the waves")
	await fresh()
	b.run_ready("waves")
	await sim(0.5)
	var pts0: int = b.points_left()
	# buying
	b.tools.place_id = "soldier"
	b.tools.team = "blue"
	b.tools._place(at(0, 10), at(0, 10), false, false)
	var bought: Array = live("red").filter(func(u: B3Unit) -> bool: return u.has_meta("cost"))
	check(bought.size() == 1 and b.points_left() == pts0 - 2 and (bought[0] as B3Unit).pers == "defend", "a 🪖 soldier costs 2, joins Red and guards its spot")
	b.tools._place(at(0, -20), at(0, -20), false, false)
	check(live("red").filter(func(u: B3Unit) -> bool: return u.has_meta("cost")).size() == 1, "nothing outside the fort")
	var p0: int = b.props.size()
	b.drop("mine", at(5, 4))
	check(b.props.size() == p0 + 1 and b.points_left() == pts0 - 4, "a 💣 mine costs 2 in the fort")
	b.drop("mine", at(5, -10))
	check(b.props.size() == p0 + 1 and b.points_left() == pts0 - 4, "but can't go outside it")
	b.tools.place_id = "mgnest"
	b.tools._place(at(-3, 4), at(-3, 4), false, false)
	check(live("red").filter(func(u: B3Unit) -> bool: return u.kind == "mgnest").size() == 1, "an 🔫 MG turret for the front")
	var spent0: int = b.spent
	var budget0: int = b.budget
	var n_red: int = live("red").size()
	# wave 1
	b.ui.mode_hud.press_next()
	await sim(0.5)
	check(b.fighting and b.modes.phase == "wave" and b.modes.wave == 1, "▶ Start wave 1 starts the fight")
	var blue := live("blue")
	check(blue.size() == 6 and blue.all(func(u: B3Unit) -> bool: return u.kind == "stick" and u.position.z < -40.0),
		"6 stick figures come from the far side (%d)" % blue.size())
	check(String(b.ui.mode_hud.title.text).contains("Wave 1"), "the panel says 🌊 Wave 1")
	await sim(3.0)
	var closer := live("blue").filter(func(u: B3Unit) -> bool: return u.position.z > -44.0)
	check(closer.size() >= 4, "they march on the fort")
	# knock them all out: points for each, and for holding the fort
	var victims := live("blue")
	victims[0].hurt(5.0, Vector3.UP, 0.0, null, "hit")
	b.remove_unit(victims[0])          # (erased, not knocked out: no points)
	await sim(0.3)
	check(b.budget == budget0, "erasing an attacker gives no points")
	for u: B3Unit in live("blue"):
		ko(u, live("red")[0])
	await sim(1.0)
	var want := budget0 + 5 + B3Modes.wave_bonus(1)
	check(b.budget == want, "+1 🪙 per knock-out and +%d for holding the fort (%d, want %d)" % [B3Modes.wave_bonus(1), b.budget, want])
	check(b.modes.phase == "break" and b.modes.break_t > 5.0 and b.winner == "", "a short break, nobody has won")
	check(String(b.ui.mode_hud.title.text).contains("Wave 2 is coming"), "🌊 Wave 2 is coming! (%s)" % b.ui.mode_hud.title.text)
	check(b.ui.mode_hud.next_btn.visible and b.ui.mode_hud.next_btn.text == "▶ Next wave", "with ▶ Next wave")
	check(B3Modes.best == 1, "⭐ best wave: 1")
	var cf := ConfigFile.new()
	check(cf.load(TEST_BEST) == OK and int(cf.get_value("waves", "best", 0)) == 1, "...and it's saved")
	# buying during the break
	b.tools.place_id = "archer"
	b.tools._place(at(4, 12), at(4, 12), false, false)
	check(b.spent == spent0 + 2, "more can be bought in the break")
	# ▶ Next wave
	await sim(2.0)
	b.ui.mode_hud.press_next()
	await sim(0.5)
	check(b.modes.wave == 2 and b.modes.phase == "wave" and live("blue").size() == 9, "▶ Next wave brings wave 2 straight away (%d attackers)" % live("blue").size())
	check(b.modes.left == 9, "the panel counts them (%d left)" % b.modes.left)
	# ♾️ Reinforcements bring back your side, not the attackers
	rule("respawn", "on")
	ko(live("blue")[0])
	await sim(0.5)
	check(b._respawns.filter(func(r: Dictionary) -> bool: return r.team == "blue").is_empty(), "knocked-out attackers don't come back")
	rule("respawn", "off")
	# losing: nothing of yours left in the fort
	for u: B3Unit in live("red"):
		u.global_position = at(40, 60)     # (everyone runs off)
	await sim(1.0)
	check(b.modes.phase == "lost" and b.winner == "blue", "nothing left in the fort: it falls")
	check(headline().contains("The fort fell on wave 2"), "🌊 The fort fell on wave 2! (%s)" % headline())
	check(b.ui.score_card.visible, "🏆 with the scoreboard")
	# ⏮ Play it again: the fort as it was at Fight!
	b.ui.again_btn.pressed.emit()
	await sim(0.6)
	check(not b.fighting and b.modes.phase == "build" and b.modes.wave == 0 and live("blue").is_empty(), "⏮ back to before wave 1")
	check(b.budget == budget0 and b.spent == spent0 and live("red").size() == n_red, "with the points and the fort you had (%d/%d, %d fighters)" % [b.points_left(), b.budget, live("red").size()])
	check(b.ready_id == "waves" and b.build_zone == B3Modes.FORT, "still Wave Defense")
	b.toggle_play()
	await sim(0.5)
	check(b.modes.wave == 1 and live("blue").size() == 6, "and Fight! starts wave 1 again")
	# another battle: the points and the fort go away
	b.run_ready("skirmish")
	await sim(0.5)
	check(b.budget < 0 and b.modes.kind == "" and not b.ui.coin_lbl.visible and b.zone_vis == null, "picking another battle: everything's free again")


func _waves_first_person() -> void:
	print("🌊 defending in first person")
	await fresh("grassland", {"scenario": "waves"})
	await sim(1.5)
	check(b.fighting and b.modes.wave == 1, "--scenario=waves starts wave 1")
	var me: B3Unit = live("red").filter(func(u: B3Unit) -> bool: return u.kind == "soldier")[0]
	b.tools.play_as(me, true)
	await sim(0.5)
	check(B3Player.active() and B3Player.me.fp and b.cam.first_person(), "👀 playing a soldier in first person during the wave")
	var foe: B3Unit = live("blue")[0]
	foe.global_position = me.position + Vector3(0, 0.2, -6)
	B3Player.me.look_yaw = PI
	B3Player.me.look_pitch = -0.05
	B3Player.me.fire = true
	await sim(3.0)
	B3Player.me.fire = false
	check(not is_instance_valid(foe) or foe.dead or foe.hp < foe.max_hp, "your shots hit the attackers")
	ko(me)
	await sim(0.6)
	check(B3Player.active() and B3Player.unit != me and B3Player.unit.team == "red" and B3Player.me.fp, "knocked out: you jump into another defender")
	check(b.modes.phase == "wave" or b.modes.phase == "break", "and the fort fights on")
	b.tools.stop_playing()


func _waves_list() -> void:
	print("🌊 the waves get stronger")
	var power := func(n: int) -> float:
		var d := B3Modes.wave_def(n)
		var p := 0.0
		for e: Array in d.units:
			p += float(B3Defs.unit_def(String(e[0])).hp) * int(e[1])
		if String(d.boss) != "":
			p += float(B3Defs.unit_def(String(d.boss)).hp) * B3Modes.BOSS_HP
		return p * B3Modes.wave_hp(n)
	var up := true
	var prev := 0.0
	for n in range(1, 31):
		var pw: float = power.call(n)
		if n % 5 != 1 and pw < prev * 0.95:     # (the wave after a boss can be a little smaller)
			up = false
			print("    wave %d: %.0f after %.0f" % [n, pw, prev])
		prev = pw
	check(up, "each wave is tougher than the one before (bosses aside)")
	check(float(power.call(15)) > float(power.call(1)) * 20.0 and float(power.call(25)) > float(power.call(15)), "much tougher later on (%.0f → %.0f → %.0f)" % [power.call(1), power.call(15), power.call(25)])
	var bosses := []
	for n in [5, 10, 15, 20, 25]:
		bosses.append(String(B3Modes.wave_def(n).boss))
	check(not bosses.has(""), "a boss every 5th wave %s" % str(bosses))
	var order := ["stick", "viking", "cavalry", "trex", "tank", "plane"]
	var first := {}
	for n in range(1, 16):
		var d := B3Modes.wave_def(n)
		for e: Array in d.units:
			if not first.has(e[0]):
				first[String(e[0])] = n
		if String(d.boss) != "" and not first.has(d.boss):
			first[String(d.boss)] = n
	var in_order := true
	for i in order.size() - 1:
		in_order = in_order and int(first.get(order[i], 99)) < int(first.get(order[i + 1], 99))
	check(in_order, "stick figures → vikings → cavalry → dinos → tanks → air raids")
	for n in range(1, 31):
		for e: Array in B3Modes.wave_def(n).units:
			if not B3Defs.UNITS.has(e[0]):
				check(false, "wave %d has a real fighter (%s)" % [n, e[0]])


func _waves_start_later() -> void:
	print("🌊 a boss wave (--scenario=waves:5)")
	await fresh("grassland", {"scenario": "waves:5"})
	await sim(1.5)
	var boss := live("blue").filter(func(u: B3Unit) -> bool: return u.has_meta("boss"))
	check(b.modes.wave == 5 and boss.size() == 1 and (boss[0] as B3Unit).kind == "giant" and (boss[0] as B3Unit).size_mult > 2.0,
		"wave 5 brings a HUGE giant")
	check(b.budget > B3Modes.START_POINTS, "starting later gives more points (%d)" % b.budget)
	var budget0: int = b.budget
	ko(boss[0], live("red")[0])
	await sim(0.5)
	check(b.budget == budget0 + 10, "a boss is worth 10 🪙")


## The panel sits clear of the top bar, the messages, the "You're the..."
## lines, the tool dock and the winner banner.
func _hud_place() -> void:
	print("the panel's place on the screen")
	await fresh("grassland", {"scenario": "waves"})
	await sim(1.0)
	var hud: Control = b.ui.mode_hud
	b.ui.toast("A long message to see where the messages go on the screen, nice and wide")
	var me: B3Unit = live("red")[0]
	b.tools.play_as(me)
	await frames(4)
	var r := hud.get_global_rect()
	var vp: Rect2 = get_viewport().get_visible_rect()
	check(hud.visible and vp.encloses(r), "it's on the screen (%s in %s)" % [r, vp.size])
	var others := {"the top bar": b.ui.top_bar, "the messages": b.ui.toasts, "the play lines": b.ui.play_lbl, "the tool dock": b.ui.dock_holder}
	for nm in others:
		var c: Control = others[nm]
		check(not c.visible or not r.intersects(c.get_global_rect()), "clear of %s" % nm)
	b.ui.sticker_pop("b3win")
	await frames(4)
	var st: Control = b.ui.sticker_box
	check(st.get_global_rect().position.y >= r.end.y, "📒 sticker messages go under it")
	b.tools.stop_playing()

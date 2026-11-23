extends TestBase
## Headless checks for the 🏁 battle goals (⚙️ Battle Rules: ⚔️ Last team
## standing, 👑 Defend the King, 🚩 King of the Hill), 🌊 Wave Defense (the
## 🎯 Ready-made card) and their panel (B3ModeHud), with the 🏆 scoreboard
## and ⏮ Reset still working.
## godot --headless --path . -- --test=b3modes

const SPEED := 4.0
const TEST_SETTINGS := "user://test_b3waves.cfg"   # (🌊 the best wave is saved with the other progress)


func fresh(map := "grassland", more := {}) -> void:
	if b and is_instance_valid(b):
		B3Player.stop()
	await drop_battle()
	var opts := {"seed": 777, "map": map}
	opts.merge(more, true)
	start_battle(99, opts)


func live(team := "") -> Array:
	return (b.units as Array).filter(func(u: B3Unit) -> bool:
		return is_instance_valid(u) and not u.dead and (team == "" or u.team == team))


func kings() -> Array:
	return live().filter(func(u: B3Unit) -> bool: return u.king)


func headline() -> String:
	return String(b.ui.banner_lbl.text).split("\n")[0] if b.ui.banner_lbl.visible else ""


## ▶ Fight! (which sets the clock back to normal speed: the tests run faster)
func go() -> void:
	b.toggle_play()
	Engine.time_scale = SPEED


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
	var keep_testing := Settings.testing
	var keep_best := Settings.b3_wave_best
	Settings.file = TEST_SETTINGS
	Settings.testing = false
	Settings.b3_wave_best = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	await _rules()
	await _last()
	await _king()
	await _king_draw()
	await _king_hp()
	await _king_small()
	await _king_rout()
	await _king_town()
	await _hill()
	await _hill_ai()
	await _hill_more()
	await _hill_everyone()
	await _waves_setup()
	await _waves_play()
	await _waves_keep()
	await _waves_more()
	await _waves_net()
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
	Settings.testing = keep_testing
	Settings.file = Settings.PATH
	Settings.b3_wave_best = keep_best
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	Settings.stickers = keep_stickers
	Settings.counters = keep_counters
	for i in 3:
		await get_tree().process_frame
	finish()


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
	check(absf(rk.size_mult - B3Modes.KING_SIZE) < 0.01 and absf(rk.max_hp - B3Modes.king_hp("soldier")) < 1.0
		and rk.max_hp >= float(B3Defs.unit_def("soldier").hp) * 3.0,
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


func _king_hp() -> void:
	print("👑 a King's health: tough, not a wall")
	var worst := 0.0
	var who := ""
	for k: String in B3Defs.UNITS:
		if B3Defs.is_vehicle(k):
			continue
		var r := B3Modes.king_hp(k) / float(B3Defs.unit_def(k).hp)
		if r > worst:
			worst = r
			who = k
	check(worst <= B3Modes.KING_HP + 0.01, "no King has more than %.0f× its kind's usual health (was 12.8×; most: %s %.1f×)" % [B3Modes.KING_HP, who, worst])
	check(B3Modes.king_hp("brachio") <= 3000.0 and B3Modes.king_hp("soldier") >= 300.0,
		"a King Brachiosaurus has %d ❤️ (was 23,040), a King soldier %d" % [int(B3Modes.king_hp("brachio")), int(B3Modes.king_hp("soldier"))])
	await fresh()
	rule("goal", "king")
	for i in 3:
		b.spawn_unit("brachio", "red", at(-20, -8 + i * 8.0), "peaceful")
		b.spawn_unit("brachio", "blue", at(20, -8 + i * 8.0), "peaceful")
	go()
	await sim(0.6)
	var rk: B3Unit = b.modes.kings.get("red")
	check(rk != null and rk.kind == "brachio" and absf(rk.max_hp - B3Modes.king_hp("brachio")) < 1.0,
		"...and that's what a crowned one gets (%d)" % int(rk.max_hp if rk else 0.0))
	rule("goal", "last")


func _king_small() -> void:
	print("👑 small armies and stand-offs")
	await fresh()
	rule("goal", "king")
	for i in 2:
		b.spawn_unit("knight", "red", at(-12, -2 + i * 4.0), "auto", PI * 0.5)
		b.spawn_unit("viking", "blue", at(12, -2 + i * 4.0), "auto", -PI * 0.5)
	go()
	await sim(0.8)
	var guards := live("red").filter(func(u: B3Unit) -> bool: return not u.king and u.pers == "defend")
	var free := live("red").filter(func(u: B3Unit) -> bool: return not u.king and u.pers != "defend")
	check(b.modes.kings.size() == 2 and guards.size() <= 1 and free.size() >= 1,
		"with 2 fighters a team keeps one on the attack (%d guarding, %d attacking)" % [guards.size(), free.size()])
	# a stand-off: everyone guarding, far apart
	for u: B3Unit in live():
		if not u.king:
			u.set_personality("defend")
			u.home = u.position
	b.modes._hp_sum = -1.0
	b.modes._calm_t = 0.0
	await sim(B3Modes.STALL_T + 1.5)
	var still := live().filter(func(u: B3Unit) -> bool: return u.pers == "defend")
	check(still.is_empty() and b.modes._charged, "nobody hurt for %.0f s: the guards and Kings charge (%d still waiting)" % [B3Modes.STALL_T, still.size()])
	var t := 0.0
	while b.winner == "" and t < 60.0:
		await sim(2.0)
		t += 2.0
	check(b.winner == "red" or b.winner == "blue", "...and someone wins (%s, %.0f s later)" % [b.winner, t])
	rule("goal", "last")


func _king_rout() -> void:
	print("👑 a team whose King falls runs away")
	await fresh()
	rule("goal", "king")
	var spots := {"red": Vector2(-22, 0), "blue": Vector2(22, 0), "green": Vector2(0, 26)}
	for t: String in spots:
		var p: Vector2 = spots[t]
		for i in 4:
			b.spawn_unit("soldier", t, at(p.x + (i - 1.5) * 2.0, p.y), "peaceful")
	go()
	await sim(0.8)
	check(b.modes.kings.size() == 3, "three Kings")
	var reds := live("red").filter(func(u: B3Unit) -> bool: return not u.king)
	ko(b.modes.kings.red, live("blue")[0])
	await sim(0.8)
	var ran := reds.filter(func(u: B3Unit) -> bool:
		return is_instance_valid(u) and (u.dead or (u.routed and u.fleeing and u.pers == "coward")))
	check(ran.size() == reds.size() and b.winner == "", "Red's King falls: Red's army runs away (%d of %d), the others fight on" % [ran.size(), reds.size()])
	await sim(B3Modes.ROUT_T + 2.5)
	check(live("red").is_empty(), "...and soon it's gone (poof!), so nobody's left fighting for a team that's out (%d)" % live("red").size())
	ko(b.modes.kings.green, live("blue")[0])
	await sim(0.8)
	check(b.winner == "blue" and headline().begins_with("👑"), "Green's King falls too: Blue wins (%s)" % b.winner)
	var losers_cheer := live().filter(func(u: B3Unit) -> bool: return u.team != "blue" and u.cheer)
	var cheer_n := live("blue").filter(func(u: B3Unit) -> bool: return u.cheer).size()
	check(losers_cheer.is_empty() and cheer_n > 0, "only the winners cheer (%d green cheering, %d blue)" % [losers_cheer.size(), cheer_n])
	await sim(B3Modes.ROUT_T + 2.5)
	check(b.winner == "blue" and live("green").is_empty(), "and Blue stays the winner")
	rule("goal", "last")


func _king_town() -> void:
	print("👑 Kings don't stand inside houses")
	await fresh("town")
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	q.shape = sph
	q.collision_mask = B3Defs.L_SCENERY
	var house := Vector3.INF
	for ix in range(-30, 31):
		for iz in range(-30, 31):
			var p := at(ix * 3.0, iz * 3.0)
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.4, 0))
			if not b.space().intersect_shape(q, 1).is_empty():
				house = p
				break
		if house != Vector3.INF:
			break
	check(house != Vector3.INF, "(found a house at %s)" % str(house))
	var spot: Vector3 = b.modes._free_spot(house)
	q.collision_mask = B3Defs.L_SCENERY | B3Defs.L_STRUCT
	q.transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 1.4, 0))
	check(b.space().intersect_shape(q, 1).is_empty() and spot.distance_to(house) > 0.5,
		"a King meant for a spot inside a house stands next to it instead (%.1f m over)" % spot.distance_to(house))


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


func _hill_more() -> void:
	print("🚩 no free points after a win, no lava or buildings in the circle")
	await fresh()
	rule("goal", "hill")
	var r: B3Unit = b.spawn_unit("soldier", "red", at(-12, 0), "peaceful")
	var bl: B3Unit = b.spawn_unit("soldier", "blue", at(12, 0), "peaceful")
	go()
	await sim(0.5)
	ko(bl, r)
	await sim(1.0)
	check(b.winner == "red", "(Red wins the usual way: Blue's all knocked out)")
	await sim(4.0)      # the winner banner stays up a while...
	pin(r, b.modes.hill_pos + Vector3(1, 0.3, 0))
	b.spawn_unit("soldier", "blue", at(30, 30), "peaceful")      # ...then someone new turns up
	await sim(0.6)
	var s := float(b.modes.scores.get("red", 0.0))
	check(b.winner == "" and b.modes.hill_won == "" and s < 5.0, "the time under the banner doesn't count: no 100 points at once (%.1f)" % s)
	# lava up on a hill, and a bunker on top of it
	var c := at(-6, -32)
	var top: Vector3 = b.modes._hill_spot(c)
	check(top.y > c.y + 1.0, "(a hill at %s, %.1f m up)" % [str(top), top.y])
	var lava: B3Hazard = b.spawn_hazard("lava", top, 3.0)
	var top2: Vector3 = b.modes._hill_spot(c)
	var gap := Vector2(top2.x - top.x, top2.z - top.z).length()
	check(gap > 3.0 + B3Modes.HILL_R, "🌋 lava up on the hill: the circle goes somewhere else (%.1f m away)" % gap)
	b.remove_hazard(lava)
	await sim(0.1)
	b.spawn_struct("bunker", top, 0.0)
	await sim(0.5)
	var top3: Vector3 = b.modes._hill_spot(c)
	check(b.modes._hill_clear(top3) and Vector2(top3.x - top.x, top3.z - top.z).length() > 1.0,
		"🧱 a bunker on top: the circle goes next to it, not round it (%.1f m away)" % Vector2(top3.x - top.x, top3.z - top.z).length())
	# 🌋 the Volcano's pools sit high and low: every one of them counts
	await fresh("volcano")
	var seen := 0
	for h: B3Hazard in b.hazards:
		if not b.modes._hill_ok(h.position.x, h.position.z):
			seen += 1
	check(b.hazards.size() >= 8 and seen == b.hazards.size(), "🌋 the circle keeps away from all %d Volcano pools, high or low (%d)" % [b.hazards.size(), seen])
	rule("goal", "last")


func _hill_everyone() -> void:
	print("🚩 vehicles and guards by nature go for the hill too")
	await fresh()
	rule("goal", "hill")
	var tank: B3Unit = b.spawn_unit("tank", "red", at(-26, -6), "auto", PI * 0.5)
	var jeep: B3Unit = b.spawn_unit("jeep", "red", at(-26, 8), "auto", PI * 0.5)
	var hop: B3Unit = b.spawn_unit("hoplite", "red", at(-24, 2), "auto", PI * 0.5)
	var ele: B3Unit = b.spawn_unit("elephant", "red", at(-26, 16), "auto", PI * 0.5)
	var post: B3Unit = b.spawn_unit("knight", "red", at(-24, -14), "defend", PI * 0.5)
	b.spawn_unit("soldier", "blue", at(26, 44), "peaceful")
	b.spawn_unit("soldier", "blue", at(26, -44), "peaceful")
	go()
	await sim(0.3)
	var hp: Vector3 = b.modes.hill_pos
	var dist := func(u: B3Unit) -> float: return Vector2(u.position.x - hp.x, u.position.z - hp.z).length()
	var d0 := {}
	for u: B3Unit in [tank, jeep, hop, ele]:
		d0[u] = float(dist.call(u))
	var p0 := post.position
	await sim(10.0)
	for u: B3Unit in [tank, jeep, hop, ele]:
		var d1: float = dist.call(u)
		check(d1 < float(d0[u]) - 6.0, "the %s heads for the hill (%.0f → %.0f m)" % [u.def.name, float(d0[u]), d1])
	check(post.position.distance_to(p0) < 3.0, "a knight you set to 🛡️ Defend still stays at its post")
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
	check(Settings.b3_wave_best == 1, "⭐ best wave: 1")
	var cf := ConfigFile.new()
	check(cf.load(TEST_SETTINGS) == OK and int(cf.get_value("battle3d", "wave_best", 0)) == 1, "...and it's saved")
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
	# losing: the 🚩 keep falls (not just everyone leaving the fort)
	for u: B3Unit in live("red"):
		u.global_position = at(40, 60)     # (everyone runs off)
	await sim(1.0)
	check(b.modes.phase == "wave" and b.winner == "", "everyone out of the fort: it hasn't fallen (the keep's what counts)")
	b.modes.keep_hp = 1.0
	b.modes.hurt_keep(5.0)
	await sim(0.5)
	check(b.modes.phase == "lost" and b.winner == "blue", "the keep falls: the fort's lost")
	check(headline().contains("The keep fell on wave 2"), "🚩 The keep fell on wave 2! (%s)" % headline())
	check(b.ui.score_card.visible, "🏆 with the scoreboard")
	# ⏮ Play it again: the fort as it was at Fight!
	b.ui.again_btn.pressed.emit()
	await sim(0.6)
	check(not b.fighting and b.modes.phase == "build" and b.modes.wave == 0 and live("blue").is_empty(), "⏮ back to before wave 1")
	check(b.budget == budget0 and b.spent == spent0 and live("red").size() == n_red, "with the points and the fort you had (%d/%d, %d fighters)" % [b.points_left(), b.budget, live("red").size()])
	check(b.ready_id == "waves" and b.build_zone == B3Modes.FORT, "still Wave Defense")
	var mg: Array = live("red").filter(func(u: B3Unit) -> bool: return u.kind == "mgnest")
	var left0: int = b.points_left()
	if not mg.is_empty():
		b.remove_unit(mg[0])
	check(mg.size() == 1 and b.points_left() == left0 + B3Defs.cost("mgnest"), "⏮ what you bought is yours to erase for its points back (%d → %d)" % [left0, b.points_left()])
	b.tools.place_id = "mgnest"
	b.tools._place(at(-3, 4), at(-3, 4), false, false)
	b.toggle_play()
	await sim(0.5)
	check(b.modes.wave == 1 and live("blue").size() == 6, "and Fight! starts wave 1 again")
	# another battle: the points and the fort go away
	b.run_ready("skirmish")
	await sim(0.5)
	check(b.budget < 0 and b.modes.kind == "" and not b.ui.coin_lbl.visible and b.zone_vis == null, "picking another battle: everything's free again")
	check(b.modes.keep_node == null, "and the keep goes away")


func _waves_keep() -> void:
	print("🚩 the Fort Keep")
	await fresh()
	b.run_ready("waves")
	await sim(0.6)
	var m = b.modes
	var kp: Vector3 = m.keep_pos
	check(is_instance_valid(m.keep_node) and m.keep_up and m.keep_hp == m.keep_max and B3Modes.FORT.has_point(Vector2(kp.x, kp.z)),
		"a 🚩 Fort Keep at the back of the fort, at full health (%d ❤️)" % int(m.keep_hp))
	check(m._keep_bar != null and m._keep_bar.visible, "with a health bar over it")
	var hud = b.ui.mode_hud
	check(hud.visible and hud._bars.has("red") and String((hud._names["red"] as Label).text).contains("Keep")
		and (hud._bars["red"] as ProgressBar).value > 99.0, "and in the panel")
	var hit: Dictionary = b.raycast(kp + Vector3(0, 12, 0), kp - Vector3(0, 1, 0), B3Defs.L_STRUCT)
	check(not hit.is_empty() and float((hit.position as Vector3).y) > kp.y + 4.0, "it's solid: things stand on top of it")
	var blocked := false
	for s: B3Struct in b.structs:
		if Vector2(s.position.x - kp.x, s.position.z - kp.z).length() < B3Modes.KEEP_R + 1.0:
			blocked = true
	check(not blocked, "(nothing of the starting fort is built on it)")
	var on_keep := Vector3(kp.x + 1.0, kp.y, kp.z)
	check(b.can_place("wall", on_keep) != "" and b.can_place("lava", on_keep) != "" and b.can_place("soldier", on_keep) == "",
		"walls and pools can't go on the keep (fighters can)")
	b.ui.mode_hud.press_next()
	Engine.time_scale = SPEED
	await sim(0.5)
	check(b.modes.phase == "wave", "(wave 1)")
	# your whole army out of the fort (flying, riding out to flank): it holds
	for u: B3Unit in live("red"):
		u.global_position = at(40.0 + randf() * 4.0, 60.0 + randf() * 4.0)
	await sim(1.5)
	check(m.phase == "wave" and b.winner == "", "everyone out of the fort (a plane, a ride round the side): no \"The fort fell!\"")
	# the attackers' booms hurt it; yours don't
	var h0: float = m.keep_hp
	b.explode(kp + Vector3(0, 1.0, -3.2), 3.5, 6.0, 80.0, {"team": "red"})
	check(m.keep_hp == h0, "your own booms don't hurt the keep")
	b.explode(kp + Vector3(0, 1.0, -3.2), 3.5, 6.0, 80.0, {"team": "blue"})
	check(m.keep_hp < h0, "the attackers' booms do (%d → %d)" % [int(h0), int(m.keep_hp)])
	# attackers with nobody to fight close by hit it
	var foes := live("blue")
	for i in 3:
		var u: B3Unit = foes[i]
		u.global_position = at(kp.x + (i - 1) * 1.6, kp.z - B3Modes.KEEP_R - 1.0)
	var h1: float = m.keep_hp
	await sim(3.0)
	check(m.keep_hp < h1 - 20.0, "attackers at the keep bash it (%d → %d)" % [int(h1), int(m.keep_hp)])
	await sim(0.3)
	check((hud._bars["red"] as ProgressBar).value < 99.0, "...and its bar goes down (%.0f%%)" % (hud._bars["red"] as ProgressBar).value)
	# far-off attackers walk to it
	var far: B3Unit = foes[4]
	var fd0 := Vector2(far.position.x - kp.x, far.position.z - kp.z).length()
	await sim(3.0)
	var fd1 := Vector2(far.position.x - kp.x, far.position.z - kp.z).length() if is_instance_valid(far) else 0.0
	check(fd1 < fd0 - 5.0, "the others march on the keep (%.0f → %.0f m)" % [fd0, fd1])
	# it falls: a defeat, not a victory
	var keep_st: Dictionary = Settings.stickers.duplicate()
	Settings.stickers.erase("b3win")
	Settings.stickers.erase("general")
	var ev0: int = b._events.size()
	m.keep_hp = 3.0
	m.hurt_keep(10.0)
	await sim(0.3)
	check(m.phase == "lost" and not m.keep_up and b.winner == "blue", "the keep falls: the fort's lost")
	check(headline().contains("The keep fell on wave 1"), "🚩 The keep fell on wave 1! (%s)" % headline())
	check(b._events.size() <= ev0 + 1, "no fireworks or confetti (%d → %d things waiting)" % [ev0, b._events.size()])
	check(not Settings.stickers.has("b3win") and not Settings.stickers.has("general"), "no 🏆 Victory or 🎖️ General sticker for losing")
	var red_cheer := live("red").filter(func(u: B3Unit) -> bool: return u.cheer).size()
	var blue_cheer := live("blue").filter(func(u: B3Unit) -> bool: return u.cheer).size()
	check(red_cheer == 0 and blue_cheer > 0, "the attackers cheer, your side doesn't (%d, %d)" % [blue_cheer, red_cheer])
	await sim(1.5)
	check(m._keep_fall >= 0.99 and m._keep_tower.scale.y < 0.5, "it crumbles into a heap, flag down")
	Settings.stickers = keep_st
	# ⏮ Play it again: a new keep
	b.ui.again_btn.pressed.emit()
	await sim(0.6)
	check(m.phase == "build" and m.keep_up and m.keep_hp == m.keep_max and is_instance_valid(m.keep_node) and m._keep_fall < 0.0,
		"⏮ Play it again: the keep's back up, good as new")


func _waves_more() -> void:
	print("🌊 points, the next wave, patching up, refunds")
	check(B3Modes.bounty("stick") == 1 and B3Modes.bounty("soldier") == 1 and B3Modes.bounty("tank") == 7 and B3Modes.bounty("plane") == 7,
		"🪙 knock-outs pay half the attacker's price: a stick figure 1, a tank or plane 7")
	check(B3Modes.bounty("giant", true) == 10 and B3Modes.bounty("dragon", true) == 15, "a boss at least 10 (a dragon 15)")
	await fresh()
	b.run_ready("waves")
	await sim(0.6)
	var hud = b.ui.mode_hud
	var first: Array = B3Modes.wave_preview(1)
	check(hud.preview.visible and String(hud.prev_title.text).contains(String(B3Modes.wave_def(1).name))
		and String(hud.prev_line.text).contains("%s×%d" % [first[0][0], first[0][1]]),
		"👀 before wave 1 the panel shows what's coming (%s)" % String(hud.prev_line.text))
	# buy one now (it'll fight in wave 1)
	b.tools.place_id = "soldier"
	b.tools._place(at(-2, 10), at(-2, 10), false, false)
	var old: B3Unit = live("red").filter(func(u: B3Unit) -> bool: return u.has_meta("cost"))[0]
	b.ui.mode_hud.press_next()
	Engine.time_scale = SPEED
	await sim(0.5)
	check(not hud.preview.visible, "(not during the wave)")
	# 🛡️ the attackers are hands-off
	var foe: B3Unit = live("blue")[0]
	check(b.modes.keeps(foe) and not b.modes.keeps(live("red")[0]), "🛡️ the attackers can't be erased, changed, grabbed or played (B3Modes.keeps)")
	if b.has_method("hands_off"):
		var ok := true
		for what in ["erase", "team", "launch", "play", "grab"]:
			ok = ok and String(b.hands_off(foe, what)) != ""
		check(ok, "...the Eraser, the Inspector, 🎮 Play as and ✋ Grab say no")
	# attackers turned red somehow don't count, and the wave still ends
	var foes := live("blue")
	for i in 3:
		(foes[i] as B3Unit).set_team("red")
	await sim(0.3)
	check(b.modes.left == foes.size() - 3 and not b.modes.keeps(foes[0]), "three attackers turned red: %d left, not %d" % [b.modes.left, foes.size()])
	# hurt: a defender and the keep (patched up after the wave)
	var hurt: B3Unit = live("red").filter(func(u: B3Unit) -> bool: return u.kind == "knight")[0]
	hurt.hp = hurt.max_hp * 0.3
	b.modes.keep_hp = 1000.0
	var budget0: int = b.budget
	for u: B3Unit in live("blue"):
		ko(u, live("red")[0])
	await sim(1.0)
	check(b.modes.phase == "break", "knocking out the real ones ends the wave (no getting stuck)")
	check(b.budget == budget0 + (foes.size() - 3) + B3Modes.wave_bonus(1), "🪙 only the real attackers pay (%d, want %d)" % [b.budget, budget0 + foes.size() - 3 + B3Modes.wave_bonus(1)])
	check(is_instance_valid(hurt) and hurt.hp >= hurt.max_hp * 0.59, "💚 your fighters still standing get 30%% of their health back (30%% → %.0f%%, with the medic's help)" % (hurt.hp / hurt.max_hp * 100.0))
	check(absf(b.modes.keep_hp - (1000.0 + B3Modes.KEEP_HP * B3Modes.KEEP_FIX)) < 1.0, "and the keep's mended a bit (%d)" % int(b.modes.keep_hp))
	await sim(0.3)
	var nxt: Array = B3Modes.wave_preview(2)
	check(hud.preview.visible and String(hud.prev_title.text).contains(String(B3Modes.wave_def(2).name))
		and String(hud.prev_line.text).contains("%s×%d" % [nxt[0][0], nxt[0][1]]), "👀 the break shows what wave 2 brings (%s)" % String(hud.prev_line.text))
	# 🪙 refunds in the break: for what you just bought, not what's fought
	var pts: int = b.points_left()
	b.tools._place(at(3, 10), at(3, 10), false, false)
	var fresh_buy: Array = live("red").filter(func(u: B3Unit) -> bool: return u.has_meta("cost") and not u.has_meta("fought"))
	check(fresh_buy.size() == 1 and b.points_left() == pts - 2, "(bought a soldier in the break)")
	b.remove_unit(fresh_buy[0])
	check(b.points_left() == pts, "erasing it in the break gives its points back")
	b.remove_unit(old)
	check(b.points_left() == pts, "...but not for one that's already fought a wave")
	# ▶ Next wave while paused
	b.set_paused(true)
	hud.press_next()
	check(b.modes.phase == "wave" and b.modes.wave == 2 and not b.paused, "▶ Next wave works while paused (and un-pauses)")
	Engine.time_scale = SPEED
	await sim(0.3)


func _waves_net() -> void:
	print("🌊 friends see the keep")
	await fresh()
	b.run_ready("waves")
	await sim(0.4)
	var st: Array = b.modes.net_state()
	check(st.size() == 9 and int(st[8]) == 1 and B3Modes._net_ok("waves", st), "the snapshot has the keep: where, its health, standing")
	# a friend's copy (on its own, in this battle)
	var f := B3Modes.new()
	f.battle = b
	f.apply_net(st)
	check(f.kind == "waves" and is_instance_valid(f.keep_node) and f.keep_up and f.keep_node.position.distance_to(b.modes.keep_pos) < 0.01,
		"a friend's screen builds the keep where the host's is")
	st[6] = 0.4
	f.apply_net(st)
	check(absf(f.keep_hp / f.keep_max - 0.4) < 0.01, "with its health")
	st[6] = 0.0
	st[8] = 2
	f.apply_net(st)
	check(not f.keep_up and f._keep_fall >= 0.0, "and it crumbles when the host's falls")
	var junk := st.duplicate()
	junk[7] = Vector3(NAN, 0, 0)
	check(not B3Modes._net_ok("waves", junk), "🛡️ a broken keep from a \"host\" is ignored")
	junk = st.duplicate()
	junk[6] = "lots"
	check(not B3Modes._net_ok("waves", junk), "(and broken health)")
	f.apply_net([""])
	check(f.keep_node == null, "leaving Wave Defense takes it away")
	f.free()


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

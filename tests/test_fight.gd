extends Node
## Headless checks for people, animals and dinosaurs: spawning, weapons and
## armor, battles, explosions and getting back up, lava, platforms,
## personalities and the nuke.
## godot --headless --path . -- --test=fight

var fails := 0
var w: World


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func fresh() -> void:
	w._clear_all()
	w.clear_placed()
	w.battle_on = true
	w.set_gravity("normal")
	await frames(2)


## Waits up to `sec` seconds for `cond` to come true.
func wait_for(cond: Callable, sec: float) -> bool:
	for i in int(sec * 120.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


var bumps := 0   # "thud" and "clink" puffs (see _count_bumps)


func _count_bumps(name: String, _a: Dictionary) -> void:
	if name == "thud" or name == "clink":
		bumps += 1


func _ready() -> void:
	seed(7)
	await get_tree().process_frame
	w = World.new()
	add_child(w)
	var fx := Effects.new()
	fx.world = w
	add_child(fx)
	w.fx.connect(fx.handle)
	w.fx.connect(_count_bumps)
	w.load_world("canvas", false)

	print("everyone")
	w.battle_on = false
	var x := -1500.0
	for k in Catalog.FIGHTERS:
		w.spawn_fighter(k, Vector2(x, 150), "red", "peaceful")
		x += float(Catalog.fighter(k).get("body", Vector2(40, 0)).x) + 70.0
	await frames(120)
	var standing := w.fighters().filter(func(f): return f.state == "stand").size()
	check(standing == Catalog.FIGHTERS.size(), "all %d people, animals and dinosaurs spawn and stand (%d standing)" % [Catalog.FIGHTERS.size(), standing])
	var armed := w.fighters().filter(func(f): return f.weapon_id != "").size()
	check(armed >= 10, "people come with their weapons (%d armed)" % armed)

	print("weapons and armor")
	await fresh()
	var stick := w.spawn_fighter("stick", Vector2(0, 150), "red", "peaceful")
	await frames(30)
	var sword := w.spawn_toy("sword", stick.center() + Vector2(40, -60))
	w.apply_command(0, {"cmd": "give", "uid": sword.uid})
	check(stick.weapon_id == "sword", "giving a sword to a person arms them")
	var helmet := w.spawn_toy("helmet", stick.center() + Vector2(30, -60))
	w.apply_command(0, {"cmd": "give", "uid": helmet.uid})
	check(stick.helmet != "" and stick.armor > 0.1, "and a helmet protects them (armor %.2f)" % stick.armor)

	print("battle")
	await fresh()
	for i in 4:
		w.spawn_fighter("soldier", Vector2(-450 + i * 40, 150), "red", "attack")
		w.spawn_fighter("knight", Vector2(450 - i * 40, 150), "blue", "attack")
	var t := 0
	while w.last_winner == "" and t < 120 * 60:
		await get_tree().physics_frame
		t += 1
	check(w.last_winner != "", "a red-vs-blue battle ends with a winner (%s after %.0f s)" % [w.last_winner, t / 120.0])
	await fresh()
	# two sharpshooters with a chest-high wall between them: they mustn't just
	# hop up and down behind it for ever (that stalled Battle Valley)
	w.apply_command(0, {"cmd": "platform", "x0": -13, "y0": 190, "x1": 13, "y1": 300})
	w.spawn_fighter("soldier", Vector2(-280, 150), "red", "ranged")
	w.spawn_fighter("rocketeer", Vector2(280, 150), "blue", "ranged")
	t = 0
	while w.last_winner == "" and t < 120 * 40:
		await get_tree().physics_frame
		t += 1
	check(w.last_winner != "", "two shooters behind a wall go round it and fight (%s won after %.0f s)" % [w.last_winner, t / 120.0])

	print("explosions")
	await fresh()
	var g := w.spawn_fighter("soldier", Vector2(0, 150), "red", "peaceful")
	g.max_hp = 2000.0
	g.hp = 2000.0
	await frames(30)
	var start := g.center()
	ToyLogic.boom(w, start + Vector2(-60, 40), 240.0, 1400.0, false, 30.0)
	await frames(20)
	check(g.state == "ragdoll", "a blast knocks a person over into a ragdoll")
	var far := 0.0
	for i in 60:
		await get_tree().physics_frame
		far = maxf(far, g.center().distance_to(start))
	check(far > 80.0, "and throws them (%.0f px)" % far)
	var up := false
	for i in 120 * 8:
		await get_tree().physics_frame
		if g.state == "stand":
			up = true
			break
	check(up, "and they get back up afterwards")
	g.hurt(99999.0)
	await frames(30)
	check(g.state == "dead", "a knocked-out fighter stays down")

	print("hazards and platforms")
	await fresh()
	w.apply_command(0, {"cmd": "spawn", "id": "lava_tub", "x": 0, "y": 300})
	check(w.in_liquid(Vector2(0, 250)) == "lava", "a lava pit has lava in it")
	var victim := w.spawn_fighter("stick", Vector2(0, -200), "red", "peaceful")
	victim.body.global_position = Vector2(0, 150)
	var died := false
	for i in 120 * 6:
		await get_tree().physics_frame
		if not victim.alive():
			died = true
			break
	check(died, "falling into lava knocks you out")
	var n0 := w.platforms.size()
	w.apply_command(0, {"cmd": "platform", "x0": -300, "y0": 0, "x1": -100, "y1": 20})
	check(w.platforms.size() == n0 + 1, "the Platform tool draws a platform")
	w.apply_command(0, {"cmd": "unplatform", "x": -200, "y": 10})
	await frames(2)
	check(w.platforms.size() == n0, "and the eraser removes it")

	print("personalities")
	await fresh()
	var guard := w.spawn_fighter("knight", Vector2(-500, 150), "red", "defend")
	var calm := w.spawn_fighter("stick", Vector2(400, 150), "blue", "peaceful")
	var foe := w.spawn_fighter("stick", Vector2(600, 150), "green", "peaceful")
	await frames(120 * 6)
	check(guard.center().distance_to(guard.home) < 320.0, "a defender stays near its spot when enemies are far away")
	check(foe.hp >= foe.max_hp - 1.0, "peaceful people never attack")
	var coward := w.spawn_fighter("soldier", Vector2(200, 150), "green", "coward")
	var bully := w.spawn_fighter("viking", Vector2(320, 150), "red", "attack")
	bully.max_hp = 5000.0
	bully.hp = 5000.0
	await frames(10)
	coward.hp = coward.max_hp * 0.3
	var cx := coward.center().x
	await frames(120 * 2)
	check(not coward.alive() or coward.center().x < cx - 40.0, "a hurt coward runs away")

	print("saving")
	await fresh()
	var keeper := w.spawn_fighter("knight", Vector2(-200, 150), "blue", "defend")
	w.spawn_fighter("trex", Vector2(200, 100), "wild", "attack")
	w.apply_command(0, {"cmd": "platform", "x0": -100, "y0": -40, "x1": 100, "y1": -20})
	w.apply_command(0, {"cmd": "spawn", "id": "acid_vat", "x": 600, "y": 300})
	await frames(30)
	var helm := w.spawn_toy("helmet", keeper.center() + Vector2(0, -60))
	w.apply_command(0, {"cmd": "give", "uid": helm.uid})
	var saved := w.serialize()
	var np := w.platforms.size()
	w._clear_all()
	w.clear_placed()
	await frames(2)
	w.restore(saved)
	await frames(10)
	check(w.fighters().size() == 2, "saving and loading brings the fighters back (%d)" % w.fighters().size())
	var back := w.fighters().filter(func(f): return f.type == "knight")
	check(back.size() == 1 and back[0].team == "blue" and back[0].pers == "defend" and back[0].helmet != "", "with their team, personality and armor")
	check(w.platforms.size() == np, "and the platforms (%d)" % w.platforms.size())
	check(w.in_liquid(Vector2(600, 250)) == "acid", "and the acid vat")

	print("fight button and effects")
	await fresh()
	var gm := Game.new()   # just its "the world changed" handler
	gm.effects = fx
	w.world_changed.connect(gm._on_world_changed)
	fx.pops.clear()
	w.apply_command(0, {"cmd": "fight", "on": true})
	var popped := fx.pops.any(func(q): return String(q.t).contains("FIGHT"))
	w.apply_command(0, {"cmd": "night", "on": true})
	w.apply_command(0, {"cmd": "night", "on": false})
	check(popped and fx.pops.any(func(q): return String(q.t).contains("FIGHT")), "⚔️ FIGHT! stays on screen (pressing ⚔️ or 🌙 doesn't wipe the effects)")
	w.world_changed.disconnect(gm._on_world_changed)
	gm.free()

	print("reviving and armor")
	await fresh()
	var ko1 := w.spawn_fighter("stick", Vector2(-200, 150), "red", "peaceful")
	var ko2 := w.spawn_fighter("stick", Vector2(200, 150), "red", "peaceful")
	await frames(20)
	ko1.hurt(9999.0)
	ko2.hurt(9999.0)
	await frames(10)
	w.apply_command(0, {"cmd": "revive", "uid": ko1.uid})
	await frames(10)
	check(ko1.alive() and not ko2.alive(), "💖 Revive gets just that one fighter back up")
	var vest1 := w.spawn_toy("body_armor", ko1.center() + Vector2(30, -60))
	w.apply_command(0, {"cmd": "give", "uid": vest1.uid})
	var armor1 := ko1.armor
	var vest2 := w.spawn_toy("body_armor", ko1.center() + Vector2(30, -60))
	w.apply_command(0, {"cmd": "give", "uid": vest2.uid})
	check(ko1.body_armor and is_equal_approx(ko1.armor, armor1) and w.things.has(vest2.uid), "a second vest doesn't pile on more armor (%.2f)" % ko1.armor)

	print("swings, reloads and bites")
	await fresh()
	var swinger := w.spawn_fighter("knight", Vector2(-40, 150), "red", "attack")
	var punchbag := w.spawn_fighter("stick", Vector2(40, 150), "blue", "peaceful")
	punchbag.max_hp = 10000.0
	punchbag.hp = 10000.0
	var swung := false
	for i in 120 * 4:
		await get_tree().physics_frame
		if swinger.hit_t > 0.0:
			swung = true
			break
	w.apply_command(0, {"cmd": "pause", "on": true})
	var hp_paused := punchbag.hp
	await frames(120)
	var waited := punchbag.hp == hp_paused
	w.apply_command(0, {"cmd": "pause", "on": false})
	await frames(60)
	check(swung and waited and punchbag.hp < hp_paused, "a sword swing waits while the game is paused, then lands")
	await fresh()
	w.battle_on = false
	var gunner := w.spawn_fighter("gunner", Vector2(0, 150), "red", "ranged")
	await frames(10)
	gunner.reload_t = 1.5   # just emptied its machine gun
	await frames(120 * 2)
	check(gunner.reload_t <= 0.0, "a gunner reloads while it isn't shooting (%.1f s left)" % gunner.reload_t)
	await fresh()
	w.spawn_fighter("trex", Vector2(-400, 150), "red", "attack", 2.0)
	var snack := w.spawn_fighter("stick", Vector2(300, 150), "blue", "peaceful")
	snack.max_hp = 100000.0
	snack.hp = 100000.0
	var bites := {"swing": 0, "hit": 0}
	var count_bites := func(n: String, _a: Dictionary) -> void:
		if bites.has(n):
			bites[n] += 1
	w.fx.connect(count_bites)
	var first := -1
	for i in 120 * 8:
		await get_tree().physics_frame
		if bites.swing > 0 and first < 0:
			first = i
		if first >= 0 and i - first > 70:
			break
	w.fx.disconnect(count_bites)
	check(bites.swing >= 1 and bites.hit >= 1, "a big T-Rex's first bite lands instead of snapping at thin air (%d bites, %d hits)" % [bites.swing, bites.hit])

	print("ragdolls, held weapons and arrows")
	await fresh()
	var aimer := w.spawn_fighter("soldier", Vector2(0, 150), "red", "peaceful")
	await frames(20)
	aimer.aim = -PI * 0.5   # rifle straight up: the arm starts half a turn from the body
	aimer.hurt(99999.0)
	# 2-3 s after the knock-out, once the body has landed and stopped rolling,
	# averaged over a second: a helicopter arm keeps whirling (50+ rad/s
	# before the fix), a normal ragdoll is lying still
	var spin_sum := {}
	for i in 360:
		await get_tree().physics_frame
		if i >= 240:
			for p in aimer.all_bodies():
				spin_sum[p] = float(spin_sum.get(p, 0.0)) + absf(p.angular_velocity) / 120.0
	var spin := 0.0
	for p in spin_sum:
		spin = maxf(spin, float(spin_sum[p]))
	check(spin < 10.0, "a knocked-out fighter's arms lie still, not spinning like a helicopter (%.1f rad/s on average)" % spin)
	await fresh()
	w.battle_on = false
	var rifleman := w.spawn_fighter("soldier", Vector2(0, 150), "red", "peaceful")
	await frames(30)
	var gun: Toy = rifleman.weapon_toy
	var muzzle_end := gun.to_global(Vector2(gun.w * 0.45, 0))
	var butt_end := gun.to_global(Vector2(-gun.w * 0.45, 0))
	var tip: Vector2 = muzzle_end if absf(muzzle_end.x - rifleman.center().x) > absf(butt_end.x - rifleman.center().x) else butt_end
	check(w.thing_at(tip) == rifleman, "clicking a soldier's rifle picks the soldier (you can't pull it out of their hands)")
	w.apply_command(0, {"cmd": "nail", "uid": gun.uid})
	check(not gun.nailed, "and you can't nail it on its own")
	w.apply_command(0, {"cmd": "pause", "on": true})
	var c0 := rifleman.center()
	w.apply_command(0, {"cmd": "grab", "uid": rifleman.uid, "x": c0.x, "y": c0.y})
	for i in 20:
		w.apply_command(0, {"cmd": "drag", "x": c0.x + 200.0, "y": c0.y - 100.0})
		await get_tree().physics_frame
	w.apply_command(0, {"cmd": "release"})
	var moved := rifleman.center() - c0
	w.apply_command(0, {"cmd": "pause", "on": false})
	check(moved.distance_to(Vector2(200, -100)) < 40.0, "while paused you can drag a fighter somewhere else (moved %s)" % str(moved))
	await fresh()
	var target_jelly := w.spawn_wiggly("bloop", Vector2(0, 0))
	await frames(2)
	target_jelly.set_frozen(5.0)   # hangs in the air
	Combat.launch(w, null, "arrow", Vector2(-250, 0), 0.0, 900.0)
	var floating := false
	for i in 90:
		await get_tree().physics_frame
		for a in w.toys():
			if a.id == "arrow" and a.nailed and a.global_position.y < 200.0:
				floating = true
	check(not floating, "an arrow that hits a Wiggly bounces off instead of sticking in mid-air")

	print("stand-offs")
	await fresh()
	# two guards far out of each other's reach would wait forever
	w.spawn_fighter("knight", Vector2(-1100, 150), "red", "defend")
	w.spawn_fighter("knight", Vector2(1100, 150), "blue", "defend")
	var st_t := 0
	var charged_at := -1
	while w.last_winner == "" and st_t < 120 * 60:
		await get_tree().physics_frame
		st_t += 1
		if w.brave and charged_at < 0:
			charged_at = st_t
	check(charged_at > 0 and charged_at / 120.0 >= World.QUIET_CHARGE - 1.0, "📣 after %.0f s with nobody hurt, everyone charges (at %.0f s)" % [World.QUIET_CHARGE, charged_at / 120.0])
	check(w.last_winner != "", "so even two guards far apart finish the battle (%s won after %.0f s)" % [w.last_winner, st_t / 120.0])
	check(not w.brave and w.quiet_t == 0.0, "and the charge is over once someone wins")

	await _knocked_out()

	print("nuke")
	await fresh()
	for i in 6:
		w.spawn_fighter("soldier", Vector2(-300 + i * 120, 150), "red", "peaceful")
	var nuke := w.spawn_toy("nuke", Vector2(0, 200))
	await frames(30)
	check(is_instance_valid(nuke), "a nuke sits still until it is set off")
	if not is_instance_valid(nuke):
		print("test_fight: %d failure(s)" % fails)
		get_tree().quit(1)
		return
	ToyLogic.trigger(w, nuke)
	nuke.fuse = 0.01
	await frames(60)
	var standing_after := w.fighters().filter(func(f): return f.alive()).size()
	check(standing_after == 0, "a nuke knocks out everyone nearby (%d still up)" % standing_after)

	print("test_fight: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## A heap of knocked-out fighters stops moving (their bodies freeze where they
## lie), but still reacts to everything that used to move it.
func _knocked_out() -> void:
	print("knocked out")
	await fresh()
	w.battle_on = false
	var heap: Array[Fighter] = []
	for i in 14:
		heap.append(w.spawn_fighter(["soldier", "knight", "viking", "wolf", "archer", "ninja", "bear"][i % 7], Vector2(-250 + (i % 7) * 45, 150 - (i / 7) * 100), "red", "peaceful"))
	await frames(2)
	for f in heap:
		f.hurt(99999.0, Vector2(0, -150))
	var all_still := func() -> bool: return heap.all(func(f): return f.is_resting())
	var rested: bool = await wait_for(all_still, 15.0)
	check(rested, "a heap of %d knocked-out fighters comes to rest (%d lying still)" % [heap.size(), heap.filter(func(f): return f.is_resting()).size()])
	var spots := _spots(heap)
	bumps = 0
	await frames(120)
	# (a dropped weapon or two may still rattle about for a moment: it used to be hundreds of bumps a second)
	check(bumps <= 10 and _moved(heap, spots) < 0.5, "and stays quiet: hardly a bump or a puff, nothing moves (%d bumps, moved %.1f px)" % [bumps, _moved(heap, spots)])
	check(heap.all(func(f): return f.state == "dead" and f.face() == "ko"), "still knocked out (X eyes and stars)")
	check(heap.all(func(f): return f._supported()), "and every one of them lies on something (nobody stuck in mid-air)")

	# a blast throws them about
	spots = _spots(heap)
	Combat.blast(w, Vector2(-100, 290), 260.0, 1200.0, 10.0)
	await frames(30)
	var thrown := heap.filter(func(f): return f.center().distance_to(spots[f]) > 30.0).size()
	check(thrown >= heap.size() / 2, "a blast still throws them about (%d of %d moved)" % [thrown, heap.size()])
	await wait_for(all_still, 15.0)

	# the grab tool drags one away (and the ones it was holding up fall)
	var f0: Fighter = heap[heap.size() - 1]
	var c0 := f0.center()
	w.apply_command(0, {"cmd": "grab", "uid": f0.uid, "x": c0.x, "y": c0.y})
	for i in 40:
		w.apply_command(0, {"cmd": "drag", "x": c0.x + 300.0, "y": c0.y - 150.0})
		await get_tree().physics_frame
	w.apply_command(0, {"cmd": "release"})
	check(f0.center().distance_to(c0) > 150.0, "you can still drag one away (moved %.0f px)" % f0.center().distance_to(c0))
	await frames(120)
	check(heap.all(func(f): return f.is_resting() == false or f._supported()), "and nobody it held up is left hanging in mid-air")
	await wait_for(all_still, 15.0)

	# the gravity turns upside down
	var ys := _spots(heap)
	w.set_gravity("flip")
	await frames(40)
	var risen := heap.filter(func(f): return f.center().y < ys[f].y - 20.0).size()
	check(risen >= heap.size() - 1, "turning gravity upside down lifts them off the floor (%d of %d)" % [risen, heap.size()])
	w.set_gravity("normal")
	await wait_for(all_still, 15.0)

	# a fan switched on next to them
	spots = _spots(heap)
	var fan := w.spawn_toy("fan", Vector2(-480, 250))
	fan.nailed = true
	fan.update_freeze()
	w.apply_command(0, {"cmd": "use", "uid": fan.uid})
	await frames(90)
	var blown := heap.filter(func(f): return f.center().x > spots[f].x + 10.0).size()
	check(blown >= 1, "a fan still blows them along (%d moved)" % blown)
	w.remove(fan.uid, false)

	# Revive brings one back up
	var back: Fighter = heap[1]
	w.apply_command(0, {"cmd": "revive", "uid": back.uid})
	await frames(30)
	check(back.state == "stand" and not back.is_resting(), "💖 Revive gets one back on its feet")

	# the ground going: a platform, and a toy, under them
	await fresh()
	w.battle_on = false
	w.apply_command(0, {"cmd": "platform", "x0": -400, "y0": 60, "x1": 0, "y1": 80})
	var shelf := w.spawn_toy("metal_beam", Vector2(300, 180), 0.0, 1.6)
	shelf.nailed = true
	shelf.update_freeze()
	var up_top: Array[Fighter] = []
	for i in 3:
		up_top.append(w.spawn_fighter("soldier", Vector2(-330 + i * 110, -40), "red", "peaceful"))
	var on_shelf := w.spawn_fighter("soldier", Vector2(300, 100), "red", "peaceful")
	await frames(30)
	for f in up_top + [on_shelf]:
		f.hurt(99999.0)
	await wait_for(func(): return (up_top + [on_shelf]).all(func(f): return f.is_resting()), 12.0)
	check(up_top.all(func(f): return f.is_resting() and f.center().y < 70.0), "knocked out on a platform, they lie still on it")
	w.apply_command(0, {"cmd": "unplatform", "x": -200, "y": 70})
	await frames(90)
	check(up_top.all(func(f): return f.center().y > 150.0), "erasing the platform under them drops them (lowest at y %.0f)" % up_top.map(func(f): return f.center().y).min())
	await wait_for(func(): return on_shelf.is_resting(), 6.0)   # (erasing the platform woke everyone)
	var y_shelf := on_shelf.center().y
	check(on_shelf.is_resting() and y_shelf < 180.0, "one knocked out on a nailed-down beam lies still on it")
	w.apply_command(0, {"cmd": "erase", "uid": shelf.uid})
	await frames(90)
	check(on_shelf.center().y > y_shelf + 40.0, "erasing the beam drops it (%.0f px)" % (on_shelf.center().y - y_shelf))
	# something thrown at one lying on its own
	var lone := w.spawn_fighter("soldier", Vector2(700, 150), "red", "peaceful")
	await frames(2)
	lone.hurt(99999.0)
	await wait_for(func(): return lone.is_resting(), 8.0)
	var c1 := lone.center()
	var ball := w.spawn_toy("bowling_ball", c1 + Vector2(-300, -10))
	ball.linear_velocity = Vector2(900, 0)
	await frames(60)
	check(lone.center().distance_to(c1) > 30.0, "a bowling ball thrown at one lying still knocks it along (%.0f px)" % lone.center().distance_to(c1))
	# nobody rests on a Wiggly: it would hop out from under them
	var jelly := w.spawn_wiggly("boulder", Vector2(-200, 200), 1.6)
	jelly.player_id = 99   # keeps still
	await frames(120)
	var on_jelly := w.spawn_fighter("knight", jelly.com + Vector2(0, -jelly.radius() - 60.0), "red", "peaceful")
	await frames(2)
	on_jelly.hurt(99999.0)
	await frames(360)
	check(not on_jelly.is_resting() or on_jelly.center().distance_to(jelly.com) > jelly.radius() + 50.0, "and one lying on a Wiggly doesn't freeze there (it could hop away)")


func _spots(fs: Array) -> Dictionary:
	var d := {}
	for f in fs:
		d[f] = f.center()
	return d


func _moved(fs: Array, spots: Dictionary) -> float:
	var most := 0.0
	for f in fs:
		most = maxf(most, f.center().distance_to(spots[f]))
	return most


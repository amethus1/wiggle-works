extends Node
## Toys and Wiggly powers against people, animals and dinosaurs: zaps, fire,
## water and rain, ice, ground pounds, Gummy, big Wigglies, the saucer's
## beam, fans, bubbles, magnets, wired battle traps and heavy things bowling
## armies over.
## godot --headless --path . -- --test=toyfight

var fails := 0
var w: World
var events := {}


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
	events.clear()
	await frames(2)


func _count(name: String, _a: Dictionary) -> void:
	events[name] = int(events.get(name, 0)) + 1


## A fighter that won't fight back and can't be knocked out by accident.
func dummy(type: String, x: float, team := "red", y := 150.0) -> Fighter:
	var f := w.spawn_fighter(type, Vector2(x, y), team, "peaceful")
	f.max_hp = 5000.0
	f.hp = 5000.0
	return f


## Waits up to `sec` seconds for `cond` to come true.
func wait_for(cond: Callable, sec: float) -> bool:
	for i in int(sec * 120.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _ready() -> void:
	seed(11)
	await get_tree().process_frame
	w = World.new()
	add_child(w)
	var fx := Effects.new()
	fx.world = w
	add_child(fx)
	w.fx.connect(fx.handle)
	w.fx.connect(_count)
	w.load_world("canvas", false)

	await _zappy()
	await _fire_and_water()
	await _ice()
	await _boulder_and_gummy()
	await _big_wigglies()
	await _saucer_and_fans()
	await _bubbles()
	await _magnets()
	await _traps()
	await _heavy_things()
	await _friends_screens()
	await _speed()

	print("test_toyfight: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _zappy() -> void:
	print("⚡ Zappy")
	await fresh()
	w.battle_on = false
	var line: Array[Fighter] = []
	for i in 6:
		line.append(w.spawn_fighter("soldier", Vector2(-100 + i * 60, 150), "red", "peaceful"))
	var zappy := w.spawn_wiggly("zappy", Vector2(-230, 200))
	await frames(60)
	zappy.use_special()
	await frames(2)
	check(line[0].stun_t > 0.0 and line[0].hp < line[0].max_hp, "Zappy's zap stuns the soldier next to it and hurts a little (%.0f/%.0f)" % [line[0].hp, line[0].max_hp])
	check(line[5].stun_t > 0.0 and line[5].center().distance_to(zappy.com) > 300.0, "and the zap jumps along the line to soldiers it couldn't reach (%d stunned)" % line.filter(func(f): return f.stun_t > 0.0).size())
	check(line.all(func(f): return f.alive() and f.hp > f.max_hp * 0.6), "but nobody gets knocked out by it")
	check(line[0].shows("zap") and line[0].face() == "zapped", "a zapped soldier shows its sparks (mood \"%s\")" % line[0].mood)
	w.battle_on = true
	var foe := dummy("stick", line[0].center().x - 70.0, "blue")
	line[0].stun_t = 1.5
	var hp_foe := foe.hp
	await frames(120)
	check(foe.hp == hp_foe and line[0].swing <= 0.0, "a stunned soldier can't fight for a moment")
	await wait_for(func(): return line[0].stun_t <= 0.0, 3.0)
	check(line[0].stun_t <= 0.0 and not line[0].helpless(), "and then it shakes it off")

	await fresh()
	var dry := dummy("soldier", -300)
	var soaked := dummy("soldier", 300)
	var tin := dummy("knight", 0)
	await frames(30)
	soaked.wet = 1.0
	var h0 := dry.hp
	dry.zap()
	soaked.zap()
	tin.zap()
	var dry_hurt := h0 - dry.hp
	var wet_hurt := soaked.max_hp - soaked.hp
	check(wet_hurt > dry_hurt * 1.4 and soaked.stun_t > dry.stun_t, "a wet soldier gets zapped harder (%.1f vs %.1f damage)" % [wet_hurt, dry_hurt])
	check(tin.stun_t > dry.stun_t, "and so does a knight in metal armor (stunned %.1f s vs %.1f s)" % [tin.stun_t, dry.stun_t])
	await fresh()
	w.battle_on = false
	var pond: Array[Fighter] = []
	for i in 5:
		var f := dummy("soldier", -200 + i * 140)
		pond.append(f)
	await frames(20)
	for f in pond:
		f.wet = 1.0
	var spark := w.spawn_wiggly("zappy", Vector2(-330, 200))
	await frames(30)
	spark.use_special()
	await frames(2)
	var got := pond.filter(func(f): return f.stun_t > 0.0).size()
	check(got == pond.size(), "a zap runs through a whole row of wet soldiers, even far apart (%d of %d)" % [got, pond.size()])


func _fire_and_water() -> void:
	print("🔥 Blaze, 💧 water and 🌧️ rain")
	await fresh()
	w.battle_on = false
	var camper := dummy("soldier", 0)
	var blaze := w.spawn_wiggly("blaze", Vector2(-90, 200))
	await frames(40)
	blaze.use_special()
	await frames(2)
	check(camper.burning > 0.0, "Blaze's flame puff sets a soldier on fire")
	var soggy := dummy("soldier", -500)
	await frames(20)
	soggy.wet = 1.0
	soggy.ignite(3.0)
	check(soggy.burning <= 0.0 and soggy.wet < 1.0, "a wet soldier doesn't catch fire, it just steams")
	w.apply_command(0, {"cmd": "spawn", "id": "water_tub", "x": 500, "y": 300})
	var diver := dummy("soldier", 500, "red", 40.0)
	diver.burning = 8.0
	var out: bool = await wait_for(func(): return diver.burning <= 0.0, 3.0)
	check(out and diver.wet > 0.5, "falling into water puts the fire out and gets them wet (wet %.2f)" % diver.wet)
	var torch := dummy("soldier", -250)
	await frames(20)
	torch.burning = 8.0
	w.cast_magic("rain")
	await frames(30)
	check(torch.burning <= 0.0 and torch.wet > 0.5, "🌧️ Rain Shower puts out burning fighters")
	check(torch.shows("wet"), "and they drip for a while (mood \"%s\")" % torch.mood)
	await fresh()
	w.fires.append({"p": Vector2(0, 280), "r": 150.0, "t": 7.0})
	w.cast_magic("rain")
	await frames(120 * 3)
	check(w.fires.is_empty(), "rain puts out napalm fires on the ground too")


func _ice() -> void:
	print("❄️ Frosty and the Freeze Bomb")
	await fresh()
	var bull := w.spawn_fighter("bull", Vector2(-600, 150), "wild", "attack")
	var bait := dummy("stick", 400, "red")
	var charged: bool = await wait_for(func(): return bull.charge_t > 0.0 and absf(bull.body.linear_velocity.x) > 200.0, 8.0)
	check(charged, "a bull charges at a stick figure")
	var frosty := w.spawn_wiggly("frosty", bull.center() + Vector2(0, -150))
	frosty.use_special()
	await frames(2)
	check(bull.frozen_t > 0.0 and bull.state == "stand" and bull.body.freeze, "Frosty freezes the charging bull into an ice block")
	var p0 := bull.center()
	var hp0 := bait.hp
	await frames(90)
	check(bull.center().distance_to(p0) < 2.0 and bait.hp == hp0, "the frozen bull stays put instead of charging on")
	check(bull.shows("ice") and bull.face() == "frozen", "and its mood tells a friend's screen to draw the ice (\"%s\")" % bull.mood)
	var thawed: bool = await wait_for(func(): return bull.frozen_t <= 0.0, 6.0)
	check(thawed and not bull.body.freeze and bull.alive(), "the ice pops after a few seconds and the bull is free again")
	check(int(events.get("ice_pop", 0)) >= 1, "with a crack of ice")

	await fresh()
	w.battle_on = false
	var hopper := dummy("soldier", -300)
	await frames(40)
	hopper.body.linear_velocity = Vector2(0, -600)   # jump!
	await frames(15)
	var top := hopper.center()
	w.freeze_area(top, 120.0, 5.0)
	await frames(60)
	check(hopper.frozen_t > 0.0 and absf(hopper.center().y - top.y) < 2.0 and top.y < 200.0, "a soldier frozen in mid-jump hangs in the air")
	check(hopper.frozen_t <= Fighter.MAX_FREEZE, "and fighters only stay frozen for a few seconds (%.1f s left)" % hopper.frozen_t)
	hopper.hurt(5.0, Vector2(0, -900))
	check(hopper.frozen_t <= 0.0 and hopper.state == "ragdoll", "a big blast smashes the ice block and sends them flying")
	var squad: Array[Fighter] = []
	for i in 4:
		squad.append(dummy("knight", 200 + i * 50))
	await frames(40)
	var bomb := w.spawn_toy("freeze_bomb", Vector2(275, 250))
	ToyLogic.trigger(w, bomb)
	await frames(120)
	check(squad.all(func(f): return f.frozen_t > 0.0), "a Freeze Bomb freezes a whole squad of knights")
	var smashed := squad[0]
	var ball := w.spawn_toy("bowling_ball", smashed.center() + Vector2(-120, 0))
	ball.linear_velocity = Vector2(600, 0)
	await frames(40)
	check(smashed.frozen_t <= 0.0, "and a bowling ball smashes one free")


func _boulder_and_gummy() -> void:
	print("🪨 Boulder and 🍬 Gummy")
	await fresh()
	w.battle_on = false
	var squad: Array[Fighter] = []
	for i in 5:
		squad.append(dummy("soldier", -60 + i * 30))
	var rex := dummy("trex", 90, "wild")
	var boulder := w.spawn_wiggly("boulder", Vector2(-150, -150))
	await frames(10)
	boulder.use_special()
	var pounded: bool = await wait_for(func(): return int(events.get("pound", 0)) > 0, 3.0)
	await frames(6)
	var down := squad.filter(func(f): return f.state != "stand").size()
	check(pounded and down >= 4, "Boulder's ground pound launches a squad of soldiers (%d of %d)" % [down, squad.size()])
	check(rex.state == "stand", "a T-Rex a little further off only wobbles")
	var up: bool = await wait_for(func(): return squad.all(func(f): return f.state == "stand"), 8.0)
	var lost := 0.0
	for f in squad:
		lost = maxf(lost, f.max_hp - f.hp)
	check(up and lost < 40.0, "and everyone gets back up (it only hurts a little: %.0f hp at most)" % lost)

	await fresh()
	var trex := w.spawn_fighter("trex", Vector2(-700, 150), "wild", "attack")
	var snack := dummy("stick", 700, "red")
	await frames(120)
	var x0 := trex.center().x
	await frames(120)
	var free_speed := absf(trex.center().x - x0)
	var gummy := w.spawn_wiggly("gummy", trex.center() + Vector2(240, 40))
	await frames(20)
	gummy.use_special()
	var stuck: bool = await wait_for(func(): return trex.goo_t > 0.0, 6.0)
	check(stuck and w.links.any(func(l): return l.b is FighterPart and l.b.fighter == trex), "Gummy in Sticky Mode sticks to a T-Rex that walks into it")
	await frames(30)
	x0 = trex.center().x
	await frames(120)
	var gummed_speed := absf(trex.center().x - x0)
	check(trex.goo_t > 0.0 and gummed_speed < free_speed * 0.6, "and slows it right down (%.0f px/s instead of %.0f)" % [gummed_speed, free_speed])
	check(trex.shows("goo"), "with gummy goo on its feet")
	await fresh()
	var squad2: Array[Fighter] = []
	for i in 3:
		squad2.append(w.spawn_fighter("soldier", Vector2(-60 + i * 60, 150), "red", "attack"))
	var glue := w.spawn_toy("glue_bomb", Vector2(0, 250))
	ToyLogic.trigger(w, glue)
	await frames(120)
	check(squad2.all(func(f): return f.goo_t > 0.0), "a Glue Bomb gums up everyone's feet")


func _big_wigglies() -> void:
	print("🫧 big Wigglies")
	await fresh()
	w.battle_on = false
	var pin := w.spawn_fighter("soldier", Vector2(0, 150), "red", "peaceful")
	var big := w.spawn_wiggly("bloop", Vector2(-280, 190), 2.2)
	await frames(30)
	big.set_velocity(Vector2(850, -40))   # flung at them
	var bowled: bool = await wait_for(func(): return pin.state != "stand", 2.0)
	check(bowled, "a big fast Wiggly bowls a soldier over")
	check(pin.hp > pin.max_hp * 0.85, "without really hurting them (%.0f/%.0f)" % [pin.hp, pin.max_hp])
	var still := dummy("soldier", 400)
	var small := w.spawn_wiggly("bloop", Vector2(250, 220), 0.8)
	await frames(30)
	small.set_velocity(Vector2(160, 0))
	await frames(120)
	check(still.state == "stand", "a small slow Wiggly doesn't knock a soldier over")
	var _puffy := w.spawn_wiggly("puffy", still.center() + Vector2(0, -220))
	var y0 := still.center().y
	var jumped := 0.0
	for i in 240:
		await get_tree().physics_frame
		jumped = maxf(jumped, y0 - still.center().y)
	check(still.state == "stand" and jumped < 20.0 and still.hp == still.max_hp, "and a Puffy landing on a soldier's head doesn't bounce them about (%.0f px)" % jumped)


func _saucer_and_fans() -> void:
	print("🛸 the saucer's tractor beam and 🌀 fans")
	await fresh()
	w.battle_on = false
	var saucer := w.spawn_toy("saucer", Vector2(0, -150))
	var flyer := dummy("soldier", 0)
	var dino := dummy("raptor", 20, "wild")
	await frames(60)
	var y_soldier := flyer.center().y
	var y_dino := dino.center().y
	w.apply_command(0, {"cmd": "use", "uid": saucer.uid})
	await frames(120 * 2)
	check(flyer.center().y < y_soldier - 120.0, "the saucer's tractor beam lifts a soldier (%.0f px up)" % (y_soldier - flyer.center().y))
	check(dino.center().y < y_dino - 80.0, "and a raptor (%.0f px up)" % (y_dino - dino.center().y))
	check(flyer.helpless() and flyer.face() == "scared", "who kicks helplessly instead of fighting")
	w.apply_command(0, {"cmd": "use", "uid": saucer.uid})
	var landed: bool = await wait_for(func(): return flyer.center().y > y_soldier - 20.0, 4.0)
	check(landed, "switching the beam off drops them again")

	await fresh()
	var pushes := {}
	for k in ["chicken", "soldier", "trex"]:
		await fresh()
		w.battle_on = false
		var fan := w.spawn_toy("fan", Vector2(-400, 260))
		fan.nailed = true
		fan.update_freeze()
		var who := dummy(k, -200, "wild")
		await frames(40)
		var start := who.center().x
		w.apply_command(0, {"cmd": "use", "uid": fan.uid})
		await frames(120 * 2)
		pushes[k] = who.center().x - start
	check(float(pushes.soldier) > 100.0, "a fan blows a soldier away (%.0f px)" % float(pushes.soldier))
	check(float(pushes.chicken) > float(pushes.soldier) and float(pushes.trex) < float(pushes.soldier) * 0.5,
		"a chicken goes further, a T-Rex barely moves (%.0f, %.0f px)" % [float(pushes.chicken), float(pushes.trex)])
	await fresh()
	w.battle_on = false
	w.apply_command(0, {"cmd": "platform", "x0": -500, "y0": 0, "x1": -100, "y1": 20})
	var fan2 := w.spawn_toy("fan", Vector2(-470, -30))
	fan2.nailed = true
	fan2.update_freeze()
	fan2.on = true
	var ledge := dummy("soldier", -300, "red", -80.0)
	var fell: bool = await wait_for(func(): return ledge.center().y > 150.0, 5.0)
	check(fell, "a fan blows a soldier right off the edge of a platform")


func _bubbles() -> void:
	print("🫧 bubbles")
	await fresh()
	w.battle_on = false
	var bub := w.spawn_toy("bubbler", Vector2(-400, 270))
	bub.nailed = true
	bub.update_freeze()
	var kid := dummy("stick", -230)
	var rex := dummy("trex", -110, "wild")
	await frames(90)
	w.apply_command(0, {"cmd": "use", "uid": bub.uid})
	var caught: bool = await wait_for(func(): return kid.bubble_t > 0.0, 3.0)
	w.apply_command(0, {"cmd": "use", "uid": bub.uid})
	check(caught, "a Bubble Maker catches a stick figure in a bubble")
	var y0 := kid.center().y
	await frames(120 * 2)
	check(kid.center().y < y0 - 80.0 and kid.helpless(), "and floats them up helplessly (%.0f px)" % (y0 - kid.center().y))
	check(kid.shows("bubble"), "inside a bubble a friend's screen can see")
	check(rex.bubble_t <= 0.0, "a T-Rex is too big for the Bubble Maker")
	var popped: bool = await wait_for(func(): return kid.bubble_t <= 0.0, 4.0)
	check(popped and kid.state == "ragdoll", "the bubble pops and they tumble down")
	var up: bool = await wait_for(func(): return kid.state == "stand", 6.0)
	check(up, "and get back up")
	await fresh()
	var army: Array[Fighter] = []
	for i in 3:
		army.append(w.spawn_fighter("knight", Vector2(-60 + i * 60, 150), "red", "attack"))
	var trex := dummy("trex", 220, "wild")
	await frames(40)
	var bomb := w.spawn_toy("bubble_bomb", Vector2(80, 250))
	ToyLogic.trigger(w, bomb)
	await frames(120)
	check(army.all(func(f): return f.bubble_t > 0.0) and trex.bubble_t > 0.0, "a Bubble Bomb floats a whole squad away, T-Rex and all")


func _magnets() -> void:
	print("🧲 magnets")
	await fresh()
	w.battle_on = false
	var mag := w.spawn_toy("magnet", Vector2(0, 280))
	mag.nailed = true
	mag.update_freeze()
	var knight := dummy("knight", 260)
	var gunner := dummy("soldier", -220)
	var archer := dummy("archer", -330)
	var plain := dummy("stick", 360)
	await frames(40)
	var rifle: Toy = gunner.weapon_toy
	var bow: Toy = archer.weapon_toy
	var kx := knight.center().x
	var px := plain.center().x
	w.apply_command(0, {"cmd": "use", "uid": mag.uid})
	await frames(120 * 2)
	check(knight.center().x < kx - 60.0, "a magnet drags a knight in metal armor toward it (%.0f px)" % (kx - knight.center().x))
	check(absf(plain.center().x - px) < 20.0, "but not a stick figure with no metal on")
	check(gunner.weapon_toy == null and gunner.weapon_id == "", "a magnet yanks the rifle out of a soldier's hands")
	check(is_instance_valid(rifle) and not rifle.extra.has("held_by") and not rifle.freeze and rifle.collision_layer == Toy.LAYER_TOYS,
		"and the rifle becomes a loose toy")
	check(is_instance_valid(rifle) and rifle.global_position.distance_to(mag.global_position) < 120.0, "that the magnet pulls in (%.0f px away)" % rifle.global_position.distance_to(mag.global_position))
	check(archer.weapon_toy == bow, "an archer's wooden bow stays in their hands")
	check(int(events.get("yoink", 0)) >= 1, "YOINK!")


func _traps() -> void:
	print("🔌 wired battle traps")
	await fresh()
	w.battle_on = false
	var c4 := w.spawn_toy("c4", Vector2(300, 280))
	var c4_id := c4.uid
	var bat := w.spawn_toy("battery", Vector2(200, 270))
	await frames(10)
	check(w.things.has(c4_id), "C4 waits quietly")
	w.add_link("wire", bat, c4, bat.global_position, c4.global_position)
	await frames(5)
	check(not w.things.has(c4_id) and int(events.get("boom", 0)) >= 1, "a battery wired to C4 sets it off")

	await fresh()
	var dyn := w.spawn_toy("dynamite", Vector2(300, 260))
	var dyn_id := dyn.uid
	var sw := w.spawn_toy("switch", Vector2(150, 280))
	await frames(10)
	w.add_link("wire", sw, dyn, sw.global_position, dyn.global_position)
	await frames(20)
	check(w.things.has(dyn_id), "a switch wired to dynamite waits until you flip it")
	w.apply_command(0, {"cmd": "use", "uid": sw.uid})
	await frames(5)
	check(not w.things.has(dyn_id), "and then BOOM")

	await fresh()
	w.battle_on = false
	var plate := w.spawn_toy("button", Vector2(0, 290))
	var barrel := w.spawn_toy("boom_barrel", Vector2(250, 270))
	var barrel_id := barrel.uid
	await frames(20)
	w.add_link("wire", plate, barrel, plate.global_position, barrel.global_position)
	var walker := dummy("soldier", -250)
	walker.max_hp = 100000.0
	walker.hp = 100000.0
	await frames(30)
	walker.player_id = 0   # walk it right, over the button
	walker.move_input = 1.0
	var gone: bool = await wait_for(func(): return not w.things.has(barrel_id), 6.0)
	walker.player_id = -1
	check(gone, "a soldier walking over a Big Button wired to a Boom Barrel sets it off")

	await fresh()
	var nailed_plate := w.spawn_toy("button", Vector2(0, 290))
	nailed_plate.nailed = true
	nailed_plate.update_freeze()
	var mine := w.spawn_toy("landmine", Vector2(220, 290))
	var mine_id := mine.uid
	await frames(10)
	w.add_link("wire", nailed_plate, mine, nailed_plate.global_position, mine.global_position)
	dummy("knight", 0, "red", 120.0)
	gone = await wait_for(func(): return not w.things.has(mine_id), 4.0)
	check(gone, "a nailed-down Big Button works as a pressure plate too")

	await fresh()
	var tick := w.spawn_toy("timer", Vector2(-100, 280))
	var rocket := w.spawn_toy("firework", Vector2(0, 270))
	await frames(5)
	w.add_link("wire", tick, rocket, tick.global_position, rocket.global_position)
	var lit: bool = await wait_for(func(): return rocket.fuse >= 0.0, 3.0)
	check(lit, "a Blinky Timer lights a wired firework")

	await fresh()
	var c4b := w.spawn_toy("c4", Vector2(100, 285))
	var c4b_id := c4b.uid
	var zappy := w.spawn_wiggly("zappy", Vector2(0, 220))
	await frames(40)
	zappy.use_special()
	await frames(5)
	check(not w.things.has(c4b_id), "a Zappy zap sets off C4 too")


func _heavy_things() -> void:
	print("🎳 heavy things knock armies over")
	await fresh()
	w.battle_on = false
	var pin := dummy("soldier", 0)
	pin.max_hp = 110.0
	pin.hp = 110.0
	var ball := w.spawn_toy("bowling_ball", Vector2(-300, 270))
	await frames(30)
	ball.linear_velocity = Vector2(450, 0)
	var flat: bool = await wait_for(func(): return pin.state != "stand", 2.0)
	check(flat, "a rolling bowling ball knocks a soldier flat")
	check(pin.alive() and pin.hp > pin.max_hp * 0.6, "but only hurts a bit (%.0f/%.0f)" % [pin.hp, pin.max_hp])
	await fresh()
	w.battle_on = false
	var pin2 := dummy("soldier", 0)
	var soccer := w.spawn_toy("soccer_ball", Vector2(-300, 270))
	await frames(30)
	soccer.linear_velocity = Vector2(450, 0)
	await frames(120)
	check(pin2.state == "stand", "a soccer ball at the same speed just bounces off")
	await fresh()
	w.battle_on = false
	var stroller := dummy("ninja", -200)
	var rock := w.spawn_toy("bowling_ball", Vector2(0, 270))
	rock.nailed = false
	await frames(30)
	stroller.player_id = 0
	stroller.move_input = 1.0
	var fell := false
	for i in 120 * 2:
		await get_tree().physics_frame
		if stroller.state != "stand":
			fell = true
	stroller.player_id = -1
	check(not fell, "running into a bowling ball doesn't knock you over")
	await fresh()
	w.battle_on = false
	var rex := dummy("trex", 0, "wild")
	var ball2 := w.spawn_toy("bowling_ball", Vector2(-350, 270))
	await frames(30)
	ball2.linear_velocity = Vector2(450, 0)
	await frames(120)
	check(rex.state == "stand", "a T-Rex shrugs off a bowling ball")

	await fresh()
	w.battle_on = false
	var row: Array[Fighter] = []
	for i in 4:
		row.append(w.spawn_fighter("soldier", Vector2(i * 70, 150), "red", "peaceful"))
	var truck := Builders.ride(w, "monster_truck", Vector2(-450, 220))
	await frames(30)
	w.apply_command(0, {"cmd": "use", "uid": truck.uid})
	var knocked := {}
	for i in 120 * 7:
		await get_tree().physics_frame
		for f in row:
			if f.state != "stand":
				knocked[f] = true
	check(knocked.size() >= 3, "a monster truck drives through a line of soldiers and bowls them over (%d of %d)" % [knocked.size(), row.size()])
	check(row.all(func(f): return f.alive()), "and nobody gets knocked out (%s hp left)" % str(row.map(func(f): return int(f.hp))))
	await fresh()
	w.battle_on = false
	var row2: Array[Fighter] = []
	for i in 3:
		row2.append(dummy("soldier", 0 + i * 60))
	var kart := Builders.ride(w, "go_kart", Vector2(-400, 240))
	await frames(30)
	w.apply_command(0, {"cmd": "use", "uid": kart.uid})
	var hit: bool = await wait_for(func(): return row2.any(func(f): return f.state != "stand"), 5.0)
	check(hit, "so does a go-kart")


func _friends_screens() -> void:
	print("👥 friends' screens")
	await fresh()
	w.battle_on = false
	var f := dummy("soldier", 0)
	await frames(30)
	f.set_frozen(3.0)
	f.wet = 1.0
	await frames(2)
	var copy := Fighter.new()
	copy.setup(w, "soldier", Vector2.ZERO)
	copy.puppet = true
	copy.net = {"c": Vector2.ZERO, "st": "stand", "mood": f.mood}
	check(copy.shows("ice") and copy.shows("wet") and copy.face() == "frozen", "a friend's copy of a frozen, wet soldier knows it's frozen and wet (\"%s\")" % f.mood)
	var t0 := copy.t
	copy._process(0.5)
	check(copy.t == t0, "and stops its animation while frozen")
	copy.free()
	f.thaw()
	await frames(2)
	check(not f.shows("ice") and f.face() == "calm", "thawing clears it again (\"%s\")" % f.mood)


func _speed() -> void:
	print("⏱️ speed")
	await fresh()
	w.battle_on = true
	for i in 50:
		w.spawn_fighter(["soldier", "knight", "archer", "gunner"][i % 4], Vector2(-1300 + (i % 25) * 40, 150 - (i / 25) * 60), "red", "attack")
		w.spawn_fighter(["soldier", "knight", "viking", "ninja"][i % 4], Vector2(300 + (i % 25) * 40, 150 - (i / 25) * 60), "blue", "attack")
	await frames(120)
	var base: float = await _step_ms(240)
	for x in [-900.0, -300.0, 300.0, 900.0]:
		var fan := w.spawn_toy("fan", Vector2(x - 150.0, 260))
		fan.on = true
		var mag := w.spawn_toy("magnet", Vector2(x, 260))
		mag.on = true
		var saucer := w.spawn_toy("saucer", Vector2(x + 100.0, -150))
		saucer.on = true
		var bub := w.spawn_toy("bubbler", Vector2(x + 150.0, 260))
		bub.on = true
		w.spawn_wiggly("bloop", Vector2(x, 100), 2.0)
	w.cast_magic("rain")
	w.cast_magic("wind")
	var busy: float = await _step_ms(240)
	print("        100 fighters: %.2f ms per step, with fans, magnets, saucers, bubbles, Wigglies, rain and wind: %.2f ms" % [base, busy])
	check(busy < base * 2.0 + 2.0, "100 fighters with toys all around them aren't much slower (%.2f ms vs %.2f ms a step)" % [busy, base])


## Average time the world takes per physics step over `n` steps (ms).
func _step_ms(n: int) -> float:
	var total := 0.0
	for i in n:
		await get_tree().physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / n

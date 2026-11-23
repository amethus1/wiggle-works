extends TestBase
## Toys and Wiggly powers against people, animals and dinosaurs: zaps, fire,
## water and rain, ice, ground pounds, Gummy, big Wigglies, the saucer's
## beam, fans, bubbles, magnets, wired battle traps and heavy things bowling
## armies over.
## godot --headless --path . -- --test=toyfight

var w: World
var events := {}
var fxv: Effects


## (frames() waits physics steps here: the playground's clock)
func _init() -> void:
	frames_are_steps = true


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


## Waits up to `sec` seconds (of physics steps) for `cond` to come true.
func wait_for(cond: Callable, sec := 3.0) -> bool:
	return await wait_steps_for(cond, sec)


func _ready() -> void:
	seed(11)
	await get_tree().process_frame
	w = World.new()
	add_child(w)
	var fx := Effects.new()
	fx.world = w
	add_child(fx)
	fxv = fx
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
	await _lying_still()
	await _review_fixes()
	await _combos()
	await _juice()
	await _speed()

	finish()


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
	seed(3)   # (now and then a truck stalls on the pile it makes: the same run every time)
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


## Knocked-out fighters that have come to rest lie frozen in place, but the
## saucer's beam, a magnet and a Wiggly rolling into them still move them.
func _lying_still() -> void:
	print("💤 knocked out and lying still")
	await fresh()
	w.battle_on = false
	var a := w.spawn_fighter("soldier", Vector2(-1000, 150), "red", "peaceful")
	var b := w.spawn_fighter("knight", Vector2(-250, 150), "red", "peaceful")
	var c := w.spawn_fighter("viking", Vector2(900, 150), "red", "peaceful")
	await frames(2)
	for f in [a, b, c]:
		f.hurt(99999.0)
	var still := await wait_for(func(): return a.is_resting() and b.is_resting() and c.is_resting(), 10.0)
	check(still, "three knocked-out fighters come to rest")
	var saucer := w.spawn_toy("saucer", a.center() + Vector2(0, -320))
	saucer.on = true
	var ya := a.center().y
	await frames(120)
	check(a.center().y < ya - 40.0, "the saucer's beam still lifts one lying still (%.0f px up)" % (ya - a.center().y))
	saucer.on = false
	# (close enough to pull hard: 250 px away, a knight lying on its face
	# barely slid in one try out of three, frozen or not)
	var mag := w.spawn_toy("magnet", b.center() + Vector2(180, -10))
	mag.on = true
	mag.nailed = true
	mag.update_freeze()
	var xb := b.center().x
	await frames(120)
	check(b.center().x > xb + 30.0, "a magnet still pulls a knight in armor lying still (%.0f px)" % (b.center().x - xb))
	mag.on = false
	var xc := c.center().x
	var rolly := w.spawn_wiggly("boulder", c.center() + Vector2(-260, -30), 1.4)
	rolly.set_velocity(Vector2(900, 0))
	await frames(60)
	check(absf(c.center().x - xc) > 20.0, "a Wiggly rolling into one lying still knocks it (%.0f px)" % absf(c.center().x - xc))


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
	# The wind knocks most of them over, and a field of ragdolls is 2 to 3½
	# times the physics work of the same army standing (it varies from run to
	# run). A toy or power that got slow with a crowd around it (looping over
	# everyone for everyone, say) costs far more than that.
	check(busy < base * 4.0 + 3.0, "100 fighters with toys all around them aren't too much slower (%.2f ms vs %.2f ms a step, under 4× + 3 ms)" % [busy, base])


## How long a physics step takes (ms): the median over `n` steps, timed
## directly from when the step's scripts start until the next step (or the
## frame's _process) begins, so it covers the scripts and Godot's physics.
## (Performance.TIME_PHYSICS_PROCESS only changes once a second, and a busy
## computer could make one sample count for half the reading. The median
## shrugs off the odd step the computer spent on something else.)
func _step_ms(n: int) -> float:
	var clock := _StepClock.new()
	add_child(clock)
	while clock.steps.size() < n:
		await get_tree().physics_frame
	clock.queue_free()
	var s: Array[float] = clock.steps.duplicate()
	s.sort()
	return s[s.size() / 2]


## Times physics steps: runs before everyone else's _physics_process and _process.
class _StepClock extends Node:
	var steps: Array[float] = []
	var _t0 := -1

	func _init() -> void:
		process_physics_priority = -1000000000
		process_priority = -1000000000

	func _physics_process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		if _t0 >= 0:
			steps.append((now - _t0) / 1000.0)
		_t0 = now

	func _process(_d: float) -> void:
		if _t0 >= 0:
			steps.append((Time.get_ticks_usec() - _t0) / 1000.0)
			_t0 = -1


func _review_fixes() -> void:
	print("🔧 fire on wet fighters, ice and trucks, toys on ragdolls, the saucer")
	await fresh()
	w.battle_on = false
	var soaked := dummy("soldier", 0)
	await frames(30)
	soaked.wet = 1.0
	w.fires.append({"p": soaked.center(), "r": 150.0, "t": 7.0})
	await frames(2)
	check(soaked.wet > 0.9 and soaked.burning <= 0.0, "a soaked soldier standing in a fire doesn't dry off in a couple of steps (wet %.2f)" % soaked.wet)
	await frames(60)
	check(soaked.burning <= 0.0 and int(events.get("steam", 0)) <= 3, "it steams a while, a few puffs, not one every step (%d puffs)" % int(events.get("steam", 0)))
	var caught: bool = await wait_for(func(): return soaked.burning > 0.0, 3.0)
	check(caught, "then dries off and catches fire")

	await fresh()
	w.battle_on = false
	var ice := dummy("soldier", 250)
	await frames(40)
	ice.set_frozen(4.0)
	var truck := Builders.ride(w, "monster_truck", Vector2(-250, 200))
	await frames(30)
	w.apply_command(0, {"cmd": "use", "uid": truck.uid})
	var smashed: bool = await wait_for(func(): return ice.frozen_t <= 0.0, 3.5)
	check(smashed and int(events.get("ice_smash", 0)) >= 1, "a driving monster truck smashes a frozen soldier's ice into chunks")
	check(ice.alive() and ice.state != "stand", "and bowls them over the bonnet")
	await fresh()
	w.battle_on = false
	var ice2 := dummy("chicken", 0, "wild")
	var kart := Builders.ride(w, "go_kart", Vector2(-150, 240))
	await frames(100)   # (the chicken lands first: frozen in mid-air, the kart would drive under it)
	w.apply_command(0, {"cmd": "use", "uid": kart.uid})
	ice2.set_frozen(4.0)
	var cracked: bool = await wait_for(func(): return ice2.frozen_t <= 0.0, 3.8)   # (the ice would pop by itself at 4 s)
	check(cracked, "even a go-kart's light wheels crack a frozen chicken out (they touch first)")

	await fresh()
	w.battle_on = false
	var down := w.spawn_fighter("soldier", Vector2(0, 150), "red", "peaceful")
	await frames(40)
	down.ragdoll(Vector2.ZERO)
	await frames(60)
	var hp0 := down.hp
	var steel := w.spawn_toy("steel_ball", down.center() + Vector2(-160, -160))
	steel.set_size(2.0)
	steel.gravity_scale = 0.0
	steel.linear_velocity = Vector2(850, 850)
	await frames(30)
	check(hp0 - down.hp > 8.0 and hp0 - down.hp <= 40.0, "a heavy ball hitting someone already knocked down hurts like it would standing up (%.0f, not 4 at most)" % (hp0 - down.hp))

	await fresh()
	w.battle_on = false
	var ufo := w.spawn_toy("saucer", Vector2(0, -60))
	ufo.nailed = true
	ufo.update_freeze()
	var cell := w.spawn_toy("battery", Vector2(-300, 280))
	await frames(5)
	w.add_link("wire", cell, ufo, cell.global_position, ufo.global_position)
	var rider := dummy("stick", 0, "red", 150.0)
	await frames(40)
	var ry := rider.center().y
	await frames(120)
	check(rider.center().y < ry - 100.0, "a nailed-down saucer wired to a battery beams people up (it used to need Use, and nailing broke it) (%.0f px up)" % (ry - rider.center().y))


## A wide pool of water (floor, walls and water) from x0 to x1, its floor at y.
func _pool(x0: float, x1: float, y: float, depth := 110.0) -> void:
	w.apply_command(0, {"cmd": "platform", "x0": x0 - 20, "y0": y, "x1": x1 + 20, "y1": y + 20})
	w.apply_command(0, {"cmd": "platform", "x0": x0 - 20, "y0": y - depth - 20, "x1": x0, "y1": y})
	w.apply_command(0, {"cmd": "platform", "x0": x1, "y0": y - depth - 20, "x1": x1 + 20, "y1": y})
	w.add_liquid(Rect2(x0, y - depth, x1 - x0, depth), "water", w.next_group)
	w._cut_water()


func _combos() -> void:
	print("⚡ elemental combos: water and metal, trampolines, warps; 🦕 dinos; laser swords")
	await fresh()
	w.battle_on = false
	_pool(-700.0, 700.0, 280.0)
	var swimmers: Array[Fighter] = []
	for x in [-550.0, 0.0, 550.0]:
		swimmers.append(dummy("soldier", x, "red", 150.0))
	var zappy := w.spawn_wiggly("zappy", Vector2(-660, 60))
	zappy.player_id = 99
	await frames(90)
	zappy.use_special()
	await frames(3)
	check(swimmers.all(func(f): return f.stun_t > 0.0), "a Zappy zap at the edge of a pool runs through all the water: every soldier in it is zapped, even 1100 px away (%s)" % str(swimmers.map(func(f): return snappedf(f.stun_t, 0.1))))
	check(int(events.get("zap_pool", 0)) >= 1, "with sparks all along the water")

	await fresh()
	w.battle_on = false
	var beams: Array[Toy] = []
	for i in 3:
		var b := w.spawn_toy("metal_beam", Vector2(-80 + i * 160, 285))
		b.nailed = true
		b.update_freeze()
		beams.append(b)
	var walker := dummy("soldier", 240, "red", 150.0)
	var bystander := dummy("soldier", 600, "red", 150.0)
	var zap2 := w.spawn_wiggly("zappy", Vector2(-260, 200))
	zap2.player_id = 99
	await frames(90)
	zap2.use_special()
	await frames(3)
	check(walker.stun_t > 0.0 and beams[2].electric > 0.0, "a zap runs along a row of touching metal beams into a soldier standing on the far end")
	check(bystander.stun_t <= 0.0, "but not into someone standing on the ground nearby")

	await fresh()
	w.battle_on = false
	var bloop := w.spawn_wiggly("bloop", Vector2(0, 230))
	bloop.player_id = 99   # (keeps still)
	await frames(90)
	var jumper := dummy("soldier", bloop.com.x, "red", -250.0)
	var touched := false
	var top_after := INF
	for i in 240:
		await get_tree().physics_frame
		if int(events.get("boing", 0)) > 0:
			touched = true
		if touched:
			top_after = minf(top_after, jumper.center().y)
	check(touched and top_after < bloop.com.y - 300.0, "a soldier dropping onto a Bloop bounces way back up: a living trampoline (up to %.0f px above it)" % (bloop.com.y - top_after))

	await fresh()
	w.battle_on = false
	var tw := w.spawn_wiggly("twinkle", Vector2(0, 230))
	tw.player_id = 99
	var near := dummy("knight", 70, "blue", 150.0)
	var far := dummy("knight", 700, "blue", 150.0)
	await frames(90)
	var y0 := near.center().y
	var hp0 := near.hp
	tw.use_special()
	await frames(2)
	check(near.center().y < y0 - 250.0 and far.center().y > y0 - 20.0, "Twinkle's warp sends a fighter right next to it high up into the air (%.0f px up), not one far away" % (y0 - near.center().y))
	var up_again: bool = await wait_for(func(): return near.state == "stand" and near.grounded, 8.0)
	check(up_again and near.hp > hp0 - 15.0, "who tumbles down and gets back up, hardly hurt (%.0f hp lost)" % (hp0 - near.hp))

	await fresh()
	w.battle_on = true
	var ptero := w.spawn_fighter("ptero", Vector2(-500, -100), "wild", "attack")
	var lunch := dummy("stick", 300, "red", 150.0)
	var grabbed: bool = await wait_for(func(): return ptero.carrying == lunch, 12.0)
	check(grabbed and int(events.get("snatch", 0)) >= 1, "a pterodactyl swoops down and snatches up a stick figure")
	var high := INF
	var y_grab := lunch.center().y
	var dropped := false
	for i in 120 * 4:
		await get_tree().physics_frame
		high = minf(high, lunch.center().y)
		if ptero.carrying == null:
			dropped = true
			break
	check(y_grab - high > 150.0, "and flies off up into the sky with it (%.0f px up)" % (y_grab - high))
	check(dropped, "then lets go")
	await fresh()
	w.battle_on = true
	var ptero2 := w.spawn_fighter("ptero", Vector2(-500, -100), "wild", "attack")
	var rex := dummy("trex", 300, "red", 100.0)
	var lifted_rex := false
	for i in 120 * 6:
		await get_tree().physics_frame
		if ptero2.carrying != null:
			lifted_rex = true
	check(not lifted_rex and rex.state == "stand", "but a T-Rex is far too heavy to carry off")
	w.battle_on = false

	await fresh()
	w.battle_on = true
	var brachio := w.spawn_fighter("brachio", Vector2(0, 0), "wild", "")
	var pest := w.spawn_fighter("soldier", Vector2(-450, 150), "red", "peaceful")
	pest.max_hp = 99999.0
	pest.hp = 99999.0
	var calm_hp := pest.hp
	await frames(120)
	check(brachio.pers == "peaceful" and brachio.target == null and pest.hp == calm_hp, "a Brachiosaurus is gentle: it leaves a soldier alone")
	pest.pers = "attack"
	brachio.hurt(30.0, Vector2.ZERO, pest)
	check(brachio.angry_t > 0.0 and brachio.target == pest and brachio.face() == "angry", "until somebody hurts it: then it gets angry")
	var stomped: bool = await wait_for(func(): return pest.hp < calm_hp, 10.0)
	check(stomped and int(events.get("angry", 0)) >= 1, "and stomps back at them")
	pest.player_id = 0   # (holds its fire)
	var calmed: bool = await wait_for(func(): return brachio.angry_t <= 0.0 and brachio.target == null, Fighter.ANGRY_FOR + 3.0)
	pest.player_id = -1
	check(calmed, "then calms down and is gentle again")
	w.battle_on = false

	await fresh()
	w.battle_on = false
	var jedi := dummy("knight", 0, "red", 150.0)
	var sw := w.spawn_toy("laser_sword", jedi.center())
	jedi.equip(sw)
	jedi.facing = -1.0
	var gunman := dummy("soldier", -500, "blue", 150.0)
	gunman.max_hp = 100.0
	gunman.hp = 100.0
	await frames(40)
	var jhp := jedi.hp
	seed(5)
	for i in 30:
		Combat.shoot(w, gunman, gunman.center() + Vector2(20, -20), (jedi.center() - gunman.center() - Vector2(20, -20)).angle(), 900.0, 10.0, 60.0)
	var pings := int(events.get("deflect", 0))
	check(pings >= 10 and pings < 30, "a laser sword bats bullets away (%d of 30)" % pings)
	check(jhp - jedi.hp < 30 * 10.0 * 0.75 and gunman.hp < 100.0, "the knight takes fewer hits, and some go back and hit the shooter (shooter hp %.0f)" % gunman.hp)
	jedi.facing = 1.0
	events.erase("deflect")
	for i in 10:
		Combat.shoot(w, gunman, gunman.center() + Vector2(20, -20), (jedi.center() - gunman.center() - Vector2(20, -20)).angle(), 900.0, 10.0, 60.0)
	check(int(events.get("deflect", 0)) == 0, "but not from behind")


func _juice() -> void:
	print("✨ swooshes, jolts, hitstop and night lights")
	await fresh()
	w.battle_on = true
	var a := w.spawn_fighter("viking", Vector2(-60, 150), "red", "attack")
	var b := dummy("knight", 40, "blue", 150.0)
	var swooshed: bool = await wait_for(func(): return not fxv.slashes.is_empty(), 4.0)
	check(swooshed, "a sword swing draws a swoosh in front of the fighter")
	w.battle_on = false
	await fresh()
	fxv.kick = Vector2.ZERO
	ToyLogic.boom(w, Vector2(fxv.view_rect.get_center().x + 400.0, 250), 260.0, 1500.0, false)
	await frames(4)
	await get_tree().process_frame
	check(fxv.kick.x > 0.5, "a blast to the right jolts the screen toward it (%.1f px)" % fxv.kick.x)
	fxv.hitstop_ok = true
	Engine.time_scale = 1.0
	fxv.hitstop(0.05)
	var stopped := Engine.time_scale < 0.5
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200:
		await get_tree().process_frame
	check(stopped and is_equal_approx(Engine.time_scale, w.time_scale), "hitstop stops the game for a blink, then carries on")
	fxv.hitstop_ok = false
	Engine.time_scale = 1.0

	await fresh()
	w.set_night(true)
	Builders.tub(w, "lava_tub", Vector2(0, 300))
	var z := w.spawn_wiggly("zappy", Vector2(-150, 200))
	z.player_id = 99
	w.spawn_toy("laser_sword", Vector2(300, 250))
	var torch := dummy("soldier", 500, "red", 150.0)
	torch.burning = 5.0
	for i in 6:
		await get_tree().process_frame
	var nl: Node = w.get_node("NightLights")
	var lit: int = nl.get_children().filter(func(l): return l is PointLight2D and l.visible).size()
	check(lit >= 4, "at night, lava, a Zappy, a laser sword and a fighter on fire light up the dark (%d lights)" % lit)
	w.set_night(false)
	for i in 4:
		await get_tree().process_frame
	lit = nl.get_children().filter(func(l): return l is PointLight2D and l.visible).size()
	check(lit == 0, "and by day they're off")


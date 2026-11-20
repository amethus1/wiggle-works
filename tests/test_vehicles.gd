extends Node
## Headless checks for the drivable and flyable vehicles: the race car,
## helicopter and fighter plane spawn on every map and fight on their own;
## every vehicle can be driven / flown in both views (B3Player); aircraft
## stay inside the map and can be shot down; the first-person seats sit in
## the right place; net_state / apply_net_state round-trips (puppets animate
## with no physics); the airshow, roadtrip and hangar scenarios run; and a
## big air battle keeps up with real time.
## godot --headless --path . -- --test=vehicles

const SPEED := 4.0
const NEW := ["car", "heli", "plane"]

var fails := 0
var b = null


func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func fresh(map := "grassland", scenario := "") -> void:
	B3Player.stop()
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	seed(4242)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin({"seed": 4242, "no_ui": true, "map": map, "scenario": scenario})
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED


func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	while b.time < end and guard < int(t * 60.0 * SPEED) + 600:
		await get_tree().physics_frame
		guard += 1


func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


func spawn(kind: String, team: String, p: Vector3, pers := "auto", yaw := INF) -> B3Unit:
	var u: B3Unit = b.spawn_unit(kind, team, p, pers, yaw)
	return u


func gh(u: B3Unit) -> float:
	return u.position.y - float(b.world.height_at(u.position.x, u.position.z))


func hurt_count(team: String) -> int:
	var n := 0
	for u: B3Unit in b.units:
		if u.team == team and (u.hp < u.max_hp or u.down):
			n += 1
	return n


func proj_count(kind: String) -> int:
	var n := 0
	for c in b.proj_root.get_children():
		if c is B3Proj and (c as B3Proj).kind == kind:
			n += 1
	return n


func alive(u) -> bool:
	return u != null and is_instance_valid(u) and not (u as B3Unit).dead


## Takes the trees and rocks away so test drives don't crash into them.
func clear_scenery() -> void:
	for c in b.world.scenery.get_children():
		if c is StaticBody3D:
			c.queue_free()


func _ready() -> void:
	await get_tree().process_frame
	B3Rules.reset()
	var only := OS.get_environment("B3_ONLY")
	if only != "":
		await call(only)
	else:
		await _spawn()
		await _ai_fight()
		await _drive_ground()
		await _drive_guns()
		await _fly_heli()
		await _fly_plane()
		await _bounds()
		await _shot_down()
		await _eyes()
		await _net()
		await _scenarios()
		await _performance()
	B3Player.stop()
	if b and is_instance_valid(b):
		b.queue_free()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	for i in 3:
		await get_tree().process_frame
	print("test_vehicles: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ spawn
func _spawn() -> void:
	print("new vehicles spawn")
	for id in NEW:
		check(B3Defs.UNIT_ORDER.vehicles.has(id) and B3Defs.item_cat(id) == "vehicles", "%s is in the Vehicles tab (%s)" % [id, B3Defs.item_label(id)])
	for map in B3Defs.MAP_ORDER:
		await fresh(String(map))
		var car := spawn("car", "red", at(-8, 0))
		var heli := spawn("heli", "blue", at(0, 0))
		var pl := spawn("plane", "green", at(8, 0))
		await sim(2.0)
		var ok_car := car is B3Vehicle and not (car is B3Aircraft) and alive(car) and absf(gh(car)) < 0.6 and car.global_basis.y.dot(Vector3.UP) > 0.95
		var ok_heli := heli is B3Aircraft and alive(heli) and gh(heli) > 5.0 and heli.global_basis.y.dot(Vector3.UP) > 0.95
		var ok_plane := pl is B3Aircraft and alive(pl) and gh(pl) > 8.0 and pl.linear_velocity.length() > 12.0
		check(ok_car and ok_heli and ok_plane, "%s: race car on its wheels, helicopter hovering (%.1f m up), plane flying (%.1f m up, %.0f m/s)" % [map, gh(heli), gh(pl), pl.linear_velocity.length()])


# --------------------------------------------------------------------- AI
func _ai_fight() -> void:
	print("the computer drives them")
	# race car: zooms at the enemy and bumps them
	await fresh()
	var car := spawn("car", "red", at(-16, 0))
	for i in 4:
		spawn("soldier", "blue", at(10, -6 + i * 4.0), "peaceful")
	await sim(0.3)
	var c0 := car.position
	b.set_fighting(true)
	var bumped := 0
	for i in 20:
		await sim(1.0)
		bumped = 0
		for u: B3Unit in b.units:
			if u.team == "blue" and (u.down or u.hp < u.max_hp):
				bumped += 1
		if bumped >= 2:
			break
	check(alive(car) and car.position.distance_to(c0) > 8.0 and bumped >= 2, "a race car zooms over and bumps soldiers (%d bumped)" % bumped)

	# helicopter: hovers up high, circles and shoots
	await fresh()
	var heli := spawn("heli", "red", at(-14, 0))
	for i in 5:
		spawn("soldier", "blue", at(12, -8 + i * 4.0), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	var low := 99.0
	var t := 0.0
	while t < 25.0 and b.kos < 2:
		await sim(1.0)
		t += 1.0
		if t > 3.0 and alive(heli):
			low = minf(low, gh(heli))
	check(alive(heli) and low > 5.0, "a helicopter stays up high while it fights (lowest %.1f m)" % low)
	check(b.kos >= 1 or hurt_count("blue") >= 3, "and shoots the enemy (%d KOs, %d hurt after %ds)" % [b.kos, hurt_count("blue"), int(t)])

	# plane: strafing runs and bombs
	await fresh()
	var pl := spawn("plane", "red", at(-20, 0))
	for i in 6:
		spawn("soldier", "blue", at(10, -10 + i * 4.0), "peaceful")
	await sim(0.3)
	b.set_fighting(true)
	var bombs := 0
	var lowest := 99.0
	var far := 0.0
	t = 0.0
	while t < 50.0 and b.kos < 3 and hurt_count("blue") < 3:
		await sim(0.5)
		t += 0.5
		if alive(pl):
			bombs = maxi(bombs, proj_count("bomb"))
			lowest = minf(lowest, gh(pl))
			far = maxf(far, maxf(absf(pl.position.x), absf(pl.position.z)))
	check(alive(pl) and (b.kos >= 1 or hurt_count("blue") >= 3), "a plane makes strafing runs (%d KOs, %d hurt after %ds)" % [b.kos, hurt_count("blue"), int(t)])
	check(lowest > 2.0, "and never hits the ground (lowest %.1f m)" % lowest)
	check(far < B3Defs.BOUNDS, "and stays inside the map (%.0f of %.0f m)" % [far, B3Defs.BOUNDS])
	# a full fight against an army ends
	await fresh()
	spawn("plane", "red", at(-24, -4))
	spawn("heli", "red", at(-20, 4))
	spawn("car", "red", at(-16, 0))
	for i in 4:
		spawn("soldier", "blue", at(14, -6 + i * 4.0))
	spawn("knight", "blue", at(12, 0))
	await sim(0.5)
	b.set_fighting(true)
	t = 0.0
	while b.winner == "" and t < 120.0:
		await sim(1.0)
		t += 1.0
	check(b.winner != "" and b.kos > 0, "a plane, a helicopter and a car fight an army to a result (%s after %ds)" % [b.winner, int(t)])


# ------------------------------------------------------------ driving them
func _drive_ground() -> void:
	print("driving the tank, jeep and race car")
	for kind in ["tank", "jeep", "car"]:
		await fresh()
		clear_scenery()
		var u := spawn(String(kind), "red", at(0, 0), "auto", 0.0) as B3Vehicle
		var foe := spawn("knight", "blue", at(0, 18), "peaceful")
		foe.hp = 9999.0
		foe.max_hp = 9999.0
		await sim(0.5)
		b.set_fighting(true)
		B3Player.start(u)
		var c := B3Player.me
		check(B3Player.active() and u.player and u.ctl == c, "%s: 🎮 you're driving it" % kind)
		# overhead: WASD (c.move) is where to go
		c.fp = false
		c.aim = u.position + Vector3(6, 0, 0)
		var p0 := u.position
		c.move = Vector3(1, 0, 0)
		await sim(3.0)
		c.move = Vector3.ZERO
		check(u.position.x - p0.x > 3.0, "%s: overhead, it drives where WASD points (%.1f m)" % [kind, u.position.x - p0.x])
		await sim(1.0)
		# first person: W gas, A/D steer
		c.fp = true
		c.look_yaw = u.facing
		c.look_pitch = 0.0
		var f0 := u.facing
		p0 = u.position
		c.steer = Vector2(0, 1)
		await sim(1.5)
		var fwd := Vector3(sin(f0), 0, cos(f0))
		check((u.position - p0).dot(fwd) > (1.5 if kind == "tank" else 2.5), "%s: first person, W drives forward (%.1f m)" % [kind, (u.position - p0).dot(fwd)])
		var ly0 := c.look_yaw
		f0 = u.facing
		c.steer = Vector2(1, 1)
		await sim(1.0)
		var turned := angle_difference(f0, u.facing)
		check(turned < -0.3, "%s: and D steers right (%.2f rad)" % [kind, turned])
		if kind != "tank":
			check(absf(angle_difference(ly0, c.look_yaw) - turned) < 0.25, "%s: the view turns with the car" % kind)
		c.steer = Vector2(0, -1)
		await sim(1.5)
		check(u.fwd_spd < -0.5, "%s: S reverses (%.1f m/s)" % [kind, u.fwd_spd])
		c.steer = Vector2.ZERO
		await sim(1.0)
		# shooting / honking
		if kind == "car":
			c.jump = true
			await sim(0.05)
			check(not c.jump and u._honk_t > 0.0, "car: Space honks")
			# drive into the knight: BONK
			var tgt := foe.position
			c.fp = false
			c.move = Vector3.ZERO
			B3Player.stop()
			u.global_position = tgt + Vector3(0, 0.2, -12)
			u.global_basis = Basis.IDENTITY
			u.linear_velocity = Vector3.ZERO
			B3Player.start(u)
			c = B3Player.me
			c.fp = true
			c.look_yaw = 0.0
			c.steer = Vector2(0, 1)
			var hit := false
			for i in 30:
				await sim(0.1)
				if foe.down or foe.hp < foe.max_hp:
					hit = true
					break
			c.steer = Vector2.ZERO
			check(hit, "car: driving into a fighter bumps it into the air")
			continue
		# park it facing the knight, then shoot
		B3Player.stop()
		u.global_position = foe.position + Vector3(0, 0.3, -12)
		u.global_basis = Basis.IDENTITY
		u.linear_velocity = Vector3.ZERO
		u.reset_physics_interpolation()
		B3Player.start(u)
		c = B3Player.me
		c.fp = true
		c.look_yaw = 0.0
		await sim(0.3)
		var c1 := proj_count("tankshell")
		var hp0 := foe.hp
		c.aim = foe.center()
		c.fire = true
		await sim(3.0)
		c.fire = false
		var aimed := absf(angle_difference(u.facing + u.turret_yaw, atan2(foe.position.x - u.position.x, foe.position.z - u.position.z)))
		check(aimed < 0.25, "%s: the turret turns to the crosshair (%.2f rad off)" % [kind, aimed])
		if kind == "tank":
			check(proj_count("tankshell") > c1 or foe.hp < hp0 or u.cd > 0.0, "tank: click fires the cannon")
			var cd2 := u.cd2
			c.fire2 = true
			await sim(0.6)
			c.fire2 = false
			check(u.cd2 > cd2 or u.burst2 > 0 or foe.hp < hp0, "tank: right-click fires the machine gun")
		else:
			check(foe.hp < hp0, "jeep: click fires the machine gun (%.0f damage)" % (hp0 - foe.hp))
		B3Player.stop()
		check(not u.player, "%s: Esc hands it back to the computer" % kind)


func _drive_guns() -> void:
	print("cannon and MG turret with the mouse")
	for kind in ["cannon", "mgnest"]:
		await fresh()
		var u := spawn(String(kind), "red", at(0, 0), "auto", 0.0) as B3Vehicle
		var foe := spawn("knight", "blue", at(14, 10), "peaceful")
		foe.hp = 9999.0
		foe.max_hp = 9999.0
		await sim(0.5)
		b.set_fighting(true)
		B3Player.start(u)
		var c := B3Player.me
		c.fp = false
		c.aim = foe.position
		var hp0 := foe.hp
		await sim(2.0)
		var want := atan2(foe.position.x - u.position.x, foe.position.z - u.position.z)
		var off := absf(angle_difference(u.facing + (u.turret_yaw if kind != "cannon" else 0.0), want))
		check(off < 0.3, "%s: overhead, it turns to the mouse (%.2f rad off)" % [kind, off])
		var n0 := proj_count("cannonball")
		c.fire = true
		await sim(2.5)
		c.fire = false
		check(proj_count("cannonball") > n0 or foe.hp < hp0 or u.cd > 0.0, "%s: click fires" % kind)
		# first person: it follows the crosshair
		c.fp = true
		c.look_yaw = -1.2
		c.look_pitch = 0.0
		c.aim = u.position + Vector3(sin(-1.2), 0.0, cos(-1.2)) * 20.0 + Vector3(0, 1, 0)
		await sim(3.0)
		off = absf(angle_difference(u.facing + (u.turret_yaw if kind != "cannon" else 0.0), -1.2))
		check(off < 0.3, "%s: first person, it follows the mouse look (%.2f rad off)" % [kind, off])
		B3Player.stop()


func _fly_heli() -> void:
	print("flying the helicopter")
	await fresh()
	var h := spawn("heli", "red", at(0, 0), "auto", 0.0) as B3Aircraft
	var foe := spawn("knight", "blue", at(16, 0), "peaceful")
	foe.hp = 9999.0
	foe.max_hp = 9999.0
	await sim(2.5)
	b.set_fighting(true)
	B3Player.start(h)
	var c := B3Player.me
	c.fp = false
	c.aim = h.position + Vector3(0, 0, 12)
	var p0 := h.position
	c.move = Vector3(0, 0, 1)
	await sim(2.0)
	c.move = Vector3.ZERO
	check(h.position.z - p0.z > 4.0, "overhead: WASD flies it (%.1f m)" % (h.position.z - p0.z))
	var y0 := gh(h)
	c.lift = 1.0
	await sim(1.5)
	var y1 := gh(h)
	c.lift = -1.0
	await sim(1.5)
	var y2 := gh(h)
	c.lift = 0.0
	check(y1 > y0 + 2.0 and y2 < y1 - 2.0, "Space climbs and Shift descends (%.1f → %.1f → %.1f m)" % [y0, y1, y2])
	c.aim = foe.position
	await sim(1.5)
	var want := atan2(foe.position.x - h.position.x, foe.position.z - h.position.z)
	check(absf(angle_difference(h.facing, want)) < 0.3, "the nose follows the mouse")
	var hp0 := foe.hp
	c.fire = true
	await sim(2.0)
	c.fire = false
	check(foe.hp < hp0, "click fires the machine gun (%.0f damage)" % (hp0 - foe.hp))
	var r0 := proj_count("rocket")
	c.fire2 = true
	await sim(0.3)
	c.fire2 = false
	check(proj_count("rocket") >= r0 + 2, "right-click fires a pair of rockets")
	await sim(2.0)
	# first person: mouse turns it, W/S forward/back, A/D sidestep
	c.fp = true
	c.look_yaw = 1.0
	c.look_pitch = -0.2
	await sim(1.5)
	check(absf(angle_difference(h.facing, 1.0)) < 0.15, "first person: the mouse turns it (%.2f)" % h.facing)
	p0 = h.position
	c.steer = Vector2(0, 1)
	await sim(1.5)
	var fwd := Vector3(sin(1.0), 0, cos(1.0))
	check((h.position - p0).dot(fwd) > 3.0, "W flies forward (%.1f m)" % (h.position - p0).dot(fwd))
	p0 = h.position
	c.steer = Vector2(1, 0)
	await sim(1.5)
	var right := Vector3(-fwd.z, 0, fwd.x)
	check((h.position - p0).dot(right) > 3.0, "D sidesteps right (%.1f m)" % (h.position - p0).dot(right))
	c.steer = Vector2.ZERO
	check(absf(h.bank) > 0.03 or absf(h.pitch) > 0.03, "it leans the way it flies")
	B3Player.stop()


func _fly_plane() -> void:
	print("flying the plane")
	await fresh()
	var pl := spawn("plane", "red", at(0, -26), "auto", 0.0) as B3Aircraft
	await sim(1.0)
	b.set_fighting(true)
	B3Player.start(pl)
	var c := B3Player.me
	# first person: it steers itself to where you look, banking into the turn
	c.fp = true
	c.look_yaw = pl.facing + 1.3
	c.look_pitch = 0.0
	var max_bank := 0.0
	for i in 20:
		await sim(0.1)
		max_bank = maxf(max_bank, absf(pl.bank))
	check(absf(angle_difference(pl.facing, c.look_yaw)) < 0.25, "first person: it turns to where you look (%.2f rad off)" % absf(angle_difference(pl.facing, c.look_yaw)))
	check(max_bank > 0.4, "and banks into the turn (%.2f rad)" % max_bank)
	var y0 := pl.position.y
	c.look_pitch = 0.35
	await sim(1.5)
	check(pl.position.y > y0 + 3.0, "looking up climbs (%.1f m)" % (pl.position.y - y0))
	c.look_pitch = 0.0
	var s0 := pl.throttle
	c.steer = Vector2(0, 1)
	await sim(1.0)
	c.steer = Vector2.ZERO
	check(pl.throttle > s0 + 0.3, "W opens the throttle (%.2f → %.2f)" % [s0, pl.throttle])
	c.aim = pl.position + pl._nose() * 30.0
	c.fire = true
	await sim(0.5)
	c.fire = false
	check(pl.burst > 0 or pl.cd > 0.2, "click fires the guns")
	var n0 := proj_count("bomb")
	c.fire2 = true
	await sim(0.1)
	c.fire2 = false
	check(proj_count("bomb") > n0, "right-click drops a bomb")
	# overhead: it flies to the mouse and Space/Shift change the height
	c.fp = false
	var goal := at(pl.position.x - 40.0, pl.position.z + 40.0)
	c.aim = goal
	var d0 := Vector2(pl.position.x - goal.x, pl.position.z - goal.z).length()
	var best := d0
	for i in 60:
		await sim(0.1)
		best = minf(best, Vector2(pl.position.x - goal.x, pl.position.z - goal.z).length())
	check(best < 10.0, "overhead: it flies to the mouse (%.0f m → %.0f m)" % [d0, best])
	var a0 := gh(pl)
	c.lift = 1.0
	await sim(2.0)
	c.lift = 0.0
	check(gh(pl) > a0 + 4.0, "Space climbs (%.1f → %.1f m)" % [a0, gh(pl)])
	B3Player.stop()
	await sim(1.0)
	check(alive(pl) and gh(pl) > 3.0, "handed back to the computer, it keeps flying")


# ------------------------------------------------------------------ bounds
func _bounds() -> void:
	print("aircraft stay inside the map")
	await fresh()
	var lim := B3Defs.BOUNDS
	var pl := spawn("plane", "red", at(lim - 20, 0), "auto", PI * 0.5)
	var pl2 := spawn("plane", "blue", at(0, -(lim - 15)), "auto", PI)
	var h := spawn("heli", "green", at(-(lim - 12), 5), "auto", -PI * 0.5)
	await sim(0.5)
	b.set_fighting(true)
	var far := 0.0
	for i in 60:
		await sim(0.25)
		for u in [pl, pl2]:
			if alive(u):
				far = maxf(far, maxf(absf(u.position.x), absf(u.position.z)))
	check(alive(pl) and alive(pl2) and far < lim, "planes heading for the edge turn back (%.1f of %.0f m)" % [far, lim])
	# a person flying straight at the edge gets turned round too
	B3Player.start(pl)
	var c := B3Player.me
	c.fp = true
	c.look_yaw = PI * 0.5
	c.look_pitch = 0.0
	far = 0.0
	for i in 40:
		await sim(0.25)
		c.look_yaw = PI * 0.5
		far = maxf(far, absf(pl.position.x))
	check(alive(pl) and far < lim, "even when you keep steering out (%.1f m)" % far)
	B3Player.stop()
	B3Player.start(h)
	c = B3Player.me
	c.fp = false
	c.move = Vector3(-1, 0, 0)
	far = 0.0
	for i in 32:
		await sim(0.25)
		far = maxf(far, absf(h.position.x))
	c.move = Vector3.ZERO
	check(alive(h) and far < lim, "a helicopter stops before the edge (%.1f m)" % far)
	B3Player.stop()


# --------------------------------------------------------------- shot down
func _shot_down() -> void:
	print("shot down")
	for kind in ["heli", "plane"]:
		await fresh()
		var a := spawn(String(kind), "red", at(0, 0)) as B3Aircraft
		var shooter := spawn("rocketeer", "blue", at(20, 0), "peaceful")
		await sim(2.0)
		b.set_fighting(true)
		var c0: int = b.chunks.size()
		var k0: int = shooter.kills
		a.hurt(99999.0, Vector3.UP, 1.0, shooter, "blast")
		check(a.falling and a.down and not a.dead, "%s: shot down, it falls instead of vanishing" % kind)
		var y0 := a.position.y
		var t := 0.0
		while alive(a) and t < 15.0:
			await sim(0.25)
			t += 0.25
		check(not alive(a) and b.kos >= 1, "%s: it crashes and is knocked out (%.1f s)" % [kind, t])
		check(b.chunks.size() - c0 >= 3, "%s: and blows apart into pieces (%d)" % [kind, b.chunks.size() - c0])
		check(shooter.kills > k0, "%s: the shooter gets the knock-out" % kind)
		check(y0 > 4.0, "%s: it was up in the air (%.1f m)" % [kind, y0])
	# a real fight: rocketeers bring down a helicopter
	await fresh()
	var heli := spawn("heli", "red", at(0, 0), "peaceful")
	for i in 6:
		spawn("rocketeer", "blue", at(12, -6 + i * 2.5))
	await sim(1.5)
	b.set_fighting(true)
	var t2 := 0.0
	while alive(heli) and t2 < 60.0:
		await sim(1.0)
		t2 += 1.0
	check(not alive(heli), "rocketeers shoot down a helicopter (%ds)" % int(t2))
	# finishing off an enemy jeep right next to you: its blast wrecks you in the
	# middle of your own shot (this used to be a script error)
	for kind in ["jeep", "tank"]:
		await fresh()
		var me := spawn(String(kind), "red", at(0, 0), "auto", 0.0)
		var foe := spawn("jeep", "blue", at(0, 4), "peaceful", 0.0)
		await sim(0.5)
		me.hp = 1.0
		foe.hp = 1.0
		b.set_fighting(true)
		B3Player.start(me)
		var c := B3Player.me
		c.fp = false
		c.aim = foe.global_position + Vector3(0, 0.8, 0)
		c.fire = true
		c.fire2 = true
		await sim(2.0)
		c.fire = false
		c.fire2 = false
		check(not alive(me) and not alive(foe), "%s: blowing up a jeep right next to you wrecks you too, without a hitch" % kind)
		B3Player.stop()


# ------------------------------------------------------------------- seats
func _eyes() -> void:
	print("first-person seats")
	await fresh()
	var i := 0
	var us: Array[B3Unit] = []
	for k in B3Defs.UNIT_ORDER.vehicles:
		us.append(spawn(String(k), "red", at(-24 + i * 8.0, 0), "auto", 0.0))
		i += 1
	await sim(1.0)
	for u in us:
		B3Player.start(u)
		var c := B3Player.me
		c.fp = true
		c.look_yaw = u.facing
		c.look_pitch = 0.0
		await get_tree().process_frame
		var xf: Transform3D = u.eye_xform(c)
		var rel := xf.origin - u.position
		var vr := u.rig as B3VRig
		var looks := -xf.basis.z
		var ok := vr != null and vr.eye != null and rel.length() < 4.0 and rel.y > 0.9 and rel.y < 3.0
		check(ok and looks.dot(u.forward()) > 0.9, "%s: the camera sits in the seat (%.1f m up) looking ahead" % [u.kind, rel.y])
		var kept := 0
		for n in u.find_children("*", "VisualInstance3D", true, false):
			if b.cam._keep(n, u):
				kept += 1
		check(kept >= 3, "%s: some of it stays in view in first person (%d meshes)" % [u.kind, kept])
		B3Player.stop()


# ----------------------------------------------------------------- network
func _net() -> void:
	print("network puppets")
	await fresh()
	var i := 0
	var pairs := []
	for k in B3Defs.UNIT_ORDER.vehicles:
		var a := spawn(String(k), "red", at(-24 + i * 8.0, -10), "auto", 0.0)
		var p := spawn(String(k), "red", at(-24 + i * 8.0, 10), "auto", 0.0)
		pairs.append([a, p])
		i += 1
	spawn("knight", "blue", at(0, -24), "peaceful")
	await sim(0.5)
	b.set_fighting(true)
	await sim(2.5)
	for pr in pairs:
		var a: B3Vehicle = pr[0]
		var p: B3Vehicle = pr[1]
		p.set_physics_process(false)
		var s: Array = a.net_state()
		p.apply_net_state(s)
		var s2: Array = p.net_state()
		var same := s.size() == s2.size()
		if same:
			for j in s.size():
				if absf(float(s[j]) - float(s2[j])) > 0.0001:
					same = false
		var va := a.rig as B3VRig
		var vp := p.rig as B3VRig
		var posed := vp.rotation.is_equal_approx(va.rotation)
		if va.turret:
			posed = posed and absf(vp.turret.rotation.y - va.turret.rotation.y) < 0.0001
		if va.gun:
			posed = posed and absf(vp.gun.rotation.x - va.gun.rotation.x) < 0.0001
		check(same and posed and p.puppet, "%s: net_state → apply_net_state round-trips (%d numbers)" % [a.kind, s.size()])
	# puppets animate from the state alone (no physics)
	var hp := pairs[5] as Array
	var hpup: B3Vehicle = hp[1]
	var rv := (hpup.rig as B3VRig).rotors[0] as Array
	var rotor_node: Node3D = rv[0]
	var r0 := rotor_node.rotation.y
	for j in 10:
		await get_tree().process_frame
	check(absf(angle_difference(r0, rotor_node.rotation.y)) > 0.01, "a puppet helicopter's rotor spins with no physics running")
	var car_pair := pairs[4] as Array
	var cpup: B3Vehicle = car_pair[1]
	cpup.apply_net_state([0.0, 0.0, 0.3, 8.0, 0.0, 0.0, 0])
	var w: Node3D = (cpup.rig as B3VRig).wheels[0]
	var w0 := w.rotation.x
	for j in 10:
		await get_tree().process_frame
	check(absf(angle_difference(w0, w.rotation.x)) > 0.01 and absf((cpup.rig as B3VRig).steer_angle - 0.3) < 0.001, "a puppet car's wheels roll and steer")
	# a destroyed puppet blows apart with physics off
	var c0: int = b.chunks.size()
	var tank_pup: B3Vehicle = (pairs[0] as Array)[1]
	tank_pup.freeze = false
	tank_pup._wreck(Vector3.ZERO, null)
	await get_tree().process_frame
	check(b.chunks.size() > c0 and (not is_instance_valid(tank_pup) or tank_pup.dead), "_wreck() on a puppet breaks it into pieces (%d)" % (b.chunks.size() - c0))


# --------------------------------------------------------------- scenarios
func _scenarios() -> void:
	print("scenarios")
	for sc in ["airshow", "roadtrip"]:
		await fresh("", sc)
		var n0: int = b.units.size()
		await sim(10.0)
		var hurt := 0
		for u: B3Unit in b.units:
			if u.hp < u.max_hp or u.down:
				hurt += 1
		check(n0 > 0 and b.fighting and (b.kos > 0 or hurt > 0), "the %s scenario starts a fight (%d units, %d hurt, %d KO'd after 10s)" % [sc, n0, hurt, b.kos])
	await fresh("", "hangar")
	await sim(2.0)
	var parked := 0
	for u: B3Unit in b.units:
		if u is B3Aircraft and (u as B3Aircraft).parked and gh(u) < 0.3:
			parked += 1
	check(b.units.size() == 7 and parked == 2, "the hangar shows all 7 vehicles, the aircraft parked (%d, %d)" % [b.units.size(), parked])
	b.set_fighting(true)
	await sim(3.0)
	var flying := 0
	for u: B3Unit in b.units:
		if u is B3Aircraft and not (u as B3Aircraft).parked and gh(u) > 2.0:
			flying += 1
	check(flying == 2, "and they take off when the fight starts (%d)" % flying)


func _performance() -> void:
	print("performance")
	await fresh("", "airshow")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var n: int = b.units.size()
	var air := 0
	for u: B3Unit in b.units:
		if u is B3Aircraft:
			air += 1
	await sim(1.0)
	var t0 := Time.get_ticks_usec()
	var s0: float = b.time
	await sim(5.0)
	var real := (Time.get_ticks_usec() - t0) / 1000000.0
	var ratio: float = (b.time - s0) / maxf(real, 0.001)
	print("        %d units (%d aircraft): %.2fx real time (%.1fs of battle in %.1fs)" % [n, air, ratio, b.time - s0, real])
	check(air == 10 and n >= 70 and ratio > 0.8, "6 planes, 4 helicopters and 60 fighters run at full speed (%.2fx)" % ratio)
	Engine.time_scale = SPEED

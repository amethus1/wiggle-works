class_name FighterAI
## How a fighter thinks and fights, for Fighter: who to go after (medics look
## after hurt teammates first), wandering about, aiming, attacking and a melee
## blow landing, a pterodactyl carrying someone off, and being played by a
## person. (Where to stand and when to attack is Fighter._act: it runs for
## everyone every physics step.) Everything here takes the fighter; all the
## state stays in Fighter.


static func think(f: Fighter) -> void:
	# medics look after hurt teammates first
	if f.def.get("heals", false):
		var hurt_ally = nearest(f, func(o): return o != f and o is Fighter and o.alive() and o.team == f.team and o.hp < o.max_hp * 0.75, 700.0)
		if hurt_ally:
			f.set_meta("heal_target", hurt_ally)
		else:
			f.remove_meta("heal_target")
	if f.pers == "peaceful" and f.angry_t <= 0.0:
		f.target = null
		return
	if f.angry_t > 0.0:
		# angry: after whoever hurt us (or anyone else close by who's in the way)
		if f.target == null or not is_instance_valid(f.target) or not f.target.alive():
			f.target = nearest(f, func(o): return f.enemy_of(o), 600.0)
		return
	var guard: bool = f.pers == "defend" and not f.world.brave      # 📣 CHARGE!: guards leave their post too
	if f.target == null or not is_instance_valid(f.target) or not f.target.alive() or (guard and f.target.center().distance_to(f.center()) > 1500.0):
		# defenders watch as far as their weapon reaches (a sniper sees a long way)
		var watch := 1400.0 if not guard else maxf(900.0, f._reach() * 1.05)
		f.target = nearest(f, func(o): return f.enemy_of(o), watch)
		# nobody close by: everyone except guards goes looking for a fight, so a
		# battle never stalls with two armies waiting at opposite ends
		if f.target == null and not guard:
			f.target = nearest(f, func(o): return f.enemy_of(o), INF)
	elif f.pers != "defend" and f.target.center().distance_to(f.center()) > 600.0:
		# chasing someone far away: switch if somebody closer shows up
		var closer = nearest(f, func(o): return f.enemy_of(o), f.target.center().distance_to(f.center()) * 0.6)
		if closer:
			f.target = closer


static func nearest(f: Fighter, pred: Callable, max_d: float):
	var best = null
	var bd := max_d
	for o in f.world.fighters():
		if pred.call(o):
			var d: float = o.center().distance_to(f.center())
			if d < bd:
				bd = d
				best = o
	return best


## A pterodactyl grabs `o` in its claws and flies off up into the sky with it,
## then lets go: a long (soft) way down, and they get back up.
static func snatch(f: Fighter, o: Fighter) -> void:
	o.ragdoll(Vector2(0, -120), true)
	if o.state == "stand":
		return
	f.carrying = o
	f.carry_t = 1.8
	f.snatch_cd = 7.0
	f.cool = f._rate()
	f.world.fx_event("snatch", {"p": o.center()})


static func carry(f: Fighter, dt: float) -> void:
	var o := f.carrying
	if not is_instance_valid(o) or o.state == "stand" or o.frozen_t > 0.0 or o.is_resting() or not o.held_by.is_empty() or f.carry_t <= 0.0:
		drop_carried(f)
		return
	f.carry_t -= dt
	o.down_t = 0.0
	o.lift_t = 0.2      # (kicking helplessly, and not getting up in mid-air)
	o._soft = true      # a soft landing when we let go
	var claws := f.body.global_position + Vector2(f.facing * 6.0, f.half_size().y + 16.0 * f.size)
	var pull: Vector2 = ((claws - o.center()) * 10.0 + f.body.linear_velocity).limit_length(900.0)
	var g: Vector2 = f.world.gravity_vec() * dt
	for b in o.all_bodies():
		b.linear_velocity = b.linear_velocity.lerp(pull, minf(1.0, dt * 14.0)) - g


static func drop_carried(f: Fighter) -> void:
	f.carrying = null
	f.carry_t = 0.0


static func wander(f: Fighter, dt: float) -> void:
	f.wander_t -= dt
	if f.wander_t <= 0.0:
		f.wander_t = randf_range(1.0, 3.0)
		f.wander_dir = 0.0 if randf() < 0.4 else (-1.0 if randf() < 0.5 else 1.0)
		if f.pers == "defend" and f.wander_dir != 0.0:
			f.facing = f.wander_dir   # a guard looks about
	if f.pers == "defend":
		# Guards stand at their post. (They used to wander about until they were
		# 60 px from it: a sniper on a tower walked right off the top.)
		var dx := f.home.x - f.center().x
		f.move = clampf(dx / 60.0, -0.8, 0.8) if absf(dx) > 12.0 else 0.0
		return
	f.move = f.wander_dir * 0.5


static func aim_at(f: Fighter, tc: Vector2, wt: String) -> float:
	var from := f.center() + Vector2(0, -20.0 * f.size)
	var d := tc - from
	if wt == "bow" or wt == "throw":
		var v := 900.0 if wt == "bow" else 620.0
		var g := 980.0
		var x := absf(d.x)
		var y := -d.y
		var v2 := v * v
		var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
		if disc >= 0.0 and x > 1.0:
			var ang := atan((v2 - sqrt(disc)) / (g * x))
			return (-ang if d.x >= 0.0 else PI + ang)
		return (-PI * 0.25 if d.x >= 0.0 else -PI * 0.75)
	return d.angle()


static func clear_shot(f: Fighter, tc: Vector2) -> bool:
	var from := f.center() + Vector2(0, -20.0 * f.size)
	var q := PhysicsRayQueryParameters2D.create(from, tc, Toy.LAYER_GROUND)
	return f.world.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


static func attack(f: Fighter, tc: Vector2, wt: String) -> void:
	var wd := f._wdef()
	match wt:
		"melee", "beast":
			f.cool = f._rate()
			f.swing = f._swing_time()
			f.swing_hit = false
			if f.beast and String(f.def.get("voice", "")) != "" and randf() < 0.4:
				f.world.fx_event("voice", {"p": f.center(), "v": String(f.def.voice)})
			var glow: bool = wd.get("glow", false)
			var sw := {"p": f.center(), "fists": wd.get("fists", false), "beast": f.beast, "f": f.facing, "r": f._reach() * (1.0 if f.beast else 0.9), "glow": glow}
			if glow and f.weapon_toy and is_instance_valid(f.weapon_toy):
				var lc: Color = f.weapon_toy.shown_color()
				sw.c = Color(lc.r * 0.9, lc.g * 0.9, lc.b * 1.1, 0.45)   # a laser sword's glowing swoosh (drawn glowing: see Effects)
			f.world.fx_event("swing", sw)
			# the blow lands halfway through the swing (counted in physics steps, so ⏸ pause stops it)
			f.hit_t = f._swing_time() * 0.5
			f._hit_wd = wd
		"gun":
			if int(wd.get("burst", 0)) > 0:
				if f.reload_t > 0.0:
					f.cool = f.reload_t   # still reloading: try again when it's done
					return
				f.ammo -= 1
				if f.ammo <= 0:
					f.ammo = int(wd.burst)
					f.reload_t = float(wd.get("reload", 1.5))
					f.world.fx_event("reload", {"p": f.center()})
			f.cool = f._rate() * randf_range(0.9, 1.2)
			var muzzle := _muzzle(f)
			for i in int(wd.get("pellets", 1)):
				var ang := f.aim + randf_range(-1.0, 1.0) * float(wd.get("spread", 0.03))
				f.world.shoot(f, muzzle, ang, float(wd.get("range", 800.0)), float(wd.get("dmg", 15.0)), float(wd.get("knock", 120.0)), bool(wd.get("laser", false)))
			f.world.fx_event("shot", {"p": muzzle, "a": f.aim, "s": String(wd.get("sound", "gun_pistol")), "laser": wd.get("laser", false)})
		"launcher":
			f.cool = f._rate()
			f.world.launch(f, "rocket", _muzzle(f), f.aim + randf_range(-0.04, 0.04), 950.0)
			f.world.fx_event("shot", {"p": _muzzle(f), "a": f.aim, "s": "bazooka"})
		"bow":
			f.cool = f._rate()
			f.world.launch(f, "arrow", _muzzle(f), f.aim + randf_range(-0.03, 0.03), 900.0)
			f.world.fx_event("bow", {"p": _muzzle(f)})
		"throw":
			f.cool = f._rate()
			f.world.launch(f, "grenade", f._hand_world(), f.aim + randf_range(-0.05, 0.05), 620.0)
			f.world.fx_event("pin", {"p": f.center()})
		"flame":
			f.cool = f._rate()
			f.world.flame(f, _muzzle(f), f.aim, float(wd.get("range", 220.0)), float(wd.get("dmg", 40.0)) * f._rate())


static func _muzzle(f: Fighter) -> Vector2:
	var hand := f._hand_world()
	var len := 26.0
	if f.weapon_toy and is_instance_valid(f.weapon_toy):
		len = f.weapon_toy.w * 0.5 * f.weapon_toy.size_scale
	return hand + Vector2.from_angle(f.aim) * len


static func melee_hit(f: Fighter, wd: Dictionary) -> void:
	if f.state != "stand" or f.puppet:
		return
	var reach := float(wd.get("reach", 40.0)) * (f.size if not f.beast else 1.0)
	# A beast decides to attack counting its own body (see Fighter._act), so it hits
	# from there too. Otherwise big or resized beasts swung at thin air.
	var body_x := f.radius() * 0.6 if f.beast else 0.0
	var c := f.center()
	var front := c + Vector2(f.facing * (reach * 0.6 + body_x), -10.0 * f.size)
	var kind := String(f.def.get("attack", "bite")) if f.beast else "melee"
	var hit_any := false
	var hit_ko := false
	var hit_player := false
	for o in f.world.fighters():
		if not f.enemy_of(o) and not (f.team == "wild" and o.team == "wild" and o != f and o.type != f.type):
			continue
		var oc: Vector2 = o.center()
		var d := oc - c
		var in_front: bool = signf(d.x) == f.facing or absf(d.x) < o.radius()
		var area: bool = absf(d.x) < reach + body_x + o.radius() * 0.8 and absf(d.y) < reach * 0.7 + o.radius()
		if kind == "stomp":
			area = d.length() < reach + body_x + o.radius() * 0.5
			in_front = true
		elif kind == "tail":
			area = absf(d.x) < reach + body_x + o.radius() * 0.8 and absf(d.y) < reach * 0.6 + o.radius()
			in_front = true
		if area and in_front:
			var knock_dir := Vector2(signf(d.x) if d.x != 0.0 else f.facing, -0.55).normalized()
			o.hurt(float(wd.get("dmg", 10.0)), knock_dir * float(wd.get("knock", 300.0)), f)
			hit_any = true
			if not o.alive():
				hit_ko = true
			if o.player_id >= 0:
				hit_player = true
	# hit toys and Wigglies too
	for t2 in f.world.all_things():
		if t2 is Toy and not t2.extra.has("held_by") and not t2.freeze and t2.global_position.distance_to(front) < reach * 0.8:
			t2.linear_velocity += Vector2(f.facing, -0.4).normalized() * float(wd.get("knock", 300.0)) * clampf(2.0 / t2.mass, 0.1, 1.5)
			if t2.def.has("breaks"):
				ToyLogic.impact(f.world, t2, null, 9999.0, t2.global_position)
			elif t2.id == "barrel":
				ToyLogic.trigger(f.world, t2)
		elif t2 is Wiggly and t2.com.distance_to(front) < reach:
			t2.add_velocity(Vector2(f.facing, -0.6).normalized() * float(wd.get("knock", 300.0)))
	if kind == "stomp":
		f.world.fx_event("stomp", {"p": c + Vector2(0, f.half_size().y), "r": reach})
	elif kind == "charge" and hit_any:
		f.charge_t = 0.0
	if hit_any:
		# (a heavy blow, or a knock-out: the screen jolts, and if you're in it, the game stops for a blink)
		f.world.fx_event("hit", {"p": front, "s": String(wd.get("sound", "punch")), "beast": f.beast, "f": f.facing,
			"big": hit_ko or float(wd.get("dmg", 10.0)) >= 38.0, "ko": hit_ko, "pl": hit_player or f.player_id >= 0})


static func player(f: Fighter, dt: float) -> void:
	f.move = f.move_input
	f.aim = (f.aim_point - (f.center() + Vector2(0, -20.0 * f.size))).angle()
	if absf(f.aim_point.x - f.center().x) > 6.0:
		f.facing = signf(f.aim_point.x - f.center().x)
	if f.want_attack and f.cool <= 0.0:
		var wt := f._wtype()
		if wt == "bow" or wt == "throw":
			f.aim = aim_at(f, f.aim_point, wt)
		attack(f, f.aim_point, wt)
	f.mood = "angry" if f.want_attack else "calm"

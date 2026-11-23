class_name WorldMagic
## Magic spells, for World: parties, wind, rain, snow, wobbles, Float Away,
## raining balls, airstrikes, artillery and meteors, healing and rainbows.
## Everything here takes the world; all the state stays in World.


static func cast(world: World, id: String) -> void:
	match id:
		"party":
			world.magic.party = 8.0
			for w in world.wigglies():
				w.party_t = 8.0
		"ball_rain":
			world._ball_rain = 26
		"wind":
			world.wind_dir = -1.0 if randf() < 0.5 else 1.0
			world.magic.wind = 5.0
		"rain":
			world.magic.rain = 10.0
		"snow":
			world.magic.snow = 12.0
		"wobble":
			world.magic.wobble = 4.0
		"float":
			world.magic["float"] = 6.0
			world.set_gravity(world.gravity_id)
		"airstrike":
			var y := world.view_rect.position.y - 120.0
			var dir := 1.0 if randf() < 0.5 else -1.0
			var x0 := world.view_rect.position.x if dir > 0.0 else world.view_rect.end.x
			world.fx_event("plane", {"y": y - 60.0, "dir": dir, "x0": x0, "w": world.view_rect.size.x})
			for i in 9:
				world._strikes.append({"t": 0.8 + i * 0.22, "p": Vector2(x0 + dir * world.view_rect.size.x * (0.1 + i * 0.1), y), "kind": "shell", "v": Vector2(dir * 300.0, 200.0)})
		"artillery":
			world.fx_event("alarm", {})
			for i in 10:
				world._strikes.append({"t": 1.2 + i * 0.35 + randf() * 0.2, "p": Vector2(randf_range(world.view_rect.position.x + 80, world.view_rect.end.x - 80), world.view_rect.position.y - 150.0), "kind": "shell", "v": Vector2(randf_range(-80, 80), 600.0), "whistle": true})
		"meteors":
			for i in 12:
				world._strikes.append({"t": 0.3 + i * 0.3 + randf() * 0.2, "p": Vector2(randf_range(world.view_rect.position.x, world.view_rect.end.x), world.view_rect.position.y - 150.0), "kind": "meteor", "v": Vector2(randf_range(150, 350), 500.0)})
		"heal_all":
			for f in world.fighters():
				f.revive()
		"rainbow":
			var i := 0
			var sorted := world.toys().duplicate()
			sorted.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
			for t in sorted:
				if t.parent_uid == 0 or true:
					t.paint = Color.from_hsv(fmod(float(i) * 0.09, 1.0), 0.65, 1.0)
					i += 1
			for w in world.wigglies():
				w.paint = Color.from_hsv(randf(), 0.55, 1.0)
	world.fx_event("magic", {"id": id, "dir": world.wind_dir})


static func step(world: World, dt: float) -> void:
	for k in world.magic.keys():
		world.magic[k] -= dt
		if world.magic[k] <= 0.0:
			world.magic.erase(k)
			if k == "float":
				world.set_gravity(world.gravity_id)
			world.fx_event("magic_end", {"id": k})
	if world.magic.has("wind"):
		for t in world.all_things():
			if t is Toy and not t.freeze:
				t.linear_velocity.x += world.wind_dir * 900.0 * dt * clampf(2.0 / t.mass, 0.1, 1.0)
			elif t is Wiggly and t.frozen_t <= 0.0:
				t.add_velocity(Vector2(world.wind_dir * 700.0 * dt * (2.0 if t.kind == "puffy" else 1.0), 0))
			elif t is Fighter:
				t.blow(Vector2(world.wind_dir * 240.0, 0), dt)   # armies lean into it; chickens tumble away
	if world.magic.has("wobble"):
		for t in world.all_things():
			if t is Fighter:
				# now and then the ground bucks under someone's feet
				if randf() < 0.012:
					t.shove(Vector2(randf_range(-160, 160), randf_range(-260, -120)))
			elif randf() < 0.08:
				var kick := Vector2(randf_range(-260, 260), randf_range(-420, -120))
				if t is Toy and not t.freeze:
					t.linear_velocity += kick * clampf(3.0 / t.mass, 0.2, 1.0)
				elif t is Wiggly:
					t.add_velocity(kick)
	if world.magic.has("rain"):
		# everyone gets wet: burning fighters fizzle out, and the napalm fires die down
		for t in world.all_things():
			if t is Fighter or t is Toy:
				t.wet = 1.0
		for z in world.fires:
			z.t -= dt * 2.5
	if world.magic.has("float"):
		for w in world.wigglies():
			w.add_velocity(Vector2(0, -30.0 * dt))
	if world._ball_rain > 0:
		world._ball_rain_t -= dt
		if world._ball_rain_t <= 0.0:
			world._ball_rain_t = 0.11
			world._ball_rain -= 1
			var ids := ["beach_ball", "bouncy_ball", "soccer_ball", "marble", "bouncy_ball"]
			var b := world.spawn_toy(ids[randi() % ids.size()], Vector2(randf_range(world.view_rect.position.x + 60, world.view_rect.end.x - 60), world.view_rect.position.y - 60))
			if b:
				b.linear_velocity = Vector2(randf_range(-80, 80), 200)


static func step_strikes(world: World, dt: float) -> void:
	for st in world._strikes:
		st.t -= dt
		if st.t <= 0.0:
			var b := world.spawn_toy(String(st.kind), st.p, 0.0, 1.0, Combat.PROJ[String(st.kind)])
			if b:
				b.extra.proj = "bomb"
				b.extra.life = 8.0
				b.linear_velocity = st.v
				if st.kind == "meteor":
					b.extra.meteor = true
				if st.get("whistle", false):
					world.fx_event("whistle", {"p": st.p})
	world._strikes = world._strikes.filter(func(st): return st.t > 0.0)

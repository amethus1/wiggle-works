class_name ToyLogic
## What each toy does: power sources, machines, booms and rides.

const SOURCES := ["battery", "switch", "button", "timer"]
const FUSED := ["firework", "paint_bomb", "bubble_bomb", "glue_bomb", "freeze_bomb", "boom_barrel", "mega_boom",
	"grenade", "dynamite", "cluster", "napalm", "acid_bomb", "nuke", "barrel"]
const FUSE_TIME := {"firework": 1.0, "paint_bomb": 0.7, "bubble_bomb": 0.7, "glue_bomb": 0.7, "freeze_bomb": 0.7, "boom_barrel": 0.9, "mega_boom": 1.6,
	"grenade": 2.0, "dynamite": 3.0, "cluster": 1.2, "napalm": 1.0, "acid_bomb": 1.0, "nuke": 4.0, "barrel": 0.8}
const GLOWS := ["lamp", "firework", "saucer"]


static func is_source(t: Toy) -> bool:
	return t.id in SOURCES


## Is this source putting power on its wires right now?
static func emits(t: Toy) -> bool:
	match t.id:
		"battery":
			return true
		"switch":
			return t.on
		"button":
			return bool(t.extra.get("pressed", false))
		"timer":
			return bool(t.extra.get("blink", false))
	return false


static func on_spawn(world: World, t: Toy) -> void:
	match t.id:
		"saucer":
			t.gravity_scale = 0.0
			t.extra.hover_y = t.global_position.y
		"balloon", "envelope":
			t.linear_damp = 2.5   # drifts up gently instead of rocketing off
		"timer":
			t.extra.tt = 0.0
	update_light(world, t)


static func on_remove(_world: World, _t: Toy) -> void:
	pass


## Use (F / the Use button).
static func use(world: World, t: Toy) -> void:
	match t.id:
		"switch", "lamp", "fan", "magnet", "motor", "rocket", "propeller", "conveyor", "bubbler", "go_kart", "monster_truck", "saucer":
			t.on = not t.on
			world.fx_event("click", {"p": t.global_position, "on": t.on})
			update_light(world, t)
			if t.on and t.id in ["go_kart", "monster_truck"]:
				Settings.award("rider")
		"bell":
			_ding(world, t)
		"cannon":
			_fire_cannon(world, t)
		"confetti":
			if t.cooldown <= 0.0:
				t.cooldown = 0.8
				var dir := Vector2.UP.rotated(t.rotation)
				world.fx_event("confetti", {"p": t.global_position + dir * 20.0, "dir": dir})
				world.push_away(t.global_position + dir * 40.0, 120.0, 260.0, t)
				for w in world.wigglies():
					if w.com.distance_to(t.global_position) < 300.0:
						w.party_t = 3.0
				_count_boom()
		"c4", "landmine":
			trigger(world, t)
		_:
			if t.id in FUSED:
				light_fuse(world, t)


static func light_fuse(world: World, t: Toy) -> void:
	if t.fuse >= 0.0:
		if t.fuse > 0.25 and t.id != "nuke":
			t.fuse = 0.05   # pressing again: go now
		return
	t.fuse = float(FUSE_TIME.get(t.id, 0.8))
	world.fx_event("fuse", {"p": t.global_position, "uid": t.uid})
	if t.id == "nuke":
		world.fx_event("alarm", {"p": t.global_position})


## Sets off a mine, barrel, C4 or other explosive right now.
static func trigger(world: World, t: Toy) -> void:
	if not world.things.has(t.uid) or t.extra.get("gone", false):
		return
	if t.id == "nuke" and t.fuse < 0.0:
		light_fuse(world, t)
		return
	if t.def.has("explode"):
		t.fuse = 0.0
		_go_off(world, t)
	elif t.id in FUSED:
		light_fuse(world, t)
	update_light(world, t)


## Blaze's flame puff, or fire from a firework.
static func heat(world: World, t: Toy) -> void:
	if t.id in ["landmine", "c4"]:
		trigger(world, t)
	elif t.id in FUSED:
		light_fuse(world, t)
	elif t.id == "ice_cube":
		world.fx_event("steam", {"p": t.global_position})
		world.remove(t.uid, false)
	elif t.id == "balloon":
		_pop_balloon(world, t)


static func step(world: World, t: Toy, dt: float) -> void:
	t.cooldown = maxf(0.0, t.cooldown - dt)
	t.zap_power = maxf(0.0, t.zap_power - dt)
	t.electric = maxf(0.0, t.electric - dt)
	t.wet = maxf(0.0, t.wet - dt * 0.1)
	if t.frozen_t > 0.0:
		t.frozen_t -= dt
		if t.frozen_t <= 0.0:
			t.update_freeze()
			world.fx_event("thaw", {"p": t.global_position})
		return
	if t.bubble_t > 0.0:
		t.bubble_t -= dt
		t.linear_velocity = t.linear_velocity.lerp(Vector2(sin(world.vision_time * 1.7 + t.uid) * 40.0, -70.0), dt * 1.5)
		t.angular_velocity *= 0.95
		if t.bubble_t <= 0.0:
			_unbubble(world, t)
	if t.fuse >= 0.0:
		t.fuse -= dt
		if t.id == "nuke" and int((t.fuse + dt) * 2.0) != int(t.fuse * 2.0):
			world.fx_event("tick", {"p": t.global_position})
		if t.fuse < 0.0:
			_go_off(world, t)
			return
	if t.extra.has("proj"):
		_projectile(world, t, dt)
		if not world.things.has(t.uid):
			return
	if t.def.has("lift") and t.bubble_t <= 0.0:
		t.apply_central_force(Vector2(0, -float(t.def.lift) * t.mass))
	if t.id == "envelope":
		t.apply_central_force(Vector2(0, -5200.0))
	var on := t.is_on()
	var dir := Vector2.RIGHT.rotated(t.rotation) * t.facing
	var up := Vector2.UP.rotated(t.rotation)
	match t.id:
		"timer":
			t.extra.tt = float(t.extra.get("tt", 0.0)) + dt
			var blink := fmod(float(t.extra.tt), 2.0) < 1.0
			if blink != bool(t.extra.get("blink", false)):
				t.extra.blink = blink
				t.extra.art = "on" if blink else "off"
				if blink:
					world.fx_event("tick", {"p": t.global_position})
		"button":
			var pressed := false
			for b in t.get_colliding_bodies():
				var bp: Vector2 = b.global_position
				if (bp - t.global_position).dot(up) > 2.0:
					pressed = true
					break
			if pressed != bool(t.extra.get("pressed", false)):
				t.extra.pressed = pressed
				t.extra.art = "down" if pressed else "up"
				world.fx_event("click", {"p": t.global_position, "on": pressed})
		"lamp", "saucer":
			var lit := on
			if bool(t.extra.get("lit", false)) != lit:
				t.extra.lit = lit
				update_light(world, t)
			if t.id == "saucer":
				_hover(world, t, dt)
		"bell":
			if t.powered and not bool(t.extra.get("was", false)):
				_ding(world, t)
			t.extra.was = t.powered
		"fan":
			if on:
				_blow(world, t, dir, dt)
		"magnet":
			if on:
				_magnet(world, t, dt)
		"motor":
			if on:
				t.angular_velocity = move_toward(t.angular_velocity, 9.0 * t.facing, 30.0 * dt)
		"rocket":
			if on:
				t.apply_central_force(dir * 5200.0)
				if randf() < 0.5:
					world.fx_event("thrust", {"p": t.global_position - dir * 30.0 * t.size_scale, "dir": -dir})
		"propeller":
			if on:
				t.apply_central_force(up * 3600.0)
		"conveyor":
			if on:
				for b in t.get_colliding_bodies():
					if b is RigidBody2D and not (b as RigidBody2D).freeze and (b.global_position - t.global_position).dot(up) > 0.0:
						var rb := b as RigidBody2D
						var along := dir.dot(rb.linear_velocity)
						rb.linear_velocity += dir * (230.0 - along) * minf(1.0, dt * 8.0)
		"cannon":
			if t.powered and t.cooldown <= 0.0:
				_fire_cannon(world, t)
		"bubbler":
			if on and t.cooldown <= 0.0:
				t.cooldown = 0.45
				_blow_bubble(world, t, dir)
		"go_kart", "monster_truck":
			_drive(world, t, on, dt)
		"boat":
			for r in world.water:
				if r.has_point(t.global_position + Vector2(0, 30)):
					t.apply_central_force(Vector2(t.facing * 900.0, 0))
					break


static func _count_boom() -> void:
	Settings.count("booms", "boom", 10)


static func _ding(world: World, t: Toy) -> void:
	if t.cooldown > 0.0:
		return
	t.cooldown = 0.25
	t.extra.art = str(randi())
	world.fx_event("ding", {"p": t.global_position})


static func _fire_cannon(world: World, t: Toy) -> void:
	if t.cooldown > 0.0:
		return
	t.cooldown = 0.7
	var dir := Vector2.RIGHT.rotated(t.rotation) * t.facing
	var muzzle := t.global_position + dir * (t.w * 0.5 + 16.0) * t.size_scale
	# keep the number of cannon balls sane
	var mine: Array = world.toys().filter(func(o): return o.extra.get("from_cannon", false))
	if mine.size() > 30:
		world.remove(mine[0].uid, false)
	var ball := world.spawn_toy("bouncy_ball", muzzle)
	if ball:
		ball.extra.from_cannon = true
		ball.paint = Catalog.PAINT[randi() % 8]
		ball.linear_velocity = dir * 1250.0 + t.linear_velocity
		ball.add_collision_exception_with(t)
	if not t.freeze:
		t.linear_velocity -= dir * 120.0
	world.fx_event("cannon", {"p": muzzle, "dir": dir})


static func _blow(world: World, t: Toy, dir: Vector2, dt: float) -> void:
	var c := t.global_position
	var reach := 420.0 * t.size_scale
	for o in world.things.values():
		if o == t:
			continue
		var p: Vector2 = world._pos_of(o)
		var d := p - c
		var dist := d.length()
		if dist > reach or dist < 1.0 or d.normalized().dot(dir) < 0.8:
			continue
		var f := (1.0 - dist / reach) * 1700.0 * dt
		if o is Toy and not o.freeze:
			o.linear_velocity += dir * f * clampf(1.6 / o.mass, 0.08, 1.2)
		elif o is Wiggly and o.frozen_t <= 0.0:
			o.add_velocity(dir * f * (1.6 if o.kind == "puffy" else 0.8))
	if randf() < 0.35:
		world.fx_event("wind", {"p": c + dir * 30.0, "dir": dir})


static func _magnet(world: World, t: Toy, dt: float) -> void:
	var c := t.global_position
	for o in world.things.values():
		if o == t or not (o is Toy) or not o.def.get("metal", false) or o.freeze:
			continue
		var d: Vector2 = c - o.global_position
		var dist := d.length()
		if dist < 20.0 or dist > 380.0:
			continue
		o.linear_velocity += d / dist * 1900.0 * (1.0 - dist / 380.0) * dt
	if randf() < 0.1:
		world.fx_event("magnet", {"p": c})


static func _hover(world: World, t: Toy, dt: float) -> void:
	if t.freeze:
		return
	var target_y := float(t.extra.get("hover_y", t.global_position.y))
	var held := false
	for g in world.grabs.values():
		if g.uid == t.uid:
			held = true
	if held:
		t.extra.hover_y = t.global_position.y
		return
	var err := target_y - t.global_position.y
	t.linear_velocity.y += (err * 6.0 - t.linear_velocity.y * 2.5) * dt
	t.linear_velocity.x *= 1.0 - dt * 0.8
	t.angular_velocity += (-t.rotation * 6.0 - t.angular_velocity * 2.0) * dt
	if t.on:
		# tractor beam: lift things below toward the saucer
		for o in world.things.values():
			if o == t:
				continue
			var p: Vector2 = world._pos_of(o)
			var d := p - t.global_position
			if d.y < 20.0 or d.y > 520.0 or absf(d.x) > 40.0 + d.y * 0.3:
				continue
			if o is Toy and not o.freeze:
				o.linear_velocity = o.linear_velocity.lerp(Vector2(-d.x * 1.5, -260.0), dt * 3.0)
			elif o is Wiggly:
				for jp in o.points:
					jp.linear_velocity = jp.linear_velocity.lerp(Vector2(-d.x * 1.5, -260.0), dt * 3.0)


static func _blow_bubble(world: World, t: Toy, dir: Vector2) -> void:
	var c := t.global_position + dir * 30.0
	world.fx_event("bubble", {"p": c, "dir": dir})
	# The first small thing in front gets caught in a bubble.
	for o in world.things.values():
		if o == t:
			continue
		var p: Vector2 = world._pos_of(o)
		var d := p - c
		if d.length() > 260.0 or d.normalized().dot(dir) < 0.7:
			continue
		if o is Toy and o.mass < 3.0 and o.bubble_t <= 0.0 and not o.freeze and o.parent_uid == 0:
			_bubble(world, o, 6.0)
			return
		if o is Wiggly and o.size < 1.2 and o.bubble_t <= 0.0:
			o.set_bubble(6.0)
			return


static func _bubble(_world: World, t: Toy, sec: float) -> void:
	t.bubble_t = sec
	t.gravity_scale = 0.0


static func _unbubble(world: World, t: Toy) -> void:
	t.bubble_t = 0.0
	t.gravity_scale = 0.0 if t.def.has("lift") or t.id == "saucer" else 1.0
	world.fx_event("pop_bubble", {"p": t.global_position, "r": t.bound_radius() * 1.5})


static func _drive(world: World, t: Toy, on: bool, dt: float) -> void:
	var speed := 26.0 if t.id == "go_kart" else 15.0
	for o in world.things.values():
		if o is Toy and o.parent_uid == t.uid and o.id == "wheel":
			var target := speed * t.facing if on else 0.0
			var accel := 40.0 if on else 12.0
			o.angular_velocity = move_toward(o.angular_velocity, target, accel * dt)
	if on and randf() < 0.12:
		world.fx_event("exhaust", {"p": t.global_position - Vector2.RIGHT.rotated(t.rotation) * t.facing * t.w * 0.55, "dir": -Vector2.RIGHT.rotated(t.rotation) * t.facing})


static func _pop_balloon(world: World, t: Toy) -> void:
	world.fx_event("balloon_pop", {"p": t.global_position, "c": t.shown_color()})
	world.remove(t.uid, false)


static func _projectile(world: World, t: Toy, dt: float) -> void:
	t.extra.life = float(t.extra.get("life", 6.0)) - dt
	if t.extra.life <= 0.0:
		if t.extra.proj in ["rocket", "bomb"]:
			_explode_at(world, t, 140.0, 900.0, 40.0)
		else:
			world.remove(t.uid, false)
		return
	match String(t.extra.proj):
		"rocket":
			var dir := Vector2.from_angle(t.rotation)
			t.linear_velocity = t.linear_velocity.lerp(dir * 950.0, dt * 2.0)
			t.angular_velocity = 0.0
			if randf() < 0.7:
				world.fx_event("thrust", {"p": t.global_position - dir * 16.0, "dir": -dir})
		"arrow":
			if not t.freeze and t.linear_velocity.length() > 60.0:
				t.rotation = t.linear_velocity.angle()
				t.angular_velocity = 0.0
		"bomb":
			if t.linear_velocity.length() > 60.0:
				t.rotation = t.linear_velocity.angle()
			if t.extra.get("meteor", false) and randf() < 0.6:
				world.fx_event("burn", {"p": t.global_position})


static func _explode_at(world: World, t: Toy, r: float, power: float, dmg: float) -> void:
	var p := t.global_position
	t.extra.gone = true
	world.remove(t.uid, false)
	boom(world, p, r, power, false, dmg)


## A lit fuse runs out.
static func _go_off(world: World, t: Toy) -> void:
	var p := t.global_position
	if t.extra.get("gone", false):
		return
	if t.def.has("explode"):
		var ex: Dictionary = t.def.explode
		var r := float(ex.r)
		var power := float(ex.power)
		var dmg := float(ex.dmg)
		t.extra.gone = true
		world.remove(t.uid, false)
		match t.id:
			"cluster":
				boom(world, p, r, power, false, dmg)
				for i in 6:
					var g := world.spawn_toy("grenade", p + Vector2(randf_range(-10, 10), -12))
					if g:
						g.linear_velocity = Vector2(randf_range(-420, 420), randf_range(-620, -260))
						g.fuse = randf_range(0.5, 1.2)
			"napalm":
				boom(world, p, r * 0.6, power, false, dmg)
				world.fires.append({"p": p, "r": r, "t": 7.0})
				world.fx_event("napalm", {"p": p, "r": r})
			"acid_bomb":
				for f in world.fighters():
					if f.center().distance_to(p) < r:
						f.acid = 4.0
						f.hurt(dmg)
				for o in world.toys():
					if o.global_position.distance_to(p) < r * 0.7:
						o.extra.melt = 2.0
				world.fx_event("acid_splash", {"p": p, "r": r})
				world.push_away(p, r, power)
			"nuke":
				_nuke(world, p, r, power, dmg)
			_:
				boom(world, p, r, power, false, dmg)
		return
	match t.id:
		"firework":
			# launch phase: fly up with a sparkly trail, then burst
			if not t.extra.has("flying"):
				t.extra.flying = true
				t.fuse = 0.8
				t.gravity_scale = 0.0
				t.rotation = 0.0
				t.angular_velocity = 0.0
				t.linear_velocity = Vector2(randf_range(-50, 50), -720.0)
				world.fx_event("firework_launch", {"p": p, "uid": t.uid})
				return
			world.fx_event("firework_burst", {"p": p, "c": Catalog.PAINT[randi() % 8], "c2": Catalog.PAINT[randi() % 8]})
			if world.night:
				Settings.award("fireworks")
			_count_boom()
			world.remove(t.uid, false)
		"paint_bomb":
			var col: Color = Catalog.PAINT[randi() % 8]
			for o in world.things.values():
				if o != t and world._pos_of(o).distance_to(p) < 200.0:
					o.paint = col
			world.fx_event("paint_splat", {"p": p, "c": col, "r": 200.0})
			_count_boom()
			world.remove(t.uid, false)
		"bubble_bomb":
			for o in world.things.values():
				if o == t or world._pos_of(o).distance_to(p) > 210.0:
					continue
				if o is Toy and not o.freeze and o.parent_uid == 0:
					_bubble(world, o, 6.0)
				elif o is Wiggly:
					o.set_bubble(6.0)
			world.fx_event("bubble_burst", {"p": p, "r": 210.0})
			_count_boom()
			world.remove(t.uid, false)
		"glue_bomb":
			var near: Array = []
			for o in world.toys():
				if o != t and o.global_position.distance_to(p) < 160.0 and not o.freeze:
					near.append(o)
			for i in near.size():
				var a: Toy = near[i]
				var best: Toy = null
				var bd := 90.0
				for j in range(i + 1, near.size()):
					var b: Toy = near[j]
					var d := a.global_position.distance_to(b.global_position) - a.bound_radius() - b.bound_radius()
					if d < bd:
						bd = d
						best = b
				if best:
					world.add_link("glue", a, best, (a.global_position + best.global_position) * 0.5, (a.global_position + best.global_position) * 0.5)
			world.fx_event("glue_splat", {"p": p, "r": 160.0})
			_count_boom()
			world.remove(t.uid, false)
		"freeze_bomb":
			world.remove(t.uid, false)
			world.freeze_area(p, 200.0, 6.0)
			_count_boom()
		"boom_barrel":
			world.remove(t.uid, false)
			boom(world, p, 260.0, 1500.0, false)
		"mega_boom":
			world.remove(t.uid, false)
			boom(world, p, 560.0, 2600.0, true)


static func _nuke(world: World, p: Vector2, r: float, power: float, dmg: float) -> void:
	Combat.blast(world, p, r, power, dmg)
	for o in world.toys():
		if o.global_position.distance_to(p) < r * 0.5 and not o.nailed:
			o.extra.melt = 2.0
	world.fx_event("nuke", {"p": p, "r": r})
	world.booms += 1
	Settings.award("nuke")
	_count_boom()


static func boom(world: World, p: Vector2, rad: float, power: float, mega: bool, dmg := -1.0) -> void:
	if dmg < 0.0:
		dmg = 120.0 if mega else 55.0
	Combat.blast(world, p, rad, power, dmg)
	for o in world.toys():
		var d: float = o.global_position.distance_to(p)
		if d > rad:
			continue
		if o.def.has("breaks") and d < rad * 0.8:
			_shatter(world, o)
		elif o.id in FUSED and o.fuse < 0.0:
			light_fuse(world, o)
			o.fuse = minf(o.fuse, 0.18)
		elif o.id == "balloon":
			_pop_balloon(world, o)
	world.fx_event("mega_boom" if mega else "boom", {"p": p, "r": rad})
	world.booms += 1
	_count_boom()


static func _shatter(world: World, t: Toy) -> void:
	world.fx_event("shatter", {"p": t.global_position, "c": t.shown_color(), "glass": t.id == "glass_pane", "a": t.rotation, "w": t.w * t.size_scale, "h": t.h * t.size_scale})
	world.remove(t.uid, false)


## Called when a toy hits something.
static func impact(world: World, t: Toy, other, closing: float, at: Vector2) -> void:
	if t.puppet or t.extra.get("gone", false) or t.extra.has("held_by"):
		return
	if t.extra.has("proj"):
		var owner_uid := int(t.extra.get("owner", 0))
		var hit_f = other.fighter if other is FighterPart else null
		if hit_f != null and hit_f.uid == owner_uid:
			return
		match String(t.extra.proj):
			"rocket":
				_explode_at(world, t, 180.0, 1150.0, 55.0)
				return
			"bomb":
				if t.extra.get("meteor", false):
					_explode_at(world, t, 150.0, 900.0, 45.0)
				else:
					_explode_at(world, t, 200.0, 1300.0, 70.0)
				return
			"arrow":
				if hit_f != null and closing > 200.0:
					var team := String(t.extra.get("team", ""))
					if team == "" or hit_f.team != team or team == "wild":
						hit_f.hurt(30.0, t.linear_velocity.normalized() * 160.0, world.things.get(owner_uid))
					world.fx_event("arrow_hit", {"p": at})
					world.remove(t.uid, false)
					return
				if closing > 300.0 and not (other is Toy):
					t.extra.proj = "stuck"
					t.extra.life = 5.0
					t.nailed = true
					t.update_freeze()
					world.fx_event("arrow_hit", {"p": at})
					return
	if t.id == "landmine" and (other is FighterPart or (other is Toy and closing > 80.0) or other is JellyPoint):
		trigger(world, t)
		return
	if t.id in ["barrel", "dynamite", "nuke", "c4"] and closing > 900.0:
		trigger(world, t)
		return
	if t.bubble_t > 0.0 and closing > 200.0:
		_unbubble(world, t)
	if t.def.has("breaks") and closing > float(t.def.breaks):
		_shatter(world, t)
		return
	if t.id == "balloon" and closing > 700.0:
		_pop_balloon(world, t)
		return
	if t.id == "spring_pad" and other is RigidBody2D:
		var up := Vector2.UP.rotated(t.rotation)
		var rel: Vector2 = (other as Node2D).global_position - t.global_position
		if rel.dot(up) > 0.0:
			if other is JellyPoint:
				other.wiggly.add_velocity(up * 1150.0 - up * other.wiggly.com_vel.dot(up))
			elif not (other as RigidBody2D).freeze:
				var rb := other as RigidBody2D
				rb.linear_velocity += up * (1100.0 - rb.linear_velocity.dot(up))
			t.extra.art = str(randi())
			world.fx_event("boing", {"p": at, "big": true})
			return
	if t.id == "bell" and closing > 120.0:
		_ding(world, t)
	if closing > 180.0:
		var kind := "thud"
		if t.def.get("metal", false):
			kind = "clink"
		elif t.id in ["bouncy_ball", "beach_ball", "soccer_ball", "pillow"]:
			kind = "boing"
		elif t.id in ["glass_pane", "ice_cube", "marble"]:
			kind = "tink"
		world.fx_event(kind, {"p": at, "v": closing, "m": t.mass})


## Adds or removes the glow light for lamps, saucers and fireworks.
static func update_light(world: World, t: Toy) -> void:
	var want := false
	match t.id:
		"lamp":
			want = t.is_on()
		"saucer":
			want = true
		"firework":
			want = t.fuse >= 0.0
	var light: PointLight2D = t.get_node_or_null("Glow")
	if want and light == null:
		light = PointLight2D.new()
		light.name = "Glow"
		light.texture = Art.light_texture()
		light.texture_scale = 2.2 if t.id == "lamp" else 1.4
		light.color = Color(1.0, 0.9, 0.6) if t.id == "lamp" else Color(0.6, 1.0, 0.9)
		light.energy = 1.4 if world.night else 0.6
		light.blend_mode = Light2D.BLEND_MODE_ADD
		t.add_child(light)
	elif not want and light != null:
		light.queue_free()
	elif light:
		light.energy = 1.4 if world.night else 0.6

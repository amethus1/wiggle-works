class_name Combat
## Fighting rules: bullets, rockets, arrows and grenades, flamethrowers,
## blasts, lava, acid and fire, and noticing when a battle is won.

const MASK_ALL := 1 | 2 | 4 | 16
const PROJ := {
	"rocket": {"part": true, "name": "Rocket", "shape": "box", "w": 26, "h": 8, "mass": 0.6, "bounce": 0.0, "fric": 0.5, "color": Color("556b2f"), "metal": true},
	"arrow": {"part": true, "name": "Arrow", "shape": "box", "w": 36, "h": 3, "mass": 0.15, "bounce": 0.0, "fric": 0.8, "color": Color("8b5a2b")},
	"shell": {"part": true, "name": "Bomb", "shape": "circle", "r": 10, "mass": 2.0, "bounce": 0.0, "fric": 0.5, "color": Color("2d3436"), "metal": true},
	"meteor": {"part": true, "name": "Meteor", "shape": "circle", "r": 16, "mass": 5.0, "bounce": 0.0, "fric": 0.5, "color": Color("c0392b")},
}


static func bodies_of(f) -> Array:
	var out: Array = []
	if f is Fighter:
		for b in f.all_bodies():
			out.append(b.get_rid())
		if f.weapon_toy and is_instance_valid(f.weapon_toy):
			out.append(f.weapon_toy.get_rid())
	return out


## A hitscan shot. Passes through teammates; stops at the first other thing.
static func shoot(w: World, shooter, from: Vector2, ang: float, rng: float, dmg: float, knock: float, laser := false) -> void:
	var dir := Vector2.from_angle(ang)
	var to := from + dir * rng
	var exclude: Array = bodies_of(shooter)
	var space := w.get_world_2d().direct_space_state
	var end := to
	var start := from
	var bounced := false
	for i in 6:
		var q := PhysicsRayQueryParameters2D.create(start, to, MASK_ALL, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col = hit.collider
		end = hit.position
		if col is FighterPart and col.fighter != null and shooter is Fighter and not shooter.enemy_of(col.fighter) and col.fighter != shooter:
			exclude.append(col.get_rid())   # don't shoot your own team
			continue
		if col is FighterPart and col.fighter and not bounced and col.fighter.deflects(start):
			# PING! a laser sword bats it back the way it came (it can hit the shooter)
			w.fx_event("tracer", {"a": start, "b": end, "laser": laser})
			w.fx_event("deflect", {"p": end})
			bounced = true
			dir = (-dir).rotated(randf_range(-0.3, 0.3))
			start = end
			to = start + dir * rng * 0.7
			exclude = bodies_of(col.fighter)
			end = to
			continue
		if col is FighterPart and col.fighter:
			col.fighter.hurt(dmg, dir * knock, shooter)
			w.fx_event("bullet_hit", {"p": end, "flesh": true})
		elif col is Toy:
			if not col.freeze:
				col.apply_impulse(dir * knock * 0.6, end - col.global_position)
			if col.id in ["barrel", "landmine", "c4", "dynamite", "nuke"]:
				ToyLogic.trigger(w, col)
			elif col.def.has("breaks"):
				ToyLogic.impact(w, col, null, 9999.0, end)
			elif col.id == "balloon":
				ToyLogic.heat(w, col)
			w.fx_event("bullet_hit", {"p": end})
		elif col is JellyPoint:
			col.wiggly.add_velocity(dir * knock * 0.8)
			w.fx_event("bullet_hit", {"p": end})
		else:
			w.fx_event("bullet_hit", {"p": end, "ground": true})
		break
	w.fx_event("tracer", {"a": start, "b": end, "laser": laser})


## Fires a projectile: rocket, arrow or grenade.
static func launch(w: World, shooter, kind: String, at: Vector2, ang: float, speed: float) -> void:
	var t: Toy
	if kind == "grenade":
		t = w.spawn_toy("grenade", at)
		if t:
			t.fuse = 1.8
	else:
		t = w.spawn_toy(kind, at, ang, 1.0, PROJ[kind])
	if t == null:
		return
	t.rotation = ang
	t.linear_velocity = Vector2.from_angle(ang) * speed
	t.extra.proj = kind
	t.extra.owner = shooter.uid if shooter else 0
	t.extra.team = shooter.team if shooter is Fighter else ""
	t.extra.life = 6.0
	if kind == "rocket":
		t.gravity_scale = 0.08
	if shooter is Fighter:
		for b in shooter.all_bodies():
			t.add_collision_exception_with(b)
	t.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE


## Flamethrower puff: burns enemies in a cone and lights fuses.
static func flame(w: World, shooter, from: Vector2, ang: float, rng: float, dmg: float) -> void:
	var dir := Vector2.from_angle(ang)
	for f in w.fighters():
		if f == shooter or (shooter is Fighter and not shooter.enemy_of(f)):
			continue
		var d: Vector2 = f.center() - from
		if d.length() < rng and d.normalized().dot(dir) > 0.82:
			f.hurt(dmg, dir * 60.0, shooter)
			f.ignite(2.5)   # (a wet fighter just steams, and a frozen one melts)
	for t in w.toys():
		var d: Vector2 = t.global_position - from
		if d.length() < rng and d.normalized().dot(dir) > 0.82:
			ToyLogic.heat(w, t)
	if randf() < 0.6:
		w.fx_event("flame", {"p": from, "a": ang, "r": rng})


## An explosion: throws and hurts everything nearby.
static func blast(w: World, p: Vector2, rad: float, power: float, dmg: float) -> void:
	w.push_away(p, rad, power)
	w.damage_platforms(p, rad, dmg)   # (platforms you built crack, and break)
	for f in w.fighters():
		var d: Vector2 = f.center() - p
		var dist := d.length()
		if dist > rad:
			continue
		var k := pow(1.0 - dist / rad, 0.8)
		var dir := d / dist if dist > 1.0 else Vector2.UP
		dir = (dir + Vector2(0, -0.6)).normalized()
		f.hurt(dmg * k, dir * power * k * 1.1)
		if k > 0.5 and f.alive():
			f.ignite(1.0)
	for t in w.toys():
		if t.global_position.distance_to(p) < rad * 0.7 and t.id in ["barrel", "dynamite", "landmine", "c4", "grenade"] and t.fuse < 0.0:
			t.fuse = randf_range(0.08, 0.25)   # chain reaction


## Lava, acid and fire zones, every physics step.
static func hazards(w: World, dt: float) -> void:
	for f in w.fighters():
		if not f.alive():
			continue
		var kind := w.in_liquid(f.center() + Vector2(0, f.half_size().y * 0.6))
		match kind:
			"lava":
				if f.frozen_t > 0.0:
					f.thaw()
				f.hurt(70.0 * dt)
				f.burning = 3.0
				if randf() < dt * 6.0:
					w.fx_event("sizzle", {"p": f.center()})
			"acid":
				f.hurt(40.0 * dt)
				f.acid = 2.0
				if randf() < dt * 6.0:
					w.fx_event("fizz", {"p": f.center()})
			"water":
				if f.burning > 0.0:
					f.burning = 0.0
					w.fx_event("steam", {"p": f.center()})
				f.wet = 1.0
	for t in w.toys():
		if t.freeze:
			continue
		var kind := w.in_liquid(t.global_position)
		if kind == "lava" or kind == "acid":
			t.extra.melt = float(t.extra.get("melt", 0.0)) + dt
			if kind == "lava" and t.id in ["barrel", "dynamite", "grenade", "c4", "landmine", "nuke"] + ToyLogic.FUSED:
				ToyLogic.trigger(w, t)
			elif float(t.extra.melt) > 2.5:
				w.fx_event("sizzle" if kind == "lava" else "fizz", {"p": t.global_position, "big": true})
				w.remove(t.uid, false)
	for wg in w.wigglies():
		var kind := w.in_liquid(wg.com)
		if (kind == "lava" or kind == "acid") and wg.frozen_t <= 0.0:
			# Wigglies are tough: they hop right out
			wg.add_velocity(Vector2(randf_range(-150, 150), -900))
			wg.dizzy_t = 1.5
			w.fx_event("sizzle" if kind == "lava" else "fizz", {"p": wg.com})
	for z in w.fires:
		z.t -= dt
		for f in w.fighters():
			if f.alive() and f.burning < 1.0 and f.center().distance_to(z.p) < z.r:
				f.ignite(1.5, dt * 0.7)   # (a wet one steams for a second or so, drying off, then catches)
		if randf() < dt * 10.0:
			w.fx_event("burn", {"p": z.p + Vector2(randf_range(-z.r, z.r), randf_range(-12, 8))})
	w.fires = w.fires.filter(func(z): return z.t > 0.0)


## How many teams (not counting wild beasts) still have someone standing.
static func teams_standing(w: World) -> int:
	var teams := {}
	for f in w.fighters():
		if f.team != "wild" and f.alive():
			teams[f.team] = true
	return teams.size()


## Which teams still have someone standing? Announces the winner once.
static func battle_check(w: World) -> void:
	var teams := {}
	var total := {}
	for f in w.fighters():
		if f.team == "wild":
			continue
		total[f.team] = int(total.get(f.team, 0)) + 1
		if f.alive():
			teams[f.team] = true
	w.teams_up = teams.size()
	if total.size() >= 2 and teams.size() == 1:
		var winner: String = teams.keys()[0]
		if w.last_winner != winner:
			w.last_winner = winner
			w.fx_event("victory", {"team": winner})
			var big := true
			for k in total:
				if int(total[k]) < 5:
					big = false
			if big:
				Settings.award("general")
	elif teams.size() > 1:
		w.last_winner = ""

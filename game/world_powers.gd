class_name WorldPowers
## Wiggly powers, for World: popping a Wiggly in two and merging two back
## together, zaps (through ponds, along metal and from soldier to soldier),
## heat, ice, ground pounds, warps and pushes, and Wigglies bumping into
## fighters. Everything here takes the world; all the state stays in World.


static func split_wiggly(world: World, w: Wiggly, pid := -1) -> void:
	if w.size < 0.62:
		return
	var s: float = w.size * 0.74
	var c: Vector2 = w.com
	var g = world.grabs.get(pid)
	var pull_dir := Vector2.RIGHT
	if g != null:
		pull_dir = (Vector2(g.target) - c).normalized()
	var kind := w.kind
	var paint := w.paint
	var vel := w.com_vel
	world.remove(w.uid, false)
	var w1 := world.spawn_wiggly(kind, c - pull_dir * 18.0 * s, s)
	var w2 := world.spawn_wiggly(kind, c + pull_dir * 30.0 * s, s)
	for nw in [w1, w2]:
		if nw:
			nw.paint = paint
			nw.dizzy_t = 1.2
			nw.set_meta("popped_t", nw.t)
	if w1:
		w1.set_velocity(vel - pull_dir * 260.0)
	if w2:
		w2.set_velocity(vel + pull_dir * 260.0)
		# remove() let go of the old Wiggly, so keep hold of this half instead
		if pid >= 0 and g != null:
			WorldCommands.grab_start(world, pid, w2, Vector2(g.target))
	world.fx_event("split", {"p": c, "k": kind})
	Settings.award("pop")


## The two halves of a Wiggly that just popped: letting go of one right away
## mustn't stick them straight back together.
static func just_popped(a: Wiggly, b: Wiggly) -> bool:
	return a.t - float(a.get_meta("popped_t", -INF)) < 1.0 and b.t - float(b.get_meta("popped_t", -INF)) < 1.0


static func merge_wigglies(world: World, a: Wiggly, b: Wiggly) -> void:
	var s := minf(2.2, sqrt(a.size * a.size + b.size * b.size))
	var c := (a.com * a.size + b.com * b.size) / (a.size + b.size)
	var kind := a.kind
	var paint := a.paint
	world.remove(a.uid, false)
	world.remove(b.uid, false)
	var w := world.spawn_wiggly(kind, c + Vector2(0, -10), s)
	if w:
		w.paint = paint
		w.party_t = 1.5
	world.fx_event("merge", {"p": c, "k": kind})


static func resize_wiggly(world: World, w: Wiggly, s: float) -> void:
	var c := w.com
	var kind := w.kind
	var paint := w.paint
	var pid := w.player_id
	world.remove(w.uid, false)
	var nw := world.spawn_wiggly(kind, c, s)
	if nw:
		nw.paint = paint
		nw.player_id = pid


static func zap_area(world: World, c: Vector2, rad: float, from: Wiggly) -> void:
	var hits: Array = []
	var zapped: Array = []
	var metal: Array = []
	for t in world.all_things():
		if t == from:
			continue
		var p := world._pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy:
			t.zap_power = 3.0
			t.electric = 1.0
			hits.append(p)
			if t.def.get("metal", false):
				metal.append(t)
		elif t is Wiggly:
			t.electric = 1.2
			hits.append(p)
		elif t is Fighter and t.alive() and t.frozen_t <= 0.0:
			zapped.append(t)
			hits.append(p)
	world.fx_event("zap", {"p": c, "hits": hits, "r": rad})
	_zap_water(world, c, rad, from, zapped)
	_zap_metal(world, metal, zapped)
	if not zapped.is_empty():
		_zap_chain(world, zapped)


## A zap that reaches a pond runs through all of it: everyone and everything
## in the water gets it (up to the knees counts).
static func _zap_water(world: World, c: Vector2, rad: float, from, zapped: Array) -> void:
	for i in world.water.size():
		if i < world.liquid_kinds.size() and String(world.liquid_kinds[i]) != "water":
			continue
		var r: Rect2 = world.water[i]
		var near := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if near.distance_to(c) > rad:
			continue
		var pool := r.grow_individual(0.0, 50.0, 0.0, 0.0)
		for t in world.all_things():
			if t == from or not pool.has_point(world._pos_of(t)):
				continue
			if t is Fighter:
				if t.alive() and t.frozen_t <= 0.0 and not zapped.has(t):
					t.wet = maxf(t.wet, 1.0)
					zapped.append(t)
			elif t is Wiggly:
				t.electric = 1.2
			elif t is Toy:
				t.zap_power = 3.0
				t.electric = 1.0
		world.fx_event("zap_pool", {"p": near, "x0": r.position.x, "x1": r.end.x, "y": r.position.y})


## ...and along metal: from the metal toys it hit to every metal toy touching
## them (a row of beams, a machine standing on one), and into anyone touching
## any of it (standing on a metal beam, leaning on a barrel).
static func _zap_metal(world: World, start: Array, zapped: Array) -> void:
	if start.is_empty():
		return
	if world._metal_q == null:
		world._metal_q = PhysicsShapeQueryParameters2D.new()
		world._metal_q.collision_mask = Toy.LAYER_TOYS | Fighter.LAYER
		world._metal_q.margin = 4.0
	var space := world.get_world_2d().direct_space_state
	var seen := {}
	for t in start:
		seen[t] = true
	var queue: Array = start.duplicate()
	var pairs: Array = []
	var i := 0
	while i < queue.size() and i < 40:
		var t: Toy = queue[i]
		i += 1
		if not is_instance_valid(t):
			continue
		var cs: CollisionShape2D = null
		for k in t.get_children():
			if k is CollisionShape2D and not k.is_queued_for_deletion():
				cs = k
				break
		if cs == null or cs.shape == null:
			continue
		world._metal_q.shape = cs.shape
		world._metal_q.transform = t.global_transform * cs.transform
		world._metal_q.exclude = [t.get_rid()]
		for hit in space.intersect_shape(world._metal_q, 12):
			var o = hit.collider
			if o is Toy and o.def.get("metal", false) and not seen.has(o) and world.things.get(o.uid) == o:
				seen[o] = true
				o.electric = 1.0
				o.zap_power = 3.0
				queue.append(o)
				pairs.append([t.global_position, o.global_position])
			elif o is FighterPart and o.fighter and o.fighter.alive() and o.fighter.frozen_t <= 0.0 and not zapped.has(o.fighter):
				zapped.append(o.fighter)
				pairs.append([t.global_position, o.fighter.center()])
	if not pairs.is_empty():
		world.fx_event("zap_metal", {"p": pairs[0][0], "pairs": pairs})


## Twinkle's warp takes the fighters close by along: each one pops out high in
## the air above where it stood, and comes tumbling down (softly).
static func warp_fighters(world: World, c: Vector2, rad: float) -> void:
	var up := -world.gravity_dir() if world.gravity_dir() != Vector2.ZERO else Vector2.UP
	var n := 0
	for f in world.fighters():
		if n >= 4:
			break
		if not f.alive() or f.frozen_t > 0.0 or f.center().distance_to(c) > rad + f.radius() * 0.5:
			continue
		var at: Vector2 = f.center()
		var to := world.lift_out_of_ground(at + up * randf_range(300.0, 400.0) + Vector2(randf_range(-60.0, 60.0), 0.0), f.radius() * 0.5)
		f.warp_to(to)
		world.fx_event("warp", {"a": at, "b": to, "r": f.radius()})
		n += 1


## Zappy's zap jumps on from soldier to soldier, further through wet ones
## (a whole pond of them) and ones in metal armor. Up to 12 in all.
static func _zap_chain(world: World, first: Array) -> void:
	var hit := {}
	for f in first:
		hit[f] = true
	var others: Array = world.fighters().filter(func(o): return o.alive() and o.frozen_t <= 0.0 and not hit.has(o))
	var queue: Array = first.duplicate()
	var pairs: Array = []
	var i := 0
	while i < queue.size() and hit.size() < 12:
		var a: Fighter = queue[i]
		i += 1
		var ac := a.center()
		var reach := 70.0 + a.radius() * 0.5 + (110.0 if a.wet > 0.2 else 0.0) + 30.0 * minf(2.0, a.metal())
		for o in others:
			if hit.has(o):
				continue
			var oc: Vector2 = o.center()
			var r2 := reach + (60.0 if o.wet > 0.2 and a.wet > 0.2 else 0.0) + 20.0 * minf(2.0, o.metal())
			if ac.distance_to(oc) < r2:
				hit[o] = true
				queue.append(o)
				pairs.append([ac, oc])
				if hit.size() >= 12:
					break
	for f in hit:
		f.zap()
	if not pairs.is_empty():
		world.fx_event("zap_chain", {"p": pairs[0][0], "pairs": pairs})


static func heat_area(world: World, c: Vector2, rad: float, from: Wiggly) -> void:
	for t in world.all_things():
		if t == from:
			continue
		var p := world._pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy:
			if t.frozen_t > 0.0:
				t.frozen_t = 0.01
			ToyLogic.heat(world, t)
		elif t is Wiggly and t.frozen_t > 0.0:
			t.set_frozen(0.0)
		elif t is Fighter:
			t.ignite(3.0)   # (melts the ice instead if it's frozen)
	world.fx_event("heat", {"p": c, "r": rad})


static func freeze_area(world: World, c: Vector2, rad: float, sec: float, from = null) -> void:
	var mid_air := false
	for t in world.all_things():
		if t == from:
			continue
		var p := world._pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy and not t.nailed:
			if t.get_contact_count() == 0 and t.linear_velocity.length() > 60.0:
				mid_air = true
			t.frozen_t = sec
			t.update_freeze()
		elif t is Wiggly:
			if not t.grounded:
				mid_air = true
			t.set_frozen(sec)
		elif t is Fighter and t.alive():
			if t.state == "stand" and not t.grounded and not t.def.get("flies", false):
				mid_air = true
			t.set_frozen(sec)
	if mid_air:
		Settings.award("freeze")
	world.fx_event("freeze", {"p": c, "r": rad})


static func ground_pound(world: World, c: Vector2, rad: float, from: Wiggly) -> void:
	push_away(world, c, rad, 950.0, from)
	# squads standing nearby get launched (a T-Rex only wobbles unless it's right there)
	var power := 1000.0 * sqrt(from.size) if from else 1000.0
	var up := -world.gravity_dir() if world.gravity_dir() != Vector2.ZERO else Vector2.UP
	for f in world.fighters():
		var d: Vector2 = f.center() - c
		var dist := d.length()
		if dist > rad + f.radius() * 0.5:
			continue
		var k := pow(clampf(1.0 - dist / (rad + f.radius() * 0.5), 0.0, 1.0), 0.7)
		var dir := ((d / dist if dist > 1.0 else up) + up * 0.9).normalized()
		f.shove(dir * power * k / sqrt(f._mass_k()), 8.0 * k)
	world.fx_event("pound", {"p": c, "r": rad})


## Throws everything near `c` outward (heavier things move less).
static func push_away(world: World, c: Vector2, rad: float, power: float, skip = null) -> void:
	var up := -world.gravity_dir() if world.gravity_dir() != Vector2.ZERO else Vector2.UP
	for t in world.all_things():
		if t == skip:
			continue
		var p := world._pos_of(t)
		var d := p - c
		var dist := d.length()
		if dist > rad:
			continue
		var f := pow(1.0 - dist / rad, 0.7)
		var dir := d / dist if dist > 1.0 else up
		var dv := dir * power * f + up * power * 0.3 * f
		if t is Toy and not t.freeze:
			t.linear_velocity += dv * clampf(3.0 / t.mass, 0.12, 1.4)
			t.angular_velocity += randf_range(-6, 6) * f
		elif t is Wiggly and t.frozen_t <= 0.0:
			t.add_velocity(dv)
			if f > 0.5:
				t.dizzy_t = 2.0


## Wigglies don't push standing fighters around (a squishy jelly on a soldier's
## head would bounce them about), but a big or fast one rolling into them
## bowls them over, and a sticky Gummy grabs on. One shape check per Wiggly
## that's moving fast enough (or sticky), so even a big army costs little.
static func wigglies_vs_fighters(world: World) -> void:
	for w in world.wiggly_layer.get_children():
		if not (w is Wiggly) or world.things.get(w.uid) != w or w.points.is_empty() or w.frozen_t > 0.0:
			continue
		var sticky: bool = w.kind == "gummy" and w.special_t > 0.0 and w.stuck_links < 3
		var bouncy: bool = w.kind == "bloop"   # (a living trampoline: see _trampoline)
		var m: float = float(w.def.mass) * Wiggly.N * w.size * w.size
		var spd: float = w.com_vel.length()
		if not sticky and not bouncy and spd * m / (m + 1.0) < 120.0:
			continue   # too small or slow to bump anybody
		if world._jelly_q == null:
			world._jelly_q = PhysicsShapeQueryParameters2D.new()
			world._jelly_q.shape = CircleShape2D.new()
			world._jelly_q.collision_mask = Fighter.LAYER
		(world._jelly_q.shape as CircleShape2D).radius = w.radius() * 0.95 + 4.0
		world._jelly_q.transform = Transform2D(0.0, w.com)
		for hit in world.get_world_2d().direct_space_state.intersect_shape(world._jelly_q, 8):
			var b = hit.collider
			if not (b is FighterPart) or b.part != "body" or b.fighter == null:
				continue
			var f: Fighter = b.fighter
			var d: Vector2 = f.center() - w.com
			if bouncy and _trampoline(world, w, f, b, d):
				continue
			if not sticky and spd * m / (m + 1.0) < 120.0:
				continue   # (a slow Bloop just being a trampoline)
			var dir := d.normalized() if d.length() > 1.0 else Vector2(signf(w.com_vel.x), 0)
			if sticky:
				var jp: JellyPoint = w.points[w.nearest_point(f.center())]
				if not world.links.any(func(l): return l.a == jp and l.b == b):
					sticky_touch(world, w, jp, b, jp.global_position)
			var rel: float = (w.com_vel - (b as RigidBody2D).linear_velocity).dot(dir)
			if rel > 60.0:
				f.jelly_bump(w, rel, dir)


## Someone coming down on top of a Bloop: BOING! It throws them up high (a
## living trampoline) and squashes down under them. True if it did.
static func _trampoline(world: World, w: Wiggly, f: Fighter, b, d: Vector2) -> bool:
	var up := -world.gravity_dir() if world.gravity_dir() != Vector2.ZERO else Vector2.UP
	# (only landing on top: feet above its middle, not standing beside it)
	var feet := d - up * f.half_size().y
	if feet.dot(up) < w.radius() * 0.25 or absf(feet.dot(up.orthogonal())) > w.radius() * 0.8:
		return false
	var v: Vector2 = (b as RigidBody2D).linear_velocity
	var falling := -(v - w.com_vel).dot(up)
	if falling < 140.0 or not f.bounce(up * clampf(falling * 1.1 + 420.0, 650.0, 1300.0)):
		return false
	w.add_velocity(-up * minf(falling, 600.0) * 0.45)
	world.fx_event("boing", {"p": w.com + up * w.radius(), "big": true})
	return true


static func sticky_touch(world: World, w: Wiggly, p: JellyPoint, other, at: Vector2) -> void:
	if w.stuck_links >= 3 or not (other is PhysicsBody2D):
		return
	if other is JellyPoint and other.wiggly == w:
		return
	for l in world.links:
		if (l.a == p and l.b == other) or (l.a == other and l.b == p):
			return
	if other is StaticBody2D:
		return
	var l := WorldLinks.add_link(world, "glue", p, other, p.global_position, at)
	if l:
		w.stuck_links += 1
		world.fx_event("glue", {"p": at})
		if other is FighterPart and other.fighter:
			other.fighter.stick(3.0)   # and it stays slow while Gummy hangs on (see WorldLinks.step)
